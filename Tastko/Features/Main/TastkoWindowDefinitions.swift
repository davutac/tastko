import CoreGraphics
import SwiftUI

// MARK: - Tastko Window IDs
extension FloatingWindowID {
    static let main = FloatingWindowID("main")
    static let keyboardDebug = FloatingWindowID("keyboardDebug")
}

// MARK: - Tastko Window Configurations
extension AlwaysOnTopWindowConfiguration {
    static var keyboardDebugWindow: AlwaysOnTopWindowConfiguration {
        AlwaysOnTopWindowConfiguration(
            size: CGSize(width: 430, height: 390),
            minSize: CGSize(width: 360, height: 300),
            allowsResizing: false,
            maintainsContentAspectRatio: false,
            storageKey: "keyboardDebug"
        )
    }
}

// MARK: - Keyboard Companion Window
extension ChildWindowID {
    static let keyboardCompanion = ChildWindowID("keyboardCompanion")
}

extension ChildWindowConfiguration {
    static var keyboardCompanion: Self {
        Self(
            title: "Keyboard companion",
            alignment: .start,
            size: .parentWidth(),
            gap: 8,
            style: ChildWindowStyle(
                background: AnyShapeStyle(Color.clear),
                cornerRadius: 0,
                borderWidth: 0,
                contentInsets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
                hasShadow: false
            ),
            passesThroughEmptyArea: true
        )
    }
}
