import Dependencies
import Foundation
import StoreKit

struct StoreClient {
    var updates: @Sendable () -> AsyncStream<String>
    var fetchProduct: @Sendable (_ productId: String) async throws -> Product
    var fetchActiveTransactions: @Sendable () async throws -> Set<String>
    var purchase: @Sendable (Product) async throws -> Void
}



extension StoreClient: DependencyKey {
    class Context {
        var continuation: AsyncStream<String>.Continuation?

        init() {}
    }

    static var liveValue: StoreClient {
        let context = Context()

        return StoreClient(
            updates: {
                let stream = AsyncStream<String> { continuation in
                    context.continuation = continuation
                    
                    let task = Task {
                        for await update in StoreKit.Transaction.updates {
                            if let transaction = try? update.payloadValue {
                                continuation.yield(transaction.productID)
                                await transaction.finish()
                            }
                        }
                    }
                    continuation.onTermination = { _ in
                        task.cancel()
                    }
                }
                return stream
            },
            fetchProduct: { productId in
                struct MissingProductError: Error {}
                guard let product = try await Product.products(for: [productId]).first
                else { throw MissingProductError() }
                return product
            },
            fetchActiveTransactions: {
                var activeTransactions: Set<String> = []

                for await entitlement in StoreKit.Transaction.currentEntitlements {
                    if let transaction = try? entitlement.payloadValue {
                        activeTransactions.insert(transaction.productID)
                    }
                }

                return activeTransactions
            },
            purchase: { product in
                let result = try await product.purchase()
                switch result {
                case .success(let verificationResult):
                    if let transaction = try? verificationResult.payloadValue {
                        context.continuation?.yield(transaction.productID)
                        await transaction.finish()
                    }
                case .userCancelled:
                    break
                case .pending:
                    break
                @unknown default:
                    break
                }
            }
        )
    }
}

extension DependencyValues {
    var storeClient: StoreClient {
        get { self[StoreClient.self] }
        set { self[StoreClient.self] = newValue }
    }
}

@MainActor
final class StoreClientImpl: ObservableObject {
    @Published private(set) var products: [Product] = []
    private var updates: Task<Void, Never>?

    init() {
        updates = Task {
            for await update in StoreKit.Transaction.updates {
                if let transaction = try? update.payloadValue {
                    activeTransactions.insert(transaction)
                    await transaction.finish()
                }
            }
        }
    }

    deinit {
        updates?.cancel()
    }

    func fetchProducts() async {
        do {
            products = try await Product.products(
                for: [
                    "me.honcharenko.SummaryPlayerTCA.subscription",
                ]
            )
        } catch {
            products = []
        }
    }

    @Published private(set) var activeTransactions: Set<StoreKit.Transaction> = []

    func fetchActiveTransactions() async {
        var activeTransactions: Set<StoreKit.Transaction> = []

        for await entitlement in StoreKit.Transaction.currentEntitlements {
            if let transaction = try? entitlement.payloadValue {
                activeTransactions.insert(transaction)
            }
        }

        self.activeTransactions = activeTransactions
    }

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verificationResult):
            if let transaction = try? verificationResult.payloadValue {
                activeTransactions.insert(transaction)
                await transaction.finish()
            }
        case .userCancelled:
            break
        case .pending:
            break
        @unknown default:
            break
        }
    }
}
