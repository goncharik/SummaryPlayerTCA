import ComposableArchitecture
import SwiftUI
import StoreKit

struct AppFeature: Reducer {
    struct State {
        var book: BookSummary
        var errorMessage: String?
        var isLoadingSubscriptions: Bool = false
        var player: PlayerFeature.State?
        var paywallOverlay: PaywallOverlayFeature.State?
    }

    enum Action {
        case player(PlayerFeature.Action)
        case paywallOverlay(PaywallOverlayFeature.Action)

        case onAppear
        case onDisappear
        case retryButtonTapped

        case gotProduct(Product)
        case finishLoading
        case storeClientActiveTransaction(String)
        case storeClientError(Error)
    }

    @Dependency(\.storeClient) var storeClient
    private enum CancelID { case storeUpdates }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .player, .paywallOverlay: return .none

            case .finishLoading:
                state.isLoadingSubscriptions = false
                state.player = PlayerFeature.State(bookSummary: state.book)
                return .none

            case let .gotProduct(product):
                state.paywallOverlay = PaywallOverlayFeature.State(product: product)
                return .none

            case .storeClientActiveTransaction(let productID):
                if state.book.purchaseId == productID {
                    state.paywallOverlay = nil
                }
                return .none

            case .onAppear, .retryButtonTapped:
                state.errorMessage = nil
                state.isLoadingSubscriptions = true
                return .run { [book = state.book] send in
                    do {
                        let product = try await storeClient.fetchProduct(book.purchaseId)
                        await send(.gotProduct(product))
                        let activeTransactions = try await storeClient.fetchActiveTransactions()
                        for transaction in activeTransactions {
                            await send(.storeClientActiveTransaction(transaction))
                        }
                        await send(.finishLoading)
                    } catch {
                        await send(.storeClientError(error))
                    }

                    for await transaction in self.storeClient.updates() {
                        await send(.storeClientActiveTransaction(transaction))
                    }
                }
                .cancellable(id: CancelID.storeUpdates)

            case .onDisappear:
                return .cancel(id: CancelID.storeUpdates)
            case .storeClientError:
                state.isLoadingSubscriptions = false
                state.errorMessage = "Error on fetching subscriptions. Please retry"
                return .none
            }
        }
        .ifLet(\.paywallOverlay, action: /Action.paywallOverlay) {
            PaywallOverlayFeature()
        }
        .ifLet(\.player, action: /Action.player) {
            PlayerFeature()
        }
    }
}

struct AppView: View {
    let store: StoreOf<AppFeature>
    @ObservedObject var viewStore: ViewStore<ViewState, AppFeature.Action>

    struct ViewState: Equatable {
        let isLoading: Bool
        let errorMessage: String?

        init(state: AppFeature.State) {
            self.isLoading = state.isLoadingSubscriptions
            self.errorMessage = state.errorMessage
        }
    }

    public init(store: StoreOf<AppFeature>) {
        self.store = store
        self.viewStore = ViewStore(self.store, observe: ViewState.init)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let errorMessage = viewStore.errorMessage {
                VStack {
                    Text(errorMessage)
                    Button("Retry", action: { viewStore.send(.retryButtonTapped) })
                }
            } else {
                if viewStore.isLoading {
                    ProgressView()
                } else {
                    IfLetStore(
                        self.store.scope(state: \.player, action: AppFeature.Action.player),
                        then: PlayerView.init(store:)
                    )

                    IfLetStore(
                        self.store.scope(state: \.paywallOverlay, action: AppFeature.Action.paywallOverlay),
                        then: PaywallOverlayView.init(store:)
                    )
                }
            }
        }
        .onAppear {
            viewStore.send(.onAppear)
        }
        .onDisappear {
            viewStore.send(.onDisappear)
        }
    }
}

#Preview {
    AppView(store: Store(initialState: AppFeature.State(book: BookSummary.mock)) {
        AppFeature()
            ._printChanges()
    })
}
