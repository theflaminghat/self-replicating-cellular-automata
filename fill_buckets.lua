local C = require("common")

local robot = C.robot
local pos = C.pos
local inv = C.inv
local sides = C.sides
local batteryLevel = C.batteryLevel

local EMPTY_BUCKET_NAME = "minecraft:bucket"
local WATER_BUCKET_NAME = "minecraft:water_bucket"
local EMPTY_BUCKET_LABEL = "Bucket"
local WATER_BUCKET_LABEL = "Water Bucket"
local FETCH_SLOT = 22

local function fwd(n)
  for _ = 1, n do C.moveForward() end
end

local function up(n)
  for _ = 1, n do C.moveUp() end
end

local function down(n)
  for _ = 1, n do C.moveDown() end
end

local function facingInventory()
  local ok, size = pcall(inv.getInventorySize, sides.front)
  if ok and size then return size end
  return nil
end

local function isEmptyBucket(st)
  if not st then return false end
  if st.name == EMPTY_BUCKET_NAME then return true end
  if st.label == EMPTY_BUCKET_LABEL then return true end
  return false
end

-- Robot -> in front of the water. From stasis: to the chest, take buckets, then
-- over the sugarcane to sit above the water source (5,1,7).
local function gotoChestFromStasis()
  C.gotoChestFromStasis()
end

-- Chest access (1,1,0 facing -X) -> above the water (5,2,7 facing +X).
-- right, forward 7, right, up 4, forward 4, down 3.
local function gotoWaterFromChest()
  C.turnRight()
  fwd(7)
  C.turnRight()
  up(4)
  fwd(4)
  down(3)
  -- One more step forward, then turn around, to line up the fill.
  fwd(1)
  C.turnAround()
end


local function pullEmptyBuckets()
  local size = facingInventory()
  if not size then return 0 end
  local got = 0
  for s = 1, size do
    local ok, st = pcall(inv.getStackInSlot, sides.front, s)
    if ok and isEmptyBucket(st) and st.size and st.size > 0 then
      -- Capture the count BEFORE sucking: suckFromSlot may return the moved
      -- count or just a boolean, and the stack table can be mutated in place,
      -- so reading st.size afterward is unreliable.
      local want = st.size
      robot.select(FETCH_SLOT)
      local moved = inv.suckFromSlot(sides.front, s, want)
      if moved then
        got = got + (type(moved) == "number" and moved or want)
      end
    end
  end
  return got
end

local function countEmptyBuckets()
  local total = 0
  for s = 1, (C.INVENTORY_SIZE or 32) do
    local ok, st = pcall(inv.getStackInInternalSlot, s)
    if ok and isEmptyBucket(st) and st.size then
      total = total + st.size
    end
  end
  return total
end

local function findEmptyBucketSlot()
  for s = 1, (C.INVENTORY_SIZE or 32) do
    local ok, st = pcall(inv.getStackInInternalSlot, s)
    if ok and isEmptyBucket(st) and st.size and st.size > 0 then
      return s
    end
  end
  return nil
end

-- Fill every empty bucket by moving ONE to a scratch slot, equipping it, using
-- it on the water below, and swapping it back. Empty buckets stack (to 16) but
-- water buckets do not, so each must be filled individually. Water is directly
-- BELOW the robot, so use useDown().
local SPLIT_SLOT = 23
local STORE_START = 24

local function fillAllBuckets()
  local filled = 0
  local guard = 0
  while guard < 256 do
    guard = guard + 1
    if countEmptyBuckets() == 0 then break end
    if batteryLevel() < 0.2 then break end

    local slot = findEmptyBucketSlot()
    if not slot then break end

    -- Move exactly ONE empty bucket into the (empty) scratch slot so equip
    -- picks up a single bucket rather than the whole stack.
    robot.select(slot)
    if not pcall(robot.transferTo, SPLIT_SLOT, 1) then break end

    -- The single empty bucket now lives in SPLIT_SLOT. Fill it: for each attempt
    -- equip it into the tool slot, right-click the water below, then equip it
    -- back to SPLIT_SLOT and check whether it actually became a water bucket.
    -- The return string ("item_used"/"item_placed") is unreliable for buckets --
    -- OC often reports success while nothing happened -- so we judge by the
    -- item, not the return. Buckets behave differently with the sneaky flag, so
    -- we try variants. Every attempt does equip/use/equip, so SPLIT_SLOT always
    -- holds the bucket at the top of each iteration (clean parity).
    local function attemptFill(fillFn)
      pcall(inv.equip)      -- SPLIT_SLOT bucket -> tool slot
      pcall(fillFn)         -- right-click the water
      pcall(inv.equip)      -- tool slot bucket -> SPLIT_SLOT
      local ok, st = pcall(inv.getStackInInternalSlot, SPLIT_SLOT)
      return ok and st and (st.name == WATER_BUCKET_NAME or st.label == WATER_BUCKET_LABEL)
    end

    robot.select(SPLIT_SLOT)
    local success =
         attemptFill(function() return robot.use(sides.down) end)
      or attemptFill(function() return robot.useDown() end)
      or attemptFill(function() return robot.useDown(sides.down, true) end)

    if success then
      filled = filled + 1
      -- Move the full water bucket into its own storage slot so SPLIT_SLOT is
      -- empty again for the next bucket (water buckets don't stack).
      robot.select(SPLIT_SLOT)
      pcall(robot.transferTo, STORE_START + filled - 1)
    else
      -- Couldn't fill; put the still-empty bucket back and stop to avoid looping.
      robot.select(SPLIT_SLOT)
      pcall(robot.transferTo, slot)
      break
    end
  end
  return filled
end

-- Fill point (6,2,7 facing -X) -> stasis (4,1,3 facing charger), staying high
-- over the sugarcane. up 3, forward 2, left, forward 4, down 4.
local function gotoStasisFromWater()
  up(3)
  fwd(2)
  C.turnLeft()
  fwd(4)
  down(4)
end



local function fill_buckets()
  if batteryLevel() < 0.25 then
    return "returning"
  end

  C.lastBucketError = nil
  C.lastBucketReport = { taken = 0, filled = 0 }

  -- Stasis -> chest, take empty buckets.
  gotoChestFromStasis()
  if not facingInventory() then
    C.lastBucketError = "not facing the tracked chest"
    C.gotoStasisFromChest()
    return "stasis"
  end
  C.lastBucketReport.taken = pullEmptyBuckets()
  if C.lastBucketReport.taken == 0 then
    C.lastBucketError = "no empty buckets in chest"
    C.gotoStasisFromChest()
    return "stasis"
  end

  -- Chest -> over the water, fill.
  gotoWaterFromChest()
  C.lastBucketReport.filled = fillAllBuckets()
  if C.lastBucketReport.filled == 0 then
    C.lastBucketError = "filled no buckets (water below?)"
  end

  -- Fill point -> stasis directly. The filled buckets stay in inventory.
  gotoStasisFromWater()
  return "stasis"
end

C.fillBuckets = fill_buckets

return fill_buckets
