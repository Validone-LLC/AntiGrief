-- AntiGrief: static data (class proficiencies, stat profiles, slot maps)
-- Follows original level-60 rules. If WoW Forever changes a class's
-- proficiencies, edit the tables here; nothing else needs to change.
-- API facts and sources: docs/api-verification.md

local _, ns = ...
local D = {}
ns.Data = D

---------------------------------------------------------------------------
-- API wrappers (Forever runs the Mainline API; the C_ versions exist there,
-- the legacy globals are only fallbacks)
---------------------------------------------------------------------------
D.GetItemInfo        = (C_Item and C_Item.GetItemInfo) or GetItemInfo
D.GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
D.GetItemStats       = (C_Item and C_Item.GetItemStats) or GetItemStats

-- Specs: the global GetSpecialization/GetSpecializationInfo/
-- GetInspectSpecialization only exist via Blizzard_DeprecatedSpecialization,
-- whose TOC is "AllowLoadGameType: classic, standard", so it does not load on
-- Forever (game type "camelot"). Use C_SpecializationInfo first.
local SI = C_SpecializationInfo
local SpecIndexFn   = (SI and SI.GetSpecialization) or GetSpecialization
local SpecInfoFn    = (SI and SI.GetSpecializationInfo) or GetSpecializationInfo
local InspectSpecFn = (SI and SI.GetInspectSpecialization) or GetInspectSpecialization

local function Secret(v)
  return issecretvalue and issecretvalue(v)
end

-- Own spec ID, or nil when unknown (0, nil, secret or API missing)
function D.PlayerSpecID()
  if not (SpecIndexFn and SpecInfoFn) then return nil end
  local ok, index = pcall(SpecIndexFn)
  if not ok or Secret(index) or type(index) ~= "number" or index <= 0 then return nil end
  local ok2, id = pcall(SpecInfoFn, index)
  if not ok2 or Secret(id) or type(id) ~= "number" or id <= 0 then return nil end
  return id
end

-- Inspected unit's spec ID (valid after INSPECT_READY), or nil when unknown
function D.InspectSpecID(unit)
  if not InspectSpecFn or not unit then return nil end
  local ok, id = pcall(InspectSpecFn, unit)
  if not ok or Secret(id) or type(id) ~= "number" or id <= 0 then return nil end
  return id
end

-- On-screen banner. RaidNotice_AddMessage is a deprecation fallback
-- (Blizzard_DeprecatedRaidWarning, loaded only while the CVar
-- loadDeprecationFallbacks is 1); RaidWarningUtil.AddMessage is current.
function D.ShowBanner(text, colorInfo)
  if RaidWarningUtil and RaidWarningUtil.AddMessage then
    return pcall(RaidWarningUtil.AddMessage, text, colorInfo)
  elseif RaidNotice_AddMessage and RaidWarningFrame then
    return pcall(RaidNotice_AddMessage, RaidWarningFrame, text, colorInfo)
  end
  return false
end

---------------------------------------------------------------------------
-- Item classes and subclasses (values verified against Enum.* in
-- ItemConstantsDocumentation.lua, forever branch; numbers are fallbacks)
---------------------------------------------------------------------------
local E = Enum or {}
local IC = E.ItemClass or {}
local AS = E.ItemArmorSubclass or {}
local WS = E.ItemWeaponSubclass or {}

D.CLASS_WEAPON = IC.Weapon or 2
D.CLASS_ARMOR  = IC.Armor or 4

-- Severity levels
D.LOW, D.MEDIUM, D.HIGH = 1, 2, 3
D.SEV_NAME  = { [1] = "Low", [2] = "Medium", [3] = "High" }
D.SEV_COLOR = { [1] = "ffd0d070", [2] = "ffff9930", [3] = "ffff4040" }

-- Armor subclasses
local CLOTH, LEATHER, MAIL, PLATE = AS.Cloth or 1, AS.Leather or 2, AS.Mail or 3, AS.Plate or 4
local SHIELD, LIBRAM, IDOL, TOTEM = AS.Shield or 6, AS.Libram or 7, AS.Idol or 8, AS.Totem or 9

