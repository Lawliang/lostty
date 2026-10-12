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

/// The pairing steps as rows: done ✓, the current one with a spinner, the
/// rest waiting.
struct StepIndicator: View {
    var progress: PairingProgress

    var body: some View {
        VStack(spacing: 0) {
            ForEach(PairingStep.allCases) { step in
                let state = progress.state(of: step)
                if step != .find { Rectangle().fill(LosttyTheme.hairline).frame(height: 1) }
                HStack(spacing: 12) {
                    marker(state).frame(width: 20, height: 20)
                    Text(step.title)
                        .font(state == .current ? LosttyFont.bodyEmphasis : LosttyFont.body)
                        .foregroundStyle(state == .pending ? LosttyTheme.textSecondary : LosttyTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(step.title), \(state == .done ? "done" : state == .current ? "in progress" : "not started")")
            }
        }
    }

    @ViewBuilder private func marker(_ state: PairingStepState) -> some View {
        switch state {
        case .done:
            Circle().fill(LosttyTheme.accent)
                .overlay(Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white))
        case .current:
            ProgressView().controlSize(.small).tint(LosttyTheme.textPrimary)
        case .pending:
            Circle().strokeBorder(LosttyTheme.hairline, lineWidth: 1.5)
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
