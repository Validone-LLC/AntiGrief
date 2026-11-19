-- AntiGrief: decides whether an item is a reasonable Need for a given player

local _, ns = ...
local D = ns.Data
local Rules = {}
ns.Rules = Rules

-- Level requirement gap: up to LEVEL_GAP_LOW levels short is Low, up to
-- LEVEL_GAP_MEDIUM is Medium, more is High
local LEVEL_GAP_LOW, LEVEL_GAP_MEDIUM = 2, 5

-- Fixed order so finding text doesn't depend on pairs() iteration order
local BUCKET_ORDER = { "STR", "AGI", "INT", "CASTER", "AP", "TANK" }

local function Labels(set, skip)
  local out = {}
  for _, b in ipairs(BUCKET_ORDER) do
    if set[b] and not (skip and skip[b]) then out[#out + 1] = D.BUCKET_LABEL[b] or b end
  end
  return out
end

local function ItemLevelOf(link)
  if not link then return nil end
  local getDetailed = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
  local ilvl = getDetailed and getDetailed(link)
  if not ilvl or ilvl == 0 then ilvl = select(4, D.GetItemInfo(link)) end
  return ilvl
end
Rules.ItemLevelOf = ItemLevelOf

-- Set of buckets from the item's plain stats
local function StatBuckets(link)
  local found = {}
  local stats = D.GetItemStats and D.GetItemStats(link)
  if type(stats) ~= "table" then return found end
  for statKey, value in pairs(stats) do
    if type(statKey) == "string" and (tonumber(value) or 0) > 0 then
      for _, b in ipairs(D.STAT_BUCKETS) do
        if statKey:find(b.key, 1, true) then found[b.bucket] = true end
      end
    end
  end
  return found
end

-- Buckets from Equip:/Use:/Chance on hit: tooltip lines. Vanilla-style items
-- often carry spell power, crit, hit and attack power here, not as stats.
local TRIGGERS = {
  ITEM_SPELL_TRIGGER_ONEQUIP or "Equip:",
  ITEM_SPELL_TRIGGER_ONUSE or "Use:",
  ITEM_SPELL_TRIGGER_ONPROC or "Chance on hit:",
}

local function EffectBuckets(link)
  local found = {}
  if not D.EFFECT_KEYWORDS_ACTIVE or not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return found end
  local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
  if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return found end
  for _, line in ipairs(data.lines) do
    local text = type(line) == "table" and line.leftText
    if type(text) == "string" then
      text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
      local isEffect = false
      for _, t in ipairs(TRIGGERS) do
        if text:find(t, 1, true) == 1 then isEffect = true; break end
      end
      if isEffect then
        local lower = text:lower()
        for _, k in ipairs(D.EFFECT_KEYWORDS) do
          if lower:find(k.pattern) then found[k.bucket] = true; break end
        end
      end
    end
  end
  return found
end

-- Returns findings ({sev, text} list), highest severity (0 = fits), item level.
-- Returns nil for items AntiGrief doesn't judge (non-gear, cosmetics).
function Rules.Evaluate(link, who)
  if type(link) ~= "string" or not who or not who.class then return nil end
  local itemID, _, subTypeName, equipLoc, _, classID, subclassID = D.GetItemInfoInstant(link)
  if not itemID then return nil end
  if classID ~= D.CLASS_ARMOR and classID ~= D.CLASS_WEAPON then return nil end
  if not equipLoc or equipLoc == "" or D.IGNORE_LOC[equipLoc] then return nil end

  local findings, maxSev = {}, 0
  local function add(sev, text)
    findings[#findings + 1] = { sev = sev, text = text }
    if sev > maxSev then maxSev = sev end
  end

  local cls = who.class
  local level = tonumber(who.level) or 0
  local className = D.ClassName(cls)
  local ilvl = ItemLevelOf(link)
  -- minLevel and bindType are nil while the item isn't cached
  local _, _, _, _, minLevel, _, _, _, _, _, _, _, _, bindType = D.GetItemInfo(link)
  local usePawn = ns.db and ns.db.usePawn

  -- 1) Level requirement. A level or two short is usually a few quests or
  -- one dungeon away, so the severity grows with the gap.
  if minLevel and minLevel > 0 and level > 0 and minLevel > level then
    local gap = minLevel - level
    local sev = (gap <= LEVEL_GAP_LOW and D.LOW) or (gap <= LEVEL_GAP_MEDIUM and D.MEDIUM) or D.HIGH
    add(sev, ("requires level %d, they're level %d"):format(minLevel, level))
  end

  -- 2) Armor type
  if classID == D.CLASS_ARMOR and equipLoc ~= "INVTYPE_CLOAK" and D.ARMOR_CHECKED[subclassID] and D.ARMOR[cls] then
    local gate = D.ARMOR_LEVEL[cls] and D.ARMOR_LEVEL[cls][subclassID]
    if not D.ARMOR[cls][subclassID] then
      add(D.HIGH, ("%s can't use %s"):format(className, subTypeName or "this armor"))
    elseif gate and level > 0 and level < gate then
      add(D.HIGH, ("%s can't wear %s until level %d"):format(className, subTypeName or "this armor", gate))
    elseif D.ARMOR_TIER[subclassID] and D.BEST_ARMOR[cls] then
      local best = D.BEST_ARMOR[cls]
      local bestGate = D.ARMOR_LEVEL[cls] and D.ARMOR_LEVEL[cls][best]
      if bestGate and level > 0 and level < bestGate then best = best - 1 end
      if D.ARMOR_TIER[subclassID] < (D.ARMOR_TIER[best] or 0) then
        add(D.LOW, ("%s is a lower armor type than a %s normally wears"):format(subTypeName or "This", className))
      end
    end
  end

  -- 3) Weapon type
  if classID == D.CLASS_WEAPON and not D.WEAPON_IGNORED[subclassID] and D.WEAPON[cls] then
    if not D.WEAPON[cls][subclassID] then
      add(D.HIGH, ("%s can't use %s"):format(className, subTypeName or "this weapon"))
    end
  end

  -- 4) Stats/effects that don't suit the class (built-in buckets, Pawn as second opinion)
  local statFlagged = false
  local useful = D.StatsFor(cls, who.spec) -- hybrids: current spec
  if useful then
    local found = StatBuckets(link)
    local effects = EffectBuckets(link)
    for bucket in pairs(effects) do found[bucket] = true end
    local anyBucket, anyUseful = false, false
    for bucket in pairs(found) do
      anyBucket = true
      if useful[bucket] then anyUseful = true end
    end
    if anyBucket and not anyUseful then
      statFlagged = true
      add(D.HIGH, ("stats/effects (%s) don't suit a %s"):format(table.concat(Labels(found), ", "), className))
    else
      -- stats fit, but an Equip/Use effect doesn't: a Low note only
      local offRole = Labels(effects, useful)
      if #offRole > 0 then
        add(D.LOW, ("has an Equip/Use effect (%s) a %s can't use"):format(table.concat(offRole, ", "), className))
      end
    end
  end
  if not statFlagged and usePawn and Rules.PawnBestScore then
    local best = Rules.PawnBestScore(link, cls)
    if best and best <= 0 then
      add(D.HIGH, ("no value under any %s Pawn scale"):format(className))
    end
  end

  -- 5) Not an upgrade over what they wear (needs a gear scan); Pawn first, item level fallback
  local slots = D.SLOTS_FOR[equipLoc]
  if who.items and slots then
    local delta = usePawn and Rules.PawnUpgradeCheck and Rules.PawnUpgradeCheck(link, who, slots)
    if delta then
      if delta < 0 then
        local sev = (delta <= -0.2) and D.HIGH or D.MEDIUM
        add(sev, ("not an upgrade: Pawn scores it %d%% below their current %s under every %s spec"):format(
          math.floor(-delta * 100 + 0.5), _G[equipLoc] or "item", className))
      end
    elseif ilvl then
      -- an empty slot always counts as an upgrade; otherwise compare to the lowest
      local worst, worstLink, emptySlot = nil, nil, false
      for _, slot in ipairs(slots) do
        local eq = who.items[slot]
        if not eq then
          emptySlot = true
        else
          local eqLvl = ItemLevelOf(eq)
          if eqLvl and (not worst or eqLvl < worst) then worst, worstLink = eqLvl, eq end
        end
      end
      local margin = (ns.db and tonumber(ns.db.upgradeMargin)) or 8
      if not emptySlot and worst and (worst - ilvl) >= margin then
        add(D.MEDIUM, ("not an upgrade: item level %d vs their %s (item level %d)"):format(ilvl, worstLink, worst))
      end
    end
  end

  -- Context note for sellable loot
  if maxSev >= D.MEDIUM and bindType == 2 then
    add(D.LOW, "Bind on Equip, so it could be resold")
  end

  return findings, maxSev, ilvl
end
