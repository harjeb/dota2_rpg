# 卡牌构筑界面 · UI98

## 交付与边界

交付为 **Dota 2 原生 Panorama XML / CSS / JavaScript**，位于独立的 `dota2_rpg_endless` addon。加载后自动打开卡牌构筑界面；关闭后可从右上角「卡牌构筑 · 预览」再次打开，也可使用客户端控制台命令 `rpg_card_ui_preview`。

当前无尽模式尚无正式卡牌运行时，本次交付是游戏内可操作的 UI 预览。22 张演示卡、8 位英雄和演示金币仅在此界面的内存中存在。没有发往服务器的购买、装配或战斗请求，没有存档、排行或外部网络服务；「确认构筑」冻结预览配装，并明确说明尚未接入战斗。不能把本页的卡名、效果说明、报价序列或 COST 分档当作正式玩法数据。

预览 addon 以原生 `dota` 地图为载体，不复制或挂载旧 addon 的战役、地图、商店、AI、上传功能。旧 addon 的入口和安装脚本不变；按项目 UI 版本规则同步递增旧资源中的中英文标记，新 addon 的中英文标记也均为 UI98。

## 视觉与交互

- 中央大卡库：阵营筛选、类型切换、名称/英雄搜索、等级排序；只统计未装备的唯一卡，装备中的卡不占 24 张容量。
- 右侧详情：原生英雄美术、卡名、归属、拥有等级、本场装载档位及 COST。Lv1/2/3 分别可点，未拥有的档位禁用。
- 底部八英雄阵容：每人专属槽和通用槽始终可见。卡牌拖起后提示合法位置；悬停时预览替换后的全队 COST。
- 原生拖拽：`DragStart / DragEnter / DragLeave / DragDrop / DragEnd`。拖回大包裹卸卡，拖到空白处取消；无效目标保留原资产；拖拽结束前不销毁源 Panel。
- 替代操作：点击卡，再点击槽位装备；右键已装备卡查看；右侧按钮卸下；Esc 依次取消选择、关闭子窗口、关闭主界面。
- 替换卡自动退回包裹，唯一资产不复制；有意允许准备阶段临时超 COST，但超额时禁用确认。
- 本局配装撤销：支持装配、卸卡、调整档位。购买、熔炼、兑换会清空撤销历史，防止撤销配装倒退交易。
- 命运召唤：五张已有卡背，购买前只显示阵营与类型；演示每波三次购买、重复卡累计份数、不自动提高装载等级。
- 阵营熔炉：只有未装备专属卡可熔炼，按份数二次确认并预告等级下降或卡移除；同阵营三点兑换基础卡。
- 中英文完整对应；状态同时使用文字、图形和色彩表达。卡面和金属材质沿用用户认可的视觉方向。

正式满仓政策仍待定。预览暂阻止会使卡库超过 24 张的卸卡和替换，但允许满仓时由包裹卡替换槽位卡（一进一出）。该临时政策不更新已确认的系统设计。

## 卡背与材质

直接使用用户提供的 `pics` 原图，不重新设计、不修改原图。仅生成 530×742 的派生纹理，以及一张从原图取材、压暗的背景纹理。当前视觉映射为：

| 阵营 | 原图 |
| --- | --- |
| 元素（蓝） | `b4abc352-adac-4c04-b317-a50fda9b5ef7.png` |
| 文明（火红） | `be9a6cb4-b644-4567-8cbc-dc19aac2eb63.png` |
| 神域（白金） | `cbc16103-fc85-4701-881d-4925517c5031.png` |
| 深渊（紫） | `cc414802-49e5-4e01-a92f-5359e3ace084.png` |
| 荒野（绿） | `ea13d122-aee2-4716-856b-2ff57cbe5027.png` |

此颜色映射是 UI 设计选择。图片按仓库已有 `.gitignore` 规则不上传；新工作副本需要把这五张原图放回 `pics`。原生英雄图像使用 `DOTAHeroImage`，游戏内无需网页、CDN 或额外网络请求。

## 验证命令

在仓库根目录执行（Python 只用标准库解析 XML，无需安装依赖）：

```powershell
node tests/card-forge.test.js
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/prepare-card-ui-assets.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/prepare-card-ui-assets.ps1 -Check
node --check content/dota_addons/dota2_rpg_endless/panorama/scripts/custom_game/card_forge.js
node --check content/dota_addons/dota2_rpg_endless/panorama/scripts/custom_game/card_forge_model.js
git diff --check
```

预期：测试输出 `PASS card model transactions...`；素材检查输出六张纹理尺寸通过；语法和 diff 检查无错误。素材生成会重建派生图，保留 `pics` 原图。

本次已通过：模型事务与容量/COST 规则、原生拖拽 Panel 测试替身、无效拖拽及取消、源 Panel 延迟重建、拖拽时关闭界面、点选装配、搜索、隐藏报价、三次购买、熔炼确认、冻结/返回、双语完整性，以及现有 sidebar / condition-ui-v2 / arena-hud 回归。

用户确认当前机器未安装 Dota。本次 **未进行 resourcecompiler 编译、游戏内渲染和真实鼠标拖放验证**。离线 Panel 测试不替代引擎验收。

## 后续安装与游戏内验收

安装器只写 `dota2_rpg_endless`，拒绝目标目录或其祖先中的重解析点，也检查 addon 内已有链接；不删除旧文件，不写 `dota2_rpg`。安装前会提示覆盖新 addon 的同名文件。`-Compile` 需要 Workshop Tools。

```powershell
$dotaPath = Read-Host '输入包含 game 和 content 的 dota 2 beta 完整目录'
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install-endless-ui.ps1 -DotaPath $dotaPath -Compile
```

预期：所有纹理、脚本、样式和 XML 编译成功，中英文安装副本哈希匹配；随后在 VConsole 执行：

```text
dota_launch_custom_game dota2_rpg_endless dota
```

原生验收需要检查：16:9 / 超宽画面无裁切，卡背及原生英雄图完整可见，卡牌名称可读；合法槽位可落牌、非法槽位不改变资产、拖到空白取消、拖回卡库卸卡；Esc/关闭不留拖拽图；超 COST 阻止确认；中英文文字无原始 token。跟踪项：`dota2_rpg-z4b`。

未来接正式卡牌运行时时，以服务器快照替换演示模型：客户端只发送操作意图，服务器校验归属、阶段、版本、容量、次数与 COST，并回传结果。当前独立预览不代表这条服务端链路已经完成。
