-- Only shop snapshots use this transport. Native CEM serialization can fail without
-- throwing in Lua, so size is bounded BEFORE SendStateTo, never by pcall/retry.
local M = { CHUNK_BYTES = 256, MAX_CHUNKS = 512, SMALL_BUDGET = 512 }
local function quote(s)
    return '"' .. s:gsub('[%z\1-\31\\"]', function(c)
        return string.format('\\u%04x', string.byte(c))
    end) .. '"'
end
local function encode(v)
    local kind = type(v)
    if kind == 'string' then return quote(v), #v + 16 end
    if kind == 'number' then
        assert(v == v and v ~= math.huge and v ~= -math.huge, 'nonfinite shop value')
        return tostring(v), 16
    end
    if kind == 'boolean' then return tostring(v), 16 end
    assert(kind == 'table', 'unsupported shop value: ' .. kind)
    local keys, parts, budget = {}, {}, 32
    for k in pairs(v) do assert(type(k) == 'string', 'shop objects require string keys'); keys[#keys+1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local text, size = encode(v[k])
        parts[#parts+1] = quote(k) .. ':' .. text
        budget = budget + #k + 16 + size
    end
    return '{' .. table.concat(parts, ',') .. '}', budget
end
M.Encode = encode
function M.Send(game, player, snapshot)
    -- Counter belongs to the game instance, not the run; reconnect publications
    -- and small/large snapshots share exactly the same ordering domain.
    game.shopTransportRevision = (game.shopTransportRevision or 0) + 1
    snapshot.shop_revision = game.shopTransportRevision
    game.shopTransportSent = game.shopTransportSent or {}
    game.shopTransportSent[player or "broadcast"] = {revision=snapshot.shop_revision, generation=snapshot.rule_generation or 0}
    local text, budget = encode(snapshot)
    print(string.format("[RPGShopSync v=72] revision=%d generation=%s bytes=%d target=%s", snapshot.shop_revision, tostring(snapshot.rule_generation or 0), #text, player and "player" or "all"))
    if budget <= M.SMALL_BUDGET and #text <= M.SMALL_BUDGET then
        game:SendStateTo(player, 'rpg_shop_state', snapshot)
        return
    end
    assert(#text <= M.CHUNK_BYTES * M.MAX_CHUNKS - 3 * M.MAX_CHUNKS, 'shop snapshot exceeds transport limit')
    local chunks, pos = {}, 1
    while pos <= #text do
        local last = math.min(pos + M.CHUNK_BYTES - 1, #text)
        -- Never split a UTF-8 codepoint across native string fields.
        while last < #text and string.byte(text, last+1) >= 128 and string.byte(text, last+1) < 192 do last = last - 1 end
        chunks[#chunks+1] = text:sub(pos, last)
        pos = last + 1
    end
    for i, chunk in ipairs(chunks) do
        game:SendStateTo(player, 'rpg_shop_state_chunk', {
            version = 1, rule_generation = snapshot.rule_generation or 0,
            shop_revision = snapshot.shop_revision, index = i, count = #chunks, data = chunk,
        })
    end
end
-- The client probes with its last fully committed revision. Unlike a successful
-- Lua send call, this proves whether native transport reached the HUD.
function M.Request(game, payload)
    local id = payload and tonumber(payload.PlayerID)
    if id == nil or id ~= game.playerId or id < 0 then return end
    local player = PlayerResource:GetPlayer(id)
    if player == nil then return end
    local t = Time and Time() or os.clock()
    game.shopTransportRequests = game.shopTransportRequests or {}
    if t - (game.shopTransportRequests[id] or -math.huge) < 3 then return end
    game.shopTransportRequests[id] = t
    local sent = game.shopTransportSent or {}
    local latest = sent[player]
    local broadcast = sent.broadcast
    if broadcast and (not latest or broadcast.revision > latest.revision) then latest = broadcast end
    if latest and tonumber(payload.shop_revision) == latest.revision
        and tonumber(payload.rule_generation) == latest.generation then
        if game.shopTransportAcknowledged ~= latest.revision then
            print(string.format("[RPGShopSync v=72] committed player=%d revision=%d", id, latest.revision))
        end
        game.shopTransportAcknowledged = latest.revision
        return
    end
    -- Build current inventory again; never replay a pre-transfer cached mirror.
    game:BroadcastShopState(player)
end
return M
