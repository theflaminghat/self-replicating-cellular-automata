-- test_build_robot.lua
-- Runs the real build_robot state once, starting from the stasis spot (4,1,3).
--
-- It goes to the tracked chest (0,1,0), takes all the robot parts, carries them
-- to the assembler (6,1,2), deposits them (case first), presses the assemble
-- button, and comes back to stasis.
--
-- Short paged output: nothing scrolls off.

local component = require("component")
local robot = require("robot")
local os = require("os")

local C = require("common")
local build_robot = require("build_robot")

-- ---- settings ----------------------------------------------------
local PAGE_SECONDS = 15
-- ------------------------------------------------------------------

local term
pcall(function() term = require("term") end)
local function clear()
  if term and term.clear then term.clear() else for _ = 1, 12 do print("") end end
end

local pageNo, TOTAL = 0, 5
local function page(title, lines)
  pageNo = pageNo + 1
  clear()
  print("[" .. pageNo .. "/" .. TOTAL .. "] " .. title)
  print("--------------------------")
  for _, l in ipairs(lines) do print(l) end
  print("--------------------------")
  os.sleep(PAGE_SECONDS)
end

C.pos.x, C.pos.y, C.pos.z, C.pos.facing = 4, 1, 3, 2

local startX, startZ = C.pos.x, C.pos.z
local moves = 0
local origFwd = C.moveForward
C.moveForward = function()
  local ok = origFwd()
  if ok then moves = moves + 1 end
  return ok
end

clear()
print("build_robot: running ...")
local ok, nextState = pcall(build_robot)
C.moveForward = origFwd

-- PAGE 1: crash / error
local l1 = { "crashed : " .. tostring(not ok) }
if ok then
  l1[#l1 + 1] = "returned: " .. tostring(nextState)
else
  local m = tostring(nextState)
  while #m > 0 do l1[#l1 + 1] = "  " .. m:sub(1, 24); m = m:sub(25) end
end
l1[#l1 + 1] = "error: " .. tostring(C.lastBuildError or "none")
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

-- PAGE 3: parts taken from the chest (first half of the report)
local rep = C.lastBuildReport or {}
local l3, l4 = {}, {}
local half = math.ceil(#rep / 2)
for i, r in ipairs(rep) do
  local line = (r.taken >= r.wanted and "  ok  " or "  --  ")
    .. r.taken .. "/" .. r.wanted .. " " .. tostring(r.item):sub(1, 16)
  if i <= half then l3[#l3 + 1] = line else l4[#l4 + 1] = line end
end
if #l3 == 0 then l3[1] = "(no parts)" end
page("PARTS TAKEN 1/2", l3)

-- PAGE 4: parts taken (second half)
if #l4 == 0 then l4[1] = "(none)" end
page("PARTS TAKEN 2/2", l4)

-- PAGE 5: button + summary
local missing = 0
for _, r in ipairs(rep) do
  if r.taken < r.wanted then missing = missing + 1 end
end
page("ASSEMBLE", {
  "parts short : " .. missing,
  "button press: " .. tostring(rep.pressed and "YES" or "no"),
  "use() result: " .. tostring(rep.useResult or "-"),
  "",
  (missing == 0 and rep.pressed) and "all parts + button OK"
    or (missing > 0 and "*** some parts missing"
                     or "*** button did not press"),
})

clear()
print("=== build_robot done ===")
print("crashed : " .. tostring(not ok))
print("at home : " .. tostring(home))
print("parts short: " .. missing)
print("pressed : " .. tostring(rep.pressed and true or false))
print("error   : " .. tostring(C.lastBuildError or "none"))
