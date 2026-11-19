-- AntiGrief: who a drop suits, shown where you look while rolling.
--
-- 1) Roll-window badge (setting lootBadge): when an item drops, a small
--    label under Blizzard's roll window: "Fits: Bob, Ann" / "Not for: Cy".
--    Our own frame, anchored to GroupLootFrame1-4 (found by .rollID); we
--    only read those frames, never move, parent or write to them.
-- 2) Item tooltip lines (setting tooltip): hovering gear while in a group
--    adds "AntiGrief: suits ..." and the top reason it doesn't suit others.
--    Uses TooltipDataProcessor.AddTooltipPostCall (runs isolated from the
--    tooltip's own code).
--
-- Verdicts come from ns.EvaluateGroup (AntiGrief.lua). See
-- docs/api-verification.md, "Loot roll frames" and "Item tooltip hook".

local _, ns = ...
local D = ns.Data

local LootUI = {}
ns.LootUI = LootUI

local NUM_ROLL_FRAMES = 4      -- GroupLootFrame1..4 (Blizzard GroupLootFrame.lua)
local FIND_TRIES, FIND_GAP = 10, 0.2 -- the roll frame may show just after START_LOOT_ROLL
local MAX_NAMES = 4            -- names per badge line before "+N"
local TOOLTIP_MAX_MISFITS = 4  -- tooltip lines for members it doesn't suit
local TOOLTIP_CACHE = 5        -- seconds a tooltip verdict is reused for the same item

local FIT_COLOR, GREY_COLOR = "ff40ff40", "ff999999"

local function Secret(v) return issecretvalue and issecretvalue(v) end

local function NameList(names)
  if #names <= MAX_NAMES then return table.concat(names, ", ") end
  local shown = {}
  for i = 1, MAX_NAMES do shown[i] = names[i] end
  return table.concat(shown, ", ") .. (" +%d"):format(#names - MAX_NAMES)
end

-- Splits verdicts into names it fits and names it doesn't (highest severity first)
local function Split(results)
  local fits, misfits = {}, {}
  for _, r in ipairs(results) do
    if ns.Fits(r) then fits[#fits + 1] = ns.Short(r.who.name) else misfits[#misfits + 1] = r end
  end
  table.sort(misfits, function(a, b) return a.maxSev > b.maxSev end)
  return fits, misfits
end

---------------------------------------------------------------------------
-- Roll-window badges
---------------------------------------------------------------------------
local badges = {} -- roll frame index -> our badge frame

local function BadgeText(results)
  local fits, misfits = Split(results)
  local first = #fits > 0 and ("|c%sFits: %s|r"):format(FIT_COLOR, NameList(fits))
    or ("|c%sFits nobody in the group|r"):format(GREY_COLOR)
  if #misfits == 0 then return first end
  local names = {}
  for i, r in ipairs(misfits) do names[i] = ns.Short(r.who.name) end
  local color = D.SEV_COLOR[misfits[1].maxSev] or GREY_COLOR
  return first .. ("\n|c%sNot for: %s|r"):format(color, NameList(names))
end
LootUI.BadgeText = BadgeText

local function RollFrameFor(rollID)
  for i = 1, NUM_ROLL_FRAMES do
    local f = _G["GroupLootFrame" .. i]
    if type(f) == "table" and f.rollID == rollID and f.IsShown and f:IsShown() then return f, i end
  end
end

local function Badge(index)
  if badges[index] then return badges[index] end
  local b = CreateFrame("Frame", "AntiGriefRollBadge" .. index, UIParent, "BackdropTemplate")
  b:SetSize(220, 30)
  b:SetFrameStrata("HIGH")
  if b.SetBackdrop then
    b:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", tile = true, tileSize = 16,
      insets = { left = 0, right = 0, top = 0, bottom = 0 } })
    b:SetBackdropColor(0, 0, 0, 0.75)
  end
  local text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  text:SetPoint("TOPLEFT", b, "TOPLEFT", 6, -4)
  text:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  text:SetJustifyH("LEFT")
  b.text = text
  -- Hide once the roll window closes or is reused for another roll
  local elapsed = 0
  b:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + (dt or 0)
    if elapsed < 0.25 then return end
    elapsed = 0
    local target = self.target
    if not target or not target:IsShown() or target.rollID ~= self.rollID then self:Hide() end
  end)
  b:Hide()
  badges[index] = b
  return b
