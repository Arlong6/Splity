import Foundation
import UIKit

/// 「回報問題」寄出的那封信。
///
/// 重點在於**預填診斷資訊**：使用者按下去時，版本、機型、系統語言就已經在內文裡了。
/// 沒有這段的話，每一封回報都得先回信問「你是哪一版、什麼機型」，而多數人不會回第二次。
enum SupportMail {

    /// ⚠️ 這個位址會編進 binary，跟 `SplityLinks.webJoin` 的網域一樣，送審後改不掉，
    /// 要換得併進下一次發版。
    static let address = "tony0912045596@gmail.com"

    /// 附在信末的環境資訊。做成一包值而不是在函式裡直接讀系統，是為了能測。
    struct Diagnostics {
        let version: String
        let build: String?
        let device: String
        let systemVersion: String
        let language: String

        /// 從實機讀出目前的環境。
        static func current() -> Diagnostics {
            Diagnostics(
                version: AppVersion.short(),
                build: AppVersion.build(),
                device: hardwareIdentifier(),
                systemVersion: UIDevice.current.systemVersion,
                language: Locale.preferredLanguages.first ?? "unknown"
            )
        }

        /// `UIDevice.current.model` 只會回「iPhone」，分不出機型；uname 才拿得到
        /// `iPhone17,1` 這種識別碼，對重現問題有用。
        private static func hardwareIdentifier() -> String {
            var info = utsname()
            uname(&info)
            // machine 是個 C 的固定長度 char 陣列，在 Swift 裡是一大包 tuple。
            // 用 withUnsafePointer 取會撞上記憶體排他性檢查（取指標的同時還要讀它算長度），
            // 走訪 Mirror 沒有這個問題，也不必碰指標。
            let identifier = Mirror(reflecting: info.machine).children.reduce(into: "") { result, element in
                guard let byte = element.value as? Int8, byte != 0 else { return }
                result.append(Character(UnicodeScalar(UInt8(byte))))
            }
            return identifier.isEmpty ? "unknown" : identifier
        }
    }

    /// 顯示在信末的版本字串：`1.8.2 (18)`，沒有 build 號時只留版號。
    static func versionLine(_ diagnostics: Diagnostics) -> String {
        guard let build = diagnostics.build, !build.isEmpty else { return diagnostics.version }
        return "\(diagnostics.version) (\(build))"
    }

    /// 組出 `mailto:` 連結。
    ///
    /// 用 `URLComponents` 而不是自己串字串：內文會包含換行、`&`、`#`，手動組會在第一個
    /// `&` 就把 query 切斷，使用者拿到的信會只剩半截。
    static func url(body: String, diagnostics: Diagnostics = .current()) -> URL? {
        let footer = """


        ——————————
        Splity \(versionLine(diagnostics))
        \(diagnostics.device) · iOS \(diagnostics.systemVersion)
        \(diagnostics.language)
        """

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: localized("Splity 問題回報 \(versionLine(diagnostics))")),
            URLQueryItem(name: "body", value: body + footer),
        ]
        return components.url
    }
}
