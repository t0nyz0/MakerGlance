import SwiftUI
import Charts
import MakerPulseCore

struct RewardsView: View {
    @Environment(\.appTextScale) private var textScale
    @EnvironmentObject var model: AppModel
    @State private var showTransactions = 100
    var balance: RewardBalance? { model.state.account?.balance?.balance }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rewards & cash").appFont(size: 32, weight: .semibold)
                        Text("Private balances, transaction reasons and model context.").foregroundStyle(Palette.secondaryText)
                    }
                    Spacer()
                    Label("STORED ON THIS MAC", systemImage: "lock.shield").appFont(.caption, weight: .semibold).foregroundStyle(Palette.accent)
                }
                Surface {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text(model.rewardsStatus).appFont(.callout); Spacer(); if model.privateSyncing { ProgressView().controlSize(.small) }; Button("Connection settings") { model.destination = .settings } }
                        Text("The cash redemption estimate is supplied by MakerWorld and is separate from wallet money. A missing balance stays unavailable. This app only reads data; it cannot redeem points, withdraw, transfer, or spend.").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 245 * CGFloat(max(1, textScale))), spacing: 14)], spacing: 14) {
                    ForEach(RewardMetric.allCases) { value in
                        Surface {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack { Image(systemName: value.isCash ? "banknote" : "sparkles").foregroundStyle(value == .exclusivePoints ? Palette.orange : Palette.accent); Spacer(); Text(value.title).appFont(size: 12).foregroundStyle(Palette.secondaryText) }
                                Text(format(balance?[value], metric: value)).appFont(size: 27, weight: .semibold, design: .default).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                                Text(balance?[value] == nil ? "Unavailable until verified" : value.isCash ? balance?.currency(for: value) ?? "Currency unavailable" : "points · exact decimal precision").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                                if let date = model.state.account?.balanceDates[value] {
                                    Text("Verified \(date.formatted(date: .abbreviated, time: .shortened))\(date != model.state.account?.balance?.date ? " · older observation" : "")").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                Text(model.walletStatus).appFont(size: 12).foregroundStyle(Palette.secondaryText)
                WalletHistoryView(rows: model.state.account?.walletTransactions ?? [])
                RewardHistoryMosaic(samples: model.balanceHistory, balance: balance)
                Surface {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { Text("Points transactions").appFont(.headline); Spacer(); Text("Read-only local copy").appFont(size: 12).foregroundStyle(Palette.secondaryText) }
                        Text("Reasons and model details come from the ledger. Exact point totals and posting windows match balance changes even when server IDs are absent; local fingerprints preserve identical entries. Ambiguous changes remain pending, with no guessed attribution. Point alerts wait up to 30 minutes for a ledger match, then report the pending state once. Later details update the saved activity quietly. Cash-estimate changes do not imply wallet cash was paid.").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                        if let transactions = model.state.account?.transactions, !transactions.isEmpty {
                            LazyVStack(spacing: 0) {
                                ForEach(transactions.prefix(showTransactions)) { transaction in
                                    RewardTransactionRow(transaction: transaction)
                                    Divider().opacity(0.5)
                                }
                            }
                            if transactions.count > showTransactions { Button("Show more transactions") { showTransactions += 100 } }
                        } else { EmptyPanel(title: "No verified ledger yet", detail: "Connect a Bambu session to read the private transaction feed. No sample balances or transactions are substituted.", symbol: "list.bullet.rectangle") }
                    }
                }
            }.padding(30)
        }
    }
    func format(_ value: Decimal?, metric: RewardMetric) -> String {
        guard let value else { return "—" }
        if metric.isCash, let currency = balance?.currency(for: metric) { return "\(DisplayNumber.decimal(value)) \(currency)" }
        return DisplayNumber.decimal(value)
    }
    func signed(_ value: Decimal?) -> String { guard let value else { return "unavailable" }; return (value > 0 ? "+" : "") + DisplayNumber.decimal(value) }
}