D.ARMOR_CHECKED = {
  [CLOTH] = true, [LEATHER] = true, [MAIL] = true, [PLATE] = true,
  [SHIELD] = true, [LIBRAM] = true, [IDOL] = true, [TOTEM] = true,
}
D.ARMOR_TIER = { [CLOTH] = 1, [LEATHER] = 2, [MAIL] = 3, [PLATE] = 4 }

D.ARMOR = {
  WARRIOR = { [CLOTH]=true, [LEATHER]=true, [MAIL]=true, [PLATE]=true, [SHIELD]=true },
  PALADIN = { [CLOTH]=true, [LEATHER]=true, [MAIL]=true, [PLATE]=true, [SHIELD]=true, [LIBRAM]=true },
  HUNTER  = { [CLOTH]=true, [LEATHER]=true, [MAIL]=true },
  SHAMAN  = { [CLOTH]=true, [LEATHER]=true, [MAIL]=true, [SHIELD]=true, [TOTEM]=true },
  ROGUE   = { [CLOTH]=true, [LEATHER]=true },
  DRUID   = { [CLOTH]=true, [LEATHER]=true, [IDOL]=true },
  PRIEST  = { [CLOTH]=true },
  MAGE    = { [CLOTH]=true },
  WARLOCK = { [CLOTH]=true },
}

-- Armor a class only learns at a given level
D.ARMOR_LEVEL = {
  WARRIOR = { [PLATE] = 40 }, PALADIN = { [PLATE] = 40 },
  HUNTER  = { [MAIL]  = 40 }, SHAMAN  = { [MAIL]  = 40 },
}

D.BEST_ARMOR = {
  WARRIOR = PLATE, PALADIN = PLATE, HUNTER = MAIL, SHAMAN = MAIL,
  ROGUE = LEATHER, DRUID = LEATHER, PRIEST = CLOTH, MAGE = CLOTH, WARLOCK = CLOTH,
}

-- Weapon subclasses
local AXE1, AXE2, BOW, GUN = WS.Axe1H or 0, WS.Axe2H or 1, WS.Bows or 2, WS.Guns or 3
local MACE1, MACE2, POLEARM = WS.Mace1H or 4, WS.Mace2H or 5, WS.Polearm or 6
local SWORD1, SWORD2, STAFF = WS.Sword1H or 7, WS.Sword2H or 8, WS.Staff or 10
local FIST, DAGGER, THROWN = WS.Unarmed or 13, WS.Dagger or 15, WS.Thrown or 16
local CROSSBOW, WAND = WS.Crossbow or 18, WS.Wand or 19

D.WEAPON_IGNORED = { [WS.Generic or 14] = true, [WS.Fishingpole or 20] = true } -- generic/misc, fishing poles

-- Every weapon type a class can EVER use on Forever 1.60.1, including skills
-- bought later from weapon masters (other players' trained skills can't be
-- seen, so anything learnable counts as usable). Polearms train at level 20
-- (1g); everything else from level 1. Not level-gated here on purpose.
-- Sources and status: docs/api-verification.md, "Weapon proficiencies (Forever)".
D.WEAPON = {
  WARRIOR = { [AXE1]=true, [AXE2]=true, [MACE1]=true, [MACE2]=true, [SWORD1]=true, [SWORD2]=true,
              [POLEARM]=true, [STAFF]=true, [DAGGER]=true, [FIST]=true,
              [BOW]=true, [GUN]=true, [CROSSBOW]=true, [THROWN]=true },
  PALADIN = { [AXE1]=true, [AXE2]=true, [MACE1]=true, [MACE2]=true, [SWORD1]=true, [SWORD2]=true,
              [POLEARM]=true },
  HUNTER  = { [AXE1]=true, [AXE2]=true, [SWORD1]=true, [SWORD2]=true, [POLEARM]=true, [STAFF]=true,
              [DAGGER]=true, [FIST]=true, [BOW]=true, [GUN]=true, [CROSSBOW]=true, [THROWN]=true },
  -- Forever: rogues can learn one-handed axes (Blizzard class deep dive).
  -- Two-handed axes are still not available.
  ROGUE   = { [DAGGER]=true, [FIST]=true, [MACE1]=true, [SWORD1]=true, [AXE1]=true,
              [BOW]=true, [GUN]=true, [CROSSBOW]=true, [THROWN]=true },
  -- Forever: 2H axes/maces are baseline (no longer an Enhancement talent).
  SHAMAN  = { [AXE1]=true, [AXE2]=true, [MACE1]=true, [MACE2]=true, [STAFF]=true,
              [DAGGER]=true, [FIST]=true },
  -- Forever: polearms (level 20) per several guides and client skill data
  -- reports; no Blizzard statement found. Allowed to avoid false alarms.
  DRUID   = { [MACE1]=true, [MACE2]=true, [STAFF]=true, [DAGGER]=true, [FIST]=true,
              [POLEARM]=true },
  PRIEST  = { [DAGGER]=true, [MACE1]=true, [STAFF]=true, [WAND]=true },
  MAGE    = { [DAGGER]=true, [SWORD1]=true, [STAFF]=true, [WAND]=true },
  WARLOCK = { [DAGGER]=true, [SWORD1]=true, [STAFF]=true, [WAND]=true },
}

