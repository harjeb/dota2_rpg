-- Fill native Necromastery only in preparation. Do not emulate soul damage,
-- kills, or Requiem, and never create/replace the engine's intrinsic modifier.
local Nevermore = {}
local function call(entity, method, ...)
    if entity == nil then return nil end
    local ok, fn = pcall(function() return entity[method] end)
    if not ok or type(fn) ~= "function" then return nil end
    local success, value = pcall(fn, entity, ...)
    if success then return value end
end
local function positive(value)
    return type(value) == "number" and value == value and value > 0 and value < math.huge
end
function Nevermore.ResetPreparation(game, hero)
    if not game or game.phase ~= "setup" or call(hero, "IsNull") == true
        or call(hero, "GetUnitName") ~= "npc_dota_hero_nevermore" then return false end
    local ability = call(hero, "FindAbilityByName", "nevermore_necromastery")
    if ability == nil or call(ability, "IsNull") == true then return false end
    local level = call(ability, "GetLevel")
    if type(level) ~= "number" or level < 1 then return false end
    local modifier = call(hero, "FindModifierByName", "modifier_nevermore_necromastery")
    if modifier == nil or call(modifier, "IsNull") == true then return false end
    -- Current native KV exposes a dynamic cap, including native adjustments.
    -- Fall back to the resolved special (not raw KV / a hardcoded soul count).
    -- Installed KV: 20, +5 talent; shard/scepter do not increase this cap.
    local capacity = call(ability, "GetSpecialValueFor", "current_max_souls_tooltip")
    if not positive(capacity) then
        capacity = call(ability, "GetSpecialValueFor", "necromastery_max_souls")
    end
    if not positive(capacity) then return false end
    capacity = math.floor(capacity)
    if capacity < 1 then return false end
    if call(modifier, "GetStackCount") == capacity then return true end
    local ok, setter = pcall(function() return modifier.SetStackCount end)
    if not ok or type(setter) ~= "function" then return false end
    return pcall(setter, modifier, capacity)
end
function Nevermore.RefreshPreparation(game)
    if not game or game.phase ~= "setup" then return end
    -- Retry delayed native initialization; cover retained/restored and bench units.
    for _, team in pairs(game.battleManager and game.battleManager.teamHeroes or {}) do
        for _, hero in pairs(team) do Nevermore.ResetPreparation(game, hero) end
    end
    for _, hero in pairs(game.benchUnits or {}) do Nevermore.ResetPreparation(game, hero) end
end
return Nevermore
