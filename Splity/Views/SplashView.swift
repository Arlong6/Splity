import SwiftUI

struct SplashView: View {
    @State private var iconScale: CGFloat = 0.4
    @State private var iconOpacity: Double = 0
    @State private var titleOffset: CGFloat = 20
    @State private var titleOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    @State private var isFinished = false

    var body: some View {
        if isFinished {
            GroupListView()
                .transition(.opacity)
        } else {
            splashContent
                .transition(.opacity)
        }
    }

    private var splashContent: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemIndigo), Color(.systemPurple)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "arrow.triangle.branch")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundStyle(.white)
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)

                VStack(spacing: 6) {
                    Text("Splity")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .offset(y: titleOffset)
                        .opacity(titleOpacity)

                    Text("輕鬆分帳，清楚明瞭")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .opacity(subtitleOpacity)
                }
            }
        }
        .onAppear { startAnimation() }
    }

    private func startAnimation() {
        withAnimation(.spring(duration: 0.6)) {
            iconScale = 1.0
            iconOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
            titleOffset = 0
            titleOpacity = 1.0
        }
        withAnimation(.easeIn(duration: 0.4).delay(0.6)) {
            subtitleOpacity = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.5)) {
                isFinished = true
            }
        }
    }
}
