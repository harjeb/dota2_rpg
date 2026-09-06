from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path


PACKAGE = Path(__file__).resolve().parents[1]
INSTALLER = PACKAGE / "tools" / "apply_issue_fixes.py"
OVERLAY_ARENA_MAP = (
    PACKAGE / "overlay/content/dota_addons/dota2_rpg/maps/dota2_rpg_demo.vmap"
)
SOURCE_ARENA_MAP = (
    PACKAGE.parent / "content/dota_addons/dota2_rpg/maps/dota2_rpg_demo.vmap"
)


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def run_installer(repo: Path) -> str:
    process = subprocess.run(
        [sys.executable, str(INSTALLER), str(repo)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if process.returncode != 0:
        raise AssertionError(process.stdout)
    return process.stdout


def main() -> None:
    # The installer must deliver the exact VMAP that the repository-level
    # structural test validates, not a stale overlay copy.
    assert OVERLAY_ARENA_MAP.is_file()
    assert SOURCE_ARENA_MAP.is_file()
    assert OVERLAY_ARENA_MAP.read_bytes() == SOURCE_ARENA_MAP.read_bytes()

    with tempfile.TemporaryDirectory() as temporary:
        repo = Path(temporary) / "dota2_rpg"
        addon = repo / "game/dota_addons/dota2_rpg/scripts/vscripts/addon_game_mode.lua"
        manifest = repo / "content/dota_addons/dota2_rpg/panorama/layout/custom_game/custom_ui_manifest.xml"
        order_filter = repo / "game/dota_addons/dota2_rpg/scripts/vscripts/tactics/order_filter.lua"
        bench_modifier = repo / "game/dota_addons/dota2_rpg/scripts/vscripts/modifiers/modifier_waiting_area.lua"
        arena_map = repo / "content/dota_addons/dota2_rpg/maps/dota2_rpg_demo.vmap"

        write(
            addon,
            "CDota2RpgDemo = class({})\n"
            "function CDota2RpgDemo:InitGameMode() end\n"
            "function CDota2RpgDemo:OnStartBattle() end\n"
            "return CDota2RpgDemo\n",
        )
        write(manifest, "<root>\n  <Panel>\n  </Panel>\n</root>\n")
        write(order_filter, "return { old = true }\n")
        write(
            bench_modifier,
            "modifier_waiting_area = class({})\n"
            "function modifier_waiting_area:CheckState()\n"
            "  return {\n"
            "    [MODIFIER_STATE_STUNNED] = true,\n"
            "    [MODIFIER_STATE_COMMAND_RESTRICTED] = true,\n"
            "  }\n"
            "end\n",
        )
        arena_map.parent.mkdir(parents=True, exist_ok=True)
        arena_map.write_bytes(b"old arena map")

        first = run_installer(repo)
        assert "ERROR" not in first
        addon_text = addon.read_text(encoding="utf-8")
        manifest_text = manifest.read_text(encoding="utf-8")
        bench_text = bench_modifier.read_text(encoding="utf-8")

        assert addon_text.count("RPG_ISSUE_FIX_BOOTSTRAP_BEGIN") == 1
        assert addon_text.index("RPG_ISSUE_FIX_BOOTSTRAP_BEGIN") < addon_text.rindex("return CDota2RpgDemo")
        assert manifest_text.count("issue_fixes_ui.xml") == 1
        assert "preparation must allow skill/shop orders" in bench_text
        assert "issuer == -1" in order_filter.read_text(encoding="utf-8")
        assert arena_map.read_bytes() == OVERLAY_ARENA_MAP.read_bytes()
        assert (repo / "ISSUE_FIX_APPLY_RESULT.md").exists()
        assert list((repo / ".rpg_issue_fix_backup").rglob("order_filter.lua"))
        assert list((repo / ".rpg_issue_fix_backup").rglob("dota2_rpg_demo.vmap"))

        second = run_installer(repo)
        assert "ERROR" not in second
        assert addon.read_text(encoding="utf-8").count("RPG_ISSUE_FIX_BOOTSTRAP_BEGIN") == 1
        assert manifest.read_text(encoding="utf-8").count("issue_fixes_ui.xml") == 1

    print("installer tests passed")


if __name__ == "__main__":
    main()
