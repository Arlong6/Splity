import Foundation

/// 幣別資訊 + 匯率 API（exchangerate-api.com 的 open.er-api.com 免費端點，支援 TWD）
@Observable
final class CurrencyService {
    static let shared = CurrencyService()

    /// 常用幣別清單（依使用頻率排序，台灣旅遊常見目的地優先）
    static let common: [String] = [
        "TWD", "USD", "JPY", "KRW", "EUR", "GBP",
        "HKD", "SGD", "CNY", "THB", "VND", "MYR",
        "IDR", "AUD", "CAD", "PHP", "CHF", "NZD"
    ]

    /// open.er-api.com 支援的常見幣別（節錄；實際會回傳 160+ 個幣別都可用）
    static let allSupported: [String] = [
        "AED", "AUD", "BGN", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR",
        "GBP", "HKD", "HUF", "IDR", "ILS", "INR", "ISK", "JPY", "KRW", "MXN",
        "MYR", "NOK", "NZD", "PHP", "PLN", "RON", "SEK", "SGD", "THB", "TRY",
        "TWD", "USD", "VND", "ZAR"
    ]

    static func displayName(for code: String) -> String {
        let locale = Locale(identifier: "zh-Hant")
        return locale.localizedString(forCurrencyCode: code) ?? code
    }

    /// 用 ISO 4217 currency code 反推發行地區國旗 emoji。台幣特例。
    static func flag(for code: String) -> String {
        let countryByCurrency: [String: String] = [
            "TWD": "TW", "USD": "US", "JPY": "JP", "KRW": "KR",
            "EUR": "EU", "GBP": "GB", "HKD": "HK", "SGD": "SG",
            "CNY": "CN", "THB": "TH", "VND": "VN", "MYR": "MY",
            "IDR": "ID", "AUD": "AU", "CAD": "CA", "PHP": "PH",
            "CHF": "CH", "NZD": "NZ", "BGN": "BG", "BRL": "BR",
            "CZK": "CZ", "DKK": "DK", "HUF": "HU", "ILS": "IL",
            "INR": "IN", "ISK": "IS", "MXN": "MX", "NOK": "NO",
            "PLN": "PL", "RON": "RO", "SEK": "SE", "TRY": "TR",
            "ZAR": "ZA", "AED": "AE"
        ]
        guard let region = countryByCurrency[code] else { return "💱" }
        if region == "EU" { return "🇪🇺" }
        let scalars = region.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }
        return String(String.UnicodeScalarView(scalars))
    }

    /// 幣別符號（NT$、¥、₩…）
    static func symbol(for code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.currencySymbol ?? code
    }

    private struct ERAPIResponse: Decodable {
        let result: String
        let base_code: String?
        let rates: [String: Double]?
    }

    enum FetchError: LocalizedError {
        case invalidResponse
        case rateNotFound

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "匯率服務回應異常"
            case .rateNotFound:    return "找不到此幣別的匯率"
            }
        }
    }

    /// 抓最新匯率 from→to（open.er-api.com）。失敗會 throw。
    /// 該 API 每日更新一次，UTC 00:00 換新值。
    func fetchLatestRate(from: String, to: String) async throws -> Decimal {
        if from == to { return 1 }
        let urlString = "https://open.er-api.com/v6/latest/\(from)"
        guard let url = URL(string: urlString) else { throw FetchError.invalidResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw FetchError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(ERAPIResponse.self, from: data)
        guard decoded.result == "success", let rate = decoded.rates?[to] else {
            throw FetchError.rateNotFound
        }
        return Decimal(rate)
    }
}
