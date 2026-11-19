-- AntiGrief: log window (/ag log, minimap menu > Log). A movable panel with
-- the saved flag history, filters (player name, minimum severity, wins only)
-- and per-player totals. Built from plain frames and standard templates, no
-- Blizzard menus (see Minimap.lua on why). The history itself comes from
-- ns.FilteredHistory in AntiGrief.lua.

local _, ns = ...

local Window = {}
ns.LogWindow = Window

local WIDTH, HEIGHT = 620, 400
local SEV_STEPS = { nil, 1, 2, 3 } -- severity filter cycle: all, Low+, Medium+, High
local SEV_LABEL = { "All", "Low+", "Medium+", "High" }

local frame        -- created on first open
local filter = { player = "", minSev = nil, winsOnly = false }
local sevStep = 1
Window.lines, Window.totals = {}, {} -- last render (read by the tests)

-- "Bob: 3 Needs, 1 win, 1 not equipped" for the most flagged players
local MAX_TOTALS = 6
local function TotalsText(totals)
  if #totals == 0 then return "|cff999999No flags match.|r" end
  local parts = {}
  for i = 1, math.min(#totals, MAX_TOTALS) do
    local t = totals[i]
    local bits = {}
    if t.needs > 0 then bits[#bits + 1] = t.needs .. (t.needs == 1 and " Need" or " Needs") end
    if t.wins > 0 then bits[#bits + 1] = t.wins .. (t.wins == 1 and " win" or " wins") end
    if t.unworn > 0 then bits[#bits + 1] = t.unworn .. " not equipped" end
    parts[#parts + 1] = ("|cffffffff%s|r: %s"):format(t.name, table.concat(bits, ", "))
  end
  if #totals > MAX_TOTALS then parts[#parts + 1] = ("+%d more"):format(#totals - MAX_TOTALS) end
  return table.concat(parts, "   ")
end

local function Render()
  if not frame or not frame:IsShown() or not ns.FilteredHistory or not ns.db then return end
  local lines, totals = ns.FilteredHistory(filter)
  Window.lines, Window.totals = lines, totals
  frame.totals:SetText(TotalsText(totals))
  local box = frame.messages
  box:Clear()
  if #lines == 0 then
    box:AddMessage(#ns.db.log == 0 and "|cff999999No flags logged yet.|r"
      or "|cff999999Nothing matches these filters.|r")
  end
  for _, l in ipairs(lines) do box:AddMessage(l) end
  if box.ScrollToBottom then box:ScrollToBottom() end
end

local function SevButtonText()
  return "Severity: " .. SEV_LABEL[sevStep]
end

local function Create()
  local f = CreateFrame("Frame", "AntiGriefLogWindow", UIParent, "BackdropTemplate")
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0, 0, 0, 0.92)
  end

  local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
  title:SetText("AntiGrief log")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

  -- Filters: player name, severity cycle, wins only, reset
  local nameLabel = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  nameLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -36)
  nameLabel:SetText("Player:")
  local name = CreateFrame("EditBox", "AntiGriefLogWindowName", f, "InputBoxTemplate")
  name:SetSize(120, 20)
  name:SetPoint("LEFT", nameLabel, "RIGHT", 10, 0)
  name:SetAutoFocus(false)
  name:SetScript("OnTextChanged", function(self)
    filter.player = self:GetText() or ""
    Render()
  end)
  name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  name:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  f.name = name

  local sev = CreateFrame("Button", "AntiGriefLogWindowSeverity", f, "UIPanelButtonTemplate")
  sev:SetSize(130, 22)
  sev:SetPoint("LEFT", name, "RIGHT", 12, 0)
  sev:SetText(SevButtonText())
  sev:SetScript("OnClick", function(self)
    sevStep = sevStep % #SEV_LABEL + 1
    filter.minSev = SEV_STEPS[sevStep]
    self:SetText(SevButtonText())
    Render()
  end)
  f.sev = sev

  local wins = CreateFrame("CheckButton", "AntiGriefLogWindowWins", f, "UICheckButtonTemplate")
  wins:SetSize(24, 24)
  wins:SetPoint("LEFT", sev, "RIGHT", 10, 0)
  local winsLabel = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  winsLabel:SetPoint("LEFT", wins, "RIGHT", 2, 0)
  winsLabel:SetText("Wins only")
  wins:SetScript("OnClick", function(self)
    filter.winsOnly = self:GetChecked() and true or false
    Render()
  end)
  f.wins = wins

  local reset = CreateFrame("Button", "AntiGriefLogWindowReset", f, "UIPanelButtonTemplate")
  reset:SetSize(70, 22)
  reset:SetPoint("LEFT", winsLabel, "RIGHT", 14, 0)
  reset:SetText("Reset")
  reset:SetScript("OnClick", function()
    filter.player, filter.minSev, filter.winsOnly, sevStep = "", nil, false, 1
    name:SetText("")
    sev:SetText(SevButtonText())
    wins:SetChecked(false)
    Render()
  end)
  f.reset = reset

  -- Per-player totals
  local totals = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  totals:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -64)
  totals:SetPoint("RIGHT", f, "RIGHT", -14, 0)
  totals:SetJustifyH("LEFT")
  totals:SetWordWrap(true)
  f.totals = totals

  -- History: scrolls with the mouse wheel; item links show their tooltip
  local box = CreateFrame("ScrollingMessageFrame", "AntiGriefLogWindowMessages", f)
  box:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -86)
  box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
  box:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
  box:SetJustifyH("LEFT")
  box:SetFading(false)
  box:SetMaxLines(2000)
  box:SetIndentedWordWrap(true)
  box:EnableMouseWheel(true)
  box:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then self:ScrollUp() else self:ScrollDown() end
  end)
  box:SetHyperlinksEnabled(true)
  box:SetScript("OnHyperlinkEnter", function(self, link)
    if GameTooltip and type(link) == "string" and link:find("^item:") then
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      pcall(GameTooltip.SetHyperlink, GameTooltip, link)
      GameTooltip:Show()
    end
  end)
  box:SetScript("OnHyperlinkLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  f.messages = box

  f:SetScript("OnShow", Render)
  f:Hide()
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "AntiGriefLogWindow") end
  return f
end

-- Opens the window (or closes it if open)
function Window.Toggle()
  frame = frame or Create()
  if frame:IsShown() then
    frame:Hide()
  else
    frame:Show()
    Render() -- OnShow renders in game; explicit for clients/tests without it
  end
end

-- Redraws if open (called by AntiGrief.lua when the log changes)
function Window.Refresh()
  Render()
end

-- For the tests: the frame and the filter table
function Window.Frame() return frame end
function Window.Filter() return filter end
