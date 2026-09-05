return {
    frontline = {
        name = "铁壁阵线",
        thresholds = {
            [2] = { member_max_health_pct = 5 },
            [3] = { member_max_health_pct = 8, opening_backline_shield_pct = 5 },
        },
    },
    caster = {
        name = "奥术共鸣",
        thresholds = {
            [2] = { member_mana_regen_pct = 8 },
            [3] = { member_mana_regen_pct = 8, arcane_echo_charges = 2, arcane_echo_mana_pct = 3 },
        },
    },
    hunter = {
        name = "猎手协同",
        thresholds = {
            [2] = { hunt_mark_damage_pct = 5, hunt_mark_duration = 4, hunt_mark_cooldown = 10 },
            [3] = { hunt_mark_damage_pct = 8, hunt_mark_duration = 4, hunt_mark_cooldown = 10 },
        },
    },
    support = {
        name = "救援网络",
        thresholds = {
            [2] = { member_heal_amp_pct = 6 },
            [3] = { member_heal_amp_pct = 10, emergency_shield_pct = 6 },
        },
    },
    controller = {
        name = "控制链",
        thresholds = {
            [2] = { disabled_target_damage_pct = 4 },
            [3] = { disabled_target_damage_pct = 7 },
        },
    },
    summoner = {
        name = "召唤军势",
        thresholds = {
            [2] = { summon_health_pct = 8, summon_duration_pct = 8 },
            [3] = { summon_health_pct = 13, summon_duration_pct = 13 },
        },
    },
}
