-- test_dispatch.lua
-- Runs the real dispatch state once, starting from the stasis spot (4,1,3).
--
-- The robot walks to the computer (case at 7,1,2), turns it on, drops a hard drive
-- in (slot 7) and waits 18s, swaps the EEPROM in slot 10, swaps the redstone card
-- in slot 1, presses the button on top, and returns to stasis. The robot must be
-- carrying a hard drive, a fresh EEPROM, and a redstone card for the swaps to move
-- anything.
--
-- NOTE: this MOVES the robot and sleeps ~24s at the computer. Start it parked at
-- the charger (stasis).
--
-- Short paged output: nothing scrolls off.

local component = require("component")
local robot = require("robot")
local os = require("os")

local C = require("common")
local dispatch = require("dispatch")

local PAGE_SECONDS = 15

local term
pcall(function() term = require("term") end)
local function clear()
  if term and term.clear then term.clear() else for _ = 1, 12 do print("") end end
end

local pageNo, TOTAL = 0, 3
local function page(title, lines)
  pageNo = pageNo + 1
  clear()
  print("[" .. pageNo .. "/" .. TOTAL .. "] " .. title)
  print("--------------------------")
  for _, l in ipairs(lines) do print(l) end
  print("--------------------------")
  os.sleep(PAGE_SECONDS)
end

-- Seed the tracked position to the charger (stasis), facing the charger (-Z). The
-- robot must be physically parked here.
C.pos.x, C.pos.y, C.pos.z, C.pos.facing = C.STASIS_X, C.STASIS_Y, C.STASIS_Z, 2

local startX, startZ = C.pos.x, C.pos.z
local moves = 0
local origFwd = C.moveForward
C.moveForward = function()
  local ok = origFwd()
  if ok then moves = moves + 1 end
  return ok
end

clear()
print("dispatch: running (~24s at computer) ...")
local ok, nextState = pcall(dispatch)
C.moveForward = origFwd

-- PAGE 1: crash / error
local l1 = { "crashed : " .. tostring(not ok) }
if ok then
  l1[#l1 + 1] = "returned: " .. tostring(nextState)
else
  local m = tostring(nextState)
  while #m > 0 do l1[#l1 + 1] = "  " .. m:sub(1, 24); m = m:sub(25) end
end
l1[#l1 + 1] = "error: " .. tostring(C.lastDispatchError or "none")
page("RESULT", l1)

-- PAGE 2: did it come home?
local home = (C.pos.x == C.STASIS_X and C.pos.y == C.STASIS_Y
          and C.pos.z == C.STASIS_Z and C.pos.facing == 2)
page("POSITION", {
  "from : " .. startX .. "," .. startZ,
  "now  : " .. C.pos.x .. "," .. C.pos.y .. "," .. C.pos.z .. " f=" .. C.pos.facing,
  "moves: " .. moves,
  "",
  home and "AT STASIS, facing charger" or "*** NOT AT STASIS (want 4,1,3 f=2)",
})

-- PAGE 3: which swaps moved an item
local d = C.lastDispatch or {}
page("SWAPS", {
  "hard drive placed : " .. tostring(d.hdd or false),
  "eeprom swapped    : " .. tostring(d.eeprom or false),
  "redstone swapped  : " .. tostring(d.redstone or false),
  "",
  "false = the robot wasn't carrying",
  "that part (or the slot was empty)",
})

clear()
print("=== dispatch done ===")
print("crashed : " .. tostring(not ok))
print("at home : " .. tostring(home))
print("error   : " .. tostring(C.lastDispatchError or "none"))
