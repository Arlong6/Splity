import Testing
import SwiftData
import SwiftUI
import Foundation
@testable import Splity

/// 讓測試決定每個匯率請求何時回應。
@MainActor
private final class RateGate {
    private var pending: [String: CheckedContinuation<Decimal, Error>] = [:]

    func fetch(_ code: String) async throws -> Decimal {
        try await withCheckedThrowingContinuation { pending[code] = $0 }
    }

    func waitUntilRequested(_ code: String) async {
        while pending[code] == nil { await Task.yield() }
    }

    func respond(_ code: String, _ rate: Decimal) {
        pending.removeValue(forKey: code)?.resume(returning: rate)
    }
}

@MainActor
@Suite("切換幣別時的匯率回應順序")
struct ExchangeRateRaceTests {
    private func makeViewModel(gate: RateGate) -> ExpenseEditViewModel {
        let vm = ExpenseEditViewModel(group: Group(name: "東京", baseCurrencyCode: "TWD"))
        vm.rateFetcher = { from, _ in try await gate.fetch(from) }
        return vm
    }

    private func select(_ code: String, _ vm: ExpenseEditViewModel, _ gate: RateGate) async -> Task<Void, Never> {
        vm.selectedCurrencyCode = code
        vm.lockedRate = nil
        let task = Task { await vm.refreshExchangeRate() }
        await gate.waitUntilRequested(code)
        return task
    }

    @Test("舊幣別的回應晚到時，不會蓋掉目前幣別的匯率")
    func lateStaleResponseIgnored() async {
        let gate = RateGate()
        let vm = makeViewModel(gate: gate)
        let usd = await select("USD", vm, gate)
        let jpy = await select("JPY", vm, gate)

        gate.respond("JPY", Decimal(string: "0.21")!)
        await jpy.value
        gate.respond("USD", Decimal(string: "31.6")!)
        await usd.value

        #expect(vm.lockedRate == Decimal(string: "0.21")!)
        #expect(vm.isFetchingRate == false)
    }

    @Test("舊幣別先回應時，不鎖匯率，也不解除讀取中狀態")
    func earlyStaleResponseKeepsWaiting() async {
        let gate = RateGate()
        let vm = makeViewModel(gate: gate)
        let usd = await select("USD", vm, gate)
        let jpy = await select("JPY", vm, gate)

        gate.respond("USD", Decimal(string: "31.6")!)
        await usd.value

        #expect(vm.lockedRate == nil)
        #expect(vm.isFetchingRate == true)

        gate.respond("JPY", Decimal(string: "0.21")!)
        await jpy.value
        #expect(vm.lockedRate == Decimal(string: "0.21")!)
        #expect(vm.isFetchingRate == false)
    }

    @Test("請求途中切回本幣，晚到的回應不留下匯率或讀取中狀態")
    func switchBackToBaseCurrency() async {
        let gate = RateGate()
        let vm = makeViewModel(gate: gate)
        let usd = await select("USD", vm, gate)

        vm.selectedCurrencyCode = "TWD"
        await vm.refreshExchangeRate()
        #expect(vm.isFetchingRate == false)

        gate.respond("USD", Decimal(string: "31.6")!)
        await usd.value
        #expect(vm.lockedRate == nil)
        #expect(vm.isFetchingRate == false)
    }
}

@MainActor
@Suite("幣別選單")
struct CurrencyPickerSelectionTests {
    /// ExpenseEditView 的 setter 會清掉鎖定匯率並重抓；點已勾選的幣別不能觸發它。
    @Test("點已選中的幣別不會寫入 selection")
    func sameCodeDoesNotWrite() {
        var writes = 0
        let binding = Binding<String>(get: { "JPY" }, set: { _ in writes += 1 })
        CurrencyPickerView.select("JPY", into: binding)
        #expect(writes == 0)
    }

    @Test("點不同幣別會寫入")
    func differentCodeWrites() {
        var written: String?
        let binding = Binding<String>(get: { "JPY" }, set: { written = $0 })
        CurrencyPickerView.select("USD", into: binding)
        #expect(written == "USD")
    }
}
