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

-- The smeltable INPUT can only be inserted through the furnace's TOP face, so the
-- robot climbs directly above the furnace and drops DOWN into it. FUEL goes in
-- through a SIDE face, so it is dropped in front from the side stand. `dropper` is
-- the drop function (robot.dropDown for the input, robot.drop for fuel).
local function dropInto(item, count, dropper)
  local moved = 0
  while moved < count do
    local from = findHeldSlot(item)
    if not from then break end
    robot.select(from)
    local before = heldCount(item)
    local ok, done = pcall(dropper, count - moved)
    if not (ok and done) then break end
    local justMoved = before - heldCount(item)
    if justMoved <= 0 then break end
    moved = moved + justMoved
  end
  return moved
end

-- A single furnace smelts one item type at a time, so this state loads exactly
-- one job per run: the first job in the list. It goes to the CHEST first and
-- pulls the ore + fuel, THEN to the furnace. Leftover fuel (coal) in the furnace
-- is fine -- more just stacks -- so it never bails on furnace contents; it simply
-- adds the input on top and tops up the fuel.
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
  -- A furnace input slot holds at most a stack, so never load more than 64 in one
  -- pass; larger amounts are broken into multiple jobs by the caller.
  local amount = math.min(job.amount or 0, 64)
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

  -- Chest -> furnace base stand (2,1,3), then up one to (2,2,3), beside the raised
  -- furnace at (2,2,2).
  C.gotoFurnaceFromChest()
  C.moveUp()                            -- (2,2,3)
  if not facingInventory() then
    C.lastFurnaceError = "not facing the furnace"
    C.moveDown()
    C.gotoStasisFromFurnace()
    return "stasis"
  end

  local report = { item = specText(job.item), wanted = amount, loaded = 0, fuel = 0 }

  -- Load the smeltable INPUT through the top face: from (2,2,3), one up and one
  -- forward to sit above the furnace at (2,3,2), drop down into it, then return.
  -- held == 0 means the chest pull failed (wrong id/label, or nothing in the
  -- tracked chest); held > 0 with loaded == 0 means the furnace took no input.
  local have = math.min(amount, heldCount(job.item))
  report.held = have
  if have > 0 then
    local up = C.moveUp()               -- (2,3,3)
    local overFurnace = up and C.moveForward()  -- (2,3,2), above the furnace
    if overFurnace then
      report.loaded = dropInto(job.item, have, robot.dropDown)
      C.moveBack()                      -- (2,3,3)
    end
    if up then C.moveDown() end         -- back to (2,2,3)
    if not overFurnace then
      report.reason = "could not climb above furnace"
    elseif report.loaded == 0 then
      report.reason = "held " .. have .. " but furnace took no input"
    end
  else
    report.reason = "no ore pulled from chest"
  end

  -- Load FUEL from the side stand (2,2,3): robot.drop puts it in the fuel slot.
  if job.fuel then
    local haveFuel = math.min(fuelWanted, heldCount(job.fuel))
    if haveFuel > 0 then
      report.fuel = dropInto(job.fuel, haveFuel, robot.drop)
    end
    if report.fuel == 0 and report.loaded > 0 then
      report.reason = "no fuel loaded"
    end
  end

  C.lastFurnaceReport[#C.lastFurnaceReport + 1] = report

  C.moveDown()                          -- (2,2,3) -> (2,1,3) base stand
  C.gotoStasisFromFurnace()
  return "stasis"
end

C.furnaceAdd = furnace_add

return furnace_add
