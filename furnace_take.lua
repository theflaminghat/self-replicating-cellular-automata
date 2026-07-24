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

-- Wait for the current batch to finish: the input slot empties as items smelt.
-- Poll until it is empty. Give up if the input stops shrinking across a few polls
-- (fuel ran out, so it will never finish) so the robot doesn't hang forever.
-- Returns true if the furnace emptied (batch done), false if it stalled.
-- A vanilla furnace smelts ~1 item / 10s, so with a 5s poll the input size is
-- unchanged on roughly every other poll while it's still working -- WAIT_STALL is
-- set well above that so normal smelting isn't mistaken for a stall. WAIT_MAX caps
-- the total wait (a full 64 stack takes ~640s) as a backstop.
local WAIT_POLL = 5      -- seconds between polls
local WAIT_MAX  = 200    -- polls before giving up (~1000s)
local WAIT_STALL = 6     -- consecutive non-shrinking polls (~30s) that mean stalled
local function waitForSmelt()
  local last, stalls = nil, 0
  for _ = 1, WAIT_MAX do
    local input = furnaceStack(C.FURNACE_SLOT_INPUT)
    if not input then return true end          -- input empty: batch finished
    if last and input.size >= last then
      stalls = stalls + 1
      if stalls >= WAIT_STALL then return false end
    else
      stalls = 0
    end
    last = input.size
    os.sleep(WAIT_POLL)
  end
  return false
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

  -- Wait for the batch to finish before taking: while the input slot has items,
  -- the smelt isn't done. If it's still going after the wait (stalled, e.g. out of
  -- fuel), leave the output and try again on a later pass.
  if furnaceStack(C.FURNACE_SLOT_INPUT) then
    waitForSmelt()
    if furnaceStack(C.FURNACE_SLOT_INPUT) then
      C.lastFurnaceError = "still smelting after wait; leaving output in furnace"
      C.gotoStasisFromFurnace()
      return "stasis"
    end
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
