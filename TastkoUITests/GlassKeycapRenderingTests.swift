import AppKit
import XCTest

// MARK: - Glass Keycap Rendering
final class GlassKeycapRenderingTests: XCTestCase {
    // MARK: - Nonactivating Keyboard
    @MainActor
    func testGlassKeepsLettersSymbolsAndProfileColors() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try installProfile(in: home)
        defer { try? FileManager.default.removeItem(at: home) }

        let app = XCUIApplication()
        app.launchEnvironment["CFFIXED_USER_HOME"] = home.path
        app.launchArguments += [
            "-keycapStyle", "glass", "-keyboardAppearance", "dark",
            "-keyboardTheme", "graphite", "-pointerAutoHideEnabled", "NO",
            "-experimentalLockScreenDisplay", "NO",
        ]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.menuButtons["Glass Regression"].waitForExistence(timeout: 5))

        for title in ["A", "⌘"] {
            let key = app.buttons[title]
            XCTAssertTrue(key.waitForExistence(timeout: 5))
            let screenshot = key.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "Glass key \(title)"
            attachment.lifetime = .keepAlways
            add(attachment)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: screenshot.pngRepresentation))
            var labelPixels = 0
            var tintedPixels = 0
            var sampledPixels = 0
            // Exclude the glass rim so highlights cannot stand in for a visible label.
            for y in (bitmap.pixelsHigh / 4)..<(bitmap.pixelsHigh * 3 / 4) {
                for x in (bitmap.pixelsWide / 4)..<(bitmap.pixelsWide * 3 / 4) {
                    let pixel = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    if min(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) > 0.8 {
                        labelPixels += 1
                    }
                    if pixel.redComponent > 0.4,
                        pixel.redComponent > pixel.greenComponent * 1.8,
                        pixel.redComponent > pixel.blueComponent * 1.8
                    {
                        tintedPixels += 1
                    }
                    sampledPixels += 1
                }
            }
            XCTAssertGreaterThan(labelPixels, sampledPixels / 50, "Missing white label: \(title)")
            XCTAssertGreaterThan(tintedPixels, sampledPixels / 4, "Missing red tint: \(title)")
        }
    }

    // MARK: - Temporary Panel Editor Profile
    private func installProfile(in home: URL) throws {
        let contents = home.appending(
            path: "Library/Application Support/com.apple.AssistiveControl/Glass.ascconfig/Contents"
        )
        let resources = contents.appending(path: "Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info = [
            "ASCConfigurationIdentifier": "glass-regression",
            "ASCConfigurationDisplayName": "Glass Regression",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appending(path: "Info.plist"))
        let buttons: [[String: Any]] = ["A", "⌘"].enumerated().map { index, title in
            [
                "ID": title, "PanelObjectType": "Button",
                "Rect": "{{\(index * 82), 0}, {80, 80}}",
                "DisplayText": title, "FontSize": 36,
                "DisplayColor": "0.900 0.100 0.100 1.000",
                "FontColor": "1.000 1.000 1.000 1.000",
            ]
        }
        let definitions: [String: Any] = [
            "Panels": [
                "GLASS": [
                    "Name": "Glass Regression", "Rect": "{{0, 0}, {162, 80}}",
                    "ShowPanelLocationString": "DefaultHomePanel", "PanelObjects": buttons,
                ]
            ]
        ]
        try PropertyListSerialization.data(fromPropertyList: definitions, format: .xml, options: 0)
            .write(to: resources.appending(path: "PanelDefinitions.plist"))
    }
}
