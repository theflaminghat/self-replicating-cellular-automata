-- test_fill_buckets.lua
-- Runs the real fill_buckets state once, starting from the stasis spot (4,1,3).
--
-- It goes to the tracked chest (0,1,0), takes empty buckets, travels over the
-- sugarcane to sit above the water source (5,1,7), fills every bucket, and
-- comes back to stasis carrying the full ones.
--
-- Short paged output: nothing scrolls off.

local component = require("component")
local robot = require("robot")
local os = require("os")

local C = require("common")
local fill_buckets = require("fill_buckets")

local PAGE_SECONDS = 15

local EMPTY_BUCKET = "minecraft:bucket"
local WATER_BUCKET = "minecraft:water_bucket"

local term
pcall(function() term = require("term") end)
local function clear()
  if term and term.clear then term.clear() else for _ = 1, 12 do print("") end end
end

local pageNo, TOTAL = 0, 4
local function page(title, lines)
  pageNo = pageNo + 1
  clear()
  print("[" .. pageNo .. "/" .. TOTAL .. "] " .. title)
  print("--------------------------")
  for _, l in ipairs(lines) do print(l) end
  print("--------------------------")
  os.sleep(PAGE_SECONDS)
end

local function countHeld(name)
  local total = 0
  for s = 1, (C.INVENTORY_SIZE or 32) do
    local ok, st = pcall(C.inv.getStackInInternalSlot, s)
    if ok and st and st.name == name and st.size then
      total = total + st.size
    end
  end
  return total
end

C.pos.x, C.pos.y, C.pos.z, C.pos.facing = 4, 1, 3, 2

local startX, startZ = C.pos.x, C.pos.z
local emptyBefore = countHeld(EMPTY_BUCKET)

local moves = 0
local origFwd = C.moveForward
C.moveForward = function()
  local ok = origFwd()
  if ok then moves = moves + 1 end
  return ok
end

clear()
print("fill_buckets: running ...")
local ok, nextState = pcall(fill_buckets)
C.moveForward = origFwd

-- PAGE 1: crash / error
local l1 = { "crashed : " .. tostring(not ok) }
if ok then
  l1[#l1 + 1] = "returned: " .. tostring(nextState)
else
  local m = tostring(nextState)
  while #m > 0 do l1[#l1 + 1] = "  " .. m:sub(1, 24); m = m:sub(25) end
end
l1[#l1 + 1] = "error: " .. tostring(C.lastBucketError or "none")
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

-- PAGE 3: taken vs filled
local rep = C.lastBucketReport or {}
page("BUCKETS", {
  "taken from chest : " .. tostring(rep.taken or 0),
  "filled at water  : " .. tostring(rep.filled or 0),
  "",
  ((rep.filled or 0) > 0 and (rep.filled or 0) == (rep.taken or 0))
    and "all buckets filled"
    or ((rep.filled or 0) == 0 and "*** none filled (water below?)"
                               or "*** some buckets not filled"),
})

-- PAGE 4: what's in the inventory now
local water = countHeld(WATER_BUCKET)
local emptyNow = countHeld(EMPTY_BUCKET)
page("INVENTORY", {
  "water buckets : " .. water,
  "empty buckets : " .. emptyNow,
  "empty at start: " .. emptyBefore,
  "",
  (water > 0 and emptyNow == 0) and "carried back full"
    or (emptyNow > 0 and "*** " .. emptyNow .. " still empty"
                      or "*** no water buckets"),
})

clear()
print("=== fill_buckets done ===")
print("crashed : " .. tostring(not ok))
print("at home : " .. tostring(home))
print("taken   : " .. tostring(rep.taken or 0))
print("filled  : " .. tostring(rep.filled or 0))
print("error   : " .. tostring(C.lastBucketError or "none"))
