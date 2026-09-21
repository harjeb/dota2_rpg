-- Enemy-only policies for current equipped native items. Regenerated each tick;
-- the ordinary action adapter owns cooldown, mana, mute, range and native orders.
local Defaults = require("issue_fixes.default_rules")
local Behavior = require("tactics/ability_behavior")
local Items = {}
local function call(object, method, ...)
    if object and object[method] then return object[method](object, ...) end
    return nil
end
local function hp(value) return {type="self_hp_pct_lte",value=value} end
local function mana(value) return {type="self_mana_pct_lte",value=value} end
local function nearby(radius) return {type="nearby_enemies_gte",radius=radius or 700,value=1} end
local function special(item, key, fallback)
    local value = tonumber(call(item,"GetSpecialValueFor",key)) or 0
    return value > 0 and value or fallback
end

-- Reviewed against installed scripts/npc/items.txt and runtime levels.kv.
-- Attribute cycling and tree cutting do not receive combat actions. Unknown
-- items, including teleports, have no fallback.
Items.Excluded = {
    item_power_treads="attribute cycling is not a combat cast",
    item_bfury="tree cutting is not an enemy combat action",
}
local defensive = {
    item_black_king_bar=true, item_blade_mail=true, item_pipe=true, item_crimson_guard=true,
}
local buffs = {item_manta=true,item_phase_boots=true,item_silver_edge=true,item_boots_of_bearing=true}
local blinks = {item_blink=true,item_overwhelming_blink=true,item_swift_blink=true,item_arcane_blink=true}
local controls = {
    item_sheepstick=true,item_bloodthorn=true,item_orchid=true,item_abyssal_blade=true,
    item_diffusal_blade=true,item_disperser=true,item_heavens_halberd=true,item_nullifier=true,item_rod_of_atos=true,
}
local function cooling_spells(unit)
    local count=0
    for slot=0,(call(unit,"GetAbilityCount") or 0)-1 do
        local a=unit:GetAbilityByIndex(slot)
        if a and call(a,"IsNull")~=true and call(a,"GetAbilityName")~="skeleton_king_reincarnation"
            and call(a,"IsPassive")~=true and call(a,"IsHidden")~=true
            and call(a,"IsActivated")~=false and (call(a,"GetLevel") or 0)>0
            and (tonumber(call(a,"GetCooldownTimeRemaining")) or 0)>=10 then count=count+1 end
    end
    return count>=2
end
-- After Silver Edge is submitted, cover its native fade time, then preserve the
-- observed windwalk until an attack breaks it (or native dispel/expiry ends it).
-- This is enemy rule selection only: it never fabricates invisibility or orders.
function Items.OpeningRules(unit, attack)
    local state = unit and unit.rpgActionLifecycle
    local cast = state and state.actions and state.actions.item_silver_edge
    local started = cast and math.max(tonumber(cast.requested_at) or -math.huge,
        tonumber(cast.executed_at) or -math.huge)
    local events = unit and unit.rpgTacticsEvents
    local succeeded = events and events.successes and events.successes.item_silver_edge
    if succeeded and tonumber(succeeded.time) then
        started = math.max(started or -math.huge, tonumber(succeeded.time))
    end
    local now = tonumber(call(GameRules,"GetGameTime"))
    if started and now and now >= started then
        local source
        for slot=0,5 do
            local candidate=call(unit,"GetItemInSlot",slot)
            if call(candidate,"GetAbilityName")=="item_silver_edge" then source=candidate;break end
        end
        local fade=special(source,"windwalk_fade_time",0.3)
        if now-started < fade then
            local wait=Defaults.CreateAttackNearestRule()
            wait.id="enemy_silver_edge_fade"
            wait.action={kind="wait",logical_id="silver_edge_fade",duration=fade-(now-started)}
            wait.target.team="self"
            return {wait}
        end
    end
    if call(unit,"HasModifier","modifier_item_silver_edge_windwalk")==true then
        -- The profile's target preference still applies. Allow approaching the
        -- chosen enemy so preserving the opener cannot strand a melee caster.
        local opener={}
        for key,value in pairs(attack) do opener[key]=value end
        opener.id="enemy_silver_edge_attack"
        opener.approach="allow_approach"
        return {opener}
    end
