#if os(macOS)
import Testing
@testable import Lostty

struct LosttyChannelTests {
    @Test func onlyBetaIsTheBeta() {
        #expect(LosttyChannel(info: [LosttyChannel.infoKey: "beta"]) == .beta)
        let others: [Any] = ["stable", "", "$(LOSTTY_CHANNEL)", "Beta", 1]
        for other in others {
            #expect(LosttyChannel(info: [LosttyChannel.infoKey: other]) == .stable)
        }
        #expect(LosttyChannel(info: nil) == .stable)
        #expect(LosttyChannel(info: [:]) == .stable)
    }

    @Test func theUnfinishedFeaturesAreOnlyInTheBeta() {
        #expect(LosttyChannel.beta.isBeta && LosttyChannel.beta.handsOff && LosttyChannel.beta.hasBranches)
        #expect(!LosttyChannel.stable.isBeta && !LosttyChannel.stable.handsOff && !LosttyChannel.stable.hasBranches)
    }

    @Test func theTurnObserverIsOffEverywhereUntilItHasANewHome() {
        #expect(!LosttyChannel.beta.observesTurns && !LosttyChannel.stable.observesTurns)
    }

    @Test func theCanvasIsOnlyInTheBeta() {
        #expect(LosttyChannel.beta.hasCanvas)
        #expect(!LosttyChannel.stable.hasCanvas)
    }

    @Test func theBetaIsNamedLosttyBeta() {
        #expect(LosttyChannel.beta.appName == "Lostty Beta")
        #expect(LosttyChannel.stable.appName == "Lostty")
    }

    @Test func aBetaShowsItsNumberBesideTheVersion() {
        let info: [String: Any] = [
            "CFBundleShortVersionString": "0.4",
            LosttyChannel.infoKey: "beta",
            LosttyChannel.betaNumberKey: "2",
        ]
        #expect(LosttyChannel.displayVersion(info: info) == "0.4 beta 2")
    }

    @Test func withoutANumberOnlyTheVersion() {
        // A Debug or install.sh beta has no number; stable never shows one.
        let numbers: [Any?] = [nil, "", "$(LOSTTY_BETA_NUMBER)", "x"]
        for number in numbers {
            var info: [String: Any] = ["CFBundleShortVersionString": "0.4", LosttyChannel.infoKey: "beta"]
            info[LosttyChannel.betaNumberKey] = number
            #expect(LosttyChannel.displayVersion(info: info) == "0.4")
        }
        let stable: [String: Any] = ["CFBundleShortVersionString": "0.4", LosttyChannel.betaNumberKey: "2"]
        #expect(LosttyChannel.displayVersion(info: stable) == "0.4")
        #expect(LosttyChannel.displayVersion(info: [:]) == nil)
    }
}
#endif
