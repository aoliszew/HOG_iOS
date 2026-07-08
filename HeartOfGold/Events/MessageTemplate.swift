import Foundation

/// Lightweight text templating for event content, resolved at fire time so
/// even a repeated line sounds fresh:
///   {n:88-99}                 → random integer in the inclusive range
///   {pick:a hawk|two pigeons} → random option ('|'-separated)
enum MessageTemplate {
    static func render(_ text: String) -> String {
        var result = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            result += rest[..<open]
            let body = rest[rest.index(after: open)..<close]
            result += substitute(String(body)) ?? "{\(body)}"
            rest = rest[rest.index(after: close)...]
        }
        result += rest
        return result
    }

    private static func substitute(_ body: String) -> String? {
        if body.hasPrefix("n:") {
            let parts = body.dropFirst(2).split(separator: "-", maxSplits: 1)
            if parts.count == 2, let lo = Int(parts[0]), let hi = Int(parts[1]), lo <= hi {
                return String(Int.random(in: lo...hi))
            }
            return nil
        }
        if body.hasPrefix("pick:") {
            let options = body.dropFirst(5).split(separator: "|").map(String.init)
            return options.randomElement()
        }
        return nil
    }
}
