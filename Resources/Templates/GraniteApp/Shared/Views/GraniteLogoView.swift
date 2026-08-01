import SwiftUI

struct GraniteLogoView: View {
    var size: CGFloat = 180

    var body: some View {
        Image("GraniteLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("Granite")
    }
}
