local C = require("common")

local robot = C.robot
local pos = C.pos
local inv = C.inv
local sides = C.sides
local batteryLevel = C.batteryLevel

local ASSEMBLER_OUTPUT_SLOT = 1

local facingInventory = C.facingFront
local freeSlot        = C.freeSlot

local function take_robot()
  if batteryLevel() < 0.25 then
    return "returning"
  end

  C.lastTakeRobotError = nil
  C.lastTakeRobot = { taken = 0, item = nil }

  -- Stasis -> assembler (left, forward 2, right).
  C.gotoAssemblerFromStasis()
  if not facingInventory() then
    C.lastTakeRobotError = "not facing the assembler"
    C.gotoStasisFromAssembler()
    return "stasis"
  end

  local ok, out = pcall(inv.getStackInSlot, sides.front, ASSEMBLER_OUTPUT_SLOT)
  if not (ok and out and out.size and out.size > 0) then
    C.lastTakeRobotError = "no finished robot in the assembler"
    C.gotoStasisFromAssembler()
    return "stasis"
  end

  C.lastTakeRobot.item = out.label or out.name

  local into = freeSlot()
  if not into then
    C.lastTakeRobotError = "no free slot for the robot"
    C.gotoStasisFromAssembler()
    return "stasis"
  end

  robot.select(into)
  local tookOk = pcall(inv.suckFromSlot, sides.front, ASSEMBLER_OUTPUT_SLOT, out.size)
  if not tookOk then
    C.lastTakeRobotError = "could not take the robot"
    C.gotoStasisFromAssembler()
    return "stasis"
  end

  local gotStack = select(2, pcall(inv.getStackInInternalSlot, into))
  C.lastTakeRobot.taken = (gotStack and gotStack.size) or 0
  if C.lastTakeRobot.taken == 0 then
    C.lastTakeRobotError = "took nothing"
  end

  -- Assembler -> stasis. The robot stays in inventory.
  C.gotoStasisFromAssembler()
  return "stasis"
end

C.takeRobot = take_robot

return take_robot
