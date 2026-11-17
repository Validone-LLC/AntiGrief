-- AntiGrief offline tests. Run from the repo root: lua tests/run.lua
-- Each test gets a fresh stub and a fresh load of the addon files in TOC
-- order, sharing one namespace table, as the client does.

local root = "."
do
  local script = arg and arg[0]
  local dir = script and script:match("^(.*)[/\\]tests[/\\][^/\\]+$")
  if dir and dir ~= "" then root = dir end
end
local function path(p) return root .. "/" .. p end

local ADDON = "AntiGrief"
-- Same order as AntiGrief.toc
local TOC = { "Data.lua", "Inspect.lua", "Rules.lua", "Pawn.lua", "Config.lua", "Minimap.lua", "AntiGrief.lua" }
-- Config.lua (the options panel) is written separately; while it isn't in
-- the repo the suite runs without it.
local OPTIONAL = { ["Config.lua"] = true }

local function exists(p)
  local fh = io.open(p, "r")
  if fh then fh:close() return true end
  return false
end
local HAS_CONFIG = exists(path("Config.lua"))
if not HAS_CONFIG then print("NOTE  Config.lua not found: loading the addon without it\n") end

local S, ns

-- Load the addon files in TOC order into a fresh namespace
local function loadAddon()
  ns = {}
  for _, f in ipairs(TOC) do
    if not (OPTIONAL[f] and not exists(path(f))) then
      local chunk, err = loadfile(path(f))
      if not chunk then error("load " .. f .. ": " .. tostring(err), 0) end
      chunk(ADDON, ns)
    end
  end
end

-- setup(S), if given, runs after the stub loads and before the addon files
-- (for load-time state such as the client locale)
local function fresh(setup)
  S = assert(loadfile(path("tests/wowstub.lua")))()
  if setup then setup(S) end
  loadAddon()
  S.fire("ADDON_LOADED", ADDON)
end

---------------------------------------------------------------------------
-- Assertions
---------------------------------------------------------------------------
local function eq(actual, expected, what)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(what or "value", tostring(expected), tostring(actual)), 2)
  end
end

local function ok(v, what)
  if not v then error(what or "assertion failed", 2) end
end

