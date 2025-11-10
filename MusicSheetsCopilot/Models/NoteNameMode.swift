import Foundation

/// Mode for displaying note names in the SVG WebView
enum NoteNameMode: String, Codable, CaseIterable {
    case none = "none"
    case letter = "letter"
    case solfege = "solfege"

    /// Human-friendly title
    var title: String {
        switch self {
        case .none: return "No note names"
        case .letter: return "Letter"
        case .solfege: return "Solfege"
        }
    }

    /// Verbose label used in menus to match MetronomeMode wording
    var menuTitle: String {
        switch self {
        case .none: return "No note names"
        case .letter: return "Letter (C-D-E)"
        case .solfege: return "Solfege (Do-Re-Mi)"
        }
    }
}
