-- diag_craft_run.lua
-- Minimal: runs the crafting state and reports ONLY where it fails.
-- Short paged output, nothing scrolls away.
--
-- Run with the robot at the stasis spot (4,1,3).

local component = require("component")
local robot = require("robot")
local os = require("os")

local PAGE_SECONDS = 15

local term
pcall(function() term = require("term") end)
local function clear()
  if term and term.clear then term.clear() else for _=1,12 do print("") end end
end
local function hold() os.sleep(PAGE_SECONDS) end

local C = require("common")
local crafting_state = require("crafting")

C.pos.x, C.pos.y, C.pos.z, C.pos.facing = 4, 1, 3, 2
C.assumeMaterials = true

local startX, startZ = C.pos.x, C.pos.z
local moves = 0
local origFwd = C.moveForward
C.moveForward = function()
  local ok = origFwd()
  if ok then moves = moves + 1 end
  return ok
end

local JOBS = { { name = "minecraft:stick", amount = 16 } }

clear()
print("running crafting state ...")
local ok, res = pcall(crafting_state, JOBS)
C.moveForward = origFwd

-- PAGE 1: crash or clean return?
clear()
print("[1/3] DID IT CRASH?")
print("--------------------------")
print("crashed : " .. tostring(not ok))
if ok then
  print("returned: " .. tostring(res))
else
  print("ERROR:")
  local m = tostring(res)
  while #m > 0 do
    print("  " .. m:sub(1, 28))
    m = m:sub(29)
  end
end
print("--------------------------")
hold()

-- PAGE 2: did it move?
clear()
print("[2/3] DID IT MOVE?")
print("--------------------------")
print("from  : " .. startX .. "," .. startZ)
print("now   : " .. C.pos.x .. "," .. C.pos.z)
print("moves : " .. moves)
print("")
if moves == 0 then
  print("0 moves = stopped before")
  print("the walk to the chest")
else
  print("it walked")
end
print("--------------------------")
hold()

-- PAGE 3: reason
clear()
print("[3/3] REASON")
print("--------------------------")
print("abort: " .. tostring(C.lastCraftError or "none"))
local rep = C.lastCraftReport
if rep and #rep > 0 then
  for _, r in ipairs(rep) do
    print("job  : " .. tostring(r.batches) .. " made")
    print("why  : " .. tostring(r.reason or "ok"))
  end
else
  print("jobs : never ran")
end
print("--------------------------")
print("done")
