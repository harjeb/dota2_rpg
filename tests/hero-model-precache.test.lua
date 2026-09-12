-- 敌方英雄模型只能在地图加载期加载：运行期 PrecacheResource / PrecacheUnitByNameSync
-- 都被原版拒绝，PrecacheUnitByNameAsync 的回调只是"已受理"。这个模块负责把
-- "哪些英雄、要加载哪些资源"从关卡表里算出来，并尽力调用原生预加载。
local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local HeroModel = require("battle.hero_model_precache")

local levels = {
    ch05 = { enemies = { { unit = "npc_dota_hero_axe" }, { unit = "npc_dota_hero_drow_ranger" } } },
    ch06 = { enemies = { { unit = "npc_dota_neutral_alpha_wolf" }, { unit = "npc_dota_hero_axe" } } },
    ch10 = { enemies = { { unit = "npc_dota_hero_crystal_maiden" }, { unit = "npc_rpg_skill_test_target" } } },
    ch11 = { enemies = "malformed" },
    ch12 = nil,
}
local names = HeroModel.HeroNames(levels)
assert(#names == 3, "only distinct enemy heroes count, got " .. #names)
assert(names[1] == "npc_dota_hero_axe" and names[2] == "npc_dota_hero_drow_ranger"
    and names[3] == "npc_dota_hero_crystal_maiden", "heroes follow level order and dedupe")
assert(#HeroModel.HeroNames(nil) == 0 and #HeroModel.HeroNames({}) == 0, "missing levels are safe")

-- 英雄模型是分件独立文件（models/heroes/drow/drow_cape.vmdl 等原版会逐个请求），
-- 所以每个英雄既要加载本体，也要加载它所在的整个目录。
local heroModels = {
    npc_dota_hero_axe = "models/heroes/axe/axe.vmdl",
    npc_dota_hero_drow_ranger = "models/heroes/drow/drow_base.vmdl",
    npc_dota_hero_crystal_maiden = "",
}
local resources = HeroModel.Resources(levels, heroModels)
local byHero = {}
for _, r in ipairs(resources) do
    byHero[r.name] = byHero[r.name] or {}
    byHero[r.name][#byHero[r.name] + 1] = r.kind .. ":" .. r.path
end
assert(#byHero["npc_dota_hero_axe"] == 2
    and byHero["npc_dota_hero_axe"][1] == "model:models/heroes/axe/axe.vmdl"
    and byHero["npc_dota_hero_axe"][2] == "model_folder:models/heroes/axe",
    "axe loads its model and its part-model folder")
assert(byHero["npc_dota_hero_drow_ranger"][1] == "model:models/heroes/drow/drow_base.vmdl"
    and byHero["npc_dota_hero_drow_ranger"][2] == "model_folder:models/heroes/drow",
    "drow folder covers its separate part models")
assert(byHero["npc_dota_hero_crystal_maiden"] == nil,
    "a hero without a usable model path contributes nothing")
assert(#HeroModel.Resources(levels, nil) == 0, "a missing hero model table is safe")

-- 原生拒绝只打日志、不抛错；任何一次失败都不能连累整个地图加载。
local calls, attempted = {}, 0
local function precache(kind, path, context)
    attempted = attempted + 1
    if path == "models/heroes/drow/drow_base.vmdl" then error("native precache rejected") end
    calls[#calls + 1] = { kind = kind, path = path, context = context }
end
local context = { token = "map-load" }
local applied = HeroModel.Apply(resources, context, precache)
assert(attempted == #resources, "every resource is attempted even after a failure")
assert(applied == #resources - 1, "the throwing resource is not counted, got " .. applied)
assert(calls[1].context == context and calls[1].kind == "model", "the map-load context is forwarded")
assert(HeroModel.Apply(nil, context, precache) == 0, "empty plan is safe")
assert(HeroModel.Apply(resources, context, nil) == 0, "missing native API is safe")

print("PASS: enemy hero models are planned for map-load precache (model + part-model folder)")
