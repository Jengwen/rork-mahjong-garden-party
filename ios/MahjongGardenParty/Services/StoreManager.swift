import Foundation
import StoreKit

@Observable
final class StoreManager {
    static let shared = StoreManager()

    static let monthlyID = "mgg_monthly"
    static let annualID = "mgg_annual"
    static let allProductIDs: [String] = [monthlyID, annualID]

    var products: [Product] = []
    var purchasedProductIDs: Set<String> = []
    var isLoading: Bool = false
    var errorMessage: String?

    var hasActiveSubscription: Bool {
        !purchasedProductIDs.isEmpty
    }

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = listenForTransactions()
        Task {
            await loadProducts()
            await refreshPurchasedProducts()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let storeProducts = try await Product.products(for: Self.allProductIDs)
            products = storeProducts.sorted { lhs, rhs in
                if lhs.id == Self.annualID { return false }
                if rhs.id == Self.annualID { return true }
                return lhs.price < rhs.price
            }
        } catch {
            errorMessage = "Unable to load subscriptions: \(error.localizedDescription)"
        }
    }

    func refreshPurchasedProducts() async {
        var active: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.revocationDate == nil {
                if let exp = transaction.expirationDate, exp < Date() { continue }
                active.insert(transaction.productID)
            }
        }
        purchasedProductIDs = active
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshPurchasedProducts()
                    return true
                } else {
                    errorMessage = "Purchase could not be verified."
                    return false
                }
            case .userCancelled:
                return false
            case .pending:
                errorMessage = "Purchase is pending approval."
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
            return false
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshPurchasedProducts()
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self.refreshPurchasedProducts()
                }
            }
        }
    }
}
