import SwiftUI

/// 「誰轉給誰多少」卡片。群組結算與快速分帳共用。
struct SettlementCardView: View {
    let fromName: String
    let toName: String
    let amount: Decimal
    let currencyCode: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                // Payer
                VStack(spacing: 8) {
                    avatarCircle(name: fromName, color: .red)
                    Text(fromName)
                        .font(.caption.bold())
                        .lineLimit(1)
                }
                .frame(minWidth: 70)

                // Arrow + Amount
                VStack(spacing: 6) {
                    Text(amount, format: .currency(code: currencyCode))
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            LinearGradient(
                                colors: [.orange, Color(red: 1, green: 0.4, blue: 0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: .orange.opacity(0.3), radius: 4, x: 0, y: 2)

                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.orange.opacity(0.35))
                            .frame(height: 2)
                        Image(systemName: "arrowtriangle.right.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity)

                // Receiver
                VStack(spacing: 8) {
                    avatarCircle(name: toName, color: .green)
                    Text(toName)
                        .font(.caption.bold())
                        .lineLimit(1)
                }
                .frame(minWidth: 70)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)

            // Footer label
            HStack {
                Image(systemName: "hand.tap")
                    .font(.caption2)
                Text("\(fromName) 轉給 \(toName)")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(.tertiarySystemGroupedBackground))
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
    }

    private func avatarCircle(name: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 54, height: 54)
            Circle()
                .strokeBorder(color.opacity(0.3), lineWidth: 1.5)
                .frame(width: 54, height: 54)
            Text(String(name.prefix(1)))
                .font(.title2.bold())
                .foregroundStyle(color)
        }
    }
}
