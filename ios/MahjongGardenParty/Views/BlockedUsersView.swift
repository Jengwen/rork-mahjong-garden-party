import SwiftUI

/// Management screen for the user's block list.
///
/// Apple Guideline 1.2 wants blocking to be a real, reviewable control rather
/// than a one-way door: a reviewer will block someone, then look for the place
/// that lists who is blocked and lets them undo it. This is that place.
///
/// It loads its own data (`loadBlockedProfiles`) rather than relying on whatever
/// the social tab happened to fetch, because the block list is reachable from
/// Settings without the social tab ever being opened.
struct BlockedUsersView: View {
    @Environment(SocialViewModel.self) private var socialVM
    @Environment(ThemeManager.self) private var themeManager

    @State private var isLoading = true
    @State private var userToUnblock: FriendProfile?

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if socialVM.blockedProfiles.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "hand.raised.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Blocked Players")
                            .font(.headline)
                        Text("You haven't blocked anyone. You can block a player from their name in the Social tab or from any message they've sent you.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(socialVM.blockedProfiles) { profile in
                        BlockedUserRow(profile: profile) {
                            userToUnblock = profile
                        }
                    }
                } header: {
                    Text("Blocked")
                } footer: {
                    Text("Blocked players can't message you, and their messages and profile are hidden from you. Unblocking does not restore a previous friendship — you'd need to add them again.")
                }
            }
        }
        .navigationTitle("Blocked Players")
        .navigationBarTitleDisplayMode(.inline)
        .tint(themeManager.currentTheme.primary)
        .task {
            await socialVM.loadBlockedProfiles()
            isLoading = false
        }
        .refreshable {
            await socialVM.loadBlockedProfiles()
        }
        .alert(
            "Unblock \(userToUnblock?.displayName ?? "Player")?",
            isPresented: Binding(
                get: { userToUnblock != nil },
                set: { if !$0 { userToUnblock = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { userToUnblock = nil }
            Button("Unblock") {
                if let profile = userToUnblock {
                    Task { await socialVM.unblockUser(profile.id) }
                }
                userToUnblock = nil
            }
        } message: {
            Text("They'll be able to send you messages and friend requests again.")
        }
    }
}

// MARK: - Row

private struct BlockedUserRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let profile: FriendProfile
    let onUnblock: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(profile.avatarImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .background(
                    Circle().fill(themeManager.currentTheme.primary.opacity(0.1))
                        .frame(width: 44, height: 44)
                )
                .grayscale(1)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.headline)
                Text("Lvl \(profile.level)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Unblock", action: onUnblock)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
        }
        .swipeActions(edge: .trailing) {
            Button("Unblock", action: onUnblock)
                .tint(themeManager.currentTheme.primary)
        }
    }
}
