# UI29：收窄我方行动逻辑与移除提示条底色

我方行动逻辑面板由 620px 缩至 310px。五个英雄头像移到标题下方，尺寸调整为 48px；减少内边距、条件按钮间距和排序按钮宽度，使带滚动条的规则行仍能容纳技能图标、条件设置、排序、增删操作。长英雄名使用省略号。条件设置弹窗仍为原有尺寸。

用户同时要求删除英雄商店后面的红色横条背景。商店已经由 `RpgTransparentHeroShop` 清除了整块背景；代码中最符合横条外观的候选是 `RuleSyncNotice`：750px 宽、顶部偏移 135px、红褐色 `#402821ee`。本次移除该提示条底色，增加文字阴影以维持可读性，提示内容和显示逻辑继续保留。没有游戏内画面证明用户所指横条就是该元素，因此这是针对候选的背景调整；仍需实机核对，不能宣称红条根因已经确认。

现有 `panorama-save`、`hud-sidebar`、`condition-ui-v2` 检查、完整 `python dota2_rpg_issue_fixes/tests/run_checks.py` 和 `tests/verify-addon.ps1` 通过，`git diff --check` 通过。Panorama 模拟检查不能代替游戏内布局验收。

已安装本地 UI29，使用 Valve resourcecompiler 编译 HUD XML 和 CSS，94 个 addon 源文件与安装位置逐字节一致。部署前备份和编译日志在 `C:/Users/harjeb/AppData/Local/Temp/dota2_rpg_v29_v3jic9bo`。本次没有重编地图，部署开始时现有地图 VPK 的 SHA-256 为 `30f219a17f480c9a1d825b75a44d75b900c57a4e05949cc3609faa5e6a5f3c43`，部署后保持一致。

运行标记 `rpg-runtime-v29-20260910`，界面版本 29。实现跟踪 `dota2_rpg-h49`；实机核对由 `dota2_rpg-9ii` 跟踪。没有启动或停止 Dota，也没有截图。
