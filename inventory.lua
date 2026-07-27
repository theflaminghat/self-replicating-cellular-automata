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
  local tracked = C.TRACKED_RESOURCES
  local specs = {}
  local stored = {}          -- cumulative across all 3 target chests
  for ti, r in ipairs(tracked) do
    specs[ti] = C.specFor(r.name)
    stored[ti] = 0
  end

  gotoChestCell(C.TRACKED_CHEST.z, C.TRACKED_CHEST.y)  -- tracked column, level 1

  -- Visit each of the 3 target chests. At each: count its existing contents into the
  -- cumulative `stored`, then deposit from inventory up to each resource's remaining
  -- target. A chest that fills takes what it can (drop() moves fewer); the rest rides
  -- along to the next chest on the next iteration.
  C.forEachTrackedChest(function()
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
                local before = stack.size
                robot.select(i)
                robot.drop(math.min(room, before))
                -- drop() can move fewer than asked when the chest fills up. Count what
                -- ACTUALLY left the slot so `stored` -- and the keep budget below --
                -- reflect the chests' real contents, not the request.
                local after = inv.getStackInInternalSlot(i)
                stored[ti] = stored[ti] + (before - ((after and after.size) or 0))
              end
              break
            end
          end
        end
      end
    end
  end)

  -- Keep budget: for each tracked resource, how much to hold back in inventory
  -- because the chests couldn't take the full target (target minus what actually
  -- landed). A resource only overflows what it has BEYOND this, so materials still
  -- needed for replication ride along in inventory instead of the overflow wall.
  local keep = {}
  for ti = 1, #tracked do
    keep[ti] = math.max(0, (tracked[ti].target or 0) - stored[ti])
  end
  return specs, keep
end

-- A collected offspring robot waiting to be dispatched. It must NOT be dumped into
-- a chest -- dispatchStep holds it in inventory (sometimes across several weave
-- passes while the last build materials are crafted), and depositing it here would
-- strand the finished offspring in the overflow. Same detection dispatch uses.
local function isOffspringRobot(stack)
  return stack and stack.size and stack.size > 0
    and (stack.name == "opencomputers:robot"
         or (stack.label and string.find(stack.label, "Robot", 1, true)))
end

-- Index of the first tracked entry `stack` matches, or nil (untracked).
local function matchTracked(stack, specs)
  for ti = 1, #specs do
    if C.matchesSpec(stack, specs[ti]) then return ti end
  end
  return nil
end

-- Is there anything the robot should OVERFLOW given the keep budget? That's any
-- untracked item, or a tracked resource in excess of its keep budget (the amount
-- reserved in inventory to reach its replication target). Tracked resources within
-- budget -- and a waiting offspring robot -- are not overflow-able, so when only
-- those remain this returns false and depositOverflow skips the chest-wall walk
-- entirely. `keptSoFar` mirrors what dumpAllHere would retain as it scans.
local function overflowable(specs, keep)
  local keptSoFar = {}
  for i = 1, INVENTORY_SIZE do
    if not RESERVE[i] then
      local stack = inv.getStackInInternalSlot(i)
      if stack and stack.size and stack.size > 0 and not isOffspringRobot(stack) then
        local ti = matchTracked(stack, specs)
        if not ti then
          return true                                   -- untracked: overflow it
        end
        local allowed = math.max(0, (keep[ti] or 0) - (keptSoFar[ti] or 0))
        local keepAmt = math.min(stack.size, allowed)
        keptSoFar[ti] = (keptSoFar[ti] or 0) + keepAmt
        if stack.size > keepAmt then
          return true                                   -- tracked beyond budget
        end
      end
    end
  end
  return false
end

-- Dump the OVERFLOW portion of each non-reserve slot into the chest in front:
-- untracked items entirely, and tracked resources only beyond their keep budget.
-- Tracked resources still needed for replication (within budget) and a waiting
-- offspring robot are left in inventory. Whatever doesn't fit (chest full) simply
-- stays put, so inventory holds a resource only once the chests can't take it.
local function dumpAllHere(specs, keep)
  local keptSoFar = {}
  for i = 1, INVENTORY_SIZE do
    if not RESERVE[i] then
      local stack = inv.getStackInInternalSlot(i)
      if stack and stack.size and stack.size > 0 and not isOffspringRobot(stack) then
        local ti = matchTracked(stack, specs)
        local dropAmt
        if ti then
          local allowed = math.max(0, (keep[ti] or 0) - (keptSoFar[ti] or 0))
          local keepAmt = math.min(stack.size, allowed)
          keptSoFar[ti] = (keptSoFar[ti] or 0) + keepAmt
          dropAmt = stack.size - keepAmt
        else
          dropAmt = stack.size
        end
        if dropAmt > 0 then
          robot.select(i)
          robot.drop(dropAmt)
        end
      end
    end
  end
end

-- Deposit overflow into the overflow chests, one access cell at a time, until
-- nothing overflow-able remains (or the chests fill up). Skips the tracked chest
-- cell. In steady state -- chest holding the full target, no untracked junk --
-- overflowable() is false up front and the robot never walks the wall at all.
local function depositOverflow(specs, keep)
  for _, z in ipairs(CHEST_ZS) do
    for level = 1, CHEST_LEVELS do
      if not overflowable(specs, keep) then return end
      local isTrackedCell = C.isTrackedChestCell(z, level)
      if not isTrackedCell then
        gotoChestCell(z, level)
        dumpAllHere(specs, keep)
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
      local isTrackedCell = C.isTrackedChestCell(z, level)
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

  clearReserveOfNonCobble()          -- reserve slots hold cobble only
  local specs, keep = depositTrackedChest()  -- fill tracked chest; get keep budget
  C.topUpReserveFromInventory()      -- reserve first, from cobble still carried
  depositOverflow(specs, keep)       -- only the EXCESS beyond target overflows;
                                     -- target resources ride along in inventory
  refillReserveFromOverflow()        -- top up any remaining reserve from those chests

  -- Return to the tracked-chest access cell, then back to the charger.
  gotoChestCell(C.TRACKED_CHEST.z, C.TRACKED_CHEST.y)
  C.gotoStasisFromChest()

  return "stasis"
end

return inventory
