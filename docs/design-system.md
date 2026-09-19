# Keyboard design system

The keyboard uses rounded, flat keycaps on a neutral chassis. Keys, predictions, and window chrome share the same palette and typography. Imported layouts still determine key placement and actions.

## Where to make changes

| Concern | Source |
| --- | --- |
| Light and dark colors | `Tastko/Assets.xcassets/Keyboard*.colorset` |
| Semantic palette, dimensions and fonts | `Tastko/DesignSystem/KeyboardDesign.swift` |
| Solid key fill, border, hover, press, and active states | `Tastko/DesignSystem/KeycapSurface.swift` |
| Imported key labels, sizing, and active indicator | `Tastko/Components/Keyboard/PanelEditorKeycap.swift` |
| SwiftUI keycap buttons | `Tastko/DesignSystem/KeycapButtonStyle.swift` |
| Light and dark component previews | `Tastko/DesignSystem/KeyboardDesignPreview.swift` |

Use `KeyboardDesign.Palette` in keyboard views. Default colors have an Any Appearance value for light mode and a Dark value in the asset catalog. Imported `DisplayColor` fills the entire key surface, and `FontColor` colors both primary and secondary labels, preserving their sRGB components and alpha in either appearance. Missing profile colors use the adaptive defaults. SwiftUI follows the system appearance; the app does not force a color scheme. Adjust both asset variants when changing a color, then check both previews. Keep normal key-label contrast at least 4.5:1.

The palette separates chassis and chrome, solid key fill, primary and secondary labels, borders, and separators. Active modifiers use a green border and indicator without replacing their profile fill. Hover softens the solid fill and strengthens the border. Key movement, highlights, borders, and active indicators update immediately without animation; pointer regions stay fixed. Keys, suggestions, and the keyboard chassis use solid colors without gradients or glows. The titlebar alone blends vertically from chrome to chassis, with no bottom divider, to join the keyboard background seamlessly.

## Components and behavior

Use `KeycapSurface` as a background, passing a shape and the current interaction state. It handles appearance only. Input delivery, accessibility labels, sounds, and focus remain with the existing control. `KeycapButtonStyle` applies this surface to SwiftUI controls such as the language switch. Rectangle and ISO Return keys share the surface. Visual insets and rounded corners do not shrink the existing pointer regions. The titlebar centers the selected profile name without an icon or extra label; its menu switches profiles, opens macOS Panel Editor, and reloads imported profiles.

Use the metrics and typography in `KeyboardDesign` rather than introducing local copies. Key labels scale with the imported panel. The panel keeps a 5-point outer inset. Key columns fill the available width so the side margins match the bottom inset, while vertical spacing and row heights stay unchanged. Prediction buttons keep a 32-point height, content-sized width, and left alignment. The row shows as many complete buttons as fit, without scrolling or changing its height.

Prediction text and row changes respect Reduce Motion. Keypress feedback is always immediate, and Increased Contrast strengthens key borders. Do not animate pointer regions or replace a prediction while it is pressed.

To add a visual state, extend `KeycapSurface` and its previews. To add a color role, create a named color asset with both appearances and expose it through `KeyboardDesign.Palette`. Avoid per-screen themes or duplicated keycap drawing code.

Automatic layout changes when switching applications preserve toggled Fn and pending one-shot modifiers. They cancel held keys and their repeat tasks so typing cannot continue from a disappearing layout. Hiding, minimizing, locking, quitting, or explicitly choosing a different layout releases virtual input.

The optional function toolbar sits directly below the titlebar and above predictions. Its complete height comes from the scaled keycap height plus vertical insets. Display-synchronized frame updates drive its clipped reveal and the native window geometry, keeping the main key area stable. Constraints and saved geometry update at completion. One permanent toggle sits to the right of the language selector in the prediction row; imported toolbar toggles are hidden without reflowing the remaining keys. System controls are the normal layer; toggling Fn exposes F1–F12.

## Settings

Settings uses a native segmented picker centered in the compact toolbar, with General, AI Providers, and the Debug-only AI Debug destination. The compact window has no sidebar. System materials, colors, typography, selection highlights, and control shapes follow macOS appearance and accessibility preferences.

The navigation picker uses the system large control size, intrinsic sizing, text-only segment labels, and per-segment help. This follows Apple's [segmented control guidance](https://developer.apple.com/design/human-interface-guidelines/segmented-controls) for macOS toolbar view switching. Apple's [AppKit design session](https://developer.apple.com/videos/play/wwdc2025/310/) explains that smaller controls retain rounded rectangles while large controls use capsules; the app does not draw or clip the selection highlight itself.

General and AI Providers use grouped `Form` sections with labeled rows and standard toggles, pickers, and buttons. The active provider is a single picker; each provider has its own model, option, status, and configuration rows. Provider refresh sits at the trailing edge of a compact title bar. A narrow `SettingsWindowConfiguration` bridge applies the native compact AppKit toolbar style because the Settings scene otherwise forces an expanded preference toolbar. No custom glass menu wrappers, hit areas, or corner radii are applied.

AI Debug uses native input and output groups, system body text, the standard editor background, and a default Generate button. View spacing and page insets use SwiftUI defaults; no explicit glass containers wrap ordinary settings controls. Descriptions appear only when needed to explain behavior, status, or recovery. Settings services and persistence are independent of the presentation.
