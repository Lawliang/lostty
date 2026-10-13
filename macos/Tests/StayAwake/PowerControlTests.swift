#if os(macOS)
import Testing
@testable import Lostty

struct PowerParseTests {
    let custom = """
    Battery Power:
     Sleep On Power Button 1
     lowpowermode         1
     displaysleep         57
    AC Power:
     Sleep On Power Button 1
     lowpowermode         0
     displaysleep         10
    """

    @Test func readsLowPowerPerSource() {
        let lp = PowerParse.lowPower(pmsetCustom: custom)
        #expect(lp.battery == true)
        #expect(lp.ac == false)
    }

    @Test func otherPowerSectionsDoNotOverwriteAC() {
        let lp = PowerParse.lowPower(pmsetCustom: custom + "\nUPS Power:\n lowpowermode         1\n")
        #expect(lp.battery == true)
        #expect(lp.ac == false)
    }

    @Test func desktopHasNoBatterySection() {
        let lp = PowerParse.lowPower(pmsetCustom: "AC Power:\n lowpowermode         1\n")
        #expect(lp.battery == nil)
        #expect(lp.ac == true)
    }

    @Test func sleepDisabledOnlyWhenListedAsOne() {
        #expect(PowerParse.sleepDisabled(pmsetG: "System-wide power settings:\n SleepDisabled\t\t1\nCurrently in use:\n sleep 1\n"))
        #expect(!PowerParse.sleepDisabled(pmsetG: "System-wide power settings:\n SleepDisabled\t\t0\n"))
        #expect(!PowerParse.sleepDisabled(pmsetG: "System-wide power settings:\nCurrently in use:\n standby 1\n"))
    }

    @Test func commandsMapToPmsetArguments() {
        #expect(PowerCommand.disableSleep(true).pmsetArguments == ["-a", "disablesleep", "1"])
        #expect(PowerCommand.lowPowerEverywhere.pmsetArguments == ["-a", "lowpowermode", "1"])
        #expect(PowerCommand.lowPower(.battery, false).pmsetArguments == ["-b", "lowpowermode", "0"])
        #expect(PowerCommand.lowPower(.ac, true).pmsetArguments == ["-c", "lowpowermode", "1"])
        #expect(PowerCommand.all.count == 7)
    }
}

struct StayAwakeSudoersTests {
    @Test func ruleAllowsExactlyTheSevenCommands() throws {
        let rule = try #require(StayAwakeSudoers.rule(user: "lawliang"))
        #expect(rule == "lawliang ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a lowpowermode 1, /usr/bin/pmset -b lowpowermode 0, /usr/bin/pmset -b lowpowermode 1, /usr/bin/pmset -c lowpowermode 0, /usr/bin/pmset -c lowpowermode 1")
    }

    @Test func refusesUnsafeUserNames() {
        for bad in ["", "a b", "a,b", "ALL", "-x", "a\nb", "a:b", "a=b", "%admin", "lawliang\n", "lawliang\r"] {
            #expect(StayAwakeSudoers.rule(user: bad) == nil, "\(bad)")
            #expect(StayAwakeSudoers.installScript(user: bad) == nil, "\(bad)")
        }
        #expect(StayAwakeSudoers.rule(user: "first.last-2_x") != nil)
    }

    @Test func installChecksWithVisudoBeforeInstalling() throws {
        let script = try #require(StayAwakeSudoers.installScript(user: "lawliang"))
        let visudo = try #require(script.range(of: "/usr/sbin/visudo -cf"))
        let install = try #require(script.range(of: "/usr/bin/install -m 0440 -o root -g wheel"))
        #expect(visudo.lowerBound < install.lowerBound)
        #expect(script.contains("/etc/sudoers.d/lostty"))
        #expect(script.contains(StayAwakeSudoers.rule(user: "lawliang")!))
        #expect(StayAwakeSudoers.removeScript == "rm -f /etc/sudoers.d/lostty")
    }
}
#endif
