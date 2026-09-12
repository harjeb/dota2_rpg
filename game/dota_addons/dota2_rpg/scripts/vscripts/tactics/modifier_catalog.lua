-- Observed/declared names, not guessed modifier_<ability> strings.
local C=require("tactics/condition_context")
local Movement=require("tactics/movement_contract")
local M={observed={},count=0}
local function name_string(value)
    return type(value)=="string" and #value>0 and #value<=128 and value:match("^[%w_]+$") and value or nil
end
local function details(ability,mod)
    local out={}
    local source=name_string(C.Call(ability,"GetAbilityName"))
    if source then out.ability=source end
    local debuff=C.Call(mod,"IsDebuff")
    if type(debuff)=="boolean" then out.debuff=debuff and 1 or 0 end
    return out
end
function M.Observe(unit)
    for _,mod in pairs(C.Call(unit,"FindAllModifiers") or {}) do
        local name=name_string(C.Call(mod,"GetName"))
        if name and (M.observed[name] or M.count<256) then
            if not M.observed[name] then M.observed[name]={}; M.count=M.count+1 end
            -- Store strings only: a modifier/ability handle can expire between snapshots.
            for key,value in pairs(details(C.Call(mod,"GetAbility"),mod)) do M.observed[name][key]=value end
        end
    end
end
function M.List(hero,ability)
    M.Observe(hero)
    local intrinsic=name_string(C.Call(ability,"GetIntrinsicModifierName"))
    local out,display={},{}
    local names={}
    for name in pairs(M.observed) do names[#names+1]=name end
    table.sort(names)
    -- The observed registry is already bounded to 256 names. Returning only
    -- its first 32 hid valid choices once raw modifier entry was removed.
    for index=1,#names do
        local name=names[index]; out[name]=1; display[name]={}
        for key,value in pairs(M.observed[name]) do display[name][key]=value end
    end
    -- These buffs have explicit native movement contracts and can be selected
    -- during the first preparation phase, before the hero has cast them.
    for abilityName,modifierName in pairs(Movement.presets) do
        local owned=C.Call(hero,"FindAbilityByName",abilityName)
        if owned then
            out[modifierName]=1; display[modifierName]=display[modifierName] or {}
            display[modifierName].ability=abilityName
        end
    end
    if intrinsic then
        out[intrinsic]=1; display[intrinsic]=display[intrinsic] or {}
        for key,value in pairs(details(ability,nil)) do display[intrinsic][key]=value end
    end
    return out,display
end
function M.Reset() M.observed={}; M.count=0 end
return M
