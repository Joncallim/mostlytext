import Darwin
import Foundation
@testable import MacDown2
import Testing

@Suite("UI test launch guard")
struct UITestLaunchGuardTests {
    @Test func rejectsUITestRequestWhenHooksAreUnavailable() {
        let arguments = ["MacDown2", "-UITesting", "-sessionDir", "/tmp/fixture"]
        #expect(UITestLaunchGuard.rejection(arguments: arguments, testHooksEnabled: false) != nil)
        #expect(UITestLaunchGuard.rejection(arguments: arguments, testHooksEnabled: true) == nil)
    }

    @Test func isolatedBuildRequiresOneMarkerAndItsOwnIdentity() {
        let bundleID = UITestLaunchGuard.isolatedBundlePrefix + UUID().uuidString
        #expect(UITestLaunchGuard.rejection(
            arguments: ["MacDown2"], testHooksEnabled: true, isolatedBuild: true, bundleID: bundleID
        ) != nil)
        #expect(UITestLaunchGuard.rejection(
            arguments: ["MacDown2", "-UITesting", "-UITesting"],
            testHooksEnabled: true, isolatedBuild: true, bundleID: bundleID
        ) != nil)
        #expect(UITestLaunchGuard.rejection(
            arguments: ["MacDown2", "-UITesting"],
            testHooksEnabled: true, isolatedBuild: true, bundleID: "com.joncallim.MacDown2"
        ) != nil)
    }

    @Test func permitsOrdinaryLaunchWithoutUITestFlag() {
        #expect(UITestLaunchGuard.rejection(arguments: ["MacDown2"], testHooksEnabled: false) == nil)
        #expect(UITestLaunchGuard.rejection(arguments: ["MacDown2"], testHooksEnabled: true) == nil)
    }

    @Test(arguments: [nil, "", "0", "-1", "501suffix", " 501", "4294967296"])
    func isolatedAccountRejectsMissingOrMalformedProtectedUID(_ value: String?) {
        #expect(UITestLaunchGuard.accountRejection(protectedOwnerUID: value, realUID: 502, effectiveUID: 502) != nil)
    }

    @Test func isolatedAccountRejectsOwnerRootAndChangedIdentity() {
        let identities: [(uid_t, uid_t)] = [(501, 501), (0, 0), (502, 0), (502, 503)]
        for (realUID, effectiveUID) in identities {
            #expect(UITestLaunchGuard.accountRejection(
                protectedOwnerUID: "501", realUID: realUID, effectiveUID: effectiveUID
            ) != nil)
        }
        #expect(UITestLaunchGuard.accountRejection(protectedOwnerUID: "501", realUID: 502, effectiveUID: 502) == nil)
    }
}
