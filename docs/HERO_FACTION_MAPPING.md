# 英雄阵营归属表（元素 / 文明 / 神域 / 深渊 / 荒野）

> 文档状态：**归属草案，等待确认**。本文只补上此前缺失的"英雄 → 阵营"映射，不改动任何代码、数据或版本号。
>
> 关联：
> - [阵营组合 buff 设计表](FACTION_COMBO_BUFFS.md)：五个阵营的方向、单/双/三阵营档位与命名键
> - [阵营卡牌模式设计](FACTION_CARD_MODE_DESIGN.md)：卡牌分类、专属卡/通用卡与合成升级
> - [羁绊与敌方随机词缀具体设计](BONDS_AND_RANDOM_AFFIXES_DESIGN.md)：八类羁绊标签（与本文的阵营是**两套独立**的分类）
> - [独立无尽模式设计](ENDLESS_MODE_DESIGN.md)：无尽模式边界
>
> 前置事实：`FACTION_COMBO_BUFFS.md` 此前引用的"无尽设计 §5.2 阵营层 / §5.3 阵营等级与组合"在 `ENDLESS_MODE_DESIGN.md` 中并不存在（该文件 §5 已是八类羁绊）。**阵营体系此前只有名字，从未有过英雄归属**；本文是这份映射的首次落盘。

## 1. 为什么需要这份表

`FACTION_COMBO_BUFFS.md` 定义了 `bond_element_*` 等 65 条组合效果的命名键和档位，但没有任何地方说明**哪名英雄属于哪个阵营**。没有这张表：

- 单阵营等级（该阵营上阵人数）无法计算；
- 双阵营/三阵营组合等级（参与阵营人数的最小值）无法计算；
- 卡牌的阵营分类（专属卡的装备限制）无法判定；
- 覆盖校验（如"每个阵营至少 6 名可招募成员"）无法执行。

## 2. 阵营定义与判定原则

阵营方向引自 `FACTION_COMBO_BUFFS.md` §2，判定原则如下。

| 阵营 | id | 方向 | 主题范围 | 判定侧重 |
| --- | --- | --- | --- | --- |
| 元素 | `element` | 技能增强与回复，随战斗时长成长 | 元素之力、大地与自然魔法、奥术能量 | 伤害主要来自技能、有明确的元素/自然主题 |
| 文明 | `civilization` | 攻速、护甲与固定值叠加，收益稳定 | 王国军队、骑士团、航海、机械与火药 | 组织化的人类/机械单位，普攻与阵型作战 |
| 神域 | `divine` | 治疗与护盾增幅、开场增益、团队减伤 | 神祇、圣光、月与天空、守护与灵魂 | 提供治疗/护盾/团队减伤，或有明确神职/守护背景 |
| 深渊 | `abyss` | 吸血、击杀收益、阵亡触发 | 恶魔、亡灵、虚空、腐蚀 | 恶魔/亡灵身份，或依赖吸血、击杀、死亡触发 |
| 荒野 | `wild` | 攻击力、生命上限与野性增益 | 野兽、蛮族、虫群、部族与森林生物 | 非人种族野兽/蛮族，靠普攻与生命值作战 |

判定规则：

1. **一名英雄恰好一个主阵营**，不设第二阵营。与八类羁绊"每人 2 标签"的两层结构不同，阵营是单值。
2. 阵营**不由力量/敏捷/智力推导**，与前缀属性无关。
3. 主题与战斗风格冲突时，**优先战斗风格**：阵营 buff 的方向按玩法设计，卡牌与羁绊要能对上英雄的实际打法。典型例子是宙斯（神王身份、纯技能爆发）归元素不归神域。
4. 分类**人工判定**，不自动从单个技能或属性生成。新英雄接入前必须补一行归属，不允许临时塞进默认阵营。
5. 阵营归属与八羁绊标签**互不取代**：八羁绊描述阵位与配合，阵营描述主题与 buff 方向，两套可以并存。
6. **用户指定的归属优先于上述原则**，并在此显式记录（见 §2.1），避免后续维护者按原则"纠正"回去。

### 2.1 用户指定归属

