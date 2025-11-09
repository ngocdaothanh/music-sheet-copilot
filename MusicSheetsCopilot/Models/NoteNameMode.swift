import Foundation

/// Mode for displaying note names in the SVG WebView
enum NoteNameMode: String, Codable, CaseIterable {
    case none = "none"
    case letter = "letter"
    case solfege = "solfege"

    /// Human-friendly title
    var title: String {
        switch self {
        case .none: return "None"
        case .letter: return "Letter"
        case .solfege: return "Solfege"
        }
    }
}
