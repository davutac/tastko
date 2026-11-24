import Foundation
import SwiftData
import Testing

@testable import Tastko

// MARK: - Provider Service Tests
@MainActor struct AIProviderServiceTests {
    // MARK: - Fixture
    private func fixture(_ adapter: AIFixtureAdapter) throws -> AIProviderService {
        let persistence = AppPersistence(inMemory: true)
        persistence.open()
        let context = try #require(persistence.container?.mainContext)
        for provider in AIProviderID.allCases {
            let configuration = AIProviderConfiguration(providerID: provider.rawValue)
            configuration.modelID = "fixture"
            context.insert(configuration)
        }
        try context.save()
        let service = AIProviderService(
            persistence: persistence,
            adapters: Dictionary(uniqueKeysWithValues: AIProviderID.allCases.map { ($0, adapter) })
        )
        service.start()
        return service
    }

    // MARK: - Refresh Failure and Cache
    @Test func failedRefreshKeepsCatalogAndSavedMissingModel() async throws {
        let adapter = AIFixtureAdapter()
        let service = try fixture(adapter)
        await service.refreshProvider(.apple)
        #expect(service.statuses[.apple]?.models.count == 2)
        #expect(service.selections[.apple]?.modelID == "fixture")
        var selection = try #require(service.selections[.apple])
        selection.modelID = "removed-model"
        service.updateSelection(selection)
        await adapter.configure(fail: true)
        await service.refreshProvider(.apple)
        #expect(service.statuses[.apple]?.models.count == 2)
        #expect(service.statuses[.apple]?.isCached == true)
        #expect(service.selections[.apple]?.modelID == "removed-model")
        service.selectProvider(.apple)
        await #expect(throws: AIProviderError.unavailableSelection) {
            try await service.generate(AIGenerationRequest(prompt: "test"))
        }
        let context = try #require(service.persistence.container?.mainContext)
        #expect(try context.fetchCount(FetchDescriptor<AIModelCatalogCache>()) == 1)
        let reopened = AIProviderService(persistence: service.persistence)
        reopened.start()
        #expect(reopened.statuses[.apple]?.isCached == true)
    }

    // MARK: - Settings Refresh Lifecycle
    @Test func settingsRefreshRepeatsAndStopsOnCancellation() async throws {
        let adapter = AIFixtureAdapter()
        let service = try fixture(adapter)
        let task = Task { await service.refreshProvidersWhileVisible(interval: .milliseconds(30)) }
        defer { task.cancel() }
        // Parallel main-actor suites can hold off the refresh loop for seconds, so the deadline
        // only catches a loop that stalls; it returns as soon as two rounds have run.
        try await withAIDeadline(seconds: 10) {
            while await adapter.discoveryCount < AIProviderID.allCases.count * 2 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        task.cancel()
        await task.value
        let count = await adapter.discoveryCount
        try await Task.sleep(for: .milliseconds(100))
        #expect(await adapter.discoveryCount == count)
        #expect(service.activeProvider == nil)
        await service.shutdown()
    }

    // MARK: - Native Provider Routing
    @Test func nativeProviderGeneratesText() async throws {
        let adapter = AIFixtureAdapter()
        let service = try fixture(adapter)
        var selection = try #require(service.selections[.apple])
        selection.modelID = "fixture"
        service.updateSelection(selection)
        await service.refreshProvider(.apple)
        #expect(service.statuses[.apple]?.error == nil)
        service.selectProvider(.apple)
        let result = try await service.generate(AIGenerationRequest(prompt: "test"))
        #expect(result.selection.provider == .apple)
        #expect(result.text == " output ")
        await service.shutdown()
    }

    // MARK: - Independent Selection
    @Test func activationAndModelChangesPreserveOptions() async throws {
        let service = try fixture(AIFixtureAdapter())
        await service.refreshProviders()
        await #expect(throws: AIProviderError.noActiveProvider) {
            try await service.generate(AIGenerationRequest(prompt: "test"))
        }
        var selection = try #require(service.selections[.apple])
        selection.optionID = "low"
        service.updateSelection(selection)
        service.selectProvider(.apple)
        #expect(service.activeProvider == .apple)
        #expect(service.selections[.apple]?.optionID == "low")
        selection.modelID = "no-options"
        service.updateSelection(selection)
        #expect(service.selections[.apple]?.optionID == nil)
        #expect(service.selections[.apple]?.modelID == "no-options")
        service.selectProvider(nil)
        #expect(service.activeProvider == nil)
    }

    // MARK: - Generation Snapshot
    @Test func requestKeepsItsSelectionWhileSettingsChange() async throws {
        let adapter = AIFixtureAdapter()
        await adapter.configure(delay: true)
        let service = try fixture(adapter)
        await service.refreshProviders()
        service.selectProvider(.apple)
        let task = Task { try await service.generate(AIGenerationRequest(prompt: "test")) }
        try await Task.sleep(for: .milliseconds(50))
        service.selectProvider(nil)
        let result = try await task.value
        #expect(result.selection.provider == .apple)
        #expect(result.text == " output ")
        #expect(service.activeProvider == nil)
    }
}
