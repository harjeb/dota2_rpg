-- Soft target ranking for generated enemy hero rules only.
local Context = require("tactics/condition_context")
local Policy = {}
local controls = {
    lion_voodoo=true, lion_impale=true, shadow_shaman_voodoo=true, shadow_shaman_shackles=true,
    crystal_maiden_frostbite=true, bane_fiends_grip=true, bane_nightmare=true,
    item_sheepstick=true, item_abyssal_blade=true, item_orchid=true, item_bloodthorn=true,
    item_cyclone=true, item_wind_waker=true,
}
local function number(unit, method, fallback, ...)
    local value = Context.Call(unit, method, ...)
    return tonumber(value) or fallback
end

function Policy.Apply(unit, rule, ability)
    if Context.Call(unit,"IsRealHero") ~= true or not rule.target or rule.target.team ~= "enemy"
        or rule.enemy_attack_objective then return end
    local action = rule.action or {}
    if action.kind ~= "attack" and action.kind ~= "ability" and action.kind ~= "item" then return end
    -- Pike is an emergency separation tool: push away the nearest threat.
    if action.logical_id == "item_hurricane_pike" then return end
    local damage = action.kind == "attack" and "physical" or "magical"
    local native = Context.Call(ability,"GetAbilityDamageType")
    if native == (DAMAGE_TYPE_PHYSICAL or 1) then damage = "physical"
    elseif native == (DAMAGE_TYPE_PURE or 4) or native == (DAMAGE_TYPE_NONE or 0) then damage = "pure" end
    local reach = action.kind == "attack" and number(unit,"Script_GetAttackRange",150)
        or number(ability,"GetCastRange",600,Context.Call(unit,"GetAbsOrigin"),nil)
    local priorities = {}
    if controls[action.logical_id or action.name] then
        priorities[#priorities+1] = {type="prefer_channeling"}
    end
    priorities[#priorities+1] = {type="enemy_combat_value",damage_type=damage,reach=reach}
    priorities[#priorities+1] = {type="nearest"}
    rule.target_priorities = priorities
end

function Policy.Score(priority, ctx, target)
    local health = math.max(1,number(target,"GetHealth",1))
    local multiplier = 1
    if priority.damage_type == "physical" then
        local armor = number(target,"GetPhysicalArmorValue",0,false)
        multiplier = 1 - 0.06 * armor / (1 + 0.06 * math.abs(armor))
    elseif priority.damage_type == "magical" then
        multiplier = 1 - math.max(0,math.min(0.95,number(target,"GetMagicalArmorValue",0)))
    end
    local origin, position = Context.Call(ctx.caster,"GetAbsOrigin"), Context.Call(target,"GetAbsOrigin")
    local distance = origin and position and (position-origin):Length2D() or 0
    -- A short step toward a vulnerable target is useful; walking past the whole
    -- frontline has a large opportunity cost. Hard native legality/range still wins.
    local travel = math.max(0,distance-math.max(0,tonumber(priority.reach) or 0))
    local cost = health / math.max(0.05,multiplier) * (1 + distance/1800 + travel/250)
    -- Illusions/summons are valid fallbacks, but usually not worth committing a
    -- full spell combo to while a similarly reachable real hero is available.
    if Context.Call(target,"IsIllusion") == true then cost = cost * 2
    elseif Context.Call(target,"IsRealHero") == false then cost = cost * 1.5 end
    return cost
end
return Policy
