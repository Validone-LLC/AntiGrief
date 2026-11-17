-- AntiGrief: minimap button. A black disc with a red "AG" in the standard
-- minimap-button ring. Click opens a menu (Log / Settings); drag moves it
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

-- Click menu: Log (opens the AG Logs chat tab with the flag history),
-- Settings (options page), then after a divider Clear Log History and
-- Feedback (Discord link in a copy box).
-- Uses the 11.0+ Menu API (Blizzard_Menu, MenuUtil.CreateContextMenu).
-- Returns false if the menu couldn't be shown, so the caller can fall back.
local function MenuGenerator(_, root)
  root:CreateTitle("AntiGrief")
  root:CreateButton("Log", function() Slash("history") end)
  root:CreateButton("Settings", function() Slash("config") end)
  if root.CreateDivider then root:CreateDivider() end
  root:CreateButton("Clear Log History", function() Slash("clear") end)
  root:CreateButton("Feedback", function() Slash("feedback") end)
end

local function OpenMenu(owner)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return false end
  return (pcall(MenuUtil.CreateContextMenu, owner, MenuGenerator))
end

local function ShowTooltip(self)
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
  GameTooltip:AddLine("Click: Log or Settings", 0.8, 0.8, 0.8)
  GameTooltip:AddLine("Drag: move", 0.8, 0.8, 0.8)
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

  local text = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  text:SetPoint("CENTER", b, "CENTER", 0, 0)
  text:SetText("AG")
  text:SetTextColor(1, 0.15, 0.15)

  local ring = b:CreateTexture(nil, "OVERLAY")
  ring:SetSize(50, 50)
  ring:SetTexture(RING_TEX)
  ring:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)

  b:SetScript("OnClick", function(self, mouse)
    if GameTooltip then GameTooltip:Hide() end
    if not OpenMenu(self) then
      -- no menu API: left-click options, right-click log
      if mouse == "RightButton" then Slash("history") else Slash("config") end
    end
  end)
  b:SetScript("OnEnter", ShowTooltip)
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
