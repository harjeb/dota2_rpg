local Catalog = require("tactics/ability_catalog")
local Snapshot = {}
local function unit_name(unit)
    if unit == nil then return nil end
    local ok, name = pcall(function()
        if unit.IsNull ~= nil and unit:IsNull() then return nil end
        return unit:GetUnitName()
    end)
    if ok then return name end
end
function Snapshot.IsDeveloperMode()
    if type(IsInToolsMode) ~= "function" then return false end
    local ok, value = pcall(IsInToolsMode)
    return ok and value == true
end
function Snapshot.IsEnemy(manager, hero)
    for _, unit in ipairs(manager.teamHeroes[DOTA_TEAM_BADGUYS] or {}) do
        if unit == hero then return true end
    end
    return false
end
function Snapshot.HeroKey(manager, hero)
    local name = unit_name(hero)
    if name == nil then return nil end
    -- Assigned at spawn, before dead creeps disappear from the engine. This
    -- preserves duplicate-enemy identities even after earlier copies vanish.
    if hero.ruleSnapshotKey ~= nil then return hero.ruleSnapshotKey end
    if hero.lineupHeroName ~= nil then return hero.lineupHeroName end
    local occurrence = 0
    for _, unit in ipairs(manager.teamHeroes[DOTA_TEAM_BADGUYS] or {}) do
        if unit_name(unit) == name then
            if unit == hero then return "enemy:" .. name .. ":" .. occurrence end
            occurrence = occurrence + 1
        end
    end
    return name
end
local function list(input)
    local output = {}
    for _, condition in ipairs(input or {}) do
        local entry = {}
        for _, key in ipairs({ "type", "value", "radius", "seconds", "action_id", "action_actor", "modifier" }) do
            if condition[key] ~= nil then entry[key] = condition[key] end
        end
        output[#output+1] = entry
    end
    return output
end
function Snapshot.ForHero(manager, hero)
    if unit_name(hero) == nil then return {} end
    local result = {}
    local rules = manager.getRules ~= nil and manager.getRules(hero) or {}
    for _, rule in ipairs(rules or {}) do
        local action = rule.action or {}
        local name = action.logical_id or action.name or "attack"
        if action.kind == "attack" then
            name = "attack"
        elseif action.kind == "ability" then
            local _, native = Catalog.DescribeAction(hero, name)
            name = native ~= "" and native or name
        elseif action.kind == "item" and not name:match("^item_%d+$") and hero.GetItemInSlot ~= nil then
            for slot = 0, 5 do
                local item = hero:GetItemInSlot(slot)
                if item ~= nil and not item:IsNull() and item:GetAbilityName() == name then name = "item_" .. (slot+1); break end
            end
        end
        result[#result+1] = { action=name, enabled=rule.enabled ~= false and 1 or 0,
            target_team=rule.target and rule.target.team or "enemy",
            forced=rule.approach == "allow_approach" and 1 or 0,
            use_conditions=list(rule.use_conditions), target_filters=list(rule.target_filters),
            target_priorities=list(rule.target_priorities), min_aoe_hits=rule.min_aoe_hits or 0,
            destination=action.destination or "target",
            cast_preference=action.cast_preference or "auto",
            desired_toggle_state=action.desired_toggle_state == nil and "" or (action.desired_toggle_state and "1" or "0") }
    end
    return result
end
return Snapshot
