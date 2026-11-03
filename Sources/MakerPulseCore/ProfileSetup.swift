import Foundation

public enum ProfileSetup {
    public static func validID(_ value: String) -> Bool {
        value.range(of: "^[0-9]{1,32}$", options: .regularExpression) != nil
    }
    public static func adopt(_ profile: Profile, into state: inout LibraryState) throws {
        guard state.preferences.userID.isEmpty, state.profile == nil, state.models.isEmpty, state.followers.isEmpty, state.account == nil, state.activity.isEmpty,
              validID(profile.id), !profile.handle.isEmpty else { throw PulseError.accountMismatch }
        state.preferences.userID = profile.id; state.preferences.handle = profile.handle
        _ = Analytics.ingestProfile(profile, into: &state, at: Date())
    }
}
