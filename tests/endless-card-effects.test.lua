-- Run from repository root with Lua 5.1+; engine contract mocks deliberately dispatch
-- nested damage/death events to catch reflection loops and shared-charge reentrancy.
package.path='game/dota_addons/dota2_rpg_endless/scripts/vscripts/?.lua;'..package.path
function class(base) local c={};c.__index=c;return setmetatable(c,{__index=base}) end
function IsServer() return true end
function Vector(x,y,z) return {x=x,y=y,z=z} end
DOTA_TEAM_GOODGUYS=2;DOTA_UNIT_TARGET_TEAM_BOTH=3;DOTA_UNIT_TARGET_HERO=1;DOTA_UNIT_TARGET_BASIC=2;FIND_ANY_ORDER=0
DAMAGE_TYPE_PHYSICAL=1;DAMAGE_TYPE_MAGICAL=2;DAMAGE_TYPE_PURE=4
DOTA_DAMAGE_FLAG_HPLOSS=1;DOTA_DAMAGE_FLAG_REFLECTION=2;DOTA_DAMAGE_FLAG_NO_SPELL_AMPLIFICATION=4;DOTA_DAMAGE_FLAG_NO_SPELL_LIFESTEAL=8
DOTA_DAMAGE_CATEGORY_ATTACK=1
local clock,world,nextid=0,{},0
local game,Effects
GameRules={GetGameTime=function() return clock end}
function FindUnitsInRadius(team,origin,cache,radius,side,types)
    assert(radius==-1 and side==3 and types==3,'whole battlefield query')
    return world
