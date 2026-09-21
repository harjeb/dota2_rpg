# 卡牌原生界面 UI 100

本次交付位于独立 `dota2_rpg_endless` addon，使用 Dota 2 Panorama XML / CSS / JavaScript。入口由 `custom_ui_manifest.xml` 加载 `card_forge.xml`，进入 addon 自动打开，也可用控制台命令 `rpg_card_ui_preview` 打开。浏览器研究稿仅保留作设计参考。

## 已实现

- 当前 100 张基础卡：45 增益、35 消耗、20 场地。名称、轴、条件和完整三档效果从 `BASIC_CARDS_V1.md` 生成，不沿用旧演示基础卡文案。
- 拥有卡库和只读图鉴分开；图鉴不提供装备、交易或拖拽。阵营、类型、名称、ID、轴筛选；图鉴档位查看不改变拥有资产。
- 保留五张既有卡背及派生资源。基础卡用类型符号、底边颜色及文字区分，消耗卡附次数，轴为空或破折号时不画轴标记。
- 保留 8 英雄 × 2 槽、专属绑定、唯一资产、拖拽 / 点选装卸与替换、撤销、装载等级和预算拦截。已装备场地计数单列显示，仍占通用槽。
- 详情展示原文条件和完整 Lv1 / Lv2 / Lv3 效果。场地覆盖全战场，开战生成后不因携卡者阵亡消失；消耗次数与已有持续效果区分。
- 中英文外壳文本同步。英文界面的基础卡名及规则暂保留中文源文并明确标注；八张专属卡仍为原有演示样例。

## 实际边界

这是游戏内原生交互界面源码；持有、金币、英雄、交易和构筑状态仍为本地演示数据，未接服务端存档或战斗效果。逐卡 COST 均使用普通档示例，未替设计提案定档。当前仅展示默认触发条件，尚未提供条件编辑保存。图鉴切换档位用于次数与费用对照，复杂效果仍完整呈现三档原文，不尝试按斜杠机械拆值。

本轮未发现本机 Dota 2 / Workshop 安装，也未运行 resourcecompiler、真实引擎渲染或战斗。原生编译、分辨率适配、字体和实际拖拽验收继续由 `dota2_rpg-z4b` 跟踪；卡牌运行时接入由 `dota2_rpg-kwl` 跟踪。不可将离线 Panel 模拟测试当成 Dota 引擎验收。

## 生成、验证和安装

```bash
python scripts/build-native-card-data.py
python scripts/build-native-card-data.py --check
node tests/card-forge.test.js
```

离线测试覆盖表格同步、100 张分配、每张卡详情、图鉴只读、查看档位不改变 COST、双语文本、专属限制、唯一资产、满库替换、拖拽生命周期、撤销、交易及确认预算。卡背资源通过 `prepare-card-ui-assets.ps1 -Check` 验证。

在安装 Dota 2 Workshop Tools 的机器上运行（替换安装目录）：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install-endless-ui.ps1 -DotaPath 'D:\SteamLibrary\steamapps\common\dota 2 beta' -Compile
```

安装脚本包含新增数据脚本的编译，并逐个核对安装后的中英文 locale 文件哈希。主 addon 与独立 addon 的中英文版本标记均为 **UI 100**；实际新界面位于独立 addon。启动命令：

```text
dota_launch_custom_game dota2_rpg_endless dota
```
