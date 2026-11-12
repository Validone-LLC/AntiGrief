-- AntiGrief: core. Events, Need-roll parsing, alerts, settings, slash commands

local ADDON, ns = ...
local D, Inspect, Rules = ns.Data, ns.Inspect, ns.Rules

local DEFAULTS = {
  enabled = true, minSeverity = 2, sound = true, screen = true,
  announce = false, hints = false, upgradeMargin = 8, usePawn = true, log = {},
}

local DEDUPE_WINDOW = 60  -- seconds; select line and result line alert once
local LOG_MAX       = 50
local LOAD_RETRIES  = 3   -- uncached item: retry this many times, 1 s apart
local RESCAN_GAP    = 30  -- UNIT_INVENTORY_CHANGED re-scan at most this often

local PREFIX = "|cff40c0ffAntiGrief|r: "
local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg) end
local function Line(msg) DEFAULT_CHAT_FRAME:AddMessage("   " .. msg) end

local function Short(name)
  if type(name) ~= "string" then return "?" end
  return (Ambiguate and Ambiguate(name, "short")) or name
end

-- Remove entries of a name/guid -> timestamp table older than `age`
local function PruneOlder(t, now, age)
  local drop = {}
  for k, ts in pairs(t) do
    if now - ts >= age then drop[#drop + 1] = k end
  end
  for i = 1, #drop do t[drop[i]] = nil end
end

---------------------------------------------------------------------------
-- Need-roll parsing (patterns built from the client's localized strings)
---------------------------------------------------------------------------
local NEED_PATTERNS = {}
local LINK_TOKEN = "\001" -- stands in for the item link while matching

local function Literal(s)
  return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

-- "%s has selected Need for: %s" -> "^(.+) has selected Need for: (.+)$".
-- Handles %d, positional %1$s / %2$d and %% literals. Nil if no captures.
local function BuildPattern(fmt)
  if type(fmt) ~= "string" or fmt == "" then return nil end
  local out, lit, caps = {}, {}, 0
  local i, n = 1, #fmt
  while i <= n do
    local c = fmt:sub(i, i)
    if c == "%" and fmt:sub(i + 1, i + 1) == "%" then
      lit[#lit + 1] = "%"
      i = i + 2
    elseif c == "%" then
      local _, e, conv = fmt:find("^%d*%$?([sd])", i + 1)
      if e then
        out[#out + 1] = Literal(table.concat(lit))
        lit = {}
        out[#out + 1] = (conv == "d") and "(%d+)" or "(.+)"
        caps = caps + 1
        i = e + 1
      else
        lit[#lit + 1] = "%"
        i = i + 1
      end
    else
      lit[#lit + 1] = c
      i = i + 1
    end
  end
  out[#out + 1] = Literal(table.concat(lit))
  if caps == 0 then return nil end
  return "^" .. table.concat(out) .. "$"
end

local function InitPatterns()
  for i = #NEED_PATTERNS, 1, -1 do NEED_PATTERNS[i] = nil end
  for _, key in ipairs({ "LOOT_ROLL_NEED", "LOOT_ROLL_ROLLED_NEED", "LOOT_ROLL_ROLLED_NEED_ROLE_BONUS" }) do
    local p = BuildPattern(_G[key])
    if p then NEED_PATTERNS[#NEED_PATTERNS + 1] = p end
  end
  -- Longest (most literal text, most specific) first, so e.g. a role-bonus
  -- line isn't swallowed by a shorter pattern that also matches it with
  -- " + Role Bonus" glued onto the name
  table.sort(NEED_PATTERNS, function(a, b) return #a > #b end)
end

-- First item hyperlink in s, including a colour prefix (|cffxxxxxx or
-- |cnIQ4:) and trailing |r. Returns link, start, end.
local function ExtractItemLink(s)
  if type(s) ~= "string" then return nil end
  local ls, le = s:find("|Hitem:[^|]*|h%[.-%]|h")
  if not ls then return nil end
  local cs = s:sub(1, ls - 1):find("|c[^|]*$")
  if cs then ls = cs end
  if s:sub(le + 1, le + 2) == "|r" then le = le + 2 end
  return s:sub(ls, le), ls, le
end

local function CleanName(s)
  local linked = s:match("|Hplayer:([^:|]+)")
  if linked then return linked end
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
  return (s:match("^%s*(.-)%s*$"))
end

-- Identify the pieces by content, so locales that reorder arguments still
-- work. The item link is masked out first, so text inside the item's name
-- (" by ", " for ", the separator itself) can't shift the split.
local function ParseNeed(msg)
  local link, ls, le = ExtractItemLink(msg)
  if not link then return nil end
  local masked = msg:sub(1, ls - 1) .. LINK_TOKEN .. msg:sub(le + 1)
  for _, pat in ipairs(NEED_PATTERNS) do
    local caps = { masked:match(pat) }
    if #caps > 0 then
      local hasLink, name = false, nil
      for _, c in ipairs(caps) do
        if c == LINK_TOKEN then hasLink = true
        elseif not tonumber(c) and not c:find(LINK_TOKEN, 1, true) then name = c end
      end
      if hasLink and name then
        name = CleanName(name)
        if name ~= "" then return name, link end
      end
    end
  end
end

-- Full-name match wins over a short-name match anywhere in the group
local function UnitByName(name)
  if type(name) ~= "string" or name == "" then return nil end
  local lname, lshort = name:lower(), Short(name):lower()
  local byShort
  for _, u in ipairs(ns.GroupUnits()) do
    local full = GetUnitName(u, true)
    if full then
      if full:lower() == lname then return u end
      if not byShort and Short(full):lower() == lshort then byShort = u end
    end
  end
  return byShort
end

---------------------------------------------------------------------------
-- Alerts
---------------------------------------------------------------------------
local recent = {}

local function DedupeKey(who, link)
  local item = link:match("|H(item:[^|]+)") or link
  return (who.guid or who.name or "?") .. "|" .. item
end

local function Alert(who, link, findings, maxSev)
  if not findings or #findings == 0 or not D.SEV_COLOR[maxSev] then return end
  local now = GetTime()
  PruneOlder(recent, now, DEDUPE_WINDOW)
  local key = DedupeKey(who, link)
  if recent[key] then return end
  recent[key] = now

  table.sort(findings, function(a, b) return a.sev > b.sev end)
  local short = Short(who.name)
  Print(("|c%s%s|r rolled NEED on %s - may be griefing loot"):format(D.SEV_COLOR[maxSev], short, link))
  for _, f in ipairs(findings) do
    Line(("|c%s[%s]|r %s"):format(D.SEV_COLOR[f.sev], D.SEV_NAME[f.sev], f.text))
  end
  if not who.items then Line("|cff999999(gear not scanned yet; upgrade check skipped)|r") end

  if ns.db.screen then
    local color = (ChatTypeInfo and ChatTypeInfo.RAID_WARNING) or { r = 1, g = 0.28, b = 0 }
    D.ShowBanner(("AntiGrief: %s may be griefing %s"):format(short, link), color)
  end
  if ns.db.sound and PlaySound then
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
  end
  -- A send blocked by chat lockdown isn't an error pcall can catch, so check first
  local lockdown = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
  if ns.db.announce and not lockdown then
    local inInstance = LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
    local channel = (inInstance and "INSTANCE_CHAT") or (IsInRaid() and "RAID") or "PARTY"
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if send then
      pcall(send, ("[AntiGrief] %s's Need on %s doesn't look like a fit: %s"):format(short, link, findings[1].text), channel)
    end
  end

  if type(ns.db.log) ~= "table" then ns.db.log = {} end
  local log = ns.db.log
  table.insert(log, 1, { t = time(), who = who.name or "?", class = who.class, item = link, sev = maxSev, why = findings[1].text })
  while #log > LOG_MAX do table.remove(log) end
end

local function Judge(name, link, attempt)
  if not ns.db or not ns.db.enabled then return end
  local unit = UnitByName(name)
  if not unit or UnitIsUnit(unit, "player") then return end
  attempt = attempt or 0
  if not D.GetItemInfo(link) and attempt < LOAD_RETRIES then -- not cached yet
    local itemID = D.GetItemInfoInstant(link)
    if itemID and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
    C_Timer.After(1, function() Judge(name, link, attempt + 1) end)
    return
  end
  -- Cached now, or out of retries: judge with what we have (type checks
  -- only need GetItemInfoInstant)
  local who = Inspect.Who(unit)
  if not who then return end
  local findings, maxSev = Rules.Evaluate(link, who)
  if findings and maxSev >= (ns.db.minSeverity or 2) then Alert(who, link, findings, maxSev) end
end

local function OnLootMessage(msg)
  if not ns.db or not ns.db.enabled then return end
  if issecretvalue and issecretvalue(msg) then return end
  if type(msg) ~= "string" or not IsInGroup() then return end
  local ok, name, link = pcall(ParseNeed, msg)
  if ok and name and link then Judge(name, link) end
end

local function OnStartLootRoll(rollID)
  if not ns.db or not ns.db.enabled or not ns.db.hints or not GetLootRollItemLink then return end
  local link = GetLootRollItemLink(rollID)
  if type(link) ~= "string" then return end
  local fits = {}
  for _, u in ipairs(ns.GroupUnits()) do
    if UnitIsPlayer(u) then
      local who = Inspect.Who(u)
      if who then
        local _, maxSev = Rules.Evaluate(link, who)
        if maxSev and maxSev < D.MEDIUM then fits[#fits + 1] = Short(who.name) end
      end
    end
  end
  if #fits > 0 then Print(("%s fits: %s"):format(link, table.concat(fits, ", "))) end
end

local lastRescan = {}
local function RescanSoon(guid)
  if not guid then return end
  local now = GetTime()
  if lastRescan[guid] and now - lastRescan[guid] < RESCAN_GAP then return end
  lastRescan[guid] = now
  Inspect.Queue(guid, true)
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function OnOff(v) return v and "|cff40ff40on|r" or "|cffff4040off|r" end

local function Toggle(key, label)
  ns.db[key] = not ns.db[key]
  Print(label .. " " .. OnOff(ns.db[key]))
end

-- Inspect.Who returns a fresh table; replacing `items` (not mutating it)
-- keeps the inspect cache untouched.
local function WhoForTest(unit)
  local who = Inspect.Who(unit)
  if who and UnitIsUnit(unit, "player") then
    local items = {}
    for _, slot in ipairs(D.INSPECT_SLOTS) do items[slot] = GetInventoryItemLink("player", slot) end
    who.items = items
  end
  return who
end

local HELP = {
  "/ag status - settings and scan progress",
  "/ag on | off - enable or disable",
  "/ag scan - re-scan the group's gear",
  "/ag gear <name> - show a member's cached gear",
  "/ag test <shift-click item> - evaluate an item against the group",
  "/ag sev 1-3 - alert threshold (1 Low, 2 Medium, 3 High)",
  "/ag margin <n> - item-level gap for the upgrade check",
  "/ag sound | screen | announce | hints | pawn - toggle",
  "/ag log | clear - show or clear recent flags",
}

SLASH_ANTIGRIEF1 = "/antigrief"
SLASH_ANTIGRIEF2 = "/ag"
SlashCmdList.ANTIGRIEF = function(input)
  if not ns.db then return end -- before ADDON_LOADED
  local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  rest = rest or ""

  if cmd == "on" or cmd == "off" then
    ns.db.enabled = (cmd == "on")
    Print("AntiGrief " .. OnOff(ns.db.enabled))

  elseif cmd == "status" then
    local scanned, total, queued = Inspect.Status()
    local pawn = Rules.PawnAvailable and Rules.PawnAvailable()
    Print(("%s | alerts at %s+ | scanned %d/%d, %d queued"):format(
      OnOff(ns.db.enabled), D.SEV_NAME[ns.db.minSeverity] or "?", scanned, total, queued))
    Line(("sound %s, banner %s, announce %s, hints %s, Pawn %s%s, margin %s"):format(
      OnOff(ns.db.sound), OnOff(ns.db.screen), OnOff(ns.db.announce), OnOff(ns.db.hints),
      OnOff(ns.db.usePawn), pawn and "" or " (not loaded)", tostring(ns.db.upgradeMargin)))

  elseif cmd == "scan" then
    Inspect.QueueGroup(true)
    Print("re-scanning group gear")

  elseif cmd == "gear" then
    if rest == "" then Print("usage: /ag gear <name>"); return end
    local unit = UnitByName(rest)
    local who = unit and Inspect.Who(unit)
    if not who then Print("no group member named " .. rest); return end
    local name = who.name or rest
    if not who.items then Print(name .. " hasn't been scanned yet"); return end
    Print(("%s (%s %d, spec ID %s):"):format(name, D.ClassName(who.class), who.level or 0, tostring(who.spec or "unknown")))
    for _, slot in ipairs(D.INSPECT_SLOTS) do
      local link = who.items[slot]
      if link then Line(("%d: %s (ilvl %s)"):format(slot, link, tostring(Rules.ItemLevelOf(link) or "?"))) end
    end

  elseif cmd == "test" then
    local link = ExtractItemLink(rest)
    if not link then Print("usage: /ag test <shift-click an item>"); return end
    local units = ns.GroupUnits()
    if #units == 0 then units = { "player" } end
    for _, u in ipairs(units) do
      local who = WhoForTest(u)
      if who then
        local findings, maxSev = Rules.Evaluate(link, who)
        if not findings then Print("AntiGrief doesn't judge this item (not equippable gear)"); return end
        local verdict = (maxSev == 0) and "|cff40ff40fits|r" or ("|c%s%s|r"):format(D.SEV_COLOR[maxSev], D.SEV_NAME[maxSev])
        Print(("%s: %s"):format(Short(who.name), verdict))
        for _, f in ipairs(findings) do Line(("[%s] %s"):format(D.SEV_NAME[f.sev], f.text)) end
      end
    end

  elseif cmd == "sev" then
    local n = tonumber(rest)
    if n and D.SEV_NAME[n] then ns.db.minSeverity = n; Print("alerts at " .. D.SEV_NAME[n] .. "+")
    else Print("usage: /ag sev 1-3") end

  elseif cmd == "margin" then
    local n = tonumber(rest)
    if n and n >= 0 then ns.db.upgradeMargin = n; Print("upgrade margin " .. n .. " item levels")
    else Print("usage: /ag margin <number>") end

  elseif cmd == "sound" then Toggle("sound", "Sound")
  elseif cmd == "screen" then Toggle("screen", "Banner")
  elseif cmd == "announce" then Toggle("announce", "Group announce")
  elseif cmd == "hints" then Toggle("hints", "Drop hints")
  elseif cmd == "pawn" then Toggle("usePawn", "Pawn scoring")

  elseif cmd == "log" then
    local log = ns.db.log
    if #log == 0 then Print("no flags logged"); return end
    Print("recent flags:")
    for i = 1, math.min(#log, 15) do
      local e = log[i]
      local when = (type(e.t) == "number" and date) and date("%m/%d %H:%M", e.t) or "?"
      Line(("%s  %s  %s  [%s] %s"):format(when, tostring(e.who), tostring(e.item),
        D.SEV_NAME[e.sev] or "?", e.why or ""))
    end

  elseif cmd == "clear" then
    wipe(ns.db.log)
    Print("log cleared")

  else
    Print("commands:")
    for _, h in ipairs(HELP) do Line(h) end
  end
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local function LoadSettings()
  if type(AntiGriefDB) ~= "table" then AntiGriefDB = {} end
  local db = AntiGriefDB
  for k, v in pairs(DEFAULTS) do
    -- fill missing keys; replace only values of the wrong type (corrupt)
    if type(db[k]) ~= type(v) then db[k] = (type(v) == "table") and {} or v end
  end
  if not D.SEV_NAME[db.minSeverity] then db.minSeverity = DEFAULTS.minSeverity end
  if db.upgradeMargin < 0 then db.upgradeMargin = DEFAULTS.upgradeMargin end
  ns.db = db
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= ADDON then return end
    LoadSettings()
    InitPatterns()
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "INSPECT_READY",
                         "UNIT_INVENTORY_CHANGED", "START_LOOT_ROLL", "CHAT_MSG_LOOT" }) do
      self:RegisterEvent(e)
    end
    C_Timer.NewTicker(0.5, function()
      if ns.db.enabled and IsInGroup() then Inspect.Pump() end
    end)
    self:UnregisterEvent("ADDON_LOADED")

  elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
    Inspect.Prune()
    PruneOlder(lastRescan, GetTime(), RESCAN_GAP)
    if ns.db.enabled then Inspect.QueueGroup(false) end

  elseif event == "INSPECT_READY" then
    Inspect.OnInspectReady(...)

  elseif event == "UNIT_INVENTORY_CHANGED" then
    local unit = ...
    if ns.db.enabled and type(unit) == "string"
        and (unit:find("^party%d+$") or unit:find("^raid%d+$")) and UnitIsPlayer(unit) then
      RescanSoon(ns.GUID(unit))
    end

  elseif event == "START_LOOT_ROLL" then
    OnStartLootRoll(...)

  elseif event == "CHAT_MSG_LOOT" then
    OnLootMessage(...)
  end
end)

-- Test hook: exposes local helpers to tests/run.lua. Harmless in game.
ns._test = {
  BuildPattern = BuildPattern, ParseNeed = ParseNeed, InitPatterns = InitPatterns,
  ExtractItemLink = ExtractItemLink, CleanName = CleanName, UnitByName = UnitByName,
  patterns = NEED_PATTERNS,
}
