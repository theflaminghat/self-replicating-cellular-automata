-- diag_generators.lua
-- Read-only check of the fill_generators chest step. It walks stasis->chest
-- (right, forward 3, left, forward 3, right), then reports what it finds
-- WITHOUT taking anything or fueling. Use it to see why coal isn't pulled.
--
-- Run with the robot at stasis (4,1,3).

local component = require("component")
local robot = require("robot")
local os = require("os")

local C = require("common")

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

local function fwd(n)
  for _ = 1, n do C.moveForward() end
end

C.pos.x, C.pos.y, C.pos.z, C.pos.facing = 4, 1, 3, 2

-- Same path the state uses: stasis -> chest.
clear()
print("walking to the chest ...")
C.turnRight(); fwd(3); C.turnLeft(); fwd(3); C.turnRight()

-- PAGE 1: did we arrive, and is an inventory in front?
local sizeOk, size = pcall(C.inv.getInventorySize, C.sides.front)
page("AT THE CHEST?", {
  "pos  : " .. C.pos.x .. "," .. C.pos.y .. "," .. C.pos.z .. " f=" .. C.pos.facing,
  "want : 1,1,0 f=3",
  "",
  "inv in front: " .. tostring((sizeOk and size) or "NONE"),
  (sizeOk and size) and "  chest is reachable"
                     or "  *** nothing to pull from",
})

-- PAGE 2: dump the first few stacks' EXACT name and label.
local lines = {}
if sizeOk and size then
  local shown = 0
  for s = 1, size do
    if shown >= 5 then break end
    local ok, st = pcall(C.inv.getStackInSlot, C.sides.front, s)
    if ok and st and st.name then
      shown = shown + 1
      lines[#lines + 1] = "name : " .. tostring(st.name):sub(1, 22)
      lines[#lines + 1] = "label: " .. tostring(st.label):sub(1, 22)
      lines[#lines + 1] = ""
    end
  end
  if shown == 0 then lines[1] = "chest is empty" end
else
  lines[1] = "no chest in front"
end
while #lines > 9 do table.remove(lines) end
page("CHEST CONTENTS", lines)

-- PAGE 3: does the state's matcher recognize anything as coal?
local COAL_NAME = "minecraft:coal"
local COAL_LABEL = "Coal"
local function isCoal(st)
  if not st then return false end
  if st.name == COAL_NAME then return true end
  if st.label == COAL_LABEL then return true end
  return false
end

local matched, total = 0, 0
if sizeOk and size then
  for s = 1, size do
    local ok, st = pcall(C.inv.getStackInSlot, C.sides.front, s)
    if ok and st and st.name then
      total = total + 1
      if isCoal(st) then matched = matched + 1 end
    end
  end
end
page("COAL MATCH", {
  "looking for:",
  "  name  = minecraft:coal",
  "  label = Coal",
  "",
  "stacks in chest : " .. total,
  "matched coal: " .. matched,
  (matched > 0) and "MATCH OK" or "*** NO MATCH - see page 2",
})

-- PAGE 3b (extra): actually attempt one suck and report what happens.
if sizeOk and size then
  -- find the first coal slot in the chest
  local chSlot = nil
  for s = 1, size do
    local ok, st = pcall(C.inv.getStackInSlot, C.sides.front, s)
    if ok and isCoal(st) then chSlot = s break end
  end
  local lines = {}
  if not chSlot then
    lines[1] = "no coal slot found"
  else
    -- pick an empty robot slot
    local dest = nil
    for s = 1, (C.INVENTORY_SIZE or 32) do
      local ok, st = pcall(C.inv.getStackInInternalSlot, s)
      if ok and not st then dest = s break end
    end
    lines[#lines+1] = "chest slot : " .. chSlot
    lines[#lines+1] = "dest slot  : " .. tostring(dest)
    C.robot.select(dest or 1)
    local before = 0
    do local ok, st = pcall(C.inv.getStackInInternalSlot, dest or 1)
       if ok and st and st.size then before = st.size end end
    local r1, r2 = pcall(C.inv.suckFromSlot, C.sides.front, chSlot, 1)
    lines[#lines+1] = "suck pcall : " .. tostring(r1)
    lines[#lines+1] = "suck ret   : " .. tostring(r2)
    local after = 0
    do local ok, st = pcall(C.inv.getStackInInternalSlot, dest or 1)
       if ok and st and st.size then after = st.size end end
    lines[#lines+1] = "dest before: " .. before
    lines[#lines+1] = "dest after : " .. after
    lines[#lines+1] = (after > before) and "SUCK WORKED" or "*** SUCK DID NOTHING"
  end
  TOTAL = TOTAL + 1
  page("SUCK TEST", lines)
end

-- Return to stasis (chest -> stasis): right, forward 3, right, forward 3, right.
C.turnRight(); fwd(3); C.turnRight(); fwd(3); C.turnRight()

clear()
print("=== diag done ===")
print("at chest : " .. tostring(sizeOk and size ~= nil))
print("matched  : " .. matched)
print("back at stasis: " .. tostring(C.pos.x == 4 and C.pos.z == 3))
