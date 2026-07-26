-- test_farm_spruce_sweep.lua
-- Runs the real farm_spruce_sweep state once, starting from the stasis spot
-- (4,1,3) facing the charger. It waits for leaf-decay drops, spirals over the cells
-- around the spruce tree base (4,12) sucking up items, and returns to stasis.
--
-- Run this AFTER a tree has been harvested (by farm_spruce) so there are drops on
-- the ground to collect. It is a "test" only in that it runs that one state in
-- isolation from the stasis point rather than as part of the full weave.
--
-- NOTE: this drives the real robot and sleeps ~30s up front waiting for drops.

local component = require("component")
local robot = require("robot")

local C = require("common")
local farm_spruce_sweep = require("farm_spruce_sweep")

-- Seed the position tracker to the stasis spot, facing the charger (-Z).
-- facing convention: 0=+Z, 1=+X, 2=-Z, 3=-X.
C.pos.x = C.STASIS_X
C.pos.y = C.STASIS_Y
C.pos.z = C.STASIS_Z
C.pos.facing = 2

print("=== farm_spruce_sweep test ===")
print(string.format("start pos: x=%d y=%d z=%d facing=%d",
  C.pos.x, C.pos.y, C.pos.z, C.pos.facing))
print(string.format("sweeping radius %d around the tree at (%d,%d)",
  C.SWEEP_RADIUS, C.SPRUCE_X, C.SPRUCE_Z))

local nextState = farm_spruce_sweep()

print(string.format("end pos:   x=%d y=%d z=%d facing=%d",
  C.pos.x, C.pos.y, C.pos.z, C.pos.facing))
local home = (C.pos.x == C.STASIS_X and C.pos.y == C.STASIS_Y
          and C.pos.z == C.STASIS_Z and C.pos.facing == 2)
print("at stasis: " .. tostring(home))
print("farm_spruce_sweep() returned next state: " .. tostring(nextState))
print("=== done ===")