| 英雄 | 指定阵营 | 说明 |
| --- | --- | --- |
| 谜团 `enigma` | 神域 | 用户指定。谜团的技能组（黑洞、恶魔转化）不落在"治疗/护盾/团队减伤"上，按 §2-3 的原则本会归深渊；此处以用户判定为准，记录在案。 |

## 3. 全量归属表（122 名可招募英雄）

数据来源：`game/dota_addons/dota2_rpg/scripts/data/heroes.json` 与 `heroes.kv`（122 名，与 `data/native_hero_pool.json` 的 attribute/hero_id 一致）。中文名仅供参考，**实现一律以 `npc_dota_hero_*` 键为准**；标 `※` 的名称需要在本地化文件中核对。

### 3.1 元素 `element`（24 名）

| 英雄键 | 中文名 | 属性 | hero_id | 归属理由 |
| --- | --- | --- | ---: | --- |
| npc_dota_hero_earthshaker | 撼地者 | strength | 7 | 大地图腾与沟壑 |
| npc_dota_hero_spirit_breaker | 裂魂人 | strength | 71 | 灵体冲撞与能量 |
| npc_dota_hero_tiny | 小小 | strength | 19 | 岩石头部构成的元素体 |
| npc_dota_hero_ember_spirit | 灰烬之灵 | agility | 106 | 火焰之灵 |
| npc_dota_hero_faceless_void | 虚空假面 | agility | 41 | 虚空与时间之力 |
| npc_dota_hero_meepo | 米波 | agility | 82 | 地卜师，大地魔法 |
| npc_dota_hero_morphling | 变体精灵 | agility | 10 | 水元素 |
| npc_dota_hero_razor | 剃刀 | agility | 15 | 等离子与雷电 |
| npc_dota_hero_ancient_apparition | 远古冰魄 | intelligence | 68 | 冰霜元素 |
| npc_dota_hero_crystal_maiden | 水晶室女 | intelligence | 5 | 冰霜法术 |
| npc_dota_hero_dark_seer | 黑暗贤者 | intelligence | 55 | 离子与能量操控 |
| npc_dota_hero_dark_willow | 邪影芳灵 | intelligence | 119 | 妖精奥术 |
| npc_dota_hero_disruptor | 干扰者 | intelligence | 87 | 雷霆萨满 |
| npc_dota_hero_enchantress | 魅惑魔女 | intelligence | 58 | 森林自然之力 |
| npc_dota_hero_jakiro | 杰奇洛 | intelligence | 64 | 冰火双头龙 |
| npc_dota_hero_leshrac | 拉席克 | intelligence | 52 | 分裂大地与闪电 |
| npc_dota_hero_lina | 莉娜 | intelligence | 25 | 火焰法术核心 |
| npc_dota_hero_puck | 帕克 | intelligence | 13 | 精灵龙的奥术位移 |
| npc_dota_hero_pugna | 帕格纳 | intelligence | 45 | 幽冥与虚无能量 |
| npc_dota_hero_storm_spirit | 风暴之灵 | intelligence | 17 | 雷电之灵 |
| npc_dota_hero_arc_warden | 天穹守望者 | universal | 113 | 古老能量与自我复制 |
| npc_dota_hero_furion | 先知 | universal | 53 | 自然之力与森林召唤 |
| npc_dota_hero_sand_king | 沙王 | universal | 16 | 沙尘与大地元素 |
| npc_dota_hero_void_spirit | 虚无之灵 | universal | 126 | 四灵之一，以太形态 |

### 3.2 文明 `civilization`（23 名）

