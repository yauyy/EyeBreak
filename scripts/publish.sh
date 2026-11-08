#!/bin/zsh
# 发布已有产物，不重新构建。--check 仅离线验签；实际发布必须显式调用本脚本。
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 - "$@" <<'PY'
import argparse
import base64
from contextlib import contextmanager
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
import xml.etree.ElementTree as ET

REPO = "yauyy/EyeBreak"
BRANCH = "feature/ymy/update-channel"
RAW = f"https://raw.githubusercontent.com/{REPO}/refs/heads/{BRANCH}/updates"
FEED = f"https://github.com/{REPO}/releases/latest/download/appcast.xml"
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
ROOT = Path.cwd()


def run(*args, cwd=ROOT, check=True):
    result = subprocess.run(args, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and result.returncode:
        raise RuntimeError(f"{args[0]} 执行失败：{result.stderr.decode(errors='replace').strip()}")
    return result


def download(url, output):
    run("curl", "--fail", "--location", "--silent", "--show-error", "--connect-timeout", "15",
        "--max-time", "45", "--output", str(output), url)


def digest(path):
    with path.open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest() if hasattr(hashlib, "file_digest") else hashlib.sha256(f.read()).hexdigest()


def feed_build(data):
    root = ET.fromstring(data)
    values = [e.text for e in root.iter(SPARKLE + "version")]
    values += [e.attrib[SPARKLE + "version"] for e in root.iter() if SPARKLE + "version" in e.attrib]
    if not values or any(v is None or not re.fullmatch(r"[0-9]+", v) for v in values):
        raise RuntimeError("appcast 缺少有效的 sparkle:version")
    return max(map(int, values))


def compatible_feed(data, candidate, build, label):
    existing = feed_build(data)
    if existing > build:
        raise RuntimeError(f"{label} 已是构建 {existing}，拒绝用 {build} 回退或抢占 latest")
    if existing == build and data != candidate:
        raise RuntimeError(f"{label} 的同构建号 appcast 内容不同，拒绝覆盖")
    def versions(xml):
        values = [e.text for e in ET.fromstring(xml).iter(SPARKLE + "shortVersionString")]
        if not values or any(v is None or not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", v) for v in values):
            raise RuntimeError(f"{label} 缺少可比较的正式版本号")
        return [tuple(map(int, v.split("."))) for v in values]
    old, new = max(versions(data)), max(versions(candidate))
    size = max(len(old), len(new))
    if old + (0,) * (size - len(old)) > new + (0,) * (size - len(new)):
        raise RuntimeError(f"{label} 已有更高版本号，拒绝版本回退")


def api(path, missing=False):
    result = run("gh", "api", f"repos/{REPO}/{path}", check=False)
    if result.returncode:
        if missing and b"HTTP 404" in result.stderr:
            return None
        raise RuntimeError(f"GitHub API 读取失败：{result.stderr.decode(errors='replace').strip()}")
    return json.loads(result.stdout)


def release_asset(release, name, output):
    if not any(a["name"] == name for a in release["assets"]):
        return False
    run("gh", "release", "download", release["tag_name"], "--repo", REPO,
        "--pattern", name, "--output", str(output))
    return True


def check_latest(candidate, build, scratch):
    latest = api("releases/latest")
    path = scratch / "latest.xml"
    path.unlink(missing_ok=True)
    # 按 API 刚返回的明确 tag 取资产，避免 latest 公开重定向/CDN 缓存错配。
    if not release_asset(latest, "appcast.xml", path):
        raise RuntimeError("最新 Release 缺少 appcast.xml")
    compatible_feed(path.read_bytes(), candidate, build, "Release latest")
    return latest


@contextmanager
def remote_lock():
    # POST refs 原子创建；所有本脚本发布共享此锁，不覆盖或抢占已有锁。
    ref = "heads/feature/ymy/publish-lock"
    if api(f"git/ref/{ref}", missing=True):
        raise RuntimeError("远端发布锁已存在；确认对应任务已结束后再人工清理 feature/ymy/publish-lock")
    head = api(f"git/ref/heads/{BRANCH}")["object"]["sha"]
    tree = api(f"git/commits/{head}")["tree"]["sha"]
    result = run("gh", "api", "--method", "POST", f"repos/{REPO}/git/commits", "-f", f"tree={tree}",
                 "-f", f"parents[]={head}", "-f", f"message=chore: 发布任务锁 {uuid.uuid4()}")
    owner = json.loads(result.stdout)["sha"]
    run("gh", "api", "--method", "POST", f"repos/{REPO}/git/refs", "-f", f"ref=refs/{ref}", "-f", f"sha={owner}")
    try:
        yield
    finally:
        current = api(f"git/ref/{ref}", missing=True)
        if current and current["object"]["sha"] == owner:
            run("gh", "api", "--method", "DELETE", f"repos/{REPO}/git/refs/{ref}")
        elif current:
            raise RuntimeError("远端发布锁已改变，未清理其他任务的锁")


def readback(url, expected, output):
    # 固定公开 URL 才是用户入口；不能用 API、随机查询参数或 commit URL 冒充通过。
    expected_hash = digest(expected)
    for attempt in range(5):
        try:
            download(url, output)
            if digest(output) == expected_hash:
                return
        except RuntimeError:
            pass
        if attempt < 4:
            time.sleep(3)
    raise RuntimeError(f"公开地址回读未与产物一致：{url}；可稍后用同一产物重试")


def validate(dmg, feed, version, scratch):
    data = feed.read_bytes()
    root = ET.fromstring(data)
    items = root.findall("./channel/item")
    if len(items) != 1:
        raise RuntimeError("正式 appcast 必须恰好包含一个版本")
    item = items[0]
    enclosure = item.find("enclosure")
    build = feed_build(data)
    if enclosure is None or item.findtext(SPARKLE + "shortVersionString") != version:
        raise RuntimeError("appcast 版本号与待发布版本不一致")
    if item.findtext(SPARKLE + "version") != str(build):
        raise RuntimeError("appcast 构建号格式不符合当前发布格式")
    if enclosure.get("url") != f"{RAW}/{dmg.name}" or enclosure.get("length") != str(dmg.stat().st_size):
        raise RuntimeError("enclosure 必须指向固定 Raw 通道，且长度必须与 DMG 一致")
    signature = enclosure.get(SPARKLE + "edSignature", "")
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise RuntimeError("appcast 缺少有效 Ed25519 签名")
    project = (ROOT / "EyeBreak.xcodeproj/project.pbxproj").read_text()
    keys = set(re.findall(r'SPARKLE_PUBLIC_KEY = "([^"]+)";', project))
    if len(keys) != 1:
        raise RuntimeError("工程必须只有一个正式 Sparkle 公钥")
    key = keys.pop()
    if len(base64.b64decode(key, validate=True)) != 32:
        raise RuntimeError("工程公钥格式错误")
    # 只使用公开密钥验签，不读取钥匙串或私钥。
    swift = '''import Foundation
import CryptoKit
let a = CommandLine.arguments
let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: a[2])!)
let valid = key.isValidSignature(Data(base64Encoded: a[3])!, for: try Data(contentsOf: URL(fileURLWithPath: a[1])))
if !valid { fputs("DMG Ed25519 签名无效\\n", stderr); exit(1) }
'''
    run("xcrun", "swift", "-e", swift, str(dmg), key, signature)
    mount = scratch / "mount"
    mount.mkdir()
    run("hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", str(mount), str(dmg))
    try:
        with (mount / "EyeBreak.app/Contents/Info.plist").open("rb") as f:
            info = plistlib.load(f)
        expected = {"CFBundleIdentifier": "com.yau.EyeBreak", "CFBundleShortVersionString": version,
                    "CFBundleVersion": str(build), "SUPublicEDKey": key,
                    "LSMinimumSystemVersion": item.findtext(SPARKLE + "minimumSystemVersion")}
        if any(info.get(k) != v for k, v in expected.items()):
            raise RuntimeError("DMG 内 App 的版本、构建号、公钥或最低系统版本与发布清单不一致")
        if info.get("SUFeedURL") not in (FEED, f"{RAW}/appcast.xml"):
            raise RuntimeError("DMG 内 App 使用了非正式更新源")
    finally:
        run("hdiutil", "detach", str(mount))
    return data, build


def publish(args, scratch, dmg, feed, candidate, build):
    tag = f"v{args.version}"
    notes = ROOT / f"docs/release-notes/{args.version}.md"
    if not notes.is_file():
        raise RuntimeError(f"缺少发布说明：{notes}")
    origin = run("git", "remote", "get-url", "origin").stdout.decode().strip().removesuffix(".git")
    if origin not in (f"git@github.com:{REPO}", f"https://github.com/{REPO}", f"ssh://git@github.com/{REPO}"):
        raise RuntimeError("origin 不是官方仓库，拒绝发布")
    push_urls = run("git", "remote", "get-url", "--push", "--all", "origin").stdout.decode().splitlines()
    if not push_urls or any(url.removesuffix(".git") != origin for url in push_urls):
        raise RuntimeError("origin 的推送地址与已校验的官方仓库地址不同，拒绝发布")
    release = api(f"releases/tags/{tag}", missing=True)
    target = None
    incomplete = release is None or release["draft"] or release["prerelease"] or not {dmg.name, feed.name}.issubset({a["name"] for a in release["assets"]})
    if incomplete or args.target:
        if not args.target:
            raise RuntimeError("新建或补齐 Release 必须通过 --target 指定构建所用源码提交")
        target = run("git", "rev-parse", "--verify", f"{args.target}^{{commit}}").stdout.decode().strip()
        api(f"commits/{target}")  # 源码提交必须已推送到官方仓库。
        reference = api(f"git/ref/tags/{tag}", missing=True)
        if reference:
            obj = reference["object"]
            while obj["type"] == "tag":
                obj = api(f"git/tags/{obj['sha']}")["object"]
            if obj["sha"] != target:
                raise RuntimeError("已有版本 tag 不指向指定源码提交，拒绝创建 Release")
    check_latest(candidate, build, scratch)
    raw_feed = scratch / "raw-before.xml"
    download(f"{RAW}/appcast.xml", raw_feed)
    compatible_feed(raw_feed.read_bytes(), candidate, build, "Raw 公开源")

    def check_assets(current):
        if current:
            for artifact in (dmg, feed):
                path = scratch / ("existing-" + artifact.name)
                path.unlink(missing_ok=True)
                if release_asset(current, artifact.name, path) and digest(path) != digest(artifact):
                    raise RuntimeError(f"Release 已有不同字节的 {artifact.name}，拒绝覆盖")

    check_assets(release)
    channel = scratch / "channel"
    ref = f"refs/remotes/origin/{BRANCH}"

    def refresh():
        run("git", "fetch", "origin", f"refs/heads/{BRANCH}:{ref}")
        run("git", "reset", "--hard", ref, cwd=channel)
        compatible_feed((channel / "updates/appcast.xml").read_bytes(), candidate, build, "分发分支")

    def push_file(source, message):
        refresh()
        destination = channel / "updates" / source.name
        if destination.exists() and digest(destination) == digest(source):
            return
        if source == dmg and destination.exists():
            raise RuntimeError("分发分支已有同名不同字节的 DMG，拒绝覆盖")
        shutil.copyfile(source, destination)
        run("git", "add", "--", str(destination.relative_to(channel)), cwd=channel)
        run("git", "commit", "-m", message, cwd=channel)
        # 非 force push；并发发布改变 tip 时直接停止，重试会重新读取构建号。
        run("git", "push", "origin", f"HEAD:refs/heads/{BRANCH}", cwd=channel)

    run("git", "fetch", "origin", f"refs/heads/{BRANCH}:{ref}")
    run("git", "worktree", "add", "--detach", str(channel), ref)
    try:
        push_file(dmg, f"chore: 分发 EyeBreak {args.version} 安装包")
        readback(f"{RAW}/{dmg.name}", dmg, scratch / "raw.dmg")
        push_file(feed, f"chore: 同步 EyeBreak {args.version} 更新源")
        readback(f"{RAW}/appcast.xml", feed, scratch / "raw.xml")
        # Raw 已可能发布；后续任何失败都保留产物，重试补齐 Release。
        check_latest(candidate, build, scratch)
        release = api(f"releases/tags/{tag}", missing=True)
        if release is None:
            run("gh", "release", "create", tag, "--repo", REPO, "--target", target,
                "--draft", "--title", f"EyeBreak {args.version}", "--notes-file", str(notes))
            release = api(f"releases/tags/{tag}")
        check_assets(release)
        names = {a["name"] for a in release["assets"]}
        for artifact in (dmg, feed):
            if artifact.name not in names:
                run("gh", "release", "upload", tag, str(artifact), "--repo", REPO)
        refresh()  # 发布 Release 前再次检查分发分支是否已领先。
        latest = check_latest(candidate, build, scratch)
        if release["draft"] or release["prerelease"] or latest["tag_name"] != tag:
            # legacy 让 GitHub 按版本/日期计算 latest；不强制让旧版本重试抢占更新版本。
            run("gh", "api", "--method", "PATCH", f"repos/{REPO}/releases/{release['id']}",
                "-F", "draft=false", "-F", "prerelease=false", "-f", "make_latest=legacy")
        latest = api("releases/latest")
        if latest["tag_name"] != tag:
            raise RuntimeError("Release latest 已改变，未确认本次双通道发布完成")
        check_assets(latest)
        if not {dmg.name, feed.name}.issubset({a["name"] for a in latest["assets"]}):
            raise RuntimeError("Release 缺少发布产物")
        readback(f"{RAW}/appcast.xml", feed, scratch / "raw-final.xml")
        print(f"发布完成：EyeBreak {args.version} ({build})，Raw 与 Release 资产完全一致。")
        print("Release 资产通过 GitHub API 回读；不代表原 Release 下载 URL 或旧 App 更新已通过。")
    finally:
        run("git", "worktree", "remove", "--force", str(channel), check=False)


parser = argparse.ArgumentParser(description="校验并同步已有 DMG/appcast 到 Raw 与 GitHub Release")
parser.add_argument("version")
parser.add_argument("--dist", type=Path, default=ROOT / "dist")
parser.add_argument("--target", help="构建所用的、已推送的源码提交 SHA；新 Release 必填")
parser.add_argument("--check", action="store_true", help="只离线检查产物与签名，不访问或修改远端")
args = parser.parse_args()
lock = None
try:
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", args.version):
        raise RuntimeError("版本号必须是由点分隔的数字")
    if not args.check:
        common = Path(run("git", "rev-parse", "--git-common-dir").stdout.decode().strip()).resolve()
        lock = common / "eyebreak-publish.lock"
        try:
            lock.mkdir()
        except FileExistsError:
            lock = None
            raise RuntimeError("已有发布任务或遗留锁；确认没有发布任务后再移除 .git/eyebreak-publish.lock")
    with tempfile.TemporaryDirectory(prefix="eyebreak-publish-") as directory:
        scratch = Path(directory)
        # 冻结两项产物，之后验证与发布都只读此快照，避免另一打包任务改写 dist。
        dmg = scratch / f"EyeBreak-{args.version}.dmg"
        feed = scratch / "appcast.xml"
        for path in (dmg, feed):
            shutil.copyfile(args.dist / path.name, path)
        candidate, build = validate(dmg, feed, args.version, scratch)
        print(f"离线校验通过：EyeBreak {args.version} ({build})，SHA-256 {digest(dmg)}", flush=True)
        if not args.check:
            with remote_lock():
                publish(args, scratch, dmg, feed, candidate, build)
except (RuntimeError, OSError, ValueError, ET.ParseError) as error:
    print(f"错误：{error}", file=sys.stderr)
    if not args.check:
        print("发布未完成；可能已有通道更新，请保留原产物并用相同命令重试。", file=sys.stderr)
    sys.exit(1)
finally:
    if lock is not None:
        lock.rmdir()
PY