end

local function spells_recover_during(unit, seconds)
    for slot=0,(call(unit,"GetAbilityCount") or 0)-1 do
        local a=unit:GetAbilityByIndex(slot)
        if a and call(a,"IsNull")~=true and call(a,"GetAbilityName")~="skeleton_king_reincarnation"
            and call(a,"IsPassive")~=true and call(a,"IsHidden")~=true
            and call(a,"IsActivated")~=false and (call(a,"GetLevel") or 0)>0 then
            local charges=tonumber(call(a,"GetCurrentAbilityCharges"))
            if charges and charges>0 then return true end
            local remaining=tonumber(call(a,"GetCooldownTimeRemaining"))
            -- Missing native timing is not proof that self-silence is harmless.
            if not remaining or remaining<seconds then return true end
        end
    end
    return false
end

local function force_moves_away(unit, item, opponents)
    local origin, facing = call(unit,"GetAbsOrigin"), call(unit,"GetForwardVector")
    if not origin or not facing or type(opponents)~="table" then return false end
    local x,y=tonumber(facing.x),tonumber(facing.y)
    if not x or not y then return false end
    local length=math.sqrt(x*x+y*y)
    if length<=0 or length~=length then return false end
    local distance=special(item,"push_length",600)
    local destination={x=origin.x+x/length*distance,y=origin.y+y/length*distance}
    local before,after=math.huge,math.huge
    local team=call(unit,"GetTeamNumber")
    for _,opponent in pairs(opponents) do
        if call(opponent,"IsNull")~=true and call(opponent,"IsAlive")==true
            and call(opponent,"GetTeamNumber")~=team then
            local point=call(opponent,"GetAbsOrigin")
            if point then
                before=math.min(before,math.sqrt((point.x-origin.x)^2+(point.y-origin.y)^2))
                after=math.min(after,math.sqrt((point.x-destination.x)^2+(point.y-destination.y)^2))
            end
        end
    end
    -- Predict the native facing-based endpoint; never force a low-HP caster
    -- toward its nearest threat or another observed enemy behind it.
    return before<=600 and after>=400 and after>=before+200
end

