-- pull_repo.lua
-- Downloads every project file listed in manifest.txt from GitHub into /home,
-- overwriting the local copies. Run it again any time to update to the latest
-- committed versions.
--
-- Bootstrap (only needed once, to get this puller onto the robot):
--   wget -f https://raw.githubusercontent.com/theflaminghat/self-replicating-cellular-automata/refs/heads/main/pull_repo.lua /home/pull_repo.lua
-- Then just run:  pull_repo
--
-- The file list lives in manifest.txt in the repo, so adding or removing a script
-- only means editing that manifest -- pull_repo fetches it fresh every run. To
-- change what gets pulled, edit manifest.txt (one filename per line; blank lines
-- and lines starting with # are ignored) and pull once.
--
-- Requires an Internet Card. A file is only overwritten when its download
-- succeeds, so a failed fetch (404, no connection) leaves the existing copy
-- untouched instead of clobbering it with an error page.

local component = require("component")
local internet  = require("internet")

local BASE = "https://raw.githubusercontent.com/theflaminghat/self-replicating-cellular-automata/refs/heads/main/"
local DEST = "/home/"
local MANIFEST = "manifest.txt"

-- Fetch a URL into a string. Returns data, or nil + error. Guards against
-- GitHub's 404 body so a missing file never overwrites a good local copy.
local function fetch(url)
  local ok, iterator = pcall(internet.request, url)
  if not ok then
    return nil, tostring(iterator)
  end
  local chunks = {}
  local okRead, err = pcall(function()
    for chunk in iterator do
      chunks[#chunks + 1] = chunk
    end
  end)
  if not okRead then
    return nil, tostring(err)
  end
  local data = table.concat(chunks)
  if #data == 0 then
    return nil, "empty response"
  end
  if data == "404: Not Found" or data:match("^404:") then
    return nil, "not found (404)"
  end
  return data
end

local function save(path, data)
  local f, err = io.open(path, "w")
  if not f then
    return false, err
  end
  f:write(data)
  f:close()
  return true
end

local function readLocal(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

-- Turn manifest text into a list of filenames: trim each line, drop blanks and
-- comments (# ...).
local function parseManifest(text)
  local files = {}
  for line in text:gmatch("[^\r\n]+") do
    local name = line:match("^%s*(.-)%s*$")
    if name ~= "" and name:sub(1, 1) ~= "#" then
      files[#files + 1] = name
    end
  end
  return files
end

if not component.isAvailable("internet") then
  io.stderr:write("No Internet Card installed -- cannot pull.\n")
  return
end

-- Get the manifest: fresh from the repo, falling back to the last local copy if
-- the network fetch fails.
local manifestText, mErr = fetch(BASE .. MANIFEST)
if not manifestText then
  manifestText = readLocal(DEST .. MANIFEST)
  if manifestText then
    io.write("manifest fetch failed (" .. tostring(mErr) .. "); using local copy\n")
  else
    io.stderr:write("Could not fetch manifest.txt (" .. tostring(mErr) .. ") and no local copy.\n")
    return
  end
end

local FILES = parseManifest(manifestText)
if #FILES == 0 then
  io.stderr:write("manifest.txt is empty -- nothing to pull.\n")
  return
end

local okCount, failCount = 0, 0
for _, name in ipairs(FILES) do
  io.write(name .. " ... ")
  local data, err = fetch(BASE .. name)
  if not data then
    io.write("FAIL (" .. tostring(err) .. ")\n")
    failCount = failCount + 1
  else
    local wrote, werr = save(DEST .. name, data)
    if wrote then
      io.write("ok (" .. #data .. " b)\n")
      okCount = okCount + 1
    else
      io.write("WRITE FAIL (" .. tostring(werr) .. ")\n")
      failCount = failCount + 1
    end
  end
end

print(string.format("done: %d updated, %d failed", okCount, failCount))
