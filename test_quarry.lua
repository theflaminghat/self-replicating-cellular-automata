-- test_quarry.lua
-- Runs the real quarry state once, assuming the robot begins at the stasis
-- spot (4,1,3) -- in front of the charging port at (4,1,2).
--
-- Place all split files (common.lua, quarry.lua, etc.) in the same
-- directory as this script and run it from there.
--
-- IMPORTANT: This drives the actual robot. It will descend the shaft and
-- excavate the quarry area layer by layer exactly as the real state does.
-- This is a LONG operation on a real world.
--
-- NOTE: quarry normally runs straight after mining, which sets C.shaftDepth
-- (how deep the shaft goes). Running quarry standalone means shaftDepth is 0
-- unless set, so this script lets you specify a depth to work with.
--
-- Progress is saved to /home/quarry_progress.txt and resumes automatically
-- across runs AND reboots. On a resume the shaft depth stored in that file
-- wins over ASSUMED_SHAFT_DEPTH below -- so the value here only matters for
-- the very first run of a fresh quarry.
--
-- To start a completely fresh quarry, call C.resetQuarryProgress() (or delete
-- /home/quarry_progress.txt) before running this.

local component = require("component")
local robot = require("robot")

local C = require("common")
local quarry = require("quarry")

-- How deep the shaft is assumed to be for this test run. Mining normally sets
-- this. Change it to match your actual shaft, or leave as-is to use whatever
-- mining last recorded.
local ASSUMED_SHAFT_DEPTH = 16

C.pos.x = C.STASIS_X      -- 4
C.pos.y = C.STASIS_Y      -- 1
C.pos.z = C.STASIS_Z      -- 3
C.pos.facing = 2          -- facing -Z, toward the charger

if C.shaftDepth == nil or C.shaftDepth == 0 then
  C.shaftDepth = ASSUMED_SHAFT_DEPTH
end

print("=== quarry test ===")
print(string.format("start pos: x=%d y=%d z=%d facing=%d",
  C.pos.x, C.pos.y, C.pos.z, C.pos.facing))
print(string.format("shaft column: (%d, ~, %d)   shaftDepth: %d",
  C.MINE_START_X, C.MINE_START_Z, C.shaftDepth))
print(string.format("quarry area: x %d..%d, z %d..%d, band %d",
  C.QUARRY_MIN_X, C.QUARRY_MAX_X, C.QUARRY_MIN_Z, C.QUARRY_MAX_Z, C.QUARRY_BAND))
print(string.format("battery: %.0f%%", C.batteryLevel() * 100))

-- Run the real quarry state exactly once.
local nextState = quarry()

print(string.format("end pos:   x=%d y=%d z=%d facing=%d",
  C.pos.x, C.pos.y, C.pos.z, C.pos.facing))
print(string.format("battery after: %.0f%%", C.batteryLevel() * 100))
print("allowHole flag: " .. tostring(C.allowHole) ..
  "  (cleared in returning once back at the surface)")
print("quarry() returned next state: " .. tostring(nextState))
print("=== done ===")
