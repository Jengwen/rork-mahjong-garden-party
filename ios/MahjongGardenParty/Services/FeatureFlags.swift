import Foundation

/// Compile-time feature switches.
///
/// Keeping these in one place means turning a feature back on is a one-line
/// change rather than an archaeology exercise across the view layer.
enum FeatureFlags {

    /// Live multiplayer (online 4-player games, invites, lobby, resume).
    ///
    /// Temporarily disabled for launch: the host intermittently fails to collect
    /// a remote player's Charleston pass, which strands the whole table. Solo
    /// play is unaffected, so the app ships without it while that is fixed.
    ///
    /// HOW THIS IS SET
    /// The value is decided at COMPILE time by the Codemagic workflow, not by
    /// editing this file:
    ///
    ///   • `ios-workflow` (Release)       → MULTIPLAYER_BETA not defined → false
    ///   • `ios-multiplayer-beta` (Beta)  → MULTIPLAYER_BETA defined     → true
    ///
    /// Both build from the same commit on `main`, so multiplayer work can land
    /// continuously without branching — it simply stays dormant in the build that
    /// real users get. And because this is a `#if` rather than a runtime toggle,
    /// a release build physically cannot ship with multiplayer on; there is no
    /// switch to forget to flip.
    ///
    /// WHEN MULTIPLAYER IS READY
    /// Delete the `#if` and leave `static let multiplayerEnabled = true`, then
    /// drop the `ios-multiplayer-beta` workflow from codemagic.yaml.
    ///
    /// To test multiplayer in Xcode locally, add MULTIPLAYER_BETA under
    /// Build Settings → Active Compilation Conditions for the Debug config.
    #if MULTIPLAYER_BETA
    static let multiplayerEnabled = true
    #else
    static let multiplayerEnabled = false
    #endif

    /// Copy shown wherever a multiplayer entry point is closed off.
    static let multiplayerComingSoonTitle = "Coming Soon"
    static let multiplayerComingSoonMessage =
        "Live multiplayer is almost ready! We're putting the finishing touches on it. In the meantime, enjoy Solo Practice against AI opponents."
}
