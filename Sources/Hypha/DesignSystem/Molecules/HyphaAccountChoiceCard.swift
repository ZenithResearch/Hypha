import SwiftUI
import HyphaCore

/// Authentication molecule that presents one account identity and its independent actions.
struct HyphaAccountChoiceCard: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let choice: HyphaLoginAccountChoice
    let isPending: Bool
    let isInteractionDisabled: Bool
    let continueSession: (MatrixSDKSessionRecord) -> Void
    let signInWithSavedPassword: (HyphaMatrixCredentialDescriptor) -> Void
    let deleteLocalSession: (MatrixSDKSessionRecord) -> Void
    let deleteSavedPassword: (HyphaMatrixCredentialDescriptor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x3) {
            HStack(spacing: ZenithDesign.Space.x3) {
                ZStack {
                    Circle()
                        .fill(ZenithDesign.Palette.brand.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: "person.fill")
                        .foregroundStyle(ZenithDesign.Palette.brand)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.displayAccount)
                        .font(ZenithDesign.Typography.technical(size: 14, weight: .semibold))
                        .textSelection(.enabled)
                    Text(capabilitySummary)
                        .font(ZenithDesign.Typography.corporate(size: 12))
                        .foregroundStyle(ZenithDesign.Palette.muted)
                }
                Spacer()
                if isPending {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Opening \(choice.displayAccount)")
                }
            }

            VStack(spacing: ZenithDesign.Space.x2) {
                if let session = choice.session {
                    HyphaButton(
                        title: "Continue existing session",
                        systemImage: "arrow.right.circle.fill",
                        variant: .primary,
                        fillsWidth: true
                    ) {
                        continueSession(session)
                    }
                    .disabled(isInteractionDisabled)
                    .accessibilityLabel("Continue existing session for \(choice.displayAccount)")
                    .accessibilityIdentifier("matrix.session.continue.\(choice.id)")
                }
                if let credential = choice.credential {
                    HyphaButton(
                        title: "Sign in with saved password",
                        systemImage: "key.fill",
                        variant: choice.session == nil ? .primary : .secondary,
                        fillsWidth: true
                    ) {
                        signInWithSavedPassword(credential)
                    }
                    .disabled(isInteractionDisabled)
                    .accessibilityLabel("Sign in with saved password for \(choice.displayAccount)")
                    .accessibilityIdentifier("matrix.password.saved.\(choice.id)")
                }
            }

            if horizontalSizeClass == .compact {
                VStack(spacing: ZenithDesign.Space.x2) {
                    deletionActions
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: ZenithDesign.Space.x2) {
                    deletionActions
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(ZenithDesign.Space.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ZenithDesign.Palette.baseSubtle.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: ZenithDesign.Radius.sheet, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ZenithDesign.Radius.sheet, style: .continuous)
                .stroke(ZenithDesign.Palette.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var deletionActions: some View {
        if let session = choice.session {
            HyphaButton(
                title: "Delete local session…",
                systemImage: "rectangle.portrait.and.arrow.right",
                variant: .quiet,
                fillsWidth: horizontalSizeClass == .compact
            ) {
                deleteLocalSession(session)
            }
            .disabled(isInteractionDisabled)
            .accessibilityLabel("Delete local session for \(choice.displayAccount)")
            .accessibilityIdentifier("matrix.session.delete.\(choice.id)")
        }
        if let credential = choice.credential {
            HyphaButton(
                title: "Delete saved password…",
                systemImage: "key.slash",
                variant: .quiet,
                fillsWidth: horizontalSizeClass == .compact
            ) {
                deleteSavedPassword(credential)
            }
            .disabled(isInteractionDisabled)
            .accessibilityLabel("Delete saved password for \(choice.displayAccount)")
            .accessibilityIdentifier("matrix.password.delete.\(choice.id)")
        }
    }

    private var capabilitySummary: String {
        switch (choice.session != nil, choice.credential != nil) {
        case (true, true): "Encrypted session and saved password available"
        case (true, false): "Encrypted session available"
        case (false, true): "Saved password available"
        case (false, false): "Account identity"
        }
    }
}
