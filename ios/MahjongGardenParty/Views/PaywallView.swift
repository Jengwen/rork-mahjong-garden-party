import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @State private var store = StoreManager.shared
    @State private var selectedProductID: String = StoreManager.annualID
    @State private var isPurchasing: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    benefits
                    plans
                    purchaseButton
                    if selectedHasTrial {
                        trialEndsLabel
                    }
                    footerLinks
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background(background)
            .navigationTitle("Mahjong Garden Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Subscription", isPresented: errorBinding, actions: {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            }, message: {
                Text(store.errorMessage ?? "")
            })
        }
        .task {
            if store.products.isEmpty {
                await store.loadProducts()
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(themeManager.currentTheme.primary.opacity(0.15))
                    .frame(width: 96, height: 96)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(themeManager.currentTheme.primary)
            }
            .padding(.top, 8)

            Text("Unlock Full Play")
                .font(.system(.largeTitle, design: .serif, weight: .bold))
                .multilineTextAlignment(.center)

            Text("Start with a 7-day free trial. Play unlimited Solo and Multiplayer Mahjong in the garden.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 14) {
            benefitRow(icon: "gift.fill", title: "7-Day Free Trial", subtitle: "Try everything free, cancel anytime before it ends")
            benefitRow(icon: "infinity", title: "Unlimited Games", subtitle: "Play Solo and Multiplayer as much as you like")
            benefitRow(icon: "person.3.fill", title: "Live Multiplayer", subtitle: "Quick match or invite friends to private games")
            benefitRow(icon: "rectangle.stack.fill", title: "All NMJL Cards", subtitle: "Access every supported card year")
            benefitRow(icon: "sparkles", title: "Future Updates", subtitle: "New features as they launch")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 16))
    }

    private func benefitRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(themeManager.currentTheme.primary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var plans: some View {
        VStack(spacing: 12) {
            if store.products.isEmpty && store.isLoading {
                ProgressView().padding()
            } else {
                ForEach(store.products, id: \.id) { product in
                    planCard(product: product)
                }
            }
        }
    }

    private func planCard(product: Product) -> some View {
        let isAnnual = product.id == StoreManager.annualID
        let isSelected = selectedProductID == product.id
        return Button {
            selectedProductID = product.id
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? themeManager.currentTheme.primary : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(isAnnual ? "Annual" : "Monthly")
                            .font(.headline)
                        if isAnnual {
                            Text("Best Value")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(themeManager.currentTheme.primary)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                        if trialEligible(for: product) {
                            Text("7-Day Free Trial")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.18))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }
                    Text(planSubtitle(for: product))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(product.displayPrice)
                    .font(.headline)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(.rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isSelected ? themeManager.currentTheme.primary : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func planSubtitle(for product: Product) -> String {
        let trialSuffix = trialEligible(for: product) ? " · 7 days free, then" : ""
        if product.id == StoreManager.annualID {
            return "Billed yearly\(trialSuffix.isEmpty ? " · Save vs monthly" : trialSuffix)"
        }
        return "Billed monthly\(trialSuffix.isEmpty ? " · Cancel anytime" : trialSuffix)"
    }

    private func trialEligible(for product: Product) -> Bool {
        guard let sub = product.subscription else { return false }
        if let intro = sub.introductoryOffer, intro.paymentMode == .freeTrial { return true }
        // Fallback: show trial badge on annual plan even before App Store Connect offer syncs
        return product.id == StoreManager.annualID
    }

    private var selectedHasTrial: Bool {
        guard let product = store.products.first(where: { $0.id == selectedProductID }) else { return false }
        return trialEligible(for: product)
    }

    private var purchaseButton: some View {
        Button {
            Task { await purchaseSelected() }
        } label: {
            HStack {
                if isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Text(continueLabel)
                        .fontWeight(.bold)
                }
            }
            .font(.title3)
            .frame(maxWidth: .infinity)
            .padding()
            .background(themeManager.currentTheme.primary)
            .foregroundStyle(.white)
            .clipShape(.rect(cornerRadius: 16))
        }
        .disabled(isPurchasing || store.products.isEmpty || store.hasActiveSubscription)
    }

    private var trialEndsDateString: String {
        let endDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: endDate)
    }

    private var trialEndsLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.caption2)
            Text("Free trial ends \(trialEndsDateString)")
                .font(.footnote.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }

    private var continueLabel: String {
        if store.hasActiveSubscription { return "Subscribed" }
        return selectedHasTrial ? "Start 7-Day Free Trial" : "Continue"
    }

    private var footerLinks: some View {
        VStack(spacing: 10) {
            Button("Restore Purchases") {
                Task { await store.restorePurchases() }
            }
            .font(.footnote)

            Text(selectedHasTrial
                 ? "7 days free, then your plan renews automatically until cancelled in Settings. Payment is charged to your Apple ID account."
                 : "Subscriptions auto-renew until cancelled in Settings. Payment is charged to your Apple ID account.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("Terms of Service", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("EULA", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("Privacy Policy", destination: URL(string: "https://www.apple.com/legal/privacy/")!)
            }
            .font(.caption2)
        }
        .padding(.top, 4)
    }

    private func purchaseSelected() async {
        guard let product = store.products.first(where: { $0.id == selectedProductID }) ?? store.products.first else { return }
        isPurchasing = true
        let success = await store.purchase(product)
        isPurchasing = false
        if success { dismiss() }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                themeManager.currentTheme.primary.opacity(0.08),
                Color(.systemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
