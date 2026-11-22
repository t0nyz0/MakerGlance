# Performance periods

The Dashboard performance menu affects only its six performance values. Lifetime is the default; it keeps the saved profile totals and existing Today indicators. Other history ranges, model filters, cash values and notification preferences are independent.

| Choice | Meaning | Data source |
| --- | --- | --- |
| 1 Day / 1 Week | Trailing 24 / 168 hours | Net changes in saved profile totals |
| 1 / 3 / 6 Months / 1 Year | Trailing local-calendar month/year intervals | Net changes in saved profile totals |
| Last Calendar Month (UTC) | Previous complete UTC calendar month | Returned Creator Center **Models** daily values |
| Lifetime | Latest saved profile totals | Public profile and model aggregates |

Snapshot changes are **not counts of events received**. They can decrease after removals or corrections. Each metric needs two actual observations inside the requested window. Missing time is excluded, not interpolated. Partial boundary coverage and observation gaps are identified. The panel uses full-fidelity retained profile samples rather than the chart's display buckets. Retention is 366 days; shorter histories remain partial.

The UTC calendar-month option sums only returned days for likes, downloads, prints, boosts and saves. Coverage is metric-specific: `20/31 days · partial` is a partial total, not a full-month total. A returned zero is valid; an absent day or field is not zero. Wrong-scope reports, conflicting duplicate dates and unavailable values show `—`. The server follower-activity field is not verified as gross follows or a net-follower count, so this option does not claim a follower total.

To load a complete prior month using the existing flow: **Analytics → Creator Center → Models → From/Through → Load report**. Dates there are inclusive UTC days. The Dashboard menu reads the saved report; changing its selection does not make network requests, change that report's filters or fetch credentials. A report for another period can supply only its overlapping returned days.

The menu and data logic have headless regression coverage. New control layout, pointer interaction and VoiceOver operation require separate native verification; no desktop fixture is launched by the unit tests.
