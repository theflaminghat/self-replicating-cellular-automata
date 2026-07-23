local C = require("common")

local robot = C.robot
local pos = C.pos
local inv = C.inv
local sides = C.sides
local batteryLevel = C.batteryLevel

-- The furnace may sit on any face of the robot. Try all six to locate it and to
-- read/extract, rather than assuming sides.front.
local FURNACE_SIDES = {
  sides.down, sides.front, sides.up, sides.back, sides.left, sides.right,
}

local function furnaceSide()
  for _, sd in ipairs(FURNACE_SIDES) do
    local ok, size = pcall(inv.getInventorySize, sd)
    if ok and size and size > 0 then
      return sd
    end
  end
  return nil
end

local function furnaceStack(sd, slot)
  local ok, st = pcall(inv.getStackInSlot, sd, slot)
  if ok and st and st.size and st.size > 0 then
    return st
  end
  return nil
end

local freeSlot = C.freeSlot

local function furnace_take()
  if batteryLevel() < 0.25 then
    return "returning"
  end

  C.lastFurnaceError = nil
  C.lastFurnaceTake = { taken = 0, item = nil }

  -- Stasis -> furnace.
  C.gotoFurnaceFromStasis()
  local sd = furnaceSide()
  if not sd then
    C.lastFurnaceError = "no furnace found on any side"
    C.gotoStasisFromFurnace()
    return "stasis"
  end

  -- Don't pull the output while the furnace is still smelting: the input slot
  -- being non-empty means the batch isn't finished. Leave the output where it is
  -- and collect it on a later pass once the input has been fully consumed.
  if furnaceStack(sd, C.FURNACE_SLOT_INPUT) then
    C.lastFurnaceError = "still smelting; leaving output in furnace"
    C.gotoStasisFromFurnace()
    return "stasis"
  end

  local out = furnaceStack(sd, C.FURNACE_SLOT_OUTPUT)
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
  local tookOk = pcall(inv.suckFromSlot, sd, C.FURNACE_SLOT_OUTPUT, out.size)
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
