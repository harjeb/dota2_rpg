"""Regression contract for the read-only live campaign configuration export."""
from __future__ import annotations

import csv
import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

from openpyxl import load_workbook

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/export-level-configuration.py"
spec = importlib.util.spec_from_file_location("export_level_configuration", SCRIPT)
assert spec and spec.loader
EXPORT = importlib.util.module_from_spec(spec)
spec.loader.exec_module(EXPORT)


class LevelConfigurationExportTests(unittest.TestCase):
    def test_live_kv_export_has_all_review_tables_and_real_values(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            files = EXPORT.export(output)
            self.assertTrue(all(path.is_file() for path in files.values()))
            manifest = json.loads(files["manifest"].read_text(encoding="utf-8"))
            self.assertEqual(manifest["runtime_source"], "game/dota_addons/dota2_rpg/scripts/data/levels.kv")
            self.assertEqual(manifest["stage_count"], 30)
            self.assertEqual(manifest["unit_configuration_rows"], 139)
            self.assertEqual(manifest["equipment_rows"], 343)
            self.assertEqual(manifest["unique_units"], 73)
            # The old JSON currently stores level 30 for hero rows while the
            # runtime KV stores their actual stage levels. This is report-only:
            # the export must never use the JSON level instead.
            self.assertEqual(manifest["maintenance_source_difference_rows"], 93)

            book = load_workbook(files["excel"], data_only=True)
            self.assertEqual(book.sheetnames, ["说明", "关卡总览", "单位明细", "装备明细", "单位出现汇总", "源文件差异"])
            for name in book.sheetnames[1:]:
                sheet = book[name]
                self.assertTrue(sheet.auto_filter.ref)
                self.assertTrue(sheet.tables, name + " must be filterable")
                self.assertEqual(sheet.freeze_panes, "A2")

            unit_sheet = book["单位明细"]
            headers = [cell.value for cell in unit_sheet[1]]
            records = [dict(zip(headers, values)) for values in unit_sheet.iter_rows(min_row=2, values_only=True)]
            axe = next(row for row in records if row["关卡"] == "ch05" and row["单位原生ID"] == "npc_dota_hero_axe")
            self.assertEqual((axe["单位名称"], axe["数量"], axe["等级"], axe["AI类型"], axe["装备1（原生ID）"], axe["装备2（原生ID）"]),
                             ("斧王", 1, 8, "aggro_front", "item_boots", "item_bracer"))
            boss = next(row for row in records if row["关卡"] == "ch30" and row["是否Boss"] == "是")
            self.assertEqual((boss["单位原生ID"], boss["等级"], boss["Boss生命倍率"], boss["Boss攻击伤害+%"], boss["Boss法术增幅+%"], boss["Boss冷却减少%"]),
                             ("npc_dota_hero_skeleton_king", 30, 16, 300, 200, 50))

            difference_sheet = book["源文件差异"]
            difference_headers = [cell.value for cell in difference_sheet[1]]
            differences = [dict(zip(difference_headers, values)) for values in difference_sheet.iter_rows(min_row=2, values_only=True)]
            self.assertEqual(len(differences), 93)
            self.assertEqual({row["字段"] for row in differences}, {"level"})
            first = differences[0]
            self.assertEqual((first["关卡"], first["单位原生ID"], first["运行时 levels.kv"], first["维护 levels_v07.json"]),
                             ("ch05", "npc_dota_hero_axe", "8", "30"))

            raw = files["units_csv"].read_bytes()
            self.assertTrue(raw.startswith(b"\xef\xbb\xbf"), "CSV needs an Excel-friendly UTF-8 BOM")
            with files["units_csv"].open(encoding="utf-8-sig", newline="") as stream:
                csv_rows = list(csv.DictReader(stream))
            self.assertEqual(len(csv_rows), 139)
            self.assertEqual(csv_rows[0]["关卡"], "ch01")
            expected_hash = hashlib.sha256(EXPORT.RUNTIME_PATH.read_bytes()).hexdigest()
            self.assertEqual(manifest["runtime_sha256"], expected_hash)


if __name__ == "__main__":
    unittest.main(verbosity=2)
