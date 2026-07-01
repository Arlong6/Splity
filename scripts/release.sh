#!/bin/bash
# ==============================================================================
# Splity 自動化上架腳本
# 用法：
#   ./scripts/release.sh              # 執行完整流程（測試 → 封存 → 上傳）
#   ./scripts/release.sh --skip-tests # 跳過測試，直接封存上傳
# ==============================================================================

set -euo pipefail

# ── 設定 ──────────────────────────────────────────────────────────────────────
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="Splity"
EXPORT_OPTIONS="$PROJECT_DIR/ExportOptions.plist"
ARCHIVE_DIR="$PROJECT_DIR/build/archives"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ARCHIVE_PATH="$ARCHIVE_DIR/Splity_$TIMESTAMP.xcarchive"
SKIP_TESTS=false

# ── 參數解析 ──────────────────────────────────────────────────────────────────
for arg in "$@"; do
  case $arg in
    --skip-tests) SKIP_TESTS=true ;;
  esac
done

# ── 輔助函數 ──────────────────────────────────────────────────────────────────
log()  { echo "▶ $*"; }
ok()   { echo "✓ $*"; }
fail() { echo "✗ $*" >&2; exit 1; }

# ── 切換到專案目錄 ────────────────────────────────────────────────────────────
cd "$PROJECT_DIR"

# ── 讀取版號（直接從 project.pbxproj）────────────────────────────────────────
PBXPROJ="$PROJECT_DIR/Splity.xcodeproj/project.pbxproj"

read_version() {
  grep -m1 "MARKETING_VERSION" "$PBXPROJ" | sed 's/.*= \(.*\);/\1/' | tr -d '[:space:]'
}
read_build() {
  grep -m1 "CURRENT_PROJECT_VERSION" "$PBXPROJ" | sed 's/.*= \(.*\);/\1/' | tr -d '[:space:]'
}
set_version() {
  sed -i '' "s/MARKETING_VERSION = .*;/MARKETING_VERSION = $1;/g" "$PBXPROJ"
}
set_build() {
  sed -i '' "s/CURRENT_PROJECT_VERSION = .*;/CURRENT_PROJECT_VERSION = $1;/g" "$PBXPROJ"
}

# ── 步驟 1：顯示目前版本 ──────────────────────────────────────────────────────
CURRENT_VERSION=$(read_version)
CURRENT_BUILD=$(read_build)
log "目前版本：$CURRENT_VERSION ($CURRENT_BUILD)"

# ── 步驟 2：詢問是否要更新版號 ────────────────────────────────────────────────
echo ""
echo "要更新版號嗎？（目前：$CURRENT_VERSION，Build $CURRENT_BUILD）"
echo "  1) 只升 Build 號（$CURRENT_BUILD → $((CURRENT_BUILD + 1))）"
echo "  2) 升 Patch 版本（例：1.0 → 1.0.1）"
echo "  3) 升 Minor 版本（例：1.0 → 1.1）"
echo "  4) 升 Major 版本（例：1.0 → 2.0）"
echo "  5) 自訂版號"
echo "  n) 不更新"
read -r -p "選擇 [1/2/3/4/5/n]：" VERSION_CHOICE

case $VERSION_CHOICE in
  1)
    NEW_BUILD=$((CURRENT_BUILD + 1))
    set_build "$NEW_BUILD"
    ok "Build 號更新為 $NEW_BUILD"
    ;;
  2|3|4)
    IFS='.' read -ra PARTS <<< "$CURRENT_VERSION"
    MAJOR=${PARTS[0]:-1}; MINOR=${PARTS[1]:-0}; PATCH=${PARTS[2]:-0}
    case $VERSION_CHOICE in
      2) PATCH=$((PATCH + 1)) ;;
      3) MINOR=$((MINOR + 1)); PATCH=0 ;;
      4) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    esac
    NEW_VERSION="$MAJOR.$MINOR.$PATCH"
    NEW_BUILD=$((CURRENT_BUILD + 1))
    set_version "$NEW_VERSION"
    set_build "$NEW_BUILD"
    ok "版本更新為 $NEW_VERSION ($NEW_BUILD)"
    ;;
  5)
    read -r -p "輸入新版號（例：1.2.0）：" CUSTOM_VERSION
    read -r -p "輸入新 Build 號（目前：$CURRENT_BUILD）：" CUSTOM_BUILD
    set_version "$CUSTOM_VERSION"
    set_build "$CUSTOM_BUILD"
    ok "版本更新為 $CUSTOM_VERSION ($CUSTOM_BUILD)"
    ;;
  n|N|*)
    log "略過版號更新"
    ;;
esac

# ── 步驟 3：執行測試 ──────────────────────────────────────────────────────────
if [ "$SKIP_TESTS" = false ]; then
  log "執行單元測試..."
  xcodebuild test \
    -scheme "$SCHEME" \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    -only-testing:SplityTests \
    -quiet \
    || fail "單元測試失敗，已中止上架"
  ok "測試通過"
else
  log "（跳過測試）"
fi

# ── 步驟 4：封存（Archive）────────────────────────────────────────────────────
mkdir -p "$ARCHIVE_DIR"
log "封存中（這需要幾分鐘）..."
xcodebuild archive \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  INFOPLIST_KEY_ITSAppUsesNonExemptEncryption=NO \
  -quiet \
  || fail "封存失敗"
ok "封存完成：$ARCHIVE_PATH"

# ── 步驟 5：上傳到 App Store Connect ─────────────────────────────────────────
log "上傳到 App Store Connect..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$ARCHIVE_DIR/export_$TIMESTAMP" \
  || fail "上傳失敗"
ok "上傳完成！"

# ── 完成 ──────────────────────────────────────────────────────────────────────
FINAL_VERSION=$(read_version)
FINAL_BUILD=$(read_build)
echo ""
echo "══════════════════════════════════════════"
echo "  上架完成 🎉"
echo "  版本：$FINAL_VERSION (Build $FINAL_BUILD)"
echo "  封存：$ARCHIVE_PATH"
echo ""
echo "  下一步：到 App Store Connect 提交審查"
echo "  https://appstoreconnect.apple.com"
echo "══════════════════════════════════════════"
