-- AntiGrief: throttled inspect queue that caches every group member's gear

local _, ns = ...
local D = ns.Data
local Inspect = {}
ns.Inspect = Inspect

local REQUEST_GAP = 1.5   -- seconds between inspect requests
local TIMEOUT     = 4     -- give up on a request after this long
local STALE_AFTER = 600   -- re-inspect cached gear older than this
local RETRY_AFTER = 8     -- wait before retrying someone out of range
local LINK_RETRY  = 0.6   -- re-read slots whose links weren't cached yet

Inspect.cache = {}        -- guid -> { guid, name, class, level, spec, items = { [slot] = link }, time }
local queue, queued, notBefore = {}, {}, {}
-- The request in flight: { guid, unit, t, retry }. While `retry` is set we
-- are waiting to re-read uncached links and must not start another inspect.
local pending
local lastRequest = 0

-- UnitGUID, treating a secret value as unknown (it can't be compared or
-- used as a table key safely)
local function GUID(unit)
  local g = UnitGUID(unit)
  if g == nil or (issecretvalue and issecretvalue(g)) then return nil end
  return g
end
ns.GUID = GUID

function ns.GroupUnits()
  local units = {}
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
  elseif IsInGroup() then
    units[1] = "player"
    for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
  end
  return units
end

function ns.UnitForGUID(guid)
  if not guid then return nil end
  for _, u in ipairs(ns.GroupUnits()) do
    if GUID(u) == guid then return u end
  end
end

-- Always returns a fresh table (callers may add fields to it)
local function Basic(unit)
  local _, class = UnitClass(unit)
  -- own spec is always readable; others' comes from the inspect
  local spec = UnitIsUnit(unit, "player") and D.PlayerSpecID() or nil
  return {
    guid  = GUID(unit),
    name  = GetUnitName(unit, true) or UnitName(unit),
    class = class,
    level = UnitLevel(unit),
    spec  = spec,
  }
end

-- Everything known about a unit: class/level always, gear if scanned.
-- Returns a new table each call; `items` is shared with the cache, so
-- callers must replace it rather than mutate it.
function Inspect.Who(unit)
  local guid = GUID(unit)
  if not guid then return nil end
  local who = Basic(unit)
  local c = Inspect.cache[guid]
  if c then
    who.items, who.scanned = c.items, c.time
    who.spec = who.spec or c.spec
  end
  return who
end

function Inspect.Queue(guid, force)
  if not guid or queued[guid] or guid == GUID("player") then return end
  local c = Inspect.cache[guid]
  if c and not force and (GetTime() - c.time) < STALE_AFTER then return end
  queued[guid] = true
  queue[#queue + 1] = guid
end

function Inspect.QueueGroup(force)
  for _, u in ipairs(ns.GroupUnits()) do
    if UnitIsPlayer(u) and not UnitIsUnit(u, "player") then Inspect.Queue(GUID(u), force) end
  end
end

local function BlizzardInspectOpen()
  return (InspectFrame and InspectFrame:IsShown()) and true or false
end

-- Remove keys of `t` not in `keep` without mutating `t` during pairs()
local function DropMissing(t, keep)
  local drop = {}
  for g in pairs(t) do
    if not keep[g] then drop[#drop + 1] = g end
  end
  for i = 1, #drop do t[drop[i]] = nil end
end

function Inspect.Prune()
  local keep = {}
  for _, u in ipairs(ns.GroupUnits()) do
    local g = GUID(u)
    if g then keep[g] = true end
  end
  DropMissing(Inspect.cache, keep)
  DropMissing(notBefore, keep)
  for i = #queue, 1, -1 do
    local g = queue[i]
    if not keep[g] then queued[g] = nil; table.remove(queue, i) end
  end
  if pending and not keep[pending.guid] then
    pending = nil
    if not BlizzardInspectOpen() then ClearInspectPlayer() end
  end
end

function Inspect.Status()
  local scanned, total = 0, 0
  for _, u in ipairs(ns.GroupUnits()) do
    if UnitIsPlayer(u) and not UnitIsUnit(u, "player") then
      total = total + 1
      local g = GUID(u)
      if g and Inspect.cache[g] then scanned = scanned + 1 end
    end
  end
  return scanned, total, #queue
end

local function InRange(unit)
  if not CheckInteractDistance then return true end
  local ok, res = pcall(CheckInteractDistance, unit, 1)
  if ok and res ~= nil then return res and true or false end
  return true -- can't tell; let the server decide
end

local function ReadItems(unit, entry)
  local missing = 0
  for _, slot in ipairs(D.INSPECT_SLOTS) do
    local link = GetInventoryItemLink(unit, slot)
    if link then
      entry.items[slot] = link
    elseif GetInventoryItemID and GetInventoryItemID(unit, slot) then
      missing = missing + 1 -- item exists, link not cached yet
    end
  end
  return missing
end

function Inspect.Pump()
  local now = GetTime()
  if pending then
    if now - pending.t < TIMEOUT then return end
    -- No answer in time: retry later (a timed-out link re-read needs no retry,
    -- the entry is already cached)
    local g, wasRetry = pending.guid, pending.retry
    pending = nil
    if not wasRetry then
      notBefore[g] = now + RETRY_AFTER
      Inspect.Queue(g, true)
    end
  end
  if #queue == 0 or (now - lastRequest) < REQUEST_GAP then return end
  if InCombatLockdown() or BlizzardInspectOpen() then return end

  -- Take the first entry whose cooldown has passed. We return right after
  -- removing it, so removing inside the loop is safe.
  for i = 1, #queue do
    local guid = queue[i]
    if (notBefore[guid] or 0) <= now then
      table.remove(queue, i)
      queued[guid] = nil
      local unit = ns.UnitForGUID(guid)
      if unit and UnitIsConnected(unit) and CanInspect(unit) and InRange(unit) then
        pending = { guid = guid, unit = unit, t = now }
        lastRequest = now
        NotifyInspect(unit)
      elseif unit then
        notBefore[guid] = now + RETRY_AFTER -- back of the queue, cooldown
        Inspect.Queue(guid, true)
      else
        notBefore[guid] = nil -- left the group
      end
      return
    end
  end
end

function Inspect.OnInspectReady(guid)
  if issecretvalue and issecretvalue(guid) then return end
  if not pending or pending.retry or pending.guid ~= guid then return end
  local unit = pending.unit
  if GUID(unit) ~= guid then unit = ns.UnitForGUID(guid) end
  if not unit then pending = nil; return end

  local entry = Basic(unit)
  entry.items, entry.time = {}, GetTime()
  entry.spec = D.InspectSpecID(unit) -- nil when unknown (0, secret, API missing)
  local missing = ReadItems(unit, entry)
  Inspect.cache[guid] = entry
  notBefore[guid] = nil

  if missing > 0 and C_Timer and C_Timer.After then
    -- Hold the queue until the re-read is done, so a new NotifyInspect
    -- doesn't replace this player's inspect data under us.
    local hold = { guid = guid, unit = unit, t = GetTime(), retry = true }
    pending = hold
    C_Timer.After(LINK_RETRY, function()
      if pending ~= hold then return end -- timed out or pruned meanwhile
      pending = nil
      if Inspect.cache[guid] == entry and GUID(unit) == guid then ReadItems(unit, entry) end
      if not BlizzardInspectOpen() then ClearInspectPlayer() end
    end)
  else
    pending = nil
    if not BlizzardInspectOpen() then ClearInspectPlayer() end
  end
end
