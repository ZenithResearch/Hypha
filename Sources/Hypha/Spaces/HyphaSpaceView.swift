import SwiftUI
import HyphaCore

struct HyphaSpaceView: View {
    let space: MatrixRoomSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenithDesign.Space.x6) {
                spaceHeader
                hierarchyCard
                identityFooter
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, ZenithDesign.Space.x6)
            .padding(.vertical, ZenithDesign.Space.x6)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(ZenithDesign.Palette.base)
        .accessibilityIdentifier("matrix.space.detail")
    }

    private var spaceHeader: some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x3) {
            Label("MATRIX SPACE", systemImage: "square.grid.2x2.fill")
                .font(ZenithDesign.Typography.technical(size: 12, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(ZenithDesign.Palette.brand)

            Text(space.name)
                .font(ZenithDesign.Typography.corporate(.largeTitle, weight: .semibold))
                .foregroundStyle(ZenithDesign.Palette.content)
                .textSelection(.enabled)

            Text(space.topic?.nilIfBlank ?? "A shared container for related rooms.")
                .font(ZenithDesign.Typography.corporate(.title3, weight: .regular))
                .foregroundStyle(ZenithDesign.Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var hierarchyCard: some View {
        HStack(alignment: .top, spacing: ZenithDesign.Space.x4) {
            Image(systemName: "rectangle.3.group.fill")
                .font(ZenithDesign.Typography.technical(.title2, weight: .semibold))
                .foregroundStyle(ZenithDesign.Palette.brand)
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: ZenithDesign.Space.x2) {
                Text("ROOM HIERARCHY")
                    .font(ZenithDesign.Typography.technical(size: 11, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(ZenithDesign.Palette.brand)

                Text("Spaces organize rooms; they are not chat timelines.")
                    .font(ZenithDesign.Typography.corporate(.title3, weight: .semibold))
                    .foregroundStyle(ZenithDesign.Palette.content)

                Text("Matrix connects rooms and subspaces with m.space.child state events. Hypha recognizes this m.space container and keeps the message composer out of the Space view.")
                    .font(ZenithDesign.Typography.corporate(.body, weight: .regular))
                    .foregroundStyle(ZenithDesign.Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(ZenithDesign.Space.x5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ZenithDesign.Palette.baseRaised)
        .clipShape(
            RoundedRectangle(
                cornerRadius: ZenithDesign.Radius.card,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: ZenithDesign.Radius.card,
                style: .continuous
            )
            .stroke(ZenithDesign.Palette.border, lineWidth: 1)
        }
    }

    private var identityFooter: some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
            Text("SPACE ID")
                .font(ZenithDesign.Typography.technical(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(ZenithDesign.Palette.muted)
            Text(space.id)
                .font(ZenithDesign.Typography.technical(size: 12, weight: .regular))
                .foregroundStyle(ZenithDesign.Palette.content)
                .textSelection(.enabled)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
