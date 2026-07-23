-- mining.lua
local C = require("common")

local robot = C.robot
local pos = C.pos
local moveUp = C.moveUp
local moveDown = C.moveDown
local batteryLevel = C.batteryLevel

local function gotoMiningStart()
  C.turnAround()
  C.moveForward()
  C.moveForward()
end

local function digShaftToBedrock()
  C.shaftDepth = 0
  while true do
    if robot.detectDown() then
      robot.swingDown()
    end
    if not moveDown() then
      break
    end
    C.shaftDepth = C.shaftDepth + 1
  end
end

local function placePillarBlock()
  for _, slot in ipairs(C.RESERVE_COBBLE_SLOTS) do
    local stack = C.inv.getStackInInternalSlot(slot)
    if stack and stack.size and stack.size > 0 then
      robot.select(slot)
      if robot.detectDown() then
        robot.swingDown()
      end
      if robot.placeDown() then
        return true
      end
    end
  end
  return false
end

local function buildPillarUp()
  while pos.y < C.STASIS_Y do
    if robot.detectUp() then robot.swingUp() end
    if not moveUp() then break end
    placePillarBlock()
  end
end

local function returnToStasis()
  C.face(0)
  C.turnAround()
  C.moveForward()
  C.moveForward()
  C.face(2)
end

local miningStarted = false
local function mining()
  if batteryLevel() < 0.25 then
    return "returning"
  end
  C.allowHole = true
  if not miningStarted then
    gotoMiningStart()
    miningStarted = true
  end
  digShaftToBedrock()
  buildPillarUp()
  returnToStasis()
  return "quarry"
end

return mining
