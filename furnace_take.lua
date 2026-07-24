local C = require("common")

local robot = C.robot
local pos = C.pos
local inv = C.inv
local sides = C.sides
local os = C.os
local batteryLevel = C.batteryLevel

local freeSlot = C.freeSlot

-- The output is taken from UNDER the furnace, so read its slots from the up face.
local function furnaceStack(slot)
  local ok, st = pcall(inv.getStackInSlot, sides.up, slot)
  if ok and st and st.size and st.size > 0 then
    return st
  end
  return nil
end

-- While the furnace is still full (input not yet consumed), check again every
-- POLL_SECONDS. MAX_POLLS caps the wait so a stalled furnace (out of fuel) can't
-- hang the robot forever.
local POLL_SECONDS = 20
local MAX_POLLS    = 90

local function furnace_take()
  if batteryLevel() < 0.25 then
    return "returning"
  end

  C.lastFurnaceError = nil
  C.lastFurnaceTake = { taken = 0, item = nil }

  -- Stasis -> furnace base stand (2,1,3), then forward into the gap (2,1,2)
  -- directly below the furnace, where its bottom face (the output) is reachable.
  C.gotoFurnaceFromStasis()
  C.moveForward()                        -- (2,1,2), under the furnace
  local ok, size = pcall(inv.getInventorySize, sides.up)
  if not (ok and size) then
    C.lastFurnaceError = "no furnace above the gap"
    C.moveBack()
    C.gotoStasisFromFurnace()
    return "stasis"
  end

  -- Wait for the batch to finish: while the furnace still has input to smelt, wait
  -- POLL_SECONDS and check again. Stop at the cap so a stall doesn't hang forever.
  for _ = 1, MAX_POLLS do
    if not furnaceStack(C.FURNACE_SLOT_INPUT) then break end
    os.sleep(POLL_SECONDS)
  end

  local out = furnaceStack(C.FURNACE_SLOT_OUTPUT)
  if not out then
    C.lastFurnaceError = "furnace output is empty"
    C.moveBack()
    C.gotoStasisFromFurnace()
    return "stasis"
  end

  C.lastFurnaceTake.item = out.label or out.name

  local into = freeSlot()
  if not into then
    C.lastFurnaceError = "no free slot for the output"
    C.moveBack()
    C.gotoStasisFromFurnace()
    return "stasis"
  end

  -- Pull the smelted items up out of the furnace's bottom face.
  robot.select(into)
  local tookOk = pcall(robot.suckUp, out.size)
  if not tookOk then
    C.lastFurnaceError = "could not take the output"
    C.moveBack()
    C.gotoStasisFromFurnace()
    return "stasis"
  end

  local gotStack = select(2, pcall(inv.getStackInInternalSlot, into))
  C.lastFurnaceTake.taken = (gotStack and gotStack.size) or 0

  if C.lastFurnaceTake.taken == 0 then
    C.lastFurnaceError = "took nothing"
  end

  -- Back up to (2,1,3), then to stasis. Output stays in the robot's inventory.
  C.moveBack()
  C.gotoStasisFromFurnace()
  return "stasis"
end

C.furnaceTake = furnace_take

return furnace_take
