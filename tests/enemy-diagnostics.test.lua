local root = TEST_REPO_ROOT or "."
local lines, orders, time = {}, 0, 0
local nativePrint = print
print = function(line) lines[#lines+1]=line end
package.loaded["issue_fixes.runtime_log"] = {Write=function() error("ordinary trace budget exhausted") end}
GameRules = {GetGameTime=function() return time end}
DOTA_TEAM_BADGUYS = 3
ExecuteOrderFromTable = function() orders=orders+1; error("diagnostics issued an order") end
local function unit(index, name)
    local u = {index=index, name=name, alive=true, hp=100, x=0, reincarnating=false}
    function u:IsNull() return false end
    function u:entindex() return self.index end
    function u:GetUnitName() return self.name end
    function u:IsAlive() return self.alive end
    function u:IsReincarnating() return self.reincarnating end
    function u:GetHealth() return self.hp end
    function u:GetMaxHealth() return 100 end
    function u:GetAbsOrigin() return {x=self.x,y=0} end
    function u:GetAttackTarget() return self.target end
    function u:GetForceAttackTarget() return self.target end
    function u:Script_GetAttackRange() return 150 end
    function u:GetAbilityByIndex() error("unsafe ability enumeration") end
    function u:SetForceAttackTarget() orders=orders+1 end
    function u:MoveToTargetToAttack() orders=orders+1 end
    return u
end
local hero=unit(1,"npc_dota_hero_axe")
local boss=unit(2,"npc_rpg_boss")
local creep=unit(3,"npc_dota_neutral_centaur_khan")
local dummy=unit(4,"npc_rpg_skill_test_target")
local game={phase="setup", currentLevelId="ch01", battleManager={teamHeroes={[3]={hero,boss,creep,dummy}}}}
local M=dofile(root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/battle/enemy_diagnostics.lua")
local function tick(t) time=t; assert(pcall(M.OnThink,game)) end
local function contains(s)
    for _, line in ipairs(lines) do if line:find(s,1,true) then return true end end
    return false
end
tick(0)
assert(#lines==5)
for _, u in ipairs({hero,boss,creep,dummy}) do assert(contains("name="..u.name)) end
local n=#lines
tick(10); assert(#lines==n,"stable preparation must remain quiet")
game.phase="fight"; tick(11); assert(#lines==n+5,"phase logs all entries")
n=#lines
hero.x=10; hero.hp=90
tick(11.1); tick(12.99); assert(#lines==n,"positions and HP cannot bypass throttle")
tick(13); assert(#lines==n+4 and contains("delta=10.00"))
n=#lines
hero.alive=false; hero.reincarnating=true; tick(13.1)
assert(#lines==n+1 and contains("alive=0 reincarnating=1"))
hero.alive=true; hero.reincarnating=false; tick(13.2); assert(#lines==n+2)
hero.GetHealth=function() error("stale getter") end
hero.GetAbsOrigin=function() return {x="malformed",y=0} end
hero.target=setmetatable({}, {__index=function() error("invalid target") end})
hero.rpgTacticsEvents={attack={time=13}}
hero.rpg_neutral_attack_intent={owner="tactic",retries=2,requested=13,progress=12,blocked_until=14}
game.tacticBridge={tacticEngine={states={[1]={unit=hero,chase={target_index=2,rule_index=1,deadline=15}}}}}
tick(13.3)
assert(contains("hp=unknown maxhp=100.00 pos=unknown"))
assert(contains("releaseage=0.30") and contains("intent.owner=tactic intent.retry=2.00"))
assert(contains("chase=1 chase.target_index=2.00"))
local invalid=setmetatable({}, {__index=function() error("invalid handle") end})
game.battleManager.teamHeroes[3][5]=invalid
tick(13.4); assert(contains("entity=unknown name=unknown"))
n=#lines; tick(13.5); assert(#lines==n,"malformed entities cannot spam errors")
game.battleManager.teamHeroes[3][2]=unit(2,"npc_rpg_reused_entity")
tick(13.6); assert(contains("event=removed entity=2.00 name=npc_rpg_boss"))
assert(contains("event=added entity=2.00 name=npc_rpg_reused_entity"))
game.currentLevelId="ch02"; n=#lines; tick(13.7); assert(#lines==n+6)
game.phase="setup"; tick(14); n=#lines; tick(20); assert(#lines==n)
game.phase="fight"; tick(21); n=#lines; tick(0); assert(#lines==n+6,"clock reset is a new round")
-- Null handles must never reach another native getter.
invalid.IsNull=nil -- ordinary raw assignment; lookup remains hostile
local null=unit(9,"null")
null.IsNull=function() return true end
null.GetHealth=function() error("null native call") end
game.battleManager.teamHeroes[3][6]=null; tick(0.1)
print=function() error("logger unavailable") end
hero.alive=false; tick(0.2)
assert(pcall(M.OnThink,nil) and pcall(M.OnThink,{}))
assert(orders==0,"diagnostics must never submit orders")
print = function(line) lines[#lines+1]=line end
-- Ability probe must be inert unless explicitly enabled, and must report per-ability
-- level/cooldown/castability with a missing native API rather than throwing.
RPG_ENEMY_ABILITY_PROBE = true
local probeLines = #lines
local probe = unit(7,"npc_dota_neutral_centaur_khan")
probe.GetLevel=function() return 5 end
probe.SetLevel=nil
probe.GetAbilityCount=function() return 2 end
probe.abilities={
  { name="centaur_khan_war_stomp", level=1, cd=0, castable=true, mana=true, passive=false, hidden=false },
  { name="neutral_upgrade", level=1, cd=0, castable=false, mana=true, passive=true, hidden=false },
}
probe.GetAbilityByIndex=function(self,slot) return self.abilities[slot+1] end
for _, ability in ipairs(probe.abilities) do
    ability.GetAbilityName=function(self) return self.name end
    ability.GetLevel=function(self) return self.level end
    ability.GetCooldownTimeRemaining=function(self) return self.cd end
    ability.IsFullyCastable=function(self) return self.castable end
    ability.IsOwnersManaEnough=function(self) return self.mana end
    ability.IsPassive=function(self) return self.passive end
    ability.IsHidden=function(self) return self.hidden end
    ability.IsNull=function() return false end
end
game.battleManager.teamHeroes[3][7]=probe; tick(30)
assert(#lines>probeLines,"probe must emit a snapshot for the new unit")
assert(contains("unitlv=5.00") and contains("hasSetLevel=0 hasHeroLevelUp=0"))
-- text() 把空格转成下划线，所以技能字段之间是 "_" 而不是空格。
assert(contains("centaur_khan_war_stomp[lv=1.00_cd=0.00_cast=1_mana=1_passive=0_hidden=0]"))
assert(contains("neutral_upgrade[lv=1.00_cd=0.00_cast=0_mana=1_passive=1_hidden=0]"))
-- A unit whose ability API is entirely absent must degrade, not raise.
local bare = unit(8,"npc_dota_neutral_gnoll_assassin")
game.battleManager.teamHeroes[3][8]=bare; tick(31)
assert(contains("name=npc_dota_neutral_gnoll_assassin") and contains("abilities=none"))
RPG_ENEMY_ABILITY_PROBE = nil
print = nativePrint
print("PASS: enemy diagnostics roster, throttle, transitions, reuse, malformed getters, logger isolation, no orders, ability probe")
