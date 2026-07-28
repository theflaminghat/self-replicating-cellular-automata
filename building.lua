-- building.lua
local C = require("common")

local robot = C.robot
local gotoXZ = C.gotoXZ
local gotoNoBreak = C.gotoNoBreak
local moveUp = C.moveUp
local placeSlotDown = C.placeSlotDown
local placeCobbleDown = C.placeCobbleDown
local placeWaterDown = C.placeWaterDown

local function building()
  -- The floor is a plain cobblestone fill now, with no open hole, so the
  -- movement helpers must NOT avoid the old mine-shaft cell (4,4). Without this,
  -- gotoXZ detours around it and falls back to up-and-over routing.
  C.allowHole = true

  -- The robot boots at its build corner (local origin 0,1,0) facing whatever direction
  -- it was placed. A placed offspring inherits the placer's facing, which is fixed per
  -- compass type (C.placementFacing); the Genesis robot is hand-placed facing +X. Seed
  -- the tracked facing to that real placement facing, then physically turn to EAST (+X)
  -- so every base -- whichever way the offspring was carried -- lays out identically into
  -- the +x,+z region.
  C.pos.x, C.pos.y, C.pos.z, C.pos.facing = 0, 1, 0, C.placementFacing(C.robotType)
  C.face(1)   -- turn to face east; tracked facing is now +X (1)

  -- Serpentine floor sweep. The robot boots facing +X, so the inner loop walks
  -- along X (straight ahead) first, then steps to the next Z row. This avoids a
  -- turn at the very start.
  for zi = 0, C.BUILD_Z - 1 do
    local xStart, xEnd, xStep
    if zi % 2 == 0 then
      xStart, xEnd, xStep = 0, C.BUILD_X - 1, 1
    else
      xStart, xEnd, xStep = C.BUILD_X - 1, 0, -1
    end
    for xi = xStart, xEnd, xStep do
      gotoXZ(xi, zi)
      if robot.detectDown() then robot.swingDown() end
      -- Most cells get cobblestone; FLOOR_OVERRIDES cells (e.g. dirt at 4,12)
      -- get their specific block instead. A single failed placement (e.g. the
      -- cell already has a block, or OC's thin-air rule on the very first cell)
      -- is not a reason to abandon the whole build -- skip and keep going.
      local override = C.floorOverride(xi, zi)
      if override then
        placeSlotDown(override)
      else
        placeCobbleDown()
      end
    end
  end

  for _, p in ipairs(C.PLACEMENTS) do
    gotoNoBreak(p.x, p.z, 2)
    placeSlotDown(p.slot)
    -- After placing the computer case, add its components. The robot is standing
    -- directly above the case, so dropDown feeds each part into it in order.
    if p.slot == C.SLOTS.case3 then
      for _, part in ipairs(C.COMPUTER_PARTS) do
        robot.select(part.slot)
        local stack = C.inv.getStackInInternalSlot(part.slot)
        if stack and stack.size and stack.size > 0 then
          pcall(function() robot.dropDown(1) end)
        end
      end
    end
  end

  -- The furnace is raised one block (to 2,2,2) so smelted output can be pulled
  -- from underneath it. Place a cobblestone on the furnace floor cell (2,1,2), set
  -- the furnace on top of it, then drop down beside it and break the cobblestone
  -- out, leaving a gap the robot can stand in to reach the furnace's bottom face.
  gotoNoBreak(C.FURNACE.x, C.FURNACE.z, 2)      -- (2, ?, 2), above the floor cell
  placeCobbleDown()                             -- cobble at (2,1,2)
  moveUp()                                       -- up to (2,3,2)
  placeSlotDown(C.SLOTS.furnace)                 -- furnace at (2,2,2)
  gotoNoBreak(C.FURNACE.x, C.FURNACE.z + 1, 1)  -- down beside it, (2,1,3)
  C.face(2)                                       -- face the cobble at (2,1,2)
  while robot.detect() do robot.swing() end      -- break it, opening the gap

  for _, c in ipairs(C.CHEST_PLACEMENTS) do
    gotoNoBreak(c.x, c.z, 2)
    for level = 1, C.CHEST_STACK_HEIGHT do
      placeSlotDown(C.SLOTS.chest)
      if level < C.CHEST_STACK_HEIGHT then
        if not moveUp() then break end
      end
    end
  end

  for _, s in ipairs(C.SAND_PLACEMENTS) do
    gotoNoBreak(s.x, s.z, 2)
    placeSlotDown(C.SLOTS.sand)
  end

  for _, w in ipairs(C.WATER_PLACEMENTS) do
    gotoNoBreak(w.x, w.z, 2)
    placeWaterDown()
  end

  for _, p in ipairs(C.Y2_PLACEMENTS) do
    gotoNoBreak(p.x, p.z, 3)
    placeSlotDown(p.slot)
  end

  for _, p in ipairs(C.CACTUS_PLACEMENTS) do
    gotoNoBreak(p.x, p.z, 3)
    placeSlotDown(C.SLOTS.cactus)
  end

  for _, p in ipairs(C.SUGARCANE_PLACEMENTS) do
    gotoNoBreak(p.x, p.z, 3)
    placeSlotDown(C.SLOTS.sugarcane)
  end

  for _, p in ipairs(C.SAPLING_PLACEMENTS) do
    gotoNoBreak(p.x, p.z, 2)
    placeSlotDown(C.SLOTS.spruce_sapling)
  end

  -- After the sapling (at 4,12 facing +Z), route to stasis by going around the
  -- sugarcane farm rather than back through it:
  -- left, forward 2, down, left, forward 9, left, forward 2, right.
  C.turnLeft()
  for _ = 1, 2 do C.moveForward() end
  C.moveDown()
  C.turnLeft()
  for _ = 1, 9 do C.moveForward() end
  C.turnLeft()
  for _ = 1, 2 do C.moveForward() end
  C.turnRight()

  return "stasis"
end

return building