function Items.CreateForUnit(unit, opponents)
    local buckets={{},{},{}}
    local seen={}
    local function add(item,name,priority,team,conditions,filters,suffix)
        local rule=Defaults.CreateAttackNearestRule()
        rule.id="enemy_"..name..(suffix or "")
        rule.action={kind="item",name=name,logical_id=name}
        rule.target.team=team or "self"
        rule.use_conditions=conditions or {}
        rule.target_filters=filters or {}
        buckets[priority][#buckets[priority]+1]=rule
        return rule
    end
    for slot=0,5 do
        local item=call(unit,"GetItemInSlot",slot)
        if call(item,"IsNull")==true then item=nil end
        local name=call(item,"GetAbilityName")
        local level=tonumber(call(item,"GetLevel")) or 0
        if item and call(item,"IsNull")~=true and name and not seen[name] and level>0
            and call(item,"IsPassive")~=true and call(item,"IsHidden")~=true
            and call(item,"IsActivated")~=false
            and not Behavior.HasFlag(Behavior.Read(item),DOTA_ABILITY_BEHAVIOR_PASSIVE) then
            seen[name]=true
            if name=="item_magic_wand" or name=="item_magic_stick" then
                if (tonumber(call(item,"GetCurrentCharges")) or 0)>0 then
                    add(item,name,1,"self",{hp(0.50)},nil,"_hp")
                    add(item,name,1,"self",{mana(0.25)},nil,"_mana")
                end
            elseif name=="item_satanic" then
                add(item,name,1,"self",{hp(0.40),nearby(600)})
            elseif name=="item_bloodstone" then
                add(item,name,1,"self",{hp(0.60),nearby()})
            elseif name=="item_guardian_greaves" or name=="item_mekansm" then
                -- Self is always inside the native heal radius. A self threshold
                -- avoids pretending the no-target action selects an ally.
                add(item,name,1,"self",{hp(0.60)})
            elseif name=="item_arcane_boots" then
                add(item,name,1,"self",{mana(0.50)})
            elseif name=="item_force_staff" then
                if force_moves_away(unit,item,opponents) then
                    add(item,name,1,"self",{hp(0.35),nearby(600)})
                end
            elseif name=="item_glimmer_cape" or name=="item_lotus_orb" then
                add(item,name,1,"self",{hp(0.60),nearby()})
            elseif defensive[name] then
                add(item,name,1,"self",{nearby()})
            elseif name=="item_cyclone" or name=="item_wind_waker" then
                add(item,name,1,"self",{hp(0.25),nearby()},nil,"_save")
                add(item,name,2,"enemy",{},nil,"_control")
            elseif controls[name] then
                add(item,name,2,"enemy")
            elseif name=="item_hurricane_pike" then
                -- Enemy mode separates caster/target along their connecting line;
                -- unlike friendly Force Staff this does not depend on facing.
                add(item,name,1,"enemy",{hp(0.60)},{{type="distance_lte",value=special(item,"cast_range_enemy",425)}})
            elseif name=="item_harpoon" then
                add(item,name,2,"enemy",{},{{type="distance_gte",value=300}})
            elseif name=="item_spirit_vessel" or name=="item_urn_of_shadows" then
                if (tonumber(call(item,"GetCurrentCharges")) or 0)>0 then
                    local heal=add(item,name,1,"ally",{},{{type="hp_pct_lte",value=0.50}},"_heal")
                    heal.target_priorities={{type="lowest_hp_pct"},{type="nearest"}}
                    add(item,name,2,"enemy",{},nil,"_damage")
                end
            elseif name=="item_shivas_guard" then
                add(item,name,2,"self",{nearby(special(item,"blast_radius",825))})
            elseif name=="item_mjollnir" then
                add(item,name,2,"self",{nearby(600)})
            elseif name=="item_radiance" then
                local rule=add(item,name,2,"self",{nearby(special(item,"aura_radius",650))})
                rule.action.desired_toggle_state=true
            elseif name=="item_armlet" then
                -- Native toggle state is checked by the adapter, so once on this
                -- rule yields to spells/attack. Never implement health toggling.
                local rule=add(item,name,2,"self",{{type="self_hp_pct_gte",value=0.50},nearby(600)})
                rule.action.desired_toggle_state=true
            elseif buffs[name] then
                add(item,name,2,"self",{nearby()})
            elseif name=="item_mask_of_madness" then
                -- Avoid self-silencing a spell that recovers during Berserk,
                -- including a charged spell that is usable despite its cooldown.
                if not spells_recover_during(unit,special(item,"berserk_duration",6)) then
                    add(item,name,2,"self",{nearby(600)})
                end
            elseif blinks[name] then
                local range=tonumber(call(item,"GetCastRange",call(unit,"GetAbsOrigin"),nil)) or 0
                range=math.min(range>0 and range or 1200,special(item,"blink_range",1200))
                add(item,name,3,"enemy",{},{{type="distance_gte",value=600},{type="distance_lte",value=range}})
            elseif name=="item_meteor_hammer" or name=="item_gungir" then
                add(item,name,2,"enemy")
            elseif name=="item_refresher" and cooling_spells(unit) then
                add(item,name,2,"self",{{type="self_mana_pct_gte",value=0.60},nearby()})
            end
        end
    end
    local result={}
    for _,bucket in ipairs(buckets) do for _,rule in ipairs(bucket) do result[#result+1]=rule end end
    return result
end
return Items
