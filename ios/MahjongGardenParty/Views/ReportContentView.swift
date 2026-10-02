import SwiftUI

/// Reasons offered when reporting content. Kept short and concrete — a long
/// list makes people pick "Other" and write nothing, which produces reports
/// that can't be triaged.
nonisolated enum ReportReason: String, CaseIterable, Identifiable, Sendable {
    case harassment = "Harassment or bullying"
    case hateSpeech = "Hate speech"
    case sexualContent = "Sexual or explicit content"
    case spam = "Spam or scam"
    case impersonation = "Impersonation"
    case threat = "Violence or threats"
    case other = "Something else"

    var id: String { rawValue }
}

/// What is being reported. Mirrors `content_reports.content_type`.
nonisolated enum ReportedContentKind: String, Sendable {
    case message
    case displayName = "display_name"
    case avatar
    case other
}

/// Report sheet shared by the message list and the player rows.
///
/// Apple Guideline 1.2 asks for a mechanism to report objectionable content;
/// this is that mechanism. Two details matter for it to be genuinely useful
/// rather than decorative:
///
///   • it carries a SNAPSHOT of the offending content, so the report survives
///     the reported user deleting the message a moment later; and
///   • it offers blocking as a follow-up step, because someone who was just
///     harassed usually wants both, and making them hunt for the second one
///     is how people end up only half-protected.
struct ReportContentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager

    let socialVM: SocialViewModel
    /// Who is being reported.
    let reportedUserId: String
    let reportedDisplayName: String
    let contentKind: ReportedContentKind
    /// Row id of the offending content, where one exists.
    let contentId: String?
    /// Verbatim copy of the offending content at report time.
    let contentSnapshot: String?

    @State private var selectedReason: ReportReason = .harassment
    @State private var details: String = ""
    @State private var isSubmitting = false
    @State private var didSubmit = false
    @State private var alsoBlock = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Reports are reviewed by our team. Thanks for helping keep Mahjong Garden Party welcoming.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("What's wrong?") {
                    Picker("Reason", selection: $selectedReason) {
                        ForEach(ReportReason.allCases) { reason in
                            Text(reason.rawValue).tag(reason)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Anything else we should know? (optional)") {
                    TextField("Add details", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let snapshot = contentSnapshot, !snapshot.isEmpty {
                    Section("Reported content") {
                        Text(snapshot)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(6)
                    }
                }

                Section {
                    Toggle("Also block \(reportedDisplayName)", isOn: $alsoBlock)
                } footer: {
                    Text("Blocking hides their messages and profile from you, and stops them contacting you.")
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if isSubmitting { ProgressView().padding(.trailing, 4) }
                            Text(isSubmitting ? "Submitting…" : "Submit Report")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isSubmitting)
                }
            }
            .navigationTitle("Report \(reportedDisplayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Report Submitted", isPresented: $didSubmit) {
                Button("OK") { dismiss() }
            } message: {
                Text(alsoBlock
                     ? "Thanks — we'll review this. \(reportedDisplayName) has also been blocked."
                     : "Thanks — we'll review this.")
            }
        }
    }

    /// Report / block actions for a player row, as a context menu.
    ///
    /// Factored out so every place a player appears — friends list, message
    /// list, search results, friend requests — offers the same two actions.
    /// Apple checks that blocking is reachable from wherever a user is visible,
    /// not just from one screen.
    @ViewBuilder
    static func playerContextMenu(
        profile: FriendProfile,
        onReport: @escaping () -> Void,
        onBlock: @escaping () -> Void
    ) -> some View {
        Button {
            onReport()
        } label: {
            Label("Report \(profile.displayName)", systemImage: "flag")
        }
        Button(role: .destructive) {
            onBlock()
        } label: {
            Label("Block \(profile.displayName)", systemImage: "hand.raised")
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }

        let ok = await socialVM.reportContent(
            reportedUserId: reportedUserId,
            contentType: contentKind.rawValue,
            contentId: contentId,
            contentSnapshot: contentSnapshot,
            reason: selectedReason.rawValue,
            details: details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : details
        )

        if ok && alsoBlock {
            await socialVM.blockUser(reportedUserId)
        }
        if ok {
            didSubmit = true
        } else {
            // reportContent already set socialVM.errorMessage; just close so the
            // host view can surface it rather than trapping the user in a sheet.
            dismiss()
        }
    }
}
