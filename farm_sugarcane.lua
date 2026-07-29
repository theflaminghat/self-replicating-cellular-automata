local C = require("common")

local robot = C.robot
local pos = C.pos
local moveUp = C.moveUp
local moveDown = C.moveDown
local batteryLevel = C.batteryLevel

local KEEP_Y = 2
local TRAVEL_Y = 5
local MAX_CLIMB = 12

local function riseToClear()
  local guard = 0
  while pos.y < TRAVEL_Y and guard < MAX_CLIMB do
    if robot.detectUp() then robot.swingUp() end
    if not moveUp() then break end
    guard = guard + 1
  end
  guard = 0
  while robot.detect() and guard < MAX_CLIMB do
    if robot.detectUp() then robot.swingUp() end
    if not moveUp() then break end
    guard = guard + 1
  end
end

local function goTo(tx, tz)
  riseToClear()
  local guard = 0
  while (pos.x ~= tx or pos.z ~= tz) and guard < 64 do
    guard = guard + 1
    local moved = false
    if pos.x < tx then
      C.face(1)
      if robot.detect() then riseToClear() end
      moved = C.moveForward()
    elseif pos.x > tx then
      C.face(3)
      if robot.detect() then riseToClear() end
      moved = C.moveForward()
    elseif pos.z < tz then
      C.face(0)
      if robot.detect() then riseToClear() end
      moved = C.moveForward()
    elseif pos.z > tz then
      C.face(2)
      if robot.detect() then riseToClear() end
      moved = C.moveForward()
    end
    if not moved then
      if not moveUp() then break end
    end
  end
end

local function harvestHere()
  local guard = 0
  while robot.detectUp() and guard < MAX_CLIMB do
    if not moveUp() then break end
    guard = guard + 1
  end
  while pos.y > KEEP_Y + 1 do
    if robot.detectDown() then
      robot.swingDown()
      robot.suckDown()
    end
    if pos.y == KEEP_Y + 1 then break end
    if not moveDown() then break end
  end
  robot.suck()
end

local ORDER = {
  { x = 4, z = 6 },
  { x = 5, z = 6 },
  { x = 6, z = 6 },
  { x = 7, z = 7 },
  { x = 6, z = 8 },
  { x = 5, z = 8 },
  { x = 4, z = 8 },
}

local function approachFirstCane()
  C.turnLeft()
  C.moveForward()
  C.turnLeft()
  C.moveForward()
  C.moveForward()
  C.turnLeft()
  C.moveForward()
  C.turnRight()
  for _ = 1, 4 do
    if robot.detectUp() then robot.swingUp() end
    if not moveUp() then break end
  end
  C.moveForward()
  C.turnRight()
end

local function returnToCharger()
  C.face(3)
  C.turnRight()
  C.moveForward()
  for _ = 1, 2 do
    if not moveDown() then break end
  end
  C.turnLeft()
  C.moveForward()
  C.moveForward()
  C.turnLeft()
  for _ = 1, 6 do
    C.moveForward()
  end
  C.turnLeft()
  C.moveForward()
  C.moveForward()
  C.turnRight()
end

local function farm_sugarcane()
  if batteryLevel() < 0.25 then
    return "returning"
  end

  -- Stop once enough sugar cane for every remaining build has been gathered -- counting
  -- cane already turned into paper (and paper into transistors, ...), not just the loose
  -- stacks. Skips the whole trip out to the field and back.
  if C.gatheredEnough("Sugar Canes") then
    return "stasis"
  end

  approachFirstCane()
  harvestHere()

  for i = 2, #ORDER do
    if batteryLevel() < 0.25 then
      return "returning"
    end
    goTo(ORDER[i].x, ORDER[i].z)
    harvestHere()
  end

  returnToCharger()

  return "stasis"
end

return farm_sugarcane
