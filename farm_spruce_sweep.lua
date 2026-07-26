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

local function farm_spruce_sweep()
  if batteryLevel() < 0.25 then
    return "returning"
  end

  os.sleep(DROP_WAIT)

  -- sweepAround navigates from wherever we are (stasis) out to the tree area and
  -- spirals over the surrounding cells, sucking up the drops on the ground/in air.
  C.sweepAround(C.SPRUCE_X, C.SPRUCE_Z, C.SPRUCE_Y)

  C.followPath(C.SPRUCE_RETURN_PATH)
  C.face(2)

  return "stasis"
end

C.farmSpruceSweep = farm_spruce_sweep

return farm_spruce_sweep
