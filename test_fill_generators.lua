-- test_fill_generators.lua
-- Runs the real fill_generators state once, starting from the stasis spot
-- (4,1,3).
--
-- It goes to the tracked chest (0,1,0), takes coal, fills the two coal
-- generators at (5,1,0) and (6,1,0), and comes back to stasis.
--
-- Short paged output: nothing scrolls off.

local component = require("component")
local robot = require("robot")
local os = require("os")

local C = require("common")
local fill_generators = require("fill_generators")

-- ---- settings ----------------------------------------------------
local PAGE_SECONDS = 15
-- ------------------------------------------------------------------

local COAL = "minecraft:coal"

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

local function heldCoal()
  local total = 0
  for s = 1, (C.INVENTORY_SIZE or 32) do
    local ok, st = pcall(C.inv.getStackInInternalSlot, s)
    if ok and st and st.name == COAL and st.size then
      total = total + st.size
    end
  end
  return total
end

C.pos.x, C.pos.y, C.pos.z, C.pos.facing = 4, 1, 3, 2

local startX, startZ = C.pos.x, C.pos.z
local coalBefore = heldCoal()

local moves = 0
local origFwd = C.moveForward
C.moveForward = function()
  local ok = origFwd()
  if ok then moves = moves + 1 end
  return ok
end

clear()
print("fill_generators: running ...")
local ok, nextState = pcall(fill_generators)
C.moveForward = origFwd

-- PAGE 1: crash / error
local l1 = { "crashed : " .. tostring(not ok) }
if ok then
  l1[#l1 + 1] = "returned: " .. tostring(nextState)
else
  local m = tostring(nextState)
  while #m > 0 do l1[#l1 + 1] = "  " .. m:sub(1, 24); m = m:sub(25) end
end
l1[#l1 + 1] = "error: " .. tostring(C.lastGeneratorError or "none")
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

-- PAGE 3: how much went into each generator
local rep = C.lastGeneratorReport or {}
local fueled = rep.fueled or { 0, 0 }
page("FUELED", {
  "target each : " .. tostring(C.GENERATOR_TARGET),
  "",
  "gen (5,1,0) : " .. tostring(fueled[1] or 0),
  "gen (6,1,0) : " .. tostring(fueled[2] or 0),
  "",
  ((fueled[1] or 0) + (fueled[2] or 0) > 0) and "coal delivered"
                                             or "nothing delivered",
})

-- PAGE 4: coal accounting
local coalAfter = heldCoal()
page("COAL", {
  "held before: " .. coalBefore,
  "held after : " .. coalAfter,
  "leftover carried back to stasis",
  "",
  (coalAfter == 0) and "none left over"
                        or (coalAfter .. " spare in inventory"),
})

clear()
print("=== fill_generators done ===")
print("crashed : " .. tostring(not ok))
print("at home : " .. tostring(home))
print("gen1/gen2: " .. tostring(fueled[1] or 0) .. " / " .. tostring(fueled[2] or 0))
print("error   : " .. tostring(C.lastGeneratorError or "none"))
