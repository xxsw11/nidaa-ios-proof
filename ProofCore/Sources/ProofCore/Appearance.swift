import Foundation

public struct HexColor: Codable, Equatable, Sendable {
    public let value: String
    public init?(_ text: String) {
        let value = text.uppercased()
        guard value.count == 7, value.first == "#", UInt32(value.dropFirst(), radix: 16) != nil else { return nil }
        self.value = value
    }
    public var rgb: (Double, Double, Double) {
        let n = UInt32(value.dropFirst(), radix: 16)!
        return (Double((n >> 16) & 255)/255, Double((n >> 8) & 255)/255, Double(n & 255)/255)
    }
    public var luminance: Double {
        let (r,g,b) = rgb
        func linear(_ x: Double) -> Double { x <= 0.04045 ? x/12.92 : pow((x+0.055)/1.055, 2.4) }
        return 0.2126*linear(r)+0.7152*linear(g)+0.0722*linear(b)
    }
    public func contrast(_ other: Self) -> Double { (max(luminance, other.luminance)+0.05)/(min(luminance, other.luminance)+0.05) }
    public var readableInk: Self {
        let black = Self("#000000")!, white = Self("#FFFFFF")!
        return contrast(black) >= contrast(white) ? black : white
    }
}
public enum AppearanceMode: String, Codable, CaseIterable, Sendable {
    case dark, light, system
    public var title: String { switch self { case .dark: return "ط¯ط§ظƒظ†"; case .light: return "ظپط§طھط­"; case .system: return "ط­ط³ط¨ ط§ظ„ط¬ظ‡ط§ط²" } }
}
public struct Palette: Codable, Equatable, Sendable {
    public var primary: String
    public var button: String
    public var background: String
    public init(primary: String, button: String, background: String) { self.primary = primary;self.button = button;self.background = background }
    public static let dark = Self(primary: "#FFDC38", button: "#FFDC38", background: "#101110")
    public static let light = Self(primary: "#806400", button: "#FFDC38", background: "#F4F2E8")
    public var valid: Bool { [primary,button,background].allSatisfy { HexColor($0) != nil } }
    public var ink: HexColor { (HexColor(background) ?? HexColor(Self.dark.background)!).readableInk }
    public var buttonInk: HexColor { (HexColor(button) ?? HexColor(Self.dark.button)!).readableInk }
    public var accentInk: HexColor {
        let p = HexColor(primary) ?? HexColor(Self.dark.primary)!, b = HexColor(background) ?? HexColor(Self.dark.background)!
        return p.contrast(b) >= 4.5 ? p : ink
    }
}
public struct AppearancePreferences: Codable, Equatable, Sendable {
    public var version = 1
    public var mode: AppearanceMode = .dark
    public var dark = Palette.dark
    public var light = Palette.light
    public init() {}
    public var valid: Bool { version == 1 && dark.valid && light.valid }
    public func palette(systemDark: Bool) -> Palette { (mode == .dark || (mode == .system && systemDark)) ? dark : light }
}
public final class DemoPreferences {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func loadAppearance() -> AppearancePreferences {
        guard let data = defaults.data(forKey: "nidaa.native.appearance"), let decoded = try? JSONDecoder().decode(AppearancePreferences.self, from: data), decoded.valid else { return .init() }
        return decoded
    }
    public func saveAppearance(_ value: AppearancePreferences) throws {
        guard value.valid else { throw SimulationError.invalidTransition }
        defaults.set(try JSONEncoder().encode(value), forKey: "nidaa.native.appearance")
    }
    public func loadContacts() -> [TrustedContact] {
        guard let data = defaults.data(forKey: "nidaa.native.contacts"), let decoded = try? JSONDecoder().decode([TrustedContact].self, from: data), Set(decoded.map(\.id)).count == decoded.count,
              decoded.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 40 }) else { return TrustedContact.samples }
        return decoded
    }
    public func saveContacts(_ value: [TrustedContact]) throws { defaults.set(try JSONEncoder().encode(value), forKey: "nidaa.native.contacts") }
    public var appLock: Bool { get { defaults.bool(forKey: "nidaa.native.lock") } set { defaults.set(newValue, forKey: "nidaa.native.lock") } }
    public func reset() { for key in ["nidaa.native.appearance","nidaa.native.contacts","nidaa.native.lock"] { defaults.removeObject(forKey: key) } }
}
