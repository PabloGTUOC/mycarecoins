import SwiftUI

enum Palette {
  static let bg = Color(hex: 0xF7F8FA)
  static let surface = Color(hex: 0xFFFFFF)
  static let border = Color(hex: 0xE5E8EE)
  static let textPrimary = Color(hex: 0x0E1726)
  static let textSecondary = Color(hex: 0x5B6478)
  static let primary = Color(hex: 0x006EB8)
  static let primarySoft = Color(hex: 0xE6F0F8)
  static let primaryInk = Color(hex: 0x005B8D)
  static let success = Color(hex: 0x16A34A)
  static let successSoft = Color(hex: 0xE7F6EC)
  static let successInk = Color(hex: 0x166534)
  static let warning = Color(hex: 0xD97706)
  static let warningSoft = Color(hex: 0xFEF1E1)
  static let warningInk = Color(hex: 0x92400E)
  static let danger = Color(hex: 0xDC2626)
  static let dangerSoft = Color(hex: 0xFCE8E8)
  static let dangerInk = Color(hex: 0xB91C1C)
  static let ink = Color(hex: 0x0F172A)
  static let inkMuted = Color(hex: 0x94A3B8)
  static let successOnDark = Color(hex: 0x34D399)
  static let dangerOnDark = Color(hex: 0xF87171)
  static let coin = Color(hex: 0xF99D1B)
  static let coinSoft = Color(hex: 0xFEE9CA)
  static let coinInk = Color(hex: 0x7C4226)

  static func widgetBackground(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? ink : surface
  }

  static func widgetText(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color.white : textPrimary
  }

  static func widgetSecondaryText(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? inkMuted : textSecondary
  }
}

extension Color {
  init(hex: UInt32) {
    let red = Double((hex >> 16) & 0xFF) / 255.0
    let green = Double((hex >> 8) & 0xFF) / 255.0
    let blue = Double(hex & 0xFF) / 255.0
    self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
  }
}
