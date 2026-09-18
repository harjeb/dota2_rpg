local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local Progression = require("battle.enemy_progression")
local function hero(level)
    local h = {level=level, points=0, abilities={}, learned={}, modifiers={}, calls=0}
    function h:GetLevel() return self.level end
    function h:IsRealHero() return true end
    function h:GetAbilityCount() return 26 end
    function h:GetAbilityByIndex(i) return self.abilities[i] end
    function h:GetAbilityPoints() return self.points end
    function h:SetAbilityPoints(n) self.points=n end
    function h:UpgradeAbility(a)
        assert(self.points > 0 and self.level >= a.required)
        assert(not self.refuse, "native refusal")
        a.level=1; self.learned[a.name]=true; self.points=self.points-1; self.calls=self.calls+1
    end
    function h:HasModifier(name) return self.modifiers[name] end
    function h:AddNewModifier(_, _, name) self.modifiers[name]=(self.modifiers[name] or 0)+1 end
    local function ability(name, required)
        local a={name=name,level=0,required=required}
        function a:IsNull() return false end
        function a:GetAbilityName() return self.name end
        function a:GetMaxLevel() return 1 end
        function a:GetLevel() return self.level end
        function a:SetLevel() error("talents must use native learning") end
        return a
    end
    h.abilities[0]=ability("zuus_arc_lightning",1)
    h.abilities[8]=ability("special_bonus_attributes",1)
    for i=1,8 do h.abilities[9+i*2]=ability("special_bonus_test_"..i,5+math.ceil(i/2)*5) end
    return h
end
for level=1,30 do
    local h=hero(level)
    Progression.TrainTalents(h)
    local expected=level==30 and 8 or math.max(0,math.floor((level-5)/5))
    assert(h.calls==expected, "talent count at "..level)
    for i=1,8 do
        assert((h.learned["special_bonus_test_"..i] or false)==
            (level==30 or (i%2==1 and level>=5+math.ceil(i/2)*5)))
    end
    assert(h.abilities[8].level==0 and h.abilities[0].level==0)
    assert(h.points==0)
    Progression.TrainTalents(h)
    assert(h.calls==expected, "repeated preparation must not relearn")
    Progression.ApplyUpgrades(h,{})
    assert((h.modifiers.modifier_item_aghanims_shard~=nil)==(level>=15))
    assert((h.modifiers.modifier_item_ultimate_scepter_consumed~=nil)==(level>=25))
    Progression.ApplyUpgrades(h,{})
    for _,count in pairs(h.modifiers) do assert(count==1) end
end
local existing=hero(25)
existing.abilities[13].level=1 -- preserve second choice of first tier
Progression.TrainTalents(existing)
assert(existing.abilities[11].level==0 and existing.calls==3)
existing.level=30
Progression.TrainTalents(existing)
assert(existing.calls==7)
local refused=hero(10); refused.refuse=true
Progression.TrainTalents(refused)
assert(refused.abilities[11].level==0 and refused.points==0)
for _,entry in ipairs({{quality_upgrades={}}, {quality_upgrades={"shard"}},
    {quality_upgrades={["1"]="scepter",["2"]="shard"}}}) do
    local h=hero(30)
    Progression.ApplyUpgrades(h,entry)
    local count=0; for _ in pairs(h.modifiers) do count=count+1 end
    local expected=0; for _ in pairs(entry.quality_upgrades) do expected=expected+1 end
    assert(count==expected, "explicit final encounter overrides curve")
end
local creep=hero(30); function creep:IsRealHero() return false end
Progression.ApplyUpgrades(creep,{})
assert(next(creep.modifiers)==nil, "creeps do not inherit hero upgrade curve")
local file=assert(io.open(root.."/game/dota_addons/dota2_rpg/scripts/vscripts/addon_game_mode.lua")); local source=file:read("*a"); file:close()
assert(source:find("EnemyProgression.ApplyUpgrades(unit, entry)",1,true))
assert(source:find("EnemyProgression.TrainTalents(hero)",1,true))
print("enemy-progression.test.lua: passed")
