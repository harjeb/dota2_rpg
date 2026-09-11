-- Observed/declared names, not guessed modifier_<ability> strings.
local C=require("tactics/condition_context")
local M={observed={},count=0}
function M.Observe(unit)
    for _,mod in pairs(C.Call(unit,"FindAllModifiers") or {}) do
        local name=C.Call(mod,"GetName")
        if type(name)=="string" and name~="" and #name<=128 and not M.observed[name] and M.count<256 then
            M.observed[name]=true; M.count=M.count+1
        end
    end
end
function M.List(hero,ability)
    M.Observe(hero)
    local intrinsic=C.Call(ability,"GetIntrinsicModifierName")
    local out={}
    local names={}
    for name in pairs(M.observed) do names[#names+1]=name end
    table.sort(names)
    for index=1,math.min(#names,32) do out[names[index]]=1 end
    if type(intrinsic)=="string" and intrinsic~="" then out[intrinsic]=1 end
    return out
end
function M.Reset() M.observed={}; M.count=0 end
return M
