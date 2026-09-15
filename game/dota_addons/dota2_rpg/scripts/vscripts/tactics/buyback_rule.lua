-- Buyback is a death policy, with no combat targeting or optional predicates.
local BuybackRule = {}
function BuybackRule.Normalize(rule)
    if type(rule) ~= "table" or type(rule.action) ~= "table"
        or rule.action.kind ~= "buyback" or rule.action.logical_id ~= "buyback" then return rule end
    rule.action = {kind="buyback", logical_id="buyback", target_mode="self", target_team="self"}
    rule.target = {team="self", types={"hero"}}
    rule.use_conditions, rule.target_filters, rule.target_priorities = {}, {}, {}
    rule.use_conditions_mode, rule.target_filters_mode = "all", "all"
    rule.approach = "range_only"
    rule.chase_timeout, rule.max_chase_distance, rule.aoe_prefer_tag = nil, nil, nil
    rule.min_aoe_hits, rule.allow_unverified_modifiers = nil, nil
    return rule
end
return BuybackRule