| 英雄键 | 中文名 | 属性 | hero_id | 归属理由 |
| --- | --- | --- | ---: | --- |
| npc_dota_hero_alchemist | 炼金术士 | strength | 73 | 炼金与工业化生产 |
| npc_dota_hero_dragon_knight | 龙骑士 | strength | 49 | 骑士团 |
| npc_dota_hero_kunkka | 昆卡 | strength | 23 | 海军统帅 |
| npc_dota_hero_largo | 拉戈 ※ | strength | 155 | 城邦表演文化 |
| npc_dota_hero_legion_commander | 军团指挥官 | strength | 104 | 军团建制 |
| npc_dota_hero_mars | 玛尔斯 | strength | 129 | 帝国战神与军团 |
| npc_dota_hero_rattletrap | 发条技师 | strength | 51 | 机械构造体 |
| npc_dota_hero_shredder | 伐木机 | strength | 98 | 工程机械 |
| npc_dota_hero_sven | 斯温 | strength | 18 | 游侠骑士 |
| npc_dota_hero_antimage | 敌法师 | agility | 1 | 修行者的反魔法纪律 |
| npc_dota_hero_bounty_hunter | 赏金猎人 | agility | 62 | 城镇佣兵交易 |
| npc_dota_hero_gyrocopter | 矮人直升机 | agility | 72 | 火器与飞行器 |
| npc_dota_hero_phantom_lancer | 幻影长矛手 | agility | 12 | 成建制长矛兵 |
| npc_dota_hero_sniper | 狙击手 | agility | 35 | 火枪与射程 |
| npc_dota_hero_grimstroke | 天涯墨客 | intelligence | 121 | 书法与笔阵 |
| npc_dota_hero_ringmaster | 马戏团长 ※ | intelligence | 131 | 城邦表演文化 |
| npc_dota_hero_silencer | 沉默术士 | intelligence | 75 | 猎魔教团 |
| npc_dota_hero_tinker | 修补匠 | intelligence | 34 | 科技与机器 |
| npc_dota_hero_brewmaster | 酒仙 | universal | 78 | 武僧行会与市井 |
| npc_dota_hero_marci | 玛西 | universal | 136 | 城镇护卫 |
| npc_dota_hero_pangolier | 石鳞剑士 | universal | 120 | 浪客剑士 |
| npc_dota_hero_snapfire | 电炎绝手 | universal | 128 | 火器与小镇 |
| npc_dota_hero_techies | 工程师 | universal | 105 | 爆破工程 |

### 3.3 神域 `divine`（25 名）

| 英雄键 | 中文名 | 属性 | hero_id | 归属理由 |
| --- | --- | --- | ---: | --- |
| npc_dota_hero_dawnbreaker | 破晓辰星 | strength | 135 | 黎明圣光 |
| npc_dota_hero_elder_titan | 上古巨神 | strength | 103 | 世界之魂与创世 |
| npc_dota_hero_huskar | 哈斯卡 | strength | 59 | 神谕教派的圣战士 |
| npc_dota_hero_omniknight | 全能骑士 | strength | 57 | 圣光守护 |
| npc_dota_hero_phoenix | 凤凰 | strength | 110 | 超新星重生 |
| npc_dota_hero_treant | 树精卫士 | strength | 83 | 活体护甲，全图守护 |
| npc_dota_hero_enigma | 谜团 | universal | 33 | **用户指定**（按原则本应归深渊） |
| npc_dota_hero_juggernaut | 主宰 | agility | 8 | 面具岛守护者，治疗守卫 |
| npc_dota_hero_luna | 露娜 | agility | 48 | 月神骑士 |
| npc_dota_hero_mirana | 米拉娜 | agility | 9 | 月之女祭司 |
| npc_dota_hero_monkey_king | 齐天大圣 | agility | 114 | 神话半神 |
| npc_dota_hero_templar_assassin | 圣堂刺客 | agility | 46 | 圣堂教团 |
| npc_dota_hero_vengefulspirit | 复仇之魂 | agility | 20 | 天空神系的亡魂 |
| npc_dota_hero_chen | 陈 | intelligence | 66 | 圣骑士与赎罪 |
| npc_dota_hero_keeper_of_the_light | 光之守卫 | intelligence | 90 | 圣光本身 |
| npc_dota_hero_muerta | 穆尔塔 ※ | intelligence | 138 | 亡者国度的神祇 |
| npc_dota_hero_oracle | 神谕者 | intelligence | 111 | 神谕与命运 |
| npc_dota_hero_skywrath_mage | 天怒法师 | intelligence | 101 | 天空神系 |
| npc_dota_hero_warlock | 术士 | intelligence | 37 | 暗言术治疗与神谕守卫 |
| npc_dota_hero_winter_wyvern | 寒冬飞龙 | intelligence | 112 | 治疗之寒与守护 |
| npc_dota_hero_witch_doctor | 巫医 | intelligence | 30 | 巫毒回复与守护 |
| npc_dota_hero_zuus | 宙斯 | intelligence | 22 | 神王 |
| npc_dota_hero_abaddon | 亚巴顿 | universal | 102 | 护盾与守护誓约 |
| npc_dota_hero_dazzle | 戴泽 | universal | 50 | 治疗与护盾增幅 |
| npc_dota_hero_visage | 维萨吉 | universal | 92 | 缚魂守卫 |

