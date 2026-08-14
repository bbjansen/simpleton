import Foundation
import SimpletonSQL

func runSQLRunStatsChecks(_ t: TestRunner) {
    t.suite("SQLRunStats count text + pluralization") {
        t.expectEqual(SQLRunStats.summary(count: 42, noun: .rows, seconds: 0.013), "42 rows · 13 ms", "rows plural")
        t.expectEqual(SQLRunStats.summary(count: 1, noun: .rows, seconds: 0.013), "1 row · 13 ms", "row singular")
        t.expectEqual(SQLRunStats.summary(count: 0, noun: .rows, seconds: 0.5), "0 rows · 500 ms", "zero rows plural")
        t.expectEqual(SQLRunStats.summary(count: 3, noun: .affected, seconds: 0.5), "3 affected · 500 ms", "affected")
    }

    t.suite("SQLRunStats timing thresholds") {
        t.expectEqual(SQLRunStats.timeText(2.5), "2.50 s", "≥ 1 s shows seconds")
        t.expectEqual(SQLRunStats.timeText(1.0), "1.00 s", "exactly 1 s shows seconds")
        t.expectEqual(SQLRunStats.timeText(0.013), "13 ms", "whole ms")
        t.expectEqual(SQLRunStats.timeText(0.0004), "0.4 ms", "sub-ms shows one decimal")
        t.expectEqual(SQLRunStats.timeText(0), "0.0 ms", "zero seconds")
    }

    t.suite("SQLRunStats guards non-finite / negative") {
        t.expectEqual(SQLRunStats.timeText(.infinity), "—", "infinite → dash")
        t.expectEqual(SQLRunStats.timeText(.nan), "—", "NaN → dash")
        t.expectEqual(SQLRunStats.timeText(-1), "—", "negative → dash")
    }
}
