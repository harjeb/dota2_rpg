local Tiny = {}
local function call(unit, method, ...)
    if unit == nil or unit[method] == nil then return nil end
    local ok,value=pcall(unit[method],unit,...)
    if ok then return value end
end
local function valid(unit) return unit ~= nil and call(unit,"IsNull") ~= true end
function Tiny.Clear(game)
    for _,state in pairs(game.tinyTrees or {}) do
        if valid(state.tree) then call(state.tree,"CutDown",DOTA_TEAM_NEUTRALS or 4) end
    end
    game.tinyTrees,game.treeGrabBusy={},{}
end
function Tiny.OnThink(game)
    game.treeGrabBusy={}
    if game.phase ~= "fight" then return end
    local gate=game.tacticBridge and game.tacticBridge.orderGate
    if gate == nil or type(CreateTempTree) ~= "function" or type(GetTreeIdForEntityIndex) ~= "function" then return end
    local now=GameRules:GetGameTime()
    game.tinyTrees=game.tinyTrees or {}
    for _,team in pairs(game.battleManager.teamHeroes or {}) do
        for _,hero in ipairs(team) do
            if valid(hero) and call(hero,"GetUnitName")=="npc_dota_hero_tiny" and call(hero,"IsAlive") == true then
                local state=game.tinyTrees[hero] or {}
                game.tinyTrees[hero]=state
                local ability=call(hero,"FindAbilityByName","tiny_tree_grab")
                local held=call(hero,"HasModifier","modifier_tiny_tree_grab") == true
                if held then
                    state.tree=nil
                elseif (state.untilTime or 0)>now then
                    game.treeGrabBusy[hero]=true
                elseif not (hero.rpgTacticsEvents and hero.rpgTacticsEvents.exclusive_movement)
                    and valid(ability) and (tonumber(call(ability,"GetLevel")) or 0)>0
                    and call(ability,"IsHidden") ~= true and call(ability,"IsActivated") ~= false
                    and call(ability,"IsCooldownReady") == true and call(ability,"IsFullyCastable") == true
                    and call(hero,"IsStunned") ~= true and call(hero,"IsFrozen") ~= true and call(hero,"IsSilenced") ~= true
                    and call(hero,"IsOutOfGame") ~= true and call(hero,"IsCommandRestricted") ~= true
                    and call(hero,"IsChanneling") ~= true and call(hero,"IsUsingAbility") ~= true
                    and now >= (state.retryAt or 0) then
                    state.retryAt=now+1
                    if not valid(state.tree) or call(state.tree,"IsStanding") == false then
                        local position=hero:GetAbsOrigin()
                        local ok,tree=pcall(CreateTempTree,Vector(position.x+48,position.y,position.z),2)
                        if ok and valid(tree) then state.tree=tree end
                    end
                    if valid(state.tree) and call(state.tree,"entindex") ~= nil then
                        local converted, treeId = pcall(GetTreeIdForEntityIndex,state.tree:entindex())
                        local ok, accepted = false, false
                        if converted and type(treeId)=="number" and treeId>=0 then
                            ok, accepted=pcall(function() return gate:Execute({UnitIndex=hero:entindex(),
                                OrderType=DOTA_UNIT_ORDER_CAST_TARGET_TREE,TargetIndex=treeId,
                                AbilityIndex=ability:entindex(),Queue=false,PlayerID=game.playerId or 0}) end)
                        end
                        if ok and accepted == true then
                            if game.tacticBridge.RecordAuxiliaryAction then
                                game.tacticBridge:RecordAuxiliaryAction(hero,"tiny_tree_grab")
                            end
                            state.untilTime=now+math.max(.35,(tonumber(call(ability,"GetCastPoint")) or .2)+.15)
                            game.treeGrabBusy[hero]=true
                        end
                    end
                end
            end
        end
    end
end
return Tiny