### 3.4 深渊 `abyss`（24 名）

| 英雄键 | 中文名 | 属性 | hero_id | 归属理由 |
| --- | --- | --- | ---: | --- |
| npc_dota_hero_abyssal_underlord | 孽主 | strength | 108 | 深渊领主 |
| npc_dota_hero_chaos_knight | 混沌骑士 | strength | 81 | 混沌恶魔 |
| npc_dota_hero_doom_bringer | 末日使者 | strength | 69 | 恶魔 |
| npc_dota_hero_life_stealer | 噬魂鬼 | strength | 54 | 亡灵寄生 |
| npc_dota_hero_night_stalker | 暗夜魔王 | strength | 60 | 暗夜恶魔 |
| npc_dota_hero_pudge | 帕吉 | strength | 14 | 腐肉与屠钩 |
| npc_dota_hero_skeleton_king | 冥魂大帝 | strength | 42 | 亡灵君主 |
| npc_dota_hero_undying | 不朽尸王 | strength | 85 | 亡灵与墓碑 |
| npc_dota_hero_bloodseeker | 血魔 | agility | 4 | 流血与吸血 |
| npc_dota_hero_clinkz | 克林克兹 | agility | 56 | 骷髅射手 |
| npc_dota_hero_nevermore | 影魔 | agility | 11 | 收集灵魂的恶魔 |
| npc_dota_hero_phantom_assassin | 幻影刺客 | agility | 44 | 暗影暗杀 |
| npc_dota_hero_spectre | 幽鬼 | agility | 67 | 复仇幽魂 |
| npc_dota_hero_terrorblade | 恐怖利刃 | agility | 109 | 恶魔 |
| npc_dota_hero_viper | 冥界亚龙 | agility | 47 | 冥界毒龙 |
| npc_dota_hero_lich | 巫妖 | intelligence | 31 | 亡灵法师 |
| npc_dota_hero_lion | 莱恩 | intelligence | 26 | 恶魔术士 |
| npc_dota_hero_necrolyte | 瘟疫法师 | intelligence | 36 | 瘟疫与亡灵 |
| npc_dota_hero_obsidian_destroyer | 殁境神蚀者 | intelligence | 76 | 殁境与虚空 |
| npc_dota_hero_queenofpain | 痛苦女王 | intelligence | 39 | 恶魔 |
| npc_dota_hero_shadow_demon | 暗影恶魔 | intelligence | 79 | 恶魔 |
| npc_dota_hero_shadow_shaman | 暗影萨满 | intelligence | 27 | 暗影巫术 |
| npc_dota_hero_bane | 祸乱之源 | universal | 3 | 噩梦恶魔 |
| npc_dota_hero_death_prophet | 死亡先知 | universal | 43 | 亡魂先知 |

### 3.5 荒野 `wild`（26 名）

