-- AntiGrief: core. Events, Need-roll parsing, alerts, settings, slash commands

local ADDON, ns = ...
local D, Inspect, Rules = ns.Data, ns.Inspect, ns.Rules

local DEFAULTS = {
  enabled = true, minSeverity = 2, sound = true, screen = true,
  announce = false, dropReport = true, upgradeMargin = 8, usePawn = true, log = {},
  minimapButton = true, minimapAngle = 225,
}
-- Keys from older versions, removed from the saved settings on load.
-- `hints` (off by default) was replaced by `dropReport` (on by default).
local RETIRED_KEYS = { "hints" }

local DEDUPE_WINDOW = 60  -- seconds; select line and result line alert once
local LOG_MAX       = 50
local LOAD_RETRIES  = 3   -- uncached item: retry this many times, 1 s apart
local RESCAN_GAP    = 30  -- UNIT_INVENTORY_CHANGED re-scan at most this often
local DROP_REPORT_MAX = 10   -- drop report: above this many members, collapse; cap on "doesn't fit" lines
local ROLL_MEMORY     = 900  -- seconds a reported rollID is remembered (rolls last minutes)
local MARGIN_MIN, MARGIN_MAX = 0, 30 -- upgradeMargin range; matches the options slider
local EQUIP_CHECK_DELAY = 15  -- seconds after a flagged Need win before checking the winner's gear
local EQUIP_CHECK_WAIT  = 120 -- then wait this long for a fresh inspect (range, combat) before giving up

