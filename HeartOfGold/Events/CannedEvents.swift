import Foundation

/// Hand-written encounter pool for the POC.
struct CannedEvents: EventSource {
    private static let general: [ShipEvent] = [
        .init(source: "MEDBAY", text: "Medbay to bridge. All crew vitals nominal. One crew member reports mild snack deficiency."),
        .init(source: "SCIENCE", text: "Science officer reporting. Sensors detect a nebula ahead. It is almost certainly just a cloud, but I am logging it as a nebula."),
        .init(source: "ENGINEERING", text: "Engineering here. The Infinite Improbability Drive is idling at two to the power of nothing much. All systems green."),
        .init(source: "COMMS", text: "Incoming transmission from a passing Vogon freighter. It appears to be poetry. Recommend we do not answer."),
        .init(source: "SECURITY", text: "Security report: no hostile vessels detected. One suspicious pigeon on the forward viewport."),
        .init(source: "AI CORE", text: "Just checking in, Captain. Probability of a pleasant journey currently holding at ninety-seven point three percent."),
        .init(source: "CARGO BAY", text: "Cargo bay reports all items secure. The towel remains exactly where you left it. Do not panic."),
        .init(source: "NAVIGATION", text: "Navigation update: we remain improbably on course. The Guide suggests this is cause for mild celebration."),
    ]

    private static let roadtripOnly: [ShipEvent] = [
        .init(source: "LONG RANGE", text: "Long range sensors report open space for several parsecs. Ideal conditions for cruise velocity."),
        .init(source: "CREW", text: "A crew member requests a status update on the next resupply station. Translation: they need a bathroom."),
    ]

    private static let errandsOnly: [ShipEvent] = [
        .init(source: "MISSION OPS", text: "Mission ops reminder: this is a multi-objective sortie. Recommend reviewing the acquisition list before docking."),
        .init(source: "DOCKING", text: "Docking control reports heavy traffic at the trade station. Patience shields to maximum."),
    ]

    private static let highSpeed: [ShipEvent] = [
        .init(source: "HELM", text: "Helm reports we are approaching maximum sublight. The hull is fine. Probably."),
    ]

    func nextEvent(mode: TravelMode, speedMPH: Double) -> ShipEvent {
        var pool = Self.general
        pool += mode == .roadtrip ? Self.roadtripOnly : Self.errandsOnly
        if speedMPH > 65 { pool += Self.highSpeed }
        return pool.randomElement()!
    }
}
