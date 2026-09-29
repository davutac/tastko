import SwiftUI

// MARK: - AI Provider Settings
struct AIProviderSettingsView: View {
    let service: AIProviderService

    // MARK: - Body
    var body: some View {
        Form {
            SettingsPaneHeader(pane: .ai)

            if let error = service.persistence.error ?? service.storageError {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button("Retry") { service.start() }
                }
            }
            Group {
                Section {
                    Picker(
                        "Active provider",
                        selection: Binding(
                            get: { service.activeProvider },
                            set: { service.selectProvider($0) }
                        )
                    ) {
                        Text("Off").tag(nil as AIProviderID?)
                        ForEach(service.availableProviders) { provider in
                            Text(provider.name).tag(Optional(provider))
                        }
                    }
                    .accessibilityIdentifier("ai.active-provider")
                }
                ForEach(service.availableProviders) { provider in
                    AIProviderSettingsRow(service: service, provider: provider)
                }
                SentencePromptSettingsView()
            }
            .disabled(service.persistence.container == nil)
        }
        .formStyle(.grouped)
        .pickerStyle(.menu)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await service.refreshProviders() }
                }
                .disabled(service.persistence.container == nil)
            }
        }
        .task {
            if service.persistence.container == nil { service.start() }
            await service.refreshProvidersWhileVisible()
        }
    }
}