| 英雄键 | 中文名 | 属性 | hero_id | 归属理由 |
| --- | --- | --- | ---: | --- |
| npc_dota_hero_axe | 斧王 | strength | 2 | 蛮族战将 |
| npc_dota_hero_bristleback | 钢背兽 | strength | 99 | 野猪人 |
| npc_dota_hero_centaur | 半人马战行者 | strength | 96 | 半人马部族 |
| npc_dota_hero_lycan | 狼人 | strength | 77 | 狼群头领 |
| npc_dota_hero_ogre_magi | 食人魔魔法师 | strength | 84 | 食人魔 |
| npc_dota_hero_primal_beast | 原始兽 ※ | strength | 137 | 原始巨兽 |
| npc_dota_hero_slardar | 斯拉达 | strength | 28 | 深海鱼人 |
| npc_dota_hero_tidehunter | 潮汐猎人 | strength | 29 | 深海巨兽 |
| npc_dota_hero_tusk | 巨牙海民 | strength | 100 | 北地蛮族 |
| npc_dota_hero_broodmother | 育母蜘蛛 | agility | 61 | 虫群 |
| npc_dota_hero_drow_ranger | 卓尔游侠 | agility | 6 | 荒野游侠 |
| npc_dota_hero_hoodwink | 森海飞霞 | agility | 123 | 森林松鼠 |
| npc_dota_hero_lone_druid | 德鲁伊 | agility | 80 | 自然与熊灵 |
| npc_dota_hero_medusa | 美杜莎 | agility | 94 | 蛇发女妖 |
| npc_dota_hero_naga_siren | 娜迦海妖 | agility | 89 | 深海海妖 |
| npc_dota_hero_riki | 力丸 | agility | 32 | 荒野潜行者 |
| npc_dota_hero_slark | 斯拉克 | agility | 93 | 深海暗礁逃囚 |
| npc_dota_hero_troll_warlord | 巨魔战将 | agility | 95 | 巨魔部族 |
| npc_dota_hero_ursa | 熊战士 | agility | 70 | 熊人 |
| npc_dota_hero_weaver | 编织者 | agility | 63 | 虫群 |
| npc_dota_hero_batrider | 蝙蝠骑士 | universal | 65 | 蝙蝠与蛮族 |
| npc_dota_hero_beastmaster | 兽王 | universal | 38 | 兽群训驭 |
| npc_dota_hero_magnataur | 马格纳斯 | universal | 97 | 巨兽 |
| npc_dota_hero_nyx_assassin | 司夜刺客 | universal | 88 | 虫族潜伏 |
| npc_dota_hero_venomancer | 剧毒术士 | universal | 40 | 剧毒虫族 |
| npc_dota_hero_windrunner | 风行者 | universal | 21 | 森林游侠 |

## 4. 分布与平衡

| 阵营 | 力量 | 敏捷 | 智力 | 全才 | 合计 | 占比 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 元素 | 3 | 5 | 12 | 4 | **24** | 19.7% |
| 文明 | 9 | 5 | 4 | 5 | **23** | 18.9% |
| 神域 | 6 | 6 | 9 | 4 | **25** | 20.5% |
| 深渊 | 8 | 7 | 7 | 2 | **24** | 19.7% |
| 荒野 | 9 | 11 | 0 | 6 | **26** | 21.3% |
| 合计 | 35 | 34 | 32 | 21 | **122** | 100% |

平衡结论：

1. **极差 3（26 − 23），满足"不超过 8"**。相对 122/5 = 24.4 的平均值，偏差 −1.4 ～ +1.6，没有任何阵营在凑人数上有系统性优势。
2. **神域从 15 补到 25**。补入的 10 名：谜团（用户指定）、亚巴顿、术士、维萨吉、穆尔塔、树精卫士、寒冬飞龙、凤凰、上古巨神、巫医。补充口径是"有治疗/护盾/守护语义，或神职与灵魂守护背景"。
3. **为了拉平，深渊让出 9 名**（谜团、亚巴顿、术士、维萨吉、穆尔塔去神域；裂魂人、虚空假面、帕格纳去元素；剧毒术士、斯拉克去荒野），**荒野让出 4 名**（巫医去神域，邪影芳灵、沙王去元素，酒仙去文明）。
4. 属性分布仍不均衡：**荒野没有智力英雄，元素以智力为主（12 名）**。这是 Dota 英雄设计本身的分布，不影响阵营强度和凑人数；如果希望每个阵营都能组出等比例的属性构成，需要把归类改成按属性配额，会牺牲主题一致性。
5. 全量 122 名开放时，各阵营都能轻松凑满单阵营 Lv5，差距只有约 1 人，不再需要按池占比归一化档位阈值（`FACTION_COMBO_BUFFS.md` §7-2 可以关闭）。