local function dump(findings)
  if not findings then return "nil" end
  local t = {}
  for _, f in ipairs(findings) do t[#t + 1] = ("[%d] %s"):format(f.sev, f.text) end
  return "{" .. table.concat(t, "; ") .. "}"
end

local function has(findings, sev, text)
  for _, f in ipairs(findings or {}) do
    if f.sev == sev and (not text or f.text:find(text, 1, true)) then return true end
  end
  return false
end

local function expectFinding(findings, sev, text)
  if not has(findings, sev, text) then
    error(("expected finding [%d] %q in %s"):format(sev, text or "*", dump(findings)), 2)
  end
end

local function expectNoFinding(findings, sev, text)
  if has(findings, sev, text) then
    error(("unexpected finding [%d] %q in %s"):format(sev, text or "*", dump(findings)), 2)
  end
end

---------------------------------------------------------------------------
-- Fixtures
---------------------------------------------------------------------------
local ARMOR, WEAPON = 4, 2
local CLOTH, LEATHER, PLATE = 1, 2, 4
local SWORD2, DAGGER = 8, 15

local I = {}
local function items()
  I.plateChest = S.AddItem { id = 1001, name = "Breastplate of Might", classID = ARMOR, subclassID = PLATE,
    subType = "Plate", equipLoc = "INVTYPE_CHEST", ilvl = 66, minLevel = 60,
    stats = { ITEM_MOD_STRENGTH_SHORT = 20, ITEM_MOD_STAMINA_SHORT = 28 } }
  I.plateChestBoE = S.AddItem { id = 1011, name = "Bloodforged Chestplate", classID = ARMOR, subclassID = PLATE,
    subType = "Plate", equipLoc = "INVTYPE_CHEST", ilvl = 60, minLevel = 55, bind = 2,
    stats = { ITEM_MOD_STRENGTH_SHORT = 15 } }
  I.spellDagger = S.AddItem { id = 1002, name = "Lightforged Blade", classID = WEAPON, subclassID = DAGGER,
    itemType = "Weapon", subType = "Daggers", equipLoc = "INVTYPE_WEAPON", ilvl = 60, minLevel = 55,
    stats = { ITEM_MOD_INTELLECT_SHORT = 10, ITEM_MOD_SPELL_POWER_SHORT = 30 } }
  I.robe58 = S.AddItem { id = 1003, name = "Robe of the Archmage", classID = ARMOR, subclassID = CLOTH,
    subType = "Cloth", equipLoc = "INVTYPE_ROBE", ilvl = 63, minLevel = 58,
    stats = { ITEM_MOD_INTELLECT_SHORT = 20 } }
  I.staminaSpellGloves = S.AddItem { id = 1004, name = "Shadowweave Grips", classID = ARMOR, subclassID = LEATHER,
    subType = "Leather", equipLoc = "INVTYPE_HAND", ilvl = 58, minLevel = 53,
    stats = { ITEM_MOD_STAMINA_SHORT = 10 },
    effects = { "Equip: Increases damage and healing done by magical spells and effects by up to 12." } }
  I.agiSpellGloves = S.AddItem { id = 1005, name = "Odd Gloves", classID = ARMOR, subclassID = LEATHER,
    subType = "Leather", equipLoc = "INVTYPE_HAND", ilvl = 58, minLevel = 53,
    stats = { ITEM_MOD_AGILITY_SHORT = 12 },
    effects = { "Equip: Increases damage done by Shadow spells and effects by up to 7." } }
  I.clothHelm52 = S.AddItem { id = 1006, name = "Cowl of Lesser Power", classID = ARMOR, subclassID = CLOTH,
    subType = "Cloth", equipLoc = "INVTYPE_HEAD", ilvl = 52, minLevel = 47,
    stats = { ITEM_MOD_INTELLECT_SHORT = 12 } }
  I.clothHelm63 = S.AddItem { id = 1007, name = "Cowl of Greater Power", classID = ARMOR, subclassID = CLOTH,
    subType = "Cloth", equipLoc = "INVTYPE_HEAD", ilvl = 63, minLevel = 58,
    stats = { ITEM_MOD_INTELLECT_SHORT = 20 } }
  I.clothHelm59 = S.AddItem { id = 1008, name = "Cowl of Middling Power", classID = ARMOR, subclassID = CLOTH,
    subType = "Cloth", equipLoc = "INVTYPE_HEAD", ilvl = 59, minLevel = 54,
    stats = { ITEM_MOD_INTELLECT_SHORT = 16 } }
  I.strIntPlate = S.AddItem { id = 1009, name = "Hybrid Pauldrons", classID = ARMOR, subclassID = PLATE,
    subType = "Plate", equipLoc = "INVTYPE_SHOULDER", ilvl = 60, minLevel = 55,
    stats = { ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_INTELLECT_SHORT = 10 } }
  I.ring55 = S.AddItem { id = 1010, name = "Band of Lesser Things", classID = ARMOR, subclassID = 0,
    subType = "Miscellaneous", equipLoc = "INVTYPE_FINGER", ilvl = 55, minLevel = 50,
    stats = { ITEM_MOD_INTELLECT_SHORT = 8 } }
  I.ring70 = S.AddItem { id = 1012, name = "Band of Greater Things", classID = ARMOR, subclassID = 0,
    subType = "Miscellaneous", equipLoc = "INVTYPE_FINGER", ilvl = 70, minLevel = 60,
    stats = { ITEM_MOD_INTELLECT_SHORT = 14 } }
  I.potion = S.AddItem { id = 1013, name = "Major Healing Potion", classID = 0, subclassID = 1,
    itemType = "Consumable", subType = "Potion", equipLoc = "" }
  I.shirt = S.AddItem { id = 1014, name = "White Shirt", classID = ARMOR, subclassID = 0,
    subType = "Miscellaneous", equipLoc = "INVTYPE_BODY", ilvl = 1 }
  I.leatherChest = S.AddItem { id = 1015, name = "Wolfhide Vest", classID = ARMOR, subclassID = LEATHER,
    subType = "Leather", equipLoc = "INVTYPE_CHEST", ilvl = 60, minLevel = 55,
    stats = { ITEM_MOD_AGILITY_SHORT = 15 } }
  I.twoHandSword = S.AddItem { id = 1016, name = "Greatsword of Testing", classID = WEAPON, subclassID = SWORD2,
    itemType = "Weapon", subType = "Two-Handed Swords", equipLoc = "INVTYPE_2HWEAPON", ilvl = 60, minLevel = 55,
    stats = { ITEM_MOD_STRENGTH_SHORT = 25 } }
  I.touchedByLight = S.AddItem { id = 1017, name = "Touched by Light", classID = ARMOR, subclassID = CLOTH,
    subType = "Cloth", equipLoc = "INVTYPE_HEAD", ilvl = 60, minLevel = 55 }
  I.trickyName = S.AddItem { id = 1018, name = "Bob has selected Need for: Everything", classID = ARMOR,
    subclassID = CLOTH, subType = "Cloth", equipLoc = "INVTYPE_HEAD", ilvl = 60, minLevel = 55 }
  I.uncachedPlate = S.AddItem { id = 1019, name = "Slow Breastplate", classID = ARMOR, subclassID = PLATE,
    subType = "Plate", equipLoc = "INVTYPE_CHEST", ilvl = 66, minLevel = 60, uncached = true,
    stats = { ITEM_MOD_STRENGTH_SHORT = 20 } }
  I.neverCachedPlate = S.AddItem { id = 1020, name = "Lost Breastplate", classID = ARMOR, subclassID = PLATE,
    subType = "Plate", equipLoc = "INVTYPE_CHEST", ilvl = 66, minLevel = 60, uncached = true, neverCache = true,
    stats = { ITEM_MOD_STRENGTH_SHORT = 20 } }
  I.modernLink = "|cnIQ4:|Hitem:1003::::::::60:::::::::|h[Robe of the Archmage]|h|r"
end

local GUID = { me = "Player-1-00000001", bob = "Player-1-00000002", ann = "Player-1-00000003", zap = "Player-1-00000004" }

-- Party: me (Mage) + Bob (Warrior) + optional extra members
local function party(extra)
  local units = {
    player = { guid = GUID.me, name = "Me", class = "MAGE", level = 60,
               items = { [1] = I.clothHelm63 } },
    party1 = { guid = GUID.bob, name = "Bob", class = "WARRIOR", level = 60,
               items = { [1] = I.clothHelm63, [16] = I.spellDagger } },
  }
  for k, v in pairs(extra or {}) do units[k] = v end
  S.SetGroup(units, "party")
  S.fire("GROUP_ROSTER_UPDATE")
end

local function evaluate(link, who) return ns.Rules.Evaluate(link, who) end

-- Chat lines in the real 1.60.1 format. The loot-history roll ID is a
-- number, so it must never be taken for the player name.
local ROLL_ID = 4242
local function NEED(name, link) return LOOT_ROLL_NEED:format(ROLL_ID, name, link) end
local function ROLLED(roll, link, name) return LOOT_ROLL_ROLLED_NEED:format(ROLL_ID, roll, link, name) end
local function SELF_NEED(link) return LOOT_ROLL_NEED_SELF:format(ROLL_ID, link) end
local function ROLE_BONUS(roll, link, name) return LOOT_ROLL_ROLLED_NEED_ROLE_BONUS:format(roll, link, name) end

---------------------------------------------------------------------------
-- Tests
---------------------------------------------------------------------------
local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

-- Fit rules (spec cases) -------------------------------------------------

test("plate on a mage -> High", function()
  local f, sev = evaluate(I.plateChest, { name = "Zap", class = "MAGE", level = 60 })
  eq(sev, 3, "maxSev")
  expectFinding(f, 3, "Mage can't use Plate")
end)

test("spell-power dagger on a warrior -> High", function()
  local f, sev = evaluate(I.spellDagger, { name = "Bob", class = "WARRIOR", level = 60 })
  eq(sev, 3, "maxSev")
  expectFinding(f, 3, "(Intellect, spell power/healing) don't suit a Warrior")
  expectNoFinding(f, 3, "can't use")
end)

test("level-58 item on a level-45 -> High", function()
  local f, sev = evaluate(I.robe58, { name = "Zap", class = "MAGE", level = 45 })
  eq(sev, 3, "maxSev")
  expectFinding(f, 3, "requires level 58, they're level 45")
end)

test("Stamina + spell-damage Equip line on a rogue -> High (no duplicate Low)", function()
  local f, sev = evaluate(I.staminaSpellGloves, { name = "Sly", class = "ROGUE", level = 60 })
  eq(sev, 3, "maxSev")
  expectFinding(f, 3, "(spell power/healing) don't suit a Rogue")
  expectNoFinding(f, 1, "Equip/Use effect")
end)

test("Agility + spell-damage Equip line on a rogue -> Low note only", function()
  local f, sev = evaluate(I.agiSpellGloves, { name = "Sly", class = "ROGUE", level = 60 })
  eq(sev, 1, "maxSev")
  expectFinding(f, 1, "has an Equip/Use effect (spell power/healing) a Rogue can't use")
end)

test("item 11 ilvl below equipped -> Medium", function()
  local f, sev = evaluate(I.clothHelm52, { name = "Zap", class = "MAGE", level = 60, items = { [1] = I.clothHelm63 } })
  eq(sev, 2, "maxSev")
  expectFinding(f, 2, "not an upgrade: item level 52 vs their")
  expectFinding(f, 2, "(item level 63)")
end)

test("item 7 ilvl below equipped -> fits (margin 8)", function()
  local f, sev = evaluate(I.clothHelm52, { name = "Zap", class = "MAGE", level = 60, items = { [1] = I.clothHelm59 } })
  eq(sev, 0, "maxSev " .. dump(f))
end)

test("upgrade margin setting is honoured", function()
  ns.db.upgradeMargin = 5
  local _, sev = evaluate(I.clothHelm52, { name = "Zap", class = "MAGE", level = 60, items = { [1] = I.clothHelm59 } })
  eq(sev, 2, "maxSev")
end)

test("empty slot counts as an upgrade; not scanned skips the check", function()
  local _, sev = evaluate(I.clothHelm52, { name = "Zap", class = "MAGE", level = 60, items = {} })
  eq(sev, 0, "empty slot")
  local _, sev2 = evaluate(I.clothHelm52, { name = "Zap", class = "MAGE", level = 60 })
  eq(sev2, 0, "not scanned")
end)

test("rings: lowest of both slots, empty ring slot = upgrade", function()
  local who = { name = "Zap", class = "MAGE", level = 60, items = { [11] = I.ring70 } }
  local _, sev = evaluate(I.ring55, who)
  eq(sev, 0, "one ring slot empty")
  who.items[12] = I.ring70
  local f, sev2 = evaluate(I.ring55, who)
  eq(sev2, 2, "both slots higher")
  expectFinding(f, 2, "item level 55")
end)

test("BoE note appended to Medium/High findings only", function()
  local f, sev = evaluate(I.plateChestBoE, { name = "Zap", class = "MAGE", level = 60 })
  eq(sev, 3, "maxSev")
  expectFinding(f, 1, "Bind on Equip, so it could be resold")
  local f2, sev2 = evaluate(I.plateChestBoE, { name = "Bob", class = "WARRIOR", level = 60 })
  eq(sev2, 0, "fits warrior")
  expectNoFinding(f2, 1, "Bind on Equip")
end)

test("mixed Str/Int plate does not flag a warrior", function()
  local f, sev = evaluate(I.strIntPlate, { name = "Bob", class = "WARRIOR", level = 60 })
  eq(sev, 0, "maxSev " .. dump(f))
  eq(#f, 0, "finding count")
end)

test("plate gated until 40 for a level-30 warrior", function()
  local f, sev = evaluate(I.plateChest, { name = "Bob", class = "WARRIOR", level = 30 })
  eq(sev, 3, "maxSev")
  expectFinding(f, 3, "can't wear Plate until level 40")
end)

test("leather on a level-60 warrior -> Low lower-armor note", function()
  local f, sev = evaluate(I.leatherChest, { name = "Bob", class = "WARRIOR", level = 60 })
  eq(sev, 1, "maxSev " .. dump(f))
  expectFinding(f, 1, "Leather is a lower armor type than a Warrior normally wears")
end)

test("priest can't use two-handed swords", function()
  local f, sev = evaluate(I.twoHandSword, { name = "Pri", class = "PRIEST", level = 60 })
  eq(sev, 3, "maxSev")
  expectFinding(f, 3, "Priest can't use Two-Handed Swords")
end)

test("Forever weapons: rogue 1H axe and druid polearm allowed; rogue 2H axe and paladin dagger flagged", function()
  local function weapon(id, name, subclassID, subType, equipLoc)
    return S.AddItem { id = id, name = name, classID = WEAPON, subclassID = subclassID, itemType = "Weapon",
      subType = subType, equipLoc = equipLoc, ilvl = 60, minLevel = 55, stats = { ITEM_MOD_STAMINA_SHORT = 10 } }
  end
  local axe1 = weapon(1101, "Test Hatchet", 0, "One-Handed Axes", "INVTYPE_WEAPON")
  local axe2 = weapon(1102, "Test Greataxe", 1, "Two-Handed Axes", "INVTYPE_2HWEAPON")
  local polearm = weapon(1103, "Test Halberd", 6, "Polearms", "INVTYPE_2HWEAPON")
  local dagger = weapon(1104, "Test Shiv", DAGGER, "Daggers", "INVTYPE_WEAPON")
  local rogue = { name = "Rog", class = "ROGUE", level = 60 }
  local druid = { name = "Dru", class = "DRUID", level = 60 }
  local paladin = { name = "Pal", class = "PALADIN", level = 60 }

  local f = evaluate(axe1, rogue)
  expectNoFinding(f, 3, "can't use")
  f = evaluate(polearm, druid)
  expectNoFinding(f, 3, "can't use")
  f = evaluate(axe2, rogue)
  expectFinding(f, 3, "Rogue can't use Two-Handed Axes")
  f = evaluate(dagger, paladin)
  expectFinding(f, 3, "Paladin can't use Daggers")
end)

test("hybrid spec: Holy paladin flags Strength plate, Retribution and unknown don't", function()
  local link = I.plateChest
  local _, holy = evaluate(link, { name = "Pal", class = "PALADIN", level = 60, spec = 65 })
  eq(holy, 3, "holy")
  local _, ret = evaluate(link, { name = "Pal", class = "PALADIN", level = 60, spec = 70 })
  eq(ret, 0, "ret")
  local _, unknown = evaluate(link, { name = "Pal", class = "PALADIN", level = 60 })
  eq(unknown, 0, "unknown spec")
end)

test("non-gear and ignored slots are not judged", function()
  eq(evaluate(I.potion, { name = "Bob", class = "WARRIOR", level = 60 }), nil, "potion")
  eq(evaluate(I.shirt, { name = "Bob", class = "WARRIOR", level = 60 }), nil, "shirt")
  eq(evaluate(I.plateChest, { name = "Bob" }), nil, "no class")
end)

-- Fit rules: effect lines, skips, gates, roles, resists ----------------------

local function ring(id, name, effects, stats)
  return S.AddItem { id = id, name = name, classID = ARMOR, subclassID = 0, subType = "Miscellaneous",
    equipLoc = "INVTYPE_FINGER", ilvl = 60, minLevel = 55, stats = stats, effects = effects }
end

test("effects: 'critical strike with spells' counts as Caster, not attack power", function()
  local spellCrit = ring(3001, "Ring of Spell Crit",
    { "Equip: Improves your chance to get a critical strike with spells by 1%." })
  local f, sev = evaluate(spellCrit, { name = "Bob", class = "WARRIOR", level = 60 })
  eq(sev, 3, "spell-crit ring on a warrior")
  expectFinding(f, 3, "(spell power/healing) don't suit a Warrior")
  local meleeCrit = ring(3002, "Ring of Melee Crit",
    { "Equip: Improves your chance to get a critical strike by 1%." })
  local f2, sev2 = evaluate(meleeCrit, { name = "Zap", class = "MAGE", level = 60 })
  eq(sev2, 3, "melee-crit ring on a mage")
  expectFinding(f2, 3, "(attack power) don't suit a Mage")
  local _, sev3 = evaluate(meleeCrit, { name = "Bob", class = "WARRIOR", level = 60 })
  eq(sev3, 0, "melee-crit ring fits a warrior")
end)

test("effects: Use: and Chance on hit: lines count; other lines don't", function()
  local useTrinket = S.AddItem { id = 3003, name = "Badge of Fury", classID = ARMOR, subclassID = 0,
    subType = "Miscellaneous", equipLoc = "INVTYPE_TRINKET", ilvl = 60, minLevel = 55,
    effects = { "Use: Increases attack power by 200 for 20 sec." } }
  local f, sev = evaluate(useTrinket, { name = "Pri", class = "PRIEST", level = 60 })
  eq(sev, 3, "Use: attack power trinket on a priest")
  expectFinding(f, 3, "(attack power) don't suit a Priest")
  local procDagger = S.AddItem { id = 3004, name = "Frenzy Shiv", classID = WEAPON, subclassID = DAGGER,
    itemType = "Weapon", subType = "Daggers", equipLoc = "INVTYPE_WEAPON", ilvl = 60, minLevel = 55,
    effects = { "Chance on hit: Increases your attack power by 50 for 10 sec." } }
  local _, sev2 = evaluate(procDagger, { name = "Zap", class = "MAGE", level = 60 })
  eq(sev2, 3, "Chance on hit: attack power dagger on a mage")
  local setTrinket = S.AddItem { id = 3005, name = "Badge of Nothing", classID = ARMOR, subclassID = 0,
    subType = "Miscellaneous", equipLoc = "INVTYPE_TRINKET", ilvl = 60, minLevel = 55,
    effects = { "(2) Set: Increases attack power by 20." } }
  local _, sev3 = evaluate(setTrinket, { name = "Pri", class = "PRIEST", level = 60 })
  eq(sev3, 0, "a non-trigger line is ignored")
end)

test("effects: English-only; a deDE client skips the effect check", function()
  fresh(function(s) s.locale = "deDE" end)
  items()
  eq(ns.Data.EFFECT_KEYWORDS_ACTIVE, false, "keywords off on deDE")
  local f, sev = evaluate(I.staminaSpellGloves, { name = "Sly", class = "ROGUE", level = 60 })
  eq(sev, 0, "Stamina + spell Equip line on a rogue passes on deDE " .. dump(f))
  local _, sev2 = evaluate(I.spellDagger, { name = "Bob", class = "WARRIOR", level = 60 })
  eq(sev2, 3, "plain stat check still runs on deDE")
end)

test("skips: cloak armor type is not judged; its stats still are", function()
  local agiCloak = S.AddItem { id = 3006, name = "Cloak of Agility", classID = ARMOR, subclassID = CLOTH,
    subType = "Cloth", equipLoc = "INVTYPE_CLOAK", ilvl = 60, minLevel = 55, stats = { ITEM_MOD_AGILITY_SHORT = 10 } }
  local f, sev = evaluate(agiCloak, { name = "Bob", class = "WARRIOR", level = 60 })
  eq(sev, 0, "cloth cloak on a warrior " .. dump(f))
  local intCloak = S.AddItem { id = 3007, name = "Cloak of Intellect", classID = ARMOR, subclassID = CLOTH,
    subType = "Cloth", equipLoc = "INVTYPE_CLOAK", ilvl = 60, minLevel = 55, stats = { ITEM_MOD_INTELLECT_SHORT = 10 } }
  local _, sev2 = evaluate(intCloak, { name = "Bob", class = "WARRIOR", level = 60 })
  eq(sev2, 3, "Int cloak on a warrior: stat check still runs")
end)

test("skips: fishing poles and misc weapons are not type-checked", function()
  local pole = S.AddItem { id = 3008, name = "Big Iron Fishing Pole", classID = WEAPON, subclassID = 20,
    itemType = "Weapon", subType = "Fishing Poles", equipLoc = "INVTYPE_2HWEAPON", ilvl = 30, minLevel = 20 }
  local misc = S.AddItem { id = 3009, name = "Skinning Knife", classID = WEAPON, subclassID = 14,
    itemType = "Weapon", subType = "Miscellaneous", equipLoc = "INVTYPE_WEAPON", ilvl = 10, minLevel = 5 }
  local f, sev = evaluate(pole, { name = "Zap", class = "MAGE", level = 60 })
  eq(sev, 0, "fishing pole on a mage " .. dump(f))
  local f2, sev2 = evaluate(misc, { name = "Zap", class = "MAGE", level = 60 })
  eq(sev2, 0, "misc weapon on a mage " .. dump(f2))
end)

test("gates: mail at 40 for hunters and shamans; lower-armor note follows the gate", function()
  local mail = S.AddItem { id = 3010, name = "Chain Hauberk", classID = ARMOR, subclassID = 3, subType = "Mail",
    equipLoc = "INVTYPE_CHEST", ilvl = 30, minLevel = 25, stats = { ITEM_MOD_AGILITY_SHORT = 5 } }
  local hunterF, hunter30 = evaluate(mail, { name = "Hun", class = "HUNTER", level = 30 })
  eq(hunter30, 3, "mail on a level-30 hunter")
  expectFinding(hunterF, 3, "Hunter can't wear Mail until level 40")
  local shamanF, shaman30 = evaluate(mail, { name = "Sha", class = "SHAMAN", level = 30 })
  eq(shaman30, 3, "mail on a level-30 shaman")
  expectFinding(shamanF, 3, "Shaman can't wear Mail until level 40")
  local _, hunter40 = evaluate(mail, { name = "Hun", class = "HUNTER", level = 40 })
  eq(hunter40, 0, "mail on a level-40 hunter")
  local leather = S.AddItem { id = 3011, name = "Hide Vest", classID = ARMOR, subclassID = LEATHER, subType = "Leather",
    equipLoc = "INVTYPE_CHEST", ilvl = 30, minLevel = 25, stats = { ITEM_MOD_AGILITY_SHORT = 5 } }
  local _, leather30 = evaluate(leather, { name = "Hun", class = "HUNTER", level = 30 })
  eq(leather30, 0, "leather is best-available for a level-30 hunter")
  local _, leather60 = evaluate(leather, { name = "Hun", class = "HUNTER", level = 60 })
  eq(leather60, 1, "leather is a lower type for a level-60 hunter")
  local cloth = S.AddItem { id = 3012, name = "Linen Vest", classID = ARMOR, subclassID = CLOTH, subType = "Cloth",
    equipLoc = "INVTYPE_CHEST", ilvl = 30, minLevel = 25, stats = { ITEM_MOD_AGILITY_SHORT = 5 } }
  local clothF, cloth30 = evaluate(cloth, { name = "Hun", class = "HUNTER", level = 30 })
  eq(cloth30, 1, "cloth on a level-30 hunter")
  expectFinding(clothF, 1, "Cloth is a lower armor type than a Hunter normally wears")
end)

test("roles: an unmapped Healer spec is treated as a caster", function()
  local roles = { [999] = "HEALER", [998] = "DAMAGER" }
  GetSpecializationInfoByID = function(id) return id, "Spec", "", 0, roles[id], "PALADIN", "Paladin" end
  local f, sev = evaluate(I.plateChest, { name = "Pal", class = "PALADIN", level = 60, spec = 999 })
  eq(sev, 3, "Strength plate on an unmapped healer spec")
  expectFinding(f, 3, "(Strength) don't suit a Paladin")
  local _, sev2 = evaluate(I.plateChest, { name = "Pal", class = "PALADIN", level = 60, spec = 998 })
  eq(sev2, 0, "unmapped damage spec falls back to the class-wide set")
end)

test("stats: a resist-only item isn't Caster (deviation D-2)", function()
  local resistPlate = S.AddItem { id = 3013, name = "Warded Breastplate", classID = ARMOR, subclassID = PLATE,
    subType = "Plate", equipLoc = "INVTYPE_CHEST", ilvl = 60, minLevel = 55,
    stats = { ITEM_MOD_SPELL_RESISTANCE_ALL_SCHOOLS_SHORT = 10, ITEM_MOD_CRIT_TAKEN_SPELL_RATING_SHORT = 5,
              ITEM_MOD_STAMINA_SHORT = 12 } }
  local f, sev = evaluate(resistPlate, { name = "Bob", class = "WARRIOR", level = 60 })
  eq(sev, 0, "resist-only plate on a warrior " .. dump(f))
end)

test("BoE note is added to a Medium-only finding", function()
  local boeHelm = S.AddItem { id = 3014, name = "Cowl of Resale", classID = ARMOR, subclassID = CLOTH,
    subType = "Cloth", equipLoc = "INVTYPE_HEAD", ilvl = 50, minLevel = 45, bind = 2,
    stats = { ITEM_MOD_INTELLECT_SHORT = 10 } }
  local f, sev = evaluate(boeHelm, { name = "Zap", class = "MAGE", level = 60, items = { [1] = I.clothHelm63 } })
  eq(sev, 2, "Medium only")
  expectFinding(f, 2, "not an upgrade: item level 50")
  expectFinding(f, 1, "Bind on Equip, so it could be resold")
  eq(#f, 2, "exactly the Medium finding and the BoE note")
end)

-- Pattern building ---------------------------------------------------------

local REAL_NEED_PAT    = "^|HlootHistory:(%d+)|h%[Loot%]|h: (.+) has selected Need for: (.+)$"
local REAL_ROLLED_PAT  = "^|HlootHistory:(%d+)|h%[Loot%]|h: Need Roll %- (%d+) for (.+) by (.+)$"
local ROLE_BONUS_PAT   = "^Need Roll %- (%d+) for (.+) by (.+) %+ Role Bonus$"

test("BuildPattern: real 1.60.1 LOOT_ROLL_NEED", function()
  eq(ns._test.BuildPattern(LOOT_ROLL_NEED), REAL_NEED_PAT, "pattern")
end)

test("BuildPattern: real 1.60.1 LOOT_ROLL_ROLLED_NEED and ROLE_BONUS", function()
  eq(ns._test.BuildPattern(LOOT_ROLL_ROLLED_NEED), REAL_ROLLED_PAT, "rolled")
  eq(ns._test.BuildPattern(LOOT_ROLL_ROLLED_NEED_ROLE_BONUS), ROLE_BONUS_PAT, "role bonus")
end)

test("BuildPattern: spec's older English strings", function()
  eq(ns._test.BuildPattern(S.OLD_LOOT.LOOT_ROLL_NEED), "^(.+) has selected Need for: (.+)$", "need")
  eq(ns._test.BuildPattern(S.OLD_LOOT.LOOT_ROLL_ROLLED_NEED), "^Need Roll %- (%d+) for (.+) by (.+)$", "rolled")
end)

test("BuildPattern: positional, %% literal, magic chars, trailing text, no captures", function()
  local B = ns._test.BuildPattern
  eq(B("%2$s rolls Need on %1$s"), "^(.+) rolls Need on (.+)$", "positional")
  eq(B("Roll %1$d by %2$s"), "^Roll (%d+) by (.+)$", "positional %d")
  eq(B("100%% of %s"), "^100%% of (.+)$", "%% literal")
  eq(B("(%s) [x]"), "^%((.+)%) %[x%]$", "magic chars")
  eq(B("%s gets %s."), "^(.+) gets (.+)%.$", "trailing text")
  eq(B("50%x %s"), "^50%%x (.+)$", "stray percent")
  eq(B("Hello"), nil, "no captures")
  eq(B(""), nil, "empty")
  eq(B(nil), nil, "nil")
end)

test("BuildPattern output matches the formatted real strings", function()
  local B = ns._test.BuildPattern
  local id, a, b = NEED("Bob", "X"):match(B(LOOT_ROLL_NEED))
  eq(id, "4242", "loot id"); eq(a, "Bob", "need name"); eq(b, "X", "need item")
  local id2, n, i, p = ROLLED(42, "X", "Bob"):match(B(LOOT_ROLL_ROLLED_NEED))
  eq(id2, "4242", "loot id"); eq(n, "42", "roll"); eq(i, "X", "item"); eq(p, "Bob", "name")
end)

test("InitPatterns: idempotent, all three strings, most specific first", function()
  local pats = ns._test.patterns
  eq(#pats, 3, "pattern count")
  ns._test.InitPatterns()
  eq(#pats, 3, "pattern count after re-init")
  for i = 2, #pats do ok(#pats[i - 1] >= #pats[i], "sorted longest first") end
end)

-- Need-line parsing (real 1.60.1 format) -----------------------------------

test("ParseNeed: select line; loot-history ID never taken as the name", function()
  local name, link = ns._test.ParseNeed(NEED("Bob", I.robe58))
  eq(name, "Bob", "name"); eq(link, I.robe58, "link")
end)

test("ParseNeed: rolled line (both numbers skipped)", function()
  local name, link = ns._test.ParseNeed(ROLLED(87, I.robe58, "Bob"))
  eq(name, "Bob", "name"); eq(link, I.robe58, "link")
end)

test("ParseNeed: role-bonus line", function()
  local name, link = ns._test.ParseNeed(ROLE_BONUS(87, I.robe58, "Bob"))
  eq(name, "Bob", "name"); eq(link, I.robe58, "link")
end)

test("ParseNeed: item name containing ' by ' in the rolled line", function()
  local name, link = ns._test.ParseNeed(ROLLED(12, I.touchedByLight, "Bob"))
  eq(name, "Bob", "name"); eq(link, I.touchedByLight, "link")
end)

test("ParseNeed: item name containing the separator itself", function()
  local name, link = ns._test.ParseNeed(NEED("Ann", I.trickyName))
  eq(name, "Ann", "name"); eq(link, I.trickyName, "link")
end)

test("ParseNeed: player hyperlink and colour-coded names", function()
  local P = ns._test.ParseNeed
  local name = P(NEED("|Hplayer:Bob-Stormrage:42:PARTY|h[Bob]|h", I.robe58))
  eq(name, "Bob-Stormrage", "player link")
  name = P(NEED("|cffc79c6eBob|r", I.robe58))
  eq(name, "Bob", "colour code")
end)

test("ParseNeed: modern |cnIQ4: link colour", function()
  local name, link = ns._test.ParseNeed(NEED("Bob", I.modernLink))
  eq(name, "Bob", "name"); eq(link, I.modernLink, "link")
end)

test("ParseNeed: own, Greed and link-less lines are ignored", function()
  local P = ns._test.ParseNeed
  eq(P(SELF_NEED(I.robe58)), nil, "own roll (real format)")
  eq(P(("|HlootHistory:%d|h[Loot]|h: Bob has selected Greed for: %s"):format(ROLL_ID, I.robe58)), nil, "greed")
  eq(P(NEED("Bob", "nothing")), nil, "no link")
  eq(P(""), nil, "empty")
end)

-- Need-line parsing (spec's older format, extra coverage) ------------------

test("ParseNeed (old format): select, rolled, self, role bonus", function()
  S.UseOldLootStrings()
  ns._test.InitPatterns()
  local O, P = S.OLD_LOOT, ns._test.ParseNeed
  local name, link = P(O.LOOT_ROLL_NEED:format("Bob", I.robe58))
  eq(name, "Bob", "select name"); eq(link, I.robe58, "select link")
  name = P(O.LOOT_ROLL_ROLLED_NEED:format(87, I.touchedByLight, "Bob"))
  eq(name, "Bob", "rolled name")
  eq(P(O.LOOT_ROLL_NEED_SELF:format(I.robe58)), nil, "self")
  -- the old rolled pattern also matches a role-bonus line ("Bob + Role Bonus");
  -- the longer role-bonus pattern must win
  name = P(ROLE_BONUS(87, I.robe58, "Bob"))
  eq(name, "Bob", "role bonus name")
end)

test("ParseNeed: locale that reorders arguments", function()
  LOOT_ROLL_NEED = "%2$s: Need from %1$s"
  ns._test.InitPatterns()
  local name, link = ns._test.ParseNeed(I.robe58 .. ": Need from Bob")
  eq(name, "Bob", "name"); eq(link, I.robe58, "link")
end)

-- End to end: chat line -> alert ------------------------------------------

test("Need select + result lines alert once; again after 60 s", function()
  party()
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.spellDagger))
  S.fire("CHAT_MSG_LOOT", ROLLED(77, I.spellDagger, "Bob"))
  eq(S.chatCount("rolled NEED"), 1, "alerts")
  eq(S.chatCount("Bob|r rolled NEED on " .. I.spellDagger .. " - may be griefing loot"), 1, "headline wording")
  eq(S.chatCount("[High]|r stats/effects (Intellect, spell power/healing) don't suit a Warrior"), 1, "[High] line")
  eq(S.sounds, 1, "sounds")
  eq(#S.banners, 1, "banners")
  eq(#ns.db.log, 1, "log entries")
  eq(S.chatCount("gear not scanned yet"), 1, "unscanned note")
  S.advance(61)
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.spellDagger))
  eq(S.chatCount("rolled NEED"), 2, "alerts after window")
end)

test("no alert: own roll, below threshold, disabled, secret, not grouped", function()
  party()
  S.fire("CHAT_MSG_LOOT", NEED("Me", I.plateChest))        -- self
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.leatherChest))     -- Low only
  ns.db.minSeverity = 3
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.robe58 ))          -- would be High...
  eq(S.chatCount("rolled NEED"), 1, "High still alerts at sev 3")
  ns.db.enabled = false
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.spellDagger))
  ns.db.enabled = true
  local secret = NEED("Bob", I.staminaSpellGloves) -- High for a warrior
  S.secret[secret] = true
  S.fire("CHAT_MSG_LOOT", secret)
  S.SetGroup(S.units, nil)
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.spellDagger))
  eq(S.chatCount("rolled NEED"), 1, "alerts")
