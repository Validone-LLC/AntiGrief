-- AntiGrief: optional Pawn scoring. Does nothing unless Pawn is loaded.
-- Pawn function names follow Pawn's public API; confirm them against the
-- Forever build's Pawn.lua before shipping (see Pawn integration).

local _, ns = ...
local Rules = ns.Rules

local function Available()
  local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Pawn")
  return (loaded and type(PawnGetItemData) == "function" and type(PawnGetSingleValueFromItem) == "function") and true or false
end
Rules.PawnAvailable = Available

local scaleCache = {}
local function ScalesForClass(classToken)
  if type(classToken) ~= "string" then return {} end
  if scaleCache[classToken] then return scaleCache[classToken] end
  local list = {}
  local all
  if type(PawnGetAllScalesEx) == "function" then
    local ok, res = pcall(PawnGetAllScalesEx)
    if ok then all = res end
  end
  if type(all) ~= "table" then all = {} end
  for _, s in ipairs(all) do
    local name = (type(s) == "table") and s.Name or s
    if type(name) == "string" and name:find(classToken, 1, true) then list[#list + 1] = name end
  end
  if #list > 0 then scaleCache[classToken] = list end -- don't cache before Pawn is ready
  return list
end

local function Score(link, scale)
  local ok, item = pcall(PawnGetItemData, link)
  if not ok or not item then return nil end
  local ok2, v = pcall(PawnGetSingleValueFromItem, item, scale)
  if ok2 and type(v) == "number" then return v end
end

-- Best score of an item across every scale for the class (nil = can't tell)
function Rules.PawnBestScore(link, classToken)
  if not Available() then return nil end
  local best
  for _, scale in ipairs(ScalesForClass(classToken)) do
    local v = Score(link, scale)
    if v and (not best or v > best) then best = v end
  end
  return best
end

-- Relative change vs their worst equipped item in the slot(s), best spec wins.
-- < 0 = worse under every spec. nil = can't tell (no Pawn, no scales, empty
-- slot); the caller then falls back to the item-level check, which also
-- treats an empty slot as an upgrade.
function Rules.PawnUpgradeCheck(link, who, slots)
  if not Available() or not who or not who.items or not slots then return nil end
  for _, slot in ipairs(slots) do
    if not who.items[slot] then return nil end -- empty slot: always an upgrade
  end
  local bestDelta
  for _, scale in ipairs(ScalesForClass(who.class)) do
    local new = Score(link, scale)
    local worst
    for _, slot in ipairs(slots) do
      local v = Score(who.items[slot], scale)
      if v and (not worst or v < worst) then worst = v end
    end
    if new and worst then
      local delta = (new - worst) / math.max(worst, 1)
      if not bestDelta or delta > bestDelta then bestDelta = delta end
    end
  end
  return bestDelta
end
