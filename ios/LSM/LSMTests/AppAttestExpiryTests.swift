import Testing
import Foundation
@testable import LSM

/// Regression cover for the JWT expiry parse. The authority mints `expiresAt`
/// with JS `Date.toISOString()`, which always carries fractional seconds
/// (`…T12:00:00.000Z`). A bare `ISO8601DateFormatter` can't read that and
/// returned nil, so `tokenExpiresAt` stayed nil and every cloud call re-ran the
/// full App Attest mint. `parseExpiry` must handle the fractional form (and the
/// plain form, defensively).
struct AppAttestExpiryTests {

    @Test func parsesWorkerFractionalSecondsFormat() throws {
        // Exactly what the worker emits (new Date(exp*1000).toISOString()).
        let date = try #require(AppAttestService.parseExpiry("2026-07-04T12:00:00.000Z"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let parts = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        #expect(parts.year == 2026)
        #expect(parts.month == 7)
        #expect(parts.day == 4)
        #expect(parts.hour == 12)
        #expect(parts.minute == 0)
        #expect(parts.second == 0)
    }

    @Test func parsesNonZeroMilliseconds() throws {
        let a = try #require(AppAttestService.parseExpiry("2026-07-04T12:00:00.500Z"))
        let b = try #require(AppAttestService.parseExpiry("2026-07-04T12:00:01.000Z"))
        // 12:00:00.500 is half a second before 12:00:01.000.
        #expect(abs(b.timeIntervalSince(a) - 0.5) < 0.01)
    }

    @Test func fallsBackToPlainInternetDateTime() throws {
        // Defensive: if the server ever drops fractional seconds we still parse.
        #expect(AppAttestService.parseExpiry("2026-07-04T12:00:00Z") != nil)
    }

    @Test func returnsNilOnGarbage() {
        #expect(AppAttestService.parseExpiry("not-a-date") == nil)
        #expect(AppAttestService.parseExpiry("") == nil)
    }
}