## 5. 首轮开放子集（每阵营 6 名，共 30 名）

按 `BONDS_AND_RANDOM_AFFIXES_DESIGN.md` §9.1"每个羁绊至少有 6 名可招募成员"的口径，首轮每阵营各开 6 名，凑满单阵营 Lv5 加双阵营 Lv2 所需的人数，同时保证每个阵营的档位都能被验证。

| 阵营 | 首轮 6 名 |
| --- | --- |
| 元素 | 莉娜、拉席克、杰奇洛、水晶室女、撼地者、上古巨神 |
| 文明 | 昆卡、龙骑士、斯温、军团指挥官、玛尔斯、修补匠 |
| 神域 | 全能骑士、陈、光之守卫、神谕者、破晓辰星、露娜 |
| 深渊 | 影魔、莱恩、巫妖、痛苦女王、冥魂大帝、噬魂鬼 |
| 荒野 | 熊战士、巨魔战将、育母蜘蛛、兽王、半人马战行者、巨牙海民 |

选择标准：原生技能语义已在 `data/native_skill_conditions.json` 中完成条件适配、在 `docs/CONDITION_COVERAGE.md` 中有覆盖记录的英雄优先；同阵营内尽量覆盖前排/输出/辅助三种职责，避免某一阵营只能组出单一打法。

## 6. 落地建议（确认后才执行）

| 项目 | 建议 |
| --- | --- |
| 源数据 | 新增 `scripts/data/hero_factions.json`：`{ hero: "npc_dota_hero_axe", faction: "wild", note: "..." }` |
| 运行时数据 | 由生成器写 `hero_factions.kv`，与 JSON 双向校验，禁止两份手工维护 |
| 与 heroes.json 的关系 | 不修改 `heroes.json`/`heroes.kv` 的招募池分组（那 4 组是属性分组）。阵营是独立的新维度，避免把属性分组当成阵营 |
| 校验 | ① 招募池每名英雄恰好 1 个阵营，缺失或未知阵营即构建失败；② 阵营取值只能是 5 个 id；③ 每个阵营人数 ≥ 6；④ 最大最小阵营人数差 ≤ 8；⑤ 用户指定归属必须在表中有记录 |
| 展示 | 招募卡片、编队面板、英雄详情显示阵营徽章；与八羁绊徽章分区显示，不用同一套图标 |

## 7. 待确认项

1. **主阵营是否够用**。当前每人一个主阵营。若要表达"斧王既是荒野也是深渊"，需要改成 1 主 + 1 副的结构，但那会让组合档位计算和卡牌装备限制都复杂一档。建议先只做主阵营。
2. **边缘归属**。以下判定按"优先战斗风格/守护语义"给出，如果按纯主题会不同，可单独调整：
   - 宙斯 → 元素（神王身份属神域，但纯技能爆发属元素）
   - 帕格纳 / 黑暗贤者 / 殁境神蚀者 → 元素（能量语义）与深渊（腐蚀语义）之间
   - 裂魂人 / 虚空假面 → 元素（灵体与虚空能量）与深渊之间
   - 剧毒术士 / 斯拉克 → 荒野（虫族与深海生物）与深渊之间
   - 复仇之魂 → 神域（亡魂属深渊，但归属天空神系）
   - 酒仙 → 文明（武僧行会）与荒野（流浪）之间
   这些是拉平人数时最先被动过的位置，如果哪一条不符合你的设定，直接改回即可，人数差仍有 8 的余量。
3. **`※` 标记的中文名**需要核对本地化文件（拉戈、马戏团长、穆尔塔、原始兽）。实现只依赖 `npc_dota_hero_*` 键，名称不影响逻辑。
4. **新英雄接入流程**。`data/native_hero_pool.json` 目前是 127 名，招募池是 122 名（排除 5 名）。新增英雄时必须同步补阵营，否则构建失败——这条要不要写进 `tests/recruitable-heroes.test.py` 的覆盖检查，需确认。
