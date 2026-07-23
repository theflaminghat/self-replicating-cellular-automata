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

-- Drop up to `count` of `item` into the inventory in front with the basic
-- robot.drop (the robot is facing the furnace). Loading the smeltable first lands
-- it in the input slot; the fuel, dropped afterwards, goes to the fuel slot since
-- the input is then occupied.
local function dropFront(item, count)
  local moved = 0
  while moved < count do
    local from = findHeldSlot(item)
    if not from then break end
    robot.select(from)
    local before = heldCount(item)
    local ok, done = pcall(robot.drop, count - moved)
    if not (ok and done) then break end
    local justMoved = before - heldCount(item)
    if justMoved <= 0 then break end
    moved = moved + justMoved
  end
  return moved
end

local function furnaceSlotStack(slot)
  local ok, st = pcall(inv.getStackInSlot, sides.front, slot)
  if ok and st and st.size and st.size > 0 then
    return st
  end
  return nil
end

-- A single furnace smelts one item type at a time, so this state loads exactly
-- one job per run: the first job in the list. It goes to the CHEST first and
-- pulls the ore + fuel, THEN to the furnace. If the furnace is still working a
-- previous batch the pulled ore is carried back and the next inventory pass
-- redeposits it.
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
  if not facingInventory() then
    C.lastFurnaceError = "not facing the furnace"
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

  -- Load the smeltable first, then the fuel, both with robot.drop while facing the
  -- furnace: the input drop lands in the input slot, and the fuel drop then lands
  -- in the fuel slot. held == 0 means the chest pull failed (wrong id/label, or
  -- nothing in the tracked chest); held > 0 with loaded == 0 means the furnace
  -- took no input.
  local have = math.min(amount, heldCount(job.item))
  report.held = have
  if have > 0 then
    report.loaded = dropFront(job.item, have)
    if report.loaded == 0 then
      report.reason = "held " .. have .. " but furnace took no input"
    end
  else
    report.reason = "no ore pulled from chest"
  end

  if job.fuel then
    local haveFuel = math.min(fuelWanted, heldCount(job.fuel))
    if haveFuel > 0 then
      report.fuel = dropFront(job.fuel, haveFuel)
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
