#if os(macOS)
import Foundation
import LosttyRemote
import Testing
@testable import Lostty

struct AgentRecipeTests {
    @Test func aRecipeFileReadsItsFrontMatterAndInstructions() throws {
        let recipe = try #require(AgentRecipe.parse("""
        ---
        name: Reviewer
        icon: eye
        agent: Codex
        model: opus
        skills: [code-review, "/run"]
        seat: manager
        ---

        You review the branch you start in.
        """, fallbackName: "reviewer"))
        #expect(recipe.name == "Reviewer")
        #expect(recipe.icon == "eye")
        #expect(recipe.agent == .codex)
        #expect(recipe.model == "opus")
        #expect(recipe.skills == ["code-review", "run"])
        #expect(recipe.takesManagerSeat)
        #expect(recipe.instructions == "You review the branch you start in.")
    }

    @Test func aFileWithoutFrontMatterIsNamedAfterItselfAndOneWithoutInstructionsIsNone() throws {
        let plain = try #require(AgentRecipe.parse("Fix flaky tests.", fallbackName: "Fixer"))
        #expect(plain.name == "Fixer")
        #expect(plain.agent == .claude)
        #expect(plain.model == nil)
        #expect(!plain.takesManagerSeat)
        #expect(AgentRecipe.parse("---\nname: Empty\n---\n\n", fallbackName: "x") == nil)
    }

    @Test func yourRecipeReplacesABuiltInOneOfTheSameNameAndOthersFollow() {
        let mine = [
            AgentRecipe(name: "verifier", instructions: "Mine."),
            AgentRecipe(name: "Reviewer", instructions: "Review."),
        ]
        let all = AgentRecipe.merged(AgentRecipe.builtIn, mine)
        #expect(all.map(\.name) == ["Coordinator", "Worker", "verifier", "Reviewer"])
        #expect(AgentRecipe.named(" VERIFIER ", in: all)?.instructions == "Mine.")
    }

    @Test func theCoordinatorIsFirstAndTakesTheManagerSeat() {
        #expect(AgentRecipe.builtIn.first?.name == "Coordinator")
        #expect(AgentRecipe.builtIn.first?.takesManagerSeat == true)
        #expect(AgentRecipe.builtIn.dropFirst().allSatisfy { !$0.takesManagerSeat })
    }

    @Test func claudeStartsWithItsPromptFileNameModelAndFirstMessage() {
        let recipe = AgentRecipe(name: "Worker", model: "opus", skills: ["run"], instructions: "Do it.")
        #expect(recipe.commandLine(file: "/tmp/a b.md", name: "Worker · Login", message: "Start on TB-7")
            == "claude --name 'Worker · Login' --model opus --append-system-prompt-file '/tmp/a b.md' 'Start on TB-7'")
        #expect(recipe.commandLine(file: "/tmp/a.md", name: "Worker", message: "  ")
            == "claude --name Worker --model opus --append-system-prompt-file /tmp/a.md")
        #expect(recipe.prompt(context: ["Your feature: Login."]) == "Do it.\n\nUse these skills when they fit: /run.\n\nYour feature: Login.")
        #expect(recipe.fileText(context: [], message: "Hi") == recipe.prompt(context: []))
    }

    @Test func codexGetsItsPromptAndMessageAsItsFirstMessage() {
        let recipe = AgentRecipe(name: "Verifier", agent: .codex, instructions: "Check it.")
        #expect(recipe.commandLine(file: "/tmp/v.md", name: "Verifier", message: "TB-7") == #"codex "$(cat /tmp/v.md)""#)
        #expect(recipe.fileText(context: [], message: "TB-7") == "Check it.\n\nTB-7")
    }

    @Test func anAgentRequestReadsOpenAndReportOnly() {
        #expect(AgentRequest(json: #"["open","Worker","","Login","tb-7"]"#)
            == .open(agent: "Worker", message: nil, feature: "Login", branch: "tb-7"))
        #expect(AgentRequest(json: #"["open","Verifier","Check TB-7","",""]"#)
            == .open(agent: "Verifier", message: "Check TB-7", feature: nil, branch: nil))
        #expect(AgentRequest(json: #"["report","TB-7: pass"]"#) == .report("TB-7: pass"))
        #expect(AgentRequest(json: #"["open"," ","","",""]"#) == nil)
        #expect(AgentRequest(json: #"["open","Worker","","","bad branch"]"#) == nil)
        #expect(AgentRequest(json: #"["report",""]"#) == nil)
        #expect(AgentRequest(json: #"["close","Worker"]"#) == nil)
        #expect(AgentRequest(json: "not json") == nil)
    }
}
#endif
