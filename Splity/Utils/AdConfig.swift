import Foundation

/// AdMob 識別碼集中在這裡。
///
/// App ID 另外還要寫在 `Info.plist` 的 `GADApplicationIdentifier`（SDK 只讀那裡），
/// 這裡留一份是為了讓 code review 時看得到兩邊有沒有對上。
///
/// Debug 一律用 Google 官方測試 unit ID：用正式 ID 在開發機上點廣告會被 AdMob 判定無效流量，
/// 嚴重的話整個帳號被停權。
enum AdConfig {
    /// 與 Info.plist 的 GADApplicationIdentifier 相同。
    static let applicationID = "ca-app-pub-7924270643823556~2284679641"

    static let removeAdsProductID = "com.arlongchien.Splity.removeAds"

    #if DEBUG
    static let bannerUnitID = "ca-app-pub-3940256099942544/2435281174"
    static let interstitialUnitID = "ca-app-pub-3940256099942544/4411468910"
    #else
    static let bannerUnitID = "ca-app-pub-7924270643823556/9739574391"
    static let interstitialUnitID = "ca-app-pub-7924270643823556/7070936613"
    #endif
}
