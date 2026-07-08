import Foundation

/// Per-character speech deliveries so the captain knows who's talking without
/// looking at the screen. Multipliers apply on top of the Power/Eco base
/// delivery. (The ElevenLabs upgrade will replace these with true voices
/// behind the same seam.)
enum CharacterVoices {
    struct Style {
        let rateMultiplier: Float
        let pitchMultiplier: Float
    }

    private static let styles: [String: Style] = [
        "MARVIN": Style(rateMultiplier: 0.82, pitchMultiplier: 0.72),   // slow, low, terminally unimpressed
        "SHIP": Style(rateMultiplier: 1.05, pitchMultiplier: 1.08),    // Eddie-adjacent: bright and eager
        "AI CORE": Style(rateMultiplier: 1.05, pitchMultiplier: 1.08),
        "SCIENCE": Style(rateMultiplier: 1.1, pitchMultiplier: 1.02),  // quick, curious
        "ENGINEERING": Style(rateMultiplier: 0.95, pitchMultiplier: 0.9),
        "MEDBAY": Style(rateMultiplier: 0.92, pitchMultiplier: 1.05),  // calm bedside manner
        "SECURITY": Style(rateMultiplier: 0.9, pitchMultiplier: 0.85), // clipped and gruff
        "COMMS": Style(rateMultiplier: 1.0, pitchMultiplier: 1.0),
        "NAVIGATION": Style(rateMultiplier: 1.0, pitchMultiplier: 0.97),
        "HELM": Style(rateMultiplier: 1.0, pitchMultiplier: 0.95),
    ]

    static func style(for source: String) -> Style {
        styles[source.uppercased()] ?? Style(rateMultiplier: 1.0, pitchMultiplier: 1.0)
    }

    /// Spoken lead-in so audio alone carries the context. Skipped when the
    /// text already announces its own source ("Medbay to bridge…").
    static func attribution(for source: String, text: String) -> String? {
        let lowerText = text.lowercased()
        let lowerSource = source.lowercased()
        let firstWords = lowerText.prefix(40)
        guard !firstWords.contains(lowerSource) else { return nil }
        switch source.uppercased() {
        case "SHIP", "AI CORE": return nil          // the ship's own voice needs no introduction
        case "MARVIN": return "Marvin:"
        case "CAPTAIN": return nil
        default: return "\(source.capitalized) reports:"
        }
    }
}
