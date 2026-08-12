import AppKit

/// The user's macOS accent color, converted to a stable RGB value for the
/// preview's HTML/CSS layer. Native SwiftUI controls resolve this same color
/// through AppKit, but WebKit needs the color values supplied explicitly.
struct SystemAccentPalette: Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    static var current: SystemAccentPalette {
        let color = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? NSColor.systemBlue
        return SystemAccentPalette(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    func cssRGBA(alpha: CGFloat = 1) -> String {
        let clampedAlpha = min(max(alpha, 0), 1)
        return "rgba(\(channel(red)), \(channel(green)), \(channel(blue)), \(format(clampedAlpha)))"
    }

    private func channel(_ value: CGFloat) -> Int {
        Int((min(max(value, 0), 1) * 255).rounded())
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.3g", locale: Locale(identifier: "en_US_POSIX"), Double(value))
    }
}
