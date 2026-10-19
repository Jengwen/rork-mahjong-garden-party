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

    /// True when the signed-in account has active access recorded server-side
    /// (`user_entitlements`) — e.g. a subscription bought on the web app via
    /// Stripe. Lets one membership unlock both iPhone and web.
    var serverEntitled: Bool = false

    var hasActiveSubscription: Bool {
        !purchasedProductIDs.isEmpty || serverEntitled
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
        var originalIDs: Set<UInt64> = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.revocationDate == nil {
                if let exp = transaction.expirationDate, exp < Date() { continue }
                active.insert(transaction.productID)
                originalIDs.insert(transaction.originalID)
            }
        }
        purchasedProductIDs = active
        await syncWithServer(originalTransactionIDs: originalIDs)
    }

    // MARK: - Cross-platform entitlement sync (web app)

    /// Reports this device's App Store subscription to the server (so the web app
    /// unlocks for the same account), then reads back the account's server-side
    /// entitlement (so a web/Stripe subscription unlocks the app). Best-effort:
    /// failures leave the StoreKit result as the source of truth on this device.
    @MainActor
    func syncWithServer(originalTransactionIDs: Set<UInt64>) async {
        let supabase = SupabaseService.shared
        guard supabase.currentUserId != nil else {
            serverEntitled = false
            return
        }
        nonisolated struct SyncPayload: Encodable { let originalTransactionId: String }
        for id in originalTransactionIDs {
            do {
                try await supabase.client.functions.invoke(
                    "app-store-sync",
                    options: .init(body: SyncPayload(originalTransactionId: String(id)))
                )
            } catch {
                print("ℹ️ app-store-sync (non-fatal): \(error)")
            }
        }
        await refreshServerEntitlement()
    }

    @MainActor
    func refreshServerEntitlement() async {
        let supabase = SupabaseService.shared
        guard let userId = supabase.currentUserId else {
            serverEntitled = false
            return
        }
        nonisolated struct EntitlementRow: Decodable, Sendable {
            let status: String
            let expires_at: String?
        }
        do {
            let rows: [EntitlementRow] = try await supabase.client
                .from("user_entitlements")
                .select("status,expires_at")
                .eq("user_id", value: userId.uuidString.lowercased())
                .execute()
                .value
            let activeStatuses: Set<String> = ["active", "trialing", "grace_period", "canceled_pending"]
            serverEntitled = rows.contains { row in
                guard activeStatuses.contains(row.status) else { return false }
                guard let exp = ISO8601.date(from: row.expires_at) else { return row.expires_at == nil }
                return exp > Date()
            }
        } catch {
            // Table not deployed yet or offline — keep the last known value.
            print("ℹ️ refreshServerEntitlement (non-fatal): \(error)")
        }
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        do {
            // Tag the purchase with the signed-in account so the server can bind
            // this subscription to exactly this user (checked in app-store-sync).
            let userId = await MainActor.run { SupabaseService.shared.currentUserId }
            var options: Set<Product.PurchaseOption> = []
            if let userId { options.insert(.appAccountToken(userId)) }
            let result = try await product.purchase(options: options)
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
