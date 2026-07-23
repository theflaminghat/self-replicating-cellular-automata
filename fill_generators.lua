local C = require("common")

local robot = C.robot
local pos = C.pos
local inv = C.inv
local sides = C.sides
local batteryLevel = C.batteryLevel

-- Match charcoal by internal id OR display label. Packs vary: the id may be
-- "minecraft:charcoal", a modded string, or the item may only be reliably
-- identified by its in-game name ("Charcoal"). Checking both is robust.
local CHARCOAL_NAME = "minecraft:charcoal"
local CHARCOAL_LABEL = "Charcoal"

local function isCharcoal(st)
  if not st then return false end
  if st.name == CHARCOAL_NAME then return true end
  if st.label == CHARCOAL_LABEL then return true end
  return false
end
local FETCH_SLOT = 22

local function fwd(n)
  for _ = 1, n do C.moveForward() end
end

local function facingInventory()
  local ok, size = pcall(inv.getInventorySize, sides.front)
  if ok and size then return size end
  return nil
end

local function heldCharcoal()
  local total = 0
  for s = 1, (C.INVENTORY_SIZE or 32) do
    local ok, st = pcall(inv.getStackInInternalSlot, s)
    if ok and isCharcoal(st) and st.size then
      total = total + st.size
    end
  end
  return total
end

local function findHeldSlot()
  for s = 1, (C.INVENTORY_SIZE or 32) do
    local ok, st = pcall(inv.getStackInInternalSlot, s)
    if ok and isCharcoal(st) and st.size and st.size > 0 then
      return s
    end
  end
  return nil
end

local function firstEmptySlot()
  for s = 1, (C.INVENTORY_SIZE or 32) do
    local isReserve = false
    for _, r in ipairs(C.RESERVE_COBBLE_SLOTS or {}) do
      if r == s then isReserve = true break end
    end
    if not isReserve then
      local ok, st = pcall(inv.getStackInInternalSlot, s)
      if ok and not st then
        return s
      end
    end
  end
  return nil
end

local function pullCharcoal(count)
  local size = facingInventory()
  if not size then return 0 end
  local got = 0
  for s = 1, size do
    if got >= count then break end
    local ok, st = pcall(inv.getStackInSlot, sides.front, s)
    if ok and isCharcoal(st) and st.size and st.size > 0 then
      local take = math.min(count - got, st.size)
      -- suckFromSlot deposits into the SELECTED slot; if that slot is occupied
      -- by something else the transfer silently fails. Select a genuinely empty
      -- slot each time (falling back to one already holding charcoal so stacks
      -- merge) so there is always somewhere for the items to land.
      local dest = firstEmptySlot() or findHeldSlot() or FETCH_SLOT
      robot.select(dest)
      if inv.suckFromSlot(sides.front, s, take) then
        got = got + take
      end
    end
  end
  return got
end

-- Drop up to `count` charcoal into the generator directly in front.
local function fuelFront(count)
  -- Compare against what we held when we started, so this works whether the
  -- robot is carrying exactly `count` or a larger pooled stack for both
  -- generators. (moved = held_before - held_now.)
  local before = heldCharcoal()
  local moved = 0
  while moved < count do
    local remainingHeld = heldCharcoal()
    if remainingHeld == 0 then break end
    local from = findHeldSlot()
    if not from then break end
    robot.select(from)
    local want = count - moved
    -- Use robot.drop into the block in front. Unlike dropIntoSlot it doesn't
    -- target a specific slot; the generator takes the charcoal as fuel.
    local ok, done = pcall(robot.drop, want)
    if not (ok and done) then break end
    local after = heldCharcoal()
    local justMoved = remainingHeld - after
    if justMoved <= 0 then break end
    moved = before - after
  end
  return moved
end

local function fill_generators()
  if batteryLevel() < 0.25 then
    return "returning"
  end

  C.lastGeneratorError = nil
  C.lastGeneratorReport = { fueled = { 0, 0 } }

  local perGen = C.GENERATOR_TARGET or 64

  -- Stasis -> chest: right, forward 3, left, forward 3, right.
  C.turnRight()
  fwd(3)
  C.turnLeft()
  fwd(3)
  C.turnRight()

  if not facingInventory() then
    C.lastGeneratorError = "not facing the tracked chest"
    -- best-effort return
    C.turnRight()
    fwd(3)
    C.turnRight()
    fwd(3)
    C.turnRight()
    return "stasis"
  end

  -- Take enough charcoal for both generators.
  local need = perGen * 2 - heldCharcoal()
  if need > 0 then
    pullCharcoal(need)
  end
  local haveCharcoal = heldCharcoal()
  if haveCharcoal == 0 then
    C.lastGeneratorError = "no charcoal in chest"
  end

  -- Split what we actually have evenly between the two generators, capped at
  -- the per-generator target. The first generator gets the rounded-up half so
  -- an odd amount does not strand one piece.
  local firstShare = math.min(perGen, math.ceil(haveCharcoal / 2))
  local secondShare = math.min(perGen, haveCharcoal - firstShare)

  -- Chest (1,0 facing -X) -> face the first generator (5,0):
  -- turn around, forward 3  => at (4,0) facing +X, generator (5,0) in front.
  C.turnAround()
  fwd(3)
  C.lastGeneratorReport.fueled[1] = fuelFront(firstShare)

  -- Step over the first generator to reach the far side of the second:
  -- up, forward 3, down  => at (7,0), then turn around to face (6,0).
  if robot.detectUp() then robot.swingUp() end
  C.moveUp()
  fwd(3)
  C.moveDown()
  C.turnAround()
  C.lastGeneratorReport.fueled[2] = fuelFront(secondShare)

  -- Return to stasis: turn around, forward, left, forward 3, left, forward 4, left.
  C.turnAround()
  fwd(1)
  C.turnLeft()
  fwd(3)
  C.turnLeft()
  fwd(4)
  C.turnLeft()

  return "stasis"
end

C.fillGenerators = fill_generators

return fill_generators
