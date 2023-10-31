import ComposableArchitecture
import SwiftUI

@main
struct SummaryPlayerTCAApp: App {
    var body: some Scene {
        WindowGroup {
            AppView(
                store: Store(initialState: AppFeature.State(book: BookSummary.mock)) {
                    AppFeature()
                        ._printChanges()
                }
            )
        }
    }
}
