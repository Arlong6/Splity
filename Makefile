# Splity 開發指令
# 用法：make <指令>

.PHONY: help test test-ui release release-skip-tests version clean

help:
	@echo ""
	@echo "Splity 可用指令："
	@echo "  make test              執行單元測試"
	@echo "  make test-ui           執行 UI 測試（iPhone 16 模擬器）"
	@echo "  make test-all          執行全部測試"
	@echo "  make release           完整上架流程（測試 → 封存 → 上傳）"
	@echo "  make release-fast      跳過測試直接上架"
	@echo "  make version           顯示目前版號"
	@echo "  make clean             清除 build 資料夾"
	@echo ""

# ── 測試 ──────────────────────────────────────────────────────────────────────

test:
	xcodebuild test \
	  -scheme Splity \
	  -destination 'platform=iOS Simulator,name=iPhone 16' \
	  -only-testing:SplityTests \
	  -quiet

test-ui:
	xcodebuild test \
	  -scheme Splity \
	  -destination 'platform=iOS Simulator,name=iPhone 16' \
	  -only-testing:SplityUITests \
	  -quiet

test-all:
	xcodebuild test \
	  -scheme Splity \
	  -destination 'platform=iOS Simulator,name=iPhone 16' \
	  -quiet

# ── 上架 ──────────────────────────────────────────────────────────────────────

release:
	@bash scripts/release.sh

release-fast:
	@bash scripts/release.sh --skip-tests

# ── 工具 ──────────────────────────────────────────────────────────────────────

version:
	@echo "版本：$$(xcrun agvtool what-marketing-version -terse1)"
	@echo "Build：$$(xcrun agvtool what-version -terse)"

clean:
	rm -rf build/
	@echo "已清除 build 資料夾"
