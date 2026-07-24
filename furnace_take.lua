local C = require("common")

local robot = C.robot
local pos = C.pos
local inv = C.inv
local sides = C.sides
local os = C.os
local batteryLevel = C.batteryLevel

local facingInventory = C.facingFront
local freeSlot        = C.freeSlot

local function furnaceStack(slot)
  local ok, st = pcall(inv.getStackInSlot, sides.front, slot)
  if ok and st and st.size and st.size > 0 then
    return st
  end
  return nil
end

-- A furnace smelts one item every ~10 seconds, so rather than poll we set a single
-- timer for the whole batch: (items in the input) * SMELT_SECONDS, plus a small
-- buffer for any item already partway through when we arrive.
local SMELT_SECONDS = 10
local SMELT_BUFFER  = 10

local function furnace_take()
  if batteryLevel() < 0.25 then
    return "returning"
  end

  C.lastFurnaceError = nil
  C.lastFurnaceTake = { taken = 0, item = nil }

  -- Stasis -> furnace.
  C.gotoFurnaceFromStasis()
  if not facingInventory() then
    C.lastFurnaceError = "not facing the furnace"
    C.gotoStasisFromFurnace()
    return "stasis"
  end

  -- Set a timer for the batch to finish smelting, then take the output. The wait
  -- is sized to the number of items still in the input slot.
  local input = furnaceStack(C.FURNACE_SLOT_INPUT)
  if input then
    os.sleep(input.size * SMELT_SECONDS + SMELT_BUFFER)
  end

  local out = furnaceStack(C.FURNACE_SLOT_OUTPUT)
  if not out then
    C.lastFurnaceError = "furnace output is empty"
    C.gotoStasisFromFurnace()
    return "stasis"
  end

  C.lastFurnaceTake.item = out.label or out.name

  local into = freeSlot()
  if not into then
    C.lastFurnaceError = "no free slot for the output"
    C.gotoStasisFromFurnace()
    return "stasis"
  end

  robot.select(into)
  local tookOk = pcall(robot.suck, out.size)
  if not tookOk then
    C.lastFurnaceError = "could not take the output"
    C.gotoStasisFromFurnace()
    return "stasis"
  end

  local gotStack = select(2, pcall(inv.getStackInInternalSlot, into))
  C.lastFurnaceTake.taken = (gotStack and gotStack.size) or 0

  if C.lastFurnaceTake.taken == 0 then
    C.lastFurnaceError = "took nothing"
  end

  -- Furnace -> stasis. Output stays in the robot's inventory.
  C.gotoStasisFromFurnace()
  return "stasis"
end

C.furnaceTake = furnace_take

return furnace_take
