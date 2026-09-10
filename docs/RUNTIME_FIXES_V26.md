# UI26：玛西与猛犸的队友 Buff

用户反馈 UI25 仍不能给队友施放 Buff。此次确认并修复了默认目标选择的问题，但没有进行 Dota 客户端实战验证。

## 原因与变化

友方候选池包含施法者，默认按最近距离排序。原生过滤允许自身时，距离为零的施法者会优先于队友被选中。此前玛西测试人为让自身不合法，没有覆盖该情况。

- `magnataur_empower`、`marci_bodyguard`、旧技能 ID `marci_guardian` 的生成默认规则加入 `exclude_self`，保留原生队伍、范围、目标类型过滤。
- 当前玛西 `marci_bodyguard`、猛犸 `magnataur_empower` 的界面预设改为最近合法队友、排除自身，移除原预设的目标附近 700 距离内必须有敌人这一限制。
- 已保存的玩家自定义规则保持原样。进入界面版本 26 后，在这两个 Buff 的条件设置中重新点击“预设”，再应用。检查目标为友方、筛选包含排除自身。旧玛西 `marci_guardian` 若实际出现，可手动使用同样设置。

本次没有实现按 Buff 状态轮流覆盖全队，默认仍选择最近的合法队友。

## 证据与验证

安装 Dota VPK 中这三个技能均为友方单位指向；猛犸还有 `always_on=1`、`should_self_cast=0`。这些原生元数据不等于实战施法成功证明。

新增引擎回归允许自身作为原生合法目标：撤销修复时猛犸选中自身并失败，修复后选择队友。覆盖 UnitFilter 回退、没有队友、距离不足和保留自定义规则。真实 HUD 测试覆盖预设替换旧自身目标、排除自身序列化、重新打开设置。

完整 `python dota2_rpg_issue_fixes/tests/run_checks.py`、`tests/verify-addon.ps1` 和 `git diff --check` 均通过。离线检查使用模拟原生 API；实战验收记录为 beads `dota2_rpg-5c7`，实现问题为 `dota2_rpg-9fa`。

## 部署

已安装至本机 Dota，编译 `skill_condition_presets.js` 成功，91 个源文件与安装副本逐字节一致。显示“界面版本 26”，运行标记 `rpg-runtime-v26-20260910`。

备份：`C:/Users/harjeb/AppData/Local/Temp/dota2_rpg_v26_q35ywhk9`。地图 VPK 未改变，SHA256 `c8fa10526bbecf84f342a7e6c5007ce41daa2ec11b909253e006e0831cab92ea`。未启动或停止 Dota；需重新载入自定义游戏以加载新版本。
