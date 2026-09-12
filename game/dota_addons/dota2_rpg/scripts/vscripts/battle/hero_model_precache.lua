-- 敌方英雄模型必须在地图加载期显式预加载。
-- 实测（本机 UI44 运行日志）：地图加载之后 PrecacheResource / PrecacheUnitByNameSync
-- 都会被原版拒绝——"must be passed a valid precache context"；PrecacheUnitByNameAsync
-- 的回调只是"已受理"（假英雄名也照样回调），回调返回时模型并不在缓存里。于是按需生成
-- 的敌方英雄请求到 models/heroes/... 时得到 "not in the system"，显示 ERROR 模型。
-- 唯一有效的上下文由引擎在 Precache(context) 期间提供，所以模型只能在这里加载。
local M = {}

-- 关卡表里出现过的敌方英雄单位名（按关卡顺序去重）。
function M.HeroNames(levels)
    local names, seen, ids = {}, {}, {}
    for id in pairs(type(levels) == "table" and levels or {}) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
    for _, id in ipairs(ids) do
        local level = levels[id]
        local enemies = type(level) == "table" and level.enemies or nil
        if type(enemies) == "table" then
            for _, enemy in pairs(enemies) do
                local unit = type(enemy) == "table" and enemy.unit or nil
                if type(unit) == "string" and unit:match("^npc_dota_hero_[%w_]+$") ~= nil and not seen[unit] then
                    seen[unit] = true
                    names[#names + 1] = unit
                end
            end
        end
    end
    return names
end

-- 每个英雄需要加载的资源：模型本体 + 它所在的整个目录。
-- 英雄模型是分件的独立文件（例如 models/heroes/drow/drow_cape.vmdl），
-- 原版会逐个请求它们，只加载本体不够。
function M.Resources(levels, heroModels)
    local out = {}
    for _, name in ipairs(M.HeroNames(levels)) do
        local model = type(heroModels) == "table" and heroModels[name] or nil
        if type(model) == "string" and model ~= "" then
            out[#out + 1] = { name = name, kind = "model", path = model }
            local folder = model:match("^(.*)/[^/]+$")
            if folder ~= nil then
                out[#out + 1] = { name = name, kind = "model_folder", path = folder }
            end
        end
    end
    return out
end

-- 逐个调用原生预加载；任何一次失败都不允许连累地图加载。返回值是尝试次数，
-- 原生拒绝不会抛错（只打日志），所以这里不做"成功"承诺。
function M.Apply(resources, context, precache)
    local applied = 0
    for _, resource in ipairs(resources or {}) do
        local ok = pcall(precache, resource.kind, resource.path, context)
        if ok then applied = applied + 1 end
    end
    return applied
end

return M
