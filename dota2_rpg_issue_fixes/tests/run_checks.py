#!/usr/bin/env python3
from __future__ import annotations

import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def run(command: list[str]) -> None:
    print("+", " ".join(command))
    process = subprocess.run(command, text=True, cwd=ROOT)
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
        return

    try:
        from lupa import LuaRuntime
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

    runtime = LuaRuntime(unpack_returned_tuples=True)
    runtime.globals().arg = runtime.table_from({1: ROOT.as_posix()})
    runtime.globals().dofile((ROOT / "tests/test_runtime.lua").as_posix())


def check_python_syntax(paths: list[Path]) -> None:
    for path in paths:
        compile(path.read_text(encoding="utf-8"), str(path), "exec")
    print(f"Python syntax ok: {len(paths)}")


def main() -> None:
    py_files = [ROOT / "tools/apply_issue_fixes.py", ROOT / "tests/test_installer.py"]
    check_python_syntax(py_files)

    lua_files = sorted((ROOT / "overlay").rglob("*.lua"))
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

    ET.parse(
        ROOT
        / "overlay/content/dota_addons/dota2_rpg/panorama/layout/custom_game/issue_fixes_ui.xml"
    )
    print("Panorama XML parse passed")

    run([sys.executable, str(ROOT / "tests/test_installer.py")])
    print("all checks passed")


if __name__ == "__main__":
    main()
