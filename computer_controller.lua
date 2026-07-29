-- computer_controller.lua
-- Runs on a plain COMPUTER (not a robot); robot.lua dispatches here when no "robot"
-- component is present. Two jobs:
--   1. Provisioning: clone this computer's boot drive, and copy its EEPROM BIOS, onto
--      any freshly INSERTED filesystem / EEPROM -- how an offspring's drive + BIOS get
--      set up.
--   2. Assembler + redstone power: while a redstone card is present, keep the wake
--      threshold at 10 so a redstone signal >= 10 powers the computer on while it is off.
--      When it then sees a redstone signal while running, it starts the electronics
--      assembler (which runs on its own power) and shuts itself down.

local component = require("component")
local computer  = require("computer")
local event     = require("event")

-- A redstone signal >= this powers the computer on (wake threshold) while it is off.
local WAKE_THRESHOLD = 10

local function controller()
  --------------------------------------------------------------------
  -- SETUP
  --------------------------------------------------------------------

  -- Boot drive = source for disk cloning.
  local source = component.proxy(computer.getBootAddress())

  -- Source EEPROM = source for BIOS copying.
  local sourceEeprom = component.eeprom
  local sourceBios   = sourceEeprom.get()
  local sourceLabel  = sourceEeprom.getLabel()
  local sourceData   = sourceEeprom.getData()

  -- Track known components so we only act on newly inserted ones.
  local knownEeprom = {}
  for addr in component.list("eeprom") do knownEeprom[addr] = true end

  local knownFs = {}
  for addr in component.list("filesystem") do knownFs[addr] = true end

  --------------------------------------------------------------------
  -- REDSTONE POWER CONTROL
  --------------------------------------------------------------------

  -- Apply the wake threshold so a redstone signal of >= WAKE_THRESHOLD boots the
  -- computer while it is off. Called at startup and whenever a redstone card appears.
  local function setRedstoneWake()
    if component.isAvailable("redstone") then
      local ok, err = pcall(function() component.redstone.setWakeThreshold(WAKE_THRESHOLD) end)
      if ok then
        print("Redstone wake threshold set to " .. WAKE_THRESHOLD .. ".")
      else
        print("Failed to set wake threshold: " .. tostring(err))
      end
    end
  end

  --------------------------------------------------------------------
  -- DISK CLONE HELPERS
  --------------------------------------------------------------------

  local function join(path, name)
    if path:sub(-1) ~= "/" then path = path .. "/" end
    return path .. name
  end

  local function copyDir(src, dst, path)
    local files = src.list(path)
    if not files then
      print("  list() returned nil for: " .. path)
      return
    end
    for i = 1, #files do
      local name = files[i]
      local isDir = name:sub(-1) == "/"
      name = name:gsub("/$", "")
      local fullPath = join(path, name)

      if isDir or src.isDirectory(fullPath) then
        dst.makeDirectory(fullPath)
        copyDir(src, dst, fullPath)
      else
        local inH, e1 = src.open(fullPath, "r")
        local outH, e2 = dst.open(fullPath, "w")
        if not inH then print("  open read failed: " .. fullPath .. " " .. tostring(e1)) end
        if not outH then print("  open write failed: " .. fullPath .. " " .. tostring(e2)) end
        if inH and outH then
          local count = 0
          while true do
            local chunk = src.read(inH, 4096)
            if not chunk then break end
            dst.write(outH, chunk)
            count = count + #chunk
          end
          src.close(inH)
          dst.close(outH)
          print("  copied " .. fullPath .. " (" .. count .. " bytes)")
        end
      end
    end
  end

  local function cloneTo(address)
    local target = component.proxy(address)
    if not target then print("no proxy for " .. address) return end
    if target.address == source.address then print("same as source, skip") return end
    if target.isReadOnly() then print("read-only, skip") return end
    print("Cloning " .. source.address .. " -> " .. target.address)
    copyDir(source, target, "/")
    print("Done. Space used on target: " .. target.spaceUsed() .. "/" .. target.spaceTotal())
  end

  --------------------------------------------------------------------
  -- BIOS COPY HELPER
  --------------------------------------------------------------------

  local function copyBios(addr)
    local target = component.proxy(addr)
    print("New EEPROM detected: " .. addr:sub(1, 8))
    local ok, err = pcall(function()
      target.set(sourceBios)
      if sourceLabel then target.setLabel(sourceLabel) end
      if sourceData and #sourceData > 0 then target.setData(sourceData) end
    end)
    if ok then
      print("BIOS copied successfully to " .. addr:sub(1, 8))
    else
      print("Failed to copy: " .. tostring(err))
    end
  end

  --------------------------------------------------------------------
  -- ASSEMBLER
  --------------------------------------------------------------------

  -- Start the electronics assembler if one is attached. It runs on its own power once
  -- started, so the computer is free to shut down immediately afterward.
  local function tryAssemblerStart()
    if component.isAvailable("assembler") then
      local ok, err = pcall(function() component.assembler.start() end)
      if ok then
        print("Assembler started.")
      else
        print("Assembler start failed: " .. tostring(err))
      end
    else
      print("No assembler available.")
    end
  end

  --------------------------------------------------------------------
  -- MAIN LOOP
  --------------------------------------------------------------------

  print("Computer controller running.")
  print("Boot drive: " .. source.address)
  print("Source BIOS size: " .. #sourceBios .. " bytes")
  print("Redstone: wake threshold " .. WAKE_THRESHOLD .. "; a redstone signal starts the assembler, then powers off.")
  print("Insert EEPROM/drive to copy.")
  setRedstoneWake()

  while true do
    local ev = { event.pull() }
    local name = ev[1]

    if name == "component_added" then
      local addr, ctype = ev[2], ev[3]
      print("component_added: " .. tostring(addr) .. " type=" .. tostring(ctype))

      if ctype == "eeprom" then
        if not knownEeprom[addr] and addr ~= sourceEeprom.address then
          knownEeprom[addr] = true
          os.sleep(0.2)
          copyBios(addr)
        end

      elseif ctype == "filesystem" then
        if not knownFs[addr] and addr ~= source.address then
          knownFs[addr] = true
          os.sleep(0.5)
          local ok, err = pcall(cloneTo, addr)
          if not ok then print("Error: " .. tostring(err)) end
        end

      elseif ctype == "redstone" then
        -- A redstone card was just inserted: (re)apply the wake threshold.
        setRedstoneWake()
      end

    elseif name == "component_removed" then
      local addr, ctype = ev[2], ev[3]
      if ctype == "eeprom" then knownEeprom[addr] = nil end
      if ctype == "filesystem" then knownFs[addr] = nil end

    elseif name == "redstone_changed" then
      -- ev = { "redstone_changed", address, side, oldValue, newValue }. An incoming
      -- signal (on any side) while we're running means "do the job, then power off":
      -- start the assembler (which then runs on its own power) and shut down. The wake
      -- threshold above turns us back on the next time redstone rises to 10.
      local newValue = ev[5]
      if newValue and newValue > 0 then
        print("Redstone signal detected -- starting assembler, then shutting down.")
        tryAssemblerStart()
        computer.shutdown()
      end
    end
  end
end

return controller
