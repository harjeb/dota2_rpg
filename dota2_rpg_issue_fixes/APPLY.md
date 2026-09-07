# 应用说明

## 方式 A：自动安装（推荐）

```bash
cd dota2_rpg_issue_fixes
python tools/apply_issue_fixes.py /你的路径/dota2_rpg --expected-head cab44ff
```

安装器不会编辑以下系统：

- 金币与经验曲线；
- 初始 500 金币与免费招募额度；
- 英雄价格、品质与商店刷新；
- 存档、羁绊、词缀；
- 关卡奖励和敌方数值预算。

自动生成的备份位于：

```text
<repo>/.rpg_issue_fix_backup/<时间戳>/
```

需要回退时，把该目录下文件复制回原位置，并删除新增的 `issue_fixes/`、UI overlay 和 bootstrap 标记块。若安装器覆盖了 `content/dota_addons/dota2_rpg/maps/dota2_rpg_demo.vmap`，同一备份目录中也会有原 VMAP；用它恢复后需重新构建地图。

## 方式 B：手工合并

1. 把 `overlay/game/...` 和 `overlay/content/...` 复制到仓库同路径。
2. 按 `integration/ADDON_GAME_MODE_INTEGRATION.md` 接入服务端生命周期。
3. 按 `integration/PANORAMA_INTEGRATION.md` 显式绑定现有 Panel ID。
4. 选择安装 overlay 中已完成的 `dota2_rpg_demo.vmap`，或按 `integration/HAMMER_ARENA_SETUP.md` 将三枚 marker、原版岩石、不可见边界、NONAV slab 和 nav 中线门（树木由 Lua 生成）手工合并到自定义地图。
5. 使用 Workshop Tools 重新构建地图；安装器不提交生成的 VPK。
6. 按 `integration/TEST_CHECKLIST.md` 回归。

## 提交到 GitHub

```bash
git switch -c fix/current-rpg-issues
git add game content ISSUE_FIX_APPLY_RESULT.md
git commit -F /path/to/dota2_rpg_issue_fixes/COMMIT_MESSAGE.txt
git push -u origin fix/current-rpg-issues
```

然后使用 `PR_BODY.md` 创建 PR。也可以在已登录 GitHub CLI 的环境中直接执行：

```bash
bash tools/create_pr.sh /你的路径/dota2_rpg
```
