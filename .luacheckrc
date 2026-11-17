-- luacheck config for AntiGrief (WoW runs Lua 5.1)
std = "lua51"
max_line_length = false
codes = true

exclude_files = { "docs/**", ".claude/**" }

-- Globals the addon writes
globals = {
  "AntiGriefDB",
  "SLASH_ANTIGRIEF1",
  "SLASH_ANTIGRIEF2",
  "SlashCmdList",
}

-- WoW API and global strings the addon reads
read_globals = {
  -- C_ namespaces
  "C_AddOns", "C_ChatInfo", "C_Item", "C_SpecializationInfo", "C_Timer", "C_TooltipInfo",
  "Enum", "RaidWarningUtil",
  -- items
  "GetItemInfo", "GetItemInfoInstant", "GetItemStats", "GetDetailedItemLevelInfo",
  "GetInventoryItemLink", "GetInventoryItemID", "GetLootRollItemLink",
  -- units, group, inspect
  "UnitClass", "UnitGUID", "UnitLevel", "UnitName", "GetUnitName", "UnitIsUnit", "UnitIsPlayer",
  "UnitIsConnected", "CanInspect", "CheckInteractDistance", "NotifyInspect", "ClearInspectPlayer",
  "InspectFrame", "IsInRaid", "IsInGroup", "GetNumGroupMembers", "GetNumSubgroupMembers",
  "InCombatLockdown", "Ambiguate",
  "GetSpecialization", "GetSpecializationInfo", "GetSpecializationInfoByID", "GetInspectSpecialization",
  -- UI, chat, sound
  "CreateFrame", "DEFAULT_CHAT_FRAME", "Minimap", "GetMinimapShape", "GetCursorPosition", "GameTooltip", "MenuUtil", "GetChatWindowInfo", "NUM_CHAT_WINDOWS", "Constants","RaidNotice_AddMessage", "RaidWarningFrame", "ChatTypeInfo",
  "PlaySound", "SOUNDKIT", "SendChatMessage", "LE_PARTY_CATEGORY_INSTANCE",
  -- misc
  "GetTime", "GetLocale", "issecretvalue", "wipe", "date", "time", "geterrorhandler",
  -- global strings and constants
  "LOOT_ROLL_NEED", "LOOT_ROLL_ROLLED_NEED", "LOOT_ROLL_ROLLED_NEED_ROLE_BONUS",
  "ITEM_SPELL_TRIGGER_ONEQUIP", "ITEM_SPELL_TRIGGER_ONUSE", "ITEM_SPELL_TRIGGER_ONPROC",
  "LOCALIZED_CLASS_NAMES_MALE", "INVSLOT_RANGED",
  -- options panel (Config.lua): Settings API
  "Settings", "MinimalSliderWithSteppersMixin",
  -- optional Pawn API
  "PawnGetItemData", "PawnGetSingleValueFromItem", "PawnGetAllScalesEx", "PawnIsInitialized",
}

-- The test stub defines fake WoW globals and the runner reassigns some of
-- them per test; global-variable warnings (1xx) are expected there.
files["tests/"] = {
  std = "lua51",
  ignore = { "1.." },
}
