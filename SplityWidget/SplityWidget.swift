import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct SplityEntry: TimelineEntry {
    let date: Date
    let activeGroupCount: Int
    let totalExpenseCount: Int
}

// MARK: - Provider

struct SplityProvider: TimelineProvider {

    func placeholder(in context: Context) -> SplityEntry {
        SplityEntry(date: Date(), activeGroupCount: 2, totalExpenseCount: 8)
    }

    func getSnapshot(in context: Context, completion: @escaping (SplityEntry) -> Void) {
        let entry = loadEntry() ?? SplityEntry(date: Date(), activeGroupCount: 0, totalExpenseCount: 0)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SplityEntry>) -> Void) {
        let entry = loadEntry() ?? SplityEntry(date: Date(), activeGroupCount: 0, totalExpenseCount: 0)
        // 每 15 分鐘更新一次
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(next))
        completion(timeline)
    }

    private func loadEntry() -> SplityEntry? {
        guard let storeURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.arlongchien.Splity")?
            .appendingPathComponent("splity_widget.json") else { return nil }

        guard let data = try? Data(contentsOf: storeURL),
              let payload = try? JSONDecoder().decode(WidgetPayload.self, from: data) else {
            return nil
        }

        return SplityEntry(
            date: Date(),
            activeGroupCount: payload.activeGroupCount,
            totalExpenseCount: payload.totalExpenseCount
        )
    }
}

struct WidgetPayload: Codable {
    let activeGroupCount: Int
    let totalExpenseCount: Int
}

// MARK: - Small Widget View

struct SplityWidgetSmallView: View {
    let entry: SplityEntry

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.sRGB, red: 0.345, green: 0.337, blue: 0.839),
                         Color(.sRGB, red: 0.686, green: 0.322, blue: 0.871)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Splity")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    statRow(icon: "folder.fill", value: "\(entry.activeGroupCount)", label: "進行中")
                    statRow(icon: "yensign", value: "\(entry.totalExpenseCount)", label: "筆花費")
                }
            }
            .padding(14)
        }
    }

    private func statRow(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 14)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}

// MARK: - Medium Widget View

struct SplityWidgetMediumView: View {
    let entry: SplityEntry

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.sRGB, red: 0.345, green: 0.337, blue: 0.839),
                         Color(.sRGB, red: 0.686, green: 0.322, blue: 0.871)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        Text("Splity")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Text("輕鬆分帳，清楚明瞭")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.leading, 16)

                Spacer()

                HStack(spacing: 16) {
                    statBadge(icon: "folder.fill", value: "\(entry.activeGroupCount)", label: "進行中")
                    statBadge(icon: "yensign", value: "\(entry.totalExpenseCount)", label: "筆花費")
                }
                .padding(.trailing, 16)
            }
        }
    }

    private func statBadge(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Widget Configuration

struct SplityWidget: Widget {
    let kind: String = "SplityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SplityProvider()) { entry in
            SplityWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Splity")
        .description("查看進行中的帳本與花費筆數")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SplityWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: SplityEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SplityWidgetSmallView(entry: entry)
        case .systemMedium:
            SplityWidgetMediumView(entry: entry)
        default:
            SplityWidgetSmallView(entry: entry)
        }
    }
}

// MARK: - Bundle

@main
struct SplityWidgetBundle: WidgetBundle {
    var body: some Widget {
        SplityWidget()
    }
}
