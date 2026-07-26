-- inventory.lua
-- Deposits carried items into the chest wall (x=0), keeping tracked resources in
-- the tracked chest up to their target and dumping everything else into the
-- overflow chests. Starts and ends at the charger (stasis point), and moves via
-- the same predefined turn/forward sequences the other states use.

local C = require("common")

local robot = C.robot
local inv = C.inv
local sides = C.sides
local pos = C.pos

local INVENTORY_SIZE = C.INVENTORY_SIZE or 64

-- Chest wall geometry. After C.gotoChestFromStasis() the robot stands at the
-- tracked-chest access cell (1,1,0) facing -X, looking at the chest at (0,1,0).
-- Chests sit at x=0 for each z in CHEST_ZS, stacked CHEST_LEVELS high (y=1..6).
local CHEST_ZS = { 0, 1, 3, 4, 6, 7 }
local CHEST_LEVELS = C.CHEST_STACK_HEIGHT   -- 6

-- Reserve cobble slots (45-48) are kept for pillaring during mining/farming and
-- must NOT be emptied into the chests during inventory. Build a lookup set.
local RESERVE = {}
for _, s in ipairs(C.RESERVE_COBBLE_SLOTS or {}) do RESERVE[s] = true end

-- ---------------------------------------------------------------------------
-- Predefined movement within the chest wall.
-- The robot always faces -X at a chest access cell. To move along the wall we
-- turn to face the z-axis, step, and turn back to -X. To change level we go
-- straight up or down. These are fixed turn/forward sequences, composed from
-- the robot's current tracked position.
-- ---------------------------------------------------------------------------

-- Move from the current access cell to (ACCESS_X, level, z), ending facing -X.
local function gotoChestCell(z, level)
  -- Adjust Z first (robot faces -X; turn onto the z-axis, step, turn back).
  if pos.z < z then
    C.turnLeft()                 -- -X -> +Z
    for _ = 1, (z - pos.z) do C.moveForward() end
    C.turnRight()                -- +Z -> -X
  elseif pos.z > z then
    C.turnRight()                -- -X -> -Z
    for _ = 1, (pos.z - z) do C.moveForward() end
    C.turnLeft()                 -- -Z -> -X
  end
  -- Adjust level.
  while pos.y < level do
    if not C.moveUp() then break end
  end
  while pos.y > level do
    if not C.moveDown() then break end
  end
end

-- ---------------------------------------------------------------------------
-- Deposits.
-- ---------------------------------------------------------------------------

-- Deposit tracked resources into the tracked chest (0,1,0), each up to its
-- target amount. Scans all 48 internal slots. Tracked resources are matched by
-- id OR display label (via C.specFor), so items referenced only by label --
-- cactus, raw circuit boards, and the smelt outputs (Iron/Gold Ingot, Glass,
-- Cactus Green, PCB, ...) -- are kept in the tracked chest rather than dumped
-- into overflow, where the furnace and crafting states would never find them.
-- The chest's current contents are counted ONCE up front, per tracked entry, and
-- a running stored-count is kept as items drop instead of re-scanning.
local function depositTrackedChest()
  gotoChestCell(C.TRACKED_CHEST.z, C.TRACKED_CHEST.y)

  local tracked = C.TRACKED_RESOURCES
  local specs = {}
  local stored = {}
  for ti, r in ipairs(tracked) do
    specs[ti] = C.specFor(r.name)
    stored[ti] = 0
  end

  -- Count what's already in the chest, attributing each stack to the first
  -- tracked entry it matches.
  local size = inv.getInventorySize(sides.front)
  if size then
    for slot = 1, size do
      local st = inv.getStackInSlot(sides.front, slot)
      if st and st.size then
        for ti = 1, #tracked do
          if C.matchesSpec(st, specs[ti]) then
            stored[ti] = stored[ti] + st.size
            break
          end
        end
      end
    end
  end

  for i = 1, INVENTORY_SIZE do
    if not RESERVE[i] then
      local stack = inv.getStackInInternalSlot(i)
      if stack and stack.name and stack.size and stack.size > 0 then
        for ti = 1, #tracked do
          if C.matchesSpec(stack, specs[ti]) then
            local room = (tracked[ti].target or 0) - stored[ti]
            if room > 0 then
              local toDrop = math.min(room, stack.size)
              robot.select(i)
              robot.drop(toDrop)
              stored[ti] = stored[ti] + toDrop
            end
            break
          end
        end
      end
    end
  end
end

-- Any non-reserve slot still holding items? (Reserve cobble stays for pillaring.)
local function hasStorableItems()
  for i = 1, INVENTORY_SIZE do
    if not RESERVE[i] then
      local stack = inv.getStackInInternalSlot(i)
      if stack and stack.size and stack.size > 0 then
        return true
      end
    end
  end
  return false
