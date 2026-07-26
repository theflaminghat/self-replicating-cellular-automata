-- test_crusher.lua
-- Runs one crusher cycle from the stasis spot (4,1,3): load a batch of cobblestone
-- from the tracked chest into the crusher (5,2,2) from above, then collect the sand
-- it grinds out of the hopper below (5,1,2). Both C.addToCrusher and
-- C.takeFromHopper start and end at stasis.
--
-- IMPORTANT: this drives the real robot. There must be cobblestone in the tracked
-- chest for the load to move anything, and the crusher needs time to grind before
-- the hopper holds sand -- so on a first run the "take" may come up empty. Run it
-- again (or raise the wait below) to collect the sand from the previous batch.

local component = require("component")
local robot = require("robot")
local os = require("os")

local C = require("common")

-- Seed the tracked position to the stasis spot, facing the charger (-Z).
-- facing convention: 0=+Z, 1=+X, 2=-Z, 3=-X.
C.pos.x = C.STASIS_X
C.pos.y = C.STASIS_Y
C.pos.z = C.STASIS_Z
C.pos.facing = 2

-- Seconds to let the crusher grind the batch before collecting. Tune to your setup.
local GRIND_WAIT = 10

print("=== crusher test ===")
print(string.format("start pos: x=%d y=%d z=%d facing=%d",
  C.pos.x, C.pos.y, C.pos.z, C.pos.facing))
print(string.format("batch in: %d cobblestone -> %d sand",
  C.CRUSHER_BATCH_IN, C.CRUSHER_BATCH_OUT))

-- Load one batch of cobblestone into the crusher.
local loaded = C.addToCrusher(C.CRUSHER_BATCH_IN)
print(string.format("addToCrusher: loaded %d cobblestone", loaded))
print(string.format("  pos now: x=%d y=%d z=%d facing=%d",
  C.pos.x, C.pos.y, C.pos.z, C.pos.facing))

-- Give the crusher a moment to grind before collecting.
print(string.format("waiting %ds for the crusher to grind ...", GRIND_WAIT))
os.sleep(GRIND_WAIT)

-- Collect whatever sand has fallen into the hopper.
local took = C.takeFromHopper()
print(string.format("takeFromHopper: took %d sand", took))

print(string.format("end pos:   x=%d y=%d z=%d facing=%d",
  C.pos.x, C.pos.y, C.pos.z, C.pos.facing))
local home = (C.pos.x == C.STASIS_X and C.pos.y == C.STASIS_Y
          and C.pos.z == C.STASIS_Z and C.pos.facing == 2)
print("at stasis: " .. tostring(home))
if loaded == 0 then
  print("NOTE: loaded 0 -- is there cobblestone in the tracked chest?")
end
print("=== done ===")
