@testable import EggKit
import FileManagerProtocol
import Foundation
import ProcessRunning
import Testing

/// `StagingFeasibility.decide` is the single decision both
/// `AgentHatchTransactionRunner.preview()` and `EggService.hatchTemplate`
/// resolve through, so the two entry points can't drift on what "too large"
/// or "needs consent" means — only the error each throws differs. These
/// exercise the decision table directly, independent of either caller.
@Suite("StagingFeasibility.decide")
struct StagingFeasibilityTests {
    private let feasibility = StagingFeasibility()

    @Test("a non-git directory without consent requires consent, reporting the measured count")
    func nonGitWithoutConsentRequiresConsent() {
        let facts = StagingFeasibility.Facts(isGitRepository: false, fileCount: 4, isExactCount: true)
        let decision = feasibility.decide(facts: facts, allowLargeStaging: false, allowNonGitStaging: false)
        guard case let .nonGitConsentRequired(fileCount, isExact) = decision else {
            Issue.record("expected nonGitConsentRequired, got \(decision)")
            return
        }
        #expect(fileCount == 4)
        #expect(isExact)
    }

    @Test("a non-git directory with consent and a count under the limit proceeds with a warning")
    func nonGitWithConsentProceeds() {
        let facts = StagingFeasibility.Facts(isGitRepository: false, fileCount: 4, isExactCount: true)
        let decision = feasibility.decide(facts: facts, allowLargeStaging: false, allowNonGitStaging: true)
        guard case let .proceed(warnings) = decision else {
            Issue.record("expected proceed, got \(decision)")
            return
        }
        #expect(warnings == [.nonGitStaging])
    }

    @Test("a non-git directory with consent but over the limit still needs allowLargeStaging")
    func nonGitConsentDoesNotBypassSizeGuard() {
        let facts = StagingFeasibility.Facts(isGitRepository: false, fileCount: 50000, isExactCount: true)
        let decision = feasibility.decide(facts: facts, allowLargeStaging: false, allowNonGitStaging: true)
        guard case let .tooLarge(fileCount, limit) = decision else {
            Issue.record("expected tooLarge, got \(decision)")
            return
        }
        #expect(fileCount == 50000)
        #expect(limit == StagingFeasibility.defaultFileLimit)
    }

    @Test("a git repository under the limit proceeds without a non-git warning")
    func gitUnderLimitProceedsClean() {
        let facts = StagingFeasibility.Facts(isGitRepository: true, fileCount: 100, isExactCount: true)
        let decision = feasibility.decide(facts: facts, allowLargeStaging: false, allowNonGitStaging: false)
        guard case let .proceed(warnings) = decision else {
            Issue.record("expected proceed, got \(decision)")
            return
        }
        #expect(warnings.isEmpty)
    }

    @Test("a git repository over the limit needs allowLargeStaging, independent of allowNonGitStaging")
    func gitOverLimitNeedsLargeStagingConsent() {
        let facts = StagingFeasibility.Facts(isGitRepository: true, fileCount: 50000, isExactCount: true)
        let decision = feasibility.decide(facts: facts, allowLargeStaging: false, allowNonGitStaging: true)
        guard case .tooLarge = decision else {
            Issue.record("expected tooLarge, got \(decision)")
            return
        }
    }

    @Test("allowLargeStaging bypasses the size guard for both git and non-git directories")
    func allowLargeStagingBypassesSizeGuardEitherWay() {
        let gitFacts = StagingFeasibility.Facts(isGitRepository: true, fileCount: 50000, isExactCount: true)
        guard case .proceed = feasibility.decide(facts: gitFacts, allowLargeStaging: true, allowNonGitStaging: false) else {
            Issue.record("expected proceed for git+allowLargeStaging")
            return
        }

        let nonGitFacts = StagingFeasibility.Facts(isGitRepository: false, fileCount: 50000, isExactCount: true)
        guard case .proceed = feasibility.decide(facts: nonGitFacts, allowLargeStaging: true, allowNonGitStaging: true) else {
            Issue.record("expected proceed for non-git+both consents")
            return
        }
    }

    @Test("a caller-configured limit is honored instead of the default")
    func customLimitIsHonored() {
        let facts = StagingFeasibility.Facts(isGitRepository: true, fileCount: 50, isExactCount: true)
        guard case .tooLarge = feasibility.decide(facts: facts, allowLargeStaging: false, allowNonGitStaging: false, limit: 10) else {
            Issue.record("expected tooLarge under a limit of 10")
            return
        }
        guard case .proceed = feasibility.decide(facts: facts, allowLargeStaging: false, allowNonGitStaging: false, limit: 100) else {
            Issue.record("expected proceed under a limit of 100")
            return
        }
    }
}
