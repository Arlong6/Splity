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
# App Store Connect API key：從終端機以外的環境（例如 Claude Code）跑時，
# Xcode 的 Apple 帳號 session 拿不到，會噴「Failed to Use Accounts」；API key 不受影響。
ASC_KEY_ID="RJ9M36258H"
ASC_ISSUER_ID="83751deb-a3d0-41ca-96b5-649816dc27f9"
ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"

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

# ── 讀寫版號（一律透過 scripts/version.rb）──────────────────────────────────
# 這裡刻意不用 grep/sed 直接碰 project.pbxproj：
#   讀：MARKETING_VERSION 在檔案裡出現 6 次（app target 兩份、測試 target 四份），
#       `grep -m1` 拿到哪一個取決於 target 在檔案裡的排列順序，順序一變就會讀到
#       測試 target 的 1.0。
#   寫：`sed -i '' "s/MARKETING_VERSION = .*;/.../g"` 會把六處全部改掉，測試 target
#       的 1.0 會被寫成正式版號。
# version.rb 用 xcodeproj gem，只動 Splity target 的 Debug/Release 兩份。
PBXPROJ="$PROJECT_DIR/Splity.xcodeproj/project.pbxproj"
VERSION_TOOL="$PROJECT_DIR/scripts/version.rb"

ruby -e "require 'xcodeproj'" 2>/dev/null \
  || fail "缺少 xcodeproj gem，版號改寫需要它（gem install xcodeproj）。原因見 scripts/version.rb 開頭。"

set_versions() {
  "$VERSION_TOOL" set "$1" "$2" || fail "版號寫入失敗"
  plutil -lint "$PBXPROJ" >/dev/null \
    || fail "版號寫入後 project.pbxproj 格式異常，請用 git checkout 還原後再試"
}

# ── 步驟 1：顯示目前版本 ──────────────────────────────────────────────────────
VERSIONS="$("$VERSION_TOOL" read)" || fail "讀取版號失敗"
[ -n "$VERSIONS" ] || fail "讀取版號失敗（version.rb 沒有輸出）"
CURRENT_VERSION="${VERSIONS%% *}"
CURRENT_BUILD="${VERSIONS##* }"
[[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]] || fail "Build 號不是數字：$CURRENT_BUILD"
log "目前版本：$CURRENT_VERSION ($CURRENT_BUILD)"

# ── 步驟 2：詢問是否要更新版號 ────────────────────────────────────────────────
echo ""
echo "要更新版號嗎？（目前：${CURRENT_VERSION}，Build ${CURRENT_BUILD}）"
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
    set_versions "$CURRENT_VERSION" "$NEW_BUILD"
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
    set_versions "$NEW_VERSION" "$NEW_BUILD"
    ok "版本更新為 $NEW_VERSION ($NEW_BUILD)"
    ;;
  5)
    read -r -p "輸入新版號（例：1.2.0）：" CUSTOM_VERSION
    read -r -p "輸入新 Build 號（目前：${CURRENT_BUILD}）：" CUSTOM_BUILD
    set_versions "$CUSTOM_VERSION" "$CUSTOM_BUILD"
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
    -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
    -only-testing:SplityTests \
    -quiet \
    || fail "單元測試失敗，已中止上架"
  ok "測試通過"
else
  log "（跳過測試）"
fi

# ── 步驟 3.5：在地化完整性 ────────────────────────────────────────────────────
log "檢查在地化..."
"$PROJECT_DIR/scripts/check_localization.sh" || fail "在地化檢查未通過，已中止上架"

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
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  -allowProvisioningUpdates \
  || fail "上傳失敗"
ok "上傳完成！"

# ── 完成 ──────────────────────────────────────────────────────────────────────
FINAL_VERSIONS="$("$VERSION_TOOL" read)" || fail "讀取版號失敗"
FINAL_VERSION="${FINAL_VERSIONS%% *}"
FINAL_BUILD="${FINAL_VERSIONS##* }"
echo ""
echo "══════════════════════════════════════════"
echo "  上架完成 🎉"
echo "  版本：$FINAL_VERSION (Build $FINAL_BUILD)"
echo "  封存：$ARCHIVE_PATH"
echo ""
echo "  下一步：到 App Store Connect 提交審查"
echo "  https://appstoreconnect.apple.com"
echo "══════════════════════════════════════════"
