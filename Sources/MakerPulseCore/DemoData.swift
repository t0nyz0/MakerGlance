import Foundation

// Original fictional fixtures. No account data, copied inbox, credentials or
// remote images are used to build documentation or the offline demo.
public struct DemoData: Sendable {
    public var state: LibraryState
    public var samples: [String: [Sample]]
    public var increases: [String: [Metric: LatestMetricIncrease]]
    public init(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) {
        let titles = ["Ripple planter", "Desk essentials tray", "Cable keeper", "Headphone stand", "Modular organizer", "Arc desk lamp", "Workshop tool rack", "Stackable grid box", "Twist vase"]
        let artwork = ["planter", "tray", "clip", "stand", "organizer", "lamp", "rack", "grid", "vase"]
        var library = LibraryState(); var history: [String: [Sample]] = [:]
        library.preferences.userID = "1000"; library.preferences.handle = "samplecreator"
        library.preferences.textScalePercent = 100; library.preferences.pollingSelectionVersion = 1
        library.preferences.notificationsEnabled = false
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -7, to: now)!)
        for index in titles.indices {
            let id = "\(9000 + index)"
            let final = Counts(likes: 920 + index * 137, downloads: 540 + index * 113, prints: 135 + index * 29,
                boosts: 7 + index * 4, collections: 620 + index * 91)
            library.models.append(Design(id: id, title: titles[index], cover: "demo://\(artwork[index])", counts: final, publishedAt: start.addingTimeInterval(-Double(index) * 86400)))
            library.watches[id] = WatchRule()
            let observed = now.addingTimeInterval(-Double(index * 7) * 60)
            let dates = stride(from: start.timeIntervalSince1970, to: observed.timeIntervalSince1970, by: 3600).map { Date(timeIntervalSince1970: $0) } + [observed.addingTimeInterval(-600), observed]
            history["model:\(id)"] = Array(Set(dates.filter { $0 >= start && $0 <= observed })).sorted().map { date in
                let hoursAgo = max(0, observed.timeIntervalSince(date) / 3600)
                return Sample(date: date, counts: Counts(likes: max(0, final.likes! - Int(ceil(hoursAgo * Double(index + 1) * 0.45))),
                    downloads: max(0, final.downloads! - Int(ceil(hoursAgo * 0.55))),
                    prints: max(0, final.prints! - Int(ceil(hoursAgo * (index % 3 == 0 ? 0.25 : 0.04)))),
                    boosts: max(0, final.boosts! - Int(hoursAgo / 36)), collections: max(0, final.collections! - Int(ceil(hoursAgo * 0.65)))))
            }
        }
        func sum(_ key: KeyPath<Counts, Int?>) -> Int { library.models.reduce(0) { $0 + ($1.counts[keyPath: key] ?? 0) } }
        let totals = Counts(likes: sum(\.likes), downloads: sum(\.downloads), prints: sum(\.prints), boosts: sum(\.boosts), collections: sum(\.collections), followers: 12)
        library.profile = Profile(id: "1000", name: "Sample Studio", handle: "samplecreator", avatar: "demo://avatar", counts: totals)
        history["profile"] = stride(from: start.timeIntervalSince1970, through: now.timeIntervalSince1970, by: 3600).map { timestamp in
            let date = Date(timeIntervalSince1970: timestamp), hours = now.timeIntervalSince(date) / 3600
            return Sample(date: date, counts: Counts(likes: max(0, totals.likes! - Int(hours * 6)), downloads: max(0, totals.downloads! - Int(hours * 4)), prints: max(0, totals.prints! - Int(hours)), boosts: max(0, totals.boosts! - Int(hours / 12)), collections: max(0, totals.collections! - Int(hours * 5)), followers: hours > 6 ? 10 : 12))
        } + [Sample(date: now, counts: totals)]
        library.followers = (1...12).map { index in
            Follower(id: "sample-follower-\(index)", name: "Sample maker \(String(format: "%02d", index))", handle: "samplemaker\(index)", avatar: "demo://avatar",
                firstObservedAt: index > 10 ? now.addingTimeInterval(-Double(index - 9) * 3600) : nil, baseline: index <= 10)
        }
        library.profileImported = true; library.followersImported = true
        library.lastProfileSync = now; library.lastModelSync = now; library.lastFollowerSync = now
        library.activity = [
            Activity(id: "sample-boost", date: now.addingTimeInterval(-180), title: "New boost", detail: "Fictional demo activity for Ripple planter", symbol: "bolt", modelID: "9000", presentation: ActivityPresentation(modelTitle: titles[0], modelCover: "demo://planter", kind: .boost, metric: .boosts, delta: 1, originalTimestamp: false)),
            Activity(id: "sample-milestone", date: now.addingTimeInterval(-1800), title: "Print milestone", detail: "Sample profile crossed a configurable milestone", symbol: "printer", presentation: ActivityPresentation(metric: .prints, originalTimestamp: false)),
            Activity(id: "sample-follower", date: now.addingTimeInterval(-7200), title: "Newly observed follower", detail: "Sample maker 11 was first observed after the demo baseline. This is not an original follow date.", symbol: "person.badge.plus", presentation: ActivityPresentation(actorName: "Sample maker 11", actorAvatar: "demo://avatar", metric: .followers, delta: 1, originalTimestamp: false))
        ]
        var prints = PrintHistory(accountID: "1000")
        prints.jobs = (0..<9).map { index in
            var job = PrintJob(id: "sample-print-\(index)", title: titles[index], status: [2,2,4,1,2,3,99,2,2][index])
            job.cover = "demo://\(artwork[index])"; job.deviceName = index % 2 == 0 ? "Sample workshop printer" : "Sample desk printer"
            job.plateIndex = index % 3 + 1; job.plateName = "Sample plate \(index % 3 + 1)"
            job.startTime = now.addingTimeInterval(-Double(index+1)*86400)
            if job.isTerminal { job.endTime = job.startTime?.addingTimeInterval(Double(index+1)*840) }
            job.estimatedSeconds = Double(index+1)*1000; job.mode = "cloud_file"
            job.firstObservedAt = now; job.lastObservedAt = now
            return job
        }
        prints.lastSync = now; prints.lastFullSync = now; prints.cloudTotal = prints.jobs.count; library.printHistory = prints
        state = library; samples = history
        increases = ["9000": [.prints: LatestMetricIncrease(delta: 1, checkedAt: now, previousCheckAt: now.addingTimeInterval(-600))]]
    }
}