-- Stat buckets, matched as plain substrings of GetItemStats keys
-- (e.g. ITEM_MOD_INTELLECT_SHORT).
-- Changed from the spec: the spec's single key "SPELL" also matched
-- ITEM_MOD_SPELL_RESISTANCE_ALL_SCHOOLS_SHORT ("Spell Resistance"),
-- ITEM_MOD_CRIT_TAKEN_SPELL_RATING_SHORT and ITEM_MOD_HIT_TAKEN_SPELL_RATING_SHORT
-- (defensive stats), so a resist-only item would flag High as "caster" on a
-- warrior. It is replaced by the specific spell keys it was meant to catch
-- (all present in the 1.60.1 GlobalStrings), plus the per-school spell
-- damage/penetration keys, which "SPELL" never matched.
D.STAT_BUCKETS = {
  { key = "STRENGTH",          bucket = "STR" },
  { key = "AGILITY",           bucket = "AGI" },
  { key = "INTELLECT",         bucket = "INT" },
  { key = "SPELL_POWER",       bucket = "CASTER" },
  { key = "SPELL_DAMAGE",      bucket = "CASTER" }, -- _DONE and _VS_<type>
  { key = "SPELL_HEALING",     bucket = "CASTER" },
  { key = "SPELL_PENETRATION", bucket = "CASTER" },
  { key = "CRIT_SPELL_RATING", bucket = "CASTER" },
  { key = "HIT_SPELL_RATING",  bucket = "CASTER" },
  { key = "ARCANE_DAMAGE",     bucket = "CASTER" },
  { key = "FIRE_DAMAGE",       bucket = "CASTER" },
  { key = "FROST_DAMAGE",      bucket = "CASTER" },
  { key = "HOLY_DAMAGE",       bucket = "CASTER" },
  { key = "NATURE_DAMAGE",     bucket = "CASTER" },
  { key = "SHADOW_DAMAGE",     bucket = "CASTER" },
  { key = "HEALING",           bucket = "CASTER" },
  { key = "MANA_REGEN",        bucket = "CASTER" },
  { key = "POWER_REGEN0",      bucket = "CASTER" },
  { key = "ATTACK_POWER",      bucket = "AP" },
  { key = "DEFENSE",           bucket = "TANK" },
  { key = "DODGE",             bucket = "TANK" },
  { key = "PARRY",             bucket = "TANK" },
  { key = "BLOCK",             bucket = "TANK" },
}
D.BUCKET_LABEL = { STR = "Strength", AGI = "Agility", INT = "Intellect", CASTER = "spell power/healing", AP = "attack power", TANK = "defense/avoidance" }

-- Equip:/Use:/Chance on hit: lines -> bucket, by keyword (lowercase Lua patterns).
-- Order matters: caster phrases first, so "critical strike with spells" is Caster.
-- English only; other locales skip the effect check.
D.EFFECT_KEYWORDS_ACTIVE = GetLocale and GetLocale():sub(1, 2) == "en"
D.EFFECT_KEYWORDS = {
  { pattern = "healing done by spells",    bucket = "CASTER" },
  { pattern = "magical spells",            bucket = "CASTER" },
  { pattern = "damage done by %a+ spells", bucket = "CASTER" },
  { pattern = "spells and effects",        bucket = "CASTER" },
  { pattern = "spell power",               bucket = "CASTER" },
  { pattern = "with spells",               bucket = "CASTER" },
  { pattern = "mana per 5",                bucket = "CASTER" },
  { pattern = "magical resistances",       bucket = "CASTER" },
  { pattern = "attack power",              bucket = "AP" },
  { pattern = "critical strike",           bucket = "AP" },
  { pattern = "chance to hit",             bucket = "AP" },
  { pattern = "defense",                   bucket = "TANK" },
  { pattern = "dodge",                     bucket = "TANK" },
  { pattern = "parry",                     bucket = "TANK" },
  { pattern = "block",                     bucket = "TANK" },
}

