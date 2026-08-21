import AppKit
import Combine
import Foundation

/// A stable sRGB color that can be shared by SwiftUI and the isolated HTML
/// preview without depending on dynamic AppKit color resolution in WebKit.
struct AppColorPalette: Codable, Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    init(nsColor: NSColor) {
        let color = nsColor.usingColorSpace(.sRGB) ?? NSColor.systemBlue
        self.init(
            red: Double(color.redComponent),
            green: Double(color.greenComponent),
            blue: Double(color.blueComponent)
        )
    }

    static var systemAccent: AppColorPalette {
        AppColorPalette(nsColor: NSColor.controlAccentColor)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    var contrastingNSColor: NSColor {
        usesDarkForeground ? .black : .white
    }

    var contrastingCSSTextColor: String {
        usesDarkForeground ? "#000" : "#fff"
    }

    private var usesDarkForeground: Bool {
        let luminance = 0.2126 * Self.linearized(red)
            + 0.7152 * Self.linearized(green)
            + 0.0722 * Self.linearized(blue)
        let blackContrast = (luminance + 0.05) / 0.05
        let whiteContrast = 1.05 / (luminance + 0.05)
        return blackContrast >= whiteContrast
    }

    func cssRGBA(alpha: Double = 1) -> String {
        let clampedAlpha = Self.clamp(alpha)
        return "rgba(\(Self.channel(red)), \(Self.channel(green)), \(Self.channel(blue)), \(Self.format(clampedAlpha)))"
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func channel(_ value: Double) -> Int {
        Int((clamp(value) * 255).rounded())
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3g", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func linearized(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
}

enum ReviewColorPreset: String, CaseIterable, Identifiable {
    case orange
    case blue
    case purple
    case green
    case pink
    case red

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var palette: AppColorPalette {
        switch self {
        case .orange:
            AppColorPalette(red: 1, green: 0.584, blue: 0)
        case .blue:
            AppColorPalette(red: 0, green: 0.478, blue: 1)
        case .purple:
            AppColorPalette(red: 0.686, green: 0.322, blue: 0.871)
        case .green:
            AppColorPalette(red: 0.204, green: 0.78, blue: 0.349)
        case .pink:
            AppColorPalette(red: 1, green: 0.176, blue: 0.333)
        case .red:
            AppColorPalette(red: 1, green: 0.231, blue: 0.188)
        }
    }
}

@MainActor
final class ReviewColorStore: ObservableObject {
    static let defaultsKey = "reviewColor"
    static let defaultPalette = ReviewColorPreset.orange.palette

    @Published private(set) var palette: AppColorPalette

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let storedPalette = try? JSONDecoder().decode(AppColorPalette.self, from: data) {
            palette = storedPalette
        } else {
            palette = Self.defaultPalette
        }
    }

    func set(_ palette: AppColorPalette) {
        guard palette != self.palette else { return }
        self.palette = palette
        if let data = try? JSONEncoder().encode(palette) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
