import Accessibility
import SwiftUI
import ZenithMacOSClientCore

struct HyphaSecurityBanner: View {
    let presentation: HyphaSecurityPresentationState
    let onSetUpDevice: () -> Void
    let onContinueDeviceSetup: () -> Void
    let onRequestVerification: () -> Void
    let onApproveVerification: () -> Void
    let onDeclineVerification: () -> Void
    let onRefresh: () -> Void
    let onSetUpRecovery: () -> Void
    let onRestoreRecovery: () -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x3) {
            HStack(alignment: .top, spacing: ZenithDesign.Space.x3) {
                Image(systemName: severitySymbol)
                    .font(.title3)
                    .foregroundStyle(severityColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
                    Text(severityTitle)
                        .font(ZenithDesign.Typography.corporate(.headline, weight: .semibold))
                    Text(severityMessage)
                        .font(ZenithDesign.Typography.corporate(.caption))
                        .foregroundStyle(ZenithDesign.Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: ZenithDesign.Space.x2)
                refreshButton
            }

            localOperationContent
            actionRow
        }
        .padding(.horizontal, ZenithDesign.Space.x4)
        .padding(.vertical, ZenithDesign.Space.x3)
        .background(severityColor.opacity(presentation.requiresPersistentCriticalBanner ? 0.13 : 0.07))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(presentation.requiresPersistentCriticalBanner ? severityColor.opacity(0.5) : ZenithDesign.Palette.border)
                .frame(height: presentation.requiresPersistentCriticalBanner ? 2 : 1)
        }
        .animation(
            accessibilityReduceMotion ? nil : .easeInOut(duration: 0.16),
            value: presentation
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("matrix.security.banner")
        .onChange(of: presentation) { _, _ in
            AccessibilityNotification.Announcement(accessibilityAnnouncement).post()
        }
    }

    private var severityTitle: String {
        switch presentation.indicatorSeverity {
        case .unknown:
            return "Checking device security"
        case .recommended:
            return "Device security needs attention"
        case .secure:
            return "Device identity verified"
        case .critical:
            return "Device identity verification failed"
        }
    }

    private var severityMessage: String {
        switch presentation.indicatorSeverity {
        case .unknown:
            return "Hypha is waiting for authoritative security state from your Matrix homeserver."
        case .recommended where presentation.primaryDeviceAction == nil:
            return "Hypha could not determine whether another Hypha device can verify this one. Refresh before choosing a setup path."
        case .recommended:
            return "Choose the available authoritative path to protect this device. Encrypted chat remains available."
        case .secure:
            return "This device is signed by your current Matrix identity."
        case .critical:
            return "Hypha detected invalid identity evidence. Security-sensitive chat actions remain blocked until this is resolved."
        }
    }

    private var severitySymbol: String {
        switch presentation.indicatorSeverity {
        case .unknown:
            return "questionmark.shield"
        case .recommended:
            return "exclamationmark.shield.fill"
        case .secure:
            return "checkmark.shield.fill"
        case .critical:
            return "xmark.shield.fill"
        }
    }

    private var accessibilityAnnouncement: String {
        switch presentation.localOperation {
        case .idle:
            return "\(severityTitle). \(severityMessage)"
        case .settingUpThisDevice:
            return "Setting up this device."
        case .requestingVerificationFromAnotherHyphaDevice:
            return "Waiting for another Hypha device."
        case .comparingWithAnotherHyphaDevice:
            return "Verification comparison is ready."
        case .approvingAnotherHyphaDevice:
            return "Confirming device identity."
        case let .verificationFailed(reason), let .recoveryFailed(reason):
            return reason
        case .restoringEncryption:
            return "Restoring encryption."
        case let .recoveryDiagnostic(receipt):
            return "Recovery diagnostic \(receipt.stableCode) is available."
        }
    }

    private var severityColor: Color {
        switch presentation.indicatorSeverity {
        case .unknown:
            return ZenithDesign.Palette.muted
        case .recommended:
            return ZenithDesign.Palette.warning
        case .secure:
            return ZenithDesign.Palette.success
        case .critical:
            return ZenithDesign.Palette.error
        }
    }

    @ViewBuilder
    private var refreshButton: some View {
        if presentation.indicatorSeverity != .secure {
            Button("Refresh", action: onRefresh)
                .disabled(isLocalOperationActive)
                .accessibilityIdentifier("matrix.security.refresh")
        }
    }

    @ViewBuilder
    private var localOperationContent: some View {
        switch presentation.localOperation {
        case .idle:
            EmptyView()
        case .settingUpThisDevice:
            progressRow("Setting up this device…")
        case .requestingVerificationFromAnotherHyphaDevice:
            HStack {
                progressRow("Waiting for another Hypha device…")
                Spacer()
                Button("Cancel", action: onDeclineVerification)
                    .accessibilityIdentifier("matrix.verification.decline")
            }
        case let .comparingWithAnotherHyphaDevice(challenge):
            verificationChallenge(challenge)
        case .approvingAnotherHyphaDevice:
            progressRow("Confirming device identity with the homeserver…")
        case let .verificationFailed(reason):
            failureRow(reason, retryTitle: "Try verification again", action: onRequestVerification)
        case .restoringEncryption:
            progressRow("Restoring encryption identity and backed-up room keys…")
        case let .recoveryFailed(reason):
            failureRow(reason, retryTitle: "Try recovery again", action: onRestoreRecovery)
        case let .recoveryDiagnostic(receipt):
            VStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
                Label("Recovery diagnostic \(receipt.stableCode)", systemImage: "stethoscope")
                    .foregroundStyle(ZenithDesign.Palette.error)
                Group {
                    Text("Identity key matches: \(receipt.privateSelfSigningKeyMatchesCurrentPublicIdentity ? "yes" : "no")")
                    Text("Device key matches: \(receipt.localOwnDeviceKeyMatchesServerDeviceKey ? "yes" : "no")")
                    Text("Signed object matches: \(receipt.signedObjectMatchesFreshServerDeviceObject ? "yes" : "no")")
                    Text("Local signature valid: \(receipt.generatedSignatureValidLocally ? "yes" : "no")")
                    Text("Upload transport: \(receipt.uploadTransport == .accepted ? "accepted" : "failed")")
                    Text("Upload processing: \(diagnosticUploadLabel(receipt.uploadProcessing))")
                    Text("Server signature present: \(receipt.postUploadServerSignaturePresent ? "yes" : "no")")
                    Text("Backup repair: \(diagnosticBackupLabel(receipt.backupRepair))")
                }
                .font(.caption)
                .foregroundStyle(ZenithDesign.Palette.muted)
                Button("Try recovery again", action: onRestoreRecovery)
                    .accessibilityIdentifier("matrix.recovery.restore")
            }
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        if presentation.primaryDeviceAction != nil || presentation.recoveryAction != nil {
            HStack(spacing: ZenithDesign.Space.x3) {
                primaryActionButton
                if presentation.primaryDeviceAction != nil,
                   presentation.recoveryAction != nil {
                    Divider().frame(height: 18)
                }
                recoveryActionButton
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        switch presentation.primaryDeviceAction {
        case .setUpThisDevice:
            Button("Set up this device", action: onSetUpDevice)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("matrix.first-device.bootstrap")
        case .verifyWithAnotherHyphaDevice:
            Button("Verify with another Hypha device", action: onRequestVerification)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("matrix.verification.request")
        case .continueDeviceSetupWithPassword:
            Button("Continue device setup", action: onContinueDeviceSetup)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("matrix.first-device.continue")
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var recoveryActionButton: some View {
        switch presentation.recoveryAction {
        case .setUpRecovery:
            Button("Set up recovery", action: onSetUpRecovery)
                .disabled(isLocalOperationActive)
                .accessibilityIdentifier("matrix.recovery.setup")
        case .restoreEncryption:
            Button("Restore encryption", action: onRestoreRecovery)
                .disabled(isLocalOperationActive)
                .accessibilityIdentifier("matrix.recovery.restore")
        case nil:
            EmptyView()
        }
    }

    private var isLocalOperationActive: Bool {
        presentation.localOperation != .idle
    }

    private func diagnosticUploadLabel(_ value: MatrixDiagnosticUploadProcessing) -> String {
        switch value {
        case .accepted: "accepted"
        case .keyMismatch: "key does not match server object"
        case .invalidSignature: "invalid signature"
        case .otherFailure: "other failure"
        }
    }

    private func diagnosticBackupLabel(_ value: MatrixDiagnosticBackupRepair) -> String {
        switch value {
        case .notAttempted: "not attempted"
        case .completed: "completed"
        case .failed: "failed"
        }
    }

    private func progressRow(_ title: String) -> some View {
        HStack(spacing: ZenithDesign.Space.x2) {
            ProgressView().controlSize(.small)
            Text(title)
                .font(ZenithDesign.Typography.corporate(.callout))
        }
        .accessibilityElement(children: .combine)
    }

    private func failureRow(
        _ reason: String,
        retryTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(ZenithDesign.Palette.error)
            Spacer()
            Button(retryTitle, action: action)
        }
    }

    private func verificationChallenge(_ challenge: MatrixVerificationChallenge) -> some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x3) {
            Text("Do these match your other Hypha device?")
                .font(ZenithDesign.Typography.corporate(.headline, weight: .semibold))

            switch challenge {
            case let .emojis(emojis):
                HStack(spacing: ZenithDesign.Space.x3) {
                    ForEach(emojis) { emoji in
                        VStack(spacing: ZenithDesign.Space.x1) {
                            Text(emoji.symbol).font(.title)
                            Text(emoji.description).font(.caption)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            case let .decimals(values):
                Text(values.map(String.init).joined(separator: "   "))
                    .font(.title2.monospacedDigit())
                    .accessibilityLabel("Verification numbers \(values.map(String.init).joined(separator: ", "))")
            }

            HStack {
                Button("They do not match", action: onDeclineVerification)
                    .accessibilityIdentifier("matrix.verification.decline")
                Spacer()
                Button("They match", action: onApproveVerification)
                    .buttonStyle(ZenithPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("matrix.verification.approve")
            }
        }
        .accessibilityIdentifier("matrix.verification.challenge")
    }
}
