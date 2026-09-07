# Panorama 接线说明

自动安装器会在 `custom_ui_manifest.xml` 加载：

```xml
<CustomUIElement type="Hud" layoutfile="file://{resources}/layout/custom_game/issue_fixes_ui.xml" />
```

UI 脚本会尝试识别常见 Panel ID。若你的 ID 不同，在现有 HUD 初始化完成后显式调用。

本仓库的主 HUD 已直接加载 `issue_fixes_ui.css`（放在基础 CSS 之后）和修复脚本，并显式绑定 `RadiantEditor` / `DireEditor`、各自 CollapseButton/CollapseLabel 和 `ShopPanel`。兄弟布局的 CSS 不保证作用于主 HUD，不能只加 manifest 就认为接线完成。独立 overlay 不覆盖整份主 HUD；移植时需要手工合并这些接线以及 `rpg_demo_hud.js`、`panorama_rule_sync.js` 的实际规则行数同步逻辑。附加布局根 Panel 不得设置 `id`，否则 Panorama 编译会失败。

## 1. 行动面板最小化按钮

```javascript
var fixUi = GameUI.CustomUIConfig().RpgIssueFixUI;
fixUi.bindActionPanel({
    panel: $("#你的行动面板ID"),
    button: $("#你的最小化按钮ID"),
    label: $("#你的箭头LabelID")
});
```

按钮文字行为：

- 展开：`<`
- 收起：`>`

CSS 固定按钮为 44×44，收起容器为 56×56。不要再通过把父容器宽度设成 `0px`、`1px` 或 `fit-children` 实现收起。

现有按钮内的 Label 最好改为：

```xml
<Button id="ActionPanelMinimizeButton">
    <Label id="ActionPanelCollapseArrow" text="&lt;" />
</Button>
```

## 2. 英雄商店透明化

```javascript
fixUi.makeHeroShopTransparent($("#你的英雄商店根PanelID"));
```

`RpgTransparentHeroShop` 会清除根面板与常见 Frame/Body 背景、边框和阴影。只给单个英雄报价卡保留轻微半透明底，避免文字无法辨认。

如果原 CSS 使用更高优先级的 ID 选择器，删除/改写这些属性：

```css
background-color: ...;
border: ...;
box-shadow: ...;
```

不要给整个商店根容器新增另一层不透明背景。

## 3. 默认规则只保留一条

在把服务器规则写入本地 UI 模型时：

```javascript
var fixUi = GameUI.CustomUIConfig().RpgIssueFixUI;
heroModel.rules = fixUi.normalizeDefaultRules(serverRules);
renderRules(heroModel.rules);
```

删除类似逻辑：

```javascript
while (rules.length < actionSlotCount) {
    rules.push(makeDefaultRule());
}
```

以及：

```javascript
for (var i = 0; i < activeSkills.length + activeItems.length + 1; i++) {
    createRuleRow(...);
}
```

正确行为：

- 没有有效规则：显示 1 条默认普通攻击规则。
- 有 N 条玩家规则：显示 N 条，不补齐空白规则。
- 点击“新增规则”才增加一条。
- 至少保留一条规则；无有效规则时恢复单条默认普攻兜底。
- `MAX_RULE_ROWS = 10` 仅是编辑上限，不是初始化或同步行数。
- 每条 `rpg_update_rule` 携带整数 `rule_count`（1..10），`slot` 不得超过该值；实际 `RuleService` 校验权限后裁掉多余旧槽位。只发送实际行，不发送禁用占位行。
- 删除后重新发送当前实际行，保留玩家主动禁用的有效规则。
- 服务端 `RuleService` 与客户端 `panorama_rule_sync.js` 必须一起合并；仅复制 UI helper 不会实现裁剪协议。
