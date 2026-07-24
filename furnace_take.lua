local C = require("common")

local robot = C.robot
local pos = C.pos
local inv = C.inv
local sides = C.sides
local os = C.os
local batteryLevel = C.batteryLevel

local freeSlot = C.freeSlot

-- While the furnace is still full (input not yet consumed), check again every
-- POLL_SECONDS. MAX_POLLS caps the wait so a stalled furnace (out of fuel) can't
-- hang the robot forever.
local POLL_SECONDS = 20
local MAX_POLLS    = 90

-- Read the furnace INPUT slot from ABOVE. Only the top face exposes the input, so
-- this must be read from above the furnace (not from the gap below, where the
-- bottom face exposes only the output/fuel). Slot 1 is the input whether the
-- controller addresses slots absolutely or per-face.
local function inputStack()
  local ok, st = pcall(inv.getStackInSlot, sides.down, C.FURNACE_SLOT_INPUT)
  if ok and st and st.size and st.size > 0 then
    return st
  end
  return nil
end

local function furnace_take()
  if batteryLevel() < 0.25 then
    return "returning"
  end

  C.lastFurnaceError = nil
  C.lastFurnaceTake = { taken = 0, item = nil }

  -- Stasis -> base stand (2,1,3), then up and over to sit ABOVE the furnace at
  -- (2,3,2), where the input slot is readable.
  C.gotoFurnaceFromStasis()
  C.moveUp()                             -- (2,2,3)
  C.moveUp()                             -- (2,3,3)
  C.moveForward()                        -- (2,3,2), above the furnace
  local okSize, size = pcall(inv.getInventorySize, sides.down)
  if not (okSize and size) then
    C.lastFurnaceError = "no furnace below the top stand"
    C.moveBack()                         -- (2,3,3)
    C.moveDown()                         -- (2,2,3)
    C.moveDown()                         -- (2,1,3)
    C.gotoStasisFromFurnace()
    return "stasis"
  end

  -- Wait for the batch to finish: while the input still has items to smelt, wait
  -- POLL_SECONDS and check again. Stop at the cap so a stall doesn't hang forever.
  for _ = 1, MAX_POLLS do
    if not inputStack() then break end
    os.sleep(POLL_SECONDS)
  end

  -- Above the furnace (2,3,2) -> the gap below it (2,1,2), where the bottom face
  -- exposes the output.
  C.moveBack()                           -- (2,3,3)
  C.moveDown()                           -- (2,2,3)
  C.moveDown()                           -- (2,1,3)
  C.moveForward()                        -- (2,1,2), under the furnace

  local into = freeSlot()
  if not into then
    C.lastFurnaceError = "no free slot for the output"
    C.moveBack()                         -- (2,1,3)
    C.gotoStasisFromFurnace()
    return "stasis"
  end

  -- Pull the smelted items up out of the furnace's bottom face. suckUp doesn't take
  -- a slot, so it works regardless of how the controller indexes furnace slots.
  robot.select(into)
  local tookOk = pcall(robot.suckUp)

  local gotStack = select(2, pcall(inv.getStackInInternalSlot, into))
  C.lastFurnaceTake.taken = (gotStack and gotStack.size) or 0
  C.lastFurnaceTake.item = gotStack and (gotStack.label or gotStack.name) or nil

  if not tookOk or C.lastFurnaceTake.taken == 0 then
    C.lastFurnaceError = "took nothing (output empty?)"
  end

  -- Back up to (2,1,3), then to stasis. Output stays in the robot's inventory.
  C.moveBack()                           -- (2,1,3)
  C.gotoStasisFromFurnace()
  return "stasis"
end

C.furnaceTake = furnace_take

return furnace_take
