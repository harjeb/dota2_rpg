-- Edda changes native ability maxima and scaling as well as base intellect.
-- Preserve the actual Winter Wyvern during campaign roster rebuilds; recreating
-- it and merely SetLevel(saved) cannot reproduce those native upgrades.
local Edda = { HERO="npc_dota_hero_winter_wyvern", ITEM="item_eldwurms_edda" }
local function live(u) return u and (not u.IsNull or not u:IsNull()) end
local function managed(game, hero)
    if not live(hero) or not hero.GetUnitName or hero:GetUnitName()~=Edda.HERO then return nil end
    if hero.lineupHeroName~=Edda.HERO and hero.benchHeroName~=Edda.HERO then return nil end
    return game.heroData and game.heroData[Edda.HERO]
end
function Edda.KeepForRespawn(game, hero)
    local data=managed(game,hero)
    if not data then return false end
    data.edda_retained_unit=hero
    return true
end
function Edda.TakeRetained(game, name, position)
    local data=game.heroData and game.heroData[name]
    local hero=data and data.edda_retained_unit
    if name~=Edda.HERO or not live(hero) then return nil end
    data.edda_retained_unit=nil
    local Lifecycle = require("issue_fixes.hero_lifecycle_log")
    Lifecycle.Event(game,"retained_before_respawn",Lifecycle.Snapshot(hero))
    if hero.IsAlive and not hero:IsAlive() then hero:RespawnHero(false,false) end
    Lifecycle.Event(game,"retained_before_cleanup",Lifecycle.Snapshot(hero))
    hero.rpgDeathBeforeRespawn=nil
    if hero.Stop then hero:Stop() end
    if hero.GetAbilityCount then
        for slot=0,hero:GetAbilityCount()-1 do
            local ability=hero:GetAbilityByIndex(slot)
            if live(ability) and ability.GetToggleState and ability:GetToggleState() and ability.ToggleAbility then
                ability:ToggleAbility()
            end
        end
    end
    if hero.FindAllModifiers then
        for _,modifier in ipairs(hero:FindAllModifiers() or {}) do
            local temporary=modifier.GetDuration and modifier:GetDuration()>=0
            local debuff=modifier.IsDebuff and modifier:IsDebuff()
            if (temporary or debuff) and modifier.Destroy then modifier:Destroy() end
        end
    end
    if hero.SetAbsOrigin then hero:SetAbsOrigin(position) end
    -- Reuse may cross lineup/bench boundaries. PrepareBattleHero owns the new
    -- role and must not inherit the previous role's preparation modifier.
    hero.lineupHeroName,hero.benchHeroName=nil,nil
    for _,name in ipairs({"modifier_rpg_prepare_bench","modifier_invulnerable","modifier_rooted","modifier_disarmed","modifier_silence"}) do
        hero:RemoveModifierByName(name)
    end
    -- Native RespawnHero can leave permanent, non-debuff fountain protection
    -- on this reused entity. End that known spawn protection during preparation;
    -- duration/debuff cleanup above deliberately preserves native Edda growth.
    hero:RemoveModifierByName("modifier_fountain_invulnerability")
    Lifecycle.Event(game,"retained_after_cleanup",Lifecycle.Snapshot(hero))
    return hero
end
function Edda.BeforeRestore(game, hero)
    local data=managed(game,hero)
    if not data then return end
    if data.edda_seen then
        local saved={}
        for _,item in pairs(data.inventory_entities or {}) do saved[item]=true end
        for slot=0,16 do
            local item=hero:GetItemInSlot(slot)
            if live(item) and item:GetAbilityName()==Edda.ITEM and not saved[item] then
                hero:TakeItem(item)
                item:RemoveSelf()
            end
        end
    end
    data.edda_seen=true
end
function Edda.Consume(game, hero, item)
    if not managed(game,hero) or not live(item) or item:GetAbilityName()~=Edda.ITEM then return false,"not_owned",0 end
    -- Arena snapshots cannot yet serialize the native Edda ability-scaling
    -- state. Reject before consumption, never silently export a weaker team.
    if game.arena and game.arena.mode=="arena" then return false,"edda_arena_unavailable",0 end
    if not hero.ConsumeItem then return false,"unavailable",0 end
    game.itemSaleInProgress=true
    local ok=pcall(hero.ConsumeItem,hero,item)
    game.itemSaleInProgress=nil
    if not ok or live(item) then return false,"sale_failed",0 end
    local data=managed(game,hero)
    data.edda_consumed=true
    if game.CaptureHeroAbilities then game:CaptureHeroAbilities(hero) end
    if game.SyncHeroInventoryFromUnit then game:SyncHeroInventoryFromUnit(hero) end
    return true,"consumed",0
end
return Edda
