import SwiftUI

extension View {
    func appCard(padding: CGFloat = 16) -> some View {
        modifier(AppCardModifier(padding: padding))
    }

    func readableContentWidth(_ maximumWidth: CGFloat = 720) -> some View {
        frame(maxWidth: maximumWidth)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    func appTransform<Content: View>(
        when condition: Bool,
        @ViewBuilder transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

private struct AppCardModifier: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.primary.opacity(0.08), lineWidth: 1)
            }
    }
}
