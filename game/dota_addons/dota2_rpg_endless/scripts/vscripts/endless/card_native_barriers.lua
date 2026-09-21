-- Native finite-damage barrier adapter. Extra capacity has the native barrier's
-- damage type and lifetime. Mana conversion, damage block and spell absorption
-- are not finite-damage barriers. Extensions can register their own grant reader.
local M={registry={}}
local function call(o,k,d,...) if o and o[k] then return o[k](o,...) end return d end
local function special(ability,keys)
    for _,key in ipairs(keys) do local n=call(ability,'GetSpecialValueFor',0,key);if n and n>0 then return n end end
    return 0
end
function M.Register(name,reader) assert(type(name)=='string' and type(reader)=='function');M.registry[name]=reader end
local function native(name,keys,kind)
    M.Register(name,function(mod,u)
        local ability=call(mod,'GetAbility',nil)
        return special(ability,keys),kind
    end)
end
native('modifier_abaddon_aphotic_shield',{'damage_absorb'},'all')
native('modifier_ember_spirit_flame_guard',{'absorb_amount'},'magic')
native('modifier_tinker_defense_matrix',{'damage_absorb'},'all')
M.Register('modifier_item_pipe_barrier',function(mod,u)
    local ability=call(mod,'GetAbility',nil)
    local keys=call(u,'IsHero',call(u,'IsRealHero',false)) and {'barrier_block'} or {'barrier_block_creep','barrier_block'}
    return special(ability,keys),'magic'
end)
native('modifier_item_pavise_shield',{'absorb_amount'},'physical')
-- Solar Crest shares modifier_item_pavise_shield. Its separate armor-addition
-- modifier is NOT a barrier and must never generate a second capacity grant.
M.Register('modifier_rpg_opening_shield',function(mod) return tonumber(mod.remaining) or 0,'all' end)
local function snapshot(mod,u)
    local name=call(mod,'GetName','')
    local reader=M.registry[name];if not reader then return end
    local amount,kind=reader(mod,u)
    if not amount or amount<=0 then return end
    return amount,kind or 'all'
end
function M.Refresh(s,u,amp)
    local r=s.unit_state[u];if not r then return end
    r.native_barriers=r.native_barriers or {}
    local seen={}
    for _,mod in pairs(call(u,'FindAllModifiers',{}) or {}) do
        local amount,kind=snapshot(mod,u)
        if amount then
            seen[mod]=true
            local remaining=call(mod,'GetRemainingTime',-1)
            local expires=remaining==-1 and math.huge or s.time+remaining
            local created=call(mod,'GetCreationTime',0)
            local old=r.native_barriers[mod]
            -- Refresh extends native expiry; float jitter in GetRemainingTime must
            -- never manufacture a new grant. Amp changes do not refill old shields.
            if not old or old.created~=created or expires>old.expires+.05 then
                r.native_barriers[mod]={amount=amount*math.max(0,amp)/100,base=amount,kind=kind,expires=expires,created=created}
            end
        end
    end
    for mod in pairs(r.native_barriers) do if not seen[mod] then r.native_barriers[mod]=nil end end
end
function M.Has(s,u)
    local r=s.unit_state[u]
    if not r then return false end
    for mod,entry in pairs(r.native_barriers or {}) do
        if entry.expires>s.time and not call(mod,'IsNull',false) then return true end
    end
    return false
end
function M.Absorb(s,u,amount,kind,scope)
    local r=s.unit_state[u]
    local entries={}
    for _,entry in pairs(r and r.native_barriers or {}) do entries[#entries+1]=entry end
    table.sort(entries,function(a,b) return a.expires<b.expires end)
    for _,entry in ipairs(entries) do
        if entry.expires>s.time and entry.amount>0 and (not scope or entry.kind==scope)
            and (entry.kind=='all' or entry.kind=='magic' and kind==DAMAGE_TYPE_MAGICAL or entry.kind=='physical' and kind==DAMAGE_TYPE_PHYSICAL) then
            local n=math.min(amount,entry.amount);entry.amount=entry.amount-n;amount=amount-n
        end
    end
    return amount
end
return M
