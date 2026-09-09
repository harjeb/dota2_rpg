#!/usr/bin/env python3
from __future__ import annotations

import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LUA_SCENARIOS = (
    "damage-stats.test.lua", "action-adapter.test.lua", "arena-trees.test.lua", "shop-state.test.lua",
    "shop-transition.test.lua", "runtime-log.test.lua", "precache-battlefield.test.lua", "default-rules.test.lua",
    "condition-v2.test.lua", "action-v2.test.lua", "condition-specials.test.lua",
    "condition-execution.test.lua", "condition-phase.test.lua", "condition-native-targets.test.lua", "condition-vector.test.lua",
    "enemy-items.test.lua", "enemy-rules.test.lua", "hero-lifecycle-log.test.lua", "boss-scaling.test.lua", "battle-reincarnation.test.lua",
    "hero-ability-policy.test.lua", "tempest-double.test.lua", "special-targets.test.lua",
    "hero-precache.test.lua", "tiny-tree.test.lua", "summon-behavior.test.lua", "item-sales.test.lua",
)


def run(command: list[str], cwd: Path = ROOT) -> None:
    print("+", " ".join(command), flush=True)
    process = subprocess.run(command, text=True, cwd=cwd)
    if process.returncode != 0:
        raise SystemExit(process.returncode)


def run_lua_checks(lua_files: list[Path]) -> None:
    texlua = shutil.which("texlua")
    if texlua:
        checker = ROOT / "tests/.syntax_check.lua"
        checker.write_text(
            "for i=1,#arg do local f,e=loadfile(arg[i]); "
            "if not f then io.stderr:write(arg[i]..': '..tostring(e)..'\\n'); "
            "os.exit(1) end end print('lua syntax ok: '..#arg)\n",
            encoding="utf-8",
        )
        try:
            run([texlua, str(checker), *map(str, lua_files)])
        finally:
            checker.unlink(missing_ok=True)
        run([texlua, str(ROOT / "tests/test_runtime.lua"), str(ROOT)])
        run([texlua, str(ROOT / "tests/test_runtime.lua"), str(ROOT), "live"])
        for name in LUA_SCENARIOS:
            run([texlua, str(ROOT.parent / "tests" / name)], cwd=ROOT.parent)
        return

    try:
        from lupa.lua51 import LuaRuntime
    except ImportError as error:
        raise SystemExit(
            "Lua checks require texlua, or the Python package lupa as a fallback"
        ) from error

    print("+ Lupa Lua syntax/runtime checks")
    syntax_runtime = LuaRuntime(unpack_returned_tuples=True)
    load_file = syntax_runtime.eval(
        "function(path) local chunk, err = loadfile(path); "
        "if not chunk then error(err) end end"
    )
    for lua_file in lua_files:
        load_file(lua_file.as_posix())
    print(f"lua syntax ok: {len(lua_files)}")

    for mode in ("overlay", "live"):
        runtime = LuaRuntime(unpack_returned_tuples=True)
        runtime.globals().arg = runtime.table_from({1: ROOT.as_posix(), 2: mode})
        runtime.globals().dofile((ROOT / "tests/test_runtime.lua").as_posix())
    for name in LUA_SCENARIOS:
        runtime = LuaRuntime(unpack_returned_tuples=True)
        runtime.globals().TEST_REPO_ROOT = ROOT.parent.as_posix()
        runtime.globals().dofile((ROOT.parent / "tests" / name).as_posix())


def check_python_syntax(paths: list[Path]) -> None:
    for path in paths:
        compile(path.read_text(encoding="utf-8"), str(path), "exec")
    print(f"Python syntax ok: {len(paths)}")


def main() -> None:
    py_files = [ROOT / "tools/apply_issue_fixes.py", ROOT / "tests/test_installer.py", ROOT.parent / "scripts/export-level-configuration.py"]
    check_python_syntax(py_files)

    lua_files = sorted((ROOT / "overlay").rglob("*.lua"))
    lua_files += sorted((ROOT.parent / "game/dota_addons/dota2_rpg/scripts/vscripts").rglob("*.lua"))
    run_lua_checks(lua_files)

    node = shutil.which("node")
    if not node:
        raise SystemExit("node is required for Panorama JavaScript syntax check")
    run([
        node,
        "--check",
        str(ROOT / "overlay/content/dota_addons/dota2_rpg/panorama/scripts/custom_game/issue_fixes_ui.js"),
    ])
    run([node, str(ROOT / "tests/test_ui.js")])
    run([node, str(ROOT.parent / "tests/condition-ui-v2.test.js")])
    run([sys.executable, str(ROOT.parent / "tests/condition-coverage.test.py")], cwd=ROOT.parent)
    run([sys.executable, str(ROOT.parent / "tests/enemy-equipment-data.test.py")], cwd=ROOT.parent)
    run([sys.executable, str(ROOT.parent / "tests/enemy-roster.test.py")], cwd=ROOT.parent)
    run([sys.executable, str(ROOT.parent / "tests/recruitable-heroes.test.py")], cwd=ROOT.parent)
    run([sys.executable, str(ROOT.parent / "tests/export-level-configuration.test.py")], cwd=ROOT.parent)
    run([node, str(ROOT.parent / "tests/panorama-save.test.js")])
    for script in (ROOT.parent / "content/dota_addons/dota2_rpg/panorama/scripts/custom_game").glob("*.js"):
        run([node, "--check", str(script)])

    layouts = list((ROOT / "overlay/content/dota_addons/dota2_rpg/panorama/layout").rglob("*.xml"))
    layouts += list((ROOT.parent / "content/dota_addons/dota2_rpg/panorama/layout").rglob("*.xml"))
    for layout in layouts:
        tree = ET.parse(layout)
        for panel in tree.getroot().findall("Panel"):
            assert "id" not in panel.attrib, f"Panorama root Panel cannot have an id: {layout}"
    print("Panorama XML parse and root-panel contracts passed")

    run([sys.executable, str(ROOT / "tests/test_installer.py")])
    run([sys.executable, str(ROOT.parent / "tests/vmap.test.py")])
    print("all checks passed")


if __name__ == "__main__":
    main()
