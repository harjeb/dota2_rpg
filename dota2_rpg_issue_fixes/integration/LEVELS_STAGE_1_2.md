# 第 1/2 关敌人配置

不要覆盖两关奖励、时间、倍率或掉落，只替换第 2 关的 `enemies` 块，使组合与第 1 关不同。

建议保留第 1 关现有新手单位；第 2 关使用：

```text
3 × npc_dota_neutral_centaur_outrunner
1 × npc_dota_neutral_centaur_khan
```

KV 示例（字段名按当前 `levels.kv` 保持一致）：

```text
"2"
{
    // 其他第 2 关字段保持原样
    "enemies"
    {
        "1"
        {
            "unit"       "npc_dota_neutral_centaur_outrunner"
            "level"      "2"
            "ai_profile" "attack_nearest"
            "tags"       "melee,standard"
        }
        "2"
        {
            "unit"       "npc_dota_neutral_centaur_outrunner"
            "level"      "2"
            "ai_profile" "attack_nearest"
            "tags"       "melee,standard"
        }
        "3"
        {
            "unit"       "npc_dota_neutral_centaur_outrunner"
            "level"      "2"
            "ai_profile" "attack_nearest"
            "tags"       "melee,standard"
        }
        "4"
        {
            "unit"       "npc_dota_neutral_centaur_khan"
            "level"      "2"
            "ai_profile" "attack_nearest"
            "tags"       "melee,leader"
        }
    }
}
```

运行时 `level_uniqueness.lua` 还会计算每关单位多重集合签名。例如：

```text
npc_dota_neutral_centaur_khanx1+npc_dota_neutral_centaur_outrunnerx3
```

两个关卡签名完全相同就输出错误。该校验比较组合而非显示名称，所以改关卡标题不能绕过。