end)

test("uncached item: the retry itself alerts once the item is cached", function()
  party()
  S.units.party1.class = "MAGE"
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.uncachedPlate)) -- the only chat line
  eq(S.chatCount("rolled NEED"), 0, "no alert before cache")
  eq(S.loadRequests, 1, "requested item data")
  S.advance(1)
  eq(S.chatCount("rolled NEED"), 1, "alert from the 1 s retry")
  eq(S.chatCount("item info not loaded"), 0, "item was loaded: full checks ran")
end)

test("never-cached item: alert says only type checks ran", function()
  party()
  S.units.party1.class = "MAGE"
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.neverCachedPlate))
  S.advance(3)
  eq(S.chatCount("rolled NEED"), 1, "alert")
  eq(S.chatCount("(item info not loaded; only type checks ran)"), 1, "not-loaded note")
end)

test("never-cached item: judged after 3 retries with instant info", function()
  party()
  S.units.party1.class = "MAGE"
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.neverCachedPlate))
  S.advance(2.5)
  eq(S.chatCount("rolled NEED"), 0, "still retrying")
  S.advance(1)
  eq(S.chatCount("rolled NEED"), 1, "alert after retries")
  eq(S.loadRequests, 3, "load requests")
end)

test("announce goes to PARTY, also when LE_PARTY_CATEGORY_INSTANCE is missing", function()
  party()
  ns.db.announce = true
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.spellDagger))
  eq(#S.sent, 1, "sent")
  eq(S.sent[1].channel, "PARTY", "channel")
  LE_PARTY_CATEGORY_INSTANCE = nil
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.robe58))
  eq(#S.sent, 2, "sent")
  eq(S.sent[2].channel, "PARTY", "channel without constant")
  ok(not S.sent[1].msg:lower():find("ninja", 1, true), "wording")
  eq(S.sent[1].msg, "[AntiGrief] Bob's Need on " .. I.spellDagger
    .. " doesn't look like a fit: stats/effects (Intellect, spell power/healing) don't suit a Warrior", "announce text")
end)

test("alert lines: [High] first, then [Low] notes, in spec format", function()
  party()
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.robe58)) -- cloth Int robe on a warrior
  local n = #S.chat
  eq(S.chat[n - 3], "|cff40c0ffAntiGrief|r: |cffff4040Bob|r rolled NEED on " .. I.robe58 .. " - may be griefing loot", "headline")
  eq(S.chat[n - 2], "   |cffff4040[High]|r stats/effects (Intellect) don't suit a Warrior", "[High] line")
  eq(S.chat[n - 1], "   |cffd0d070[Low]|r Cloth is a lower armor type than a Warrior normally wears", "[Low] line")
  eq(S.chat[n], "   |cff999999(gear not scanned yet; upgrade check skipped)|r", "unscanned note")
end)

