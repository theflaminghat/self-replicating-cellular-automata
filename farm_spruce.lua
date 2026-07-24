-- farm_spruce.lua
-- Harvest the spruce tree: take a replacement sapling from the tracked chest, go
-- to the tree base, and check whether the sapling has grown (step up one and over
-- one -- if both moves are clear it hasn't grown, so leave; if either is blocked a
-- trunk is there, so harvest). When grown, mine straight up until nothing more can
-- be broken (pillaring up with reserve cobble if the tree out-climbs the hover
-- limit), mine back down, replant the sapling, wait for leaf-decay drops to fall,
-- then sweep the surrounding cells. Returns to stasis.
local C = require("common")

local robot = C.robot
local pos = C.pos
local os = C.os
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

  -- Growth check: from the approach cell (facing the sapling) try to step up one
  -- and over one, without digging. If BOTH moves succeed the space is clear -- the
  -- sapling hasn't grown into a tree yet -- so leave and come back next pass. If
  -- either move is blocked, a trunk (or leaves) are in the way: it has grown, so
  -- return to the approach cell and harvest.
  local up = moveUp()                    -- (3,2,12) if clear
  local over = up and C.moveForward()    -- (4,2,12) if also clear
  if up and over then
    C.followPath(C.SPRUCE_RETURN_PATH)
    C.face(2)
    return "stasis"
  end
  if up then C.moveDown() end            -- back down to the approach cell (3,1,12)

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

  -- Wait for leaf-decay drops (saplings, sticks, apples) to fall before sweeping.
  os.sleep(30)

  C.sweepAround(C.SPRUCE_X, C.SPRUCE_Z, C.SPRUCE_Y)

  C.followPath(C.SPRUCE_RETURN_PATH)
  C.face(2)

  return "stasis"
end

return farm_spruce
