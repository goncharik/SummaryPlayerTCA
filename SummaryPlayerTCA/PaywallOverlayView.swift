import ComposableArchitecture
import Dependencies
import StoreKit
import SwiftUI

struct PaywallOverlayFeature: Reducer {
    struct State: Equatable {
        var product: Product
        var isPurchasing = false
    }

    enum Action: Equatable {
        case purchaseButtonTapped
        case purchasedFinished
    }

    @Dependency(\.storeClient) var storeClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .purchaseButtonTapped:
                state.isPurchasing = true
                return .run { [product = state.product] send in
                    try? await storeClient.purchase(product)
                    await send(.purchasedFinished)
                }
            case .purchasedFinished:
                state.isPurchasing = false
                return .none
            }
        }
    }
}

struct PaywallOverlayView: View {
    let store: StoreOf<PaywallOverlayFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(spacing: 0) {
                LinearGradient(gradient: Gradient(colors: [.clear, .white]), startPoint: .top, endPoint: .bottom)
                    .frame(height: 150)

                VStack {
                    Text("Unlock learning")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                        .padding()

                    Text("Grow on the go by listening and reading the world's best ideas")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.black)
                        .padding()

                    Button(action: { viewStore.send(.purchaseButtonTapped) }) {
                        if viewStore.isPurchasing {
                            ProgressView()
                        } else {
                            Text("Start Listening • \(viewStore.product.displayPrice)")
                                .font(.headline)
                                .fontWeight(.bold)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue)
                                .cornerRadius(10)
                                .foregroundColor(.white)
                        }
                    }
                    .frame(height: 60)
                    .allowsHitTesting(!viewStore.isPurchasing)
                    .padding()
                }
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .edgesIgnoringSafeArea(.all)
            }
        }
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        PlayerView(
            store: Store(initialState: PlayerFeature.State(bookSummary: BookSummary.mock)) {
                PlayerFeature()
                    ._printChanges()
            }
        )

//        PaywallOverlayView(
//            store: Store(initialState: PaywallOverlayFeature.State(product: Product.mock)) {
//                PaywallOverlayFeature()
//                    ._printChanges()
//            }
//        )
    }
}
