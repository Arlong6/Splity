import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseAppCheck

/// App Check provider 工廠：release 版用 App Attest（裝置硬體認證），
/// debug/模擬器用 Debug provider（首次執行會在 console 印出 debug token，需到
/// Firebase Console → App Check 註冊該 token 才能通過驗證）。
/// 注意：要等 Console 完成註冊並啟用 enforcement 後才會真正生效；在那之前只是
/// 默默產生 token、不影響現有請求，屬安全漸進式上線。
final class SplityAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if DEBUG
        return AppCheckDebugProvider(app: app)
        #else
        return AppAttestProvider(app: app)
        #endif
    }
}

// 註：不使用 SchemaMigrationPlan/VersionedSchema。先前用 V1/V2 兩個版本化 schema 但兩者
// 指向同一批 model 類別 → checksum 相同 → SwiftData 建立遷移階段時擲出
// "Duplicate version checksums detected" 並在啟動時崩潰（見 1.7.0 上線後的閃退）。
// `isEvenSplit` 這種「新增可選欄位」屬於 SwiftData 能自動處理的輕量遷移，用單一 Schema 即可。

@main
struct SplityApp: App {
    @AppStorage("appLanguage") private var appLanguage = "zh-Hant"
    @Environment(\.scenePhase) private var scenePhase
    @State private var sharingManager = FirebaseSharingManager.shared

    let container: ModelContainer

    init() {
        let isTest = Bundle.allBundles.contains { $0.bundleURL.pathExtension == "xctest" }
            || UserDefaults.standard.bool(forKey: "IS_UI_TESTING")
        if !isTest {
            // App Check 的 provider factory 必須在 configure() 之前設定
            AppCheck.setAppCheckProviderFactory(SplityAppCheckProviderFactory())
            FirebaseApp.configure()
        }

        if ProcessInfo.processInfo.arguments.contains("-UIResetDefaults") {
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        }

        let schema = Schema([Group.self, Member.self, Expense.self, ExpenseSplit.self, HistoryRecord.self])
        // Detect unit tests (xctest bundle injected) or UI tests (UserDefaults arg set by test helpers)
        let isTestEnvironment = Bundle.allBundles.contains { $0.bundleURL.pathExtension == "xctest" }
            || UserDefaults.standard.bool(forKey: "IS_UI_TESTING")

        if isTestEnvironment {
            // 測試環境：明確關閉 CloudKit，避免 schema 驗證失敗
            let config = ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            do {
                container = try ModelContainer(
                    for: Group.self, Member.self, Expense.self, ExpenseSplit.self, HistoryRecord.self,
                    configurations: config
                )
            } catch {
                fatalError("Test ModelContainer failed: \(error)")
            }
        } else {
            // 正式環境：先試本機儲存。失敗時「不刪除」使用者資料 —
            // 改成把舊 store（含 -wal/-shm）改名備份後再重試，避免暫時性 I/O 錯誤或未來
            // 無法輕量遷移的 schema 變更造成使用者帳本被永久清空（資料保留在備份檔可挽救）。
            let storeURL = URL.applicationSupportDirectory.appendingPathComponent("default.store")
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            do {
                container = try ModelContainer(for: schema, configurations: config)
            } catch {
                let stamp = Int(Date().timeIntervalSince1970)
                for ext in ["", "-wal", "-shm"] {
                    let original = URL(fileURLWithPath: storeURL.path + ext)
                    guard FileManager.default.fileExists(atPath: original.path) else { continue }
                    let backup = URL(fileURLWithPath: storeURL.path + ext + ".corrupt-\(stamp).bak")
                    try? FileManager.default.moveItem(at: original, to: backup)
                }
                // 備份後以全新 store 重試；仍失敗才退回記憶體容器（原始資料仍在 .bak 備份）
                container = (try? ModelContainer(for: schema, configurations: config))
                    ?? (try! ModelContainer(
                        for: Group.self, Member.self, Expense.self, ExpenseSplit.self, HistoryRecord.self,
                        configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
                    ))
            }
        }

        // 背景任務 handler 必須在 app 完成啟動前註冊
        if !isTest {
            ActivityNotifier.register(container: container)
        }
    }

    var body: some Scene {
        WindowGroup {
            SplashView()
                .environment(\.locale, Locale(identifier: appLanguage))
                .environment(sharingManager)
                .task { try? await sharingManager.signInAnonymously() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        ActivityNotifier.scheduleNext()
                    }
                }
        }
        .modelContainer(container)
    }
}
