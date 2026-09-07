# 条件跨关保留、准备区钱包与沙王射程（2026-09-07）

承接 `30ce00f`，Beads `dota2_rpg-qjd`。用户已确认火枪散弹可以释放；沙王穿刺和准备区购买余额仍未通过实际游戏验收。

## 本轮改动

条件界面原先按槽位存储，敌方名单重建还会清空规则；槽位数据更新时又可能创建默认行。现在按单位名和同名出现次数保存本局规则，实体重生、换关和我方阵容排序不再抹掉已经编辑的条件。不同新敌人仍使用默认行；同名敌人的不同出现位置分别保存。服务端我方规则原本已按英雄名保存，不需要修改服务端存储。保留范围是当前比赛，不是跨新开游戏的磁盘存档。

此前 `updateShopEconomyLabels` 只更新刷新和扩充价格，并没有显示金币。用户看到的是原生钱包，不能用项目 `rpg_shop_state` 广播通过来宣称原生余额显示已修好。本轮在顶部加入直接显示服务器权威钱包的“金币”标签，并在可选商店内容渲染之前更新，避免其他渲染错误阻断余额显示。

原生购买现在将执行单位改为玩家的 assigned hero 小精灵，原先选择的待命/上阵英雄仍保存在 `recipient_key`，由已有的确认物品转交路径交付。这样让原生钱包所属英雄执行购买，额外英雄负责接收物品。保留原价、预检、原生已扣款覆盖和防重复扣款测试。本轮没有依赖猜测的原生 UI 事件强制刷新。原生钱包本身是否仍有显示延迟，需要地图内确认；顶部的新余额标签直接反映服务器值。

从本机 `pak01_dir.vpk` 提取的 `scripts/npc/heroes/npc_dota_hero_sand_king.txt` 确认穿刺是 POINT + ROOT_DISABLES + ALT_CASTABLE，射程位于 `AbilityValues.AbilityCastRange`，数值为 550/625/700/775，并有天赋修正。施法器优先使用 `GetEffectiveCastRange`，回退 `GetCastRange`，两者无正数值时读取原生 `AbilityCastRange` 特殊值及施法距离加成。没有写死沙王的射程。离线测试验证旧接口返回 0 时不会把原生特殊值射程丢失，但没有运行时证据证明这就是用户那一局沙王不释放的唯一原因。

## 验证与部署

- 全套 `run_checks.py`、`tests/verify-addon.ps1` 通过，包括条件跨关/同名敌人/阵容排序、可见余额独立更新、原生购买者改写及交付目标保留、沙王特殊值与有效射程边界，以及既有钱包和防重复消费回归。
- `install-addon.ps1 -Compile` 完成：地图 19 compiled / 0 failed，8 个 Panorama 资源显式编译成功，没有 invalid property name。
- 67 个安装源文件与仓库逐字节一致。顶部为界面版本 7；启动日志标识 `rpg-persist-wallet-burrow-20260907`。
- VPK：3,123,798 字节，SHA256 `7352c750b2507c81daa3710e4f1befa7fc43dd3c85e2e664f2cfce5950d794cb`。
- 安装前备份及编译/检查日志：`C:/Users/harjeb/AppData/Local/Temp/dota2_rpg_wallet7_20260907/`。

编译仍有既有 Dota 基础资源诊断（generic.vfx 开发材质、soundevents_test、surfaceproperties_steamaudio、nav_hulls），此前已由 `dota2_rpg-xrx` 跟踪。未主动启动或关闭 Dota，未进行实际对战。安装目录最新 console.log 仍是 9 月 5 日，不能充当本轮失败的运行证据。问题保持待游戏内验收。
