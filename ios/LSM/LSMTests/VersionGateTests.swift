import Testing
@testable import LSM

/// Regression cover for the version-gate comparison. The Worker's `minVersion`
/// and the app's `CFBundleShortVersionString` are both plain dot-separated
/// integers, but a naive string compare gets multi-digit components backwards
/// (e.g. "1.9" vs "1.10"), and unparseable input must fail open (no gate)
/// rather than fail closed (locking out every install).
struct VersionGateTests {

    @Test func sameVersionIsNotOlder() {
        #expect(VersionGateCheck.isVersion("1.0", olderThan: "1.0") == false)
    }

    @Test func lowerMinorIsOlder() {
        #expect(VersionGateCheck.isVersion("1.0", olderThan: "1.1") == true)
    }

    @Test func higherMinorIsNotOlder() {
        #expect(VersionGateCheck.isVersion("1.2", olderThan: "1.1") == false)
    }

    @Test func multiDigitComponentsCompareNumericallyNotLexically() {
        // A string compare would read "1.9" > "1.10" — component-wise must not.
        #expect(VersionGateCheck.isVersion("1.9", olderThan: "1.10") == true)
        #expect(VersionGateCheck.isVersion("1.10", olderThan: "1.9") == false)
    }

    @Test func differingComponentCountsPadWithZero() {
        #expect(VersionGateCheck.isVersion("1", olderThan: "1.1") == true)
        #expect(VersionGateCheck.isVersion("1.0", olderThan: "1") == false)
    }

    @Test func unparseableInputFailsOpenNotClosed() {
        #expect(VersionGateCheck.isVersion("not-a-version", olderThan: "1.0") == nil)
        #expect(VersionGateCheck.isVersion("1.0", olderThan: "not-a-version") == nil)
        #expect(VersionGateCheck.isVersion("", olderThan: "1.0") == nil)
    }
}
