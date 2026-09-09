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
local function root(game,unit)
    local roster={}
    for _,team in pairs(game.battleManager and game.battleManager.teamHeroes or {}) do
        for _,hero in ipairs(team) do roster[hero]=true end
    end
    if roster[unit] then return nil end
    local owner=call(unit,"GetCloneSource") or call(unit,"GetOwnerEntity") or call(unit,"GetOwner")
    local seen={}
    for _=1,8 do
        if not valid(owner) or seen[owner] then return nil end
        if roster[owner] then return owner end
        seen[owner]=true
        owner=call(owner,"GetOwnerEntity") or call(owner,"GetOwner")
    end
end
local excluded={npc_dota_ember_spirit_remnant=true,npc_dota_elder_titan_ancestral_spirit=true}
function Summons.OnSpawn(game,unit)
    if not valid(unit) or call(unit,"IsTempestDouble")==true or excluded[call(unit,"GetUnitName")] then return false end
    -- Native projectiles, attached parasites and stationary hero soldiers own
    -- their own behavior. Do not disable their acquisition or redirect them.
    if call(unit,"IsControllableByAnyPlayer")==false then return false end
    if call(unit,"IsRealHero")==true and call(unit,"IsIllusion")~=true and call(unit,"IsClone")~=true then return false end
    local owner=root(game,unit)
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
local function issue(game,order)
    local gate=game.tacticBridge and game.tacticBridge.orderGate
    if gate then gate:Execute(order) end
end
function Summons.Clear(game)
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
            end
        end
    end
    for unit,state in pairs(game.managedSummons or {}) do
        local owner=root(game,unit)
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
                if target and call(unit,"GetAttackTarget")~=target then
                    issue(game,{UnitIndex=unit:entindex(),OrderType=DOTA_UNIT_ORDER_ATTACK_TARGET,TargetIndex=target:entindex(),Queue=false})
                end
            end
        end
    end
end
return Summons
