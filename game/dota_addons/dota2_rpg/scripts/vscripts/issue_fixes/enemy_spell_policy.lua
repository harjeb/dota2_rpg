-- Named policies for generated enemy spells. Native execution remains the owner
-- of cast legality, mana, cooldowns, healing and duration.
local Policy = {}
local heals = {omniknight_purification=0.85, dazzle_shadow_wave=0.85}
local saves = {
    dazzle_shallow_grave={hp=0.35,modifier="modifier_dazzle_shallow_grave"},
    oracle_false_promise={hp=0.40,modifier="modifier_oracle_false_promise_timer"},
}
local function append(rule,key,condition)
    rule[key]=rule[key] or {}
    rule[key][#rule[key]+1]=condition
end
function Policy.Apply(_unit,rule,_ability)
    local name=rule.action and rule.action.logical_id
    if name=="dazzle_nothl_projection_end" then
        -- This becomes visible during projection. Automatically pressing it on
        -- the next AI tick immediately cancels Dazzle's own ultimate.
        rule.enabled=false
        return
    end
    local save=saves[name]
    if rule.target and rule.target.team=="ally" and (heals[name] or save) then
        append(rule,"target_filters",{type="hp_pct_lte",value=save and save.hp or heals[name]})
        if save then
            append(rule,"target_filters",{type="not_has_modifier",modifier=save.modifier})
            rule.target_priorities={{type="lowest_hp_pct"},{type="nearest"}}
        else
            rule.target_priorities={{type="most_missing_health"},{type="nearest"}}
        end
    elseif name=="abaddon_borrowed_time" then
        append(rule,"use_conditions",{type="self_hp_pct_lte",value=0.40})
    end
end
return Policy
