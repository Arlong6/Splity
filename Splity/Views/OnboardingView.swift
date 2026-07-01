import SwiftUI

private struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
}

private let pages: [OnboardingPage] = [
    OnboardingPage(
        icon: "person.3.fill",
        title: String(localized: "建立群組"),
        description: String(localized: "為每次旅遊、聚餐建立專屬群組，把所有成員加進來")
    ),
    OnboardingPage(
        icon: "creditcard.fill",
        title: String(localized: "記錄費用"),
        description: String(localized: "每筆消費都記得清清楚楚，選擇誰付款、平均分攤或自訂金額")
    ),
    OnboardingPage(
        icon: "arrow.left.arrow.right.circle.fill",
        title: String(localized: "一鍵結算"),
        description: String(localized: "自動計算最少轉帳次數，誰欠誰多少一目了然")
    ),
    OnboardingPage(
        icon: "checkmark.seal.fill",
        title: String(localized: "輕鬆完成"),
        description: String(localized: "結算完畢後封存群組，歷史紀錄隨時查閱")
    )
]

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var currentPage = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemIndigo), Color(.systemPurple)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    ForEach(pages.indices, id: \.self) { index in
                        pageView(pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                bottomBar
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)
            }
        }
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: page.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .foregroundStyle(.white)
                .padding(32)
                .background(.white.opacity(0.15), in: Circle())

            VStack(spacing: 12) {
                Text(page.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(page.description)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()
            Spacer()
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 24) {
            // 點點指示器
            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(index == currentPage ? 1 : 0.4))
                        .frame(width: index == currentPage ? 20 : 8, height: 8)
                        .animation(.spring(duration: 0.3), value: currentPage)
                }
            }

            // 按鈕
            if currentPage < pages.count - 1 {
                HStack {
                    Button("跳過") {
                        hasSeenOnboarding = true
                    }
                    .foregroundStyle(.white.opacity(0.7))

                    Spacer()

                    Button {
                        withAnimation {
                            currentPage += 1
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("下一步")
                            Image(systemName: "chevron.right")
                        }
                        .font(.headline)
                        .foregroundStyle(Color(.systemIndigo))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.white, in: Capsule())
                    }
                    .accessibilityLabel("下一步")
                }
            } else {
                Button {
                    hasSeenOnboarding = true
                } label: {
                    Text("開始使用")
                        .font(.headline)
                        .foregroundStyle(Color(.systemIndigo))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white, in: Capsule())
                }
            }
        }
    }
}
