-- Match-local server authority. Clients submit intent, never card values or ownership.
local Catalog = require('endless.card_catalog')
local Effects = require('endless.card_effects')
local Json = require('lib.json')
local Cards = {}
local STARTERS = {'E-g8', 'C-g1', 'D-g2', 'A-g1', 'W-g1'}
local function copy(t)
    if type(t) ~= 'table' then return t end
    local out = {}; for k,v in pairs(t) do out[k] = copy(v) end; return out
end
local function short(name) return tostring(name):gsub('^npc_dota_hero_', '') end
local function whole(n) return type(n)=='number' and n==n and n%1==0 end
local function keys(t) local out={};for k in pairs(t) do out[#out+1]=k end;table.sort(out);return out end
local function owned(game,id) return game.endlessCards.cards[id] end
local function location(game,id)
    for slot,value in pairs(game.endlessCards.slots) do if value==id then return slot end end
end
local function inventoryCount(game)
    local n=0;for id in pairs(game.endlessCards.cards) do if not location(game,id) then n=n+1 end end;return n
end
local function activeHero(game,id)
    for _,name in ipairs(game.lineup or {}) do if short(name)==id then return name end end
end
local function acquire(game,id)
    local c=owned(game,id)
    if c then
        c.copies=c.copies+1;c.level=math.min(3,c.copies)
        if c.copies>3 then c.plus=math.min(99,c.copies-3) end
    else
        if inventoryCount(game)>=24 then return false end
        c=copy(Catalog[id]);c.copies=1;c.level=1;c.load=1;c.plus=0
        game.endlessCards.cards[id]=c
    end
    return true
end
function Cards.Ensure(game)
    local run=tostring(game.endlessRunId or 1)
    if not game.endlessCards or game.endlessCards.run_id~=run then
        game.endlessCards={run_id=run,revision=0,cards={},slots={},points={element=0,civilization=0,divine=0,abyss=0,wild=0},requests={}}
        game.endlessPurchases=0
        for _,id in ipairs(STARTERS) do assert(Effects.definitions[id],id);acquire(game,id) end
    end
    local s=game.endlessCards
    if s.wave~=(game.endlessWave or 1) then
        s.wave=game.endlessWave or 1;s.offers={};s.bought={};game.endlessPurchases=0
        local pool=keys(Effects.definitions)
        -- Deterministic frozen per-wave offers; retries and recovery never reroll.
        for i=1,5 do s.offers[i]=pool[((s.wave-1)*5+i-1)%#pool+1] end
        s.revision=s.revision+1
    end
    return s
end
function Cards.Budget(game)
    local total=0
    for _,name in ipairs(game.lineup or {}) do total=total+math.max(1,tonumber((game.heroData[name] or {}).level) or 1) end
    return total
end
function Cards.Used(game)
    local total=0
    for _,id in pairs(game.endlessCards.slots) do local c=owned(game,id);total=total+({1,5,10})[c.load] end
    return total
end
function Cards.Validate(game)
    Cards.Ensure(game)
    for slot,id in pairs(game.endlessCards.slots) do
        local hero,kind=slot:match('^([^:]+):([^:]+)$')
        if not activeHero(game,hero) or kind~='general' or not Effects.definitions[id] or not owned(game,id) then return '配装与当前上阵英雄不一致，请先卸卡' end
    end
    if Cards.Used(game)>Cards.Budget(game) then return 'COST 超出预算，请降低装载等级或卸卡' end
end
function Cards.Snapshot(game)
    local s=Cards.Ensure(game);local heroes={};local cards={}
    for _,name in ipairs(game.lineup or {}) do
        local id=short(name);heroes[#heroes+1]={id=id,name=id,level=math.max(1,tonumber((game.heroData[name] or {}).level) or 1)}
    end
    for _,id in ipairs(keys(s.cards)) do cards[#cards+1]=copy(s.cards[id]) end
    local bought={};for _,index in ipairs(keys(s.bought)) do if s.bought[index] then bought[#bought+1]=index end end
    return {run_id=s.run_id,revision=s.revision,wave=s.wave,cards=cards,heroes=heroes,slots=copy(s.slots),points=copy(s.points),gold=game:GetGoldBalance(),purchases=game.endlessPurchases or 0,offers=copy(s.offers),bought=bought,phase=game.phase=='setup' and 'prepare' or 'locked',supported=keys(Effects.definitions),combat={cards={}}}
end
function Cards.Publish(game,player)
    local data=Cards.Snapshot(game)
    -- Runtime carries entity handles internally; only status fields cross the wire.
    data.combat={cards={}}
    for _,c in ipairs((game.endlessCardCombat or {}).cards or {}) do
        data.combat.cards[#data.combat.cards+1]={id=c.id,remaining=c.remaining,next_trigger=c.next_trigger,active_until=c.active_until}
    end
    if not player and PlayerResource and game.playerId and game.playerId>=0 then player=PlayerResource:GetPlayer(game.playerId) end
    if player then CustomGameEventManager:Send_ServerToPlayer(player,'rpg_card_state',{state_json=Json.encode(data)}) end
end
local function owner(game,source,payload)
    if type(payload)~='table' or tonumber(payload.PlayerID)~=game.playerId or game.playerId<0 then return false end
    if not EntIndexToHScript or not tonumber(source) then return false end
    local ok,player=pcall(EntIndexToHScript,tonumber(source))
    if not ok or not player or not player.GetPlayerID then return false end
    local resolved,id=pcall(player.GetPlayerID,player)
    return resolved and id==game.playerId
end
function Cards.Apply(game,a,source)
    local s=Cards.Ensure(game)
    if type(a)~='table' then return '无效请求' end
    if tostring(a.run_id or '')~=s.run_id or a.wave~=s.wave or a.revision~=s.revision then return '状态已更新，请重试' end
    if game.phase~='setup' or game.runComplete then return '只能在准备阶段调整卡牌' end
    local id=a.id;local c=owned(game,id)
    if a.type=='equip' then
        if not c or not Effects.definitions[id] then return '该卡尚未拥有或尚未实现' end
        local hero,kind=tostring(a.slot):match('^([^:]+):([^:]+)$')
        if not activeHero(game,hero) or kind~='general' then return '基础卡只能装备上阵英雄的通用槽' end
        local from=location(game,id);local replaced=s.slots[a.slot]
        if from==a.slot then return '卡牌已经在该槽位' end
        if from and replaced and inventoryCount(game)>=24 then return '卡库已满，请先腾出位置' end
        if from then s.slots[from]=nil end;s.slots[a.slot]=id
    elseif a.type=='unequip' then
        local from=c and location(game,id)
        if not from then return '卡牌未装备' end
        if inventoryCount(game)>=24 then return '卡库已满，请先腾出位置' end
        s.slots[from]=nil
    elseif a.type=='level' then
        if not c or not whole(a.level) or a.level<1 or a.level>c.level then return '该装载等级尚未解锁' end
        c.load=a.level
    elseif a.type=='buy' then
        local index=a.index
        if not whole(index) or index<0 or index>=#s.offers or s.bought[index] then return '报价已购买或不存在' end
        if (game.endlessPurchases or 0)>=3 then return '本波购买次数已用完' end
        id=s.offers[index+1]
        if not owned(game,id) and inventoryCount(game)>=24 then return '卡库已满，请先腾出位置' end
        if not game:SpendGold(100) then return '金币不足' end
        assert(acquire(game,id));s.bought[index]=true;game.endlessPurchases=(game.endlessPurchases or 0)+1
    elseif a.type=='exchange' then
        local def=Catalog[id]
        if not def or not Effects.definitions[id] then return '该卡尚未实现' end
        if (s.points[def.faction] or 0)<3 then return '需要 3 点对应阵营印记' end
        if not acquire(game,id) then return '卡库已满，请先腾出位置' end
        s.points[def.faction]=s.points[def.faction]-3
    elseif a.type=='confirm' then
        local err=Cards.Validate(game);if err then return err end
        game:OnStartBattle(source,{PlayerID=game.playerId})
        if game.phase~='fight' then return '请先招募并上阵英雄，等待敌军资源就绪' end
    else return '此操作尚未开放' end
    s.revision=s.revision+1
end
function Cards.Request(game,source,a)
    if not owner(game,source,a) then return end
    local s=Cards.Ensure(game)
    local err=Cards.Apply(game,a,source)
    if err then
        local p=PlayerResource:GetPlayer(game.playerId)
        if p then CustomGameEventManager:Send_ServerToPlayer(p,'rpg_card_error',{message=err}) end
    end
    Cards.Publish(game)
    if game.BroadcastShopState then game:BroadcastShopState() end
end
function Cards.Install(game)
    Cards.Ensure(game)
    CustomGameEventManager:RegisterListener('rpg_card_request_state',function(source,payload)
        if owner(game,source,payload) then Cards.Publish(game);require('endless.mode').Publish(game) end
    end)
    CustomGameEventManager:RegisterListener('rpg_card_action',function(source,payload) Cards.Request(game,source,payload) end)
    local start=game.OnStartBattle
    game.OnStartBattle=function(self,source,payload)
        if self.phase~='setup' then return end
        local err=Cards.Validate(self)
        if err then
            local p=PlayerResource:GetPlayer(self.playerId)
            if p then CustomGameEventManager:Send_ServerToPlayer(p,'rpg_card_error',{message=err}) end
            return
        end
        start(self,source,payload)
        if self.phase=='fight' then
            local snapshot={}
            for slot,id in pairs(self.endlessCards.slots) do snapshot[#snapshot+1]={id=id,load=owned(self,id).load,hero='npc_dota_hero_'..slot:match('^([^:]+)')} end
            Effects.Start(self,snapshot);self.endlessCards.revision=self.endlessCards.revision+1;Cards.Publish(self)
        end
    end
    local finish=game.EndBattle
    game.EndBattle=function(self,...)
        if self.phase=='fight' then Effects.Stop(self) end
        local result=finish(self,...);Cards.Publish(self);return result
    end
    local broadcast=game.BroadcastShopState
    game.BroadcastShopState=function(self,...)
        local result=broadcast(self,...);Cards.Publish(self);return result
    end
    local think=game.OnThink
    game.OnThink=function(self,...)
        local result=think(self,...)
        if self.phase=='fight' then
            Effects.Tick(self)
            local now=GameRules:GetGameTime()
            if now>=(self.endlessCardNextPublish or 0) then self.endlessCardNextPublish=now+1;Cards.Publish(self) end
        end
        return result
    end
    local recruit=game.OnShopBuy
    game.OnShopBuy=function(self,source,payload)
        if source~=nil and not owner(self,source,payload) then return end
        Cards.Ensure(self)
        if (self.endlessPurchases or 0)>=3 then return end
        local before=#self.ownedHeroes
        recruit(self,source,payload)
        if #self.ownedHeroes>before then
            self.endlessPurchases=(self.endlessPurchases or 0)+1
            self.endlessCards.revision=self.endlessCards.revision+1;Cards.Publish(self)
        end
    end
    local lineup=game.OnLineupSet
    game.OnLineupSet=function(self,source,payload)
        if source~=nil and not owner(self,source,payload) then return end
        Cards.Ensure(self)
        -- Preserve owned assets when heroes leave the field; block overflow rather than discard.
        local previous=copy(self.lineup);local slots=copy(self.endlessCards.slots)
        lineup(self,source,payload)
        local removed={}
        for slot,id in pairs(self.endlessCards.slots) do if not activeHero(self,slot:match('^([^:]+)')) then removed[#removed+1]=slot end end
        if inventoryCount(self)+#removed>24 then
            self.lineup=previous;self.endlessCards.slots=slots;self:RespawnPlayerRoster();self:BroadcastShopState()
        else for _,slot in ipairs(removed) do self.endlessCards.slots[slot]=nil end end
        self.endlessCards.revision=self.endlessCards.revision+1;Cards.Publish(self)
    end
end
return Cards
