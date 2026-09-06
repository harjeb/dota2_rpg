# Panorama 接线说明

自动安装器会在 `custom_ui_manifest.xml` 加载：

```xml
<CustomUIElement type="Hud" layoutfile="file://{resources}/layout/custom_game/issue_fixes_ui.xml" />
```

UI 脚本会尝试识别常见 Panel ID。若你的 ID 不同，在现有 HUD 初始化完成后显式调用。

## 1. 行动面板最小化按钮

```javascript
var fixUi = GameUI.CustomUIConfig().RpgIssueFixUI;
fixUi.bindActionPanel({
    panel: $("#你的行动面板ID"),
    button: $("#你的最小化按钮ID")
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
- 删除最后一条玩家规则后，恢复单条默认普攻兜底。
