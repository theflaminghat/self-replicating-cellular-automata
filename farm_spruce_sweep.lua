-- farm_spruce_sweep.lua
-- Collect the spruce tree's leaf-decay drops (saplings, sticks, apples) after the
-- tree has been harvested by farm_spruce. Waits for the drops to fall, walks out in
-- front of the sapling WITHOUT crossing it, spirals around it (never stepping onto
-- the sapling cell), ends on the west edge, then heads down the x=1 lane back to
-- stasis. Kept separate from farm_spruce so the harvest isn't blocked on drops.
local C = require("common")

local robot = C.robot
local pos = C.pos
local os = C.os
local batteryLevel = C.batteryLevel

-- Seconds to let leaf-decay drops fall before sweeping. Guards the case where this
-- runs right after the harvest; harmless (just a minimum) when it runs later.
local DROP_WAIT = 0

local TRUNK_X, TRUNK_Z = C.SPRUCE_X, C.SPRUCE_Z   -- 4, 12 (the sapling cell)

local function fwd(n)
  for _ = 1, n do
    if not C.moveForward() then break end
  end
end

local function onTrunk(x, z)
  return x == TRUNK_X and z == TRUNK_Z
end

-- Step one cell at a time toward (tx,tz) at the sweep level, NEVER stepping onto the
-- sapling cell. Prefer the x axis, fall back to z when the x step would land on the
-- sapling. Consecutive spiral cells are adjacent, so this is one step each and just
-- rounds the sapling on the transitions that would otherwise cross it.
local function stepToward(tx, tz)
  local guard = 0
  while (pos.x ~= tx or pos.z ~= tz) and guard < 40 do
    guard = guard + 1
    local moved = false
    if pos.x ~= tx and not onTrunk(pos.x + (tx > pos.x and 1 or -1), pos.z) then
      moved = C.stepDirNoDig(tx > pos.x and 1 or 3)
    end
    if not moved and pos.z ~= tz
        and not onTrunk(pos.x, pos.z + (tz > pos.z and 1 or -1)) then
      moved = C.stepDirNoDig(tz > pos.z and 0 or 2)
    end
    if not moved then break end
  end
end

local function farm_spruce_sweep()
  if batteryLevel() < 0.25 then
    return "returning"
  end

  -- Nothing was felled this cycle (the sapling hadn't grown), so there are no
  -- leaf-decay drops to collect -- skip the whole sweep and stay parked.
  if not C.choppedSpruce then
    return "stasis"
  end

  os.sleep(DROP_WAIT)

  -- Stasis -> in front of the sapling: right, forward 3, right, forward 9, right,
  -- forward 2. Ends at (3,1,12) facing +X, one cell short of the sapling at (4,12)
  -- (so it never crosses it) and clear of the sugarcane on the way.
  C.face(2)
  C.turnRight(); fwd(3)
  C.turnRight(); fwd(9)
  C.turnRight(); fwd(2)

  -- Spiral around the sapling (4,12) sucking up drops, stepping cell-to-cell so the
  -- robot rounds the sapling instead of ever stepping onto it.
  for _, o in ipairs(C.spiralOffsets(C.SWEEP_RADIUS)) do
    stepToward(TRUNK_X + o.dx, TRUNK_Z + o.dz)
    robot.suckDown()
    robot.suck()
  end

  -- End the sweep at (1,1,11) on the west edge, then take the x=1 lane home: south
  -- to (1,3), then east to stasis.
  stepToward(1, 11)
  C.followPath({ { x = 1, y = 1, z = 3 }, { x = 4, y = 1, z = 3 } })
  C.face(2)

  return "stasis"
end

C.farmSpruceSweep = farm_spruce_sweep

return farm_spruce_sweep
