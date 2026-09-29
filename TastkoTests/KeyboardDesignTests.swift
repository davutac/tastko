import AppKit
import SwiftUI
import Testing

@testable import Tastko

// MARK: - KeyboardDesignTests
struct KeyboardDesignTests {
    // MARK: - Flat Profile Colors
    @Test @MainActor func importedColorsPreserveComponentsAndUseFallbackOnlyWhenMissing() throws {
        let components = PanelEditorColorComponents(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.75)
        let color = try #require(KeyboardPalette.imported(components))
        let nativeColor = try #require(NSColor(color).usingColorSpace(.sRGB))

        #expect(abs(nativeColor.redComponent - components.red) < 0.001)
        #expect(abs(nativeColor.greenComponent - components.green) < 0.001)
        #expect(abs(nativeColor.blueComponent - components.blue) < 0.001)
        #expect(abs(nativeColor.alphaComponent - components.alpha) < 0.001)
        #expect(KeyboardPalette.imported(nil) == nil)
    }

    @Test(arguments: [false, true]) @MainActor
    func keySurfaceKeepsUniformProfileFillWhenActive(isActive: Bool) throws {
        let components = PanelEditorColorComponents(red: 0.12, green: 0.52, blue: 0.9, alpha: 1)
        let renderer = ImageRenderer(
            content:
                KeycapSurface(
                    shape: Rectangle(),
                    fill: KeyboardPalette.imported(components),
                    isActive: isActive
                ) {
                    Color.clear
                }
                .frame(width: 60, height: 60)
        )
        let image = try #require(renderer.nsImage)
        let imageData = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: imageData))
        let swatchRenderer = ImageRenderer(
            content: Color(.sRGB, red: 0.12, green: 0.52, blue: 0.9)
                .frame(width: 60, height: 60)
        )
        let swatchImage = try #require(swatchRenderer.nsImage)
        let swatchData = try #require(swatchImage.tiffRepresentation)
        let swatch = try #require(NSBitmapImageRep(data: swatchData))
        let expected = try #require(swatch.colorAt(x: 30, y: 30)?.usingColorSpace(.sRGB))

        for y in [10, 30, 50] {
            let pixel = try #require(bitmap.colorAt(x: 30, y: y)?.usingColorSpace(.sRGB))
            #expect(abs(pixel.redComponent - expected.redComponent) < 0.001)
            #expect(abs(pixel.greenComponent - expected.greenComponent) < 0.001)
            #expect(abs(pixel.blueComponent - expected.blueComponent) < 0.001)
        }
    }

    // MARK: - Adaptive Colors
    @Test @MainActor func keyColorsAdaptToAppearanceAndKeepReadableContrast() throws {
        var backgrounds: [CGFloat] = []
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try #require(NSAppearance(named: name))
            var label: NSColor?
            var background: NSColor?
            appearance.performAsCurrentDrawingAppearance {
                label = NSColor(named: "KeyboardLabel")?.usingColorSpace(.sRGB)
                background = NSColor(named: "KeyboardKeyFill")?.usingColorSpace(.sRGB)
            }
            let labelLuminance = luminance(try #require(label))
            let backgroundLuminance = luminance(try #require(background))
            let contrast =
                (max(labelLuminance, backgroundLuminance) + 0.05)
                / (min(labelLuminance, backgroundLuminance) + 0.05)
            #expect(contrast >= 4.5)
            backgrounds.append(backgroundLuminance)
        }
        #expect(backgrounds[0] > backgrounds[1])
    }

    // MARK: - Return Key Geometry
    @Test func roundedReturnKeyPreservesTheNotchAndBounds() {
        let bounds = CGRect(x: 10, y: 20, width: 46, height: 77)
        let path = PanelEditorKeyShape(buttonShape: .isoReturn, cornerRadius: 6).path(in: bounds)

        #expect(path.boundingRect == bounds)
        #expect(path.contains(CGPoint(x: 14, y: 40)))
        #expect(!path.contains(CGPoint(x: 14, y: 80)))
        #expect(path.contains(CGPoint(x: 30, y: 80)))
        #expect(!path.contains(CGPoint(x: 10.1, y: 20.1)))
    }

    @Test func returnKeyNotchKeepsTheKeyGapWhenInset() {
        let frame = CGRect(x: 0, y: 0, width: 46, height: 77)
        let inset: CGFloat = 2
        let path = PanelEditorKeyShape(buttonShape: .isoReturn, frameInset: inset)
            .path(in: frame.insetBy(dx: inset, dy: inset))

        // The neighbouring key ends at x 8 and the row above ends at y 37; both notch edges
        // sit one inset past Panel Editor's 2-point gap, like every other key edge.
        #expect(!path.contains(CGPoint(x: 11.5, y: 60)))
        #expect(path.contains(CGPoint(x: 12.5, y: 60)))
        #expect(path.contains(CGPoint(x: 6, y: 34.5)))
        #expect(!path.contains(CGPoint(x: 6, y: 35.5)))
    }

    // MARK: - Keycap Shape
    @Test func pillCornersBecomeACapsule() {
        let rect = CGRect(x: 0, y: 0, width: 80, height: 30)
        let path = KeycapShape(cornerRadius: KeycapCorners.pill.radius).path(in: rect)

        #expect(path.boundingRect == rect)
        #expect(path.contains(CGPoint(x: 40, y: 15)))
        #expect(!path.contains(CGPoint(x: 2, y: 2)))
    }

    // MARK: - Themes
    @Test func unknownThemeFallsBackToTastko() {
        #expect(KeyboardTheme.named("missing").id == KeyboardTheme.tastko.id)
        #expect(Set(KeyboardTheme.all.map(\.id)).count == KeyboardTheme.all.count)
    }

    @Test(arguments: KeyboardTheme.all.filter { $0.id != KeyboardTheme.tastko.id })
    @MainActor func themeLabelsStayReadableOnKeys(theme: KeyboardTheme) throws {
        for palette in [theme.light, theme.dark].compactMap(\.self) {
            let label = try #require(NSColor(palette.label).usingColorSpace(.sRGB))
            let key = try #require(NSColor(palette.keyFill).usingColorSpace(.sRGB))
            let labelLuminance = luminance(label)
            let keyLuminance = luminance(key)
            let contrast =
                (max(labelLuminance, keyLuminance) + 0.05)
                / (min(labelLuminance, keyLuminance) + 0.05)
            #expect(contrast >= 4.5, "\(theme.name) \(palette.colorScheme) contrast \(contrast)")
        }
    }

    // MARK: - Contrast
    private func luminance(_ color: NSColor) -> CGFloat {
        let components = [color.redComponent, color.greenComponent, color.blueComponent].map {
            $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
        }
        return components[0] * 0.2126 + components[1] * 0.7152 + components[2] * 0.0722
    }
}