end

-- Called by AntiGrief.lua's drop report with the group's verdicts
function LootUI.ShowBadge(rollID, link, results, tries)
  if not ns.db or not ns.db.lootBadge or type(results) ~= "table" or #results == 0 then return end
  local target, index = RollFrameFor(rollID)
  if not target then
    tries = (tries or 0) + 1
    if tries < FIND_TRIES and C_Timer and C_Timer.After then
      C_Timer.After(FIND_GAP, function() LootUI.ShowBadge(rollID, link, results, tries) end)
    end
    return
  end
  local b = Badge(index)
  b.target, b.rollID, b.link = target, rollID, link
  b.text:SetText(BadgeText(results))
  local h = b.text.GetStringHeight and b.text:GetStringHeight()
  if type(h) == "number" and h > 0 then b:SetHeight(h + 8) end
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 8, 2)
  b:Show()
end

function LootUI.Badge(index) return badges[index] end

---------------------------------------------------------------------------
-- Item tooltip lines
---------------------------------------------------------------------------
local cache = { link = nil, t = 0, results = nil }

local function Verdicts(link)
  local now = GetTime()
  if cache.link == link and now - cache.t < TOOLTIP_CACHE then return cache.results end
  local results = ns.EvaluateGroup(link)
  cache.link, cache.t, cache.results = link, now, results
  return results
end

-- Lines to add for `link`: { text, r, g, b }, or nil
function LootUI.TooltipLines(link)
  if not ns.db or not ns.db.enabled or not ns.db.tooltip or not IsInGroup() then return nil end
  if type(link) ~= "string" or Secret(link) then return nil end
  local results = Verdicts(link)
  if not results then return nil end
  local fits, misfits = Split(results)
  local lines = {}
  if #fits > 0 then
    lines[1] = ("|c%sAntiGrief: suits %s|r"):format(FIT_COLOR, NameList(fits))
  else
    lines[1] = ("|c%sAntiGrief: suits nobody in the group|r"):format(GREY_COLOR)
  end
  for i = 1, math.min(#misfits, TOOLTIP_MAX_MISFITS) do
    local r = misfits[i]
    local color = D.SEV_COLOR[r.maxSev] or GREY_COLOR
    local top = ns.TopFinding(r.findings)
    lines[#lines + 1] = ("|c%s  %s: %s|r"):format(color, ns.Short(r.who.name),
      (top.text:gsub("|r", "|r|c" .. color)))
  end
  if #misfits > TOOLTIP_MAX_MISFITS then
    lines[#lines + 1] = ("|c%s  +%d more|r"):format(GREY_COLOR, #misfits - TOOLTIP_MAX_MISFITS)
  end
  return lines
end

local function OnItemTooltip(tooltip)
  if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end -- not the comparison tooltips
  if not tooltip.GetItem then return end
  local _, link = tooltip:GetItem()
  local lines = LootUI.TooltipLines(link)
  if not lines then return end
  for _, l in ipairs(lines) do tooltip:AddLine(l) end
end

local hooked = false
-- Called once by AntiGrief.lua at ADDON_LOADED
function LootUI.Init()
  if hooked then return end
  local processor = TooltipDataProcessor
  if type(processor) ~= "table" or type(processor.AddTooltipPostCall) ~= "function" then return end
  if not (Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item) then return end
  processor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip) pcall(OnItemTooltip, tooltip) end)
  hooked = true
end
