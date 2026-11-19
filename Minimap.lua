-- AntiGrief: minimap button. The AntiGrief logo (media/minimap.tga) in the
-- standard minimap-button ring. Click opens a small menu (Log / Settings / ...); drag moves it
-- around the minimap edge. No libraries: the layout and
-- placement math follow the common LibDBIcon approach.
--
-- Settings (ns.db): minimapButton (show/hide), minimapAngle (degrees, 0 = east,
-- counter-clockwise). Init is called by AntiGrief.lua after ns.db is loaded.

local _, ns = ...

local Button = {}
ns.MinimapButton = Button

local SIZE   = 31  -- button frame; the ring texture is drawn larger from its top-left
local RADIUS = 5   -- how far outside the minimap edge the button centre sits

-- Standard minimap-button art in the client (file data IDs, as LibDBIcon uses)
local RING_TEX      = 136430 -- Interface\Minimap\MiniMap-TrackingBorder
local DISC_TEX      = 136467 -- Interface\Minimap\UI-Minimap-Background
local HIGHLIGHT_TEX = 136477 -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight
-- Our logo (64x64 TGA with alpha; the client finds the extension itself)
local ICON_TEX      = "Interface\\AddOns\\AntiGrief\\media\\minimap"

local button -- created once in Init

local function Slash(cmd)
  local fn = SlashCmdList and SlashCmdList.ANTIGRIEF
  if fn then fn(cmd) end
end

-- Places the button on the minimap edge at ns.db.minimapAngle. Round minimaps
-- (the default) put it on the circle; a square minimap (GetMinimapShape, set
-- by some UI addons) pushes it out to the square's edge.
local function UpdatePosition()
  if not button or not ns.db then return end
  local angle = math.rad(ns.db.minimapAngle or 225)
  local x, y = math.cos(angle), math.sin(angle)
  local w = Minimap:GetWidth() / 2 + RADIUS
  local h = Minimap:GetHeight() / 2 + RADIUS
  local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
  if shape == "SQUARE" then
    local dw, dh = math.sqrt(2 * w * w) - 10, math.sqrt(2 * h * h) - 10
    x = math.max(-w, math.min(x * dw, w))
    y = math.max(-h, math.min(y * dh, h))
  else
    x, y = x * w, y * h
  end
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Angle from the minimap centre to the cursor, in degrees 0-360
local function CursorAngle()
  local mx, my = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  px, py = px / scale, py / scale
  return math.deg(math.atan2(py - my, px - mx)) % 360
end

-- Only runs while the button is being dragged (set on drag start, cleared on stop)
local function OnDragUpdate()
  ns.db.minimapAngle = CursorAngle()
  UpdatePosition()
end

-- Click menu: Log (the log window), Settings (options page), then after a
-- divider Clear Log History and Feedback (Discord link in a copy box).
--
-- A small frame of our own, not Blizzard's Menu API: menus an addon opens
-- through MenuUtil share Blizzard's menu system with the unit right-click
-- menus, and in game that left the raid-marker entries blocked
-- (ADDON_ACTION_FORBIDDEN SetRaidTarget, blamed on AntiGrief). Closes on a
-- pick, a click anywhere else (GLOBAL_MOUSE_DOWN) or Escape (UISpecialFrames).
local MENU_ITEMS = {
  { "Log", "log" },
  { "Settings", "config" },
  false, -- divider
  { "Clear Log History", "clear" },
  { "Feedback", "feedback" },
}
local MENU_WIDTH, ITEM_HEIGHT, PAD = 150, 18, 8

local menu -- created on first open

