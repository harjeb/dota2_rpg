-- This is deliberately a small example. Generate and validate the real file per patch.
return {
    npc_dota_hero_axe = {
        status = "supported",
        variant = { policy = "verified_default", variant_id = "patch_default", dedicated_server_verified = true },
        innate = { active = false, adapter_id = nil },
        talents = { player_selectable = true, enemy_plan_id = "axe_frontline_v1", level_30_verified = true },
        tags = { "frontline", "controller" },
        actions = {
            primary_control = { name = "axe_berserkers_call", cast_type = "none", target_team = "enemy", aoe_radius = 300 },
            primary_nuke = { name = "axe_battle_hunger", cast_type = "unit", target_team = "enemy" },
            finisher = { name = "axe_culling_blade", cast_type = "unit", target_team = "enemy" },
        },
        shard_verified = true,
        scepter_verified = true,
    },
    npc_dota_hero_dazzle = {
        status = "supported",
        variant = { policy = "verified_default", variant_id = "patch_default", dedicated_server_verified = true },
        innate = { active = false, adapter_id = nil },
        talents = { player_selectable = true, enemy_plan_id = "dazzle_support_v1", level_30_verified = false },
        tags = { "support", "caster", "healer" },
        actions = {
            primary_heal = { name = "dazzle_shadow_wave", cast_type = "unit", target_team = "ally" },
            save = { name = "dazzle_shallow_grave", cast_type = "unit", target_team = "ally" },
            debuff = { name = "dazzle_poison_touch", cast_type = "unit", target_team = "enemy" },
        },
        shard_verified = false,
        scepter_verified = false,
    },
    npc_dota_hero_crystal_maiden = {
        status = "partial",
        variant = { policy = "verified_default", variant_id = "patch_default", dedicated_server_verified = false },
        innate = { active = false, adapter_id = nil },
        talents = { player_selectable = true, enemy_plan_id = "cm_control_v1", level_30_verified = false },
        tags = { "caster", "controller", "backline" },
        actions = {
            area_nuke = { name = "crystal_maiden_crystal_nova", cast_type = "point", target_team = "enemy", aoe_radius = 425 },
            single_control = { name = "crystal_maiden_frostbite", cast_type = "unit", target_team = "enemy" },
            channel_ultimate = { name = "crystal_maiden_freezing_field", cast_type = "none", target_team = "enemy", aoe_radius = 810 },
        },
        notes = "Ultimate needs channel-preservation tests and dedicated-server regression.",
        shard_verified = false,
        scepter_verified = false,
    },
}
