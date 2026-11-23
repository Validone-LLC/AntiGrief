-- Minimal WoW API stub for offline tests. Not an emulator: just enough
-- surface for the AntiGrief files to load and the rules to be exercised.
-- Loading this file (re)defines every global it fakes and returns the
-- control table S.

local S = {
  now = 1000,
  timers = {},
  frames = {},
  chat = {},
  sounds = 0,
  banners = {},
  sent = {},
  notified = {},
  cleared = 0,
  loadRequests = 0,
  items = {},     -- itemID -> definition
  units = {},     -- unit token -> { guid, name, class, level, spec, items, far, offline, noName, lateLinks, linksReadyAt }
  groupKind = nil, -- nil | "party" | "raid"
  instance = false,
  combat = false,
  secret = {},
  rolls = {},
}

---------------------------------------------------------------------------
-- Clock and timers
---------------------------------------------------------------------------
function GetTime() return S.now end

local function addTimer(delay, fn, interval)
  local t = { due = S.now + delay, fn = fn, interval = interval }
  S.timers[#S.timers + 1] = t
  return t
end

C_Timer = {
  After = function(delay, fn) addTimer(delay, fn) end,
  NewTicker = function(interval, fn)
    local t = addTimer(interval, fn, interval)
    t.Cancel = function(self) self.cancelled = true end
    return t
  end,
}

-- Advance the clock by dt seconds, running due timers in time order
function S.advance(dt)
  local target = S.now + dt + 1e-9
  while true do
    local best, bi
    for i, t in ipairs(S.timers) do
      if not t.cancelled and t.due <= target and (not best or t.due < best.due) then best, bi = t, i end
    end
    if not best then break end
    if best.due > S.now then S.now = best.due end
    if best.interval then
      best.due = best.due + best.interval
      best.fn(best)
    else
      table.remove(S.timers, bi)
      best.fn()
    end
  end
  S.now = target
end

---------------------------------------------------------------------------
-- Frames and events
---------------------------------------------------------------------------
-- Widget methods the addon doesn't need modelled are accepted and ignored
-- (layout, strata, textures); the ones tests inspect keep state.
local noop = function() end
local Region = { __index = function() return noop end }

local function NewRegion(kind)
  local r = setmetatable({ kind = kind }, Region)
  function r:SetText(t) self.text = t end
  function r:SetTextColor(...) self.textColor = { ... } end
  function r:SetVertexColor(...) self.vertexColor = { ... } end
  -- returns false for paths listed in S.missingTextures, like the client
  function r:SetTexture(t)
    if S.missingTextures and S.missingTextures[t] then return false end
    self.texture = t
    return true
  end
  return r
end

function CreateFrame(frameType, name, parent)
  local f = setmetatable({ events = {}, scripts = {}, frameType = frameType, name = name,
    parent = parent, shown = false, regions = {} }, Region)
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterEvent(e) self.events[e] = nil end
  function f:SetScript(k, fn) self.scripts[k] = fn end
  function f:GetScript(k) return self.scripts[k] end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  function f:IsShown() return self.shown end
  function f:ClearAllPoints() self.point = nil end
  function f:SetPoint(...) self.point = { ... } end
  function f:CreateTexture() local r = NewRegion("Texture"); self.regions[#self.regions + 1] = r; return r end
  function f:CreateFontString() local r = NewRegion("FontString"); self.regions[#self.regions + 1] = r; return r end
  -- Only frame types that are actually widgets get Show state; event frames stay hidden
  if frameType == "Button" then f.shown = true end
  S.frames[#S.frames + 1] = f
  if name then _G[name] = f end
  return f
end

-- Frame names are globals; clear ours so each fresh stub starts without the button
rawset(_G, "AntiGriefMinimapButton", nil)
-- Chat windows are opt-in per test (see chatSystem in run.lua); start without them
for i = 1, 10 do rawset(_G, "ChatFrame" .. i, nil) end
for _, k in ipairs({ "GetChatWindowInfo", "NUM_CHAT_WINDOWS", "FCF_OpenNewWindow", "FCF_SelectDockFrame" }) do
  rawset(_G, k, nil)
end

-- Minimap: 140 px wide, centred at (500, 400) in UI units, scale 1
Minimap = {
  GetWidth = function() return 140 end, GetHeight = function() return 140 end,
  GetCenter = function() return 500, 400 end, GetEffectiveScale = function() return 1 end,
}
S.cursor = { 500, 400 }
function GetCursorPosition() return S.cursor[1], S.cursor[2] end

-- Menu API (Blizzard_Menu): records the last menu built
S.menus = {}
MenuUtil = {
  CreateContextMenu = function(owner, generator)
    local menu = { owner = owner, items = {} }
    local root = {}
    function root.CreateTitle(_, text) menu.items[#menu.items + 1] = { kind = "title", text = text } end
    function root.CreateButton(_, text, fn) menu.items[#menu.items + 1] = { kind = "button", text = text, fn = fn } end
    function root.CreateDivider() menu.items[#menu.items + 1] = { kind = "divider" } end
    generator(owner, root)
    S.menus[#S.menus + 1] = menu
    return menu
  end,
}

-- StaticPopup (11.2+ shape: dialog:GetEditBox()). StaticPopup_Show runs
-- OnShow against a fake dialog and records it in S.popups.
S.popups = {}
StaticPopupDialogs = {}
CLOSE = "Close"
function StaticPopup_Show(which)
  local info = StaticPopupDialogs[which]
  if not info then return nil end
  local dialog = { which = which, shown = true }
  local eb = { text = "", highlighted = false, focused = false }
  function eb:SetText(t)
    self.text = t
    if info.EditBoxOnTextChanged and not self.inChange then
      self.inChange = true; info.EditBoxOnTextChanged(self); self.inChange = false
    end
  end
  function eb:GetText() return self.text end
  function eb:HighlightText() self.highlighted = true end
  function eb:SetFocus() self.focused = true end
  function eb.GetParent() return dialog end
  function dialog.GetEditBox() return eb end
  function dialog:Hide() self.shown = false end
  dialog.editBox = eb
  if info.OnShow then info.OnShow(dialog) end
  S.popups[#S.popups + 1] = dialog
  return dialog
end

GameTooltip = { lines = {} }
function GameTooltip:SetOwner(owner) self.owner, self.lines = owner, {} end
function GameTooltip:SetText(t) self.lines = { t } end
function GameTooltip:AddLine(t) self.lines[#self.lines + 1] = t end
function GameTooltip:Show() self.shown = true end
function GameTooltip:Hide() self.shown = false end

function S.fire(event, ...)
  for _, f in ipairs(S.frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

---------------------------------------------------------------------------
-- Chat, alerts, sound
---------------------------------------------------------------------------
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) S.chat[#S.chat + 1] = msg end }
-- Forever with loadDeprecationFallbacks = 0: the RaidNotice_AddMessage and
-- global SendChatMessage shims don't exist; the current APIs do.
RaidWarningFrame = {}
RaidNotice_AddMessage = nil
RaidWarningUtil = {
  AddMessage = function(text, colorInfo) S.banners[#S.banners + 1] = { text = text, color = colorInfo } end,
}
ChatTypeInfo = { RAID_WARNING = { r = 1, g = 0.28, b = 0 } }
SOUNDKIT = { RAID_WARNING = 8959, ALARM_CLOCK_WARNING_3 = 12889 }
function PlaySound(id) S.sounds = S.sounds + 1; S.lastSound = id end
SendChatMessage = nil
S.chatLockdown = false
C_ChatInfo = {
  SendChatMessage = function(msg, channel) S.sent[#S.sent + 1] = { msg = msg, channel = channel } end,
  InChatMessagingLockdown = function() return S.chatLockdown end,
}
PawnIsInitialized = nil
LE_PARTY_CATEGORY_HOME = 1
LE_PARTY_CATEGORY_INSTANCE = 2
SlashCmdList = {}
SLASH_ANTIGRIEF1, SLASH_ANTIGRIEF2 = nil, nil
AntiGriefDB = nil
-- Blizzard_InspectUI frame; S.inspectFrameShown simulates the player's own Inspect window
InspectFrame = { IsShown = function() return S.inspectFrameShown == true end }
function issecretvalue(v) return S.secret[v] == true end

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
date = os.date
time = os.time

-- Count chat lines containing a plain substring
function S.chatCount(sub)
  local n = 0
  for _, m in ipairs(S.chat) do if m:find(sub, 1, true) then n = n + 1 end end
  return n
end

---------------------------------------------------------------------------
-- Global strings (enUS)
---------------------------------------------------------------------------
-- Real 1.60.1 strings (docs/api-verification.md): a loot-history link and
-- roll ID come first.
LOOT_ROLL_NEED = "|HlootHistory:%d|h[Loot]|h: %s has selected Need for: %s"
LOOT_ROLL_NEED_SELF = "|HlootHistory:%d|h[Loot]|h: You have selected Need for: %s"
LOOT_ROLL_ROLLED_NEED = "|HlootHistory:%d|h[Loot]|h: Need Roll - %d for %s by %s"
LOOT_ROLL_ROLLED_NEED_ROLE_BONUS = "Need Roll - %d for %s by %s + Role Bonus"
-- Roll-won lines, verbatim from [KBIR] 1.60.1 enUS GlobalStrings
LOOT_ROLL_WON = "|HlootHistory:%d|h[Loot]|h: %s won: %s"
LOOT_ROLL_YOU_WON = "|HlootHistory:%d|h[Loot]|h: You won: %s"
LOOT_ROLL_WON_NO_SPAM_NEED = "|HlootHistory:%d|h[Loot]|h: %s (Need - %d, Main-Spec) Won: %s"
LOOT_ROLL_WON_NO_SPAM_NEED_OFF_SPEC = "|HlootHistory:%d|h[Loot]|h: %s (Need - %d, Off-Spec) Won: %s"
LOOT_ROLL_WON_NO_SPAM_GREED = "|HlootHistory:%d|h[Loot]|h: %s (Greed - %d) Won: %s"
LOOT_ROLL_ALL_PASSED = "|HlootHistory:%d|h[Loot]|h: Everyone passed on: %s"
-- The spec's older forms, kept for extra coverage (S.UseOldLootStrings)
S.OLD_LOOT = {
  LOOT_ROLL_NEED = "%s has selected Need for: %s",
  LOOT_ROLL_NEED_SELF = "You have selected Need for: %s",
  LOOT_ROLL_ROLLED_NEED = "Need Roll - %d for %s by %s",
}
function S.UseOldLootStrings()
  for k, v in pairs(S.OLD_LOOT) do _G[k] = v end
end
ITEM_SPELL_TRIGGER_ONEQUIP = "Equip:"
ITEM_SPELL_TRIGGER_ONUSE = "Use:"
ITEM_SPELL_TRIGGER_ONPROC = "Chance on hit:"
INVSLOT_RANGED = nil
INVTYPE_HEAD, INVTYPE_CHEST, INVTYPE_HAND = "Head", "Chest", "Hands"
INVTYPE_FINGER, INVTYPE_WEAPON, INVTYPE_ROBE = "Finger", "One-Hand", "Chest"
LOCALIZED_CLASS_NAMES_MALE = {
  WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
  SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}
S.locale = "enUS"
function GetLocale() return S.locale end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
-- def: { id, name, classID, subclassID, subType, equipLoc, ilvl, minLevel,
--        bind, stats = {KEY = n}, effects = {"Equip: ..."}, uncached, neverCache }
function S.AddItem(def)
  def.quality = def.quality or 4
  def.link = def.link or ("|cffa335ee|Hitem:%d::::::::60:::::::::|h[%s]|h|r"):format(def.id, def.name)
  S.items[def.id] = def
  return def.link
end

local function lookup(item)
  if type(item) == "number" then return S.items[item] end
  if type(item) == "string" then
    local id = tonumber(item:match("item:(%d+)"))
    return id and S.items[id]
  end
end

local function cached(def)
  if not def.uncached then return true end
  return def.cacheAt ~= nil and S.now >= def.cacheAt
end

local function GetItemInfoInstant(item)
  local d = lookup(item)
  if not d then return nil end
  return d.id, d.itemType or "Armor", d.subType, d.equipLoc, 134400, d.classID, d.subclassID
end

local function GetItemInfo(item)
  local d = lookup(item)
  if not d or not cached(d) then return nil end
  return d.name, d.link, d.quality, d.ilvl, d.minLevel or 0, d.itemType or "Armor", d.subType, 1,
    d.equipLoc, 134400, 0, d.classID, d.subclassID, d.bind or 0
end

local function GetItemStats(link)
  local d = lookup(link)
  local out = {}
  if d and d.stats then for k, v in pairs(d.stats) do out[k] = v end end
  return out
end

local function GetDetailedItemLevelInfo(link)
  local d = lookup(link)
  if not d or not cached(d) then return nil end
  return d.ilvl, false, d.ilvl
end

C_Item = {
  GetItemInfo = GetItemInfo,
  GetItemInfoInstant = GetItemInfoInstant,
  GetItemStats = GetItemStats,
  GetDetailedItemLevelInfo = GetDetailedItemLevelInfo,
  RequestLoadItemDataByID = function(id)
    S.loadRequests = S.loadRequests + 1
    local d = lookup(id)
    if d and d.uncached and not d.neverCache and not d.cacheAt then d.cacheAt = S.now + 0.5 end
  end,
}

C_TooltipInfo = {
  GetHyperlink = function(link)
    local d = lookup(link)
    if not d then return nil end
    local lines = { { leftText = d.name } }
    for _, e in ipairs(d.effects or {}) do lines[#lines + 1] = { leftText = "|cff00ff00" .. e .. "|r" } end
    return { lines = lines }
  end,
}

C_AddOns = { IsAddOnLoaded = function() return false end }

function GetLootRollItemLink(id) return S.rolls[id] end

---------------------------------------------------------------------------
-- Units, group, inspect
---------------------------------------------------------------------------
function S.SetGroup(units, kind)
  S.units = units
  S.groupKind = kind
end

local function U(unit) return type(unit) == "string" and S.units[unit] or nil end

function UnitGUID(u) local d = U(u); return d and d.guid end
function UnitClass(u)
  local d = U(u)
  if d then return LOCALIZED_CLASS_NAMES_MALE[d.class] or d.class, d.class end
end
function UnitLevel(u) local d = U(u); return d and d.level or 0 end
function UnitName(u)
  local d = U(u)
  if not d or d.noName then return nil end
  local n, r = d.name:match("^([^-]+)%-?(.*)$")
  return n, (r ~= "" and r or nil)
end
function GetUnitName(u, showServer)
  local d = U(u)
  if not d or d.noName then return nil end
  if showServer then return d.name end
  return (d.name:match("^[^-]+"))
end
function UnitIsUnit(a, b)
  local ga, gb = UnitGUID(a), UnitGUID(b)
  return ga ~= nil and ga == gb
end
function UnitIsPlayer(u) local d = U(u); return d ~= nil and not d.npc end
function UnitIsConnected(u) local d = U(u); return d ~= nil and not d.offline end
function CanInspect(u) local d = U(u); return d ~= nil and not d.noInspect end
function CheckInteractDistance(u) local d = U(u); return d ~= nil and not d.far end

function IsInRaid() return S.groupKind == "raid" end
function IsInGroup(category)
  if category == LE_PARTY_CATEGORY_INSTANCE and category ~= nil then
    return S.groupKind ~= nil and S.instance
  end
  return S.groupKind ~= nil
end
function GetNumGroupMembers()
  local n = 0
  for token in pairs(S.units) do
    if S.groupKind == "raid" and token:find("^raid%d+$") then n = n + 1 end
    if S.groupKind == "party" and (token == "player" or token:find("^party%d+$")) then n = n + 1 end
  end
  return n
end
function GetNumSubgroupMembers()
  local n = 0
  for token in pairs(S.units) do if token:find("^party%d+$") then n = n + 1 end end
  return n
end
function InCombatLockdown() return S.combat end

function NotifyInspect(u)
  S.notified[#S.notified + 1] = u
  S.inspectTarget = UnitGUID(u)
end
function ClearInspectPlayer()
  S.cleared = S.cleared + 1
  S.inspectTarget = nil
end

local function visibleItem(u, slot)
  local d = U(u)
  if not d or not d.items then return nil end
  if not UnitIsUnit(u, "player") and S.inspectTarget ~= d.guid then return nil end
  return d.items[slot], d
end

function GetInventoryItemLink(u, slot)
  local link, d = visibleItem(u, slot)
  if link and d.lateLinks and d.lateLinks[slot] and S.now < (d.linksReadyAt or math.huge) then return nil end
  return link
end
function GetInventoryItemID(u, slot)
  local link = visibleItem(u, slot)
  return link and tonumber(link:match("item:(%d+)")) or nil
end
-- Forever: the global spec functions (Blizzard_DeprecatedSpecialization) are
-- not loaded; C_SpecializationInfo is. S.playerSpecIndex / S.playerSpecID
-- drive the player's spec; unit.spec drives an inspected unit's (default 0).
GetSpecialization, GetSpecializationInfo, GetInspectSpecialization = nil, nil, nil
GetSpecializationInfoByID = nil
C_SpecializationInfo = {
  GetSpecialization = function() return S.playerSpecIndex end,
  GetSpecializationInfo = function(index)
    if index == S.playerSpecIndex then return S.playerSpecID or 0 end
    return 0
  end,
  GetInspectSpecialization = function(u) local d = U(u); return d and d.spec or 0 end,
}

Enum = {
  ItemClass = { Weapon = 2, Armor = 4 },
  ItemArmorSubclass = { Cloth = 1, Leather = 2, Mail = 3, Plate = 4, Shield = 6, Libram = 7, Idol = 8, Totem = 9 },
  ItemWeaponSubclass = {
    Axe1H = 0, Axe2H = 1, Bows = 2, Guns = 3, Mace1H = 4, Mace2H = 5, Polearm = 6, Sword1H = 7, Sword2H = 8,
    Staff = 10, Unarmed = 13, Generic = 14, Dagger = 15, Thrown = 16, Crossbow = 18, Wand = 19, Fishingpole = 20,
  },
}

function Ambiguate(name, context)
  if context == "short" then return (name:match("^[^-]+")) or name end
  return name
end

---------------------------------------------------------------------------
-- Settings API (options panel). Recorders, not a UI: S.cfg collects what
-- was registered. A test sets Settings = nil to model a client without it.
---------------------------------------------------------------------------
S.cfg = {
  categories = {},      -- RegisterVerticalLayoutCategory results
  addOnCategories = {}, -- RegisterAddOnCategory arguments
  settings = {},        -- variable -> setting
  controls = {},        -- { kind, category, setting, options, tooltip }
  opened = {},          -- OpenToCategory arguments
}

local function newCategory(name)
  local cat = { name = name, id = #S.cfg.categories + 1, initializers = {} }
  function cat:GetID() return self.id end
  function cat:GetName() return self.name end
  S.cfg.categories[#S.cfg.categories + 1] = cat
  local layout = { initializers = {} }
  function layout:AddInitializer(init) self.initializers[#self.initializers + 1] = init end
  return cat, layout
end

local function control(kind, category, setting, options, tooltip)
  local c = { kind = kind, category = category, setting = setting, options = options, tooltip = tooltip }
  S.cfg.controls[#S.cfg.controls + 1] = c
  return c
end

Settings = {
  VarType = { Boolean = "boolean", Number = "number", String = "string" },
  RegisterVerticalLayoutCategory = newCategory,
  -- Like the real API: binds to variableTbl by reference (no copy) and fills
  -- in the default only when the key is nil
  RegisterAddOnSetting = function(category, variable, variableKey, variableTbl, varType, name, default)
    if type(variableTbl) ~= "table" then error("RegisterAddOnSetting: variableTbl must be a table", 2) end
    if variableTbl[variableKey] == nil then variableTbl[variableKey] = default end
    local setting = {
      category = category, variable = variable, key = variableKey, tbl = variableTbl,
      varType = varType, name = name, default = default, callbacks = {}, updates = 0,
    }
    function setting:NotifyUpdate()
      self.updates = self.updates + 1
      local v = self.tbl[self.key]
      for _, cb in ipairs(self.callbacks) do cb(self, v) end
    end
    function setting:GetValue() return self.tbl[self.key] end
    function setting:SetValue(v)
      if type(v) ~= self.varType then
        error(("SetValue: %s expects %s, got %s"):format(tostring(self.variable), tostring(self.varType), type(v)), 2)
      end
      self.tbl[self.key] = v
      for _, cb in ipairs(self.callbacks) do cb(self, v) end
    end
    function setting:GetVariable() return self.variable end
    function setting:GetName() return self.name end
    function setting:GetDefaultValue() return self.default end
    function setting:SetValueChangedCallback(cb) self.callbacks[#self.callbacks + 1] = cb end
    S.cfg.settings[variable] = setting
    return setting
  end,
  SetOnValueChangedCallback = function(variable, cb)
    local s = S.cfg.settings[variable]
    if s then s.callbacks[#s.callbacks + 1] = function(setting, v) cb(nil, setting, v) end end
  end,
  CreateCheckbox = function(category, setting, tooltip)
    assert(setting and setting.varType == "boolean", "CreateCheckbox needs a boolean setting")
    return control("checkbox", category, setting, nil, tooltip)
  end,
  CreateSlider = function(category, setting, options, tooltip)
    assert(setting and setting.varType == "number", "CreateSlider needs a number setting")
    return control("slider", category, setting, options, tooltip)
  end,
  -- options is a function returning the entries; call it now, as the panel would
  CreateDropdown = function(category, setting, options, tooltip)
    assert(type(options) == "function", "CreateDropdown needs an options function")
    local entries = options()
    assert(type(entries) == "table", "dropdown options must return a table")
    for i = 1, 3 do
      assert(entries[i] and entries[i].value == i, "dropdown entry " .. i .. " must have value " .. i)
    end
    local c = control("dropdown", category, setting, options, tooltip)
    c.entries = entries
    return c
  end,
  CreateSliderOptions = function(minValue, maxValue, rate)
    -- like Settings.CreateSliderOptions: steps is the number of steps, not the step size
    local o = { minValue = minValue, maxValue = maxValue, steps = (maxValue - minValue) / rate, formatters = {} }
    function o:SetLabelFormatter(where, fn) self.formatters[where] = fn end
    return o
  end,
  CreateControlTextContainer = function()
    local c = { data = {} }
    function c:Add(value, label, tooltip) self.data[#self.data + 1] = { value = value, label = label, tooltip = tooltip } end
    function c:GetData() return self.data end
    return c
  end,
  -- each call is recorded, so #S.cfg.addOnCategories is the call count
  RegisterAddOnCategory = function(category) S.cfg.addOnCategories[#S.cfg.addOnCategories + 1] = category end,
  OpenToCategory = function(id) S.cfg.opened[#S.cfg.opened + 1] = id end,
}
MinimalSliderWithSteppersMixin = { Label = { Left = 0, Right = 1, Top = 2, Min = 3, Max = 4 } }


---------------------------------------------------------------------------
-- Round 4 additions: instance info, combat, friends/guild, own UI frames,
-- loot roll frames, tooltip post-calls, addon compartment
---------------------------------------------------------------------------
-- GetInstanceInfo: S.instanceInfo is its return list (nil -> open world)
S.instanceInfo = nil
function GetInstanceInfo()
  if S.instanceInfo then return unpack(S.instanceInfo) end
  return "Elwynn Forest", "none", 0, "", 0, 0, false, 0
end
function UnitAffectingCombat(u) local d = U(u); return d ~= nil and d.combat == true end
function UnitIsInMyGuild(u) local d = U(u); return d ~= nil and d.guild == true end
S.friends = {} -- guid -> true
C_FriendList = { IsFriend = function(guid) return S.friends[guid] == true end }
S.shift = false
function IsShiftKeyDown() return S.shift end
UIParent = CreateFrame("Frame", nil)
UISpecialFrames = {}

-- Text, check state, focus and message lines for our own windows. Added to
-- every frame CreateFrame makes from here on (the base stub ignores them).
local baseCreateFrame = CreateFrame
function CreateFrame(frameType, name, parent, template)
  local f = baseCreateFrame(frameType, name, parent)
  f.template = template
  function f:SetText(t) self.text = t end
  function f:GetText() return self.text end
  function f:SetChecked(v) self.checked = v and true or false end
  function f:GetChecked() return self.checked end
  function f:HighlightText() self.highlighted = true end
  function f:SetFocus() self.focused = true end
  function f:IsMouseOver() return self.mouseOver == true end
  if frameType == "ScrollingMessageFrame" then
    f.lines = {}
    function f:AddMessage(m) self.lines[#self.lines + 1] = m end
    function f:Clear() self.lines = {} end
  end
  return f
end
-- Calls a frame script the way the client would (OnClick, OnTextChanged, ...)
function S.run(frame, script, ...)
  local fn = frame.scripts[script]
  if fn then return fn(frame, ...) end
end
for _, n in ipairs({ "AntiGriefMenu", "AntiGriefLogWindow", "AntiGriefFeedback", "AntiGriefFeedbackLink" }) do
  rawset(_G, n, nil)
end
for i = 1, 6 do rawset(_G, "AntiGriefMenuItem" .. i, nil) end

-- Blizzard's loot roll windows: tests create them with S.rollFrame(i, rollID)
for i = 1, 4 do rawset(_G, "GroupLootFrame" .. i, nil); rawset(_G, "AntiGriefRollBadge" .. i, nil) end
function S.rollFrame(i, rollID)
  local f = baseCreateFrame("Frame", "GroupLootFrame" .. i)
  f.rollID = rollID
  f:Show()
  return f
end

-- Tooltips: post-calls registered per tooltip data type
S.postCalls = {}
Enum.TooltipDataType = { Item = 0 }
TooltipDataProcessor = {
  AddTooltipPostCall = function(kind, fn)
    S.postCalls[kind] = S.postCalls[kind] or {}
    table.insert(S.postCalls[kind], fn)
  end,
}
-- Shows `link` in a fake tooltip and runs the item post-calls; returns the added lines
function S.hoverItem(tooltip, link)
  tooltip.lines = {}
  tooltip.GetItem = function() return "item", link end
  for _, fn in ipairs(S.postCalls[Enum.TooltipDataType.Item] or {}) do fn(tooltip, {}) end
  return tooltip.lines
end
ItemRefTooltip = { lines = {} }
function ItemRefTooltip:AddLine(t) self.lines[#self.lines + 1] = t end

return S
