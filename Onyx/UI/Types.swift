import Foundation
import SwiftUI

enum ProcessingMode: String, CaseIterable, Equatable {
    case mono = "MONO"
    case zero = "ZERO"
    
    var description: String {
        switch self {
        case .zero: return "Unprocessed RAW color data."
        case .mono: return "Authentic monochrome. Natural sensor grain."
        }
    }
}

enum GridMode: Int, CaseIterable, Equatable {
    case none = 0
    case thirds = 1
    
    mutating func toggle() {
        switch self {
        case .none: self = .thirds
        case .thirds: self = .none
        }
    }
}

enum AppTheme: String, CaseIterable, Equatable {
    case system = "SYSTEM"
    case light = "LIGHT"
    case dark = "DARK"
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
