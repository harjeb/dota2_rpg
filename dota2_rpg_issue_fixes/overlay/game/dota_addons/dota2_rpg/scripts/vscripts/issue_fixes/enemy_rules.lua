-- Enemy spell rules follow the spawned unit's native abilities, not generic
-- profile slots (ability_1 can be a heal on one hero and a nuke on another).
local Defaults = require("issue_fixes.default_rules")
local EnemyRules = {}

function EnemyRules.CreateForUnit(unit, profileRules)
    local rules = Defaults.CreateForHero(unit)
    local attack = table.remove(rules)
    -- Profiles continue to choose basic-attack priorities/chase policy. Their
    -- positional spell rules cannot safely describe an arbitrary enemy hero.
    for _, rule in ipairs(profileRules or {}) do
        if type(rule.action) == "table" and rule.action.kind == "attack" then
            attack = rule
            break
        end
    end
    for _, rule in ipairs(rules) do
        rule.id = "enemy_" .. rule.id
        if rule.target.team == "self" then
            local ability = unit.FindAbilityByName and unit:FindAbilityByName(rule.action.logical_id)
            local radius = ability and ability.GetAOERadius and tonumber(ability:GetAOERadius()) or 0
            if radius > 0 then
                rule.use_conditions = { { type = "nearby_enemies_gte", radius = radius, value = 1 } }
            else
                rule.use_conditions = { { type = "alive_enemy_count_gte", value = 1 } }
            end
        end
    end
    rules[#rules + 1] = attack
    return rules
end

return EnemyRules
