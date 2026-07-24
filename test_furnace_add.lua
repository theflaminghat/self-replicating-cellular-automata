-- test_furnace_add.lua
-- Runs the real furnace_add state once, starting from the stasis spot (4,1,3).
--
-- It pulls the items and fuel from the tracked chest (0,1,0), loads them into
-- the furnace (2,1,2), and comes back to stasis.
--
-- Short paged output: nothing scrolls off.

local component = require("component")
local robot = require("robot")
local os = require("os")

local C = require("common")
local furnace_add = require("furnace_add")

-- ---- settings ----------------------------------------------------
local PAGE_SECONDS = 15

-- What to smelt. fuelAmount is optional (defaults to ceil(amount/8)).
local JOBS = {
  { item = "minecraft:iron_ore", fuel = "minecraft:coal", amount = 32 },
}
-- ------------------------------------------------------------------

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
print("furnace_add: running ...")
local ok, nextState = pcall(furnace_add, JOBS)
C.moveForward = origFwd

-- PAGE 1: crash or clean return
local l1 = { "crashed : " .. tostring(not ok) }
if ok then
  l1[#l1 + 1] = "returned: " .. tostring(nextState)
else
  local m = tostring(nextState)
  while #m > 0 do l1[#l1 + 1] = "  " .. m:sub(1, 24); m = m:sub(25) end
end
l1[#l1 + 1] = "error: " .. tostring(C.lastFurnaceError or "none")
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

-- PAGE 3: what got loaded
local l3 = {}
for _, r in ipairs(C.lastFurnaceReport or {}) do
  l3[#l3 + 1] = tostring(r.item):sub(1, 20)
  l3[#l3 + 1] = "  in " .. tostring(r.loaded) .. "/" .. tostring(r.wanted) ..
    "  fuel " .. tostring(r.fuel)
  if r.reason then l3[#l3 + 1] = "  " .. r.reason end
end
if #l3 == 0 then l3[1] = "(no jobs ran)" end
while #l3 > 7 do table.remove(l3) end
page("LOADED", l3)

-- PAGE 4: furnace contents now (robot is at stasis, so this is last known)
local l4 = {
  "furnace at " .. C.FURNACE.x .. "," .. C.FURNACE.y .. "," .. C.FURNACE.z,
  "input from top, fuel from side",
  "output from below",
  "",
  "input slot : " .. C.FURNACE_SLOT_INPUT,
  "fuel slot  : " .. C.FURNACE_SLOT_FUEL,
  "output slot: " .. C.FURNACE_SLOT_OUTPUT,
}
page("FURNACE SETUP", l4)

clear()
print("=== furnace_add done ===")
print("crashed : " .. tostring(not ok))
print("at home : " .. tostring(home))
print("error   : " .. tostring(C.lastFurnaceError or "none"))
