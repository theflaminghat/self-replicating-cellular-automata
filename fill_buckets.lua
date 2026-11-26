-- fill_buckets.lua
-- Fill empty buckets with water for an offspring's build payload. From stasis: take
-- empty buckets from the tracked chests, fly over the sugarcane to sit above the
-- base's water source, fill them one at a time, and return to stasis carrying the
-- full ones. `want` is how many to fill (default: one per C.WATER_SLOTS slot).
--
-- The base places water at (4,1,7) and (6,1,7); the gap between them, (5,1,7), has
-- two source neighbours over a solid floor, so it becomes a source too -- an endless
-- one. Taking water from that MIDDLE block refills it instantly. Taking it from an end
-- block (as this used to, from (6,1,7)) leaves only flowing water there, which never
-- turns back into a source: one bucket, then nothing ever again.

local C = require("common")

local robot = C.robot
local inv = C.inv
local sides = C.sides
local batteryLevel = C.batteryLevel

local EMPTY_BUCKET_NAME = "minecraft:bucket"
local WATER_BUCKET_NAME = "minecraft:water_bucket"
local EMPTY_BUCKET_LABEL = "Bucket"
local WATER_BUCKET_LABEL = "Water Bucket"

-- Surface route: mine through anything blocking the path (see C.travelForward) instead of
-- silently stalling and losing sync with the scripted step sequence.
local function fwd(n)
  for _ = 1, n do C.travelForward() end
end

local function up(n)
  for _ = 1, n do C.moveUp() end
end

local function down(n)
  for _ = 1, n do C.moveDown() end
end

local facingInventory = C.facingFront

local function isEmptyBucket(st)
  if not st then return false end
  if st.name == EMPTY_BUCKET_NAME then return true end
  if st.label == EMPTY_BUCKET_LABEL then return true end
  return false
end

local function isWaterBucket(st)
  if not st then return false end
  return st.name == WATER_BUCKET_NAME or st.label == WATER_BUCKET_LABEL
end

local function countEmptyBuckets()
  local total = 0
  for s = 1, (C.INVENTORY_SIZE or 32) do
    if not C.isReserveSlot(s) then
      local ok, st = pcall(inv.getStackInInternalSlot, s)
      if ok and isEmptyBucket(st) and st.size then
        total = total + st.size
      end
    end
  end
  return total
end

local function findEmptyBucketSlot()
  for s = 1, (C.INVENTORY_SIZE or 32) do
    if not C.isReserveSlot(s) then
      local ok, st = pcall(inv.getStackInInternalSlot, s)
      if ok and isEmptyBucket(st) and st.size and st.size > 0 then
        return s
      end
    end
  end
  return nil
end

-- Pull up to `need` empty buckets from the chest in front; returns how many came over.
-- Each pull lands in a genuinely empty slot: suckFromSlot targets the SELECTED slot, and
-- an occupied one makes it fail silently. The count is read off that one slot (before
-- and after) rather than by rescanning the whole inventory per chest slot.
local function pullEmptyBuckets(need)
  local size = facingInventory()
  if not size then return 0 end
  local got = 0
  for s = 1, size do
    if got >= need then break end
    local ok, st = pcall(inv.getStackInSlot, sides.front, s)
    if ok and isEmptyBucket(st) and st.size and st.size > 0 then
      local dest = C.freeSlot()
      if not dest then break end
      robot.select(dest)
      pcall(inv.suckFromSlot, sides.front, s, math.min(need - got, st.size))
      local okA, after = pcall(inv.getStackInInternalSlot, dest)
      got = got + ((okA and isEmptyBucket(after) and after.size) or 0)
    end
  end
  return got
end

-- Chest access (1,1,0 facing -X) -> above the middle water source, (5,2,7) facing +X.
-- right, forward 7, right, up 4, forward 4, down 3.
local function gotoWaterFromChest()
  C.turnRight()
  fwd(7)
  C.turnRight()
  up(4)
  fwd(4)
  down(3)
end

-- Fill point (5,2,7 facing +X) -> stasis (4,1,3 facing the charger), staying high over
-- the sugarcane: up 3, turn around, forward 1, left, forward 4, down 4.
local function gotoStasisFromWater()
  up(3)
  C.turnAround()
  fwd(1)
  C.turnLeft()
  fwd(4)
  down(4)
end

-- Equip the single bucket in the selected slot, right-click the water below with
-- `fillFn`, and equip it back. The use() return string ("item_used"/"item_placed") is
-- unreliable for buckets -- OC often reports success while nothing happened -- so judge
-- by the item: did the bucket in `slot` become a water bucket? Every attempt does
-- equip/use/equip, so `slot` holds the bucket again afterwards either way.
local function attemptFill(slot, fillFn)
  pcall(inv.equip)      -- bucket -> tool slot (the pickaxe comes out into `slot`)
  pcall(fillFn)         -- right-click the water
  pcall(inv.equip)      -- bucket back into `slot`, pickaxe back into the tool slot
  local ok, st = pcall(inv.getStackInInternalSlot, slot)
  return ok and isWaterBucket(st)
end

-- Fill up to `want` held empty buckets, one at a time: empty buckets stack but water
-- buckets don't, and equip must pick up a single bucket, not the whole stack. Each one
-- is split into its own empty slot -- picked fresh each time, since a fixed scratch slot
-- could already hold something and transferTo into an occupied slot just fails -- and it
-- stays there once filled.
local function fillBuckets(want)
  local filled = 0
  while filled < want do
    if batteryLevel() < 0.2 then break end
    local from = findEmptyBucketSlot()
    if not from then break end
    local split = C.freeSlot()
    if not split then break end
    robot.select(from)
    local okT, moved = pcall(robot.transferTo, split, 1)
    if not (okT and moved) then break end

    robot.select(split)
    -- Buckets behave differently with the sneaky flag, so try the variants in turn.
    local success =
         attemptFill(split, function() return robot.use(sides.down) end)
      or attemptFill(split, function() return robot.useDown() end)
      or attemptFill(split, function() return robot.useDown(sides.down, true) end)

    if success then
      filled = filled + 1
    else
      -- Couldn't fill: put the still-empty bucket back and stop rather than loop.
      robot.select(split)
      pcall(robot.transferTo, from)
      break
    end
  end
  return filled
end

local function fill_buckets(want)
  want = want or #C.WATER_SLOTS
  if batteryLevel() < 0.25 then
    return "returning"
  end

  C.lastBucketError = nil
  C.lastBucketReport = { taken = 0, filled = 0 }

  -- Stasis -> chest. Take empty buckets from all 3 tracked chests -- they can sit in
  -- any of them, and reading only the level-1 chest could come up empty.
  C.gotoChestFromStasis()
  if not facingInventory() then
    C.lastBucketError = "not facing the tracked chest"
    C.gotoStasisFromChest()
    return "stasis"
  end
  local held = countEmptyBuckets()
  local heldBefore = held
  C.forEachTrackedChest(function()
    if held < want then held = held + pullEmptyBuckets(want - held) end
  end)
  C.lastBucketReport.taken = held - heldBefore
  if held == 0 then
    C.lastBucketError = "no empty buckets in chest"
    C.gotoStasisFromChest()
    return "stasis"
  end

  -- Chest -> over the water, fill.
  gotoWaterFromChest()
  C.lastBucketReport.filled = fillBuckets(want)
  if C.lastBucketReport.filled == 0 then
    C.lastBucketError = "filled no buckets (water below?)"
  end

  -- Fill point -> stasis directly. The filled buckets stay in inventory.
  gotoStasisFromWater()
  return "stasis"
end

C.fillBuckets = fill_buckets

return fill_buckets
