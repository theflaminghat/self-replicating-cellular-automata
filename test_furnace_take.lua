-- test_furnace_take.lua
-- Runs the real furnace_take state once, starting from the stasis spot (4,1,3).
--
-- It takes whatever is in the furnace output slot (2,1,2), deposits it in the
-- tracked chest (0,1,0), and comes back to stasis.
--
-- Short paged output: nothing scrolls off.

local component = require("component")
local robot = require("robot")
local os = require("os")

local C = require("common")
local furnace_take = require("furnace_take")

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
print("furnace_take: running ...")
local ok, nextState = pcall(furnace_take)
C.moveForward = origFwd

-- PAGE 1: crash / error
local l1 = { "crashed : " .. tostring(not ok) }
if ok then
  l1[#l1 + 1] = "returned: " .. tostring(nextState)
else
  local m = tostring(nextState)
  while #m > 0 do l1[#l1 + 1] = "  " .. m:sub(1, 24); m = m:sub(25) end
end
l1[#l1 + 1] = "error: " .. tostring(C.lastFurnaceError or "none")
l1[#l1 + 1] = ""
l1[#l1 + 1] = "'output is empty' just means"
l1[#l1 + 1] = "nothing has smelted yet"
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

-- PAGE 3: what moved
local t = C.lastFurnaceTake or {}
page("TAKEN", {
  "item : " .. tostring(t.item or "none"),
  "taken: " .. tostring(t.taken or 0),
  "",
  ((t.taken or 0) > 0) and "kept in robot inventory"
                        or "nothing taken",
})

clear()
print("=== furnace_take done ===")
print("crashed : " .. tostring(not ok))
print("at home : " .. tostring(home))
print("taken   : " .. tostring(t.taken or 0))
print("error   : " .. tostring(C.lastFurnaceError or "none"))