end

-- Dump every non-reserve slot into the chest in front. The tracked chest already
-- holds each tracked resource up to its target; everything left -- excess tracked
-- resources AND untracked items -- flows into the overflow chests here. Whatever
-- doesn't fit (chest full) simply stays put, so the robot's inventory is only used
-- once the chests can no longer hold the resource.
local function dumpAllHere()
  for i = 1, INVENTORY_SIZE do
    if not RESERVE[i] then
      local stack = inv.getStackInInternalSlot(i)
      if stack and stack.size and stack.size > 0 then
        robot.select(i)
        robot.drop()
      end
    end
  end
end

-- Deposit leftovers into the overflow chests, one access cell at a time, until
-- nothing storable remains (or the chests fill up). Skips the tracked chest cell.
local function depositOverflow()
  for _, z in ipairs(CHEST_ZS) do
    for level = 1, CHEST_LEVELS do
      if not hasStorableItems() then return end
      local isTrackedCell =
        (z == C.TRACKED_CHEST.z and level == C.TRACKED_CHEST.y)
      if not isTrackedCell then
        gotoChestCell(z, level)
        dumpAllHere()
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Reserve cobble top-up.
-- ---------------------------------------------------------------------------

local COBBLE = C.COBBLE_NAME

-- Is the chest in front completely empty (no items in any slot)? A missing chest
-- (no inventory in front) is NOT treated as empty -- only a real, drained chest.
local function frontChestEmpty()
  local size = inv.getInventorySize(sides.front)
  if not size then return false end
  for cs = 1, size do
    local st = inv.getStackInSlot(sides.front, cs)
    if st and st.size and st.size > 0 then return false end
  end
  return true
end

-- Reserve slots must hold cobblestone only. If something else has ended up in one
-- (e.g. from an arrangement eviction), move it into a normal slot so the deposit
-- flow stores it -- or, failing that, straight into the chest in front -- leaving
-- the reserve slot free for cobble.
local function clearReserveOfNonCobble()
  for _, rs in ipairs(C.RESERVE_COBBLE_SLOTS or {}) do
    local st = inv.getStackInInternalSlot(rs)
    if st and st.size and st.size > 0 and st.name ~= COBBLE then
      robot.select(rs)
      local dest = C.freeSlot()
      if dest then
        robot.transferTo(dest)
      else
        robot.drop()
      end
    end
  end
end

-- Pull cobblestone from the chest in front into the reserve slots, up to full.
local function suckCobbleFromFront()
  local size = inv.getInventorySize(sides.front)
  if not size then return end
  for _, rs in ipairs(C.RESERVE_COBBLE_SLOTS or {}) do
    local st = inv.getStackInInternalSlot(rs)
    local have = (st and st.name == COBBLE and st.size) or 0
    for cs = 1, size do
      if have >= 64 then break end
      local cst = inv.getStackInSlot(sides.front, cs)
      if cst and cst.name == COBBLE and cst.size and cst.size > 0 then
        robot.select(rs)
        inv.suckFromSlot(sides.front, cs, 64 - have)
        local st2 = inv.getStackInInternalSlot(rs)
        have = (st2 and st2.size) or have
      end
    end
  end
end

-- Top the pillaring reserve back up from the overflow chests (the carried-cobble
-- top-up runs first, in inventory(), before that cobble is dumped). Only if the
-- reserve isn't already full, and STOP as soon as an empty chest is reached (no
-- point walking a wall of drained chests).
local function refillReserveFromOverflow()
  if C.reserveCobbleDeficit() <= 0 then return end

  for _, z in ipairs(CHEST_ZS) do
    for level = 1, CHEST_LEVELS do
      local isTrackedCell =
        (z == C.TRACKED_CHEST.z and level == C.TRACKED_CHEST.y)
      if not isTrackedCell then
        gotoChestCell(z, level)
        if frontChestEmpty() then return end     -- hit an empty chest: stop
        suckCobbleFromFront()
        if C.reserveCobbleDeficit() <= 0 then return end   -- reserve full: done
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- State entry.
-- ---------------------------------------------------------------------------

local function inventory()
  -- Charger (stasis) -> chest wall via the predefined sequence.
  C.gotoChestFromStasis()

  clearReserveOfNonCobble()       -- reserve slots hold cobble only
  depositTrackedChest()
  C.topUpReserveFromInventory()   -- reserve first, from cobble still carried
  depositOverflow()               -- then everything else flows to overflow chests
  refillReserveFromOverflow()     -- top up any remaining reserve from those chests

  -- Return to the tracked-chest access cell, then back to the charger.
  gotoChestCell(C.TRACKED_CHEST.z, C.TRACKED_CHEST.y)
  C.gotoStasisFromChest()

  return "stasis"
end

return inventory