end
local Modifier=require('modifiers/modifier_endless_card_stats')
require('modifiers/modifier_endless_card_control')
local NAME='modifier_endless_card_stats';local PREP='modifier_endless_card_prepare'
local function unit(team,hero)
    nextid=nextid+1
    local u={id=nextid,name='test_'..nextid,team=team,hp=1000,maxhp=1000,basehp=1000,mp=500,maxmp=500,basemp=500,
        alive=true,hero=hero,mods={},adds=0,str=10,agi=10,int=10,armor=0,attack=100,position=Vector(0,0,0),abilities={},items={}}
    function u:IsNull() return self.removed or false end
    function u:IsAlive() return self.alive end
    function u:IsRealHero() return self.hero end
    function u:IsIllusion() return self.illusion or false end
    function u:IsSummoned() return self.summoned or false end
    function u:IsCreature() return not self.hero end
    function u:GetTeamNumber() return self.team end
    function u:GetHealth() return self.hp end
    function u:GetMaxHealth() return self.maxhp end
    function u:GetMana() return self.mp end
    function u:GetMaxMana() return self.maxmp end
    function u:GetUnitName() return self.name end
    function u:GetAbsOrigin() return self.position end
    function u:GetAverageTrueAttackDamage() return self.attack end
    function u:GetPhysicalArmorValue() return self.armor end
    function u:GetStatusResistance() return self.resistance or 0 end
    function u:GetAttackTarget() return self.target end
    function u:GetPrimaryAttribute() return self.primary or 0 end
    function u:GetBaseStrength() return self.str end
    function u:GetBaseAgility() return self.agi end
    function u:GetBaseIntellect() return self.int end
    local function attr(self,key,method)
        local n=self[key]
        for _,m in pairs(self.mods) do if m[method] then n=n+m[method](m) end end
        return math.max(0,n)
    end
    function u:GetStrength() return attr(self,'str','GetModifierBonusStats_Strength') end
    function u:GetAgility() return attr(self,'agi','GetModifierBonusStats_Agility') end
    function u:GetIntellect() return attr(self,'int','GetModifierBonusStats_Intellect') end
    function u:SetBaseStrength(n) self.str=n end
    function u:SetBaseAgility(n) self.agi=n end
    function u:SetBaseIntellect(n) self.int=n end
    function u:SetHealth(n) self.hp=math.min(self.maxhp,n) end
    function u:SetMana(n) self.mp=math.min(self.maxmp,n) end
    function u:GiveMana(n) self:SetMana(self.mp+n) end
    function u:Heal(n)
        local m=self.mods[NAME];n=n*(1+(m and m.stats.heal_amp or 0)/100)
        self.healed=(self.healed or 0)+n;self:SetHealth(self.hp+n)
    end
    function u:HasModifier(name) return self.mods[name]~=nil end
    function u:FindModifierByName(name) return self.mods[name] end
    function u:FindAllModifiers() local list={};for _,m in pairs(self.mods) do list[#list+1]=m end;return list end
    function u:SetTeam(team) self.team=team end
    function u:RemoveModifierByName(name) self.mods[name]=nil;self:CalculateStatBonus() end
    function u:AddNewModifier(caster,ability,name,kv)
        if name=='modifier_endless_card_control' then self.controls=self.controls or {};self.controls[#self.controls+1]=kv;return {} end
        if name=='modifier_endless_card_source' then return {} end
        if name=='modifier_illusion' then self.illusion=true;self.illusionKV=kv;self.mods[name]={};return self.mods[name] end
        if name=='modifier_endless_card_echo' then local m=setmetatable({},modifier_endless_card_echo);self.mods[name]=m;return m end
        assert(caster==nil,'stat effects must not belong to carrier')
        self.adds=self.adds+1
        local m=setmetatable({parent=self},name==PREP and modifier_endless_card_prepare or Modifier)
        function m:GetParent() return self.parent end
        m:OnCreated();self.mods[name]=m;return m
    end
    function u:CalculateStatBonus()
        local h,m=self.basehp,self.basemp
        for _,mod in pairs(self.mods) do
            if mod.GetModifierHealthBonus then h=h+mod:GetModifierHealthBonus() end
            if mod.GetModifierManaBonus then m=m+mod:GetModifierManaBonus() end
        end
        h=h+(self:GetStrength()-self.str)*22;m=m+(self:GetIntellect()-self.int)*12
        self.maxhp=math.max(1,h);self.maxmp=math.max(0,m)
        self.hp=math.min(self.hp,self.maxhp);self.mp=math.min(self.mp,self.maxmp)
    end
    function u:GetBaseMaxHealth() return self.basehp end
    function u:GetBaseDamageMin() return self.damage_min or self.attack end
    function u:GetBaseDamageMax() return self.damage_max or self.attack end
    function u:GetBaseAttackTime() return self.bat or 1.7 end
    function u:GetBaseMoveSpeed() return self.ms or 300 end
    function u:GetPhysicalArmorBaseValue() return self.armor end
    function u:GetBaseMagicalResistanceValue() return self.mr or 25 end
    function u:SetBaseMaxHealth(n) self.basehp=n end
    function u:SetMaxHealth(n) self.maxhp=n end
    function u:SetBaseDamageMin(n) self.damage_min=n end
    function u:SetBaseDamageMax(n) self.damage_max=n end
    function u:SetBaseAttackTime(n) self.bat=n end
    function u:SetBaseMoveSpeed(n) self.ms=n end
    function u:SetPhysicalArmorBaseValue(n) self.armor=n end
    function u:SetBaseMagicalResistanceValue(n) self.mr=n end
    function u:MoveToTargetToAttack(target) self.orders=(self.orders or 0)+1;self.target=target end
    function u:GetAbilityByIndex(i) return self.abilities[i] end
    function u:GetItemInSlot(i) return self.items[i] end
    function u:AddItem(item) local i=0;while self.items[i] do i=i+1 end;self.items[i]=item;item.slot=i end
    function u:SwapItems(a,b) self.items[a],self.items[b]=self.items[b],self.items[a];if self.items[a] then self.items[a].slot=a end;if self.items[b] then self.items[b].slot=b end end
    function u:FindAbilityByName(name) for _,a in pairs(self.abilities) do if a:GetAbilityName()==name then return a end end end
    function u:Purge(...) self.purge={...} end
    function u:IsStunned() return self.stunned or false end
    function u:IsFeared() return false end
    function u:IsTaunted() return false end
    function u:SetRespawnsDisabled(v) self.respawnsDisabled=v end
    function u:SetDeathXP(v) self.xp=v end
    function u:SetMinimumGoldBounty(v) self.gold=v end
    function u:SetMaximumGoldBounty(v) self.gold=v end
    world[#world+1]=u
    return u
end
function CreateUnitByName(name,pos,_,owner,__,team)
    local u=unit(team,name:find('hero')~=nil);u.name=name;u.position=pos;return u
end
function CreateIllusions(owner,original,kv,count)
    local result={}
    for i=1,count do local u=unit(owner:GetTeamNumber(),true);u.illusion=true;u.illusionKV=kv;u.original=original;result[#result+1]=u end
    return result
end
function CreateItem(name,owner,purchaser)
    local item={name=name,charges=0,secondary=0,cd=0,slot=-1}
    function item:GetAbilityName() return self.name end
    function item:GetCurrentCharges() return self.charges end
    function item:SetCurrentCharges(n) self.charges=n end
    function item:GetSecondaryCharges() return self.secondary end
    function item:SetSecondaryCharges(n) self.secondary=n end
    function item:GetCooldownTimeRemaining() return self.cd end
    function item:StartCooldown(n) self.cd=n end
    function item:GetItemSlot() return self.slot end
    function item:SetDroppable(v) self.droppable=v end
    function item:SetSellable(v) self.sellable=v end
    function item:SetPurchaser(v) self.purchaser=v end
    return item
end
function UTIL_Remove(u) u.removed=true;u.alive=false end
function EntIndexToHScript(id) for _,u in ipairs(world) do if u.id==id then return u end end end
local damageLog={}
function ApplyDamage(p)
    local v,a=p.victim,p.attacker
    local n=p.damage
    if p.damage_type==DAMAGE_TYPE_PHYSICAL then n=n*(1-.06*v.armor/(1+.06*math.abs(v.armor))) end
    local m=v.mods[NAME]
    if (p.damage_flags or 0)%2~=1 and m then
        n=n*(1+m:GetModifierIncomingDamage_Percentage({damage_type=p.damage_type})/100)
        local function event() return {damage=n,damage_type=p.damage_type,inflictor=p.inflictor,damage_flags=p.damage_flags} end
        if p.damage_type==DAMAGE_TYPE_PHYSICAL then n=math.max(0,n+m:GetModifierIncomingPhysicalDamageConstant(event())) end
        if p.damage_type==DAMAGE_TYPE_MAGICAL then n=math.max(0,n+m:GetModifierIncomingSpellDamageConstant(event())) end
        n=math.max(0,n+m:GetModifierIncomingDamageConstant(event()))
    end
    v.hp=v.hp-n
    local entry={unit=v,attacker=a,damage=n,original_damage=p.damage,damage_type=p.damage_type,damage_flags=p.damage_flags,inflictor=p.inflictor}
    damageLog[#damageLog+1]={victim=v,attacker=a,amount=n,tag=game.endlessCardCombat and game.endlessCardCombat.damage_context and game.endlessCardCombat.damage_context.tag}
    if m then m:OnTakeDamage(entry) end
    if v.hp<=0 and v.alive then v.hp=0;v.alive=false;if m then m:OnDeath(entry) end end
    return n
end
Effects=require('endless/card_effects')
local a,b,e,commander
local assertions=0
local function eq(actual,expected,message)
    assertions=assertions+1
    assert(actual==expected,(message or 'value')..': '..tostring(actual)..' ~= '..tostring(expected))
end
local function near(actual,expected,message) assertions=assertions+1;assert(math.abs(actual-expected)<.00001,(message or 'near')..': '..actual..' ~= '..expected) end
local function reset()
    if game then Effects.Stop(game) end
    clock=0;world={};damageLog={}
    a=unit(2,true);a.name='npc_dota_hero_axe';b=unit(2,true);b.name='npc_dota_hero_lina';e=unit(3,true);commander=unit(2,true)
    game={placeholderHero=commander,battleManager={teamHeroes={[2]={a,b},[3]={e}}}}
end
local function start(cards) return Effects.Start(game,cards) end
local function at(t) clock=t;Effects.Tick(game) end
local function stat(u,key) return u.mods[NAME] and (u.mods[NAME].stats[key] or 0) or 0 end
local function spell(item) return {IsItem=function() return item or false end,IsToggle=function() return false end} end
local function cast(u,item) u.mods[NAME]:OnAbilityExecuted({unit=u,ability=spell(item)}) end
local function attack(attacker,victim,n)
    return ApplyDamage({attacker=attacker,victim=victim,damage=n,damage_type=DAMAGE_TYPE_PHYSICAL,damage_flags=0})
end
reset()
local count=0;for _ in pairs(Effects.definitions) do count=count+1 end
eq(count,100,'executable basic definitions')
local unsupported=0;for id,why in pairs(Effects.unsupported) do unsupported=unsupported+1;eq(Effects.definitions[id],nil,id..' excluded');assert(#why>20) end
eq(unsupported,0,'all 100 basic cards accounted for')
local s=start({{id='C-g1',load=2,hero=a},{id='C-g1',load=3},{id='E-f2',load=3},{id='A-f4',load=2},{id='unknown-card',load=3},{id='D-g1',load=4}})
eq(#s.cards,3);eq(stat(a,'attack_speed'),35);eq(stat(b,'attack_speed'),35);eq(stat(e,'move_speed'),-28);eq(stat(e,'armor'),-13)
eq(commander.mods[NAME],nil)
local adds=a.adds;for i=1,10 do at(i/10) end;eq(a.adds,adds,'no stacking')
a.alive=false;local summon=unit(2,false);at(2);eq(stat(summon,'attack_speed'),35);eq(stat(e,'armor'),-13)
Effects.Stop(game);for _,u in ipairs(world) do eq(u.mods[NAME],nil) end
reset();s=start({{id='C-c1',load=2},{id='W-g5',load=1},{id='W-c4',load=1}})
at(4.99);eq(s.cards[1].remaining,2);at(5);eq(s.cards[1].remaining,1);eq(stat(a,'base_damage_pct'),72)
at(8);eq(stat(a,'base_damage_pct'),97);at(13);eq(stat(a,'base_damage_pct'),37)
at(17);eq(s.cards[1].remaining,0);eq(stat(a,'base_damage_pct'),97);at(25);eq(stat(a,'base_damage_pct'),12)
reset();a.hp=700;s=start({{id='D-c1',load=3},{id='D-g2',load=1},{id='A-g1',load=3}})
eq(s.cards[1].remaining,3);a.hp=699;b.hp=600;at(1);eq(s.cards[1].remaining,2);near(stat(a,'health_regen_pct'),4.9)
at(11);near(stat(a,'health_regen_pct'),.4);at(13);eq(s.cards[1].remaining,1)
a.hp=0;near(a.mods[NAME]:GetModifierConstantHealthRegen(),50);a.hp=1000;near(a.mods[NAME]:GetModifierConstantHealthRegen(),15)
reset();s=start({{id='E-c1',load=3},{id='E-c6',load=3}});at(5);eq(s.by_id['E-c1'].remaining,2);at(100);eq(s.by_id['E-c1'].remaining,2);eq(s.by_id['E-c6'].remaining,2,'elemental first only')
reset();s=start({{id='C-c1',load=2,trigger={type='hero_mana_below',threshold=.3}}});at(5);eq(s.cards[1].remaining,2);a.mp=1;at(6);eq(s.cards[1].remaining,1)
-- Preparation arithmetic, health ratio preservation, field carriers deduplicated, universal primary maximum.
reset();a.hp=500;a.mp=250;a.str=200;b.primary=3;b.str=20;b.agi=300
local cards={{id='E-g3',load=1},{id='W-g8',load=1},{id='W-g9',load=1},{id='A-g6',load=1},{id='D-g8',load=1},{id='A-g7',load=1},
    {id='E-f3',load=3,hero=a.name},{id='E-f1',load=1,hero=b.name},{id='C-f1',load=1,hero=a.name}}
local p=Effects.Prepare(game,cards);near(p.field_scale,1.5);near(a.maxhp,(1000+450)*.98+60*22);near(a.hp/a.maxhp,.5)
near(a.maxmp,(500+150)*.85+60*12);near(a.mp/a.maxmp,.5)
for i=1,3 do Effects.Prepare(game,cards);near(a.hp/a.maxhp,.5);near(a.mp/a.maxmp,.5) end
s=start(cards);near(s.field_scale,1.5);near(stat(a,'mana_regen'),15);near(a.hp/a.maxhp,.5)
Effects.Stop(game);near(a.maxhp,1000);near(a.hp,500);near(a.maxmp,500);near(a.mp,250)
-- Cast shields cap at start maximum, independent caster cooldown, curse enemy-local expiries.
reset();s=start({{id='E-g4',load=3},{id='E-g5',load=1},{id='D-g4',load=1},{id='E-f4',load=1},{id='W-c1',load=2}})
a.hp=500;cast(a,true);eq(s.by_id['W-c1'].remaining,2);cast(a);eq(s.by_id['W-c1'].remaining,1);eq(a.hp,540)
cast(a);eq(a.hp,540,'cast healing ICD');eq(s.unit_state[a].shields['E-g4'].amount,300)
cast(a);cast(a);eq(stat(a,'intelligence'),3,'enlightenment cap')
local n=a.mods[NAME]:GetModifierIncomingDamageConstant({damage=350,damage_type=DAMAGE_TYPE_PURE})
eq(n,-300);eq(s.unit_state[a].shields['E-g4'].amount,0)
cast(e);near(damageLog[#damageLog].amount,20);cast(e);near(damageLog[#damageLog].amount,23)
at(11);eq(stat(a,'intelligence'),0);cast(e);near(damageLog[#damageLog].amount,20,'expired curse layers')
eq(damageLog[#damageLog].tag,'card_curse');eq(damageLog[#damageLog].attacker.endlessCardSource,true)
-- Shield refreshing uses one shared charge, expiring shields and HPLOSS bypass.
reset();a.hp=400;s=start({{id='D-c3',load=3},{id='C-g2',load=1}})
eq(s.cards[1].remaining,2);near(s.unit_state[a].shields['D-c3'].amount,400)
near(a.mods[NAME]:GetModifierIncomingDamageConstant({damage=100,damage_type=DAMAGE_TYPE_PHYSICAL}),-100)
near(s.unit_state[a].shields['D-c3'].amount,315,'post armor attack block before shield')
near(a.mods[NAME]:GetModifierIncomingDamageConstant({damage=50,damage_type=DAMAGE_TYPE_PURE,damage_flags=DOTA_DAMAGE_FLAG_HPLOSS}),0)
at(10);near(a.mods[NAME]:GetModifierIncomingDamageConstant({damage=100,damage_type=DAMAGE_TYPE_PURE}),0)
at(12);near(s.unit_state[a].shields['D-c3'].amount,400)
-- Reflection cannot recursively trigger or lifesteal; victims handle one broadcast event.
reset();s=start({{id='C-c5',load=3},{id='A-g9',load=3}});a.hp=500
attack(e,a,100);eq(s.cards[1].remaining,2);eq(#damageLog,2);near(e.hp,830);near(a.hp,400)
a.hp=500;attack(a,e,100);near(a.hp,528,'actual attack lifesteal')
-- Extra damage, splash center and no secondary recursion. Physical ignores target armor only for original attacks.
reset();local other=unit(3,false);other.position=Vector(300,0,0);a.position=Vector(2000,0,0)
s=start({{id='A-g5',load=1},{id='W-c5',load=1},{id='A-g9',load=1},{id='C-g9',load=3}});at(5);a.hp=500
attack(a,e,100);eq(#damageLog,3);near(other.hp,965);near(e.hp,885);near(a.hp,510)
e.armor=20;local keys={entindex_attacker_const=a.id,entindex_victim_const=e.id,damagetype_const=DAMAGE_TYPE_PHYSICAL,damage=100}
Effects.DamageFilter(game,keys);near(keys.damage,100*(1/(1+.06*20*.72))/(1/(1+.06*20)))
keys.damage=100;keys.entindex_inflictor_const=42;Effects.DamageFilter(game,keys);eq(keys.damage,100)
-- Mark migration, death rewards, per-life growth caps, no expiry/cleanup/form death rewards.
reset();s=start({{id='A-c1',load=3},{id='A-c2',load=3},{id='C-g3',load=1},{id='C-g4',load=3},{id='A-g3',load=3},{id='W-g4',load=3},{id='W-g2',load=2}})
a.alive=false;Effects.Death(game,{unit=a,attacker=e});eq(s.mark,e);eq(stat(b,'armor'),3);eq(stat(b,'attack_damage'),8)
b.target=e;eq(Effects.MarkAttackSpeed(game,b),65);eq(Effects.Outgoing(game,b,{target=e}),28)
Effects.Death(game,{unit=a,attacker=e});eq(s.friendly_deaths,1,'duplicate death ignored')
b.hp=100;e.alive=false;Effects.Death(game,{unit=e,attacker=b});eq(s.mark,nil);eq(s.by_id['A-c2'].remaining,2);eq(b.hp,550)
local form=unit(2,false);form.endlessRebirthForm=true;form.alive=false;Effects.Death(game,{unit=form,attacker=b});eq(s.deaths,2)
local expired=unit(2,false);expired.endlessCardCleanup=true;expired.alive=false;Effects.Death(game,{unit=expired,attacker=e});eq(s.deaths,2)
-- Ownerless cumulative field drains: unbounded pulses, floors cannot grant 1 HP immunity.
reset();s=start({{id='A-f3',load=3}});a.alive=false;e.hp=20
at(3);eq(e.alive,false,'max health loss is lethal');eq(damageLog[#damageLog].tag,'card_field');eq(damageLog[#damageLog].attacker.endlessCardSource,true)
reset();e.basehp=30;e.maxhp=30;e.hp=30;s=start({{id='A-f3',load=3}});at(3);eq(e.alive,false,'lethal at max-health floor')
reset();s=start({{id='W-f3',load=3},{id='A-f2',load=1}});at(1);near(e:GetStrength(),9);near(e.hp,978);at(2);near(e:GetStrength(),8);at(5);near(e:GetStrength(),5);eq(e.controls[1].kind,'fear')
-- Stat recipient groups and skill-only cooldown/cost; enemy healing reduction capped -80.
reset();s=start({{id='A-f1',load=3},{id='A-c7',load=3},{id='D-g6',load=3},{id='C-g5',load=3},{id='C-g7',load=1},{id='D-g9',load=2}})
at(5);eq(stat(e,'heal_amp'),-80);eq(stat(a,'heal_amp'),40)
eq(a.mods[NAME]:GetModifierPercentageCooldown({ability=spell()}),24);eq(a.mods[NAME]:GetModifierPercentageCooldown({ability=spell(true)}),0)
eq(a.mods[NAME]:GetModifierPercentageManacostStacking({ability=spell()}),-20)
eq(a.mods[NAME]:GetModifierIncomingDamage_Percentage({damage_type=DAMAGE_TYPE_PHYSICAL}),-13)
-- Per-unit guaranteed critical budgets, repeated property queries same record, new unit excluded.
reset();s=start({{id='W-c6',load=1}});at(5)
local params={target=e,record=1};eq(Effects.Critical(game,a,params),180);eq(Effects.Critical(game,a,params),180)
eq(s.unit_state[a].guaranteed.count,3);Effects.Attack(game,a,params);eq(s.unit_state[a].guaranteed.count,2);eq(s.unit_state[b].guaranteed.count,3)
local newcomer=unit(2,false);at(6);eq(s.unit_state[newcomer].guaranteed,nil)
at(15);eq(Effects.Critical(game,a,{target=e,record=2}),nil)
-- Hounds use unmodified opening averages, team total cap, expiration causes no death growth.
reset();s=start({{id='W-c3',load=3},{id='W-g8',load=1},{id='A-g3',load=1}});at(5)
local hounds={};for u,entry in pairs(s.spawned) do hounds[#hounds+1]=u;eq(entry.kind,'hound');eq(u.basehp,500);eq(u.damage_min,50);eq(u.bat,1.2);eq(u.ms,350);eq(u.armor,3);eq(u.mr,25);eq(u.maxhp,750) end
eq(#hounds,4);at(20);for _,u in ipairs(hounds) do eq(u.removed,true) end;eq(s.deaths,0)
-- Cast-capable soul lifecycle, source association, no duplicate preparation bonus, no forced attack orders.
reset();a.items[16]=CreateItem('item_neutral_test',a,a);a.items[16].charges=3;a.items[16].secondary=7;a.items[16].cd=12
s=start({{id='A-g2',load=1,hero=a.name},{id='W-g8',load=1},{id='C-g1',load=1}})
a.alive=false;Effects.Death(game,{unit=a,attacker=e})
local soul;for u,entry in pairs(s.forms) do soul=u;eq(entry.source,a);eq(entry.expires,5) end
assert(soul,'soul spawned');eq(soul.endlessRebirthSource,a);eq(soul.maxhp,1250);eq(stat(soul,'attack_speed'),20);eq(soul.respawnsDisabled,true);eq(soul.xp,0)
eq(soul.items[16]:GetAbilityName(),'item_neutral_test');eq(soul.items[16].charges,3);eq(soul.items[16].secondary,7);eq(soul.items[16].cd,12);eq(soul.items[16].droppable,false);eq(soul.items[16].sellable,false)
at(1);eq(soul.orders,nil);at(5);eq(soul.removed,true);eq(next(s.forms),nil)
a.alive=true;at(6);a.alive=false;Effects.Death(game,{unit=a,attacker=e});eq(next(s.forms),nil,'once per card per battle')
-- State changes remove combat stats from benched units and stop cancels all jobs.
reset();s=start({{id='C-c4',load=1}});at(6);local logged=#damageLog;Effects.Stop(game);at(7);eq(#damageLog,logged)
-- Remaining timing/instant branches: no deferred DoT after expiry, per-recipient rescue,
-- mana costs and healing pools use the recipient's own capacity.
reset();s=start({{id='E-c3',load=2}});for t=1,5 do at(t) end;near(e.hp,875);eq(s.cards[1].remaining,1);at(20);near(e.hp,875)
reset();s=start({{id='E-c3',load=1}});at(20);near(e.hp,1000,'stalled DoT does not damage after expiry')
reset();a.mp=0;b.mp=400;s=start({{id='E-c5',load=3}});eq(s.cards[1].remaining,3,'team ratio, not any hero');b.mp=200;at(1);eq(s.cards[1].remaining,2);near(a.mp,225);near(b.mp,425)
reset();s=start({{id='E-g1',load=3},{id='E-g2',load=2},{id='E-g6',load=3}});at(29);near(stat(a,'spell_amp'),5);near(stat(a,'cooldown'),0);at(30);near(stat(a,'spell_amp'),7.5);near(stat(a,'cooldown'),18);at(150);near(stat(a,'spell_amp'),25);a.hp=500;near(a.mods[NAME]:GetModifierSpellAmplify_Percentage(),42.5)
reset();a.hp=200;b.hp=500;s=start({{id='D-c4',load=1}});near(a.hp,400);near(b.hp,700);eq(stat(a,'incoming_damage'),-20);eq(stat(b,'incoming_damage'),0);at(4);eq(stat(a,'incoming_damage'),0)
reset();a.stunned=true;s=start({{id='D-c5',load=2}});eq(s.cards[1].remaining,1);eq(a.purge[1],false);eq(a.purge[2],true);eq(a.purge[4],true);eq(a.purge[5],true);eq(stat(b,'status_resistance'),40)
reset();e.resistance=.25;s=start({{id='D-c6',load=2}});at(10);near(e.hp,650);eq(e.controls[1].kind,'stun');near(e.controls[1].duration,.9)
reset();a.hp=100;b.hp=600;s=start({{id='C-c6',load=2}});near(a.hp,350);near(b.hp,850);near(stat(a,'health_regen_pct'),1.5);at(6);eq(stat(a,'health_regen_pct'),0)
reset();a.mp=0;b.basemp=0;b.maxmp=0;b.mp=0;s=start({{id='A-c6',load=2}});near(a.hp,920);near(a.mp,200);near(b.hp,1000);eq(stat(a,'mana_cost'),-25);at(8);eq(stat(a,'mana_cost'),0)
reset();a.hp=100;b.hp=100;local extra=unit(3,false);extra.basehp=2000;extra.maxhp=2000;extra.hp=2000
s=start({{id='A-c3',load=3}});near(e.hp,910);near(extra.hp,1820);near(a.hp,208);near(b.hp,208,'heal pool divided among bodies, not summons')
reset();s=start({{id='C-c4',load=1}});at(6);near(e.hp,900);at(7);near(e.hp,800);at(8);near(e.hp,700)
reset();s=start({{id='W-f4',load=2}});at(6);eq(stat(e,'attack_damage_pct'),-22);eq(stat(e,'base_damage_pct'),0);at(8);eq(stat(e,'attack_damage_pct'),0)
reset();local beast=unit(2,false);beast.summoned=true;s=start({{id='W-g3',load=2},{id='C-g4',load=1}})
beast.alive=false;Effects.Death(game,{unit=beast,attacker=e});local beastSoul;for u,entry in pairs(s.spawned) do beastSoul=u;eq(entry.kind,'beast') end
assert(beastSoul);eq(s.friendly_deaths,1);beastSoul.alive=false;Effects.Death(game,{unit=beastSoul,attacker=e});eq(s.friendly_deaths,1);at(1);eq(beastSoul.removed,true)
reset();s=start({{id='A-g4',load=2},{id='E-g9',load=3}});a.hp=500
ApplyDamage({attacker=a,victim=e,damage=100,damage_type=DAMAGE_TYPE_MAGICAL,inflictor=spell(),damage_flags=0});near(a.hp,514);eq(stat(e,'move_speed'),-18);eq(stat(e,'attack_speed'),-15);at(2);eq(stat(e,'move_speed'),0)
reset();a.hp=400;s=start({{id='A-g8',load=3},{id='W-c7',load=3}});near(stat(a,'evasion'),62.5,'independent evasion sources');at(8);near(stat(a,'evasion'),25)
reset();s=start({{id='C-f4',load=3},{id='D-f2',load=1}});near(stat(a,'health_regen'),149.5);near(stat(a,'health_regen_pct'),1.15);eq(stat(a,'heal_amp'),0);a.hp=100;a:Heal(100);near(a.hp,200,'field amplifier never feeds native hero healing')
-- Fire Shield is unconditional; overlapping living allies never duplicate one pulse.
reset();b.position=Vector(200,0,0);local far=unit(3,false);far.position=Vector(601,0,0)
s=start({{id='E-g7',load=2}});at(1);near(e.hp,930);near(far.hp,1000);eq(#damageLog,1,'no shield gate and overlapping centers hit once')
at(2);near(e.hp,860);a.alive=false;b.position=Vector(900,0,0)
at(3);near(e.hp,860,'dead allies cannot emit pulses');near(far.hp,930)
-- Opening resistance is one-shot and expires after ten seconds.
reset();s=start({{id='E-c2',load=3}});eq(stat(a,'magic_resistance'),30);eq(s.cards[1].remaining,2);at(10);eq(stat(a,'magic_resistance'),0);at(30);eq(s.cards[1].remaining,2)
-- Burn uses actual attack damage, refreshes without stacking, survives grant expiry.
reset();a.hp=400;s=start({{id='E-c4',load=2}});near(a.hp,650);eq(s.cards[1].remaining,1)
attack(a,e,120);at(1);near(e.hp,866);attack(b,e,60);at(2);near(e.hp,792);at(3);near(e.hp,778);at(4);near(e.hp,764)
at(4.5);attack(a,e,30);at(5.5);near(e.hp,730.5);at(6.5);near(e.hp,727);at(7.5);near(e.hp,723.5)
attack(a,e,30);at(8.5);near(e.hp,693.5,'no new burns after five second window')
reset();a.hp=400;s=start({{id='E-c4',load=1}});attack(a,e,100);at(10);near(e.hp,900,'no stale burn backlog')
reset();a.hp=100;s=start({{id='E-c4',load=2}});eq(s.cards[1].remaining,1);a.hp=100;at(11.9);eq(s.cards[1].remaining,1);at(12);eq(s.cards[1].remaining,0);near(a.hp,350,'second burn grant after shared cooldown')
reset();a.hp=400;s=start({{id='E-c4',load=1}})
attack(a,e,10);at(.5);attack(a,e,10);at(1)
local burns=0;for _,hit in ipairs(damageLog)do if hit.tag=='card_burn' then burns=burns+1 end end
eq(burns,1,'rapid attack refresh preserves next burn tick')
reset();a.hp=400;s=start({{id='E-c4',load=1}});attack(a,e,120)
at(1.03);at(2.02);at(3.01);near(e.hp,838,'frame jitter does not cancel final burn tick')
-- Aggregate team health excludes dead roster bodies; rune center is lowest living body.
reset();a.position=Vector(2000,0,0);a.hp=900;b.hp=400;local nearby=unit(3,false);nearby.position=Vector(450,0,0)
local distant=unit(3,false);distant.position=Vector(501,0,0)
s=start({{id='E-c7',load=3}});eq(#damageLog,0);a.hp=700;at(1);near(e.hp,680);near(nearby.hp,680);near(distant.hp,1000);eq(s.cards[1].remaining,2)
at(20);near(e.hp,680,'rune first crossing only')
reset();a.alive=false;a.hp=0;s=start({{id='E-c7',load=1}});near(e.hp,1000,'dead body excluded from team maximum');b.hp=500;at(1);near(e.hp,880)
-- Three spatial plasma waves per pulse, each hits once outward and once inward.
reset();RandomInt=function(lo,hi) return math.floor((lo+hi)/2) end
s=start({{id='D-f1',load=1}});at(2.9);eq(#damageLog,0);at(3);eq(#s.waves,3);near(e.hp,760)
at(4);near(e.hp,760,'outward pass cannot repeat');at(6.34);near(e.hp,280,'return pass plus next three waves')
for _,hit in ipairs(damageLog) do eq(hit.tag,'card_storm');eq(hit.attacker.endlessCardSource,true) end
reset();s=start({{id='D-f1',load=3}});at(1);eq(#s.waves,3);eq(s.cards[1].pulse_at,2)
-- A moving target crosses the expanding ring even when its final distance is behind it.
reset();s=start({{id='D-f1',load=1}});at(3)
local mover=unit(3,false);mover.position=Vector(600,0,0);at(3+400/1200)
mover.position=Vector(300,0,0);at(3+460/1200)
for _,wave in ipairs(s.waves)do eq(wave.hits[1][mover],true,'moving segment intersects expanding ring')end
-- Wall uses a finite rectangle; moving through it between ticks still creates one illusion.
reset();s=start({{id='D-f3',load=2}});at(3);eq(stat(e,'move_speed'),-50)
local wallCount=0;local wallIllusion
for u,entry in pairs(s.spawned) do wallCount=wallCount+1;wallIllusion=u;eq(entry.kind,'wall_illusion');eq(u:GetTeamNumber(),2);eq(u:IsIllusion(),true);eq(u.original,e);eq(u.illusionKV.outgoing_damage,-20);eq(u.illusionKV.incoming_damage,100);eq(entry.expires,11) end
eq(wallCount,1);at(3.1);local n=0;for _ in pairs(s.spawned) do n=n+1 end;eq(n,1,'one illusion per hero per wall')
local crossing=unit(3,true);crossing.position=Vector(0,100,0);at(3.2);crossing.position=Vector(0,-100,0);at(3.3)
n=0;for _ in pairs(s.spawned) do n=n+1 end;eq(n,2,'wall catches crossing segment')
Effects.Stop(game);eq(wallIllusion.removed,true)
reset();for i=1,30 do unit(3,true) end;s=start({{id='D-f3',load=3}});at(3)
local capped=0;for _,entry in pairs(s.spawned)do if entry.kind=='wall_illusion' then capped=capped+1 end end
eq(capped,24,'wall cap shared across enemies and wall instances');at(6)
capped=0;for _,entry in pairs(s.spawned)do if entry.kind=='wall_illusion' then capped=capped+1 end end;eq(capped,24)
-- Den retains native neutral skills, imposes a shared cap, cleans up on expiry.
reset();s=start({{id='W-f2',load=1}});for t=2,16,2 do at(t) end
n=0;for u,entry in pairs(s.spawned) do n=n+1;eq(entry.kind,'den');eq(u.endlessCardSummon,true);eq(u.gold,0);eq(u.xp,0);assert(u.name:find('neutral')) end;eq(n,8)
at(18);n=0;for _ in pairs(s.spawned) do n=n+1 end;eq(n,8,'expired den unit replaced')
reset();s=start({{id='W-f2',load=3}});at(2);for u in pairs(s.spawned) do eq(u.name,'npc_dota_neutral_granite_golem') end
RandomInt=nil
-- Native den descendants inherit the card parent's lifetime through either owner
-- API, even in reverse discovery order; ordinary hero summons stay independent.
local function denFamily()
    reset();s=start({{id='W-f2',load=1},{id='W-g3',load=1}});at(2)
    local parent;for u in pairs(s.spawned) do parent=u end
    local grandchild=unit(2,false);local child=unit(2,false)
    function grandchild:GetOwner() return child end
    function child:GetOwnerEntity() return parent end
    local unrelated=unit(2,false);function unrelated:GetOwnerEntity() return a end
    local cycleA,cycleB=unit(2,false),unit(2,false)
    function cycleA:GetOwnerEntity() return cycleB end
    function cycleB:GetOwner() return cycleA end
    -- A cycle on one API must not hide a tracked parent on the other.
    function child:GetOwner() return grandchild end
    return parent,child,grandchild,unrelated,cycleA,cycleB
end
local parent,child,grandchild,unrelated,cycleA,cycleB=denFamily()
at(2.1)
eq(s.spawned[child].expires,s.spawned[parent].expires);eq(s.spawned[grandchild].expires,s.spawned[parent].expires)
eq(child.endlessCardSummon,true);assert(child.orders and grandchild.orders,'descendants receive normal attack orders')
eq(s.spawned[unrelated],nil);eq(s.spawned[cycleA],nil);eq(s.spawned[cycleB],nil)
local remove=UTIL_Remove
UTIL_Remove=function(u) Effects.Death(game,{unit=u,attacker=e});remove(u) end
at(17)
for _,u in ipairs({parent,child,grandchild}) do eq(u.removed,true);eq(u.endlessCardCleanup,true);eq(s.spawned[u],nil) end
eq(s.friendly_deaths,0,'expiry does not grant growth or rebirth rewards')
for _,entry in pairs(s.spawned) do assert(entry.kind~='beast','cleanup cannot spawn beast forms') end
assert(not unrelated.removed and not cycleA.removed and not cycleB.removed)
UTIL_Remove=remove
parent,child,grandchild,unrelated,cycleA,cycleB=denFamily()
-- Stop must discover this family without an intervening card Tick.
eq(s.spawned[child],nil);eq(s.spawned[grandchild],nil)
Effects.Stop(game)
for _,u in ipairs({parent,child,grandchild}) do eq(u.removed,true);eq(u.endlessCardCleanup,true) end
assert(not unrelated.removed and not cycleA.removed and not cycleB.removed)
-- Native hazard thinkers are outside HERO/BASIC queries but share card ancestry cleanup.
reset();s=start({{id='W-f2',load=1}});at(2)
local denParent;for u,entry in pairs(s.spawned)do if entry.kind=='den' then denParent=u end end
local hazard=unit(2,false);function hazard:IsOther()return true end;function hazard:GetOwnerEntity()return denParent end
local unrelatedHazard=unit(2,false);function unrelatedHazard:IsOther()return true end;function unrelatedHazard:GetOwnerEntity()return a end
local oldEntities=Entities
Entities={FindAllByClassname=function(_,name)assert(name=='npc_dota_thinker');return {hazard,unrelatedHazard}end}
at(2.1);eq(s.spawned[hazard].passive,true);eq(hazard.orders,nil,'thinkers never receive attack orders');eq(s.spawned[unrelatedHazard],nil)
Effects.Stop(game);eq(hazard.removed,true);eq(unrelatedHazard.removed,nil);Entities=oldEntities
-- Oil grants its initial barrier before its own amp; existing passive amp still applies.
reset();a.hp=600;s=start({{id='D-g5',load=3},{id='D-c2',load=1},{id='E-g4',load=1}})
near(s.unit_state[a].shields['D-c2'].amount,112);eq(stat(a,'shield_amp'),70);eq(stat(a,'heal_amp'),30)
cast(a);near(s.unit_state[a].shields['E-g4'].amount,102);at(10);eq(stat(a,'shield_amp'),40)
-- Native finite barriers have typed extra capacity, one grant per lifetime/refresh.
local function nativeBarrier(u,name,amount,kind,duration)
    local ability={GetSpecialValueFor=function() return amount end}
    local m={expires=clock+duration,created=clock}
    function m:GetName() return name end
    function m:GetAbility() return ability end
    function m:GetRemainingTime() return self.expires-clock end
    function m:GetCreationTime() return self.created end
    u.mods[name]=m;return m
end
reset();s=start({{id='D-g5',load=3},{id='E-g7',load=1}})
local pipe=nativeBarrier(a,'modifier_item_pipe_barrier',200,'magic',10);at(.1)
near(Effects.AbsorbNative(game,a,{damage=100,damage_type=DAMAGE_TYPE_PHYSICAL},'magic'),0,'pipe bonus cannot absorb physical')
near(Effects.AbsorbNative(game,a,{damage=50,damage_type=DAMAGE_TYPE_MAGICAL},'magic'),-50)
at(.2);near(Effects.AbsorbNative(game,a,{damage=100,damage_type=DAMAGE_TYPE_MAGICAL},'magic'),-30,'poll cannot refill barrier')
pipe.expires=11;at(1);near(Effects.AbsorbNative(game,a,{damage=100,damage_type=DAMAGE_TYPE_MAGICAL},'magic'),-80,'native refresh creates new grant')
near(e.hp,960,'fire pulse remains independent of native bonus capacity')
a.mods.modifier_item_pipe_barrier=nil;at(2);near(e.hp,920,'native removal does not disable pulse')
local custom=nativeBarrier(a,'test_barrier',0,'all',5)
Effects.RegisterBarrier('test_barrier',function() return 300,'all' end);at(2.1)
near(Effects.Absorb(game,a,{damage=150,damage_type=DAMAGE_TYPE_PURE}),-120,'registered extension barrier')
custom.expires=2.1;at(2.2);near(Effects.Absorb(game,a,{damage=100,damage_type=DAMAGE_TYPE_PURE}),0)
-- Event-time shield grants must reject oil amplification that expired since the last Tick.
reset();a.hp=600;s=start({{id='D-c2',load=1},{id='E-g4',load=1}})
near(s.unit_state[a].shields['D-c2'].amount,80);eq(stat(a,'shield_amp'),30)
clock=10.01;cast(a);near(s.unit_state[a].shields['E-g4'].amount,60,'expired oil cannot amplify a cast shield')
for _,passive in ipairs({false,true})do
 reset();a.hp=600;local entries={{id='D-c2',load=1}};if passive then entries[#entries+1]={id='D-g5',load=3}end
 s=start(entries);clock=10.01;nativeBarrier(a,'modifier_item_pipe_barrier',100,'magic',10)
 near(Effects.AbsorbNative(game,a,{damage=100,damage_type=DAMAGE_TYPE_MAGICAL},'magic'),passive and -40 or 0,'native grant uses current passive amp only')
end
-- Every native registry type uses the matching stage; Solar's armor-only modifier is ignored.
reset();s=start({{id='D-g5',load=3}})
local registryCases={
    {'modifier_abaddon_aphotic_shield',DAMAGE_TYPE_PURE},
    {'modifier_ember_spirit_flame_guard',DAMAGE_TYPE_MAGICAL},
    {'modifier_tinker_defense_matrix',DAMAGE_TYPE_PURE},
    {'modifier_item_pavise_shield',DAMAGE_TYPE_PHYSICAL},
}
for _,case in ipairs(registryCases) do
    local mod=nativeBarrier(a,case[1],100,'all',10);a.hp=1000
    ApplyDamage({attacker=e,victim=a,damage=50,damage_type=case[2],damage_flags=0})
    near(a.hp,990,case[1]..' bonus capacity consumed by modifier callback')
    a.mods[case[1]]=nil;Effects.Refresh(game)
end
nativeBarrier(a,'modifier_item_solar_crest_armor_addition',100,'physical',10);a.hp=1000;attack(e,a,50);near(a.hp,950,'solar armor is not a second barrier')
local creep=unit(2,false);Effects.Refresh(game)
local cp=nativeBarrier(creep,'modifier_item_pipe_barrier',100,'magic',10)
function cp:GetAbility() return {GetSpecialValueFor=function(_,key) return key=='barrier_block_creep' and 50 or 100 end} end
near(Effects.AbsorbNative(game,creep,{damage=100,damage_type=DAMAGE_TYPE_MAGICAL},'magic'),-20,'pipe uses native creep capacity')
-- Amp changes neither refill consumed capacity nor retroactively augment old grants.
local fresh=nativeBarrier(a,'modifier_item_pavise_shield',100,'physical',10);Effects.Refresh(game)
near(Effects.AbsorbNative(game,a,{damage=20,damage_type=DAMAGE_TYPE_PHYSICAL},'physical'),-20)
s.by_id['D-g5'].load=1;Effects.Refresh(game)
near(Effects.AbsorbNative(game,a,{damage=100,damage_type=DAMAGE_TYPE_PHYSICAL},'physical'),-20,'grant retains original amp')
-- Strong echo retains native illusion identity and the engine spell/item exceptions.
reset();a.items[0]=CreateItem('item_blink',a,a);a.items[0].cd=4
s=start({{id='D-g3',load=2,hero=a.name},{id='E-g3',load=1}});a.alive=false;Effects.Death(game,{unit=a,attacker=e})
local echo;for u,entry in pairs(s.forms) do echo=u;eq(entry.source,a);eq(entry.expires,8) end
assert(echo);eq(echo:IsIllusion(),true);eq(echo.illusionKV.outgoing_damage,0);eq(echo.illusionKV.incoming_damage,0);near(echo.maxhp,1200)
local identity=echo.mods.modifier_endless_card_echo
eq(identity:GetIsIllusion(),1);eq(identity:GetModifierStrongIllusion(),1);eq(identity:GetModifierSuperIllusionWithUltimate(),1);eq(identity:GetModifierSuperIllusionWithItems(),1)
eq(echo.items[0].cd,4);at(1);eq(echo.orders,nil,'echo reserved for native AI orders');at(8);eq(echo.removed,true);eq(next(s.forms),nil)
-- Rebirth forms preserve intrinsic overrides without counting card preparation bonuses twice.
for _,id in ipairs({'D-g3','A-g2'}) do
 reset();a.basehp=2500;a:CalculateStatBonus();a.damage_min=123;a.damage_max=145;a.armor=7;a.bat=1.3
 s=start({{id=id,load=1,hero=a},{id='E-g3',load=1},{id='E-f3',load=1,hero=a}})
 local expected=a:GetMaxHealth();a.alive=false;Effects.Death(game,{unit=a,attacker=e})
 local form;for u,entry in pairs(s.spawned) do if entry.original==a then form=u end end
 assert(form);eq(form.basehp,2500);eq(form:GetMaxHealth(),expected);eq(form:GetHealth(),expected)
 eq(form.damage_min,123);eq(form.damage_max,145);eq(form.armor,7);eq(form.bat,1.3)
end
-- All static scalar definitions expose all three levels without being lost during aggregation.
for id,definition in pairs(Effects.definitions) do
    if definition.type~='consumable' then
        for level=1,3 do
            reset();s=start({{id=id,load=level,hero=a.name}})
            local recipient=definition.target=='friendly' and a or e
            for _,effect in ipairs(definition.effects) do
                if effect.stat~='health' and effect.stat~='health_pct' and effect.stat~='mana' and effect.stat~='mana_pct' and effect.stat~='field_heal_amp' then
                    local expected=effect.values[level]
                    if id=='C-f4' and level==3 and effect.stat=='health_regen' then expected=expected*1.15 end
                    near(stat(recipient,effect.stat),expected,id..' Lv'..level..' '..effect.stat)
                end
            end
        end
    end
end
Effects.Stop(game)
-- Actual spatial effects own visual creation and fight-stop cleanup.
local created,destroyed,released=0,0,0
ParticleManager={CreateParticle=function()created=created+1;return created end,SetParticleControl=function()end,
 DestroyParticle=function()destroyed=destroyed+1 end,ReleaseParticleIndex=function()released=released+1 end}
reset();s=start({{id='D-f1',load=1},{id='D-f3',load=1}});at(3)
eq(created,4,'three rings and one wall create native visuals');Effects.Stop(game)
eq(destroyed,4);eq(released,4);Effects.Stop(game);eq(destroyed,4,'repeat stop cannot destroy twice');ParticleManager=nil
print('endless-card-effects: '..count..' supported, '..unsupported..' explicit exclusions; '..assertions..' assertions passed')
