-- Fixed player-configured offsets, not a skill-delay or hit-probability model.
local Context = require("tactics/condition_context")
local P = {}
local samples = setmetatable({}, {__mode="k"})

function P.Observe(units, now)
    if type(now) ~= "number" then return end
    for _, unit in ipairs(units or {}) do
        local pos = Context.Call(unit, "GetAbsOrigin")
        if pos and type(pos.x)=="number" and type(pos.y)=="number" then
            local old = samples[unit]
            if not old or now ~= old.time then
                local sample = {x=pos.x, y=pos.y, time=now}
                if old then
                    local dt = now-old.time
                    local dx,dy = pos.x-old.x,pos.y-old.y
                    local length = math.sqrt(dx*dx+dy*dy)
                    local speed = tonumber(Context.Call(unit,"GetIdealSpeed")) or 550
                    -- Discard stale observations and teleports rather than aiming along them.
                    if dt > 0 and dt <= 0.5 and length > 0.5 and length <= math.max(550,speed)*dt+64 then
                        sample.dx,sample.dy = dx/length,dy/length
                    end
                end
                samples[unit] = sample
            end
        end
    end
end

function P.Enabled(rule)
    local direction = (rule.target or {}).prediction_direction
    return direction == "forward" or direction == "backward"
end

function P.Point(rule, anchor, now)
    local pos = anchor:GetAbsOrigin()
    local target = rule.target or {}
    local distance = tonumber(target.prediction_distance) or 200
    if distance == 0 then return pos end
    if distance ~= distance or distance < 0 or distance > 3000 then return nil end
    local sample = samples[anchor]
    local dx,dy
    if sample and type(now)=="number" and now >= sample.time and now-sample.time <= 0.5 then
        dx,dy = sample.dx,sample.dy
    end
    if not dx then
        local facing = Context.Call(anchor,"GetForwardVector")
        if not facing then return nil end
        local length = math.sqrt(facing.x*facing.x+facing.y*facing.y)
        if length <= 0 then return nil end
        dx,dy = facing.x/length,facing.y/length
    end
    if target.prediction_direction == "backward" then distance = -distance end
    local point = Vector(pos.x+dx*distance,pos.y+dy*distance,pos.z)
    if type(GetGroundPosition)=="function" then point=GetGroundPosition(point,anchor) end
    return point
end
return P