private struct WalletHistoryView: View {
    let rows: [WalletTransaction]
    @State private var limit = 50
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Text("Wallet income history").appFont(.headline); Spacer(); Text("Read only · server entry IDs").appFont(size: 12).foregroundStyle(Palette.secondaryText) }
                Text("Income, pending balances and transfers remain distinct. A balance-change reason is shown only when observed wallet entries and status transitions reconcile exactly in the same currency. Missing payout or redemption links stay unavailable.").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                if rows.isEmpty { Text("No verified wallet income entries yet.").appFont(size: 12).foregroundStyle(Palette.secondaryText).padding(.vertical, 15) }
                else {
                    LazyVStack(spacing: 0) {
                        ForEach(rows.prefix(limit)) { row in
                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(row.reason).appFont(.callout, weight: .medium)
                                    Text("Entry \(row.id) · \(row.date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Original date unavailable")").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 5) {
                                    Text("\(DisplayNumber.decimal(row.amount)) \(row.currency)").appFont(.callout).monospacedDigit()
                                    Text(row.statusTitle).appFont(size: 12).foregroundStyle(row.status == 2 ? Palette.orange : .secondary)
                                }
                            }.padding(.vertical, 12)
                            Divider().opacity(0.5)
                        }
                    }
                    if rows.count > limit { Button("Show more wallet entries") { limit += 50 } }
                }
            }
        }
    }
}

struct RewardModelLink: View {
    @EnvironmentObject var model: AppModel
    let id: String?
    let title: String
    var body: some View {
        if let id, let design = model.state.models.first(where: { $0.id == id }) {
            Button { model.selectedModel = design } label: { Label(title, systemImage: "arrow.up.right") }.buttonStyle(.plain).foregroundStyle(Palette.accent)
        } else if let id, ProfileSetup.validID(id), let url = URL(string: "https://makerworld.com/en/models/\(id)") {
            Link(destination: url) { Label(title, systemImage: "arrow.up.right") }.foregroundStyle(Palette.accent)
        } else { Text(title) }
    }
}
struct RewardTransactionRow: View {
    @EnvironmentObject var model: AppModel
    let transaction: RewardTransaction
    var media: ActivityPresentation { transaction.presentation ?? ActivityPresentation() }
    var design: Design? { model.state.models.first { $0.id == transaction.modelID } }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) { details; amounts.frame(width: 160, alignment: .trailing) }
            VStack(alignment: .leading, spacing: 10) { details; amounts }
        }.padding(.vertical, 14)
    }
    var details: some View {
        HStack(alignment: .top, spacing: 14) {
            if transaction.modelID != nil {
                RemoteImage(url: media.modelCover ?? design?.cover, pixelWidth: 160).frame(width: 76, height: 64).clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(alignment: .bottomTrailing) {
                        if media.actorAvatar != nil { RemoteImage(url: media.actorAvatar, symbol: "person.fill", pixelWidth: 80).frame(width: 25, height: 25).clipShape(Circle()).overlay(Circle().stroke(Palette.surface, lineWidth: 2)) }
                    }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(transaction.reason ?? "MakerWorld ledger entry (\(transaction.type))").appFont(.callout, weight: .medium).textSelection(.enabled)
                if let title = media.modelTitle ?? design?.title { RewardModelLink(id: transaction.modelID, title: title).appFont(.callout) }
                if let actor = media.actorName { Text("\(transaction.type == "boost_exchange_point" ? "Boost from" : "Profile contributor") \(actor)\(media.actorHandle.map { " · @\($0)" } ?? "")").appFont(.caption).foregroundStyle(Palette.secondaryText) }
                Text(transaction.date.map { "Ledger time (local) " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "Ledger timestamp not supplied").appFont(.caption).foregroundStyle(Palette.secondaryText)
                if let created = transaction.createdAt, transaction.date.map({ abs(created.timeIntervalSince($0)) >= 60 }) ?? true { Text("Recorded (local) " + created.formatted(date: .abbreviated, time: .shortened)).appFont(.caption).foregroundStyle(Palette.secondaryText) }
                if let earned = transaction.earningDayUTC { Text("Incentive date " + earned + " · UTC").appFont(.caption).foregroundStyle(Palette.secondaryText) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    var amounts: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("Regular " + signed(transaction.regularChange)).foregroundStyle((transaction.regularChange ?? 0) < 0 ? Palette.negative : Palette.secondaryText)
            Text("Exclusive " + signed(transaction.exclusiveChange)).foregroundStyle((transaction.exclusiveChange ?? 0) < 0 ? Palette.negative : Palette.accent)
        }.appFont(.callout, weight: .medium).monospacedDigit()
    }
    func signed(_ value: Decimal?) -> String { value.map { ($0 > 0 ? "+" : "") + DisplayNumber.decimal($0) } ?? "—" }
}
