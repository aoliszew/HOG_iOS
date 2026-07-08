import Foundation

/// Loads every event JSON under Content/events (recursively) from the app bundle.
/// Malformed files are skipped with a log line — the CI validator should have
/// caught them long before they reach a build.
final class ContentLibrary {
    let events: [EventDefinition]

    init(bundle: Bundle = .main) {
        var loaded: [EventDefinition] = []
        let decoder = JSONDecoder()
        if let root = bundle.resourceURL?.appendingPathComponent("Content/events"),
           let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.pathExtension == "json" {
                do {
                    loaded.append(try decoder.decode(EventDefinition.self, from: Data(contentsOf: url)))
                } catch {
                    print("ContentLibrary: skipping \(url.lastPathComponent): \(error)")
                }
            }
        }
        if loaded.isEmpty {
            print("ContentLibrary: no events found in bundle")
        }
        events = loaded
    }
}
