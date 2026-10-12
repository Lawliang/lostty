import SwiftUI

/// The three waits of pairing a phone.
enum PairingStep: Int, CaseIterable, Identifiable {
    case find, allow, connect

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .find: "Find your Mac"
        case .allow: "Allow on Mac"
        case .connect: "Connect"
        }
    }
}

enum PairingStepState: Equatable { case done, current, pending }

/// Where pairing is: the step under way, or finished.
struct PairingProgress: Equatable {
    var current: PairingStep?
    var finished = false

    static let notStarted = PairingProgress(current: nil)
    static let finding = PairingProgress(current: .find)
    static let waitingForAllow = PairingProgress(current: .allow)
    static let testing = PairingProgress(current: .connect)
    static let finished = PairingProgress(current: nil, finished: true)

    func state(of step: PairingStep) -> PairingStepState {
        if finished { return .done }
        guard let current else { return .pending }
        if step == current { return .current }
        return step.rawValue < current.rawValue ? .done : .pending
    }
}

/// Numbered steps: done ✓, the current one pulsing, the rest dim.
struct StepIndicator: View {
    var progress: PairingProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(PairingStep.allCases) { step in
                let state = progress.state(of: step)
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(state == .pending ? LosttyTheme.surfaceRaised : LosttyTheme.accentSoft)
                        switch state {
                        case .done:
                            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(LosttyTheme.accent)
                        case .current:
                            Circle().fill(LosttyTheme.accent).frame(width: 8, height: 8)
                                .symbolEffect(.pulse, options: .repeating)
                        case .pending:
                            Text("\(step.rawValue + 1)").font(LosttyFont.mono(.footnote, size: 13, weight: .semibold))
                                .foregroundStyle(LosttyTheme.textSecondary)
                        }
                    }
                    .frame(width: 24, height: 24)
                    Text(step.title)
                        .font(state == .current ? LosttyFont.bodyEmphasis : LosttyFont.body)
                        .foregroundStyle(state == .pending ? LosttyTheme.textSecondary : LosttyTheme.textPrimary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(step.title), \(state == .done ? "done" : state == .current ? "in progress" : "not started")")
            }
        }
    }
}

/// How much of a pairing code's life is left, 1 (new) … 0 (expired).
enum PairingCountdown {
    static func fraction(now: Date, expires: Date, total: TimeInterval = 120) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, expires.timeIntervalSince(now) / total))
    }
}
