import SwiftUI
import MakerPulseCore

struct PreferencesView: View {
    @Environment(\.appTextScale) private var textScale
    @EnvironmentObject var model: AppModel
    @State private var token = ""
    @State private var email = ""
    @State private var code = ""
    @State private var tfaKey: String?
    @State private var codeSent = false
    @State private var authenticating = false
    @State private var authMessage: String?
    @State private var customPolling = 10
    @State private var pollingError: String?
    @State private var publicUserID = ""
    @State private var settingUpProfile = false
    @State private var profileSetupError: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) { Text("Settings").appFont(size: 32, weight: .semibold); Text("MakerGlance \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development") · build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")").foregroundStyle(Palette.secondaryText) }
                TextSizeSettings()
                AppearanceSettings()
                Surface {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Images", systemImage: "photo").appFont(.headline)
                            Text("Images retry automatically after a connection failure. Refresh also retries missing images.").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                        }
                        Spacer()
                        Button("Reload images") { ImageRefresh.shared.retry() }
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 18) {
                        Label("Monitoring", systemImage: "antenna.radiowaves.left.and.right").appFont(.headline)
                        if model.state.preferences.userID.isEmpty {
                            Text("Choose your creator profile").appFont(.headline)
                            Text("Connect your own Bambu account below to identify your profile, or use its numeric public user ID without signing in. A library monitors one creator so histories cannot be mixed.").appFont(.callout).foregroundStyle(Palette.secondaryText)
                            HStack {
                                TextField("Numeric MakerWorld user ID", text: $publicUserID).textFieldStyle(.roundedBorder).accessibilityLabel("Public MakerWorld numeric user ID")
                                Button("Use public profile") { Task {
                                    settingUpProfile = true; defer { settingUpProfile = false }
                                    do { try await model.configurePublicProfile(id: publicUserID); profileSetupError = nil }
                                    catch { profileSetupError = error.localizedDescription }
                                } }.disabled(settingUpProfile || !ProfileSetup.validID(publicUserID.trimmingCharacters(in: .whitespacesAndNewlines)))
                            }
                            if settingUpProfile { ProgressView().controlSize(.small) }
                            if let profileSetupError { Text(profileSetupError).appFont(.callout).foregroundStyle(Palette.negative) }
                        } else {
                            HStack { Text("Profile"); Spacer(); Text("@\(model.state.preferences.handle)").foregroundStyle(Palette.secondaryText) }
                        }
                        Picker("Refresh profile and models", selection: Binding(get: { model.state.preferences.pollingMinutes }, set: { model.setPollingMinutes($0) })) {
                            ForEach(PollingPolicy.presets, id: \.self) { Text(PollingPolicy.title($0)).tag($0) }
                            if !PollingPolicy.presets.contains(model.state.preferences.pollingMinutes) { Text(PollingPolicy.title(model.state.preferences.pollingMinutes) + " · custom").tag(model.state.preferences.pollingMinutes) }
                        }.frame(maxWidth: 450, alignment: .leading)
                        HStack {
                            Text("Custom minutes")
                            TextField("10", value: $customPolling, format: .number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width: 80)
                            Button("Apply") { if PollingPolicy.valid(customPolling) { model.setPollingMinutes(customPolling); pollingError = nil } else { pollingError = "Choose 5–1440 minutes (up to 24 hours)." } }
                            Text("5 minutes to 24 hours").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                        }
                        if let pollingError { Text(pollingError).appFont(size: 12).foregroundStyle(Palette.negative) }
                        if let next = model.nextRefreshDate { Text("Next automatic check around \(next.formatted(date: .omitted, time: .shortened)) · brief pacing jitter avoids request bursts").appFont(size: 12).foregroundStyle(Palette.secondaryText) }
                        DisclosureGroup("How background monitoring works") { Text("Followers are checked hourly, or whenever you click Refresh. Requests are paced and backed off after rate limits. Monitoring continues when the window is closed, while MakerGlance is running; quitting or sleeping this Mac pauses checks. These are local notifications, not server push.").appFont(size: 12).foregroundStyle(Palette.secondaryText).padding(.top, 8) }.appFont(size: 12).foregroundStyle(Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack { Label("Notifications & milestones", systemImage: "bell.badge").appFont(.headline); Spacer(); Text(model.notificationStatus).appFont(size: 12).foregroundStyle(Palette.secondaryText) }
                        HStack { Toggle("Send local notifications", isOn: preference(\.notificationsEnabled)).toggleStyle(.switch); Spacer(); Button("Allow notifications…") { Task { await model.enableNotifications() } } }
                        Toggle("Newly observed followers", isOn: preference(\.notifyFollowers))
                        Toggle("Profile count milestones", isOn: preference(\.notifyMilestones))
                        HStack { Text("Milestone interval"); TextField("1000", value: milestone, format: .number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width: 100); Text("likes, design downloads/prints, boosts, saves & followers").appFont(size: 12).foregroundStyle(Palette.secondaryText) }
                        DisclosureGroup("Milestone behavior") { Text("Choose any positive interval, such as 1000. Crossing several intervals in one refresh creates a single alert. Initial imports stay quiet, and counts that drop and recover do not repeat old alerts. Model alerts are configured on each model.").appFont(size: 12).foregroundStyle(Palette.secondaryText).padding(.top, 8) }.appFont(size: 12).foregroundStyle(Palette.secondaryText)
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack { Label("Bambu connection", systemImage: "lock.shield").appFont(.headline); Spacer(); Text(model.connection).appFont(size: 12).foregroundStyle(Palette.accent) }
                        DisclosureGroup("About your connection") { Text("Your public profile, models, and followers work without signing in. If Bambu later restricts access, you can connect using the existing Bambu email-code flow or a MakerWorld session token. Sessions are validated and stored only in your Mac's Keychain.").appFont(size: 12).foregroundStyle(Palette.secondaryText).padding(.top, 8) }.appFont(size: 12).foregroundStyle(Palette.secondaryText)
                        DisclosureGroup("Connect with email code") {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("Bambu account email", text: $email).textFieldStyle(.roundedBorder).frame(maxWidth: 350)
                                if codeSent {
                                    SecureField(tfaKey == nil ? "Email verification code" : "Authenticator code", text: $code).textFieldStyle(.roundedBorder).frame(maxWidth: 350)
                                    Button(tfaKey == nil ? "Verify and save session" : "Verify MFA") { Task { await verifyCode() } }.disabled(code.isEmpty || authenticating)
                                } else { Button("Send email code") { Task { await sendCode() } }.disabled(!email.contains("@") || authenticating) }
                            }.padding(.top, 12)
                        }
                        DisclosureGroup("Connect with an existing session token") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Paste the token cookie from your own signed-in MakerWorld session. The existing BambuBoard fallback uses the same bearer-token format. Never share it or commit it to GitHub.").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                                SecureField("Session token", text: $token).textFieldStyle(.roundedBorder)
                                Button("Validate & save to Keychain") { Task { await saveToken() } }.disabled(token.isEmpty || authenticating)
                            }.padding(.top, 12)
                        }
                        if authenticating || model.restoringSession { ProgressView().controlSize(.small) }
                        Text(model.authenticationStatus).appFont(size: 12).foregroundStyle(Palette.secondaryText)
                        if model.privateSyncing { Label("Session is saved. Inbox and rewards are loading in the background…", systemImage: "arrow.triangle.2.circlepath").appFont(size: 12).foregroundStyle(Palette.accent) }
                        if let authMessage { Text(authMessage).appFont(size: 12).foregroundStyle(Palette.secondaryText).textSelection(.enabled) }
                        Button("Remove saved session", role: .destructive) { model.disconnect() }
                    }.disabled(authenticating || model.restoringSession || model.isDemo)
                }
                Surface {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Activity & inbox notifications", systemImage: "tray").appFont(.headline)
                        Text("Choose which events appear in Activity and send alerts. Printer/device updates are off by default. These preferences are local. MakerGlance never marks notifications read or changes notification settings on MakerWorld.").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210 * CGFloat(max(1, textScale))))], alignment: .leading, spacing: 12) {
                            ForEach(EventKind.allCases) { kind in
                                Toggle(kind.title, isOn: Binding(get: { (model.state.account?.preferences ?? AccountPreferences()).eventNotifications.contains(kind) }, set: { model.setEventNotification(kind, enabled: $0) }))
                            }
                        }.toggleStyle(.checkbox)
                        DisclosureGroup("How duplicate events are handled") { Text("Boost events that provide the same model ID and resulting boost count as a metric alert are merged. Other feed categories remain identifiable by their API event type.").appFont(size: 12).foregroundStyle(Palette.secondaryText).padding(.top, 8) }.appFont(size: 12).foregroundStyle(Palette.secondaryText)
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Rewards notifications", systemImage: "sparkles").appFont(.headline)
                        DisclosureGroup("Balance changes and reasons") { Text("Notify on increases and decreases after the first verified baseline. Reasons use transaction IDs and exact decimal reconciliation. Missing or unmatched reasons stay unavailable.").appFont(size: 12).foregroundStyle(Palette.secondaryText).padding(.top, 8) }.appFont(size: 12).foregroundStyle(Palette.secondaryText)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 245 * CGFloat(max(1, textScale))))], alignment: .leading, spacing: 12) {
                            ForEach(RewardMetric.allCases) { metric in
                                Toggle(metric.title, isOn: Binding(get: { (model.state.account?.preferences ?? AccountPreferences()).balanceNotifications.contains(metric) }, set: { model.setBalanceNotification(metric, enabled: $0) }))
                            }
                        }.toggleStyle(.checkbox)
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Your data belongs here", systemImage: "internaldrive").appFont(.headline)
                        Text("SQLite stores snapshots, watch preferences, first-observed follower dates, and activity locally. One year of observations is retained. No analytics or credentials are uploaded to the app's repository.").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                        Text(model.isDemo ? "Demo library · temporary local storage" : model.databaseURL.path).appFont(.caption2, design: .monospaced).textSelection(.enabled).foregroundStyle(Palette.secondaryText)
                        HStack { Button("Show local database") { NSWorkspace.shared.activateFileViewerSelecting([model.databaseURL]) }.disabled(model.isDemo); Link("View source ↗", destination: URL(string: "https://github.com/t0nyz0/MakerGlance")!) }
                        Divider()
                        Text("API limitations").appFont(.callout, weight: .semibold)
                        Text("Historical data begins with this installation. Collection counts do not reveal individual collections or events. Follow dates are unavailable. MakerWorld endpoints are undocumented and may change; failed or incomplete crawls never replace the last complete follower baseline.").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                    }
                }
            }.padding(30).frame(maxWidth: 930, alignment: .leading).frame(maxWidth: .infinity, alignment: .center)
        }.onAppear { customPolling = model.state.preferences.pollingMinutes }
    }
    var milestone: Binding<Int> {
        Binding(get: { model.state.preferences.milestoneStep }, set: { model.state.preferences.milestoneStep = max(1, min(1_000_000_000, $0)); model.save() })
    }
    func preference<T>(_ key: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { model.state.preferences[keyPath: key] }, set: { model.state.preferences[keyPath: key] = $0; model.save() })
    }
    func sendCode() async {
        authenticating = true; defer { authenticating = false }
        do { try await model.api.sendEmailCode(email: email); codeSent = true; authMessage = "Check your Bambu account email for the verification code." }
        catch { authMessage = error.localizedDescription }
    }
    func verifyCode() async {
        authenticating = true; defer { authenticating = false }
        do {
            let result: AuthResult
            if let tfaKey { result = try await model.api.mfa(key: tfaKey, code: code) }
            else { result = try await model.api.login(email: email, code: code) }
            code = ""
            if let key = result.tfaKey { tfaKey = key; authMessage = "Enter your authenticator code to complete MFA." }
            if let token = result.token { try await model.connect(token: token); authMessage = "Session validated and saved securely."; codeSent = false; email = ""; tfaKey = nil }
        } catch { code = ""; authMessage = error.localizedDescription }
    }
    func saveToken() async {
        authenticating = true; defer { authenticating = false; token = "" }
        do { try await model.connect(token: token); authMessage = "Session validated and saved securely. Private feeds load in the background." }
        catch { authMessage = error.localizedDescription }
    }
}
