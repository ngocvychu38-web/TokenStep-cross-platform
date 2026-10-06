import AppKit
import SwiftUI

struct TokenStepRGB: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    var nsColor: NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }
}

struct TokenStepThemePalette {
    var canvas: TokenStepRGB
    var surface: TokenStepRGB
    var accent: TokenStepRGB
    var accentDark: TokenStepRGB
    var accentSoft: TokenStepRGB
    var track: TokenStepRGB
    var lowActivity: TokenStepRGB
    var activity1: TokenStepRGB
    var activity2: TokenStepRGB
    var activity3: TokenStepRGB
    var activity4: TokenStepRGB
    var ring1: TokenStepRGB
    var ring2: TokenStepRGB
    var ring3: TokenStepRGB
    var ring4: TokenStepRGB

    func ringRGB(for lap: Int) -> TokenStepRGB {
        switch max(lap, 1) {
        case 1: return ring1
        case 2: return ring2
        case 3: return ring3
        default: return ring4
        }
    }

    func activityColor(for level: Int) -> Color {
        switch level {
        case 1: return activity1.color
        case 2: return activity2.color
        case 3: return activity3.color
        default: return activity4.color
        }
    }
}

enum TokenStepTheme: String, CaseIterable, Identifiable, Codable {
    case green
    case ocean
    case violet
    case amber
    case graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .green: return L("青绿")
        case .ocean: return L("海蓝")
        case .violet: return L("紫藤")
        case .amber: return L("琥珀")
        case .graphite: return L("石墨")
        }
    }

    var subtitle: String {
        switch self {
        case .green: return L("默认")
        case .ocean: return L("清爽")
        case .violet: return "Agent"
        case .amber: return L("温暖")
        case .graphite: return L("专注")
        }
    }

    var palette: TokenStepThemePalette {
        switch self {
        case .green:
            return TokenStepThemePalette(
                canvas: .init(red: 246 / 255, green: 248 / 255, blue: 250 / 255),
                surface: .init(red: 255 / 255, green: 255 / 255, blue: 255 / 255),
                accent: .init(red: 45 / 255, green: 164 / 255, blue: 78 / 255),
                accentDark: .init(red: 33 / 255, green: 110 / 255, blue: 57 / 255),
                accentSoft: .init(red: 155 / 255, green: 233 / 255, blue: 168 / 255),
                track: .init(red: 235 / 255, green: 237 / 255, blue: 240 / 255),
                lowActivity: .init(red: 221 / 255, green: 244 / 255, blue: 223 / 255),
                activity1: .init(red: 155 / 255, green: 233 / 255, blue: 168 / 255),
                activity2: .init(red: 64 / 255, green: 196 / 255, blue: 99 / 255),
                activity3: .init(red: 48 / 255, green: 161 / 255, blue: 78 / 255),
                activity4: .init(red: 33 / 255, green: 110 / 255, blue: 57 / 255),
                ring1: .init(red: 64 / 255, green: 196 / 255, blue: 99 / 255),
                ring2: .init(red: 48 / 255, green: 161 / 255, blue: 78 / 255),
                ring3: .init(red: 33 / 255, green: 110 / 255, blue: 57 / 255),
                ring4: .init(red: 14 / 255, green: 68 / 255, blue: 41 / 255)
            )
        case .ocean:
            return TokenStepThemePalette(
                canvas: .init(red: 245 / 255, green: 250 / 255, blue: 253 / 255),
                surface: .init(red: 254 / 255, green: 255 / 255, blue: 255 / 255),
                accent: .init(red: 14 / 255, green: 165 / 255, blue: 233 / 255),
                accentDark: .init(red: 3 / 255, green: 105 / 255, blue: 161 / 255),
                accentSoft: .init(red: 186 / 255, green: 230 / 255, blue: 253 / 255),
                track: .init(red: 234 / 255, green: 240 / 255, blue: 245 / 255),
                lowActivity: .init(red: 224 / 255, green: 242 / 255, blue: 254 / 255),
                activity1: .init(red: 186 / 255, green: 230 / 255, blue: 253 / 255),
                activity2: .init(red: 56 / 255, green: 189 / 255, blue: 248 / 255),
                activity3: .init(red: 14 / 255, green: 165 / 255, blue: 233 / 255),
                activity4: .init(red: 3 / 255, green: 105 / 255, blue: 161 / 255),
                ring1: .init(red: 56 / 255, green: 189 / 255, blue: 248 / 255),
                ring2: .init(red: 14 / 255, green: 165 / 255, blue: 233 / 255),
                ring3: .init(red: 2 / 255, green: 132 / 255, blue: 199 / 255),
                ring4: .init(red: 7 / 255, green: 89 / 255, blue: 133 / 255)
            )
        case .violet:
            return TokenStepThemePalette(
                canvas: .init(red: 250 / 255, green: 248 / 255, blue: 255 / 255),
                surface: .init(red: 255 / 255, green: 254 / 255, blue: 255 / 255),
                accent: .init(red: 139 / 255, green: 92 / 255, blue: 246 / 255),
                accentDark: .init(red: 91 / 255, green: 33 / 255, blue: 182 / 255),
                accentSoft: .init(red: 221 / 255, green: 214 / 255, blue: 254 / 255),
                track: .init(red: 238 / 255, green: 235 / 255, blue: 245 / 255),
                lowActivity: .init(red: 237 / 255, green: 233 / 255, blue: 254 / 255),
                activity1: .init(red: 221 / 255, green: 214 / 255, blue: 254 / 255),
                activity2: .init(red: 167 / 255, green: 139 / 255, blue: 250 / 255),
                activity3: .init(red: 139 / 255, green: 92 / 255, blue: 246 / 255),
                activity4: .init(red: 91 / 255, green: 33 / 255, blue: 182 / 255),
                ring1: .init(red: 167 / 255, green: 139 / 255, blue: 250 / 255),
                ring2: .init(red: 139 / 255, green: 92 / 255, blue: 246 / 255),
                ring3: .init(red: 109 / 255, green: 40 / 255, blue: 217 / 255),
                ring4: .init(red: 76 / 255, green: 29 / 255, blue: 149 / 255)
            )
        case .amber:
            return TokenStepThemePalette(
                canvas: .init(red: 255 / 255, green: 250 / 255, blue: 242 / 255),
                surface: .init(red: 255 / 255, green: 255 / 255, blue: 252 / 255),
                accent: .init(red: 245 / 255, green: 158 / 255, blue: 11 / 255),
                accentDark: .init(red: 180 / 255, green: 83 / 255, blue: 9 / 255),
                accentSoft: .init(red: 253 / 255, green: 230 / 255, blue: 138 / 255),
                track: .init(red: 244 / 255, green: 239 / 255, blue: 231 / 255),
                lowActivity: .init(red: 254 / 255, green: 243 / 255, blue: 199 / 255),
                activity1: .init(red: 254 / 255, green: 243 / 255, blue: 199 / 255),
                activity2: .init(red: 251 / 255, green: 191 / 255, blue: 36 / 255),
                activity3: .init(red: 245 / 255, green: 158 / 255, blue: 11 / 255),
                activity4: .init(red: 180 / 255, green: 83 / 255, blue: 9 / 255),
                ring1: .init(red: 251 / 255, green: 191 / 255, blue: 36 / 255),
                ring2: .init(red: 245 / 255, green: 158 / 255, blue: 11 / 255),
                ring3: .init(red: 180 / 255, green: 83 / 255, blue: 9 / 255),
                ring4: .init(red: 120 / 255, green: 53 / 255, blue: 15 / 255)
            )
        case .graphite:
            return TokenStepThemePalette(
                canvas: .init(red: 247 / 255, green: 247 / 255, blue: 247 / 255),
                surface: .init(red: 255 / 255, green: 255 / 255, blue: 255 / 255),
                accent: .init(red: 82 / 255, green: 82 / 255, blue: 91 / 255),
                accentDark: .init(red: 39 / 255, green: 39 / 255, blue: 42 / 255),
                accentSoft: .init(red: 212 / 255, green: 212 / 255, blue: 216 / 255),
                track: .init(red: 232 / 255, green: 232 / 255, blue: 236 / 255),
                lowActivity: .init(red: 228 / 255, green: 228 / 255, blue: 231 / 255),
                activity1: .init(red: 212 / 255, green: 212 / 255, blue: 216 / 255),
                activity2: .init(red: 113 / 255, green: 113 / 255, blue: 122 / 255),
                activity3: .init(red: 82 / 255, green: 82 / 255, blue: 91 / 255),
                activity4: .init(red: 39 / 255, green: 39 / 255, blue: 42 / 255),
                ring1: .init(red: 113 / 255, green: 113 / 255, blue: 122 / 255),
                ring2: .init(red: 82 / 255, green: 82 / 255, blue: 91 / 255),
                ring3: .init(red: 63 / 255, green: 63 / 255, blue: 70 / 255),
                ring4: .init(red: 24 / 255, green: 24 / 255, blue: 27 / 255)
            )
        }
    }
}

enum TokenStepThemeRuntime {
    private static var activeTheme: TokenStepTheme = .green

    static var theme: TokenStepTheme { activeTheme }
    static var palette: TokenStepThemePalette { activeTheme.palette }

    static func apply(_ theme: TokenStepTheme) {
        activeTheme = theme
    }
}
