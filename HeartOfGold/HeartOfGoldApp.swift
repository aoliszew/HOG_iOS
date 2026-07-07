import SwiftUI

@main
struct HeartOfGoldApp: App {
    @StateObject private var ship = ShipController()

    var body: some Scene {
        WindowGroup {
            BridgeView()
                .environmentObject(ship)
                .preferredColorScheme(.dark)
        }
    }
}
