-- Shared flat wire contract for MainUI, child editors, snapshots and legacy saves.
local M = {}
M.fields = {"movement_mode", "movement_buff", "movement_trigger_ability", "movement_duration", "movement_distance", "movement_retarget", "movement_loop", "movement_interruptible", "movement_direction", "positioning_mode", "positioning_distance", "positioning_tolerance"}
local booleans = {movement_retarget=true, movement_loop=true, movement_interruptible=true}
local numbers = {movement_duration={0.1,60}, movement_distance={32,3000}, positioning_distance={0,3000}, positioning_tolerance={0,300}}
local enums = {movement_mode={follow=true,pass=true,orbit=true,cycle=true}, movement_direction={auto=true,cw=true,ccw=true}, positioning_mode={default=true,fixed=true,attack_range=true,cast_range=true}}
M.presets = {weaver_shukuchi="modifier_weaver_shukuchi", primal_beast_trample="modifier_primal_beast_trample"}
function M.Copy(source, target)
    for _, key in ipairs(M.fields) do
        local v = source[key]
        if v ~= nil and v ~= "" then
            if booleans[key] then
                if v == 0 or v == "0" or v == "false" then v = false
                elseif v == 1 or v == "1" or v == "true" then v = true end
            elseif numbers[key] then v = tonumber(v) or v end
            target[key] = v
        end
    end
    return target
end
function M.Validate(action)
    for _, key in ipairs(M.fields) do
        local v = action[key]
        if v ~= nil then
            if booleans[key] and type(v) ~= "boolean" then return false, "invalid_" .. key end
            if enums[key] and not enums[key][v] then return false, "invalid_" .. key end
            local bounds = numbers[key]
            if bounds and (type(v) ~= "number" or v ~= v or v < bounds[1] or v > bounds[2]) then return false, "invalid_" .. key end
            if key == "movement_buff" or key == "movement_trigger_ability" then
                if type(v) ~= "string" or #v > 256 or not v:match("^[%w_]+$") then return false, "invalid_" .. key end
            end
        end
    end
    if action.logical_id == "sustained_move" then
        if action.kind ~= "move" or not action.movement_buff then return false, "movement_buff_required" end
        action.movement_mode = action.movement_mode or "follow"
        action.movement_duration = action.movement_duration or 8
        action.movement_distance = action.movement_distance or 250
        action.movement_direction = action.movement_direction or "auto"
    end
    return true
end
return M
