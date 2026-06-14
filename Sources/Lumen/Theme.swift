import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

/// A visual identity built on real translucency (Apple "Liquid Glass"): the
/// panel is a frosted material that samples the desktop behind it. Themes differ
/// by light/dark scheme, a subtle colour wash, the accent, and the ring gradient.
struct Theme: Identifiable {
    let id: String
    let name: String
    let tagline: String
    let scheme: ColorScheme   // drives the frosted material + text colour
    let wash: Color           // subtle tint laid over the glass
    let accent: Color
    let accent2: Color
    let ringStops: [Color]    // healthy-ring gradient (swept around the ring)
    let warn: Color
    let danger: Color

    /// The ring fill for a given load: gradient when healthy, solid when it
    /// matters (warn → danger). Keeps the severity signal across every theme.
    func ringFill(_ pct: Double, warnAt: Double = 68, dangerAt: Double = 85) -> AnyShapeStyle {
        if pct >= dangerAt { return AnyShapeStyle(danger) }
        if pct >= warnAt { return AnyShapeStyle(warn) }
        return AnyShapeStyle(AngularGradient(
            colors: ringStops + [ringStops.first ?? accent],
            center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)))
    }

    // MARK: The headline glasses

    /// Frosted white — Apple Liquid Glass, light and airy.
    static let clear = Theme(
        id: "clear", name: "Clear", tagline: "Frosted white glass",
        scheme: .light, wash: Color.white.opacity(0.16),
        accent: Color(hex: 0x0A84FF), accent2: Color(hex: 0x5E5CE6),
        ringStops: [Color(hex: 0x0A84FF), Color(hex: 0x5E5CE6)],
        warn: Color(hex: 0xFF9500), danger: Color(hex: 0xFF3B30))

    /// Deep black glass — the "black hole" / Grok-dark look.
    static let obsidian = Theme(
        id: "obsidian", name: "Obsidian", tagline: "Black-hole glass",
        scheme: .dark, wash: Color.black.opacity(0.34),
        accent: Color(hex: 0x64D2FF), accent2: Color(hex: 0x7C6CFF),
        ringStops: [Color(hex: 0x64D2FF), Color(hex: 0x7C6CFF)],
        warn: Color(hex: 0xFFD60A), danger: Color(hex: 0xFF453A))

    /// Vercel / Geist: pure-black glass, single signature blue ring. (Default.)
    static let vercel = Theme(
        id: "vercel", name: "Vercel", tagline: "Geist black + signature blue",
        scheme: .dark, wash: Color.black.opacity(0.44),
        accent: Color(hex: 0x0070F3), accent2: Color(hex: 0x3D9DFF),
        ringStops: [Color(hex: 0x0070F3)],
        warn: Color(hex: 0xF5A623), danger: Color(hex: 0xEE0000))

    /// Linear: black glass, refined indigo ring.
    static let linear = Theme(
        id: "linear", name: "Linear", tagline: "Black glass + indigo",
        scheme: .dark, wash: Color.black.opacity(0.42),
        accent: Color(hex: 0x5E6AD2), accent2: Color(hex: 0x8B5CF6),
        ringStops: [Color(hex: 0x5E6AD2)],
        warn: Color(hex: 0xF5A623), danger: Color(hex: 0xEE0000))

    /// Stripe: black glass, the signature flowing multi-colour gradient ring.
    static let stripe = Theme(
        id: "stripe", name: "Stripe", tagline: "Black glass + flow gradient",
        scheme: .dark, wash: Color.black.opacity(0.42),
        accent: Color(hex: 0x635BFF), accent2: Color(hex: 0xFF80B5),
        ringStops: [Color(hex: 0x11EFE3), Color(hex: 0x635BFF),
                    Color(hex: 0xFF80B5), Color(hex: 0xFFB199)],
        warn: Color(hex: 0xF5A623), danger: Color(hex: 0xEE0000))

    // MARK: Warm tinted glass

    static let ember = Theme(
        id: "ember", name: "Ember", tagline: "Amber-tinted glass",
        scheme: .dark, wash: Color(hex: 0x3A1E08).opacity(0.40),
        accent: Color(hex: 0xFF9D3D), accent2: Color(hex: 0xFF5E3A),
        ringStops: [Color(hex: 0xFF9D3D), Color(hex: 0xFF5E3A)],
        warn: Color(hex: 0xFFC24D), danger: Color(hex: 0xFF4D3D))

    static let all: [Theme] = [vercel, obsidian, linear, stripe, clear, ember]
    static func byId(_ id: String) -> Theme { all.first { $0.id == id } ?? vercel }

    /// Same theme with different ring colours (gradient = the stops given).
    func recolored(_ stops: [Color]) -> Theme {
        Theme(id: id, name: name, tagline: tagline, scheme: scheme, wash: wash,
              accent: stops.first ?? accent, accent2: stops.last ?? accent2,
              ringStops: stops, warn: warn, danger: danger)
    }
}

/// The frosted-glass backdrop: a translucent material plus a subtle colour wash.
/// In the live app the material samples the desktop behind the panel.
struct ThemeBackground: View {
    let theme: Theme
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(theme.wash)
        }
    }
}

/// A stand-in desktop used only when rendering previews offscreen, so the glass
/// translucency is visible (the live app frosts the real wallpaper instead).
struct WallpaperBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x223A8E), Color(hex: 0x7A2A6E), Color(hex: 0x1E6E72)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(hex: 0xFF6EC7).opacity(0.65)).blur(radius: 34)
                .frame(width: 180, height: 180).offset(x: -110, y: -130)
            Circle().fill(Color(hex: 0x6EC7FF).opacity(0.55)).blur(radius: 34)
                .frame(width: 200, height: 200).offset(x: 130, y: 110)
            Circle().fill(Color(hex: 0xFFD86E).opacity(0.45)).blur(radius: 36)
                .frame(width: 150, height: 150).offset(x: 90, y: -120)
        }
        .ignoresSafeArea()
    }
}

/// The selected theme, shared across the menu-bar panel and the Storage window
/// and persisted across launches.
@MainActor
final class ThemeStore: ObservableObject {
    @Published var theme: Theme
    private let key = "lumen.theme"

    init() {
        let id = UserDefaults.standard.string(forKey: key) ?? "vercel"
        theme = Theme.byId(id)
    }

    /// Fixed theme, used by offscreen previews.
    init(theme: Theme) { self.theme = theme }

    func select(_ id: String) {
        theme = Theme.byId(id)
        UserDefaults.standard.set(id, forKey: key)
    }
}