test("log keeps the newest 50", function()
  party()
  for i = 1, 55 do
    S.AddItem { id = 2000 + i, name = "Plate " .. i, classID = ARMOR, subclassID = PLATE, subType = "Plate",
      equipLoc = "INVTYPE_CHEST", ilvl = 60, minLevel = 55 }
    S.units.party1.class = "MAGE"
    S.fire("CHAT_MSG_LOOT", NEED("Bob", S.items[2000 + i].link))
  end
  eq(#ns.db.log, 50, "log size")
  ok(ns.db.log[1].item:find("Plate 55", 1, true), "newest first")
end)

test("drop report is on by default and lists every member, the player included", function()
  party()
  S.rolls[7] = I.robe58
  S.fire("START_LOOT_ROLL", 7)
  local n = #S.chat
  eq(S.chat[n - 2], "|cff40c0ffAntiGrief|r: new drop: " .. I.robe58, "header")
  eq(S.chat[n - 1], "   |cff40ff40Me (Mage): fits|r", "player line")
  eq(S.chat[n], "   |cffff4040Bob (Warrior): High - stats/effects (Intellect) don't suit a Warrior|r |cff999999(not scanned)|r",
    "unscanned Bob")
end)

-- Inspect queue ------------------------------------------------------------

test("inspect: queue, NotifyInspect, INSPECT_READY caches gear", function()
  party()
  S.units.party1.spec = 71
  S.advance(0.5)
  eq(#S.notified, 1, "notified"); eq(S.notified[1], "party1", "unit")
  S.fire("INSPECT_READY", GUID.bob)
  local c = ns.Inspect.cache[GUID.bob]
  ok(c, "cached")
  eq(c.items[16], I.spellDagger, "main hand")
  eq(c.spec, 71, "spec")
  eq(S.cleared, 1, "ClearInspectPlayer")
  local scanned, total, queued = ns.Inspect.Status()
  eq(scanned, 1, "scanned"); eq(total, 1, "total"); eq(queued, 0, "queued")
  local who = ns.Inspect.Who("party1")
  eq(who.items[1], I.clothHelm63, "Who items")
  ok(who ~= ns.Inspect.Who("party1"), "Who returns a fresh table")
end)

test("inspect: unanswered request times out and retries after cooldown", function()
  party()
  S.advance(0.5)
  eq(#S.notified, 1, "first request")
  S.advance(5)
  eq(#S.notified, 1, "no request during cooldown")
  S.advance(7.5)
  eq(#S.notified, 2, "retried")
end)

test("inspect: out of range goes to the back with a cooldown", function()
  party()
  S.units.party1.far = true
  S.advance(3)
  eq(#S.notified, 0, "not inspected while far")
  S.units.party1.far = false
  S.advance(8)
  eq(#S.notified, 1, "inspected once in range")
end)

test("inspect: skips turns in combat", function()
  party()
  S.combat = true
  S.advance(5)
  eq(#S.notified, 0, "no inspect in combat")
  S.combat = false
  S.advance(0.5)
  eq(#S.notified, 1, "inspect after combat")
end)

test("inspect: late links re-read after 0.6 s and queue held meanwhile", function()
  party({ party2 = { guid = GUID.ann, name = "Ann", class = "PRIEST", level = 60, items = { [1] = I.clothHelm63 } } })
  S.units.party1.lateLinks = { [16] = true }
  S.advance(0.5)
  eq(#S.notified, 1, "first request")
  S.advance(1.4)                         -- answer arrives late (t = 1001.9)
  S.units.party1.linksReadyAt = S.now + 0.5
  S.fire("INSPECT_READY", GUID.bob)
  eq(ns.Inspect.cache[GUID.bob].items[16], nil, "link not ready yet")
  eq(S.cleared, 0, "not cleared yet")
  S.advance(0.1)                         -- 1002.0: gap passed, but retry pending
  eq(#S.notified, 1, "queue held during re-read")
  S.advance(1.1)                         -- 1003.1
  eq(ns.Inspect.cache[GUID.bob].items[16], I.spellDagger, "re-read link")
  eq(S.cleared, 1, "cleared after re-read")
  eq(#S.notified, 2, "next member inspected")
end)

test("inspect: members who leave are pruned", function()
  party()
  S.advance(0.5)
  S.fire("INSPECT_READY", GUID.bob)
  ok(ns.Inspect.cache[GUID.bob], "cached")
  S.units.party1 = nil
  S.fire("GROUP_ROSTER_UPDATE")
  eq(ns.Inspect.cache[GUID.bob], nil, "pruned")
end)

test("inspect: UNIT_INVENTORY_CHANGED re-queues a member", function()
  party()
  S.advance(0.5)
  S.fire("INSPECT_READY", GUID.bob)
  local _, _, queued = ns.Inspect.Status()
  eq(queued, 0, "queue empty")
  S.fire("UNIT_INVENTORY_CHANGED", "party1")
  _, _, queued = ns.Inspect.Status()
  eq(queued, 1, "re-queued")
  S.fire("UNIT_INVENTORY_CHANGED", "partypet1")
  _, _, queued = ns.Inspect.Status()
  eq(queued, 1, "pets ignored")
end)

local function scanBob()
  S.advance(0.5)
  eq(S.notified[#S.notified], "party1", "inspected Bob")
  S.fire("INSPECT_READY", GUID.bob)
  ok(ns.Inspect.cache[GUID.bob], "Bob cached")
end

local function queuedCount()
  local _, _, q = ns.Inspect.Status()
  return q
end

test("inspect: paused while Blizzard's InspectFrame is shown", function()
  party()
  S.inspectFrameShown = true
  S.advance(5)
  eq(#S.notified, 0, "no inspect while the Inspect window is open")
  S.inspectFrameShown = false
  S.advance(0.5)
  eq(#S.notified, 1, "inspect once it closes")
end)

test("inspect: an open InspectFrame isn't cleared under the player", function()
  party()
  S.advance(0.5)
  S.inspectFrameShown = true -- player opened Inspect while our request was out
  S.fire("INSPECT_READY", GUID.bob)
  ok(ns.Inspect.cache[GUID.bob], "still cached")
  eq(S.cleared, 0, "ClearInspectPlayer not called while the window is open")
end)

test("inspect: 1.5 s gap between requests to two members", function()
  party({ party2 = { guid = GUID.ann, name = "Ann", class = "PRIEST", level = 60, items = {} } })
  S.advance(0.5)                 -- t = 1000.5: Bob
  eq(#S.notified, 1, "first request")
  S.fire("INSPECT_READY", GUID.bob) -- answered at once, so nothing is pending
  S.advance(0.5)                 -- +0.5 s
  eq(#S.notified, 1, "no request 0.5 s later")
  S.advance(0.5)                 -- +1.0 s
  eq(#S.notified, 1, "no request 1.0 s later")
  S.advance(0.5)                 -- +1.5 s
  eq(#S.notified, 2, "second request at +1.5 s")
  eq(S.notified[2], "party2", "Ann")
end)

test("inspect: offline member is re-queued with a cooldown", function()
  party()
  S.units.party1.offline = true
  S.advance(0.5)
  eq(#S.notified, 0, "offline: not inspected")
  eq(queuedCount(), 1, "back in the queue")
  S.units.party1.offline = false
  S.advance(5)
  eq(#S.notified, 0, "cooldown still running at +5 s")
  S.advance(3.5)
  eq(#S.notified, 1, "inspected after the 8 s cooldown")
end)

test("inspect: CanInspect false is re-queued with a cooldown", function()
  party()
  S.units.party1.noInspect = true
  S.advance(0.5)
  eq(#S.notified, 0, "CanInspect false: not inspected")
  eq(queuedCount(), 1, "back in the queue")
  S.units.party1.noInspect = false
  S.advance(8.5)
  eq(#S.notified, 1, "inspected after the cooldown")
end)

test("inspect: UNIT_INVENTORY_CHANGED re-scan at most every 30 s", function()
  party()
  scanBob()                                  -- t = 1000.5
  S.fire("UNIT_INVENTORY_CHANGED", "party1") -- first change: queued
  eq(queuedCount(), 1, "first change queues")
  S.advance(2)                               -- re-scan goes out and is answered
  S.fire("INSPECT_READY", GUID.bob)
  eq(queuedCount(), 0, "re-scanned")
  S.fire("UNIT_INVENTORY_CHANGED", "party1") -- 2 s after the first: throttled
  eq(queuedCount(), 0, "second change within 30 s ignored")
  S.advance(29)                              -- 31 s after the first
  S.fire("UNIT_INVENTORY_CHANGED", "party1")
  eq(queuedCount(), 1, "change after 30 s queues again")
end)

test("inspect: cached gear is re-scanned after 10 minutes", function()
  party()
  scanBob()                       -- cached at t = 1000.5
  S.fire("GROUP_ROSTER_UPDATE")
  eq(queuedCount(), 0, "fresh cache not re-queued")
  S.advance(598)                  -- age 598 s
  S.fire("GROUP_ROSTER_UPDATE")
  eq(queuedCount(), 0, "under 10 minutes: not re-queued")
  S.advance(2)                    -- age 600 s
  S.fire("GROUP_ROSTER_UPDATE")
  eq(queuedCount(), 1, "stale after 10 minutes: re-queued")
end)

-- Spec reading (C_SpecializationInfo via D.PlayerSpecID / D.InspectSpecID) -

test("spec: own spec read via C_SpecializationInfo; 0 or nil index = unknown", function()
  party()
  S.playerSpecIndex, S.playerSpecID = 1, 65
  eq(ns.Inspect.Who("player").spec, 65, "known spec")
  S.playerSpecIndex = 0
  eq(ns.Inspect.Who("player").spec, nil, "index 0")
  S.playerSpecIndex = nil
  eq(ns.Inspect.Who("player").spec, nil, "nil index")
  S.playerSpecIndex, S.playerSpecID = 1, 0
  eq(ns.Inspect.Who("player").spec, nil, "spec ID 0")
end)

local function scanPaladin(spec)
  -- Ann replaces Bob as party1 (party unit tokens must be contiguous)
  party({ party1 = { guid = GUID.ann, name = "Ann", class = "PALADIN", level = 60, spec = spec, items = {} } })
  S.advance(0.5)
  eq(S.notified[1], "party1", "inspected Ann")
  S.fire("INSPECT_READY", GUID.ann)
  return ns.Inspect.Who("party1")
end

test("spec: inspected spec 0 -> nil -> class-wide stats (no flag)", function()
  local who = scanPaladin(0)
  eq(who.spec, nil, "spec")
  local _, sev = evaluate(I.plateChest, who)
  eq(sev, 0, "Strength plate fits an unknown-spec paladin")
end)

test("spec: inspected Holy (65) narrows a paladin to caster stats", function()
  local who = scanPaladin(65)
  eq(who.spec, 65, "spec")
  local _, sev = evaluate(I.plateChest, who)
  eq(sev, 3, "Strength plate on Holy")
end)

test("spec: secret inspect spec is treated as unknown", function()
  S.secret[65] = true
  local who = scanPaladin(65)
  eq(who.spec, nil, "spec")
end)

test("secret GUIDs are skipped by the inspect queue", function()
  party()
  S.secret[GUID.bob] = true
  S.fire("GROUP_ROSTER_UPDATE")
  S.advance(2)
  eq(#S.notified, 0, "no inspect for a secret GUID")
  S.fire("INSPECT_READY", GUID.bob) -- must not error
end)

-- Banner and announce --------------------------------------------------------

test("banner: shown via RaidWarningUtil with the raid-warning colour", function()
  party()
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.spellDagger))
  eq(#S.banners, 1, "banners")
  ok(S.banners[1].text:find("Bob may be griefing", 1, true), "banner text")
  eq(S.banners[1].color, ChatTypeInfo.RAID_WARNING, "colour")
end)

test("banner: no banner API and no ChatTypeInfo doesn't break the alert", function()
  party()
  RaidWarningUtil, RaidNotice_AddMessage, ChatTypeInfo = nil, nil, nil
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.spellDagger))
  eq(S.chatCount("rolled NEED"), 1, "chat alert")
  eq(S.sounds, 1, "sound")
end)

test("banner: off when the screen setting is off", function()
  party()
  ns.db.screen = false
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.spellDagger))
  eq(#S.banners, 0, "banners")
end)

test("announce: skipped during chat messaging lockdown, alert still shown", function()
  party()
  ns.db.announce = true
  S.chatLockdown = true
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.spellDagger))
  eq(#S.sent, 0, "nothing sent in lockdown")
  eq(S.chatCount("rolled NEED"), 1, "private alert shown")
  S.chatLockdown = false
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.robe58))
  eq(#S.sent, 1, "sent after lockdown")
end)

test("announce: a send that raises is contained by pcall", function()
  party()
  ns.db.announce = true
  C_ChatInfo.SendChatMessage = function() error("blocked") end
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.spellDagger))
  eq(#ns.db.log, 1, "alert completed and logged")
end)

-- Pawn (fake Pawn 2.14.1 API) -------------------------------------------------

-- values[itemID][scale] = { Value, UnenchantedValue }
local function fakePawn(values)
  local calls = { scales = 0 }
  C_AddOns.IsAddOnLoaded = function(name) return name == "Pawn" end
  PawnGetAllScalesEx = function()
    calls.scales = calls.scales + 1
    return {
      { Name = '"Classic":WARRIOR1' }, { Name = '"Classic":WARRIOR2' },
      { Name = '"Classic":HUNTER1' }, { Name = '"Classic":DEMONHUNTER1' },
      { Name = "My custom WARRIOR scale" },
    }
  end
  PawnGetItemData = function(link)
    local id = tonumber(link:match("item:(%d+)"))
    if not id or (S.items[id] and S.items[id].uncached) then return nil end -- uncached -> nil
    return { id = id }
  end
  PawnGetSingleValueFromItem = function(item, scale)
    local v = values[item.id] and values[item.id][scale]
    if not v then return 0, 0 end
    return v[1], v[2]
  end
  return calls
end

test("pawn: nothing is called before PawnIsInitialized", function()
  local calls = fakePawn({})
  PawnIsInitialized = nil
  eq(ns.Rules.PawnAvailable(), false, "not available")
  local f = evaluate(I.plateChestBoE, { name = "Bob", class = "WARRIOR", level = 60, items = { [5] = I.plateChest } })
  eq(calls.scales, 0, "PawnGetAllScalesEx not called")
  expectNoFinding(f, 2, "Pawn")
end)

test("pawn: unenchanted values compared; best class scale wins", function()
  fakePawn({
    [1011] = { ['"Classic":WARRIOR1'] = { 45, 45 }, ['"Classic":WARRIOR2'] = { 30, 30 } },
    [1001] = { ['"Classic":WARRIOR1'] = { 50, 40 }, ['"Classic":WARRIOR2'] = { 35, 35 } },
  })
  PawnIsInitialized = true
  local who = { name = "Bob", class = "WARRIOR", level = 60, items = { [5] = I.plateChest } }
  local delta = ns.Rules.PawnUpgradeCheck(I.plateChestBoE, who, { 5 })
  ok(delta and math.abs(delta - 0.125) < 1e-9, "delta vs unenchanted 40: " .. tostring(delta))
  local f, sev = evaluate(I.plateChestBoE, who)
  eq(sev, 0, "upgrade under WARRIOR1 " .. dump(f))
end)

test("pawn: worse by 20%+ under every class scale -> High", function()
  fakePawn({
    [1011] = { ['"Classic":WARRIOR1'] = { 30, 30 }, ['"Classic":WARRIOR2'] = { 20, 20 } },
    [1001] = { ['"Classic":WARRIOR1'] = { 40, 40 }, ['"Classic":WARRIOR2'] = { 35, 35 } },
  })
  PawnIsInitialized = true
  local f, sev = evaluate(I.plateChestBoE, { name = "Bob", class = "WARRIOR", level = 60, items = { [5] = I.plateChest } })
  eq(sev, 3, "maxSev")
  expectFinding(f, 3, "Pawn scores it 25% below their current Chest")
end)

test("pawn: HUNTER scales don't include DEMONHUNTER; zero score flags High", function()
  fakePawn({ [1015] = { ['"Classic":HUNTER1'] = { 0, 0 }, ['"Classic":DEMONHUNTER1'] = { 100, 100 } } })
  PawnIsInitialized = true
  eq(ns.Rules.PawnBestScore(I.leatherChest, "HUNTER"), 0, "best hunter score")
  local f, sev = evaluate(I.leatherChest, { name = "Hun", class = "HUNTER", level = 60 })
  eq(sev, 3, "maxSev")
  expectFinding(f, 3, "no value under any Hunter Pawn scale")
end)

test("pawn: uncached item -> nil score -> item-level fallback", function()
  fakePawn({})
  PawnIsInitialized = true
  eq(ns.Rules.PawnBestScore(I.uncachedPlate, "WARRIOR"), nil, "no score for uncached")
  eq(ns.Rules.PawnUpgradeCheck(I.clothHelm52, { class = "MAGE", items = { [1] = I.clothHelm63 } }, { 1 }), nil,
    "no MAGE scales -> nil")
  local _, sev = evaluate(I.clothHelm52, { name = "Zap", class = "MAGE", level = 60, items = { [1] = I.clothHelm63 } })
  eq(sev, 2, "item-level Medium still applies")
end)

test("pawn: 1-19% worse under every class scale -> Medium", function()
  fakePawn({
    [1011] = { ['"Classic":WARRIOR1'] = { 36, 36 }, ['"Classic":WARRIOR2'] = { 27, 27 } },
    [1001] = { ['"Classic":WARRIOR1'] = { 40, 40 }, ['"Classic":WARRIOR2'] = { 30, 30 } },
  })
  PawnIsInitialized = true
  local f, sev = evaluate(I.plateChestBoE, { name = "Bob", class = "WARRIOR", level = 60, items = { [5] = I.plateChest } })
  eq(sev, 2, "maxSev " .. dump(f))
  expectFinding(f, 2, "Pawn scores it 10% below their current Chest under every Warrior spec")
  expectFinding(f, 1, "Bind on Equip") -- BoE note follows the Medium finding
end)

test("pawn: custom scales without the \"Classic\":CLASSn shape are excluded", function()
  fakePawn({
    [1015] = { ['"Classic":WARRIOR1'] = { 0, 0 }, ['"Classic":WARRIOR2'] = { 0, 0 },
               ["My custom WARRIOR scale"] = { 100, 100 } },
  })
  PawnIsInitialized = true
  eq(ns.Rules.PawnBestScore(I.leatherChest, "WARRIOR"), 0, "custom scale's 100 ignored")
  local f = evaluate(I.leatherChest, { name = "Bob", class = "WARRIOR", level = 60 })
  expectFinding(f, 3, "no value under any Warrior Pawn scale")
end)

-- Slash commands and settings ------------------------------------------------

test("slash commands run without errors", function()
  local cmd = SlashCmdList.ANTIGRIEF
  party()
  cmd("")
  ok(S.chatCount("commands:") == 1, "help")
  cmd("status")
  ok(S.chatCount("scanned 0/1") == 1, "status")
  cmd("sev 2.5"); eq(ns.db.minSeverity, 2, "fractional sev rejected")
  cmd("sev 3"); eq(ns.db.minSeverity, 3, "sev set")
  cmd("margin 5"); eq(ns.db.upgradeMargin, 5, "margin set")
  cmd("margin -1"); eq(ns.db.upgradeMargin, 0, "negative margin clamped to 0")
  cmd("margin 5")
  cmd("sound"); eq(ns.db.sound, false, "sound toggled")
  cmd("gear"); ok(S.chatCount("usage: /ag gear") == 1, "gear usage")
  cmd("gear nobody"); ok(S.chatCount("no group member named nobody") == 1, "gear unknown")
  cmd("gear bob"); ok(S.chatCount("hasn't been scanned yet") == 1, "gear unscanned (case-insensitive)")
  cmd("test look at " .. I.plateChest .. " please")
  ok(S.chatCount("Me (Mage): ") == 1, "test verdict for me")
  cmd("test nothing"); ok(S.chatCount("usage: /ag test") == 1, "test usage")
  cmd("off"); eq(ns.db.enabled, false, "off")
  cmd("on"); eq(ns.db.enabled, true, "on")
  cmd("log"); ok(S.chatCount("no flags logged") == 1, "empty log")
  ns.db.minSeverity = 2
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.spellDagger))
  cmd("log"); ok(S.chatCount("recent drops:") == 1, "log")
  cmd("clear"); eq(#ns.db.log, 0, "cleared")
end)

test("/ag test solo and with a nameless member doesn't error", function()
  S.SetGroup({ player = { guid = GUID.me, name = "Me", class = "MAGE", level = 60, items = {} } }, nil)
  SlashCmdList.ANTIGRIEF("test " .. I.plateChest)
  ok(S.chatCount("Me (Mage): ") == 1, "solo verdict")
  party({ party2 = { guid = GUID.zap, name = "Zap", noName = true, class = "MAGE", level = 60 } })
  SlashCmdList.ANTIGRIEF("test " .. I.plateChest)
  ok(S.chatCount("? (Mage): ") == 1, "nameless member shown as ?")
end)

test("saved settings: all eight spec defaults on a fresh DB", function()
  local db = ns.db
  eq(db, AntiGriefDB, "db bound to the SavedVariable")
  eq(db.enabled, true, "enabled")
  eq(db.minSeverity, 2, "minSeverity")
  eq(db.sound, true, "sound")
  eq(db.screen, true, "screen")
  eq(db.announce, false, "announce")
  eq(db.dropReport, true, "dropReport (replaces hints)")
  eq(db.hints, nil, "no hints key")
  eq(db.upgradeMargin, 8, "upgradeMargin")
  eq(db.usePawn, true, "usePawn")
  eq(type(db.log), "table", "log"); eq(#db.log, 0, "log empty")
end)

test("saved settings: defaults merged, user values kept, corrupt values fixed", function()
  -- reload with an existing DB
  S = assert(loadfile(path("tests/wowstub.lua")))()
  AntiGriefDB = { sound = false, minSeverity = 7, upgradeMargin = "x", log = "bad" }
  loadAddon()
  S.fire("ADDON_LOADED", "SomeOtherAddon")
  eq(ns.db, nil, "ignores other addons")
  S.fire("ADDON_LOADED", ADDON)
  eq(ns.db, AntiGriefDB, "db bound")
  eq(ns.db.sound, false, "user value kept")
  eq(ns.db.minSeverity, 2, "bad severity reset")
  eq(ns.db.upgradeMargin, 8, "bad margin reset")
  eq(type(ns.db.log), "table", "log fixed")
  eq(ns.db.enabled, true, "default filled")
end)

-- Drop report (START_LOOT_ROLL) ---------------------------------------------

local function linesSince(n0)
  local t = {}
  for i = n0 + 1, #S.chat do t[#t + 1] = S.chat[i] end
  return t
end

local function roll(id, link)
  S.rolls[id] = link
  local n0 = #S.chat
  S.fire("START_LOOT_ROLL", id)
  return linesSince(n0)
end

test("drop report: party lines for fits, High, Medium and not scanned", function()
  party({ party2 = { guid = GUID.ann, name = "Ann", class = "PRIEST", level = 60, items = {} } })
  scanBob() -- Bob scanned; Ann not
  local out = roll(7, I.robe58)
  eq(#out, 4, "header + 3 members")
  eq(out[1], "|cff40c0ffAntiGrief|r: new drop: " .. I.robe58, "header")
  eq(out[2], "   |cff40ff40Me (Mage): fits|r", "player fits")
  -- Bob's findings are [Low] cloth note first, [High] stats second: the High one is shown
  eq(out[3], "   |cffff4040Bob (Warrior): High - stats/effects (Intellect) don't suit a Warrior|r", "scanned Bob")
  eq(out[4], "   |cff40ff40Ann (Priest): fits|r |cff999999(not scanned)|r", "unscanned Ann")
  -- the player is judged on the gear they're wearing (never in the inspect cache)
  out = roll(8, I.clothHelm52)
  eq(out[2], "   |cffff9930Me (Mage): Medium - not an upgrade: item level 52 vs their " .. I.clothHelm63:sub(1, -3)
    .. "|r|cffff9930 (item level 63)|r", "player's own helm; colour resumes after the link")
end)

-- Raid of n members: raid1 is the player (Mage); `fitCount` warriors, the rest mages
local function raid(n, fitCount)
  local units = {}
  for i = 1, n do
    local isWarrior = i > 1 and i <= fitCount + 1
    units["raid" .. i] = { guid = "Player-1-1" .. i, name = (i == 1) and "Me" or ((isWarrior and "W" or "M") .. i),
      class = isWarrior and "WARRIOR" or "MAGE", level = 60, items = {} }
  end
  units.player = units.raid1
  S.SetGroup(units, "raid")
  S.fire("GROUP_ROSTER_UPDATE")
end

test("drop report: raid collapses to a fits line and caps the rest", function()
  eq(ns._test.DROP_REPORT_MAX, 10, "cap constant")
  raid(14, 2) -- 2 warriors fit plate; 12 mages (the player included) don't
  local out = roll(1, I.plateChest)
  eq(#out, 13, "header + fits line + 10 + 'more'")
  eq(out[1], "|cff40c0ffAntiGrief|r: new drop: " .. I.plateChest, "header")
  eq(out[2], "   |cff40ff40fits: W2, W3|r", "fits line")
  eq(out[3], "   |cffff4040Me (Mage): High - Mage can't use Plate|r", "first misfit")
  for i = 3, 12 do ok(out[i]:find("(Mage): High", 1, true), "misfit line " .. i) end
  eq(out[13], "   |cff999999...and 2 more|r", "overflow line")
end)

test("drop report: a member whose only finding is Low is listed as a misfit, not 'fits'", function()
  -- Fits() (AntiGrief.lua:285) is maxSev < Low: a Low-only member gets a Low line
  party()
  local out = roll(40, I.leatherChest) -- leather on a level-60 warrior: Low lower-armor note only
  eq(out[3], "   |cffd0d070Bob (Warrior): Low - Leather is a lower armor type than a Warrior normally wears|r"
    .. " |cff999999(not scanned)|r", "party: Low line")
  raid(11, 2) -- W2, W3 get only the Low note; the mages (player included) get High
  out = roll(41, I.leatherChest)
  eq(out[2], "   |cff40ff40fits: nobody|r", "raid: Low-only warriors not on the fits line")
  eq(out[4], "   |cffd0d070W2 (Warrior): Low - Leather is a lower armor type than a Warrior normally wears|r"
    .. " |cff999999(not scanned)|r", "raid: W2 has a Low line")
  eq(out[#out], "   |cff999999...and 1 more|r", "11 misfits: 10 lines + 1 more")
end)

test("drop report: exactly 10 members get one line each; nobody fits shows 'nobody'", function()
  raid(10, 3)
  local out = roll(1, I.plateChest)
  eq(#out, 11, "header + 10 member lines")
  eq(out[2], "   |cffff4040Me (Mage): High - Mage can't use Plate|r", "no collapse")
  raid(11, 0)
  out = roll(2, I.plateChest)
  eq(out[2], "   |cff40ff40fits: nobody|r", "nobody fits")
  eq(#out, 13, "header + fits + 10 + 'more'")
  eq(out[13], "   |cff999999...and 1 more|r", "overflow")
end)

test("drop report: items AntiGrief doesn't judge print nothing", function()
  party()
  eq(#roll(3, I.potion), 0, "potion")
  eq(#roll(4, I.shirt), 0, "shirt")
  eq(#roll(5, nil), 0, "no link")
end)

test("drop report: uncached item retried 1 s later, then reported", function()
  party()
  eq(#roll(9, I.uncachedPlate), 0, "nothing while uncached")
  eq(S.loadRequests, 1, "item data requested")
  local n0 = #S.chat
  S.advance(1)
  local out = linesSince(n0)
  eq(out[1], "|cff40c0ffAntiGrief|r: new drop: " .. I.uncachedPlate, "report from the retry")
  eq(#out, 3, "header + 2 members")
end)

test("drop report: never-cached item gives up silently after 3 retries", function()
  party()
  local n0 = #S.chat
  roll(10, I.neverCachedPlate)
  S.advance(10)
  eq(#S.chat, n0, "nothing printed")
  eq(S.loadRequests, 3, "three load requests")
end)

test("drop report: one report per rollID, also across retries", function()
  party()
  eq(#roll(11, I.robe58), 3, "first report")
  eq(#roll(11, I.robe58), 0, "same rollID again")
  eq(#roll(12, I.robe58), 3, "a new rollID with the same item reports")
  roll(13, I.uncachedPlate)
  roll(13, I.uncachedPlate) -- fired twice while still uncached
  S.advance(5)
  eq(S.chatCount("new drop: " .. I.uncachedPlate), 1, "one report for the retried roll")
end)

test("drop report: off with dropReport=false or enabled=false, also mid-retry", function()
  party()
  ns.db.dropReport = false
  eq(#roll(14, I.robe58), 0, "dropReport off")
  ns.db.dropReport, ns.db.enabled = true, false
  eq(#roll(15, I.robe58), 0, "addon off")
  ns.db.enabled = true
  roll(16, I.uncachedPlate)
  ns.db.dropReport = false
  S.advance(3)
  eq(S.chatCount("new drop:"), 0, "dropReport turned off during the retry")
  ns.db.dropReport = true
  local slow2 = S.AddItem { id = 4001, name = "Slower Breastplate", classID = ARMOR, subclassID = PLATE,
    subType = "Plate", equipLoc = "INVTYPE_CHEST", ilvl = 66, minLevel = 60, uncached = true }
  eq(#roll(18, slow2), 0, "uncached")
  ns.db.enabled = false
  S.advance(3)
  eq(S.chatCount("new drop:"), 0, "addon turned off during the retry")
end)

test("drop report: private; never sent to chat, no banner, sound or log", function()
  party()
  ns.db.announce = true
  roll(17, I.plateChest) -- High for the mage player
  eq(S.chatCount("new drop:"), 1, "reported")
  eq(#S.sent, 0, "nothing sent to the group")
  eq(#S.banners, 0, "no banner"); eq(S.sounds, 0, "no sound"); eq(#ns.db.log, 0, "not logged")
end)

test("/ag test: exact lines through the shared formatter", function()
  party()
  local n0 = #S.chat
  SlashCmdList.ANTIGRIEF("test " .. I.robe58)
  local out = linesSince(n0)
  eq(out[1], "|cff40c0ffAntiGrief|r: |cff40ff40Me (Mage): fits|r", "player")
  eq(out[2], "|cff40c0ffAntiGrief|r: |cffff4040Bob (Warrior): High - stats/effects (Intellect) don't suit a Warrior|r"
    .. " |cff999999(not scanned)|r", "Bob verdict")
  eq(out[3], "   [Low] Cloth is a lower armor type than a Warrior normally wears", "Bob finding 1")
  eq(out[4], "   [High] stats/effects (Intellect) don't suit a Warrior", "Bob finding 2")
  eq(#out, 4, "line count")
  n0 = #S.chat
  SlashCmdList.ANTIGRIEF("test " .. I.potion)
  eq(S.chat[#S.chat], "|cff40c0ffAntiGrief|r: AntiGrief doesn't judge this item (not equippable gear)", "non-gear")
  eq(#S.chat, n0 + 1, "one line")
end)

-- Settings migration and slash toggles -----------------------------------

local function reloadWith(db)
  S = assert(loadfile(path("tests/wowstub.lua")))()
  AntiGriefDB = db
  loadAddon()
  S.fire("ADDON_LOADED", ADDON)
  items()
end

test("saved settings: old hints=false doesn't carry over; the hints key is removed", function()
  reloadWith({ hints = false, sound = false })
  eq(ns.db.dropReport, true, "new key gets its default")
  eq(ns.db.hints, nil, "hints removed")
  eq(AntiGriefDB.hints, nil, "removed from the SavedVariable")
  eq(ns.db.sound, false, "other user values kept")
  reloadWith({ hints = true, dropReport = false })
  eq(ns.db.dropReport, false, "a saved dropReport=false is kept")
  eq(ns.db.hints, nil, "hints removed")
end)

test("/ag drops and /ag hints toggle dropReport; status and help mention it", function()
  local cmd = SlashCmdList.ANTIGRIEF
  cmd("drops"); eq(ns.db.dropReport, false, "drops off")
  eq(S.chat[#S.chat], "|cff40c0ffAntiGrief|r: Drop report |cffff4040off|r", "message")
  cmd("hints"); eq(ns.db.dropReport, true, "hints alias on")
  cmd("DROPS"); eq(ns.db.dropReport, false, "case-insensitive")
  eq(ns.db.hints, nil, "no hints key written")
  cmd("status"); eq(S.chatCount("drop report |cffff4040off|r"), 1, "status line")
  eq(S.chatCount("hints |c"), 0, "status no longer shows hints")
  cmd("help")
  eq(S.chatCount("/ag drops - toggle the fit report on new drops (alias: hints)"), 1, "help: drops")
  eq(S.chatCount("/ag config - open the options panel"), 1, "help: config")
end)

-- Options panel hooks (ns.Config replaced by a recorder) ---------------------

local function fakeConfig()
  local rec = { init = 0, open = 0, refresh = {} }
  ns.Config = {
    Init = function() rec.init = rec.init + 1 end,
    Open = function() rec.open = rec.open + 1 end,
    Refresh = function(key) rec.refresh[#rec.refresh + 1] = key end,
  }
  return rec
end

test("config: Init runs once at ADDON_LOADED, after the settings are loaded", function()
  S = assert(loadfile(path("tests/wowstub.lua")))()
  loadAddon()
  local calls, sawDB = 0, nil
  ns.Config = { Init = function() calls = calls + 1; sawDB = ns.db end }
  S.fire("ADDON_LOADED", "SomeOtherAddon")
  eq(calls, 0, "not for other addons")
  S.fire("ADDON_LOADED", ADDON)
  S.fire("ADDON_LOADED", ADDON)
  eq(calls, 1, "once")
  ok(sawDB ~= nil and sawDB == AntiGriefDB, "settings loaded before Init")
end)

test("config: RegisterAddOnSetting raising -> one 'unavailable' line, /ag config hint, alerts work", function()
  fresh(function() Settings.RegisterAddOnSetting = function() error("boom") end end)
  items()
  ok(ns.db and ns.db.enabled, "addon loaded")
  if HAS_CONFIG then
    eq(S.chatCount("options page unavailable"), 1, "exactly one unavailable line")
    SlashCmdList.ANTIGRIEF("config")
    eq(S.chatCount("the options page isn't available on this client"), 1, "/ag config hint")
    eq(#S.cfg.opened, 0, "nothing opened")
  end
  eq(S.chatCount("options panel error"), 0, "contained inside Config.Init")
  party()
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.spellDagger))
  eq(S.chatCount("rolled NEED"), 1, "Need alert still fires")
end)

test("config: an error in Init is reported and the addon still starts", function()
  S = assert(loadfile(path("tests/wowstub.lua")))()
  loadAddon()
  ns.Config = { Init = function() error("panel broke") end }
  S.fire("ADDON_LOADED", ADDON)
  eq(S.chatCount("options panel error:"), 1, "error reported")
  eq(#ns._test.patterns, 3, "patterns built")
  items()
  party()
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.spellDagger))
  eq(S.chatCount("rolled NEED"), 1, "alerts still work")
end)

test("config: Init and /ag config are skipped without ns.Config", function()
  S = assert(loadfile(path("tests/wowstub.lua")))()
  loadAddon()
  ns.Config = nil
  S.fire("ADDON_LOADED", ADDON)
  ok(ns.db, "loaded")
  SlashCmdList.ANTIGRIEF("config")
  eq(S.chatCount("commands:"), 1, "falls back to the command list")
end)

test("/ag config and /ag options call Config.Open; fallback when Open is missing", function()
  local rec = fakeConfig()
  SlashCmdList.ANTIGRIEF("config")
  SlashCmdList.ANTIGRIEF("options")
  eq(rec.open, 2, "Open called")
  eq(S.chatCount("commands:"), 0, "no help when Open exists")
  ns.Config = { Refresh = function() end }
  SlashCmdList.ANTIGRIEF("config")
  eq(S.chatCount("commands:"), 1, "help when Open is missing")
end)

test("slash changes call Config.Refresh with the changed key", function()
  local rec = fakeConfig()
  local cmd = SlashCmdList.ANTIGRIEF
  for _, c in ipairs({ "off", "on", "sev 3", "margin 5", "sound", "screen", "announce", "drops", "hints", "pawn" }) do
    cmd(c)
  end
  eq(table.concat(rec.refresh, ","),
    "enabled,enabled,minSeverity,upgradeMargin,sound,screen,announce,dropReport,dropReport,usePawn", "keys")
  rec.refresh = {}
  for _, c in ipairs({ "sev 9", "margin x", "margin", "status", "scan", "log", "clear", "help", "test nothing" }) do
    cmd(c)
  end
  eq(#rec.refresh, 0, "no Refresh for rejected input or read-only commands")
end)

test("a client without the Settings API loads and runs /ag config", function()
  fresh(function() Settings = nil end)
  items()
  party()
  SlashCmdList.ANTIGRIEF("config")
  if HAS_CONFIG then
    eq(S.chatCount("the options page isn't available on this client"), 1, "Config.Open explains")
  else
    eq(S.chatCount("commands:"), 1, "no Config.lua: command list")
  end
  SlashCmdList.ANTIGRIEF("drops")
  eq(ns.db.dropReport, false, "toggle still works")
  roll(20, I.robe58)
end)

-- Config.lua itself (against the Settings stub) ------------------------------

if HAS_CONFIG then
  local EXPECTED = {
    { "enabled", "checkbox", "boolean" }, { "minSeverity", "dropdown", "number" },
    { "sound", "checkbox", "boolean" }, { "screen", "checkbox", "boolean" },
    { "announce", "checkbox", "boolean" }, { "dropReport", "checkbox", "boolean" },
    { "upgradeMargin", "slider", "number" }, { "usePawn", "checkbox", "boolean" },
    { "minimapButton", "checkbox", "boolean" },
  }

  local function settingFor(key)
    for _, c in ipairs(S.cfg.controls) do
      if c.setting.key == key then return c.setting end
    end
  end

  test("Config.lua: Init registers all nine controls bound to the right ns.db keys", function()
    eq(#S.cfg.categories, 1, "one category")
    eq(S.cfg.addOnCategories[1], S.cfg.categories[1], "registered as an addon category")
    eq(#S.cfg.addOnCategories, 1, "registered once")
    eq(#S.cfg.controls, 9, "controls")
    local vars = {}
    for i, want in ipairs(EXPECTED) do
      local c = S.cfg.controls[i]
      eq(c.setting.key, want[1], "control " .. i .. " key")
      eq(c.kind, want[2], want[1] .. " kind")
      eq(c.setting.varType, want[3], want[1] .. " type")
      eq(c.setting.tbl, ns.db, want[1] .. " bound to ns.db")
      eq(type(ns.db[want[1]]), want[3], want[1] .. " stored type matches")
      ok(not vars[c.setting.variable], "unique variable " .. tostring(c.setting.variable))
      vars[c.setting.variable] = true
    end
    local sev = settingFor("minSeverity")
    local dd
    for _, c in ipairs(S.cfg.controls) do if c.kind == "dropdown" then dd = c end end
    local choices = dd.options()
    eq(#choices, 3, "severity choices"); eq(choices[1].value, 1, "Low"); eq(choices[3].value, 3, "High")
    eq(sev:GetDefaultValue(), 2, "severity default")
    local SPEC_DEFAULTS = { enabled = true, minSeverity = 2, sound = true, screen = true, announce = false,
      dropReport = true, upgradeMargin = 8, usePawn = true, minimapButton = true }
    local n = 0
    for key, want in pairs(SPEC_DEFAULTS) do
      local st = settingFor(key)
      ok(st, key .. " has a control")
      eq(st:GetDefaultValue(), want, key .. " GetDefaultValue")
      n = n + 1
    end
    eq(n, 9, "all nine defaults checked")
    local slider
    for _, c in ipairs(S.cfg.controls) do if c.kind == "slider" then slider = c end end
    eq(slider.options.minValue, 0, "slider min"); eq(slider.options.maxValue, 30, "slider max")
    eq(slider.options.steps, 30, "slider steps: (30 - 0) / 1")
  end)

  test("Config.lua: the panel reads live values and writes ns.db", function()
    local cmd = SlashCmdList.ANTIGRIEF
    cmd("sev 3"); eq(settingFor("minSeverity"):GetValue(), 3, "slash change visible to the panel")
    cmd("drops"); eq(settingFor("dropReport"):GetValue(), false, "toggle visible to the panel")
    eq(settingFor("dropReport").updates, 1, "Refresh notified the dropReport control")
    eq(settingFor("minSeverity").updates, 1, "Refresh notified the severity control")
    eq(settingFor("sound").updates, 0, "other controls untouched")
    settingFor("announce"):SetValue(true); eq(ns.db.announce, true, "panel writes ns.db")
    settingFor("upgradeMargin"):SetValue(6.6); eq(ns.db.upgradeMargin, 7, "slider value kept whole")
    -- the drop report follows a panel change at once
    settingFor("dropReport"):SetValue(true)
    party()
    eq(#roll(30, I.robe58), 3, "report after re-enabling in the panel")
  end)

  test("Config.lua: /ag config opens the category; not in combat", function()
    SlashCmdList.ANTIGRIEF("config")
    eq(#S.cfg.opened, 1, "opened")
    eq(S.cfg.opened[1], S.cfg.categories[1]:GetID(), "our category")
    S.combat = true
    SlashCmdList.ANTIGRIEF("config")
    eq(#S.cfg.opened, 1, "not opened in combat")
    eq(S.chatCount("can't open the options in combat"), 1, "combat message")
  end)

  test("Config.lua: no Settings global -> Init does nothing, Open prints the hint", function()
    fresh(function() Settings = nil end)
    eq(#S.cfg.controls, 0, "no controls")
    eq(#S.cfg.categories, 0, "no category")
    ok(ns.db and ns.db.enabled, "addon loaded")
    ns.Config.Open()
    eq(S.chatCount("the options page isn't available on this client"), 1, "hint")
    eq(#S.cfg.opened, 0, "nothing opened")
  end)

  test("Config.lua: every control has a tooltip; variables are ANTIGRIEF_<key>", function()
    for _, c in ipairs(S.cfg.controls) do
      ok(type(c.tooltip) == "string" and c.tooltip ~= "", c.setting.key .. " tooltip")
      eq(c.setting.variable, "ANTIGRIEF_" .. c.setting.key, "variable name")
    end
  end)

  test("Config.lua: Init runs only once, even when called twice", function()
    ns.Config.Init()
    ns.Config.Init()
    eq(#S.cfg.controls, 9, "still 9 controls")
    eq(#S.cfg.categories, 1, "one category")
    eq(#S.cfg.addOnCategories, 1, "RegisterAddOnCategory called once")
  end)

  test("Config.lua: Open passes the category's numeric ID", function()
    ns.Config.Open()
    eq(type(S.cfg.opened[1]), "number", "number")
    eq(S.cfg.opened[1], S.cfg.categories[1]:GetID(), "category:GetID()")
  end)

  test("Config.lua: panel and /ag share one table, never a copy", function()
    local margin = settingFor("upgradeMargin")
    eq(margin.tbl, AntiGriefDB, "bound to the SavedVariable table itself")
    SlashCmdList.ANTIGRIEF("margin 12"); eq(margin:GetValue(), 12, "slash -> panel")
    margin:SetValue(20); eq(ns.db.upgradeMargin, 20, "panel -> db")
    SlashCmdList.ANTIGRIEF("status")
    eq(S.chatCount("margin 20"), 1, "panel value used by /ag status")
    settingFor("enabled"):SetValue(false)
    party()
    eq(#roll(31, I.robe58), 0, "panel off -> no drop report")
  end)
end

test("/ag margin is clamped to 0-30, whole numbers; usage says so", function()
  local cmd = SlashCmdList.ANTIGRIEF
  cmd("margin 50"); eq(ns.db.upgradeMargin, 30, "clamped high")
  eq(S.chat[#S.chat], "|cff40c0ffAntiGrief|r: upgrade margin 30 item levels (allowed 0-30)", "clamp message")
  cmd("margin -4"); eq(ns.db.upgradeMargin, 0, "clamped low")
  cmd("margin 6.6"); eq(ns.db.upgradeMargin, 7, "rounded")
  cmd("margin 9"); eq(S.chat[#S.chat], "|cff40c0ffAntiGrief|r: upgrade margin 9 item levels", "in range: no note")
  cmd("margin x"); eq(S.chat[#S.chat], "|cff40c0ffAntiGrief|r: usage: /ag margin <0-30>", "usage")
  eq(ns.db.upgradeMargin, 9, "unchanged by bad input")
  cmd("help"); eq(S.chatCount("/ag margin 0-30 - "), 1, "help")
  reloadWith({ upgradeMargin = 45 })
  eq(ns.db.upgradeMargin, 30, "saved value above the range clamped on load")
end)

-- Output tab: a chat window named AntiGrief receives everything ----------

test("output: an 'AntiGrief' chat tab gets all messages; closed or missing tab falls back", function()
  local cmd = SlashCmdList.ANTIGRIEF
  party()
  -- Real return order: name, fontSize, r, g, b, alpha, shown, locked, docked, uninteractable
  local windows = {
    { "General", 14, 0, 0, 0, 0.4, true, false, true, false },
    { "Combat Log", 14, 0, 0, 0, 0.4, false, false, true, false },
    { " antigrief ", 14, 0, 0, 0, 0.4, false, false, true, false }, -- docked, not the selected tab
  }
  local tab = {}
  rawset(_G, "GetChatWindowInfo", function(i)
    local w = windows[i]
    if w then return unpack(w) end
    return "", 14, 0, 0, 0, 0, false, false, false, false
  end)
  rawset(_G, "NUM_CHAT_WINDOWS", 10)
  rawset(_G, "ChatFrame3", { AddMessage = function(_, msg) tab[#tab + 1] = msg end })

  local mainBefore = #S.chat
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.spellDagger))
  eq(#S.chat, mainBefore, "nothing in main chat")
  ok(#tab >= 2, "alert headline and finding lines in the tab")
  ok(tab[1]:find("rolled NEED", 1, true), "headline in tab")
  eq(#S.banners, 1, "banner still shown")
  cmd("status")
  eq(tab[#tab], "   output: AntiGrief / AG Logs chat tab", "status names the tab")

  -- Closed window keeps its name but is neither shown nor docked
  windows[3][7], windows[3][9] = false, false
  cmd("status")
  ok(S.chat[#S.chat]:find("output: main chat", 1, true), "closed tab -> main chat")

  -- A GetChatWindowInfo error never breaks output
  rawset(_G, "GetChatWindowInfo", function() error("boom") end)
  cmd("log")
  ok(S.chat[#S.chat] ~= nil and #S.chat > mainBefore, "falls back on error")
  rawset(_G, "GetChatWindowInfo", nil)
  rawset(_G, "ChatFrame3", nil)
end)

-- Wins: "X won: [item]" after a Need that doesn't fit -------------------

local function WON(name, link) return LOOT_ROLL_WON:format(ROLL_ID, name, link) end
local function WON_NEED(name, n, link) return LOOT_ROLL_WON_NO_SPAM_NEED:format(ROLL_ID, name, n, link) end
local function WON_OFFSPEC(name, n, link) return LOOT_ROLL_WON_NO_SPAM_NEED_OFF_SPEC:format(ROLL_ID, name, n, link) end
local function WON_GREED(name, n, link) return LOOT_ROLL_WON_NO_SPAM_GREED:format(ROLL_ID, name, n, link) end
local function wins() local n = 0; for _, e in ipairs(ns.db.log) do if e.kind == "won" then n = n + 1 end end; return n end

test("ParseWin: default and no-spam Need lines; Greed and own wins don't parse", function()
  local P = ns._test
  local name, link, saysNeed = P.ParseWin(WON("Bob", I.spellDagger))
  eq(name, "Bob"); eq(link, I.spellDagger); eq(saysNeed, false, "default line has no roll type")
  name, link, saysNeed = P.ParseWin(WON_NEED("Bob", 87, I.spellDagger))
  eq(name, "Bob", "no-spam name"); eq(link, I.spellDagger); eq(saysNeed, true, "says Need")
  name, _, saysNeed = P.ParseWin(WON_OFFSPEC("Bob", 12, I.spellDagger))
  eq(name, "Bob", "off-spec name"); eq(saysNeed, true, "off-spec Need counts")
  eq(P.ParseWin(WON_GREED("Bob", 50, I.spellDagger)), nil, "Greed win not parsed")
  eq(P.ParseWin(LOOT_ROLL_YOU_WON:format(ROLL_ID, I.spellDagger)), nil, "own win not parsed")
  eq(P.ParseWin(LOOT_ROLL_ALL_PASSED:format(ROLL_ID, I.spellDagger)), nil, "all passed not parsed")
  eq(P.ParseWin(NEED("Bob", I.spellDagger)), nil, "a Need line isn't a win")
  eq(#P.winPatterns, 3, "three win patterns")
end)

test("wins: Need then won on a misfit -> chat line and a 'won' log entry", function()
  party()
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.spellDagger))
  eq(#ns.db.log, 1, "the Need flag")
  S.fire("CHAT_MSG_LOOT", WON("Bob", I.spellDagger))
  eq(wins(), 1, "win logged")
  local e = ns.db.log[1]
  eq(e.kind, "won"); eq(e.who, "Bob"); eq(e.item, I.spellDagger); eq(e.sev, 3)
  ok(e.why:find("don't suit a Warrior", 1, true), "reason kept: " .. tostring(e.why))
  eq(S.chatCount("Bob|r won " .. I.spellDagger .. " with Need - doesn't look like a fit"), 1, "chat line")
  eq(#S.banners, 1, "no second banner for the win"); eq(S.sounds, 1, "no second sound")
  -- history shows it as a win under the item
  SlashCmdList.ANTIGRIEF("log")
  eq(S.chatCount("|cffff66ff-- Bob won and is High for: stats/effects"), 1, "won line, own colour")
  eq(S.chatCount("- Bob is High: stats/effects"), 1, "the Need line under the same item")
end)

test("wins: Need-only - a default won line without a seen Need is ignored", function()
  party()
  S.fire("CHAT_MSG_LOOT", WON("Bob", I.spellDagger))
  eq(wins(), 0, "Greed win (no Need seen) not logged")
  eq(#ns.db.log, 0, "nothing logged")
end)

test("wins: no-spam Need lines count on their own; no-spam Greed doesn't", function()
  party()
  S.fire("CHAT_MSG_LOOT", WON_NEED("Bob", 87, I.spellDagger))
  eq(wins(), 1, "Main-Spec Need win")
  S.fire("CHAT_MSG_LOOT", WON_OFFSPEC("Bob", 12, I.robe58))
  eq(wins(), 2, "Off-Spec Need win")
  S.fire("CHAT_MSG_LOOT", WON_GREED("Bob", 50, I.staminaSpellGloves))
  eq(wins(), 2, "Greed win ignored")
end)

test("wins: a fitting item, a Need forgotten after 15 min, and own wins aren't logged", function()
  party()
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.plateChest)) -- plate suits a warrior
  S.fire("CHAT_MSG_LOOT", WON("Bob", I.plateChest))
  eq(wins(), 0, "fits -> no win entry")
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.spellDagger))
  S.advance(901)
  S.fire("CHAT_MSG_LOOT", WON("Bob", I.spellDagger))
  eq(wins(), 0, "Need older than 15 minutes doesn't count")
  S.fire("CHAT_MSG_LOOT", NEED("Me", I.spellDagger))
  S.fire("CHAT_MSG_LOOT", WON("Me", I.spellDagger))
  eq(wins(), 0, "own win ignored")
end)

test("wins: one Need is used once; another player's Need doesn't count for Bob", function()
  party()
  S.fire("CHAT_MSG_LOOT", NEED("Me", I.spellDagger))
  S.fire("CHAT_MSG_LOOT", WON("Bob", I.spellDagger))
  eq(wins(), 0, "someone else's Need")
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.spellDagger))
  S.fire("CHAT_MSG_LOOT", WON("Bob", I.spellDagger))
  S.fire("CHAT_MSG_LOOT", WON("Bob", I.spellDagger)) -- a second copy won on Greed
  eq(wins(), 1, "the Need is consumed by the first win")
end)

test("wins and Needs below the alert threshold are logged quietly; disabled logs nothing", function()
  party()
  ns.db.minSeverity = 3
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.leatherChest)) -- Low only for a warrior
  S.fire("CHAT_MSG_LOOT", WON("Bob", I.leatherChest))
  eq(#ns.db.log, 2, "Low Need and Low win both in the history")
  eq(ns.db.log[2].sev, 1, "Need logged as Low"); eq(ns.db.log[1].kind, "won", "win logged")
  eq(S.chatCount("rolled NEED"), 0, "no alert below the threshold")
  eq(S.chatCount(" won "), 0, "no win line below the threshold")
  eq(#S.banners, 0, "no banner"); eq(S.sounds, 0, "no sound")
  eq(wins(), 1, "one win")
  ns.db.log = {}
  ns.db.enabled = false
  S.fire("CHAT_MSG_LOOT", WON_NEED("Bob", 90, I.spellDagger))
  eq(wins(), 0, "disabled")
end)

-- Chat windows: a fake chat-window system for the AG Logs tab tests -----

-- General and Combat Log, plus `extra` windows { name, shown, docked }.
-- FCF_OpenNewWindow adds a window unless W.full is set.
local function chatSystem(extra)
  local W = { windows = {}, frames = {}, opened = {}, selected = {} }
  local function add(name, shown, docked)
    local i = #W.windows + 1
    W.windows[i] = { name = name, shown = shown, docked = docked }
    local fr = { lines = {}, cleared = 0 }
    function fr:AddMessage(m) self.lines[#self.lines + 1] = m end
    function fr:Clear() self.lines = {}; self.cleared = self.cleared + 1 end
    rawset(_G, "ChatFrame" .. i, fr)
    W.frames[i] = fr
    return fr, i
  end
  add("General", true, true); add("Combat Log", false, true)
  for _, w in ipairs(extra or {}) do add(w[1], w[2], w[3]) end
  rawset(_G, "NUM_CHAT_WINDOWS", 10)
  rawset(_G, "GetChatWindowInfo", function(i)
    local w = W.windows[i]
    if not w then return "", 14, 0, 0, 0, 0, false, false, false, false end
    return w.name, 14, 0, 0, 0, 0, w.shown, false, w.docked, false
  end)
  rawset(_G, "FCF_OpenNewWindow", function(name, noDefaultChannels)
    if W.full then return nil end
    W.opened[#W.opened + 1] = { name = name, noDefaultChannels = noDefaultChannels }
    return add(name, true, true)
  end)
  rawset(_G, "FCF_SelectDockFrame", function(f) W.selected[#W.selected + 1] = f end)
  return W
end

local function twoFlags()
  -- newest first, as Alert stores them
  ns.db.log[1] = { t = 2000, who = "Cy", item = "[Staff]", sev = 2, why = "probably not an upgrade" }
  ns.db.log[2] = { t = 1000, who = "Bob", item = "[Robe]", sev = 3, why = "Warrior can't use Cloth" }
end

test("history: Log opens a new 'AG Logs' tab with the whole log, oldest first", function()
  local W = chatSystem()
  twoFlags()
  SlashCmdList.ANTIGRIEF("history")
  eq(#W.opened, 1, "one window created")
  eq(W.opened[1].name, "AG Logs", "named AG Logs")
  eq(W.opened[1].noDefaultChannels, true, "no Say/Party/etc. channels in it")
  local tab = W.frames[3]
  -- header, [Robe] block (2 lines), blank, [Staff] block (2 lines)
  eq(#tab.lines, 6, "header + two drops")
  ok(tab.lines[1]:find("flag history: 2 drops, oldest first (keeps the last 50 entries)", 1, true), "header")
  ok(tab.lines[2]:find("[Robe]", 1, true), "oldest drop first")
  eq(tab.lines[3], "   |cffff4040- Bob is High: Warrior can't use Cloth|r", "Need line in High colour")
  eq(tab.lines[4], " ", "blank line between drops")
  ok(tab.lines[5]:find("[Staff]", 1, true), "newest drop last")
  eq(tab.lines[6], "   |cffff9930- Cy is Medium: probably not an upgrade|r", "Medium colour")
  eq(#S.chat, 0, "nothing in the main chat")
  -- new AntiGrief output now goes to the AG Logs tab
  party()
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.spellDagger))
  ok(tab.lines[7]:find("rolled NEED", 1, true), "live alerts land in AG Logs")
end)

test("history: an existing AG Logs tab is selected and redrawn, not duplicated", function()
  local W = chatSystem({ { " ag logs ", false, true } })
  twoFlags()
  SlashCmdList.ANTIGRIEF("history")
  SlashCmdList.ANTIGRIEF("history")
  eq(#W.opened, 0, "no new window")
  local tab = W.frames[3]
  eq(#W.selected, 2, "tab selected each time"); eq(W.selected[1], tab, "the AG Logs tab")
  eq(tab.cleared, 2, "cleared before each redraw")
  eq(#tab.lines, 6, "one copy of the history")
end)

test("history: a floating (undocked) AG Logs window is redrawn without dock selection", function()
  local W = chatSystem({ { "AG Logs", true, false } })
  twoFlags()
  SlashCmdList.ANTIGRIEF("history")
  eq(#W.selected, 0, "not dock-selected"); eq(#W.opened, 0, "not recreated")
  eq(#W.frames[3].lines, 6, "filled")
end)

test("history: a closed AG Logs window is skipped and a new tab opened", function()
  local W = chatSystem({ { "AG Logs", false, false } })
  SlashCmdList.ANTIGRIEF("history")
  eq(#W.opened, 1, "new tab")
  eq(W.frames[4].lines[1], "|cff40c0ffAntiGrief|r: flag history: no flags logged", "empty history message")
end)

test("history: no free chat window -> recent flags in the main chat instead", function()
  local W = chatSystem()
  W.full = true
  twoFlags()
  SlashCmdList.ANTIGRIEF("history")
  eq(S.chatCount("couldn't open an AG Logs chat tab"), 1, "explains")
  eq(S.chatCount("Warrior can't use Cloth"), 1, "still shows the flags")
  rawset(_G, "FCF_OpenNewWindow", function() error("boom") end)
  SlashCmdList.ANTIGRIEF("history")
  eq(S.chatCount("couldn't open an AG Logs chat tab"), 2, "an error falls back the same way")
end)

test("history: one block per drop - every Need under the item, the winner last", function()
  local W = chatSystem()
  local robe, staff = "|cffa335ee|Hitem:1003::::|h[Robe]|h|r", "|cff0070dd|Hitem:2000::::|h[Staff]|h|r"
  -- newest first, as stored; robe and staff dropped together, robe again 20 min later
  ns.db.log = {
    { t = 2300, kind = "won", who = "Zed", item = robe, sev = 2, why = "probably not an upgrade" },
    { t = 2290, who = "Zed", item = robe, sev = 2, why = "probably not an upgrade" },
    { t = 1010, kind = "won", who = "Bob-Realm", item = robe, sev = 3, why = "Warrior can't use Cloth" },
    { t = 1008, who = "Cy", item = staff, sev = 1, why = "Staff is unusual for a Rogue" },
    { t = 1005, who = "Ann", item = robe, sev = 1, why = "lower armor type" },
    { t = 1000, who = "Bob-Realm", item = robe, sev = 3, why = "Warrior can't use Cloth" },
  }
  SlashCmdList.ANTIGRIEF("history")
  local L = W.frames[3].lines
  ok(L[1]:find("3 drops", 1, true), "robe, staff, robe again = 3 drops: " .. L[1])
  ok(L[2]:find(robe, 1, true), "first drop: the robe link")
  eq(L[3], "   |cffff4040- Bob is High: Warrior can't use Cloth|r", "needers in roll order, short names")
  eq(L[4], "   |cffd0d070- Ann is Low: lower armor type|r", "Low colour")
  eq(L[5], "   |cffff66ff-- Bob won and is High for: Warrior can't use Cloth|r", "winner last, own colour")
  eq(L[6], " ")
  ok(L[7]:find(staff, 1, true), "second drop: staff")
  eq(L[8], "   |cffd0d070- Cy is Low: Staff is unusual for a Rogue|r")
  eq(L[9], " ")
  ok(L[10]:find(robe, 1, true), "a later robe is its own drop")
  eq(L[11], "   |cffff9930- Zed is Medium: probably not an upgrade|r")
  eq(L[12], "   |cffff66ff-- Zed won and is Medium for: probably not an upgrade|r")
  eq(#L, 12, "no extra lines")
  -- /ag log shows the same layout for the recent drops
  SlashCmdList.ANTIGRIEF("log")
  eq(L[#L], "      |cffff66ff-- Zed won and is Medium for: probably not an upgrade|r", "/ag log, indented once more")
end)

test("history: Clear Log History wipes the log and the AG Logs tab", function()
  local W = chatSystem()
  twoFlags()
  SlashCmdList.ANTIGRIEF("history")
  local tab = W.frames[3]
  SlashCmdList.ANTIGRIEF("clear")
  eq(#ns.db.log, 0, "log emptied")
  eq(tab.cleared, 2, "tab cleared (once by history, once by clear)")
  eq(#tab.lines, 1, "only the confirmation left")
  eq(tab.lines[1], "|cff40c0ffAntiGrief|r: log history cleared (2 entries removed)", "confirmation in the tab")
  SlashCmdList.ANTIGRIEF("clear")
  eq(tab.lines[#tab.lines], "|cff40c0ffAntiGrief|r: log history cleared (0 entries removed)", "plural on 0")
end)

-- Minimap button ----------------------------------------------------------

local function mmButton() return rawget(_G, "AntiGriefMinimapButton") end
local function near(a, b, what) ok(math.abs(a - b) < 0.01, ("%s: expected %s, got %s"):format(what, b, a)) end

test("minimap: black disc with red AG on the minimap, shown at 225 degrees by default", function()
  local b = mmButton()
  ok(b, "button created")
  eq(b.parent, Minimap, "parented to the minimap")
  ok(b:IsShown(), "shown")
  local text, disc
  for _, r in ipairs(b.regions) do
    if r.kind == "FontString" then text = r end
    if r.texture == 136467 then disc = r end
  end
  eq(text.text, "AG", "label")
  eq(text.textColor[1], 1, "red"); ok(text.textColor[2] < 0.3 and text.textColor[3] < 0.3, "red, not orange/pink")
  eq(disc.vertexColor[1] + disc.vertexColor[2] + disc.vertexColor[3], 0, "disc tinted black")
  eq(ns.db.minimapButton, true, "default on"); eq(ns.db.minimapAngle, 225, "default angle")
  local p = b.point
  eq(p[1], "CENTER"); eq(p[2], Minimap); eq(p[3], "CENTER")
  local r = 140 / 2 + 5
  near(p[4], math.cos(math.rad(225)) * r, "x"); near(p[5], math.sin(math.rad(225)) * r, "y")
end)

test("minimap: click opens a Log / Settings / Clear Log History / Feedback menu; each item does its job", function()
  local W = chatSystem()
  ns.db.log[1] = { t = 1, who = "Bob", item = "[Robe]", sev = 3, why = "Warrior can't use Cloth" }
  local b = mmButton()
  b.scripts.OnClick(b, "LeftButton")
  eq(#S.menus, 1, "menu opened")
  local m = S.menus[1]
  eq(m.owner, b, "anchored to the button")
  eq(m.items[1].kind, "title"); eq(m.items[1].text, "AntiGrief")
  eq(m.items[2].text, "Log"); eq(m.items[3].text, "Settings")
  eq(m.items[4].kind, "divider")
  eq(m.items[5].text, "Clear Log History", "Clear follows the divider")
  eq(m.items[6].text, "Feedback", "Feedback is below Clear Log History")
  eq(#m.items, 6, "four choices plus title and divider")
  m.items[2].fn()
  eq(#W.opened, 1, "Log opens the AG Logs tab")
  m.items[5].fn()
  eq(#ns.db.log, 0, "Clear Log History empties the log")
  m.items[6].fn()
  eq(#S.popups, 1, "Feedback opens the copy-link popup")
  if HAS_CONFIG then
    m.items[3].fn()
    eq(#S.cfg.opened, 1, "Settings opens the options page")
  end
  b.scripts.OnClick(b, "RightButton")
  eq(#S.menus, 2, "right-click opens the same menu")
end)

test("feedback: popup shows the Discord link selected and read-only; falls back to chat", function()
  local url = "https://discord.gg/XvsKbTEv7"
  SlashCmdList.ANTIGRIEF("feedback")
  eq(#S.popups, 1, "popup shown")
  local dialog = S.popups[1]
  local eb = dialog:GetEditBox()
  eq(eb.text, url, "edit box holds the invite")
  ok(eb.highlighted and eb.focused, "selected and focused, ready for Ctrl+C")
  eb:SetText(url .. "x")
  eq(eb.text, url, "typing can't change the link")
  StaticPopupDialogs.ANTIGRIEF_FEEDBACK.EditBoxOnEnterPressed(eb)
  eq(dialog.shown, false, "Enter closes it")
  SlashCmdList.ANTIGRIEF("discord")
  eq(#S.popups, 2, "/ag discord is an alias")
  StaticPopup_Show = nil
  SlashCmdList.ANTIGRIEF("feedback")
  eq(S.chatCount(url), 1, "no StaticPopup: link printed in chat")
end)

test("minimap: without the menu API, left-click opens settings and right-click the log", function()
  local b = mmButton()
  MenuUtil = nil
  b.scripts.OnClick(b, "RightButton")
  eq(S.chatCount("no flags logged"), 1, "right-click -> log (history; no chat windows here, so in main chat)")
  if HAS_CONFIG then
    b.scripts.OnClick(b, "LeftButton")
    eq(#S.cfg.opened, 1, "left-click -> settings")
  end
  MenuUtil = { CreateContextMenu = function() error("menu broke") end }
  b.scripts.OnClick(b, "RightButton")
  eq(S.chatCount("no flags logged"), 2, "menu error -> same fallback")
end)

test("minimap: dragging moves it round the edge and saves the angle", function()
  local b = mmButton()
  b.scripts.OnDragStart(b)
  ok(b.scripts.OnUpdate, "OnUpdate only while dragging")
  S.cursor = { 600, 400 } -- due east of the minimap centre
  b.scripts.OnUpdate(b)
  near(ns.db.minimapAngle, 0, "east = 0")
  near(b.point[4], 75, "x"); near(b.point[5], 0, "y")
  S.cursor = { 500, 300 } -- due south
  b.scripts.OnUpdate(b)
  near(ns.db.minimapAngle, 270, "south = 270 (0-360, never negative)")
  b.scripts.OnDragStop(b)
  eq(b.scripts.OnUpdate, nil, "OnUpdate cleared on drop")
end)

test("minimap: square minimap pushes the button to the corner", function()
  rawset(_G, "GetMinimapShape", function() return "SQUARE" end)
  ns.db.minimapAngle = 45
  ns.MinimapButton.Refresh()
  local p = mmButton().point
  local corner = (math.sqrt(2 * 75 * 75) - 10) * math.cos(math.rad(45)) -- LibDBIcon formula, ~67.9
  near(p[4], corner, "x pushed toward the corner"); near(p[5], corner, "y pushed toward the corner")
  ok(p[4] > 75 * math.cos(math.rad(45)) + 1, "further out than on a round minimap")
  rawset(_G, "GetMinimapShape", nil)
end)

test("minimap: /ag minimap and the options checkbox hide and show it", function()
  local b = mmButton()
  SlashCmdList.ANTIGRIEF("minimap")
  ok(not b:IsShown(), "hidden"); eq(ns.db.minimapButton, false, "saved")
  SlashCmdList.ANTIGRIEF("minimap")
  ok(b:IsShown(), "shown again")
  eq(S.chatCount("/ag sound | screen | announce | pawn | minimap - toggle"), 0, "help not printed by toggling")
  -- The slash path must work on its own, without the options page relaying it
  local cfg = ns.Config
  ns.Config = nil
  SlashCmdList.ANTIGRIEF("minimap")
  ok(not b:IsShown(), "hidden without the options page")
  SlashCmdList.ANTIGRIEF("minimap")
  ok(b:IsShown(), "shown without the options page")
  ns.Config = cfg
  if HAS_CONFIG then
    local setting = S.cfg.settings.ANTIGRIEF_minimapButton
    ok(setting, "options checkbox exists")
    setting:SetValue(false)
    ok(not b:IsShown(), "checkbox off hides it")
    setting:SetValue(true)
    ok(b:IsShown(), "checkbox on shows it")
  end
end)

test("minimap: saved angle is normalised; hidden setting survives reload", function()
  reloadWith({ minimapAngle = 400, minimapButton = false })
  eq(ns.db.minimapAngle, 40, "400 -> 40")
  ok(not mmButton():IsShown(), "stays hidden after reload")
  reloadWith({ minimapAngle = 0 / 0 })
  eq(ns.db.minimapAngle, 225, "NaN -> default")
  reloadWith({ minimapAngle = -90 })
  eq(ns.db.minimapAngle, 270, "-90 -> 270")
  reloadWith({ minimapAngle = "x" })
  eq(ns.db.minimapAngle, 225, "wrong type -> default")
end)

test("minimap: tooltip shows status and how to use it", function()
  local b = mmButton()
  b.scripts.OnEnter(b)
  eq(GameTooltip.lines[1], "AntiGrief", "title")
  local all = table.concat(GameTooltip.lines, "\n")
  ok(all:find("alerts at Medium+", 1, true), "status line")
  ok(all:find("Click: Log or Settings", 1, true), "usage line")
  ok(GameTooltip.shown, "shown")
  b.scripts.OnLeave(b)
  ok(not GameTooltip.shown, "hidden on leave")
end)

test("minimap: no minimap frame (UI replacement) -> no button, no error, addon works", function()
  S = assert(loadfile(path("tests/wowstub.lua")))()
  Minimap = nil
  loadAddon()
  S.fire("ADDON_LOADED", ADDON)
  S.fire("PLAYER_ENTERING_WORLD")
  eq(rawget(_G, "AntiGriefMinimapButton"), nil, "no button")
  eq(S.chatCount("minimap button error"), 0, "no error")
  items(); party()
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.spellDagger))
  eq(S.chatCount("rolled NEED"), 1, "alerts still work")
end)

---------------------------------------------------------------------------
-- Run
---------------------------------------------------------------------------
local passed, failed = 0, 0
for _, t in ipairs(tests) do
  local good, err = xpcall(function()
    fresh()
    items()
    t.fn()
  end, debug.traceback)
  if good then
    passed = passed + 1
    print("PASS  " .. t.name)
  else
    failed = failed + 1
    print("FAIL  " .. t.name)
    print("      " .. tostring(err):gsub("\n", "\n      "))
  end
end
print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
