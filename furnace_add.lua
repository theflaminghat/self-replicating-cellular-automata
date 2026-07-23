local C = require("common")

local robot = C.robot
local pos = C.pos
local inv = C.inv
local sides = C.sides
local batteryLevel = C.batteryLevel

local function itemSpec(item)
  if type(item) == "string" then
    return { name = item }
  end
  return item
end

local function stackMatches(st, item)
  if not st then return false end
  local spec = itemSpec(item)
  if spec.name and st.name ~= spec.name then return false end
  if spec.damage and st.damage ~= spec.damage then return false end
  if spec.label and st.label ~= spec.label then return false end
  return true
end

local function specText(item)
  local spec = itemSpec(item)
  return spec.label or spec.name or "?"
end

local function facingInventory()
  local ok, size = pcall(inv.getInventorySize, sides.front)
  if ok and size then return size end
  return nil
end

local function isReserveSlot(s)
  for _, r in ipairs(C.RESERVE_COBBLE_SLOTS or {}) do
    if r == s then return true end
  end
  return false
end

-- Count how many of `item` the robot holds. The reserve cobble slots are skipped
-- so a cobble-based smelt could never drain the pillaring reserve.
local function heldCount(item)
  local total = 0
  for s = 1, (C.INVENTORY_SIZE or 32) do
    if not isReserveSlot(s) then
      local ok, st = pcall(inv.getStackInInternalSlot, s)
      if ok and stackMatches(st, item) and st.size then
        total = total + st.size
      end
    end
  end
  return total
end

local function findHeldSlot(item)
  for s = 1, (C.INVENTORY_SIZE or 32) do
    if not isReserveSlot(s) then
      local ok, st = pcall(inv.getStackInInternalSlot, s)
      if ok and stackMatches(st, item) and st.size and st.size > 0 then
        return s
      end
    end
  end
  return nil
end

local function firstEmptySlot()
  for s = 1, (C.INVENTORY_SIZE or 32) do
    if not isReserveSlot(s) then
      local ok, st = pcall(inv.getStackInInternalSlot, s)
      if ok and not st then
        return s
      end
    end
  end
  return nil
end

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

-- Drop up to `count` of `item` from robot storage into `furnaceSlot` in front.
local function pushIntoFurnaceSlot(item, count, furnaceSlot)
  local moved = 0
  while moved < count do
    local from = findHeldSlot(item)
    if not from then break end
    robot.select(from)
    local before = heldCount(item)
    local ok, done = pcall(inv.dropIntoSlot, sides.front, furnaceSlot, count - moved)
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

-- A single vanilla furnace has ONE input slot and smelts one item type at a time,
-- so this state loads exactly one job per run: the first job whose ore is present.
-- If the furnace is still working a previous batch, it is left untouched (the
-- furnace_take state collects the finished output once the input is consumed).
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

  -- Check the furnace first. Going to the chest to pull ore only makes sense if
  -- the furnace is free to take it.
  C.gotoFurnaceFromStasis()
  if not facingInventory() then
    C.lastFurnaceError = "not facing the furnace"
    C.gotoStasisFromFurnace()
    return "stasis"
  end

  local input = furnaceSlotStack(C.FURNACE_SLOT_INPUT)
  if input then
    -- Still smelting the previous batch; don't switch ores mid-smelt.
    C.lastFurnaceError = "furnace still smelting " .. tostring(input.label or input.name)
    C.gotoStasisFromFurnace()
    return "stasis"
  end

  local job = jobs[1]
  local amount = job.amount or 0
  local fuelWanted = job.fuelAmount or math.ceil(amount / 8)

  -- Furnace -> chest, pull the ore and its fuel.
  C.gotoChestFromFurnace()
  if not facingInventory() then
    C.lastFurnaceError = "not facing the tracked chest"
    C.gotoFurnaceFromChest()
    C.gotoStasisFromFurnace()
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

  -- Chest -> furnace, load input then fuel.
  C.gotoFurnaceFromChest()
  if not facingInventory() then
    C.lastFurnaceError = "not facing the furnace"
    C.gotoStasisFromFurnace()
    return "stasis"
  end

  local report = { item = specText(job.item), wanted = amount, loaded = 0, fuel = 0 }

  local have = math.min(amount, heldCount(job.item))
  if have > 0 then
    report.loaded = pushIntoFurnaceSlot(job.item, have, C.FURNACE_SLOT_INPUT)
  end
  if report.loaded == 0 then
    report.reason = "nothing to smelt"
  end

  if job.fuel then
    local haveFuel = math.min(fuelWanted, heldCount(job.fuel))
    if haveFuel > 0 then
      report.fuel = pushIntoFurnaceSlot(job.fuel, haveFuel, C.FURNACE_SLOT_FUEL)
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
