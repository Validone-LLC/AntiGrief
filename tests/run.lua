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
local TOC = { "Data.lua", "Inspect.lua", "Rules.lua", "Pawn.lua", "AntiGrief.lua" }

local S, ns

local function fresh()
  S = assert(loadfile(path("tests/wowstub.lua")))()
  ns = {}
  for _, f in ipairs(TOC) do
    local chunk, err = loadfile(path(f))
    if not chunk then error("load " .. f .. ": " .. tostring(err), 0) end
    chunk(ADDON, ns)
  end
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

test("uncached item: retried, then alerts once cached", function()
  party()
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.uncachedPlate))
  eq(S.chatCount("rolled NEED"), 0, "no alert before cache")
  ok(S.loadRequests >= 1, "requested item data")
  S.advance(1)
  eq(S.chatCount("rolled NEED"), 0, "warrior fits plate")
  S.units.party1.class = "MAGE"
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.uncachedPlate))
  eq(S.chatCount("rolled NEED"), 1, "mage on cached plate")
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

test("drop hints list who an item fits", function()
  party()
  ns.db.hints = true
  S.rolls[7] = I.robe58
  S.fire("START_LOOT_ROLL", 7)
  eq(S.chatCount("fits: Me"), 1, "hint line")
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
  cmd("margin -1"); eq(ns.db.upgradeMargin, 5, "negative margin rejected")
  cmd("sound"); eq(ns.db.sound, false, "sound toggled")
  cmd("gear"); ok(S.chatCount("usage: /ag gear") == 1, "gear usage")
  cmd("gear nobody"); ok(S.chatCount("no group member named nobody") == 1, "gear unknown")
  cmd("gear bob"); ok(S.chatCount("hasn't been scanned yet") == 1, "gear unscanned (case-insensitive)")
  cmd("test look at " .. I.plateChest .. " please")
  ok(S.chatCount("Me: ") == 1, "test verdict for me")
  cmd("test nothing"); ok(S.chatCount("usage: /ag test") == 1, "test usage")
  cmd("off"); eq(ns.db.enabled, false, "off")
  cmd("on"); eq(ns.db.enabled, true, "on")
  cmd("log"); ok(S.chatCount("no flags logged") == 1, "empty log")
  ns.db.minSeverity = 2
  S.fire("CHAT_MSG_LOOT", NEED("Bob", I.spellDagger))
  cmd("log"); ok(S.chatCount("recent flags:") == 1, "log")
  cmd("clear"); eq(#ns.db.log, 0, "cleared")
end)

test("/ag test solo and with a nameless member doesn't error", function()
  S.SetGroup({ player = { guid = GUID.me, name = "Me", class = "MAGE", level = 60, items = {} } }, nil)
  SlashCmdList.ANTIGRIEF("test " .. I.plateChest)
  ok(S.chatCount("Me: ") == 1, "solo verdict")
  party({ party2 = { guid = GUID.zap, name = "Zap", noName = true, class = "MAGE", level = 60 } })
  SlashCmdList.ANTIGRIEF("test " .. I.plateChest)
  ok(S.chatCount("?: ") == 1, "nameless member shown as ?")
end)

test("saved settings: defaults merged, user values kept, corrupt values fixed", function()
  -- reload with an existing DB
  S = assert(loadfile(path("tests/wowstub.lua")))()
  AntiGriefDB = { sound = false, minSeverity = 7, upgradeMargin = "x", log = "bad" }
  ns = {}
  for _, f in ipairs(TOC) do assert(loadfile(path(f)))(ADDON, ns) end
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
