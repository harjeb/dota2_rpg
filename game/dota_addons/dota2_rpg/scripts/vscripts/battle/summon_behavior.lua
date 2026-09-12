local Summons={}
local function call(unit,method,...)
    if unit==nil then return nil end
    local ok,fn=pcall(function() return unit[method] end)
    if not ok or type(fn)~="function" then return nil end
    local success,value=pcall(fn,unit,...)
    if success then return value end
end
local function valid(unit) return unit~=nil and call(unit,"IsNull")~=true end
local function distance(a,b)
    local p,q=call(a,"GetAbsOrigin"),call(b,"GetAbsOrigin")
    if p==nil or q==nil then return math.huge end
    return math.sqrt((p.x-q.x)^2+(p.y-q.y)^2)
end
local function ownership(unit,roster)
    local seen={[unit]=true}
    local level={unit}
    for _=1,8 do
        local nextLevel={}
        for _,current in ipairs(level) do
            for _,method in ipairs({"GetCloneSource","GetOwnerEntity","GetOwner"}) do
                local owner=call(current,method)
                if valid(owner) and not seen[owner] then
                    if roster and roster[owner] then return owner,seen end
                    seen[owner]=true
                    nextLevel[#nextLevel+1]=owner
                end
            end
        end
        level=nextLevel
        if #level==0 then break end
    end
    return nil,seen
end
function Summons.ResolveOwner(game,unit)
    if not valid(unit) then return nil end
    local roster={}
    for _,team in pairs(game.battleManager and game.battleManager.teamHeroes or {}) do
        for _,hero in ipairs(team) do if valid(hero) then roster[hero]=true end end
    end
    if roster[unit] then return nil end
    local owner,ancestors=ownership(unit,roster)
    if owner then return owner end
    if call(unit,"IsIllusion")~=true then return nil end
    -- Native Conjure Image can inherit the hidden Wisp owner and report player
    -- ID -1. Match a unique fielded copy source through shared native ownership;
    -- player ID or hero name alone would also accept unrelated/bench units.
    local source
    for hero in pairs(roster) do
        if call(hero,"GetUnitName")==call(unit,"GetUnitName")
            and call(hero,"GetTeamNumber")==call(unit,"GetTeamNumber") then
            local _,heroAncestors=ownership(hero)
            heroAncestors[hero]=nil
            local shared=false
            for ancestor in pairs(heroAncestors) do
                if ancestor~=unit and ancestors[ancestor] then shared=true;break end
            end
            if shared then
                if source then return nil end
                source=hero
            end
        end
    end
    return source
end
local excluded={npc_dota_ember_spirit_remnant=true,npc_dota_elder_titan_ancestral_spirit=true}
function Summons.OnSpawn(game,unit)
    if not valid(unit) or call(unit,"IsTempestDouble")==true or excluded[call(unit,"GetUnitName")] then return false end
    -- Native projectiles, attached parasites and stationary hero soldiers own
    -- their own behavior. Do not disable their acquisition or redirect them.
    if call(unit,"IsControllableByAnyPlayer")==false then return false end
    if call(unit,"IsRealHero")==true and call(unit,"IsIllusion")~=true and call(unit,"IsClone")~=true then return false end
    local owner=Summons.ResolveOwner(game,unit)
    if not owner or call(owner,"GetTeamNumber")~=call(unit,"GetTeamNumber") then return false end
    local name=call(unit,"GetUnitName")
    local healing=name=="npc_dota_juggernaut_healing_ward"
    local attack=tonumber(call(unit,"GetAttackCapability"))
    if not healing and (attack==nil or attack==(DOTA_UNIT_CAP_NO_ATTACK or 0)) then return false end
    game.managedSummons=game.managedSummons or {}
    game.managedSummons[unit]={owner=owner,healing=healing,nextOrder=0}
    call(unit,"SetIdleAcquire",false)
    call(unit,"SetAcquisitionRange",0)
    return true
end
local function is_registered(game,unit)
    for _,team in pairs(game.battleManager and game.battleManager.teamHeroes or {}) do
        for _,member in ipairs(team) do if member==unit then return true end end
    end
    return false
end
-- 敌方召唤物（蛇棒、地狱火等）不属于受管召唤物：本模块只给玩家方下达指令。
-- 但它们同样必须在战斗结束时消失，否则会活到下一关，甚至打死准备区里的小精灵。
-- 只登记"非本关登记的敌方非英雄单位"，登记过的敌人和玩家单位一律不动。
-- 注意：npc_spawned 在 CreateUnitByName 期间同步触发，早于 battleManager:RegisterHero，
-- 所以 is_registered 在生成瞬间必然为假。除登记外还要看项目自己的敌方标记
-- （enemyRuleIndex），否则本关野怪会在准备阶段被当成召唤物清掉。
function Summons.TrackEnemySummon(game,unit)
    if not valid(unit) then return false end
    if call(unit,"GetTeamNumber")~=(DOTA_TEAM_BADGUYS or 3) then return false end
    if call(unit,"IsRealHero")==true then return false end
    -- enemyRuleIndex 是字段不是方法，不能用 call（它只转发函数）。
    if unit.enemyRuleIndex~=nil then return false end
    if is_registered(game,unit) then return false end
    game.enemySummons=game.enemySummons or {}
    game.enemySummons[unit]=true
    return true
end
function Summons.ClearEnemySummons(game)
    for unit in pairs(game.enemySummons or {}) do
        if valid(unit) then call(unit,"RemoveSelf") end
    end
    game.enemySummons={}
end
local function issue(game,order)
    local gate=game.tacticBridge and game.tacticBridge.orderGate
    return gate~=nil and gate:Execute(order)==true
end
function Summons.Clear(game)
    Summons.ClearEnemySummons(game)
    for unit in pairs(game.managedSummons or {}) do
        if valid(unit) then
            call(unit,"SetIdleAcquire",false)
            if call(unit,"IsRealHero")==true then
                issue(game,{UnitIndex=unit:entindex(),OrderType=DOTA_UNIT_ORDER_STOP,Queue=false})
            else call(unit,"RemoveSelf") end
        end
    end
    game.managedSummons={}
end
function Summons.OnThink(game)
    if game.phase~="fight" then Summons.Clear(game); return end
    local now=GameRules:GetGameTime()
    -- Some native abilities assign ownership just after npc_spawned. Revisit
    -- owned units periodically so those summons are not permanently missed.
    if now >= (game.nextSummonScan or 0) and type(FindUnitsInRadius)=="function" then
        game.nextSummonScan=now+.5
        local origin
        for _,team in pairs(game.battleManager.teamHeroes or {}) do
            if team[1] and valid(team[1]) then origin=team[1]:GetAbsOrigin(); break end
        end
        if origin then
            local ok,units=pcall(FindUnitsInRadius,DOTA_TEAM_GOODGUYS or 2,origin,nil,4000,
                DOTA_UNIT_TARGET_TEAM_BOTH or 3,DOTA_UNIT_TARGET_ALL or 55,
                DOTA_UNIT_TARGET_FLAG_INVULNERABLE or 0,FIND_ANY_ORDER or 0,false)
            for _,unit in ipairs(ok and units or {}) do
                if not (game.managedSummons or {})[unit] then Summons.OnSpawn(game,unit) end
                Summons.TrackEnemySummon(game,unit)
            end
        end
    end
    for unit,state in pairs(game.managedSummons or {}) do
        local owner=Summons.ResolveOwner(game,unit)
        if not valid(unit) or call(unit,"IsAlive")==false or not owner
            or call(owner,"GetTeamNumber")~=call(unit,"GetTeamNumber") then
            game.managedSummons[unit]=nil
        elseif now>=state.nextOrder and call(unit,"IsChanneling")~=true and call(unit,"IsUsingAbility")~=true
            and call(unit,"IsStunned")~=true and call(unit,"IsCommandRestricted")~=true and call(unit,"IsOutOfGame")~=true then
            state.nextOrder=now+.5
            local target
            if state.healing then
                if call(owner,"IsAlive")==true then target=owner end
                for _,hero in ipairs(game.battleManager.teamHeroes[unit:GetTeamNumber()] or {}) do
                    if valid(hero) and call(hero,"IsAlive")==true and call(hero,"IsRealHero")==true
                        and (target==nil or distance(unit,hero)<distance(unit,target)) then target=hero end
                end
                if target and distance(unit,target)>150 then
                    issue(game,{UnitIndex=unit:entindex(),OrderType=DOTA_UNIT_ORDER_MOVE_TO_TARGET,
                        TargetIndex=target:entindex(),Queue=false})
                elseif target then issue(game,{UnitIndex=unit:entindex(),OrderType=DOTA_UNIT_ORDER_STOP,Queue=false}) end
            elseif type(FindUnitsInRadius)=="function" then
                local ok,found=pcall(FindUnitsInRadius,unit:GetTeamNumber(),unit:GetAbsOrigin(),nil,4000,
                    DOTA_UNIT_TARGET_TEAM_ENEMY,(DOTA_UNIT_TARGET_HERO or 1)+(DOTA_UNIT_TARGET_BASIC or 2),
                    (DOTA_UNIT_TARGET_FLAG_FOW_VISIBLE or 0)+(DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES or 0),FIND_CLOSEST,false)
                for _,enemy in ipairs(ok and found or {}) do
                    if valid(enemy) and call(enemy,"IsAlive")~=false and call(enemy,"IsInvulnerable")~=true
                        and call(enemy,"IsAttackImmune")~=true and call(enemy,"IsOutOfGame")~=true
                        and call(enemy,"GetTeamNumber")~=unit:GetTeamNumber()
                        and (target==nil or distance(unit,enemy)<distance(unit,target)) then target=enemy end
                end
                -- GetAttackTarget may stay nil during native approach. Keep a
                -- successfully submitted chase instead of cancelling its order
                -- every half second; an idle unit or a new nearest target recovers.
                local current=call(unit,"GetAttackTarget")
                local pursuing=current==nil and state.attackTarget==target and call(unit,"IsIdle")==false
                if target and current~=target and not pursuing then
                    if issue(game,{UnitIndex=unit:entindex(),OrderType=DOTA_UNIT_ORDER_ATTACK_TARGET,TargetIndex=target:entindex(),Queue=false}) then
                        state.attackTarget=target
                    end
                elseif not target then state.attackTarget=nil end
            end
        end
    end
end
return Summons
