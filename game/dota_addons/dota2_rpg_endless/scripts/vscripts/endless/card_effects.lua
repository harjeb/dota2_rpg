local Effects = {definitions=require('endless/card_definitions')}
local MODIFIER='modifier_endless_card_stats'
local PREP='modifier_endless_card_prepare'
local World=require('endless/card_world_effects')
local Barriers=require('endless/card_native_barriers')
local worldContext
Effects.unsupported={}
Effects.RegisterBarrier=Barriers.Register
if LinkLuaModifier then
    LinkLuaModifier(MODIFIER,'modifiers/'..MODIFIER,LUA_MODIFIER_MOTION_NONE)
    LinkLuaModifier(PREP,'modifiers/'..MODIFIER,LUA_MODIFIER_MOTION_NONE)
    LinkLuaModifier('modifier_endless_card_control','modifiers/modifier_endless_card_control',LUA_MODIFIER_MOTION_NONE)
    LinkLuaModifier('modifier_endless_card_echo','modifiers/modifier_endless_card_control',LUA_MODIFIER_MOTION_NONE)
    LinkLuaModifier('modifier_endless_card_source','modifiers/modifier_endless_card_control',LUA_MODIFIER_MOTION_NONE)
end
local function valid(u) return u~=nil and (not u.IsNull or not u:IsNull()) end
local function alive(u) return valid(u) and (not u.IsAlive or u:IsAlive()) end
local function call(u,name,default,...) if valid(u) and u[name] then return u[name](u,...) end return default end
local function clock(game) return GameRules and GameRules.GetGameTime and GameRules:GetGameTime() or tonumber(game.time) or 0 end
local function pick(card,values) return values[card.load] end
local function clamp(n,a,b) return math.max(a,math.min(b,n)) end
local function legal(game,u)
    return valid(u) and not u.endlessCardSource and u~=game.placeholderHero and u~=game.commander
        and not call(u,'HasModifier',false,'modifier_rpg_prepare_bench')
        and not call(u,'HasModifier',false,'modifier_rpg_commander_disarmed')
        and not call(u,'IsOther',false) and not call(u,'IsBuilding',false)
end
local function body(game,s,u)
    if not legal(game,u) or not alive(u) or not call(u,'IsRealHero',false) or call(u,'IsIllusion',false) or u.endlessRebirthForm then return false end
    for _,hero in pairs(((game.battleManager or {}).teamHeroes or {})[s.team] or {}) do if hero==u then return true end end
    return false
