-- farm_spruce.lua
-- Harvest the spruce tree: take a replacement sapling from the tracked chest,
-- go to the tree base, mine straight up until nothing more can be broken
-- (pillaring up with reserve cobble if the tree out-climbs the hover limit),
-- mine back down, replant the sapling, then sweep the 8 surrounding cells for
-- fallen items. Returns to stasis afterward.
local C = require("common")

local robot = C.robot
local pos = C.pos
local moveUp = C.moveUp
local moveDown = C.moveDown
local batteryLevel = C.batteryLevel

-- Mine upward through the trunk. Between moves, if the robot ends up hovering
-- (nothing solid below and nothing was just broken to climb into), pillar up
-- with reserve cobble so it keeps a foothold on tall trees. Stops when the
-- block above can't be broken and can't be entered (top of tree / open sky).
local MAX_TRUNK = 40

local function mineTrunkUp()
  local climbed = 0
  while climbed < MAX_TRUNK do
    if not robot.detectUp() then
      break
    end
    robot.swingUp()
    if moveUp() then
      climbed = climbed + 1
    else
      if not C.placeReserveCobbleDown() then
        break
      end
      if moveUp() then
        climbed = climbed + 1
      else
        break
      end
    end
  end
  return climbed
end

-- Mine straight back down `n` blocks (or until blocked), clearing anything.
local function mineDown(n)
  for _ = 1, n do
    if robot.detectDown() then robot.swingDown() end
    if not moveDown() then break end
  end
end

local function farm_spruce()
  if batteryLevel() < 0.25 then
    return "returning"
  end

  while pos.y > C.SPRUCE_Y do
    if not moveDown() then break end
  end
  while pos.y < C.SPRUCE_Y do
    if not moveUp() then break end
  end

  C.takeFromTrackedChestLow("sapling")

  C.turnRight()
  for _ = 1, 12 do
    if not C.moveForward() then break end
  end

  C.turnRight()
  for _ = 1, 2 do
    if not C.moveForward() then break end
  end

  while robot.detect() do robot.swing() end
  C.moveForward()

  local climbed = mineTrunkUp()

  mineDown(climbed)
  while pos.y > C.SPRUCE_Y do
    if robot.detectDown() then robot.swingDown() end
    if not moveDown() then break end
  end
  while pos.y < C.SPRUCE_Y do
    if not moveUp() then break end
  end

  C.turnLeft()
  C.moveForward()
  C.turnAround()

  if C.selectMatching("sapling") then
    robot.place()
  end

  C.sweepAround(C.SPRUCE_X, C.SPRUCE_Z, C.SPRUCE_Y)

  C.followPath(C.SPRUCE_RETURN_PATH)
  C.face(2)

  return "stasis"
end

return farm_spruce
