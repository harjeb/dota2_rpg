#!/usr/bin/env python3
"""Apply the issue-only overlay to a local dota2_rpg checkout.

The script is intentionally conservative:
- it backs up every overwritten file;
- it does not edit progression, economy, recruitment, rewards, save data or bonds;
- it appends a compatibility bootstrap instead of rewriting addon_game_mode.lua;
- it reports integration points that still require in-engine verification.
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

BOOTSTRAP_BEGIN = "-- RPG_ISSUE_FIX_BOOTSTRAP_BEGIN"
BOOTSTRAP_END = "-- RPG_ISSUE_FIX_BOOTSTRAP_END"
UI_LAYOUT_URI = "file://{resources}/layout/custom_game/issue_fixes_ui.xml"


@dataclass
class ApplyReport:
    copied: list[str] = field(default_factory=list)
    overwritten: list[str] = field(default_factory=list)
    patched: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    checks: list[str] = field(default_factory=list)


class InstallerError(RuntimeError):
    pass


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_text(path: Path, content: str, dry_run: bool) -> None:
    if dry_run:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")


def run(command: list[str], cwd: Path | None = None) -> tuple[int, str]:
    process = subprocess.run(
        command,
        cwd=str(cwd) if cwd else None,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    return process.returncode, process.stdout.strip()


def discover_head(repo: Path) -> str | None:
    if not (repo / ".git").exists():
        return None
    code, output = run(["git", "rev-parse", "HEAD"], repo)
    return output if code == 0 else None


def backup_file(source: Path, repo: Path, backup_root: Path, dry_run: bool) -> None:
    if not source.exists():
        return
    relative = source.relative_to(repo)
    destination = backup_root / relative
    if dry_run:
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def copy_overlay(
    overlay_root: Path,
    repo: Path,
    backup_root: Path,
    report: ApplyReport,
    dry_run: bool,
    replace_order_filter: bool,
) -> None:
    for source in sorted(path for path in overlay_root.rglob("*") if path.is_file()):
        relative = source.relative_to(overlay_root)
        if (
            relative.as_posix().endswith("scripts/vscripts/tactics/order_filter.lua")
            and not replace_order_filter
        ):
            report.warnings.append(
                "未覆盖 tactics/order_filter.lua；需要手工合并准备阶段升级/购买和 FIGHT AI 放行逻辑。"
            )
            continue

        destination = repo / relative
        if destination.exists():
            if destination.read_bytes() == source.read_bytes():
                continue
            backup_file(destination, repo, backup_root, dry_run)
            report.overwritten.append(relative.as_posix())
        else:
            report.copied.append(relative.as_posix())

        if not dry_run:
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)


def patch_manifest(
    manifest: Path,
    repo: Path,
    backup_root: Path,
    report: ApplyReport,
    dry_run: bool,
) -> None:
    if manifest.exists():
        content = read_text(manifest)
        if UI_LAYOUT_URI in content:
            return
        closing = content.rfind("</Panel>")
        if closing < 0:
            raise InstallerError(
                f"无法识别 Panorama manifest 结构：{manifest}。请按 APPLY.md 手工加入 UI。"
            )
        insertion = (
            "        <CustomUIElement type=\"Hud\" "
            f"layoutfile=\"{UI_LAYOUT_URI}\" />\n"
        )
        content = content[:closing] + insertion + content[closing:]
        backup_file(manifest, repo, backup_root, dry_run)
        write_text(manifest, content, dry_run)
        report.patched.append(manifest.relative_to(repo).as_posix())
        return

    content = (
        "<root>\n"
        "    <Panel>\n"
        f"        <CustomUIElement type=\"Hud\" layoutfile=\"{UI_LAYOUT_URI}\" />\n"
        "    </Panel>\n"
        "</root>\n"
    )
    write_text(manifest, content, dry_run)
    report.copied.append(manifest.relative_to(repo).as_posix())


def detect_game_mode_class(content: str) -> str:
    matches = re.findall(
        r"function\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*InitGameMode\s*\(",
        content,
    )
    if not matches:
        raise InstallerError(
            "addon_game_mode.lua 中未找到 Class:InitGameMode()，无法安全追加 bootstrap。"
        )
    return matches[-1]


def patch_addon_game_mode(
    addon_file: Path,
    repo: Path,
    backup_root: Path,
    report: ApplyReport,
    dry_run: bool,
) -> None:
    content = read_text(addon_file)
    if BOOTSTRAP_BEGIN in content:
        return

    class_name = detect_game_mode_class(content)
    block = (
        f"{BOOTSTRAP_BEGIN}\n"
        "-- Installed after all class methods are defined and before any module return.\n"
        f"require(\"issue_fixes.bootstrap\").Install({class_name})\n"
        f"{BOOTSTRAP_END}"
    )

    # Lua requires a return statement to be the final statement in its block.
    # Some addon_game_mode.lua revisions return the class table at EOF, so insert
    # the bootstrap before that return instead of blindly appending after it.
    stripped = content.rstrip()
    trailing_return = re.search(
        r"(?m)^[ \t]*return(?:[ \t]+[^\n]+)?[ \t]*$",
        stripped,
    )
    if trailing_return is not None and trailing_return.end() == len(stripped):
        patched = (
            stripped[: trailing_return.start()].rstrip()
            + "\n\n"
            + block
            + "\n\n"
            + stripped[trailing_return.start() :]
            + "\n"
        )
    else:
        patched = stripped + "\n\n" + block + "\n"

    backup_file(addon_file, repo, backup_root, dry_run)
    write_text(addon_file, patched, dry_run)
    report.patched.append(addon_file.relative_to(repo).as_posix())


def patch_prepare_modifiers(
    vscripts: Path,
    repo: Path,
    backup_root: Path,
    report: ApplyReport,
    dry_run: bool,
) -> None:
    name_pattern = re.compile(r"bench|waiting|prepare|staging|reserve", re.I)
    state_pattern = re.compile(
        r"^(?P<indent>\s*)\[(?P<state>MODIFIER_STATE_(?:COMMAND_RESTRICTED|STUNNED))\]"
        r"\s*=\s*true\s*,?\s*$",
        re.M,
    )

    for path in sorted(vscripts.rglob("*.lua")):
        relative = path.relative_to(vscripts).as_posix()
        if relative.startswith("issue_fixes/"):
            continue

        content = read_text(path)
        contextual = name_pattern.search(path.name) or (
            "CheckState" in content and name_pattern.search(content)
        )
        if not contextual or not state_pattern.search(content):
            continue

        def replace(match: re.Match[str]) -> str:
            indent = match.group("indent")
            state = match.group("state")
            return (
                f"{indent}-- RPG issue fix: preparation must allow skill/shop orders.\n"
                f"{indent}-- [{state}] = true,"
            )

        patched = state_pattern.sub(replace, content)
        if patched == content:
            continue
        backup_file(path, repo, backup_root, dry_run)
        write_text(path, patched, dry_run)
        report.patched.append(path.relative_to(repo).as_posix())


def write_repo_report(
    repo: Path,
    backup_root: Path,
    report: ApplyReport,
    dry_run: bool,
) -> None:
    lines = [
        "# Dota2 RPG issue 修复安装结果",
        "",
        "本次只处理 issue.txt 中的 10 项，不修改 EXP、GOLD、招募价格、存档、羁绊或词缀。",
        "",
        "## 新增文件",
    ]
    lines.extend(f"- `{item}`" for item in report.copied)
    lines.extend(["", "## 覆盖文件（原文件已备份）"])
    lines.extend(f"- `{item}`" for item in report.overwritten)
    lines.extend(["", "## 自动修改文件"])
    lines.extend(f"- `{item}`" for item in report.patched)
    lines.extend(["", "## 检查"])
    lines.extend(f"- {item}" for item in report.checks)
    lines.extend(["", "## 仍需 Dota 2 Tools 实机检查"])
    lines.extend(
        [
            "- 小精灵转交普通装备、可叠加物品和会自动合成的组件。",
            "- 等待区英雄和场上英雄在准备阶段使用原版升级按钮。",
            "- 两类英雄通过原版商店购买后，物品进入当前选中英雄物品栏/背包。",
            "- 当前关实际敌人进入 FIGHT 后主动攻击，且不再引用固定三英雄列表。",
            "- Hammer 中线门和外墙导航阻挡是否与地图实体名一致。",
            "- 若现有 UI 的 Panel ID 不在自动候选中，按 integration/PANORAMA_INTEGRATION.md 显式绑定。",
        ]
    )
    if report.warnings:
        lines.extend(["", "## 警告"])
        lines.extend(f"- {item}" for item in report.warnings)
    lines.extend(["", f"备份目录：`{backup_root.relative_to(repo).as_posix()}`", ""])

    write_text(repo / "ISSUE_FIX_APPLY_RESULT.md", "\n".join(lines), dry_run)


def syntax_checks(repo: Path, report: ApplyReport) -> None:
    lua_files = sorted(
        (repo / "game/dota_addons/dota2_rpg/scripts/vscripts/issue_fixes").rglob("*.lua")
    )
    lua_files.append(
        repo
        / "game/dota_addons/dota2_rpg/scripts/vscripts/modifiers/modifier_rpg_prepare_bench.lua"
    )
    lua_files.append(
        repo / "game/dota_addons/dota2_rpg/scripts/vscripts/tactics/order_filter.lua"
    )
    lua_files = [path for path in lua_files if path.exists()]

    texlua = shutil.which("texlua")
    if texlua and lua_files:
        checker = (
            "for i=1,#arg do local f,e=loadfile(arg[i]); "
            "if not f then io.stderr:write(arg[i]..': '..tostring(e)..'\\n'); "
            "os.exit(1) end end"
        )
        temporary = repo / ".rpg_issue_fix_lua_check.lua"
        temporary.write_text(checker, encoding="utf-8")
        try:
            code, output = run([texlua, str(temporary), *map(str, lua_files)])
        finally:
            temporary.unlink(missing_ok=True)
        if code != 0:
            raise InstallerError(f"Lua syntax check failed:\n{output}")
        report.checks.append(f"Lua 语法检查通过：{len(lua_files)} 个文件")
    elif lua_files:
        try:
            from lupa import LuaRuntime
        except ImportError:
            report.warnings.append("未找到 texlua 或 Python Lupa，跳过 Lua 语法检查。")
        else:
            runtime = LuaRuntime(unpack_returned_tuples=True)
            load_file = runtime.eval(
                "function(path) local chunk, err = loadfile(path); "
                "if not chunk then error(err) end end"
            )
            try:
                for lua_file in lua_files:
                    load_file(lua_file.as_posix())
            except Exception as error:
                raise InstallerError(f"Lua syntax check failed:\n{error}") from error
            report.checks.append(
                f"Lua 语法检查通过（Lupa）：{len(lua_files)} 个文件"
            )

    node = shutil.which("node")
    js = (
        repo
        / "content/dota_addons/dota2_rpg/panorama/scripts/custom_game/issue_fixes_ui.js"
    )
    if node and js.exists():
        code, output = run([node, "--check", str(js)])
        if code != 0:
            raise InstallerError(f"JavaScript syntax check failed:\n{output}")
        report.checks.append("Panorama JavaScript 语法检查通过")
    else:
        report.warnings.append("未找到 node，跳过 Panorama JavaScript 检查。")

    xml = (
        repo
        / "content/dota_addons/dota2_rpg/panorama/layout/custom_game/issue_fixes_ui.xml"
    )
    ET.parse(xml)
    report.checks.append("Panorama XML 解析通过")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Apply issue.txt fixes to a local harjeb/dota2_rpg checkout."
    )
    parser.add_argument("repo", type=Path, help="Local repository root")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--no-bootstrap",
        action="store_true",
        help="Copy files but do not append the compatibility bootstrap.",
    )
    parser.add_argument(
        "--keep-order-filter",
        action="store_true",
        help="Do not replace tactics/order_filter.lua; merge it manually.",
    )
    parser.add_argument(
        "--expected-head",
        help="Warn if git HEAD differs from this full or abbreviated commit.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    repo = args.repo.expanduser().resolve()
    package_root = Path(__file__).resolve().parent.parent
    overlay_root = package_root / "overlay"

    addon_file = (
        repo
        / "game/dota_addons/dota2_rpg/scripts/vscripts/addon_game_mode.lua"
    )
    vscripts = addon_file.parent
    manifest = (
        repo
        / "content/dota_addons/dota2_rpg/panorama/layout/custom_game/custom_ui_manifest.xml"
    )

    if not addon_file.exists():
        raise InstallerError(f"不是可识别的 dota2_rpg checkout，缺少：{addon_file}")

    timestamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_root = repo / ".rpg_issue_fix_backup" / timestamp
    report = ApplyReport()

    head = discover_head(repo)
    if args.expected_head and head and not head.startswith(args.expected_head):
        report.warnings.append(
            f"当前 HEAD {head} 与期望 {args.expected_head} 不同；已使用兼容补丁方式，而非行号补丁。"
        )

    copy_overlay(
        overlay_root,
        repo,
        backup_root,
        report,
        args.dry_run,
        replace_order_filter=not args.keep_order_filter,
    )
    patch_manifest(manifest, repo, backup_root, report, args.dry_run)
    patch_prepare_modifiers(vscripts, repo, backup_root, report, args.dry_run)

    if not args.no_bootstrap:
        patch_addon_game_mode(
            addon_file,
            repo,
            backup_root,
            report,
            args.dry_run,
        )
    else:
        report.warnings.append(
            "未追加 bootstrap；必须按 integration/ADDON_GAME_MODE_INTEGRATION.md 手工接线。"
        )

    if not args.dry_run:
        syntax_checks(repo, report)
    else:
        report.checks.append("dry-run：未写文件，也未运行目标仓库语法检查")

    write_repo_report(repo, backup_root, report, args.dry_run)

    print("Dota2 RPG issue fixes prepared.")
    print(f"  copied: {len(report.copied)}")
    print(f"  overwritten: {len(report.overwritten)}")
    print(f"  patched: {len(report.patched)}")
    print(f"  warnings: {len(report.warnings)}")
    if args.dry_run:
        print("  mode: dry-run")
    else:
        print(f"  backup: {backup_root}")
        print(f"  report: {repo / 'ISSUE_FIX_APPLY_RESULT.md'}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except InstallerError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2)
