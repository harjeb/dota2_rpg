-- Offline publication regression: real state serializers and capability sender,
-- native entities/capability discovery replaced with deterministic fixtures.
local root = TEST_REPO_ROOT or "."
local scripts = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/"
function class() local c = {}; c.__index = c; return c end
function Vector(x,y,z) return {x=x,y=y,z=z} end
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS = 2, 3
local catalog = dofile(scripts .. "tactics/ability_catalog.lua")
local resends = 0
local recruitSelections = {}
local modules = {
    ["battle/neutral_recruitment"] = {
        GetOptions = function() return {} end,
        Clear = function() end, OnThink = function() end, Precache = function() end,
        Select = function(game, hero, source, unit)
            recruitSelections[#recruitSelections+1] = {game=game, hero=hero, source=source, unit=unit}
            return true
        end,
    },
    ["issue_fixes.shop_transport"] = dofile(scripts .. "issue_fixes/shop_transport.lua"),
    ["battle.unit_helpers"] = { IsValidUnit = function(u) return u ~= nil end },
    ["battle/buyback"] = { IsEligible = function() return false end },
    ["tactics/ability_catalog"] = catalog,
    ["tactics/rule_snapshot"] = {
        HeroKey = function(_,h) return h.key end,
        TargetActor = function(_,_,h) return h.key end,
        IsDeveloperMode = function() return false end,
        ForHero = function(bridge,h) return bridge.saved[h.key] or {} end,
    },
    ["tactics/ability_capability"] = {
        ForAction = function() return { enabled = 1 } end,
        Source = function(h) return h end,
    },
    ["tactics/condition_context"] = { Call = function(h,k) return h[k](h) end },
    ["battle.run_results"] = { Resend = function() resends = resends + 1 end },
    ["battle.run_lives"] = { MAX_LIVES = 5, Ensure = function() return {remaining=4} end },
    ["issue_fixes/gris_gris"] = { Gold = function() return 0 end },
    ["issue_fixes/runtime_log"] = { Write = function() end },
    ["issue_fixes.runtime_log"] = { Write = function() end },
}
require = function(name) return modules[name] or { Install = function() end } end
dofile(scripts .. "addon_game_mode.lua")
local timers, schedules, sent = {}, 0, {}
GameRules = { GetGameTime = function() return 10 end, GetGameModeEntity = function() return {
    SetContextThink = function(_,name,callback,delay)
        assert(delay > 0, "must leave entity reconstruction update")
        schedules = schedules + 1; timers[name] = callback
    end,
} end }
local players = {[0]={GetPlayerID=function() return 0 end}, [1]={GetPlayerID=function() return 1 end}}
PlayerResource = { GetPlayer = function(_,id) return players[id] end,
    SetCustomTeamAssignment = function() end }
local chunks = {}
local Json = dofile(scripts .. "lib/json.lua")
local function receive(player,event,data)
    if event == "rpg_shop_state_chunk" then
        local key = player or "all"
        chunks[key] = chunks[key] or {}
        chunks[key][data.index] = data.data
        if data.index ~= data.count then return end
        data = Json.decode(table.concat(chunks[key])); chunks[key] = nil
        event = "rpg_shop_state"
    end
    sent[#sent+1]={event=event,data=data,player=player}
end
CustomGameEventManager = {
    Send_ServerToAllClients = function(_,event,data) receive(nil,event,data) end,
    Send_ServerToPlayer = function(_,player,event,data) receive(player,event,data) end,
}
local function tick()
    local callback = assert(timers.Dota2RpgStatePublications)
    local again = callback()
    if not again then timers.Dota2RpgStatePublications = nil end
    return again
end
local function hero(id)
    return { key="hero_"..id, entindex=function() return id end,
        GetUnitName=function() return "npc_dota_hero_axe" end,
        GetAbilityCount=function() return 0 end }
end
local function roster(first,count)
    local units={}; for i=first,first+count-1 do units[#units+1]=hero(i) end; return units
end
local saved = {{ action="attack", condition="health_pct", value=40 }}
local game = setmetatable({
    playerId=0, phase="setup", currentLevelId="ch12", ruleGeneration=7, settlementGeneration=3,
    ownedHeroes={}, lineup={}, heroData={}, scrollStock={}, shopCosts={}, orderedLevels={"ch12"},
    tacticBridge={getRules=function() end, saved={hero_101=saved}},
    battleManager={teamHeroes={[2]=roster(1,5),[3]=roster(10,4)}},
    dataLoader={GetLevel=function() return {} end},
    GetGoldBalance=function() return 500 end, GetStashUnit=function() end,
    GetRefreshCost=function() return 100 end, GetScrollRemaining=function() return 2 end,
    BuildBattleState=function(self) return {phase=self.phase, rule_generation=self.ruleGeneration} end,
    damageStats={startedAt=0, Snapshot=function() return {{total=123}} end},
    EnsureGoldWalletInitialized=function(self) self.walletCalls=(self.walletCalls or 0)+1 end,
}, CDota2RpgDemo)
local function resetPublications(defer)
    if defer then game:DeferStatePublications() end
    -- Model overlapping preparation-completion, roster and inventory
    -- publications. This intentionally stresses duplicate requests; it does
    -- not claim every synchronous reset invokes all three in this order.
    game:BroadcastHeroInfo()
    game.battleManager.teamHeroes[2]=roster(101,5)
    game:BroadcastHeroInfo(); game:BroadcastShopState()
    game:BroadcastHeroInfo(); game:BroadcastShopState()
    game:BroadcastLevelInfo(); game:BroadcastBattleState()
end
resetPublications(false)
local baseline=#sent
sent={}; resetPublications(true)
assert(#sent==0, "no state serialization/send during rebuild")
assert(schedules==1, "one timer for overlapping publications")
-- A newer rule generation/edit and an async stage completion must win over
-- any state that existed when publication was requested.
game.stageLoading=true
assert(tick()==0.1 and #sent==0)
game.ruleGeneration=8; saved[1].value=55
game.stageLoading=false
assert(tick()==nil)
local optimized=#sent
assert(baseline==88 and optimized==31, "measured event count changed")
local revisions={}
for _,packet in ipairs(sent) do
    assert(not packet.player)
    if packet.event=="rpg_hero_slots" then
        assert(packet.data.rule_generation==8)
        assert(packet.data.hero_index>=10, "removed allies never published")
        revisions[packet.data.hero_index]=packet.data.capability_revision
        if packet.data.hero_index==101 then
            assert(packet.data.rules==saved and packet.data.rules[1].value==55)
        end
    end
end
for _,packet in ipairs(sent) do
    if packet.event=="rpg_action_capability" then
        assert(packet.data.revision==revisions[packet.data.hero_index], "capability revision pairs with slots")
    end
end
-- Connection lifecycle and duplicate HUD requests share a single targeted
-- rebuild; empty/missing client state must be restored even with no mutations.
sent={}; local before=schedules
game:OnPlayerConnectFull({PlayerID=0})
game:OnRequestBattleState(nil,{PlayerID=0}); game:OnRequestBattleState(nil,{PlayerID=0})
assert(schedules==before+1 and #sent==0)
tick()
assert(#sent==32 and resends==1)
for _,packet in ipairs(sent) do assert(packet.player==players[0], "reconnect must not flood other clients") end
assert(game.ruleGeneration==8 and game.tacticBridge.saved.hero_101==saved)
assert(game.walletCalls==1)
-- A global flush satisfies the same reconnect family only once.
sent={}; game:DeferStatePublications(); game:BroadcastHeroInfo(); game:RequestStateRecovery(0); tick()
assert(#sent==32)
-- Current result can be reconstructed, without replaying rewards. Stale
-- settlements are excluded after a new run changes the generation.
game.phase="result"; game.lastSettlement={settlement_generation=3,gold=123}
sent={}; game:RequestStateRecovery(1); tick()
assert(#sent==33 and sent[#sent].event=="rpg_settlement" and sent[#sent].player==players[1])
game.settlementGeneration=4
sent={}; game:RequestStateRecovery(1); tick(); assert(#sent==32)
-- A vanished player is skipped, not accidentally converted to broadcast.
sent={}; game:RequestStateRecovery(1); players[1]=nil; tick(); assert(#sent==0)
-- Failed serializers retain pending work and cannot cancel other families.
local serialize=game.BroadcastShopState
local fail=true
game.BroadcastShopState=function(self,player)
    if fail then fail=false; error("transient native handle") end
    return serialize(self,player)
end
sent={}; game:RequestStateRecovery(0)
assert(tick()==0.1 and #sent==31)
assert(tick()==nil and #sent==63)
assert(game.statePublicationFlushing==nil and game.statePublications==nil)
-- Engine-side roster entry point activates batching before assembly callbacks.
local assemblyRan=false
game.AwaitEnemyResources=function() return true end
game.AssembleLevelEnemies=function(self)
    assemblyRan=true; assert(self.stageLoading)
    self:BroadcastHeroInfo(); self:BroadcastHeroInfo(); return true
end
game.PreloadNextLevel=function() end
sent={}; assert(game:SpawnLevelEnemies("ch12"))
assert(assemblyRan and #sent==0 and game.preparedEnemyLevel=="ch12")
tick(); assert(#sent==28)
-- Nonreplaceable replies remain immediate while state is pending.
sent={}; game:DeferStatePublications(); game:BroadcastHeroInfo()
CustomGameEventManager:Send_ServerToPlayer(players[0],"rpg_item_sell_result",{ok=1})
CustomGameEventManager:Send_ServerToAllClients("rpg_settlement",{settlement_generation=99})
assert(#sent==2 and sent[1].event=="rpg_item_sell_result" and sent[2].event=="rpg_settlement")
tick(); assert(#sent==30)
-- Exercise the real event boundary; backend selection semantics have their own suite.
local ally = game.battleManager.teamHeroes[2][1]
local function selectPayload(owner, generation, entity)
    return {PlayerID=owner, rule_generation=generation, hero_entindex=entity,
        source_name="chen_holy_persuasion", unit_name="npc_dota_neutral_kobold"}
end
sent={}
assert(game:OnNeutralRecruitSelect(nil, selectPayload(1, 8, ally:entindex())) == false)
assert(game:OnNeutralRecruitSelect(nil, selectPayload(0, 7, ally:entindex())) == false)
assert(game:OnNeutralRecruitSelect(nil, selectPayload(0, 8, 999)) == false)
assert(game:OnNeutralRecruitSelect(nil, selectPayload(0, 8, 10)) == false, "enemy roster is unauthorized")
assert(#recruitSelections == 0 and #sent == 0, "rejected requests never select or publish")
assert(game:OnNeutralRecruitSelect(nil, selectPayload(0, 8, ally:entindex())) == true)
assert(#recruitSelections == 1)
local selection = recruitSelections[1]
assert(selection.game == game and selection.hero == ally)
assert(selection.source == "chen_holy_persuasion" and selection.unit == "npc_dota_neutral_kobold")
local reply = sent[#sent]
assert(reply.event == "rpg_neutral_recruit_result" and reply.player == players[0])
assert(reply.data.success == 1 and reply.data.rule_generation == 8 and reply.data.hero_entindex == ally:entindex())
local multi=selectPayload(0,8,ally:entindex())
multi.unit_names={["1"]="npc_dota_neutral_kobold",["2"]="npc_dota_neutral_kobold"}
assert(game:OnNeutralRecruitSelect(nil,multi))
assert(recruitSelections[2].unit==multi.unit_names,"Chen list is forwarded intact instead of legacy scalar")
multi.unit_names={};assert(game:OnNeutralRecruitSelect(nil,multi))
assert(recruitSelections[3].unit==multi.unit_names,"empty Chen list clears all choices")
multi.source_name="enchantress_enchant"
assert(game:OnNeutralRecruitSelect(nil,multi))
assert(recruitSelections[4].unit==multi.unit_name,"other sources retain scalar selection contract")
print(string.format("state-publication: reset %d -> %d events; reconnect 32 targeted; generation, settlement, async, retry PASS",baseline,optimized))
