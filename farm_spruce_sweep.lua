-- farm_spruce_sweep.lua
-- Collect the spruce tree's leaf-decay drops (saplings, sticks, apples) after the
-- tree has been harvested by farm_spruce. Waits for the drops to finish falling,
-- spirals out from the tree base sucking up ground/hovering items, then returns to
-- stasis. Kept separate from farm_spruce so the harvest isn't blocked waiting on
-- drops -- run this a few steps later in the weave, once the leaves have decayed.
local C = require("common")

local os = C.os
local batteryLevel = C.batteryLevel

-- Seconds to let leaf-decay drops fall before sweeping. Guards the case where this
-- runs right after the harvest; harmless (just a minimum) when it runs later.
local DROP_WAIT = 30

local function fwd(n)
  for _ = 1, n do
    if not C.moveForward() then break end
  end
end

local function farm_spruce_sweep()
  if batteryLevel() < 0.25 then
    return "returning"
  end

  os.sleep(DROP_WAIT)

  -- Stasis -> tree area, keeping clear of the sugarcane the plain over-the-top route
  -- crossed: right, forward 3, right, forward 9, right, forward 2. Ends at (3,1,12)
  -- facing +X, beside the tree, so the spiral below stays local.
  C.face(2)
  C.turnRight(); fwd(3)
  C.turnRight(); fwd(9)
  C.turnRight(); fwd(2)

  -- Spiral over the cells around the tree base, sucking up the drops.
  C.sweepAround(C.SPRUCE_X, C.SPRUCE_Z, C.SPRUCE_Y)

  -- Step back to the tree base (the cell just south of the sapling, facing the
  -- charger) so the return always starts from the same spot -- the spiral can end
  -- anywhere, and this makes the route below a clean "forward 3, then turn left".
  C.gotoNoBreak(C.SPRUCE_X, C.SPRUCE_Z + 1, C.SPRUCE_Y)
  C.face(2)

  -- Return via the sweep's own route (forward 3 south, turn left, east lane home).
  C.followPath(C.SPRUCE_SWEEP_RETURN_PATH)
  C.face(2)

  return "stasis"
end

C.farmSpruceSweep = farm_spruce_sweep

return farm_spruce_sweep
