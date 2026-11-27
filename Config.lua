-- AntiGrief: options page in the game's Settings UI
-- (Esc > Options > AddOns > AntiGrief), opened with /ag config.
--
-- Uses the Mainline Settings API (Blizzard_Settings_Shared, loads on game
-- type camelot). Each control is an "addon setting" bound to a key of ns.db
-- (the AntiGriefDB table): the panel reads and writes ns.db[key] directly,
-- so slash commands and the panel share one value. See
-- docs/api-verification.md, "Settings panel".

local _, ns = ...

local Config = {}
ns.Config = Config

local PREFIX = "|cff40c0ffAntiGrief|r: "
local CATEGORY_NAME = "AntiGrief"
local VAR_PREFIX = "ANTIGRIEF_" -- Settings variable names are global; keep ours unique

local category      -- the registered category, nil until Init succeeds
local settings = {} -- ns.db key -> setting object

local function Print(msg)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg) end
end

-- Every function this file calls on the Settings table.
local function HasSettingsAPI()
  local S = Settings
  return type(S) == "table"
    and type(S.RegisterVerticalLayoutCategory) == "function"
    and type(S.RegisterAddOnCategory) == "function"
    and type(S.RegisterAddOnSetting) == "function"
    and type(S.CreateCheckbox) == "function"
    and type(S.CreateSlider) == "function"
    and type(S.CreateSliderOptions) == "function"
    and type(S.CreateDropdown) == "function"
    and type(S.CreateControlTextContainer) == "function"
    and type(S.OpenToCategory) == "function"
end

-- Controls, in display order. `default` also sets the setting's type
-- (boolean or number), which must match the type stored in ns.db.
local CHECKBOX, DROPDOWN, SLIDER = 1, 2, 3
local CONTROLS = {
  { key = "enabled", kind = CHECKBOX, default = true, label = "Enabled",
    tooltip = "Watch Need rolls in your group and warn you about ones that don't fit." },
  { key = "minSeverity", kind = DROPDOWN, default = 2, label = "Minimum severity",
    tooltip = "Only warn about Need rolls at this severity or higher.",
    choices = {
      { 1, "Low",    "Warn about everything, including small notes." },
      { 2, "Medium", "Warn about rolls that are probably not an upgrade or not a good fit." },
      { 3, "High",   "Warn only when the item clearly can't be used or doesn't suit the class." },
    } },
  { key = "sound", kind = CHECKBOX, default = true, label = "Play sound",
    tooltip = "Play the raid warning horn when a flagged player wins the item, and an alarm when they still haven't equipped it. Need rolls are silent." },
  { key = "screen", kind = CHECKBOX, default = true, label = "Show banner",
    tooltip = "Show a one-line warning in the middle of your screen." },
  { key = "announce", kind = CHECKBOX, default = false, label = "Announce to group",
    tooltip = "Post each warning publicly to party, raid or instance chat, where everyone in the group can read it." },
  { key = "dropReport", kind = CHECKBOX, default = true, label = "Show fit report on new drops",
    tooltip = "When an item drops, print in chat which group members it suits." },
  { key = "upgradeMargin", kind = SLIDER, default = 8, label = "Upgrade margin (item levels)",
    min = 0, max = 30, step = 1,
    tooltip = "How many item levels below someone's current gear a drop can be before their Need is flagged as not an upgrade." },
  { key = "usePawn", kind = CHECKBOX, default = true, label = "Use Pawn scoring",
    tooltip = "If the Pawn addon is installed, use its scores instead of item level to judge upgrades." },
  { key = "skipFriends", kind = CHECKBOX, default = true, label = "Don't flag friends or guildmates",
    tooltip = "Never warn about Need rolls from your character friends or members of your guild. Use /ag ignore <name> for anyone else." },
  { key = "tooltip", kind = CHECKBOX, default = true, label = "Item tooltip lines",
    tooltip = "In a group, add who an item suits (and why it doesn't suit others) to item tooltips." },
  { key = "lootBadge", kind = CHECKBOX, default = true, label = "Badge on the roll window",
    tooltip = "When an item drops, show who it fits in a small label under the loot roll window." },
  { key = "minimapButton", kind = CHECKBOX, default = true, label = "Show minimap button",
    tooltip = "Show the AG button on the minimap. Click it for the log or these settings; drag it to move it. AntiGrief is also in the AddOns menu by the minimap.",
    onChange = function()
      if ns.MinimapButton and ns.MinimapButton.Refresh then ns.MinimapButton.Refresh() end
    end },
}