D.STATS = {
  WARRIOR = { STR=true, AGI=true, AP=true, TANK=true },
  ROGUE   = { AGI=true, STR=true, AP=true },
  HUNTER  = { AGI=true, AP=true, INT=true },
  PALADIN = { STR=true, AGI=true, INT=true, CASTER=true, AP=true, TANK=true },
  SHAMAN  = { STR=true, AGI=true, INT=true, CASTER=true, AP=true, TANK=true },
  DRUID   = { STR=true, AGI=true, INT=true, CASTER=true, AP=true, TANK=true },
  PRIEST  = { INT=true, CASTER=true },
  MAGE    = { INT=true, CASTER=true },
  WARLOCK = { INT=true, CASTER=true },
}

-- Equip location -> slot(s) compared by the upgrade check.
-- Slot 18 exists on Forever: INVSLOT_RANGED = 18 in Blizzard_FrameXMLBase/
-- Constants.lua, the Camelot inspect frame has InspectRangedSlot, and Pawn
-- sets RangedSlotExists for Forever.
local RANGED_SLOT = INVSLOT_RANGED or 18
D.SLOTS_FOR = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
  INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
  INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
  INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
  INVTYPE_CLOAK = { 15 },
  INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
  INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
  INVTYPE_RANGED = { RANGED_SLOT }, INVTYPE_RANGEDRIGHT = { RANGED_SLOT },
  INVTYPE_THROWN = { RANGED_SLOT }, INVTYPE_RELIC = { RANGED_SLOT },
}
D.IGNORE_LOC = { INVTYPE_BODY = true, INVTYPE_TABARD = true, INVTYPE_NON_EQUIP_IGNORE = true }
D.INSPECT_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, RANGED_SLOT }

-- Useful buckets by current spec, for hybrids. Keys are modern WoW
-- specialization IDs; confirm Forever's in game (/ag gear prints them).
-- Unverified: Pawn 2.14.1 treats Forever as having no specs
-- (VgerCore.SpecsExist is false for build 16001), so the spec APIs may return
-- 0 there; everything then falls back to D.STATS.
local CASTER_SET = { INT=true, CASTER=true }
local MELEE_SET  = { STR=true, AGI=true, AP=true }
local BEAR_SET   = { STR=true, AGI=true, AP=true, TANK=true }
D.SPEC_STATS = {
  [65]  = CASTER_SET,                                   -- Paladin: Holy
  [66]  = { STR=true, AGI=true, AP=true, CASTER=true, TANK=true }, -- Paladin: Protection
  [70]  = MELEE_SET,                                    -- Paladin: Retribution
  [262] = CASTER_SET,                                   -- Shaman: Elemental
  [263] = MELEE_SET,                                    -- Shaman: Enhancement
  [264] = CASTER_SET,                                   -- Shaman: Restoration
  [102] = CASTER_SET,                                   -- Druid: Balance
  [103] = BEAR_SET,                                     -- Druid: Feral
  [104] = BEAR_SET,                                     -- Druid: Guardian
  [105] = CASTER_SET,                                   -- Druid: Restoration
}

-- Current spec's buckets when known; otherwise the class-wide set
function D.StatsFor(class, specID)
  if type(specID) == "number" and D.SPEC_STATS[specID] then return D.SPEC_STATS[specID] end
  if type(specID) == "number" and specID > 0 and GetSpecializationInfoByID then
    -- returns id, name, description, icon, role, classFile, className
    local ok, _, _, _, _, role = pcall(GetSpecializationInfoByID, specID)
    if ok and role == "HEALER" then return CASTER_SET end
  end
  return D.STATS[class]
end

function D.ClassName(token)
  return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or token or "?"
end
