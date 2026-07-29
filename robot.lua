-- robot.lua: entry point. The SAME image boots on both a self-replicating robot and
-- the plain computer it provisions offspring with, so decide which to run here:
--   * on a ROBOT    -> hand control to the scheduler (startup once, then the weave).
--   * on a COMPUTER -> run the computer controller (drive/BIOS cloning + redstone power).
-- Detected via the "robot" component, which only robots expose. The two branches are
-- required lazily so the computer never loads robot-only modules (common.lua does
-- require("robot") at load, which errors on a plain computer).
--
-- All modules (common.lua, recipes.lua, the state files, scheduler.lua,
-- computer_controller.lua) must be in the same directory. Fetch/update them with
-- pull_repo.

local component = require("component")

if component.isAvailable("robot") then
  local scheduler = require("scheduler")
  scheduler()
else
  local controller = require("computer_controller")
  controller()
end