local PREFIX = "|cff40c0ffAntiGrief|r: "
-- Chat window names (case-insensitive, trimmed). A tab named "AntiGrief"
-- receives all our output instead of the main chat. "AG Logs" is the tab the
-- minimap menu's Log option opens (/ag history): it shows the flag history
-- and gets a copy of each new flag, but doesn't take output away from the
-- main chat (a docked tab you aren't looking at would hide the alerts).
local LOG_TAB_NAME = "AG Logs"
local LOG_TAB      = { ["ag logs"] = true }
local OUTPUT_TABS  = { ["antigrief"] = true }

-- First open chat window whose name is in `names`: frame, docked. A closed
-- window keeps its name but is neither shown nor docked, so it's skipped.
-- Looked up each time so a tab made or closed mid-session is picked up.
local function FindChatWindow(names)
  if not GetChatWindowInfo then return nil end
  local max = (Constants and Constants.ChatFrameConstants and Constants.ChatFrameConstants.MaxChatWindows)
    or NUM_CHAT_WINDOWS or 10
  for i = 1, max do
    local ok, name, _, _, _, _, _, shown, _, docked = pcall(GetChatWindowInfo, i)
    if ok and type(name) == "string" and (shown or docked)
      and names[name:match("^%s*(.-)%s*$"):lower()] then
      local frame = _G["ChatFrame" .. i]
      if frame and frame.AddMessage then return frame, docked and true or false end
    end
  end
  return nil
end

-- An "AntiGrief" chat tab if one exists, else the main chat.
local function OutputFrame()
  local frame = FindChatWindow(OUTPUT_TABS)
  if frame then return frame, true end
  return DEFAULT_CHAT_FRAME, false
end

local function Print(msg) (OutputFrame()):AddMessage(PREFIX .. msg) end
local function Line(msg) (OutputFrame()):AddMessage("   " .. msg) end

-- Flag messages (Needs, wins, equip checks): printed as above, plus a copy
-- in the AG Logs tab if it's open and isn't already where output goes.
local function Mirror(text)
  local tab = FindChatWindow(LOG_TAB)
  if tab and tab ~= (OutputFrame()) then tab:AddMessage(text) end
end
local function Report(msg) Print(msg); Mirror(PREFIX .. msg) end
local function ReportLine(msg) Line(msg); Mirror("   " .. msg) end

local function Short(name)
  if type(name) ~= "string" then return "?" end
  return (Ambiguate and Ambiguate(name, "short")) or name
end

-- Calls module[method](...) if that file provides it (Config.lua, Minimap.lua). An error in the
-- module is reported (WoW's error handler) but never stops the caller.
-- Returns true if the method exists.
local function ModuleCall(label, module, method, ...)
  local fn = module and module[method]
  if type(fn) ~= "function" then return false end
  local args, n = { ... }, select("#", ...)
  local handler = (geterrorhandler and geterrorhandler())
    or function(err) Print(label .. " error: " .. tostring(err)) end
  xpcall(function() fn(unpack(args, 1, n)) end, handler)
  return true
end
local function ConfigCall(method, ...) return ModuleCall("options panel", ns.Config, method, ...) end
-- Same for the minimap button (Minimap.lua)
local function ButtonCall(method, ...) return ModuleCall("minimap button", ns.MinimapButton, method, ...) end

-- Tell the options panel (if any) that a setting changed outside it
local function Changed(key)
  ConfigCall("Refresh", key)
  if key == "minimapButton" then ButtonCall("Refresh") end
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
-- Roll-won lines: { pat = pattern, need = true (the line says Need) | false (no roll type) }.
-- Greed/Disenchant/Transmog wins aren't parsed: they're never judged.
local WIN_PATTERNS = {}
local YOU_WON_PATTERN -- "You won: %s": the player's own win, which the "%s won:" pattern would also match
local WIN_KEYS = {
  { "LOOT_ROLL_WON", false },                       -- "%s won: %s" (default, showLootSpam 1)
  { "LOOT_ROLL_WON_NO_SPAM_NEED", true },           -- "%s (Need - %d, Main-Spec) Won: %s"
  { "LOOT_ROLL_WON_NO_SPAM_NEED_OFF_SPEC", true },  -- "%s (Need - %d, Off-Spec) Won: %s"
}
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

  for i = #WIN_PATTERNS, 1, -1 do WIN_PATTERNS[i] = nil end
  for _, k in ipairs(WIN_KEYS) do
    local p = BuildPattern(_G[ k[1] ])
    if p then WIN_PATTERNS[#WIN_PATTERNS + 1] = { pat = p, need = k[2] } end
  end
  YOU_WON_PATTERN = BuildPattern(LOOT_ROLL_YOU_WON)
  table.sort(WIN_PATTERNS, function(a, b) return #a.pat > #b.pat end)
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
-- Returns name, link, and the index of the pattern that matched.
local function MatchNameAndLink(msg, patterns, patOf)
  local link, ls, le = ExtractItemLink(msg)
  if not link then return nil end
  local masked = msg:sub(1, ls - 1) .. LINK_TOKEN .. msg:sub(le + 1)
  for i, entry in ipairs(patterns) do
    local caps = { masked:match(patOf and patOf(entry) or entry) }
    if #caps > 0 then
      local hasLink, name = false, nil
      for _, c in ipairs(caps) do
        if c == LINK_TOKEN then hasLink = true
        elseif not tonumber(c) and not c:find(LINK_TOKEN, 1, true) then name = c end
      end
      if hasLink and name then
        name = CleanName(name)
        if name ~= "" then return name, link, i end
      end
    end
  end
end

local function ParseNeed(msg)
  local name, link = MatchNameAndLink(msg, NEED_PATTERNS)
  return name, link
end

-- "Bob won: [item]" -> "Bob", link, saysNeed (true when the line itself says Need)
local function WinPat(e) return e.pat end
local function ParseWin(msg)
  if YOU_WON_PATTERN then
    local link, ls, le = ExtractItemLink(msg)
    if link and (msg:sub(1, ls - 1) .. LINK_TOKEN .. msg:sub(le + 1)):match(YOU_WON_PATTERN) then return nil end
  end
  local name, link, i = MatchNameAndLink(msg, WIN_PATTERNS, WinPat)
  if name then return name, link, WIN_PATTERNS[i].need end
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

-- Logs a misfit Need (any severity) and, when `notify` (at or above the
-- alert threshold), also prints it, shows the banner, plays the sound and
-- announces if enabled.
local function Alert(who, link, findings, maxSev, itemNotLoaded, notify)
  if not findings or #findings == 0 or not D.SEV_COLOR[maxSev] then return end
  local now = GetTime()
  PruneOlder(recent, now, DEDUPE_WINDOW)
  local key = DedupeKey(who, link)
  if recent[key] then return end
  recent[key] = now

  table.sort(findings, function(a, b) return a.sev > b.sev end)
  if type(ns.db.log) ~= "table" then ns.db.log = {} end
  local log = ns.db.log
  table.insert(log, 1, { t = time(), who = who.name or "?", class = who.class, item = link, sev = maxSev, why = findings[1].text })
  while #log > LOG_MAX do table.remove(log) end
  if not notify then return end

  local short = Short(who.name)
  Report(("|c%s%s|r rolled NEED on %s - may be griefing loot"):format(D.SEV_COLOR[maxSev], short, link))
  for _, f in ipairs(findings) do
    ReportLine(("|c%s[%s]|r %s"):format(D.SEV_COLOR[f.sev], D.SEV_NAME[f.sev], f.text))
  end
  if itemNotLoaded then ReportLine("|cff999999(item info not loaded; only type checks ran)|r") end
  if not who.items then ReportLine("|cff999999(gear not scanned yet; upgrade check skipped)|r") end

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
  -- only need GetItemInfoInstant; level, stat and upgrade data stay nil)
  local who = Inspect.Who(unit)
  if not who then return end
  local findings, maxSev = Rules.Evaluate(link, who)
  if findings and maxSev >= D.LOW then
    Alert(who, link, findings, maxSev, not D.GetItemInfo(link), maxSev >= (ns.db.minSeverity or 2))
  end
end

---------------------------------------------------------------------------
-- Wins: "Bob won: [item]" after Bob rolled Need on it, and it doesn't fit
---------------------------------------------------------------------------
-- itemString -> { [short lowercase name] = GetTime() of their Need }
local needed = {}

local function ItemKey(link) return link:match("|H(item:[^|]+)") or link end
local function NameKey(name) return Short(name):lower() end

local function RememberNeed(name, link)
  local key = ItemKey(link)
  needed[key] = needed[key] or {}
  needed[key][NameKey(name)] = GetTime()
end

-- True (and forgets it) if `name` rolled Need on this item in the last ROLL_MEMORY s
local function TakeNeed(name, link)
  local key = ItemKey(link)
  local byName = needed[key]
  local t = byName and byName[NameKey(name)]
  if not t then return false end
  byName[NameKey(name)] = nil
  if next(byName) == nil then needed[key] = nil end
  return GetTime() - t <= ROLL_MEMORY
end

local function PruneNeeded(now)
  for key, byName in pairs(needed) do
    PruneOlder(byName, now, ROLL_MEMORY)
    if next(byName) == nil then needed[key] = nil end
  end
end

-- Logs a misfit Need win (any severity); prints it when `notify`
local function LogWin(who, link, findings, maxSev, notify)
  table.sort(findings, function(a, b) return a.sev > b.sev end)
  if type(ns.db.log) ~= "table" then ns.db.log = {} end
  local log = ns.db.log
  table.insert(log, 1, { t = time(), kind = "won", who = who.name or "?", class = who.class, item = link,
    sev = maxSev, why = findings[1].text })
  while #log > LOG_MAX do table.remove(log) end
  if not notify then return end
  Report(("|c%s%s|r won %s with Need - doesn't look like a fit"):format(D.SEV_COLOR[maxSev], Short(who.name), link))
  for _, f in ipairs(findings) do
    ReportLine(("|c%s[%s]|r %s"):format(D.SEV_COLOR[f.sev], D.SEV_NAME[f.sev], f.text))
  end
end

-- Judge a confirmed Need win: any misfit is logged, printed at the alert threshold
---------------------------------------------------------------------------
-- Equip check: EQUIP_CHECK_DELAY s after a flagged Need win, re-inspect the
-- winner and log whether they're wearing the item. Not wearing it is alerted
-- (at the alert threshold); wearing it, or no inspect in time, is only logged.
---------------------------------------------------------------------------
local EQUIP_TEXT = {
  no      = "hasn't equipped it %d s after winning",
  yes     = "equipped it",
  unknown = "couldn't be checked (out of inspect range, offline or left)",
}
local equipChecks = {} -- guid -> list of checks waiting for a fresh inspect

local function ItemID(link) return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil end

local function Wears(entry, itemID)
  for _, id in pairs(entry.ids or {}) do if id == itemID then return true end end
  for _, l in pairs(entry.items or {}) do if ItemID(l) == itemID then return true end end
  return false
end

local function LogEquip(c, result)
  if not ns.db or not ns.db.enabled then return end
  if type(ns.db.log) ~= "table" then ns.db.log = {} end
  local log = ns.db.log
  table.insert(log, 1, { t = time(), kind = "equip", who = c.name or "?", class = c.class, item = c.link,
    sev = c.sev, equip = result })
  while #log > LOG_MAX do table.remove(log) end
  if result ~= "no" or not c.notify then return end
  local short = Short(c.name)
  Report(("|c%s%s|r hasn't equipped %s %d s after winning it with Need"):format(
    D.SEV_COLOR[c.sev] or "ffff4040", short, c.link, EQUIP_CHECK_DELAY))
  if ns.db.screen then
    local color = (ChatTypeInfo and ChatTypeInfo.RAID_WARNING) or { r = 1, g = 0.28, b = 0 }
    D.ShowBanner(("AntiGrief: %s won %s but hasn't equipped it"):format(short, c.link), color)
  end
  if ns.db.sound and PlaySound then
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
  end
end

local function TakeCheck(guid, c)
  local list = equipChecks[guid]
  if not list then return false end
  for i, x in ipairs(list) do
    if x == c then
      table.remove(list, i)
      if #list == 0 then equipChecks[guid] = nil end
      return true
    end
  end
  return false
end

-- Inspect.onScan: settle every check on this player that the scan is fresh enough for
local function OnScan(guid, entry)
  local list = equipChecks[guid]
  if not list then return end
  for i = #list, 1, -1 do
    local c = list[i]
    if entry.time >= c.after then
      table.remove(list, i)
      LogEquip(c, Wears(entry, c.itemID) and "yes" or "no")
    end
  end
  if #list == 0 then equipChecks[guid] = nil end
end
Inspect.onScan = OnScan

local function StartEquipCheck(c)
  if not ns.db or not ns.db.enabled then return end
  -- Already seen wearing it since the win (e.g. the re-scan on equip): done
  local cached = Inspect.cache[c.guid]
  if cached and cached.time >= c.wonAt and Wears(cached, c.itemID) then
    LogEquip(c, "yes")
    return
  end
  c.after = GetTime()
  equipChecks[c.guid] = equipChecks[c.guid] or {}
  table.insert(equipChecks[c.guid], c)
  Inspect.Queue(c.guid, true)
  C_Timer.After(EQUIP_CHECK_WAIT, function()
    if TakeCheck(c.guid, c) then LogEquip(c, "unknown") end
  end)
end

local function ScheduleEquipCheck(who, link, maxSev, notify)
  local itemID = ItemID(link)
  if not who.guid or not itemID or not (C_Timer and C_Timer.After) then return end
  local c = { guid = who.guid, name = who.name, class = who.class, link = link, itemID = itemID,
              sev = maxSev, notify = notify, wonAt = GetTime() }
  C_Timer.After(EQUIP_CHECK_DELAY, function() StartEquipCheck(c) end)
end

local function JudgeWin(name, link, attempt)
  if not ns.db or not ns.db.enabled then return end
  local unit = UnitByName(name)
  if not unit or UnitIsUnit(unit, "player") then return end
  attempt = attempt or 0
  if not D.GetItemInfo(link) and attempt < LOAD_RETRIES then
    C_Timer.After(1, function() JudgeWin(name, link, attempt + 1) end)
    return
  end
  local who = Inspect.Who(unit)
  if not who then return end
  local findings, maxSev = Rules.Evaluate(link, who)
  if findings and #findings > 0 and D.SEV_COLOR[maxSev] then
    local notify = maxSev >= (ns.db.minSeverity or 2)
    LogWin(who, link, findings, maxSev, notify)
    ScheduleEquipCheck(who, link, maxSev, notify)
  end
end

local function OnWin(name, link, saysNeed)
  -- Need-only: the default "won:" line has no roll type, so it counts only if
  -- we saw this player's Need on the item; the no-spam Need lines say it.
  local rolledNeed = TakeNeed(name, link)
  if saysNeed or rolledNeed then JudgeWin(name, link) end
end

local function OnLootMessage(msg)
  if not ns.db or not ns.db.enabled then return end
  if issecretvalue and issecretvalue(msg) then return end
  if type(msg) ~= "string" or not IsInGroup() then return end
  local ok, name, link = pcall(ParseNeed, msg)
  if ok and name and link then
    PruneNeeded(GetTime())
    RememberNeed(name, link)
    Judge(name, link)
    return
  end
  local okWin, wname, wlink, saysNeed = pcall(ParseWin, msg)
  if okWin and wname and wlink then OnWin(wname, wlink, saysNeed) end
end

---------------------------------------------------------------------------
-- Group verdicts: shared by /ag test and the drop report
---------------------------------------------------------------------------
local FIT_COLOR  = "ff40ff40"
local GREY_COLOR = "ff999999"

-- Inspect.Who returns a fresh table; replacing `items` (not mutating it)
-- keeps the inspect cache untouched. The player is judged on the gear
-- they're wearing now.
local function WhoWithOwnGear(unit)
  local who = Inspect.Who(unit)
  if who and UnitIsUnit(unit, "player") then
    local items = {}
    for _, slot in ipairs(D.INSPECT_SLOTS) do items[slot] = GetInventoryItemLink("player", slot) end
    who.items = items
  end
  return who
end

-- Evaluate `link` for every group member (just the player when solo).
-- Returns a list of { who, findings, maxSev }, or nil if AntiGrief doesn't
-- judge the item (Rules.Evaluate returned nil for everyone).
local function EvaluateGroup(link)
  local units = ns.GroupUnits()
  if #units == 0 then units = { "player" } end
  local results = {}
  for _, u in ipairs(units) do
    local who = UnitIsPlayer(u) and WhoWithOwnGear(u)
    if who then
      local findings, maxSev = Rules.Evaluate(link, who)
      if findings then results[#results + 1] = { who = who, findings = findings, maxSev = maxSev } end
    end
  end
  if #results == 0 then return nil end
  return results
end

local function Fits(r) return r.maxSev < D.LOW end -- maxSev 0: no findings

-- Highest-severity finding; the first one listed wins a tie
local function TopFinding(findings)
  local top
  for _, f in ipairs(findings) do
    if not top or f.sev > top.sev then top = f end
  end
  return top
end

-- One member's verdict: "Name (Class): fits" in green, or
-- "Name (Class): High - <top finding>" in the severity colour, plus
-- "(not scanned)" when their upgrade check was skipped.
local function VerdictLine(r)
  local who = r.who
  local label = ("%s (%s)"):format(Short(who.name), D.ClassName(who.class))
  local color, text
  if Fits(r) then
    color, text = FIT_COLOR, label .. ": fits"
  else
    local top = TopFinding(r.findings)
    color = D.SEV_COLOR[r.maxSev]
    -- an item link inside the finding ends with |r; resume the colour after it
    text = ("%s: %s - %s"):format(label, D.SEV_NAME[r.maxSev], (top.text:gsub("|r", "|r|c" .. color)))
  end
  local line = ("|c%s%s|r"):format(color, text)
  if not who.items then line = line .. (" |c%s(not scanned)|r"):format(GREY_COLOR) end
  return line
end

---------------------------------------------------------------------------
-- Drop report (START_LOOT_ROLL). Private: never sent to group chat.
---------------------------------------------------------------------------
local reportedRolls = {} -- rollID -> time reported

local function PrintDropReport(link, results)
  Print("new drop: " .. link)
  if #results <= DROP_REPORT_MAX then
    for _, r in ipairs(results) do Line(VerdictLine(r)) end
    return
  end
  -- Big group: everyone it fits on one line, then capped lines for the rest
  local fits, misfits = {}, {}
  for _, r in ipairs(results) do
    if Fits(r) then fits[#fits + 1] = Short(r.who.name) else misfits[#misfits + 1] = r end
  end
  Line(("|c%sfits: %s|r"):format(FIT_COLOR, #fits > 0 and table.concat(fits, ", ") or "nobody"))
  for i = 1, math.min(#misfits, DROP_REPORT_MAX) do Line(VerdictLine(misfits[i])) end
  if #misfits > DROP_REPORT_MAX then
    Line(("|c%s...and %d more|r"):format(GREY_COLOR, #misfits - DROP_REPORT_MAX))
  end
end

local function DropReport(rollID, link, attempt)
  -- re-checked on every retry: settings may change and the roll may be reported
  if not ns.db or not ns.db.enabled or not ns.db.dropReport then return end
  if reportedRolls[rollID] then return end
  if not D.GetItemInfo(link) then -- not cached yet
    if attempt >= LOAD_RETRIES then return end -- never loaded: say nothing
    local itemID = D.GetItemInfoInstant(link)
    if itemID and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
    C_Timer.After(1, function() DropReport(rollID, link, attempt + 1) end)
    return
  end
  local results = EvaluateGroup(link)
  if not results then return end -- not gear AntiGrief judges
  local now = GetTime()
  PruneOlder(reportedRolls, now, ROLL_MEMORY)
  reportedRolls[rollID] = now
  PrintDropReport(link, results)
end

local function OnStartLootRoll(rollID)
  if not ns.db or not ns.db.enabled or not ns.db.dropReport or not GetLootRollItemLink then return end
  if rollID == nil or (issecretvalue and issecretvalue(rollID)) then return end
  if reportedRolls[rollID] then return end
  local ok, link = pcall(GetLootRollItemLink, rollID)
  if not ok or type(link) ~= "string" or (issecretvalue and issecretvalue(link)) then return end
  DropReport(rollID, link, 0)
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
  Changed(key)
end

local HELP = {
  "/ag status - settings and scan progress",
  "/ag config - open the options panel",
  "/ag on | off - enable or disable",
  "/ag scan - re-scan the group's gear",
  "/ag gear <name> - show a member's cached gear",
  "/ag test <shift-click item> - evaluate an item against the group",
  "/ag sev 1-3 - alert threshold (1 Low, 2 Medium, 3 High)",
  "/ag margin 0-30 - item-level gap for the upgrade check",
  "/ag drops - toggle the fit report on new drops (alias: hints)",
  "/ag sound | screen | announce | pawn | minimap - toggle",
  "/ag history - open the AG Logs chat tab with the full flag history",
  "/ag log | clear - show recent flags here, or clear the log history",
  "/ag feedback - Discord link for feedback and bug reports",
  "Tip: a chat tab named AntiGrief receives all AntiGrief messages; AG Logs gets a copy of each flag",
}

-- History layout: one block per drop (item), oldest first:
--   11/16 21:04  [item]
--      - Bob is High: <reason>          (severity colour)
--      - Cy is Low: <reason>
--      -- Bob won and is High for: <reason>   (WIN_COLOR)
local WIN_COLOR = "ffff66ff"
--      --- Bob hasn't equipped it 15 s after winning   (red; green if he did)
local EQUIP_COLOR = { no = "ffff4040", yes = "ff40ff40" }

-- Groups log entries (stored newest first) into drops, oldest first. Entries
-- for the same item within ROLL_MEMORY of the drop's first entry are one drop.
local function GroupDrops(log)
  local drops, open = {}, {}
  for i = #log, 1, -1 do
    local e = log[i]
    local key = (type(e.item) == "string") and ItemKey(e.item) or tostring(e.item)
    local d = open[key]
    if not d or (type(e.t) == "number" and type(d.t) == "number" and e.t - d.t > ROLL_MEMORY) then
      d = { t = e.t, item = e.item, needs = {}, wins = {} }
      drops[#drops + 1] = d
      open[key] = d
    end
    local list = (e.kind == "won" or e.kind == "equip") and d.wins or d.needs
    list[#list + 1] = e
  end
  return drops
end

-- Appends the chat lines for one drop to `out`
local function DropLines(d, out)
  local when = (type(d.t) == "number" and date) and date("%m/%d %H:%M", d.t) or "?"
  out[#out + 1] = ("%s  %s"):format(when, tostring(d.item))
  for _, e in ipairs(d.needs) do
    out[#out + 1] = ("   |c%s- %s is %s: %s|r"):format(D.SEV_COLOR[e.sev] or GREY_COLOR,
      Short(e.who), D.SEV_NAME[e.sev] or "?", e.why or "")
  end
  for _, e in ipairs(d.wins) do
    if e.kind == "equip" then
      local text = EQUIP_TEXT[e.equip] or EQUIP_TEXT.unknown
      out[#out + 1] = ("   |c%s--- %s %s|r"):format(EQUIP_COLOR[e.equip] or GREY_COLOR,
        Short(e.who), text:format(EQUIP_CHECK_DELAY))
    else
      out[#out + 1] = ("   |c%s-- %s won and is %s for: %s|r"):format(WIN_COLOR,
        Short(e.who), D.SEV_NAME[e.sev] or "?", e.why or "")
    end
  end
end

-- Lines for the last `maxDrops` drops (all if nil), oldest first, with a
-- blank line between drops
local function HistoryLines(maxDrops)
  local drops, out = GroupDrops(ns.db.log), {}
  local first = maxDrops and math.max(1, #drops - maxDrops + 1) or 1
  for i = first, #drops do
    if i > first then out[#out + 1] = " " end
    DropLines(drops[i], out)
  end
  return out, #drops
end

local RECENT_DROPS = 5 -- /ag log and the no-tab fallback show this many

-- Opens the "AG Logs" chat tab (creating it if needed) and fills it with the
-- whole saved flag log, oldest first, the way chat reads. The tab then keeps
-- receiving a copy of each new flag (Mirror).
local function ShowHistory()
  local frame, docked = FindChatWindow(LOG_TAB)
  local created = false
  if not frame and FCF_OpenNewWindow then
    -- true = no default chat channels: the tab holds only what we add
    local ok, f = pcall(FCF_OpenNewWindow, LOG_TAB_NAME, true)
    if ok and type(f) == "table" and f.AddMessage then frame, created = f, true end
  end
  local log = ns.db.log
  if not frame then
    Print("couldn't open an AG Logs chat tab (no free chat window?); recent drops:")
    if #log == 0 then Line("no flags logged") end
    for _, l in ipairs((HistoryLines(RECENT_DROPS))) do Line(l) end
    return
  end
  if not created and docked and FCF_SelectDockFrame then pcall(FCF_SelectDockFrame, frame) end
  if frame.Clear then pcall(frame.Clear, frame) end -- redraw, don't append a second copy
  if #log == 0 then
    frame:AddMessage(PREFIX .. "flag history: no flags logged")
    return
  end
  local lines, drops = HistoryLines()
  frame:AddMessage(PREFIX .. ("flag history: %d %s, oldest first (keeps the last %d entries)"):format(
    drops, drops == 1 and "drop" or "drops", LOG_MAX))
  for _, l in ipairs(lines) do frame:AddMessage(l) end
end

-- Feedback: a popup with the Discord invite in a pre-selected edit box, so
-- the player can Ctrl+C it (chat links can't be copied). Falls back to
-- printing the link if StaticPopup isn't available.
local DISCORD_URL = "https://discord.gg/3GSsbDWWbM"
ns.DISCORD_URL = DISCORD_URL

local function FeedbackEditBox(dialog)
  if dialog.GetEditBox then return dialog:GetEditBox() end -- 11.2+ StaticPopup
  return dialog.editBox or dialog.EditBox
end

local function ShowFeedback()
  if type(StaticPopupDialogs) == "table" and StaticPopup_Show then
    if not StaticPopupDialogs.ANTIGRIEF_FEEDBACK then
      StaticPopupDialogs.ANTIGRIEF_FEEDBACK = {
        text = "AntiGrief feedback and bug reports: join the Discord.\nPress Ctrl+C to copy the link, then paste it into your browser.",
        button1 = CLOSE or "Close",
        hasEditBox = true,
        editBoxWidth = 260,
        OnShow = function(self)
          local eb = FeedbackEditBox(self)
          if not eb then return end
          eb:SetText(DISCORD_URL)
          eb:HighlightText()
          eb:SetFocus()
        end,
        -- read-only: typing puts the link back and re-selects it
        EditBoxOnTextChanged = function(eb)
          if eb:GetText() ~= DISCORD_URL then eb:SetText(DISCORD_URL) end
          eb:HighlightText()
        end,
        EditBoxOnEnterPressed = function(eb) eb:GetParent():Hide() end,
        EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
      }
    end
    if pcall(StaticPopup_Show, "ANTIGRIEF_FEEDBACK") then return end
  end
  Print("feedback and bug reports: " .. DISCORD_URL)
end

local function PrintHelp()
  Print("commands:")
  for _, h in ipairs(HELP) do Line(h) end
end

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
    Changed("enabled")

  elseif cmd == "status" then
    local scanned, total, queued = Inspect.Status()
    local pawn = Rules.PawnAvailable and Rules.PawnAvailable()
    Print(("%s | alerts at %s+ | scanned %d/%d, %d queued"):format(
      OnOff(ns.db.enabled), D.SEV_NAME[ns.db.minSeverity] or "?", scanned, total, queued))
    Line(("sound %s, banner %s, announce %s, drop report %s, Pawn %s%s, margin %s"):format(
      OnOff(ns.db.sound), OnOff(ns.db.screen), OnOff(ns.db.announce), OnOff(ns.db.dropReport),
      OnOff(ns.db.usePawn), pawn and "" or " (not loaded)", tostring(ns.db.upgradeMargin)))
    local _, ownTab = OutputFrame()
    Line(ownTab and "output: AntiGrief chat tab"
      or "output: main chat (a chat tab named AntiGrief would take it instead)")

  elseif cmd == "config" or cmd == "options" then
    if not ConfigCall("Open") then PrintHelp() end

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
    local results = EvaluateGroup(link)
    if not results then Print("AntiGrief doesn't judge this item (not equippable gear)"); return end
    for _, r in ipairs(results) do
      Print(VerdictLine(r))
      for _, f in ipairs(r.findings) do Line(("[%s] %s"):format(D.SEV_NAME[f.sev], f.text)) end
    end

  elseif cmd == "sev" then
    local n = tonumber(rest)
    if n and D.SEV_NAME[n] then
      ns.db.minSeverity = n; Print("alerts at " .. D.SEV_NAME[n] .. "+"); Changed("minSeverity")
    else Print("usage: /ag sev 1-3") end

  elseif cmd == "margin" then
    local n = tonumber(rest)
    if n and n == n then -- not NaN
      -- whole numbers within the options slider's range
      local m = math.max(MARGIN_MIN, math.min(MARGIN_MAX, math.floor(n + 0.5)))
      ns.db.upgradeMargin = m
      Print(("upgrade margin %d item levels%s"):format(m,
        (m ~= n) and (" (allowed %d-%d)"):format(MARGIN_MIN, MARGIN_MAX) or ""))
      Changed("upgradeMargin")
    else Print(("usage: /ag margin <%d-%d>"):format(MARGIN_MIN, MARGIN_MAX)) end

  elseif cmd == "sound" then Toggle("sound", "Sound")
  elseif cmd == "screen" then Toggle("screen", "Banner")
  elseif cmd == "announce" then Toggle("announce", "Group announce")
  elseif cmd == "drops" or cmd == "hints" then Toggle("dropReport", "Drop report")
  elseif cmd == "pawn" then Toggle("usePawn", "Pawn scoring")
  elseif cmd == "minimap" then Toggle("minimapButton", "Minimap button")

  elseif cmd == "log" then
    local log = ns.db.log
    if #log == 0 then Print("no flags logged"); return end
    Print("recent drops:")
    for _, l in ipairs((HistoryLines(RECENT_DROPS))) do Line(l) end

  elseif cmd == "history" then
    ShowHistory()

  elseif cmd == "clear" then
    local n = #ns.db.log
    wipe(ns.db.log)
    local tab = FindChatWindow(LOG_TAB)
    if tab and tab.Clear then pcall(tab.Clear, tab) end
    -- in the main chat (where /ag was typed) and in the emptied AG Logs tab
    Report(("log history cleared (%d %s removed)"):format(n, n == 1 and "entry" or "entries"))

  elseif cmd == "feedback" or cmd == "discord" then
    ShowFeedback()

  else
    PrintHelp()
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
  for _, k in ipairs(RETIRED_KEYS) do db[k] = nil end
  if not D.SEV_NAME[db.minSeverity] then db.minSeverity = DEFAULTS.minSeverity end
  if db.upgradeMargin < MARGIN_MIN or db.upgradeMargin ~= db.upgradeMargin then
    db.upgradeMargin = DEFAULTS.upgradeMargin -- corrupt
  elseif db.upgradeMargin > MARGIN_MAX then
    db.upgradeMargin = MARGIN_MAX            -- e.g. set by /ag margin before the cap
  end
  if db.minimapAngle ~= db.minimapAngle or db.minimapAngle == math.huge or db.minimapAngle == -math.huge then
    db.minimapAngle = DEFAULTS.minimapAngle -- NaN or infinite
  end
  db.minimapAngle = db.minimapAngle % 360
  -- ns.db is this same table from here on (edited in place, never replaced):
  -- the options panel binds its settings to it in Config.Init
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
    ConfigCall("Init") -- options panel (Config.lua), once the settings exist
    ButtonCall("Init") -- minimap button (Minimap.lua)
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
    -- no-op once made; covers a minimap that didn't exist yet at ADDON_LOADED
    if event == "PLAYER_ENTERING_WORLD" then ButtonCall("Init") end
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
  patterns = NEED_PATTERNS, DROP_REPORT_MAX = DROP_REPORT_MAX,
  ParseWin = ParseWin, winPatterns = WIN_PATTERNS,
}