local function CreateMenu()
  local m = CreateFrame("Frame", "AntiGriefMenu", UIParent, "BackdropTemplate")
  m:SetFrameStrata("DIALOG")
  m:SetClampedToScreen(true)
  m:EnableMouse(true)
  if m.SetBackdrop then
    m:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    m:SetBackdropColor(0, 0, 0, 0.92)
  end
  local title = m:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("TOPLEFT", m, "TOPLEFT", PAD + 2, -PAD)
  title:SetText("AntiGrief")
  local y = -PAD - ITEM_HEIGHT
  m.items = {}
  for i, item in ipairs(MENU_ITEMS) do
    if item then
      local b = CreateFrame("Button", "AntiGriefMenuItem" .. i, m)
      b:SetSize(MENU_WIDTH - 2 * PAD, ITEM_HEIGHT)
      b:SetPoint("TOPLEFT", m, "TOPLEFT", PAD, y)
      b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      local text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      text:SetPoint("LEFT", b, "LEFT", 4, 0)
      text:SetText(item[1])
      local cmd = item[2]
      b:SetScript("OnClick", function()
        m:Hide()
        Slash(cmd)
      end)
      m.items[#m.items + 1] = { text = item[1], cmd = cmd, button = b }
      y = y - ITEM_HEIGHT
    else
      local line = m:CreateTexture(nil, "ARTWORK")
      line:SetColorTexture(1, 1, 1, 0.2)
      line:SetSize(MENU_WIDTH - 2 * PAD, 1)
      line:SetPoint("TOPLEFT", m, "TOPLEFT", PAD, y - 4)
      m.items[#m.items + 1] = { divider = true }
      y = y - 9
    end
  end
  m:SetSize(MENU_WIDTH, -y + PAD)
  m:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
  m:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
  -- A click outside the menu (or its button, which toggles it itself) closes it
  m:SetScript("OnEvent", function(self)
    if not self:IsMouseOver() and not (button and button:IsMouseOver()) then self:Hide() end
  end)
  m:Hide()
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "AntiGriefMenu") end
  return m
end

local function ToggleMenu(owner)
  menu = menu or CreateMenu()
  if menu:IsShown() then menu:Hide(); return end
  menu:ClearAllPoints()
  menu:SetPoint("TOPRIGHT", owner, "BOTTOMLEFT", 8, 8)
  menu:Show()
end
Button.ToggleMenu = ToggleMenu
function Button.Menu() return menu end

-- `compartment`: shown for the AddOns-menu entry, which has no menu or drag
local function ShowTooltip(self, compartment)
  if not GameTooltip then return end
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetText("AntiGrief")
  local db = ns.db
  if db then
    local sev = ns.Data and ns.Data.SEV_NAME and ns.Data.SEV_NAME[db.minSeverity] or "?"
    GameTooltip:AddLine(db.enabled and ("|cff40ff40On|r, alerts at " .. sev .. "+") or "|cffff4040Off|r", 1, 1, 1)
    if ns.Inspect and ns.Inspect.Status then
      local ok, scanned, total = pcall(ns.Inspect.Status)
      if ok and total and total > 0 then
        GameTooltip:AddLine(("Group gear scanned: %d/%d"):format(scanned, total), 1, 1, 1)
      end
    end
  end
  if compartment then
    GameTooltip:AddLine("Click: log window; right-click: settings", 0.8, 0.8, 0.8)
  else
    GameTooltip:AddLine("Click: menu (Log, Settings)", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Shift-click: log window; shift-right-click: settings", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Drag: move", 0.8, 0.8, 0.8)
  end
  GameTooltip:Show()
end

local function Create()
  local b = CreateFrame("Button", "AntiGriefMinimapButton", Minimap)
  b:SetSize(SIZE, SIZE)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture(HIGHLIGHT_TEX)

  local disc = b:CreateTexture(nil, "BACKGROUND")
  disc:SetSize(24, 24)
  disc:SetTexture(DISC_TEX)
  disc:SetVertexColor(0, 0, 0, 1) -- tint the round background solid black
  disc:SetPoint("CENTER", b, "CENTER", 0, 0)

  -- Logo over the black disc. If the client refuses the file, fall back to
  -- the old red "AG" text on the disc.
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetSize(24, 24)
  icon:SetPoint("CENTER", b, "CENTER", 0, 0)
  if icon:SetTexture(ICON_TEX) == false then
    icon:Hide()
    local text = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    text:SetPoint("CENTER", b, "CENTER", 0, 0)
    text:SetText("AG")
    text:SetTextColor(1, 0.15, 0.15)
  end

  local ring = b:CreateTexture(nil, "OVERLAY")
  ring:SetSize(50, 50)
  ring:SetTexture(RING_TEX)
  ring:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)

  b:SetScript("OnClick", function(self, mouse)
    if GameTooltip then GameTooltip:Hide() end
    if IsShiftKeyDown and IsShiftKeyDown() then
      -- shortcuts: shift-left the log window, shift-right the options
      Slash(mouse == "RightButton" and "config" or "log")
      return
    end
    ToggleMenu(self)
  end)
  b:SetScript("OnEnter", function(self) ShowTooltip(self) end) -- not OnEnter's 2nd arg (motion)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  b:SetScript("OnDragStart", function(self)
    if GameTooltip then GameTooltip:Hide() end
    self:SetScript("OnUpdate", OnDragUpdate)
  end)
  b:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  return b
end

-- Shows or hides the button to match ns.db.minimapButton and re-places it.
function Button.Refresh()
  if not button or not ns.db then return end
  if ns.db.minimapButton then
    UpdatePosition()
    button:Show()
  else
    button:Hide()
  end
end

-- Called once by AntiGrief.lua after ns.db is loaded. Does nothing if the
-- minimap isn't there (a UI replacement may remove it).
function Button.Init()
  if button or type(Minimap) ~= "table" or not CreateFrame or not ns.db then return end
  button = Create()
  Button.Refresh()
end

-- AddOns menu (the addon compartment, next to the minimap): the TOC names
-- these functions. Left-click opens the log window, right-click the
-- settings. Works with the minimap button hidden.
local function MouseButton(...)
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if v == "LeftButton" or v == "RightButton" then return v end
  end
end
local function FirstFrame(...)
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if type(v) == "table" then return v end
  end
end

function AntiGrief_OnAddonCompartmentClick(_, ...)
  Slash(MouseButton(...) == "RightButton" and "config" or "log")
end

function AntiGrief_OnAddonCompartmentEnter(_, ...)
  local owner = FirstFrame(...)
  if owner then ShowTooltip(owner, true) end
end

function AntiGrief_OnAddonCompartmentLeave()
  if GameTooltip then GameTooltip:Hide() end
end
