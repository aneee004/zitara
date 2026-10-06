import SwiftUI
import UIKit

/// Central palette + type. Every color the UI paints comes through here so the
/// app can be re-themed in one place. The current theme is "rosewood" — a
/// crafted-instrument look: dark wood ground, brass for Sa and active state,
/// ivory for in-scale notes, and a single garnet accent reserved for vibrato.
///
/// Restraint is the point: no glows on idle cells, no particles. Light only
/// appears where the player is touching, so the eye goes to the music.
///
/// Both UIColor and SwiftUI Color mirrors exist because the grid is UIKit
/// (`GridSurfaceView.draw`) while the rest of the chrome is SwiftUI.
enum Theme {

    // MARK: - Grounds (darkest → lightest)

    static let appBackground     = Color(hex: 0x120C0A)
    static let appBackgroundUI   = UIColor(hex: 0x120C0A)

    /// The grid canvas, visible in the gaps between tiles.
    static let gridCanvasUI      = UIColor(hex: 0x140E0B)

    static let panelBackground   = Color(hex: 0x1D1512)

    /// Inset surfaces inside the panel: XY pad, keys, sustain disc.
    static let surfaceRaised     = Color(hex: 0x261C17)
    static let surfaceRaisedUI   = UIColor(hex: 0x261C17)

    static let hairline          = Color(hex: 0x3A2C25)
    static let hairlineUI        = UIColor(hex: 0x3A2C25)

    // MARK: - Ink

    static let ivory             = Color(hex: 0xEDE3CF)
    static let ivoryUI           = UIColor(hex: 0xEDE3CF)
    static let textSecondary     = Color(hex: 0xA38F7C)
    static let textTertiary      = Color(hex: 0x6E5D51)
    static let textTertiaryUI    = UIColor(hex: 0x6E5D51)

    // MARK: - Accents

    /// Brass: Sa, active touch, filled fader tracks. The "royal" metal.
    static let brass             = Color(hex: 0xE8B04A)
    static let brassUI           = UIColor(hex: 0xE8B04A)

    /// Garnet: used ONLY for vibrato so it reads as a distinct gesture.
    static let garnet            = Color(hex: 0xC2434F)
    static let garnetUI          = UIColor(hex: 0xC2434F)

    // MARK: - Grid tiles

    static let cellOutFillUI     = UIColor(hex: 0x1F1713)
    static let cellInFillUI      = UIColor(hex: 0xEDE3CF, alpha: 0.07)
    static let cellInStrokeUI    = UIColor(hex: 0xEDE3CF, alpha: 0.18)
    static let cellRootFillUI    = UIColor(hex: 0xE8B04A, alpha: 0.16)
    /// Overlay on every cell that shares the sounding pitch.
    static let cellLitFillUI     = UIColor(hex: 0xE8B04A, alpha: 0.30)

    // MARK: - Touch feedback

    /// Bloom under the finger: brass when quiet, warm ivory when loud.
    static let bloomUI           = UIColor(hex: 0xE8B04A)
    static let bloomHotUI        = UIColor(hex: 0xFFE9C2)

    // MARK: - Type
    //
    // Serif (New York) for anything the musician reads; tracked uppercase for
    // section labels so they recede behind the values they describe.

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func serifUI(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let desc = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: desc, size: size)
    }
}

/// Section label used throughout the control bar.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.serif(10.5, weight: .semibold))
            .tracking(1.4)
            .foregroundColor(Theme.textSecondary)
            .lineLimit(1)
    }
}

// MARK: - Hex helpers

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >>  8) & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >>  8) & 0xFF) / 255.0
        let b = CGFloat( hex        & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}
