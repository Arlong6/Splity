#!/usr/bin/env python3
"""App Store Connect 送審工具（不經 Xcode 帳號 session，用 API key）。

用法：
  scripts/asc_submit.py status
      列出最近的 build 與版本狀態。
  scripts/asc_submit.py submit --version 1.8.1 --build 17 --notes notes.txt [--yes]
      建立（或沿用）該版本、附上 build、寫入 zh-Hant 更新說明、提交審查。
      預設會先印出摘要並要求確認；--yes 跳過。

需求：PyJWT + cryptography（pyenv 3.10.11 已有；若 python3 報 pyenv 版本錯誤，
前面加 PYENV_VERSION=3.10.11）。API key 與 release.sh 共用。
"""
import argparse, json, os, sys, time, urllib.error, urllib.request

import jwt

KEY_ID = os.environ.get("ASC_KEY_ID", "RJ9M36258H")
ISSUER_ID = os.environ.get("ASC_ISSUER_ID", "83751deb-a3d0-41ca-96b5-649816dc27f9")
KEY_PATH = os.environ.get(
    "ASC_KEY_PATH", os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8"))
BUNDLE_ID = "com.arlongchien.Splity"
BASE = "https://api.appstoreconnect.apple.com/v1"
LOCALE = "zh-Hant"
REUSABLE_STATES = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
                   "METADATA_REJECTED", "INVALID_BINARY"}


def token():
    now = int(time.time())
    with open(KEY_PATH) as f:
        key = f.read()
    return jwt.encode({"iss": ISSUER_ID, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": KEY_ID})


def call(method, path, body=None):
    req = urllib.request.Request(
        BASE + path, method=method, data=json.dumps(body).encode() if body else None,
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code} {method} {path}\n{e.read().decode()[:2000]}")


def app_id():
    apps = call("GET", f"/apps?filter[bundleId]={BUNDLE_ID}")["data"]
    if not apps:
        sys.exit(f"找不到 bundle id {BUNDLE_ID} 的 app")
    return apps[0]["id"]


def cmd_status(_):
    aid = app_id()
    print("Builds:")
    for b in call("GET", f"/builds?filter[app]={aid}&sort=-uploadedDate&limit=5")["data"]:
        a = b["attributes"]
        print(f"  build {a['version']:>4}  {a['processingState']:<10} {a['uploadedDate']}"
              f"{'  (expired)' if a['expired'] else ''}")
    print("Versions:")
    for v in call("GET", f"/apps/{aid}/appStoreVersions?limit=5")["data"]:
        a = v["attributes"]
        print(f"  {a['versionString']:<8} {a['appStoreState']:<25} release={a.get('releaseType')}")


def find_build(aid, number):
    builds = call("GET", f"/builds?filter[app]={aid}&filter[version]={number}&limit=5")["data"]
    builds = [b for b in builds if not b["attributes"]["expired"]]
    if not builds:
        sys.exit(f"找不到 build {number}（是否還沒上傳？）")
    b = builds[0]
    state = b["attributes"]["processingState"]
    if state != "VALID":
        sys.exit(f"build {number} 狀態是 {state}，還不能送審（等 Apple 處理完成為 VALID）")
    return b["id"]


def existing_version(aid, version):
    """回傳 (id, state) 或 None；狀態不能沿用時直接結束。"""
    for v in call("GET", f"/apps/{aid}/appStoreVersions?filter[versionString]={version}")["data"]:
        state = v["attributes"]["appStoreState"]
        if state in REUSABLE_STATES:
            return v["id"], state
        sys.exit(f"版本 {version} 已存在且狀態為 {state}，不能重複送審")
    return None


def attach_or_create_version(aid, version, build_id, release_type, existing):
    if existing:
        vid, state = existing
        call("PATCH", f"/appStoreVersions/{vid}/relationships/build",
             {"data": {"type": "builds", "id": build_id}})
        return vid, f"沿用既有版本（{state}）"
    v = call("POST", "/appStoreVersions", {"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": "IOS", "versionString": version, "releaseType": release_type},
        "relationships": {"app": {"data": {"type": "apps", "id": aid}},
                          "build": {"data": {"type": "builds", "id": build_id}}}}})["data"]
    return v["id"], "新建版本"


def set_whats_new(version_id, notes):
    locs = call("GET", f"/appStoreVersions/{version_id}/appStoreVersionLocalizations")["data"]
    match = [l for l in locs if l["attributes"]["locale"] == LOCALE]
    if match:
        call("PATCH", f"/appStoreVersionLocalizations/{match[0]['id']}", {"data": {
            "type": "appStoreVersionLocalizations", "id": match[0]["id"],
            "attributes": {"whatsNew": notes}}})
    else:
        call("POST", "/appStoreVersionLocalizations", {"data": {
            "type": "appStoreVersionLocalizations",
            "attributes": {"locale": LOCALE, "whatsNew": notes},
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}})


def submit_for_review(aid, version_id):
    rs = call("POST", "/reviewSubmissions", {"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}})["data"]
    call("POST", "/reviewSubmissionItems", {"data": {
        "type": "reviewSubmissionItems",
        "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": rs["id"]}},
                          "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}})
    rs = call("PATCH", f"/reviewSubmissions/{rs['id']}", {"data": {
        "type": "reviewSubmissions", "id": rs["id"], "attributes": {"submitted": True}}})["data"]
    return rs["attributes"]["state"]


def cmd_submit(args):
    with open(args.notes) as f:
        notes = f.read().strip()
    if not notes:
        sys.exit("更新說明是空的")
    aid = app_id()
    build_id = find_build(aid, args.build)
    existing = existing_version(aid, args.version)
    print(f"App {aid}  版本 {args.version}  build {args.build}（VALID）  發布方式 {args.release_type}")
    print("更新說明：\n" + "\n".join("  " + line for line in notes.splitlines()))
    if not args.yes:
        if input("送出審查？送出後更新說明就鎖住了 [y/N] ").strip().lower() != "y":
            sys.exit("已取消")
    version_id, how = attach_or_create_version(aid, args.version, build_id, args.release_type, existing)
    print(f"{how}：{version_id}")
    set_whats_new(version_id, notes)
    print(f"已寫入 {LOCALE} 更新說明")
    state = submit_for_review(aid, version_id)
    v = call("GET", f"/appStoreVersions/{version_id}")["data"]["attributes"]
    b = call("GET", f"/appStoreVersions/{version_id}/build")["data"]
    print(f"提交狀態 {state}；版本 {v['versionString']} {v['appStoreState']}，build {b['attributes']['version']}")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status").set_defaults(fn=cmd_status)
    s = sub.add_parser("submit")
    s.add_argument("--version", required=True, help="例如 1.8.1")
    s.add_argument("--build", required=True, help="build 號，例如 17")
    s.add_argument("--notes", required=True, help="zh-Hant 更新說明檔案路徑")
    s.add_argument("--release-type", default="AFTER_APPROVAL", choices=["AFTER_APPROVAL", "MANUAL"])
    s.add_argument("--yes", action="store_true", help="不詢問直接送出")
    s.set_defaults(fn=cmd_submit)
    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
