import Foundation
import SwiftData

// MARK: - App Schema V1
enum AppSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [AISettings.self, AIProviderConfiguration.self, AIModelCatalogCache.self]
    }

    // MARK: - AI Settings
    @Model final class AISettings {
        @Attribute(.unique) var key: String
        var activeProvider: String?

        // MARK: - Initialization
        init() { key = "ai" }
    }

    // MARK: - Provider Configuration
    @Model final class AIProviderConfiguration {
        @Attribute(.unique) var providerID: String
        var executableOverride: String
        var modelID: String?
        var optionID: String?

        // MARK: - Initialization
        init(providerID: String) {
            self.providerID = providerID
            executableOverride = ""
        }
    }

    // MARK: - Catalog Cache
    @Model final class AIModelCatalogCache {
        @Attribute(.unique) var providerID: String
        var modelsJSON: Data
        var cliVersion: String
        var source: String
        var refreshedAt: Date

        // MARK: - Initialization
        init(
            providerID: String,
            modelsJSON: Data,
            cliVersion: String,
            source: String,
            refreshedAt: Date
        ) {
            self.providerID = providerID
            self.modelsJSON = modelsJSON
            self.cliVersion = cliVersion
            self.source = source
            self.refreshedAt = refreshedAt
        }
    }
}

typealias AISettings = AppSchemaV1.AISettings
typealias AIProviderConfiguration = AppSchemaV1.AIProviderConfiguration
typealias AIModelCatalogCache = AppSchemaV1.AIModelCatalogCache
