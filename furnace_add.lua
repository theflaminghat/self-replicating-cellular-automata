local C = require("common")

local robot = C.robot
local pos = C.pos
local inv = C.inv
local sides = C.sides
local batteryLevel = C.batteryLevel

-- Shared item/inventory helpers (defined in common.lua).
local stackMatches   = C.matchesSpec
local specText       = C.specText
local facingInventory = C.facingFront
local heldCount      = C.heldCount
local findHeldSlot   = C.findHeldSlot
local firstEmptySlot = C.freeSlot

-- Pull up to `count` of `item` from the inventory in front into robot storage.
-- Each transfer lands in a slot that already holds this item (so stacks merge) or
-- a fresh empty slot -- never a fixed scratch slot, so different items can't
-- collide and silently fail to transfer.
local function pullFromFront(item, count)
  local size = facingInventory()
  if not size then return 0 end
  local got = 0
  for s = 1, size do
    if got >= count then break end
    local ok, st = pcall(inv.getStackInSlot, sides.front, s)
    if ok and stackMatches(st, item) and st.size and st.size > 0 then
      local take = math.min(count - got, st.size)
      local dest = findHeldSlot(item) or firstEmptySlot()
      if not dest then break end
      robot.select(dest)
      if inv.suckFromSlot(sides.front, s, take) then
        got = got + take
      end
    end
  end
  return got
end

-- The furnace can sit on any face of the robot depending on where it's standing
-- (beside the furnace for fuel, above it for the smeltable). Rather than assume
-- sides.front, every furnace access tries all six faces and uses whichever one
-- actually has an inventory. Which slot a drop lands in is decided by the face:
-- top -> input, side -> fuel, bottom -> output.
local FURNACE_SIDES = {
  sides.down, sides.front, sides.up, sides.back, sides.left, sides.right,
}

-- Find a face that has an inventory (the furnace). Returns the side, or nil.
local function furnaceSide()
  for _, sd in ipairs(FURNACE_SIDES) do
    local ok, size = pcall(inv.getInventorySize, sd)
    if ok and size and size > 0 then
      return sd
    end
  end
  return nil
end

-- Drop up to `count` of `item` into `slot` of the furnace, trying every face.
-- The caller positions the robot (above for the smeltable -> top face -> input,
-- beside for fuel -> side face -> fuel) and passes the matching slot, so this is
-- correct whether the furnace routes by face or honors the slot index.
local function furnaceInsert(item, count, slot)
  local moved = 0
  while moved < count do
    local from = findHeldSlot(item)
    if not from then break end
    robot.select(from)
    local before = heldCount(item)
    local placed = false
    for _, sd in ipairs(FURNACE_SIDES) do
      local ok, done = pcall(inv.dropIntoSlot, sd, slot, count - moved)
      if ok and done then placed = true break end
    end
    if not placed then break end
    local justMoved = before - heldCount(item)
    if justMoved <= 0 then break end
    moved = moved + justMoved
  end
  return moved
end

-- Read `slot` of the furnace from whichever face it's on. Returns the stack (or
-- nil for an empty slot / no furnace found).
local function furnaceSlotStack(slot)
  local sd = furnaceSide()
  if not sd then return nil end
  local ok, st = pcall(inv.getStackInSlot, sd, slot)
  if ok and st and st.size and st.size > 0 then
    return st
  end
  return nil
end

-- A single vanilla furnace has ONE input slot and smelts one item type at a time,
-- so this state loads exactly one job per run: the first job in the list. It goes
-- to the CHEST first and pulls the ore + fuel, THEN to the furnace -- so a busy or
-- undetected furnace can never cause the chest step to be skipped. If the furnace
-- is still working a previous batch, the pulled ore is carried back and the next
-- inventory pass redeposits it.
local function furnace_add(jobs)
  if not jobs then
    return "stasis"
  end
  if jobs.item then
    jobs = { jobs }
  end
  if #jobs == 0 then
    return "stasis"
  end
  if batteryLevel() < 0.25 then
    return "returning"
  end

  C.lastFurnaceError = nil
  C.lastFurnaceReport = {}

  local job = jobs[1]
  local amount = job.amount or 0
  local fuelWanted = job.fuelAmount or math.ceil(amount / 8)

  -- Stasis -> chest, pull the ore and its fuel.
  C.gotoChestFromStasis()
  if not facingInventory() then
    C.lastFurnaceError = "not facing the tracked chest"
    C.gotoStasisFromChest()
    return "stasis"
  end

  local needItem = amount - heldCount(job.item)
  if needItem > 0 then
    pullFromFront(job.item, needItem)
  end
  if job.fuel then
    local needFuel = fuelWanted - heldCount(job.fuel)
    if needFuel > 0 then
      pullFromFront(job.fuel, needFuel)
    end
  end

  -- Chest -> furnace.
  C.gotoFurnaceFromChest()
  if not furnaceSide() then
    C.lastFurnaceError = "no furnace found on any side"
    C.gotoStasisFromFurnace()
    return "stasis"
  end

  -- Don't switch ores mid-smelt: if the furnace still has input, leave it and
  -- carry the pulled ore back (the inventory state redeposits it next pass).
  local input = furnaceSlotStack(C.FURNACE_SLOT_INPUT)
  if input then
    C.lastFurnaceError = "furnace still smelting " .. tostring(input.label or input.name)
    C.gotoStasisFromFurnace()
    return "stasis"
  end

  local report = { item = specText(job.item), wanted = amount, loaded = 0, fuel = 0 }

  -- Load the smeltable INPUT through the furnace's top face: the robot is at the
  -- side stand (2,1,3) facing the furnace, so climb one up and one forward to sit
  -- directly above the furnace (2,2,2), drop the input down into it, then return.
  -- held == 0 means the chest pull failed (wrong id/label, or nothing in the
  -- tracked chest); held > 0 with loaded == 0 means the furnace took no input.
  local have = math.min(amount, heldCount(job.item))
  report.held = have
  if have > 0 then
    -- Climb directly above the furnace so it sits on the robot's DOWN face, then
    -- insert: from the top face the drop lands in the input slot.
    local up = C.moveUp()               -- (2,2,3)
    local overFurnace = up and C.moveForward()  -- (2,2,2), above the furnace
    if overFurnace then
      report.loaded = furnaceInsert(job.item, have, C.FURNACE_SLOT_INPUT)
      C.moveBack()                      -- (2,2,3)
    end
    if up then C.moveDown() end         -- back to (2,1,3), the side stand
    if not overFurnace then
      report.reason = "could not climb above furnace"
    elseif report.loaded == 0 then
      report.reason = "held " .. have .. " but furnace took no input"
    end
  else
    report.reason = "no ore pulled from chest"
  end

  if job.fuel then
    -- Fuel goes in from the SIDE stand: with the furnace on a side face, the drop
    -- lands in the fuel slot.
    local haveFuel = math.min(fuelWanted, heldCount(job.fuel))
    if haveFuel > 0 then
      report.fuel = furnaceInsert(job.fuel, haveFuel, C.FURNACE_SLOT_FUEL)
    end
    if report.fuel == 0 and report.loaded > 0 then
      report.reason = "no fuel loaded"
    end
  end

  C.lastFurnaceReport[#C.lastFurnaceReport + 1] = report

  C.gotoStasisFromFurnace()
  return "stasis"
end

C.furnaceAdd = furnace_add

return furnace_add
