#!/bin/bash
# 在地化完整性檢查。
#
# 為什麼需要這支腳本：命令列 `xcodebuild` 只會產生 .stringsdata，不會像 Xcode.app
# 那樣把新的字串寫回 Localizable.xcstrings。所以只要沒人用 Xcode.app 建置過，
# 新加的 Text("…")／Button("…") 就會悄悄不在 catalog 裡，英文機直接看到中文。
#
# 用法：./scripts/check_localization.sh   （需要先建置過一次）
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CATALOG="$PROJECT_DIR/Splity/Localizable.xcstrings"

BUILD_DIR=$(ls -td "$HOME/Library/Developer/Xcode/DerivedData/Splity-"*/Build/Intermediates.noindex/Splity.build/*/Splity.build 2>/dev/null | head -1 || true)
if [ -z "$BUILD_DIR" ]; then
  echo "✗ 找不到建置產物，請先跑一次 xcodebuild build" >&2
  exit 1
fi

python3 - "$BUILD_DIR" "$CATALOG" <<'PY'
import sys, pathlib, json, re

build_dir, catalog_path = pathlib.Path(sys.argv[1]), sys.argv[2]

extracted = set()
for f in build_dir.rglob('*.stringsdata'):
    try:
        data = json.loads(f.read_text())
    except Exception:
        continue
    for entry in (data.get('tables', {}).get('Localizable') or []):
        extracted.add(entry['key'])

catalog = json.load(open(catalog_path))['strings']
han = re.compile(r'[一-鿿]')

missing = sorted(k for k in extracted - set(catalog) if han.search(k))
untranslated = sorted(
    k for k, v in catalog.items()
    if han.search(v.get('localizations', {}).get('en', {}).get('stringUnit', {}).get('value', ''))
)
no_english = sorted(k for k, v in catalog.items() if 'en' not in v.get('localizations', {}))

print(f"編譯器擷取 {len(extracted)} 個 key，catalog {len(catalog)} 個")

problems = 0
for label, items in (
    ("不在 catalog 裡（英文機會看到中文）", missing),
    ("沒有英文條目", no_english),
    ("英文值仍是中文", untranslated),
):
    if items:
        problems += len(items)
        print(f"\n✗ {len(items)} 個 {label}：")
        for k in items:
            print(f"    {k!r}")

if problems:
    print(f"\n共 {problems} 個問題。用 String(localized:) 包起來（純 String 情境），"
          f"並在 Localizable.xcstrings 補上英文。")
    sys.exit(1)

print("✓ 在地化完整")
PY
