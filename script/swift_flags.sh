# Swift settings matching the Tastko app target, for scripts that compile app sources
# directly with swiftc. Keep in sync with the project's build settings.
TASTKO_SWIFT_FLAGS=(
    -swift-version 6
    -default-isolation MainActor
    -enable-upcoming-feature NonisolatedNonsendingByDefault
    -enable-upcoming-feature InferIsolatedConformances
    -enable-upcoming-feature MemberImportVisibility
)
