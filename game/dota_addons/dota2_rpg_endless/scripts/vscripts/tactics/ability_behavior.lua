-- GetBehaviorInt overflows for native abilities carrying flags above bit 31
-- (e.g. Hammer of Purity returns -2147483648 instead of 137439088648).
-- Read the full numeric mask and test individual flags without 32-bit coercion.
local Behavior = {}

function Behavior.Read(ability)
    for _, method in ipairs({"GetBehavior", "GetBehaviorInt"}) do
        if ability ~= nil and ability[method] ~= nil then
            local ok, value = pcall(ability[method], ability)
            value = ok and tonumber(value) or nil
            if value ~= nil and value == value and value > -math.huge and value < math.huge then
                return value
            end
        end
    end
    return 0
end

function Behavior.HasFlag(value, flag)
    return type(value) == "number" and type(flag) == "number" and flag > 0
        and math.floor(value / flag) % 2 == 1
end

return Behavior
