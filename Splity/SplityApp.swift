import SwiftUI
import SwiftData

@main
struct SplityApp: App {
    @AppStorage("appLanguage") private var appLanguage = "zh-Hant"

    var body: some Scene {
        WindowGroup {
            SplashView()
                .environment(\.locale, Locale(identifier: appLanguage))
        }
        .modelContainer(for: [Group.self, Member.self, Expense.self, ExpenseSplit.self, HistoryRecord.self])
    }
}

