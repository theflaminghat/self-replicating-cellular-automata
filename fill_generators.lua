local C = require("common")

local robot = C.robot
local pos = C.pos
local inv = C.inv
local sides = C.sides
local batteryLevel = C.batteryLevel

-- Match coal by internal id OR display label. Packs vary: the id may be
-- "minecraft:coal", a modded string, or the item may only be reliably
-- identified by its in-game name ("Coal"). Checking both is robust.
local COAL_NAME = "minecraft:coal"
local COAL_LABEL = "Coal"

local function isCoal(st)
  if not st then return false end
  if st.name == COAL_NAME then return true end
  if st.label == COAL_LABEL then return true end
  return false
end
local FETCH_SLOT = 22

local function fwd(n)
  for _ = 1, n do C.moveForward() end
end

local facingInventory = C.facingFront

local function heldCoal()
  local total = 0
  for s = 1, (C.INVENTORY_SIZE or 32) do
    local ok, st = pcall(inv.getStackInInternalSlot, s)
    if ok and isCoal(st) and st.size then
      total = total + st.size
    end
  end
  return total
end

local function findHeldSlot()
  for s = 1, (C.INVENTORY_SIZE or 32) do
    local ok, st = pcall(inv.getStackInInternalSlot, s)
    if ok and isCoal(st) and st.size and st.size > 0 then
      return s
    end
  end
  return nil
end

local firstEmptySlot = C.freeSlot

local function pullCoal(count)
  local size = facingInventory()
  if not size then return 0 end
  local got = 0
  for s = 1, size do
    if got >= count then break end
    local ok, st = pcall(inv.getStackInSlot, sides.front, s)
    if ok and isCoal(st) and st.size and st.size > 0 then
      local take = math.min(count - got, st.size)
      -- suckFromSlot deposits into the SELECTED slot; if that slot is occupied
      -- by something else the transfer silently fails. Select a genuinely empty
      -- slot each time (falling back to one already holding coal so stacks
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

-- Drop up to `count` coal into the generator directly in front. Works from one
-- coal slot at a time -- reading just that slot's size before/after the drop
-- instead of rescanning the whole inventory each iteration (coal is usually a
-- single stack, so this is one drop and two single-slot reads).
local function fuelFront(count)
  local moved = 0
  while moved < count do
    local from = findHeldSlot()
    if not from then break end
    robot.select(from)
    local st = inv.getStackInInternalSlot(from)
    local have = (st and st.size) or 0
    if have == 0 then break end
    -- robot.drop into the block in front; unlike dropIntoSlot it doesn't target a
    -- specific slot -- the generator takes the coal as fuel.
    local ok, done = pcall(robot.drop, count - moved)
    if not (ok and done) then break end
    local after = inv.getStackInInternalSlot(from)
    local justMoved = have - ((after and after.size) or 0)
    if justMoved <= 0 then break end
    moved = moved + justMoved
  end
  return moved
end

local function fill_generators()
  -- No low-battery bail: this runs as part of the charge cycle, so it must fuel the
  -- generators precisely WHEN the battery is low (they're what power the charger).
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

  -- Take enough coal for both generators.
  local need = perGen * 2 - heldCoal()
  if need > 0 then
    pullCoal(need)
  end
  local haveCoal = heldCoal()
  if haveCoal == 0 then
    C.lastGeneratorError = "no coal in chest"
  end

  -- Split what we actually have evenly between the two generators, capped at
  -- the per-generator target. The first generator gets the rounded-up half so
  -- an odd amount does not strand one piece.
  local firstShare = math.min(perGen, math.ceil(haveCoal / 2))
  local secondShare = math.min(perGen, haveCoal - firstShare)

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