local function BuildControl(cat, c, db)
  local S = Settings
  local setting = S.RegisterAddOnSetting(cat, VAR_PREFIX .. c.key, c.key, db,
    type(c.default), c.label, c.default)
  if not setting then return end
  settings[c.key] = setting

  if c.kind == CHECKBOX then
    S.CreateCheckbox(cat, setting, c.tooltip)
    if c.onChange and setting.SetValueChangedCallback then
      setting:SetValueChangedCallback(function() c.onChange() end)
    end
  elseif c.kind == DROPDOWN then
    local choices = c.choices
    local function GetOptions()
      local container = S.CreateControlTextContainer()
      for _, ch in ipairs(choices) do container:Add(ch[1], ch[2], ch[3]) end
      return container:GetData()
    end
    S.CreateDropdown(cat, setting, GetOptions, c.tooltip)
  elseif c.kind == SLIDER then
    local options = S.CreateSliderOptions(c.min, c.max, c.step)
    local label = MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label
    if label and label.Right and options.SetLabelFormatter then
      options:SetLabelFormatter(label.Right, function(value)
        return tostring(math.floor(value + 0.5))
      end)
    end
    S.CreateSlider(cat, setting, options, c.tooltip)
    -- Keep the saved value a whole number even if the slider reports a
    -- fraction. Written straight to the table; the setting reads it live.
    if setting.SetValueChangedCallback then
      setting:SetValueChangedCallback(function(_, value)
        if type(value) == "number" and value ~= math.floor(value) and ns.db then
          ns.db[c.key] = math.floor(value + 0.5)
        end
      end)
    end
  end
end

local function DoInit()
  local db = ns.db
  if type(db) ~= "table" then return end
  local cat = Settings.RegisterVerticalLayoutCategory(CATEGORY_NAME)
  if not cat then return end
  for _, c in ipairs(CONTROLS) do BuildControl(cat, c, db) end
  Settings.RegisterAddOnCategory(cat)
  category = cat
end

-- Called once by AntiGrief.lua after ns.db is loaded (ADDON_LOADED).
-- Does nothing if the Settings API is missing or Init already ran.
function Config.Init()
  if category or not HasSettingsAPI() then return end
  local ok, err = pcall(DoInit)
  if not ok then
    category = nil
    Print("options page unavailable (" .. tostring(err) .. "); use the /ag commands.")
  end
end

-- Opens the AntiGrief page in Esc > Options > AddOns.
function Config.Open()
  if not category or not HasSettingsAPI() then
    Print("the options page isn't available on this client; type /ag for the commands.")
    return
  end
  -- C_SettingsUtil.OpenSettingsPanel is marked HasRestrictions; don't try
  -- it in combat, where a block can't be caught.
  if InCombatLockdown and InCombatLockdown() then
    Print("can't open the options in combat; try again afterwards, or use the /ag commands.")
    return
  end
  local id = category.GetID and category:GetID()
  local ok = pcall(Settings.OpenToCategory, id)
  if not ok then
    Print("couldn't open the options page; type /ag for the commands.")
  end
end

-- Called after a slash command changes ns.db[key]. The setting already reads
-- ns.db live; this tells an open panel to redraw the control. Without a key,
-- refreshes every control.
function Config.Refresh(key)
  if key == nil then
    for k in pairs(settings) do Config.Refresh(k) end
    return
  end
  local setting = settings[key]
  if setting and setting.NotifyUpdate then
    pcall(setting.NotifyUpdate, setting)
  end
end
