local C = require("common")

local robot = C.robot
local pos = C.pos
local inv = C.inv
local sides = C.sides
local batteryLevel = C.batteryLevel

local function facingInventory()
  local ok, size = pcall(inv.getInventorySize, sides.front)
  if ok and size then return size end
  return nil
end

local function freeSlot()
  for s = 1, (C.INVENTORY_SIZE or 32) do
    local isReserve = false
    for _, r in ipairs(C.RESERVE_COBBLE_SLOTS) do
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

  -- Don't pull the output while the furnace is still smelting: the input slot
  -- being non-empty means the batch isn't finished. Leave the output where it is
  -- and collect it on a later pass once the input has been fully consumed.
  local okIn, input = pcall(inv.getStackInSlot, sides.front, C.FURNACE_SLOT_INPUT)
  if okIn and input and input.size and input.size > 0 then
    C.lastFurnaceError = "still smelting; leaving output in furnace"
    C.gotoStasisFromFurnace()
    return "stasis"
  end

  local ok, out = pcall(inv.getStackInSlot, sides.front, C.FURNACE_SLOT_OUTPUT)
  if not (ok and out and out.size and out.size > 0) then
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
  local tookOk = pcall(inv.suckFromSlot, sides.front, C.FURNACE_SLOT_OUTPUT, out.size)
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
