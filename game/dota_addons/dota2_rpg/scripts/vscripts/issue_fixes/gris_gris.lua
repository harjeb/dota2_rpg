-- Gris-Gris is a one-time innate grant, not a shop item. Roster heroes are
-- recreated between stages; keep its bank and redemption state on heroData.
local Gris = { HERO = "npc_dota_hero_witch_doctor", ITEM = "item_grisgris" }
local COUNTER = "modifier_item_grisgris_counter"
local LAST_SLOT = 16
local function call(object, method, ...)
    if object == nil or object[method] == nil then return nil end
    local ok, value = pcall(object[method], object, ...)
    if ok then return value end
end
local function now() return GameRules:GetGameTime() end
local function stateFor(game, hero)
    if call(hero, "GetUnitName") ~= Gris.HERO then return nil end
    local data = game.heroData and game.heroData[Gris.HERO]
    if not data then return nil end
    data.grisGris = data.grisGris or { gold = 0 }
    return data.grisGris
end
local function counter(hero) return call(hero, "FindModifierByName", COUNTER) end
local function count(hero) return math.max(0, tonumber(call(counter(hero), "GetStackCount")) or 0) end
local function held(game, hero)
    local items = {}
    for slot = 0, LAST_SLOT do
        local item = call(hero, "GetItemInSlot", slot)
        if game:IsLiveItem(item) and call(item, "GetAbilityName") == Gris.ITEM then items[#items + 1] = item end
    end
    return items
end
local function remove(game, hero, item)
    if not game:IsLiveItem(item) then return end
    -- Never ConsumeItem a duplicate: that would pay out an unwanted grant.
    if game:IsItemHeldBy(hero, item, 0, LAST_SLOT) then call(hero, "RemoveItem", item)
    elseif type(UTIL_Remove) == "function" then UTIL_Remove(item) end
end

-- Compare cumulative native savings with one cumulative game-time clock. Do
-- not add a second tick to the native modifier: either source can advance the
-- same bank. This also works during the custom preparation phase.
function Gris.Update(game, hero)
    local state = stateFor(game, hero)
    if not state or state.consumed or not state.issued then return state end
    local time = now()
    if state.pendingCounterGold and counter(hero) then
        call(counter(hero), "SetStackCount", math.max(state.pendingCounterGold, count(hero)))
        state.pendingCounterGold = nil
    end
    local interval = tonumber(call(state.item, "GetSpecialValueFor", "gold_tick_interval")) or 3
    if interval <= 0 then interval = 3 end
    state.interval = interval
    state.started = state.started or time
    state.base = state.base or state.gold
    local elapsed = math.max(0, time - state.started)
    state.gold = math.max(state.gold, state.base + math.floor(elapsed / interval), count(hero))
    return state
end

function Gris.Capture(game, hero)
    local state = Gris.Reconcile(game, hero)
    if not state or state.consumed then return end
    Gris.Update(game, hero)
    state.remainder = math.max(0, now() - state.started) % (state.interval or 3)
    state.restoring = true
end

-- Called before ordinary inventory restore so a newly spawned innate grant
-- cannot fill a slot or overwrite the original saved entity.
function Gris.BeforeRestore(game, hero)
    local state = stateFor(game, hero)
    if not state then return end
    if state.issued then
        for _, item in ipairs(held(game, hero)) do
            if item ~= state.item or state.consumed then remove(game, hero, item) end
        end
        local data = game.heroData[Gris.HERO]
        local names, states, entities = {}, {}, {}
        local kept = false
        for index, name in ipairs(data.inventory or {}) do
            local item = (data.inventory_entities or {})[index]
            if name ~= Gris.ITEM or (not state.consumed and not kept
                and (item == state.item or not game:IsLiveItem(state.item))) then
                names[#names + 1] = name
                states[#states + 1] = (data.inventory_states or {})[index] or { name = name }
                entities[#names] = item
                if name == Gris.ITEM then kept = true end
            elseif name == Gris.ITEM then remove(game, hero, item) end
        end
        data.inventory, data.inventory_states, data.inventory_entities = names, states, entities
    end
    state.restoring = true
end

function Gris.Reconcile(game, hero)
    local state = stateFor(game, hero)
    if not state then return nil end
    local items = held(game, hero)
    if state.consumed then
        for _, item in ipairs(items) do remove(game, hero, item) end
        return state
    end
    local selected
    for _, item in ipairs(items) do if item == state.item then selected = item end end
    selected = selected or items[1]
    if not selected then return state end -- native innate may grant asynchronously
    local rebuilding = state.hero ~= hero or state.restoring
    if not state.issued then
        state.gold = math.max(state.gold, count(hero))
        state.base, state.started = state.gold, now()
    elseif not rebuilding then Gris.Update(game, hero) end
    for _, item in ipairs(items) do if item ~= selected then remove(game, hero, item) end end
    state.item, state.hero, state.issued = selected, hero, true
    if rebuilding then
        -- Native counter belongs to the removed hero, not the retained item.
        -- Preserve its bank, and the partial 3-second tick, on the new carrier.
        state.base = state.gold
        state.started = now() - (state.remainder or 0)
        state.pendingCounterGold = state.gold
        state.restoring, state.remainder = nil, nil
    end
    return Gris.Update(game, hero)
end

function Gris.OnKilled(game, killed)
    local data = game.heroData and game.heroData[Gris.HERO]
    local state = data and data.grisGris
    if not state then return end
    local lost = tonumber(call(PlayerResource, "GetGoldLostToDeath", game.playerId))
    if lost and state.lossSnapshot and killed == state.hero and not state.consumed then
        -- Only actual owner death losses are deposits. Reliable gold has no
        -- death loss; another roster hero sharing the wallet is not the owner.
        state.base = (state.base or state.gold) + math.max(0, lost - state.lossSnapshot)
        Gris.Update(game, killed)
    end
    state.lossSnapshot = lost
end

function Gris.OnThink(game)
    if not (game.heroData and game.heroData[Gris.HERO]) then return end
    local hero = game.FindOwnedHeroUnit and game:FindOwnedHeroUnit(Gris.HERO)
    if hero then
        local state = Gris.Reconcile(game, hero)
        if state then
            state.lossSnapshot = tonumber(call(PlayerResource, "GetGoldLostToDeath", game.playerId))
        end
        if state and state.lastBroadcast ~= state.gold then
            state.lastBroadcast = state.gold
            game.nativeShopTransactionPending = true
        end
    end
end

function Gris.Gold(game)
    local data = game.heroData and game.heroData[Gris.HERO]
    local state = data and data.grisGris
    return state and not state.consumed and state.gold or 0
end

-- Caller validates phase, player, exact entity/holder and pending purchases.
function Gris.Redeem(game, hero, item)
    local state = Gris.Reconcile(game, hero)
    if not state or state.consumed or state.item ~= item then return false, "not_owned", 0 end
    if hero.RemoveItem == nil then return false, "unavailable", 0 end
    Gris.Update(game, hero)
    local saved = state.gold
    local before = game:GetGoldBalance()
    game.itemSaleInProgress = true
    -- The RPG bank has one payout authority. Remove this exact owned item
    -- without invoking native ConsumeItem (whose native wallet credit may be
    -- delayed), then credit the saved bank once after confirmed destruction.
    pcall(hero.RemoveItem, hero, item)
    if game:IsLiveItem(item) then
        game.itemSaleInProgress = nil
        return false, "sale_failed", 0
    end
    state.consumed, state.item = true, nil
    game:AddGold(saved)
    game.itemSaleInProgress = nil
    game.nativeShopTransactionPending = true
    return true, "sold", math.max(0, game:GetGoldBalance() - before)
end

return Gris
