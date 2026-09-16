# 团战模拟器 · UI98 界面改版

这份代码直接修改自本次上传的 `dota2_rpg.zip`，不是独立网页，也不是只附效果图。
实际修改的是 Dota 2 Panorama 的 XML、JavaScript、CSS 和本地贴图。界面版本号为 **UI98**。

## 改了什么

### 条件设置：复古魔幻的战术工坊

木纹底板、古铜描边、羊皮纸条件卡片、手绘线稿风格图标和暖金色按钮，配少量灰绿色选中态。
左侧为「触发条件 / 目标筛选 / 优先级 / 施法行为」，中间编辑当前分类，右侧显示当前行为及草稿预览。
有编号和已启用数量；数值修改后预览更新，切换分类保留未提交的草稿。
取消不提交，应用仍走原来的校验与保存流程。技能能力限制、动作引用、指定目标、移动设置、只读限制、买活专用设置保留。

没有添加效果图里未经后端支持的「拖拽排序」「效果演示」等功能，也没有把整张效果图作为不可交互的界面背景。
手绘图标以可编辑 SVG 和运行用 PNG 提供；无需安装新字体，也没有外部图片链接。

### 排行榜：两张榜同时看

积分榜和速通榜改为左右并排，不再通过标签切换。
每张榜都有大号「我的最佳排名」、总上榜人数、独立榜单和独立状态。
前三名使用金、银、铜层级；自己的行高亮并带「你」标记。
规则、详细计分和诊断说明收进默认关闭的「规则与计分」区域。
本局奖励可以从单独按钮查看；普通关卡的掉落结算和再来一次的流程保留。

榜单只使用现有服务器返回的数据，保留「前 5 名 + 自己附近名次」的真实快照与名次间隔。
没有添加示例玩家、虚构英雄头像、假的前十名或新的排行榜网络接口。
长名字按普通文本处理，并保留悬停查看；时间保留毫秒。

**统计口径没有改：** 原项目的速通榜按「全通后的各关胜利剩余时间合计」升序排列，
并不是通常意义的整局耗时。本版按真实字段标注，不会把它错误写成「通关耗时」。
失败局如果服务端返回历史速通排名，界面明确显示为历史最佳；不会把失败局冒充为通关成绩。

## 选择哪个压缩包

- `dota2_rpg_UI98_full.zip`：完整修改后的项目，可直接作为新的工作目录。
- `dota2_rpg_UI98_patch.zip`：只有本次新增和修改的文件，需要合并到本次上传版本的项目根目录。

两个包都包含顶层 `dota2_rpg` 文件夹。项目根目录是能同时看到 `content`、`game`、`scripts` 的那一层。
覆盖前备份现有项目。若你在上传后又改过同名 JS/XML/本地化文件，应先比较差异，避免覆盖自己的新修改。

## 本地使用：已安装原项目

先关闭正在运行的自定义游戏。确认已经安装 **Dota 2 Workshop Tools**。

解压后进入项目根目录，双击：

```text
APPLY_UI98.cmd
```

默认使用 Steam 的常见安装路径。找不到编译器时会询问 `dota 2 beta` 文件夹的完整路径。
也可以从 PowerShell 在项目根目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\install-ui.ps1" -DotaPath "D:\SteamLibrary\steamapps\common\dota 2 beta"
```

将示例路径换成你实际的 Dota 2 目录。

这个脚本只更新本次 UI 文件、贴图及中英文本地化，并调用本机 `resourcecompiler.exe` 编译；
不重新构建地图，不修改战斗 Lua，也不自动发布创意工坊。
它会检查编译返回值、对应编译产物是否存在，以及两份本地化文件的哈希。
报错时先处理错误，不要把报错后的目录当作已经完成的发布包。

完成后重新启动自定义游戏，确认可见界面版本为 **98**。
只把源码复制过去、没有编译新贴图和 Panorama 文件，可能仍显示旧界面。

## 首次安装

尚未安装原项目时，请使用完整项目包，并在项目根目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\install-addon.ps1" -DotaPath "D:\SteamLibrary\steamapps\common\dota 2 beta" -Compile
```

原有完整安装流程保留，新增 UI98 资源编译和双语本地化校验。
UI-only 脚本不会替你安装不存在的基础地图和战斗脚本。

## 主要文件

| 文件 | 用途 |
|---|---|
| `content/dota_addons/dota2_rpg/panorama/layout/custom_game/rpg_demo_hud.xml` | 条件设置与双榜布局 |
| `content/dota_addons/dota2_rpg/panorama/styles/custom_game/fantasy_ui.css` | 独立、限域的复古魔幻主题 |
| `content/dota_addons/dota2_rpg/panorama/scripts/custom_game/condition_catalog.js` | 分类导航、草稿预览与条件卡片 |
| `content/dota_addons/dota2_rpg/panorama/scripts/custom_game/rpg_demo_hud.js` | 双榜渲染、个人名次、说明折叠、结算生命周期 |
| `content/dota_addons/dota2_rpg/panorama/images/custom_game/fantasy_ui/` | 19 张 PNG、对应 VTEX 描述及 13 份图标 SVG |
| `game/dota_addons/dota2_rpg/resource/addon_*.txt` | 中英文新增文案与 UI98 版本号 |
| `scripts/install-ui.ps1`、`APPLY_UI98.cmd` | 已安装项目的 UI 更新与编译入口 |
| `scripts/build-ui-art.py` | 贴图与图标的可复现生成源码；日常安装不需要执行 |
| `tests/fantasy-ui.test.js`、`tests/hud-sidebar.test.js` | 本次界面交互与双榜回归测试 |
| `tests/results/ui98-regression.json` | 本次离线测试的逐组结果 |
| `UI98_MANIFEST.sha256` | 本次改动文件的校验清单 |

## 验证范围

151 组离线测试返回成功，包含 117 个游戏 Lua 源文件和 16 个 Panorama JS 文件的语法检查。
其中原测试自带的 4 个「原生 Dota 资源」子测试因环境缺少安装目录/VPK/外部地图而跳过。
这不是 Dota 2 客户端内的完整实机验证，详见 `UI98_VALIDATION.md`。

当前环境没有 Dota 2 客户端、Windows PowerShell 或 Valve 资源编译器，
因此没有声称已经在游戏中编译运行或验证所有分辨率。
安装脚本负责在你的开发机器上执行真正的资源编译；发布前应做下方的实机检查。

## 发布前实机检查

1. 打开普通攻击和至少一个单位目标/地点目标技能的条件设置。切换四个分类，修改数值，
   选择动作或目标，再返回原分类，确认草稿和右侧预览一致。取消后重开应恢复旧设置。
2. 点击应用，确认原有服务端规则同步成功。测试只读状态、买活规则、刷新技能能力后保留草稿。
3. 通关或失败后确认双榜同时出现、两边自己的排名和真实榜单对应。
   检查未上榜、网络失败、仅一张榜返回数据、失败局显示历史最佳的状态。
4. 展开/收起规则说明及本局奖励。确认普通关卡掉落仍可领取，重新开始仍回到第一关，
   新一局不会残留上一局榜单。
5. 分别检查中文/英文以及 16:9、4:3 窗口：输入框、下拉菜单、滚动区域、应用按钮和两边榜单均可操作。
   使用 Panorama 控制台确认没有资源缺失、无效属性或脚本错误。

## 说明

这次交付聚焦 UI，没有更改计分算法、排行榜后端、地图或战斗规则。
完整包保留项目主体，但不包含版本控制内部目录、自动缓存和开发工具会话目录。
原有历史测试报告保留；本次结果单独保存为 UI98 报告。
