-- RPG Jinada income: enemy units need no player wallet. Native damage/cooldown
-- stay on Jinada; its gold special is zeroed server-side to prevent two payouts.
local M = {}
local NAME = "modifier_rpg_jinada_income"
local ABILITY = "bounty_hunter_jinada"
local function call(u, method, ...)
    if u and u[method] then return u[method](u, ...) end
end
local function valid(u) return u ~= nil and call(u,"IsNull") ~= true end
function M.Attach(game, hero)
    if not valid(hero) or call(hero,"GetUnitName") ~= "npc_dota_hero_bounty_hunter"
        or call(hero,"GetTeamNumber") ~= DOTA_TEAM_GOODGUYS
        or (not hero.lineupHeroName and not hero.benchHeroName)
        or call(hero,"IsIllusion") == true then return end
    hero.rpgJinadaGame = game
    if call(hero,"HasModifier",NAME) then return end
    LinkLuaModifier(NAME,"issue_fixes/jinada_income",LUA_MODIFIER_MOTION_NONE)
    hero:AddNewModifier(hero,nil,NAME,{})
    -- Existing native intrinsic modifiers may cache their specials on creation.
    local ability = hero:FindAbilityByName(ABILITY)
    local intrinsic = call(ability,"GetIntrinsicModifierName")
    local modifier = intrinsic and call(hero,"FindModifierByName",intrinsic)
    if modifier and modifier.ForceRefresh then modifier:ForceRefresh() end
end

modifier_rpg_jinada_income = class({})
local C = modifier_rpg_jinada_income
function C:IsHidden() return true end
function C:IsPurgable() return false end
function C:RemoveOnDeath() return false end
function C:DeclareFunctions()
    return {MODIFIER_PROPERTY_OVERRIDE_ABILITY_SPECIAL, MODIFIER_PROPERTY_OVERRIDE_ABILITY_SPECIAL_VALUE,
        MODIFIER_EVENT_ON_ORDER, MODIFIER_EVENT_ON_ATTACK_START, MODIFIER_EVENT_ON_ATTACK_RECORD,
        MODIFIER_EVENT_ON_ATTACK, MODIFIER_EVENT_ON_ATTACK_LANDED, MODIFIER_EVENT_ON_ATTACK_RECORD_DESTROY,
        MODIFIER_EVENT_ON_TAKEDAMAGE}
end
function C:OnCreated() self.records = {} end
function C:GetModifierOverrideAbilitySpecial(event)
    if IsServer() and not self.readingNative and event.ability_special_value == "gold_steal"
        and call(event.ability,"GetAbilityName") == ABILITY then return 1 end
    return 0
end
function C:GetModifierOverrideAbilitySpecialValue() return 0 end
function C:Ability()
    return self:GetParent():FindAbilityByName(ABILITY)
end
function C:Eligible(target)
    local hero = self:GetParent()
    local game = hero.rpgJinadaGame
    return game and game.phase == "fight" and valid(target) and target ~= hero
        and call(target,"GetTeamNumber") ~= call(hero,"GetTeamNumber")
        and call(hero,"GetPlayerOwnerID") == game.playerId
        and call(hero,"IsIllusion") ~= true and call(hero,"PassivesDisabled") ~= true
end
function C:Amount(ability)
    -- Re-enter only this modifier's override to retain native talents and other
    -- native special-value adjustments. Clients still show the original value.
    self.readingNative = true
    local ok, amount = pcall(ability.GetSpecialValueFor,ability,"gold_steal")
    self.readingNative = false
    if not ok then return 0 end
    return math.max(0,math.floor(tonumber(amount) or 0))
end
function C:Candidate(target)
    local ability = self:Ability()
    if not self:Eligible(target) or not valid(ability) or ability:GetLevel() <= 0
        or not ability:IsCooldownReady() then return end
    if call(ability,"GetAutoCastState") ~= true and self.manualTarget ~= target then return end
    return {target=target, amount=self:Amount(ability)}
end
function C:OnOrder(event)
    if not IsServer() or event.unit ~= self:GetParent() then return end
    if event.order_type == DOTA_UNIT_ORDER_CAST_TARGET and call(event.ability,"GetAbilityName") == ABILITY then
        self.manualTarget = event.target
    elseif event.order_type ~= DOTA_UNIT_ORDER_ATTACK_TARGET or event.target ~= self.manualTarget then
        self.manualTarget = nil
    end
end
function C:OnAttackStart(event)
    if not IsServer() or event.attacker ~= self:GetParent() then return end
    self.windup = self:Candidate(event.target)
end
function C:OnAttackRecord(event)
    if not IsServer() or event.attacker ~= self:GetParent() or event.record == nil then return end
    local candidate = self.windup
    self.windup = nil
    if event.no_attack_cooldown == true or event.no_attack_cooldown == 1
        or event.process_procs == false or event.process_procs == 0 then return end
    if not candidate or candidate.target ~= event.target then candidate = self:Candidate(event.target) end
    if candidate and self:Eligible(event.target) then
        self.records[event.record] = candidate
    end
    self.manualTarget = nil
end
function C:OnAttack(event)
    if not IsServer() or event.attacker ~= self:GetParent() then return end
    local candidate = self.records[event.record]
    if not candidate then return end
    candidate.released = true
    -- Readiness belongs to the native ability. An independent addon timer would
    -- incorrectly block cooldown refreshes and no-cooldown talents.
end
function C:Pay(target, amount, source)
    if amount <= 0 or not self:Eligible(target) then return end
    local hero = self:GetParent()
    local game = hero.rpgJinadaGame
    game:AddGold(amount)
    if SendOverheadEventMessage and OVERHEAD_ALERT_GOLD then
        SendOverheadEventMessage(call(PlayerResource,"GetPlayer",game.playerId),OVERHEAD_ALERT_GOLD,hero,amount,nil)
    end
    print(string.format("[JinadaIncome] source=%s target=%s gold=%d balance=%d",
        source,tostring(call(target,"GetUnitName")),amount,game:GetGoldBalance()))
end
function C:OnAttackLanded(event)
    if not IsServer() or event.attacker ~= self:GetParent() or event.record == nil then return end
    local candidate = self.records[event.record]
    self.records[event.record] = nil -- Claim before wallet callbacks can re-enter.
    if candidate and candidate.released and candidate.target == event.target then
        self:Pay(event.target,candidate.amount,"attack")
    end
end
function C:OnAttackRecordDestroy(event)
    if IsServer() and event.attacker == self:GetParent() and event.record ~= nil then self.records[event.record] = nil end
end
function C:OnTakeDamage(event)
    if not IsServer() or event.attacker ~= self:GetParent() or (tonumber(event.damage) or 0) <= 0
        or call(event.inflictor,"GetAbilityName") ~= "bounty_hunter_shuriken_toss"
        or call(self:GetParent(),"HasScepter") ~= true then return end
    local ability = self:Ability()
    if valid(ability) and ability:GetLevel() > 0 then
        self:Pay(event.unit,self:Amount(ability),"scepter_shuriken")
    end
end
return M
