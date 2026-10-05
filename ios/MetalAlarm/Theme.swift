import SwiftUI
import UIKit

enum Theme {
    static let void = Color(hex: 0x070405)
    static let crypt = Color(hex: 0x130B0C)
    static let crypt2 = Color(hex: 0x1C1012)
    static let line = Color(hex: 0x3A2224)
    static let bone = Color(hex: 0xE3D6BD)
    static let ash = Color(hex: 0x9A8A80)
    static let blood = Color(hex: 0x9E0B12)
    static let bloodHi = Color(hex: 0xD8141E)
    static let bloodDark = Color(hex: 0x4A0307)
    static let brass = Color(hex: 0x7A5D2A)

    static func display(_ size: CGFloat) -> Font { .custom("MetalMania-Regular", size: size) }
    static func gothic(_ size: CGFloat) -> Font { .custom("UnifrakturMaguntia", size: size) }
    static func heavy(_ size: CGFloat) -> Font { .custom("BarlowCondensed-ExtraBold", size: size) }
    static func semi(_ size: CGFloat) -> Font { .custom("BarlowCondensed-SemiBold", size: size) }
    static func body(_ size: CGFloat) -> Font { .custom("BarlowCondensed-Regular", size: size) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Loose PNGs rendered from the web clock's SVG (see ios/tools/render-art.cjs).
func art(_ name: String) -> Image {
    Image(uiImage: UIImage(named: name) ?? UIImage())
}

struct BloodButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.semi(19))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(Theme.bone)
            .padding(.horizontal, 18)
            .frame(minHeight: 50)
            .background(primary ? Theme.blood : Theme.crypt2, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(primary ? Theme.bloodHi : Theme.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct Pill: View {
    let text: String
    var on = false
    var body: some View {
        Text(text.uppercased())
            .font(Theme.heavy(14))
            .tracking(2)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .foregroundStyle(on ? Theme.bone : Theme.ash)
            .background(on ? Theme.blood : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(on ? Theme.bloodHi : Theme.line, lineWidth: 1))
    }
}

func clockTime(_ d: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "h:mm"
    return f.string(from: d)
}

func amPM(_ d: Date) -> String {
    Calendar.current.component(.hour, from: d) < 12 ? "AM" : "PM"
}
