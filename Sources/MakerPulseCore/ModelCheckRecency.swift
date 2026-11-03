import Foundation

public struct MetricObservation: Equatable, Sendable {
    public var value: Int
    public var date: Date
    public init(value: Int, date: Date) { self.value = value; self.date = date }
}

public struct LatestMetricIncrease: Equatable, Sendable {
    public var delta: Int
    public var checkedAt: Date
    public var previousCheckAt: Date
    public init(delta: Int, checkedAt: Date, previousCheckAt: Date) {
        self.delta = delta; self.checkedAt = checkedAt; self.previousCheckAt = previousCheckAt
    }
}

// Session-local highlights, reconstructed baselines. Launch never replays an
// old highlight; the first fresh fetch can discover a real change while away.
public struct ModelCheckRecency: Sendable {
    private var baselines: [String: [Metric: MetricObservation]]
    public private(set) var increases: [String: [Metric: LatestMetricIncrease]] = [:]
    public init(baselines: [String: [Metric: MetricObservation]] = [:]) { self.baselines = baselines }

    // Call only after a complete successful model crawl has been committed.
    // An omitted field/model is not an unchanged observation. Failures never
    // call this method. Alert/watch preferences do not suppress observations.
    public mutating func recordSuccessful(_ models: [Design], at date: Date) {
        for model in models {
            for metric in ModelActivity.metrics {
                guard let value = model.counts[metric] else { continue }
                if let previous = baselines[model.id]?[metric] {
                    guard date > previous.date else { continue }
                    if value > previous.value {
                        increases[model.id, default: [:]][metric] = LatestMetricIncrease(delta: value - previous.value, checkedAt: date, previousCheckAt: previous.date)
                    } else { increases[model.id]?[metric] = nil }
                } else { increases[model.id]?[metric] = nil }
                baselines[model.id, default: [:]][metric] = MetricObservation(value: value, date: date)
            }
        }
    }
}
