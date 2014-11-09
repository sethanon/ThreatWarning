local Utility = {}
Utility.__index = Utility

-- Merge two tables together
function Utility:MergeTables(t1, t2)
  for k, v in pairs(t2) do
    if type(v) == "table" then
    if t1[k] then
        if type(t1[k] or false) == "table" then
          self:MergeTables(t1[k] or {}, t2[k] or {})
        else
          t1[k] = v
        end
    else
      t1[k] = {}
        self:MergeTables(t1[k] or {}, t2[k] or {})
    end
    else
      t1[k] = v
    end
  end
  return t1
end

-- Register Package
Apollo.RegisterPackage(Utility, "ThreatWarning:Utility", 1, {})