end
local function units(game,s)
    local result,seen={},{}
    local function add(u) if legal(game,u) and not seen[u] then seen[u]=true;result[#result+1]=u end end
    if FindUnitsInRadius then
        local flags=(DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES or 0)+(DOTA_UNIT_TARGET_FLAG_INVULNERABLE or 0)+(DOTA_UNIT_TARGET_FLAG_OUT_OF_WORLD or 0)
        for _,u in pairs(FindUnitsInRadius(s.team,Vector(0,0,0),nil,FIND_UNITS_EVERYWHERE or -1,DOTA_UNIT_TARGET_TEAM_BOTH,
            DOTA_UNIT_TARGET_HERO+DOTA_UNIT_TARGET_BASIC,flags,FIND_ANY_ORDER,false) or {}) do add(u) end
    end
    for _,roster in pairs((game.battleManager or {}).teamHeroes or {}) do for _,u in pairs(roster) do add(u) end end
    for _,u in pairs(game.spawnedSummons or {}) do add(u) end
    for u in pairs(s.spawned or {}) do add(u) end
    return result
end
-- Native spells on temporary card units can create their own summons. Only
-- ancestry reaching a tracked card parent grants this temporary lifetime.
local function discoverDescendants(game,s)
    local candidates,thinkers=units(game,s),{}
    -- Native Fireball and similar hazards are OTHER units, outside combat queries.
    if Entities and Entities.FindAllByClassname then
        for _,u in pairs(Entities:FindAllByClassname('npc_dota_thinker') or {}) do
            if valid(u) and not u.endlessCardSource then candidates[#candidates+1]=u;thinkers[u]=true end
        end
    end
    for _,u in ipairs(candidates) do
        if not s.spawned[u] and call(u,'GetTeamNumber',nil)==s.team and not body(game,s,u) then
            local seen={[u]=true};local queue={{unit=u,depth=0}};local index=1;local parent
            while index<=#queue and index<=32 and not parent do
                local node=queue[index];index=index+1
                if node.depth<8 then
                    for _,method in ipairs({'GetOwnerEntity','GetOwner'}) do
                        local owner=call(node.unit,method,nil)
                        if owner and not seen[owner] then
                            seen[owner]=true
                            if s.spawned[owner] then parent=s.spawned[owner];break end
                            if valid(owner) and #queue<32 then queue[#queue+1]={unit=owner,depth=node.depth+1} end
                        end
                    end
                end
            end
            if parent then
                u.endlessCardSummon=true
                s.spawned[u]={kind='descendant',expires=parent.expires,
                    passive=thinkers[u] or call(u,'IsOther',false) or call(u,'GetAttackCapability',1)==0,
                    native_ai=call(u,'GetUnitName',''):find('npc_dota_neutral_',1,true)==1}
            end
        end
    end
end
local function spawnedSnapshot(s)
    local result={}
    for u,entry in pairs(s.spawned) do result[#result+1]={unit=u,entry=entry} end
    return result
end
local function each(game,s,friendly,fn,living)
    for _,u in ipairs(units(game,s)) do
        if (u:GetTeamNumber()==s.team)==friendly and (living==false or alive(u)) then fn(u) end
    end
end
local function record(s,u)
    s.unit_state[u]=s.unit_state[u] or {shields={},timed={},crit_records={}}
    return s.unit_state[u]
end
local function active(s,id,t)
    local c=s.by_id[id]
    if c and (Effects.definitions[id].type~='consumable' or (c.active_until and t<c.active_until)) then return c end
end
local function value(s,id,values,t)
    local c=active(s,id,t or s.time)
    return c and pick(c,values) or 0
end
local function resolve(game,s,hero)
    if type(hero)~='string' then return hero end
    for _,u in pairs(((game.battleManager or {}).teamHeroes or {})[s.team] or {}) do if call(u,'GetUnitName','')==hero then return u end end
end
local function setstats(game,s,u,stats,name)
    if not u.AddNewModifier then return end
    local m=call(u,'FindModifierByName',nil,name)
    if not m then m=u:AddNewModifier(nil,nil,name,{}) end
    if m and m.SetStats then m.game=game;m:SetStats(stats) end
    if name==MODIFIER then s.units[u]=true end
end
local prepareKeys={health=true,health_pct=true,mana=true,mana_pct=true}
function Effects.ClearPrepare(game)
    local p=game.endlessCardPrepared
    if p then for u in pairs(p.units) do if valid(u) and u.RemoveModifierByName then
        local hp,maxhp,mp,maxmp=call(u,'GetHealth',0),call(u,'GetMaxHealth',0),call(u,'GetMana',0),call(u,'GetMaxMana',0)
        local modifier=call(u,'FindModifierByName',nil,PREP)
        if modifier and modifier.SetStats then modifier:SetStats({}) end
        u:RemoveModifierByName(PREP)
        if u.CalculateStatBonus then u:CalculateStatBonus(true) end
        if u.SetHealth and hp>0 and maxhp>0 then u:SetHealth(math.max(1,u:GetMaxHealth()*hp/maxhp)) end
        if u.SetMana and maxmp>0 then u:SetMana(call(u,'GetMaxMana',0)*mp/maxmp) end
    end end end
    game.endlessCardPrepared=nil
end
-- Called after setup loadout/roster changes; Start freezes this result.
function Effects.Prepare(game,snapshot)
    if game.endlessCardCombat then return end
    Effects.ClearPrepare(game)
    local p={units={},stats={},team=game.endlessCardTeam or DOTA_TEAM_GOODGUYS or 2,field_scale=1,base_health={},base_attack={}}
    local seen,fields,carriers,resonance={},0,{},nil
    local sums={health=0,health_pct=0,mana=0,mana_pct=0}
    for _,entry in ipairs(snapshot or {}) do
        local def,l=Effects.definitions[entry.id],tonumber(entry.load)
        if def and l and l>=1 and l<=3 and l==math.floor(l) and not seen[entry.id] then
            seen[entry.id]=true
            if def.type=='field' then fields=fields+1;local u=resolve(game,p,entry.hero);if valid(u) then carriers[u]=true end end
            if entry.id=='E-f3' then resonance=l end
            for _,effect in ipairs(def.effects) do if prepareKeys[effect.stat] then sums[effect.stat]=sums[effect.stat]+effect.values[l] end end
        end
    end
    if resonance==3 then
        local primary=0
        for u in pairs(carriers) do
            local attr=call(u,'GetPrimaryAttribute',-1)
            local str,agi,int=call(u,'GetStrength',0),call(u,'GetAgility',0),call(u,'GetIntellect',0)
            primary=primary+(attr==0 and str or attr==1 and agi or attr==2 and int or math.max(str,agi,int))
        end
        p.field_scale=1+math.min(0.5,primary*.001)
    end
    p.sums=sums
    for _,u in ipairs(units(game,p)) do
        if u:GetTeamNumber()==p.team and alive(u) and not call(u,'IsIllusion',false) and not u.endlessRebirthForm then
            local hp,mp=call(u,'GetMaxHealth',0),call(u,'GetMaxMana',0)
            p.base_health[u]=hp;p.base_attack[u]=call(u,'GetAverageTrueAttackDamage',0,nil)
            local stats={health=(hp+sums.health)*(1+sums.health_pct/100)-hp,mana=(mp+sums.mana)*(1+sums.mana_pct/100)-mp}
            if resonance and body(game,p,u) then stats.all_attributes=({6,10,20})[resonance]*math.min(5,fields) end
            p.stats[u]=stats;p.units[u]=true
            setstats(game,p,u,stats,PREP)
        end
    end
    game.endlessCardPrepared=p
    return p
end
local function source(game,s)
    if alive(s.source) then return s.source end
    if CreateUnitByName then
        s.source=CreateUnitByName('npc_dota_thinker',Vector(0,0,0),false,nil,nil,s.team)
        if valid(s.source) then
            s.source.endlessCardSource=true
            if s.source.AddNewModifier then s.source:AddNewModifier(nil,nil,'modifier_endless_card_source',{}) end
        end
    end
    return s.source
end
-- A hidden team thinker owns card damage, never the equipment carrier. The synchronous
-- context distinguishes it from hero spells and prevents card damage feeding itself.
local function damage(game,s,victim,amount,kind,tag,attacker,flags)
    if amount<=0 or not alive(victim) or not ApplyDamage then return 0 end
    attacker=attacker or source(game,s)
    if not valid(attacker) then return 0 end
    local previous=s.damage_context
    s.damage_context={tag=tag or 'card_effect',attacker=attacker,victim=victim}
    local noamp=(DOTA_DAMAGE_FLAG_NO_SPELL_AMPLIFICATION or 0)+(DOTA_DAMAGE_FLAG_NO_SPELL_LIFESTEAL or 0)
    local ok,result=pcall(ApplyDamage,{victim=victim,attacker=attacker,damage=amount,damage_type=kind,
        damage_flags=noamp+(flags or 0)})
    s.damage_context=previous
    if not ok then error(result) end
    return tonumber(result) or 0
end
local function heal(u,n)
    if n>0 and alive(u) and u.Heal then u:Heal(n,nil) end
end
local function mana(u,pct)
    if u.GiveMana then u:GiveMana(call(u,'GetMaxMana',0)*pct/100) end
end
local function teamheal(game,s,pct) each(game,s,true,function(u) heal(u,u:GetMaxHealth()*pct/100) end) end
local function statsOf(u) local m=call(u,'FindModifierByName',nil,MODIFIER);return m and m.stats or {} end
-- Shield grants use live lifetimes even for events between combat ticks.
-- Only the receiving team's cards amplify a grant, exactly once.
local function shieldAmp(game,s,u)
    if u:GetTeamNumber()~=s.team then return 0 end
    local amount,t=0,clock(game)
    for _,id in ipairs({'D-g5','D-c2'}) do
        local c=active(s,id,t)
        if c then for _,effect in ipairs(Effects.definitions[id].effects) do
            if effect.stat=='shield_amp' then amount=amount+effect.values[c.load] end
        end end
    end
    return amount
end
local function shield(game,s,u,id,amount,expires,stack,cap)
    local r=record(s,u)
    amount=amount*(1+shieldAmp(game,s,u)/100)
    local old=r.shields[id]
    if stack and old and old.expires>s.time then amount=amount+old.amount end
    r.shields[id]={amount=math.min(cap or math.huge,amount),expires=expires}
end
local function teamshield(game,s,id,pct,duration)
    each(game,s,true,function(u) shield(game,s,u,id,u:GetMaxHealth()*pct/100,s.time+duration) end)
end
local function control(game,s,u,kind,duration)
    if not alive(u) or not u.AddNewModifier then return end
    duration=duration*(1-clamp(call(u,'GetStatusResistance',0),0,1))
    u:AddNewModifier(source(game,s),nil,'modifier_endless_card_control',{duration=duration,kind=kind})
end
local function burst(game,s,amount,kind,pct,tag)
    local total=0
    each(game,s,false,function(u) total=total+damage(game,s,u,pct and u:GetMaxHealth()*amount/100 or amount,kind,tag) end)
    return total
end
local function schedule(s,delay,fn) s.jobs[#s.jobs+1]={at=s.time+delay,run=fn} end
local function timed(s,u,id,stats,duration) record(s,u).timed[id]={stats=stats,expires=s.time+duration} end
local function summonDogs(game,s,c)
    if not CreateUnitByName then return end
    local count=0
    for u,entry in pairs(s.spawned) do if alive(u) and entry.kind=='hound' then count=count+1 end end
    local n=math.min(4-count,pick(c,{2,3,4}))
    if n<=0 then return end
    local ratio=pick(c,{.3,.4,.5})
    for i=1,n do
        local pos=s.center or Vector(0,0,0)
        if RandomVector then pos=pos+RandomVector(100) end
        local u=CreateUnitByName('npc_dota_neutral_fel_beast',pos,true,nil,nil,s.team)
        if valid(u) then
            u.endlessCardSummon=true
            for slot=0,23 do local a=call(u,'GetAbilityByIndex',nil,slot);if a and u.RemoveAbility then u:RemoveAbility(a:GetAbilityName()) end end
            local hp=math.max(1,s.mean_health*ratio);local atk=s.mean_attack*ratio
            if u.SetBaseMaxHealth then u:SetBaseMaxHealth(hp) end
            if u.SetMaxHealth then u:SetMaxHealth(hp) end
            if u.SetHealth then u:SetHealth(hp) end
            if u.SetBaseDamageMin then u:SetBaseDamageMin(atk);u:SetBaseDamageMax(atk) end
            if u.SetBaseAttackTime then u:SetBaseAttackTime(1.2) end
            if u.SetBaseMoveSpeed then u:SetBaseMoveSpeed(350) end
            if u.SetPhysicalArmorBaseValue then u:SetPhysicalArmorBaseValue(3) end
            if u.SetBaseMagicalResistanceValue then u:SetBaseMagicalResistanceValue(25) end
            if FindClearSpaceForUnit then FindClearSpaceForUnit(u,pos,true) end
            s.spawned[u]={expires=s.time+15,kind='hound'}
        end
    end
end
worldContext={each=each,body=body,units=units,record=record,damage=damage,heal=heal,timed=timed,valid=valid,alive=alive,call=call,source=source}
local function fire(game,s,c,event)
    World.Fire(worldContext,game,s,c)
    local id,l=c.id,c.load
    local function v(a) return a[l] end
    if id=='E-c5' then each(game,s,true,function(u) mana(u,v({20,30,45})) end)
    elseif id=='E-c6' then burst(game,s,v({10,16,23}),DAMAGE_TYPE_MAGICAL,true)
    elseif id=='C-c4' then
        local n=v({100,170,260});burst(game,s,n,DAMAGE_TYPE_PHYSICAL)
        for i=1,2 do schedule(s,i,function() burst(game,s,n,DAMAGE_TYPE_PHYSICAL) end) end
    elseif id=='C-c6' then teamheal(game,s,v({15,25,35}))
    elseif id=='C-c7' then teamheal(game,s,v({12,20,30}))
    elseif id=='D-c2' then teamshield(game,s,id,v({8,12,18}),10)
    elseif id=='D-c3' then teamshield(game,s,id,v({18,28,40}),10)
    elseif id=='D-c4' then
        each(game,s,true,function(u)
            if body(game,s,u) and u:GetHealth()/u:GetMaxHealth()<.3 then timed(s,u,id,{incoming_damage=-v({20,30,40})},4) end
        end)
        teamheal(game,s,v({20,30,45}))
    elseif id=='D-c5' then each(game,s,true,function(u) if u.Purge then u:Purge(false,true,false,true,true) end end)
    elseif id=='D-c6' then
        burst(game,s,v({200,350,550}),DAMAGE_TYPE_MAGICAL)
        each(game,s,false,function(u) control(game,s,u,'stun',v({.8,1.2,1.6})) end)
    elseif id=='D-c7' then teamheal(game,s,v({10,16,24}));teamshield(game,s,id,v({12,18,26}),10)
    elseif id=='A-c1' then s.mark=event.attacker;s.mark_bonus=v({10,18,28})
    elseif id=='A-c2' then teamheal(game,s,v({20,30,45}));each(game,s,true,function(u) mana(u,v({15,25,35})) end)
    elseif id=='A-c3' then
        local pool=burst(game,s,v({4,6,9}),DAMAGE_TYPE_MAGICAL,true)*v({.4,.6,.8})
        local heroes={};each(game,s,true,function(u) if body(game,s,u) then heroes[#heroes+1]=u end end)
        for _,u in ipairs(heroes) do heal(u,math.min(pool/math.max(1,#heroes),u:GetMaxHealth()*v({.15,.25,.4}))) end
    elseif id=='A-c5' then burst(game,s,v({200,350,550}),DAMAGE_TYPE_MAGICAL)
    elseif id=='A-c6' then each(game,s,true,function(u)
        if call(u,'GetMaxMana',0)>0 then
            -- Direct nonlethal health cost is not damage, does not proc cards or shields.
            if u.SetHealth then u:SetHealth(math.max(1,u:GetHealth()*.92)) end
            mana(u,v({25,40,60}))
        end
    end)
    elseif id=='W-c3' then summonDogs(game,s,c)
    elseif id=='W-c6' then each(game,s,true,function(u) record(s,u).guaranteed={count=v({3,4,5}),multiplier=v({180,230,300}),expires=s.time+10} end)
    elseif id=='W-c7' then teamheal(game,s,v({15,25,35})) end
end
local function trigger(game,s,c,event)
    if not c.remaining or c.remaining<=0 or s.time<c.next_trigger then return false end
    local d=Effects.definitions[c.id]
    local tr=c.trigger or d.trigger
    c.remaining=c.remaining-1
    -- Reserve cooldown before damage/healing dispatch can synchronously reenter events.
    if tr.once then c.next_trigger=math.huge
    elseif tr.type=='time' then
        c.next_trigger=c.next_trigger+(math.floor((s.time-c.next_trigger)/tr.interval)+1)*tr.interval
    else c.next_trigger=s.time+(tr.cooldown or 12) end
    fire(game,s,c,event or {})
    c.active_until=s.time+(d.duration or 0)
    c.pulse_at=s.time+1
    return true
end
local function dispatch(game,s,name,event)
    for _,c in ipairs(s.cards) do local d=Effects.definitions[c.id]
        if c.trigger and c.trigger.type==name then trigger(game,s,c,event) end
    end
end
local function stateTrigger(game,s,tr)
    if tr.type=='team_health_below' then
        local current,maximum=0,0
        each(game,s,true,function(u)
            if body(game,s,u) then
                current=current+call(u,'GetHealth',0);maximum=maximum+call(u,'GetMaxHealth',0)
            end
        end)
        return maximum>0 and current/maximum<tr.threshold
    end
    if tr.type=='team_mana_below' then
        local current,maximum=0,0
        each(game,s,true,function(u) if body(game,s,u) then current=current+call(u,'GetMana',0);maximum=maximum+call(u,'GetMaxMana',0) end end)
        return maximum>0 and current/maximum<tr.threshold
    end
    local match=false
    each(game,s,true,function(u)
        if body(game,s,u) then
            if tr.type=='hero_health_below' then match=match or u:GetHealth()/math.max(1,u:GetMaxHealth())<tr.threshold
            elseif tr.type=='hero_mana_below' then local max=call(u,'GetMaxMana',0);match=match or max>0 and call(u,'GetMana',0)/max<tr.threshold
            elseif tr.type=='controlled' then match=match or call(u,'IsStunned',false) or call(u,'IsFeared',false) or call(u,'IsTaunted',false) end
        end
    end)
    return match
end
local function add(stats,key,n)
    if key=='evasion' then
        -- Multiple evasion grants use independent native avoidance rolls.
        stats[key]=100-(100-(stats[key] or 0))*(100-n)/100
    else stats[key]=(stats[key] or 0)+n end
end
local function totals(game,s,u)
    local friendly=u:GetTeamNumber()==s.team
    local stats={}
    for _,c in ipairs(s.cards) do
        local d=Effects.definitions[c.id]
        if (d.target=='friendly')==friendly and active(s,c.id,s.time) then
            local scale=d.type=='field' and s.field_scale or 1
            for _,e in ipairs(d.effects) do
                if not prepareKeys[e.stat] and e.stat~='field_heal_amp' then
                    local amount=e.values[c.load]*scale
                    -- Supply Line belongs to the field layer. It cannot amplify
                    -- a hero's own healing spell, lifesteal or native regeneration.
                    if d.type=='field' and (e.stat=='health_regen' or e.stat=='health_regen_pct') then
                        amount=amount*(1+value(s,'C-f4',{0,0,15})*s.field_scale/100)
                    end
                    add(stats,e.stat,amount)
                end
            end
        end
    end
    local r=record(s,u)
    for id,buff in pairs(r.timed) do
        if s.time>=buff.expires then r.timed[id]=nil else for key,n in pairs(buff.stats) do add(stats,key,n) end end
    end
    if friendly then
        add(stats,'spell_amp',value(s,'E-g1',{.8,1.6,2.5})*math.min(10,math.floor((s.time-s.started_at)/10)))
        if s.time-s.started_at>=30 then add(stats,'cooldown',value(s,'E-g2',{10,18,25})) end
        add(stats,'armor',value(s,'C-g4',{1,2,3})*math.min(5,s.friendly_deaths))
        add(stats,'attack_damage',value(s,'A-g3',{3,5,8})*math.min(8,s.deaths))
        add(stats,'base_damage_pct',value(s,'W-g4',{3,5,8})*math.min(5,s.friendly_deaths))
        local stacks=0
        for _,expiry in ipairs(s.enlightenment) do if expiry>s.time then stacks=stacks+1 end end
        add(stats,'intelligence',stacks*value(s,'E-g5',{1,2,3}))
        if not (game.endlessCardPrepared and game.endlessCardPrepared.units[u]) and not call(u,'IsIllusion',false) and not u.endlessRebirthForm then
            if not r.prepared then
                local sums=s.prepare_sums
                local hp,mp=call(u,'GetMaxHealth',0),call(u,'GetMaxMana',0)
                r.prepared={health=(hp+sums.health)*(1+sums.health_pct/100)-hp,mana=(mp+sums.mana)*(1+sums.mana_pct/100)-mp}
            end
            add(stats,'health',r.prepared.health);add(stats,'mana',r.prepared.mana)
        end
    else
        add(stats,'strength',-(r.lost_strength or 0));add(stats,'agility',-(r.lost_agility or 0));add(stats,'intelligence',-(r.lost_intelligence or 0))
        add(stats,'health',-(r.lost_health or 0))
    end
    stats.heal_amp=math.max(-80,stats.heal_amp or 0)
    return stats
end
function Effects.Refresh(game)
    local s=game.endlessCardCombat;if not s then return end
    local present={}
    for _,u in ipairs(units(game,s)) do
        present[u]=true
        -- Every legal unit observes events even when it currently has no numeric stats.
        setstats(game,s,u,totals(game,s,u),MODIFIER)
        Barriers.Refresh(s,u,shieldAmp(game,s,u))
        local r=record(s,u)
        if alive(u) then r.dead=false end
        r.start_health=r.start_health or call(u,'GetMaxHealth',0)
    end
    for u in pairs(s.units) do if not present[u] then
        if valid(u) and u.RemoveModifierByName then u:RemoveModifierByName(MODIFIER) end
        s.units[u]=nil
    end end
end
local function attrDrain(game,s,u,str,agi,int,hp)
    local r=record(s,u)
    str=math.min(str,math.max(0,call(u,'GetStrength',0)))
    agi=math.min(agi,math.max(0,call(u,'GetAgility',0)))
    int=math.min(int,math.max(0,call(u,'GetIntellect',0)))
    local hpLoss=math.min(hp,math.max(0,u:GetMaxHealth()))
    hp=math.min(hp,math.max(0,u:GetMaxHealth()-1))
    -- Record before recalc: engine clamps current health when maximum health falls.
    -- Restore the original current health where possible and account for the clamp,
    -- so explicit HPLOSS is applied exactly once, and can kill at the numerical floor.
    local before,maximum=u:GetHealth(),u:GetMaxHealth()
    r.lost_strength=(r.lost_strength or 0)+str;r.lost_agility=(r.lost_agility or 0)+agi
    r.lost_intelligence=(r.lost_intelligence or 0)+int;r.lost_health=(r.lost_health or 0)+hp
    setstats(game,s,u,totals(game,s,u),MODIFIER)
    local loss=hpLoss+math.max(0,maximum-hp-u:GetMaxHealth())
    -- Dota strength grants 22 health; GetMaxHealth after CalculateStatBonus is the authority.
    local intended=before-loss
    local remaining=math.max(0,u:GetHealth()-intended)
    if remaining>0 then damage(game,s,u,remaining,DAMAGE_TYPE_PURE,'card_field',nil,DOTA_DAMAGE_FLAG_HPLOSS or 0) end
end
local function periodic(game,s,c)
    World.Periodic(worldContext,game,s,c)
    local id=c.id
    local n=function(a) return pick(c,a)*s.field_scale end
    if id=='W-f1' then burst(game,s,n({10,16,26}),DAMAGE_TYPE_MAGICAL,false,'card_field')
    elseif id=='D-f2' then burst(game,s,n({50,80,120}),DAMAGE_TYPE_MAGICAL,false,'card_field')
    elseif id=='D-f4' then burst(game,s,n({40,75,102}),DAMAGE_TYPE_PURE,false,'card_field');each(game,s,false,function(u) control(game,s,u,'stun',.5*s.field_scale) end)
    elseif id=='A-f2' then each(game,s,false,function(u) control(game,s,u,'fear',n({.5,.8,1.2}));attrDrain(game,s,u,n({2,4,6}),0,0,0) end)
    elseif id=='A-f3' then each(game,s,false,function(u) control(game,s,u,'silence',s.field_scale);attrDrain(game,s,u,0,0,0,n({20,30,40})) end)
    elseif id=='W-f3' then each(game,s,false,function(u) local a=n({.5,.8,1});attrDrain(game,s,u,a,a,a,0) end)
    elseif id=='W-f4' then each(game,s,false,function(u) timed(s,u,id,{attack_damage_pct=-n({15,22,30})},2*s.field_scale) end)
    elseif id=='E-c3' then burst(game,s,pick(c,{1.5,2.5,4.5}),DAMAGE_TYPE_MAGICAL,true)
    elseif id=='A-c7' then burst(game,s,pick(c,{25,45,70}),DAMAGE_TYPE_MAGICAL) end
end
local periods={['E-g7']=1,['D-f3']=3,['W-f2']=2,['W-f1']=1,['D-f2']=1,['D-f4']=5,['A-f2']=5,['A-f3']=3,['W-f3']=1,['W-f4']=6}
function Effects.Start(game,snapshot)
    Effects.Stop(game)
    local p=Effects.Prepare(game,snapshot)
    local t=clock(game)
    local s={cards={},by_id={},units={},unit_state={},spawned={},forms={},jobs={},started_at=t,time=t,team=p.team,
        field_scale=p.field_scale,prepare_sums=p.sums,enlightenment={},attack_inputs={},friendly_deaths=0,deaths=0,mean_health=0,mean_attack=0}
    local count,x,y,z=0,0,0,0
    for u in pairs(p.units) do if body(game,s,u) then
        count=count+1;s.mean_health=s.mean_health+p.base_health[u];s.mean_attack=s.mean_attack+p.base_attack[u]
        local pos=call(u,'GetAbsOrigin',nil);if pos then x=x+pos.x;y=y+pos.y;z=z+pos.z end
    end end
    s.mean_health=s.mean_health/math.max(1,count);s.mean_attack=s.mean_attack/math.max(1,count)
    s.center=Vector(x/math.max(1,count),y/math.max(1,count),z/math.max(1,count))
    for _,entry in ipairs(snapshot or {}) do
        local d,l=Effects.definitions[entry.id],tonumber(entry.load)
        if d and l and l>=1 and l<=3 and l==math.floor(l) and not s.by_id[entry.id] then
            local tr=d.trigger
            if tr and entry.id:sub(1,1)~='E' and type(entry.trigger)=='table' then
                local custom=entry.trigger
                if custom.type=='time' and tonumber(custom.first) and tonumber(custom.interval) and custom.first>=0 and custom.interval>=12 then
                    tr={type='time',first=custom.first,interval=custom.interval,cooldown=12}
                elseif (custom.type=='hero_health_below' or custom.type=='hero_mana_below') and tonumber(custom.threshold) and custom.threshold>0 and custom.threshold<1 then
                    tr={type=custom.type,threshold=custom.threshold,cooldown=12}
                end
            end
            local c={id=entry.id,load=l,hero=resolve(game,s,entry.hero),remaining=d.type=='consumable' and l or nil,trigger=tr,
                next_trigger=tr and t+(tr.first or 0) or nil,pulse_at=periods[entry.id] and t+periods[entry.id] or nil}
            if entry.id=='D-f1' then c.period=({3,2,1})[l];c.pulse_at=t+c.period end
            s.cards[#s.cards+1]=c;s.by_id[c.id]=c
        end
    end
    game.endlessCardCombat=s
    Effects.Refresh(game)
    Effects.Tick(game)
    return s
end
function Effects.Stop(game)
    local s=game.endlessCardCombat
    game.endlessCardCombat=nil
    if s then
        discoverDescendants(game,s)
        World.Stop(s)
        for u in pairs(s.units) do if valid(u) and u.RemoveModifierByName then u:RemoveModifierByName(MODIFIER);u:RemoveModifierByName('modifier_endless_card_control') end end
        local cleanup=spawnedSnapshot(s)
        for _,item in ipairs(cleanup) do if valid(item.unit) then item.unit.endlessCardCleanup=true end end
        for _,item in ipairs(cleanup) do
            local u=item.unit
            if valid(u) then if UTIL_Remove then UTIL_Remove(u) elseif u.ForceKill then u:ForceKill(false) end end
        end
        if valid(s.source) and UTIL_Remove then UTIL_Remove(s.source) end
    end
    Effects.ClearPrepare(game)
end
function Effects.Tick(game)
    local s=game.endlessCardCombat;if not s then return end
    s.time=clock(game)
    for _,u in ipairs(units(game,s)) do Barriers.Refresh(s,u,shieldAmp(game,s,u)) end
    for _,c in ipairs(s.cards) do
        local d=Effects.definitions[c.id]
        if c.trigger and c.remaining>0 and s.time>=c.next_trigger then
            if c.trigger.type=='time' or stateTrigger(game,s,c.trigger) then trigger(game,s,c) end
        end
        local period=c.period or periods[c.id]
        if period and s.time>=c.pulse_at then
            -- A stalled server never fires a damaging backlog in one frame.
            periodic(game,s,c);c.pulse_at=c.pulse_at+(math.floor((s.time-c.pulse_at)/period)+1)*period
        elseif (c.id=='E-c3' or c.id=='A-c7') and c.active_until and c.pulse_at<=c.active_until and s.time<=c.active_until and s.time>=c.pulse_at then
            periodic(game,s,c);c.pulse_at=c.pulse_at+math.floor(s.time-c.pulse_at)+1
        end
    end
    World.Tick(worldContext,game,s)
    local pending=s.jobs;s.jobs={}
    for _,job in ipairs(pending) do if s.time>=job.at then job.run() else s.jobs[#s.jobs+1]=job end end
    discoverDescendants(game,s)
    local spawned=spawnedSnapshot(s)
    -- Mark the entire expiry batch before removal can dispatch nested deaths.
    for _,item in ipairs(spawned) do
        if valid(item.unit) and (not alive(item.unit) or s.time>=item.entry.expires) then item.unit.endlessCardCleanup=true end
    end
    for _,item in ipairs(spawned) do
        local u,entry=item.unit,item.entry
        if not valid(u) or not alive(u) then
            s.spawned[u]=nil;s.forms[u]=nil
            if valid(u) then u.endlessCardCleanup=true;if UTIL_Remove then UTIL_Remove(u) end end
        elseif s.time>=entry.expires then
            u.endlessCardCleanup=true;s.spawned[u]=nil;s.forms[u]=nil
            if UTIL_Remove then UTIL_Remove(u) elseif u.ForceKill then u:ForceKill(false) end
        elseif entry.kind~='soul' and entry.kind~='echo' and entry.kind~='den' and not entry.native_ai and not entry.passive and u.MoveToTargetToAttack then
            local nearest,distance=nil,math.huge
            local origin=call(u,'GetAbsOrigin',nil)
            each(game,s,false,function(enemy)
                local pos=call(enemy,'GetAbsOrigin',nil)
                if origin and pos then local d=(pos.x-origin.x)^2+(pos.y-origin.y)^2;if d<distance then nearest=enemy;distance=d end end
            end)
            if nearest then u:MoveToTargetToAttack(nearest) end
        end
    end
    Effects.Refresh(game)
end
-- Attack damage filter runs before armor. Change only an ordinary physical attack,
-- scaling by the ratio of native positive-armor multipliers without editing armor.
function Effects.DamageFilter(game,keys)
    local s=game.endlessCardCombat;if not s or s.damage_context then return true end
    if not EntIndexToHScript then return true end
    local attacker=keys.entindex_attacker_const and EntIndexToHScript(keys.entindex_attacker_const)
    local victim=keys.entindex_victim_const and EntIndexToHScript(keys.entindex_victim_const)
    if not valid(attacker) or not valid(victim) or attacker:GetTeamNumber()~=s.team or (tonumber(keys.entindex_inflictor_const) or -1)>0 then return true end
    if keys.damagetype_const~=DAMAGE_TYPE_PHYSICAL then return true end
    local pct=value(s,'C-g9',{10,18,28})/100
    local armor=call(victim,'GetPhysicalArmorValue',0,false)
    if pct>0 and armor>0 then
        local function mult(a) return 1-.06*a/(1+.06*math.abs(a)) end
        s.attack_inputs[victim]={attacker=attacker,raw=keys.damage,time=clock(game)}
        keys.damage=keys.damage*mult(armor*(1-pct))/mult(armor)
    end
    return true
end
function Effects.AbsorbNative(game,u,params,scope)
    local s=game.endlessCardCombat
    if not s or not params or not params.damage or params.damage<=0 then return 0 end
    local flag=DOTA_DAMAGE_FLAG_HPLOSS or 0
    if flag>0 and math.floor((params.damage_flags or 0)/flag)%2==1 then return 0 end
    s.time=clock(game);Barriers.Refresh(s,u,shieldAmp(game,s,u))
    return Barriers.Absorb(s,u,params.damage,params.damage_type,scope)-params.damage
end
function Effects.Absorb(game,u,params)
    local s=game.endlessCardCombat
    if not s or not params or not params.damage or params.damage<=0 then return 0 end
    -- HPLOSS bypasses mitigation and shields, including lethal field stat erosion.
    local flags=params.damage_flags or 0
    local function flag(n) return n and n>0 and math.floor(flags/n)%2==1 end
    if flag(DOTA_DAMAGE_FLAG_HPLOSS) then return 0 end
    local amount=params.damage
    local stats=statsOf(u)
    if not s.damage_context and params.damage_type==DAMAGE_TYPE_PHYSICAL and not params.inflictor
        and (params.damage_category==nil or params.damage_category==(DOTA_DAMAGE_CATEGORY_ATTACK or 1)) then
        amount=math.max(0,amount-(stats.attack_block or 0))
    end
    local r=record(s,u)
    s.time=clock(game)
    Barriers.Refresh(s,u,shieldAmp(game,s,u))
    amount=Barriers.Absorb(s,u,amount,params.damage_type,'all')
    local ids={};for id in pairs(r.shields) do ids[#ids+1]=id end;table.sort(ids)
    for _,id in ipairs(ids) do local sh=r.shields[id]
        if sh.expires<=clock(game) or sh.amount<=0 then r.shields[id]=nil
        elseif amount>0 then local absorbed=math.min(amount,sh.amount);amount=amount-absorbed;sh.amount=sh.amount-absorbed end
    end
    return -(params.damage-amount)
end
function Effects.Critical(game,u,params)
    local s=game.endlessCardCombat;if not s or not params or not alive(params.target) or params.target:GetTeamNumber()==u:GetTeamNumber() then return nil end
    local r=record(s,u);local key=params.record
    if key and r.crit_records[key]~=nil then return r.crit_records[key] or nil end
    local stats=statsOf(u);local result=0
    local roll=RandomInt and RandomInt(1,100) or math.random(100)
    if roll<=(stats.crit_chance or 0) then result=stats.crit_multiplier or 0 end
    if r.guaranteed and r.guaranteed.expires>clock(game) and r.guaranteed.count>0 then result=math.max(result,r.guaranteed.multiplier) end
    if key then r.crit_records[key]=result>0 and result or false end
    return result>0 and result or nil
end
function Effects.Attack(game,u,params)
    local s=game.endlessCardCombat;if not s then return end
    local r=record(s,u)
    if r.guaranteed and r.guaranteed.expires>clock(game) and r.guaranteed.count>0 then r.guaranteed.count=r.guaranteed.count-1 end
end
function Effects.AttackLanded(game,u,params)
    local s=game.endlessCardCombat
    if s and not s.damage_context and body(game,s,u) and params.target==u then
        s.time=clock(game);dispatch(game,s,'attacked',{unit=u,attacker=params.attacker})
        Effects.Refresh(game)
    end
end
function Effects.AttackRecordDestroy(game,u,params)
    local s=game.endlessCardCombat;if s and params.record then record(s,u).crit_records[params.record]=nil end
end
function Effects.MarkAttackSpeed(game,u)
    local s=game.endlessCardCombat;if not s or u:GetTeamNumber()~=s.team then return 0 end
    return s.mark and call(u,'GetAttackTarget',nil)==s.mark and value(s,'W-g2',{40,65,100}) or 0
end
function Effects.Outgoing(game,u,params)
    local s=game.endlessCardCombat
    if not s or s.damage_context or u:GetTeamNumber()~=s.team then return 0 end
    return (statsOf(u).outgoing_damage or 0)+(params and params.target==s.mark and (s.mark_bonus or 0) or 0)
end
function Effects.Cast(game,u,ability)
    local s=game.endlessCardCombat
    if not s or not alive(u) or not ability or call(ability,'IsItem',false) or call(ability,'IsToggle',false) then return end
    s.time=clock(game)
    if u:GetTeamNumber()==s.team then
        local amount=value(s,'E-g4',{60,100,150})
        if amount>0 then each(game,s,true,function(target)
            local r=record(s,target)
            shield(game,s,target,'E-g4',amount,math.huge,true,(r.start_health or target:GetMaxHealth())*.3)
        end) end
        local c=s.by_id['E-g5']
        if c then
            local retained={};for _,expiry in ipairs(s.enlightenment) do if expiry>s.time then retained[#retained+1]=expiry end end
            if #retained>=pick(c,{3,5,8}) then table.remove(retained,1) end
            retained[#retained+1]=s.time+10;s.enlightenment=retained
        end
        c=s.by_id['D-g4'];local r=record(s,u)
        if c and s.time>=(r.cast_heal_at or 0) then
            r.cast_heal_at=s.time+1
            heal(u,pick(c,{30,50,80})+u:GetMaxHealth()*pick(c,{.01,.015,.02}))
        end
        if body(game,s,u) then dispatch(game,s,'cast',{unit=u,ability=ability}) end
    else
        local c=s.by_id['E-f4']
        if c then
            local r=record(s,u);local retained={}
            for _,expiry in ipairs(r.curse or {}) do if expiry>s.time then retained[#retained+1]=expiry end end
            damage(game,s,u,pick(c,{20,32,50})*(1+.15*#retained)*s.field_scale,DAMAGE_TYPE_MAGICAL,'card_curse')
            if #retained>=pick(c,{5,8,12}) then table.remove(retained,1) end
            retained[#retained+1]=s.time+10;r.curse=retained
        end
    end
    Effects.Refresh(game)
end
function Effects.TakeDamage(game,params)
    local s=game.endlessCardCombat;if not s or s.damage_context then return end
    local u,attacker=params.unit,params.attacker
    if not legal(game,u) or not valid(attacker) or (params.damage or 0)<0 then return end
    local flags=params.damage_flags or 0
    local function flagged(flag) return flag and flag>0 and math.floor(flags/flag)%2==1 end
    if flagged(DOTA_DAMAGE_FLAG_HPLOSS) or flagged(DOTA_DAMAGE_FLAG_REFLECTION) then return end
    s.time=clock(game)
    local attack=not params.inflictor and (params.damage_category==nil or params.damage_category==(DOTA_DAMAGE_CATEGORY_ATTACK or 1))
    local filtered=s.attack_inputs[u]
    s.attack_inputs[u]=nil
    local originalDamage=params.original_damage or params.damage
    if attack and filtered and filtered.attacker==attacker and filtered.time==s.time then originalDamage=filtered.raw end
    if u:GetTeamNumber()==s.team and attack and body(game,s,u) then dispatch(game,s,'attacked',params) end
    if u:GetTeamNumber()==s.team and attack then
        local c=active(s,'C-c5',s.time)
        if c then damage(game,s,attacker,pick(c,{40,70,110})+params.damage*pick(c,{.3,.45,.6}),DAMAGE_TYPE_PHYSICAL,'card_reflect',u,DOTA_DAMAGE_FLAG_REFLECTION or 0) end
    end
    if attacker:GetTeamNumber()==s.team and u:GetTeamNumber()~=s.team and legal(game,attacker) then
        local stats=statsOf(attacker)
        if attack then
            World.Attack(worldContext,game,s,attacker,u,params.damage)
            heal(attacker,params.damage*(stats.attack_lifesteal or 0)/100)
            local magic=value(s,'A-g5',{15,25,40})
            local physical=value(s,'W-c1',{30,50,80})+(s.mark==u and value(s,'C-g3',{30,50,80}) or 0)
            damage(game,s,u,magic,DAMAGE_TYPE_MAGICAL,'card_attack',attacker)
            damage(game,s,u,physical,DAMAGE_TYPE_PHYSICAL,'card_attack',attacker)
            local c=active(s,'W-c5',s.time)
            local center=call(u,'GetAbsOrigin',nil)
            if c and center then
                local raw=originalDamage
                each(game,s,false,function(other)
                    local pos=call(other,'GetAbsOrigin',nil)
                    if other~=u and pos and (pos.x-center.x)^2+(pos.y-center.y)^2<=350^2 then
                        damage(game,s,other,raw*pick(c,{.35,.55,.8}),DAMAGE_TYPE_PHYSICAL,'card_splash',attacker)
                    end
                end)
            end
        elseif params.inflictor then
            if not flagged(DOTA_DAMAGE_FLAG_NO_SPELL_LIFESTEAL) then heal(attacker,params.damage*(stats.spell_lifesteal or 0)/100) end
            local c=s.by_id['E-g9']
            if c then timed(s,u,'E-g9',{move_speed=-pick(c,{8,12,18}),attack_speed=-pick(c,{6,10,15})},2*(1-call(u,'GetStatusResistance',0))) end
        end
    end
    Effects.Refresh(game)
end
local function copyForm(game,s,dead,c,kind)
    if not CreateUnitByName or not valid(dead) then return end
    local r=record(s,dead)
    if r.reborn then return end
    r.reborn=true
    local pos=call(dead,'GetAbsOrigin',s.center)
    local u=CreateUnitByName(dead:GetUnitName(),pos,true,nil,nil,s.team)
    if not valid(u) then return end
    u.endlessRebirthForm=true;u.endlessRebirthSource=dead;u.endlessCardSummon=true
    if u.SetDeathXP then u:SetDeathXP(0) end
    if u.SetMinimumGoldBounty then u:SetMinimumGoldBounty(0);u:SetMaximumGoldBounty(0) end
    if u.SetRespawnsDisabled then u:SetRespawnsDisabled(true) end
    if kind=='soul' and u.SetRenderColor then u:SetRenderColor(80,255,120) end
    -- Copy spells and items before native illusion identity is applied. Echo exposes
    -- strong/super illusion properties so native orders may use copied abilities.
    local level=call(dead,'GetLevel',1)
    if u.HeroLevelUp then for i=2,level do u:HeroLevelUp(false) end end
    for _,name in ipairs({'Strength','Agility','Intellect'}) do
        if u['SetBase'..name] and dead['GetBase'..name] then u['SetBase'..name](u,dead['GetBase'..name](dead)) end
    end
    for i=0,23 do
        local original=call(dead,'GetAbilityByIndex',nil,i)
        if original then
            local name=original:GetAbilityName();local a=call(u,'FindAbilityByName',nil,name)
            if not a and u.AddAbility then a=u:AddAbility(name) end
            if a then
                a:SetLevel(original:GetLevel())
                if a.EndCooldown then a:EndCooldown() end
                local cd=call(original,'GetCooldownTimeRemaining',0)
                if cd>0 and a.StartCooldown then a:StartCooldown(cd) end
                if a.SetCurrentAbilityCharges and original.GetCurrentAbilityCharges then a:SetCurrentAbilityCharges(original:GetCurrentAbilityCharges()) end
            end
        end
    end
    if CreateItem and u.AddItem then for _,slot in ipairs({0,1,2,3,4,5,6,7,8,16}) do
        local item=call(dead,'GetItemInSlot',nil,slot)
        if item then
            local copy=CreateItem(item:GetAbilityName(),u,u)
            if copy then
                if copy.SetCurrentCharges then copy:SetCurrentCharges(call(item,'GetCurrentCharges',0)) end
                if copy.SetSecondaryCharges and item.GetSecondaryCharges then copy:SetSecondaryCharges(item:GetSecondaryCharges()) end
                if copy.SetDroppable then copy:SetDroppable(false) end
                if copy.SetSellable then copy:SetSellable(false) end
                if copy.SetPurchaser then copy:SetPurchaser(nil) end
                u:AddItem(copy)
                local cd=call(item,'GetCooldownTimeRemaining',0);if cd>0 and copy.StartCooldown then copy:StartCooldown(cd) end
                if u.SwapItems and copy.GetItemSlot then u:SwapItems(copy:GetItemSlot(),slot) end
            end
        end
    end end
    -- Native base edits apply to every form. Total health/damage include
    -- attributes, items and cards, whose contributions are inherited separately.
    for _,name in ipairs({'BaseMaxHealth','BaseMaxMana','BaseDamageMin','BaseDamageMax',
        'PhysicalArmorBaseValue','BaseAttackTime','BaseMoveSpeed','BaseMagicalResistanceValue'}) do
        if u['Set'..name] and dead['Get'..name] then
            u['Set'..name](u,dead['Get'..name](dead))
        end
    end
    if kind=='echo' and u.AddNewModifier then
        u:AddNewModifier(dead,nil,'modifier_illusion',{duration=pick(c,{5,8,12}),outgoing_damage=0,incoming_damage=0})
        u:AddNewModifier(dead,nil,'modifier_endless_card_echo',{duration=pick(c,{5,8,12})})
    end
    -- The preparation contribution is inherited once. Combat stats are freshly aggregated once.
    local p=game.endlessCardPrepared
    local inherited=p and p.stats[dead] or record(s,dead).prepared
    if inherited then setstats(game,s,u,inherited,PREP);p.units[u]=true;p.stats[u]=inherited end
    if u.SetControllableByPlayer then local owner=call(dead,'GetPlayerOwnerID',-1);if owner>=0 then u:SetControllableByPlayer(owner,true) end end
    s.spawned[u]={expires=s.time+pick(c,{5,8,12}),kind=kind,original=dead}
    if kind=='soul' or kind=='echo' then s.forms[u]={source=dead,expires=s.spawned[u].expires} end
    if FindClearSpaceForUnit then FindClearSpaceForUnit(u,pos,true) end
    Effects.Refresh(game)
    if u.SetHealth then u:SetHealth(u:GetMaxHealth()) end
    if u.SetMana then u:SetMana(call(u,'GetMaxMana',0)) end
    return u
end
function Effects.Death(game,params)
    local s=game.endlessCardCombat;if not s then return end
    local u=params.unit
    if not legal(game,u) or u.endlessRebirthForm or u.endlessCardCleanup then return end
    -- Expiring native summons die through modifier_kill, with no hostile killer.
    local attacker=params.attacker
    if (call(u,'HasModifier',false,'modifier_kill') or call(u,'IsSummoned',false) or call(u,'IsIllusion',false) or u.endlessCardSummon)
        and (not valid(attacker) or attacker==u) then return end
    s.time=clock(game)
    local r=record(s,u)
    if r.dead then return end
    r.dead=true
    s.deaths=s.deaths+1
    if s.mark==u then dispatch(game,s,'mark_death',params);s.mark=nil;s.mark_bonus=nil end
    if u:GetTeamNumber()==s.team then
        s.friendly_deaths=s.friendly_deaths+1
        dispatch(game,s,'friendly_death',params)
        if alive(attacker) and attacker:GetTeamNumber()~=s.team then dispatch(game,s,'killed_ally',params) end
        for _,id in ipairs({'D-g3','A-g2'}) do local c=s.by_id[id]
            if c and c.hero==u and not c.reborn then c.reborn=true;copyForm(game,s,u,c,id=='D-g3' and 'echo' or 'soul') end
        end
        local c=s.by_id['W-g3']
        if c and not call(u,'IsRealHero',false) and not call(u,'IsIllusion',false)
            and (u.endlessCardSummon or call(u,'IsSummoned',false) or call(u,'IsCreature',false)) then copyForm(game,s,u,c,'beast') end
    end
    Effects.Refresh(game)
end
return Effects
