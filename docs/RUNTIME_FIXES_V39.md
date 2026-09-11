# UI39：魔晶开局可购买

用户要求取消阿哈利姆魔晶的购买等待。检查当前安装的 `pak01_dir.vpk` → `scripts/npc/items.txt`，原生 `item_aghanims_shard` 的初始库存为 0，首次上架时间为 990 秒，极速模式为 510 秒。

在 `scripts/npc/npc_items_custom.txt` 为同名原生物品添加三项覆盖：`ItemStockInitial=1`、`ItemInitialStockTime=0`、`ItemInitialStockTimeTurbo=0`。开局提供库存并取消首次上架门槛；没有复制物品实现、覆盖原价 1400、修改原生升级效果或后续补货规则。

验证：KV 解析通过，逐字段确认仅新增这三项覆盖，其他自定义物品定义与上一版完全相同；完整离线回归 **72 / 72 通过**，`tests/verify-addon.ps1` 通过（原有外部地图模型来源检查为可选项）。

2026-09-11 22:49 安装 UI39：复制 4 个源文件，全部 117 个安装源文件与仓库逐字节一致。此次没有 Panorama 源码改动，无需资源编译。备份：`C:/Users/harjeb/AppData/Local/Temp/dota2_rpg_ui39_backup_20260911_224952`。

未启动/停止 Dota、重载地图或发出购买操作。需要重新载入地图并确认“界面版本 39”；离线检查不等于原生商店购买、扣款和魔晶生效已验收。实现记录 `dota2_rpg-bks`，原生复验 `dota2_rpg-795`。
