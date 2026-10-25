import Foundation
import Testing
@testable import Reader

/// What the shipped bundle promises: the privacy manifest says nothing is collected or tracked, and
/// the app asks for no permission and runs nothing in the background.
struct ShipHygieneTests {
    func plist(_ name: String) throws -> [String: Any] {
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func privacyManifestCollectsAndTracksNothing() throws {
        let manifest = try plist("PrivacyInfo")
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true)
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
        // Required-reason APIs the shipped code uses: none yet. Adding one adds it here and to
        // the manifest together.
        let reasons = (manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? [])
            .compactMap { $0["NSPrivacyAccessedAPIType"] as? String }
        #expect(reasons == [])
    }

    @Test func asksForNoPermissionAndRunsNothingInTheBackground() {
        let info = Bundle.main.infoDictionary ?? [:]
        #expect(info.keys.filter { $0.hasSuffix("UsageDescription") }.isEmpty)
        #expect(info["UIBackgroundModes"] == nil)
        #expect(info["NSAppTransportSecurity"] == nil)
    }
}
