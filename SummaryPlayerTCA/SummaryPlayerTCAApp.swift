import ComposableArchitecture
import SwiftUI

@main
struct SummaryPlayerTCAApp: App {
    var body: some Scene {
        WindowGroup {
            PlayerView(
                store: Store(initialState: PlayerFeature.State(bookSummary: BookSummary.mock)) {
                    PlayerFeature()
                        ._printChanges()
                }
            )
//            ContentView()
        }
    }
}
