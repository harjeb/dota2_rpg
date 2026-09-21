-- Reviewed native sustained casts which do not report IsChanneling after wind-up.
-- Observe the caster modifier, never a fixed duration, cooldown or projectile effect.
local Context = require("tactics/condition_context")
local SustainedCast = {}
function SustainedCast.ActiveAbility(unit)
    if Context.Call(unit, "HasModifier", "modifier_snapfire_mortimer_kisses") == true then
        return "snapfire_mortimer_kisses"
    end
    return nil
end
return SustainedCast
