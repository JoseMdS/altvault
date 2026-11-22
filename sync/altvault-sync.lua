#!/usr/bin/env lua
-- Merge AltVault data between every account in a WoW install so each account
-- sees every character. Run it with the game CLOSED (WoW overwrites
-- SavedVariables when you log out).
--
-- usage: lua altvault-sync.lua ["/Applications/World of Warcraft/_forever_"]

local root = arg[1] or "/Applications/World of Warcraft/_forever_"
local accountDir = root .. "/WTF/Account"

local function sh(cmd)
  local p = io.popen(cmd)
  local out = p:read("*a")
  p:close()
  return out
end

local function q(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

if not os.getenv("ALTVAULT_TEST") and sh("pgrep -x 'World of Warcraft' || true") ~= "" then
  io.stderr:write("WoW is running. Close the game first, then run the sync again.\n")
  os.exit(1)
end

-- Find accounts (folders in WTF/Account other than SavedVariables)
local accounts = {}
for name in sh("ls " .. q(accountDir)):gmatch("[^\n]+") do
  if name ~= "SavedVariables" and sh("test -d " .. q(accountDir .. "/" .. name) .. " && echo y") ~= "" then
    table.insert(accounts, name)
  end
end

-- Which account owns which character (WTF/Account/<ACC>/<server>/<Name-Realm>)
local owner = {}
for _, acc in ipairs(accounts) do
  for path in sh("find " .. q(accountDir .. "/" .. acc) .. " -mindepth 2 -maxdepth 2 -type d"):gmatch("[^\n]+") do
    local char = path:match("([^/]+)$")
    if char:find("-", 1, true) and not path:find("/SavedVariables/", 1, true) then owner[char] = acc end
  end
end

local function load(file)
  local env = {}
  local chunk = loadfile(file, "t", env)
  if not chunk then return nil end
  pcall(chunk)
  return env.AltVaultDB
end

local merged = { chars = {}, items = {}, version = 1 }
local found = {}
for _, acc in ipairs(accounts) do
  local file = accountDir .. "/" .. acc .. "/SavedVariables/AltVault.lua"
  local db = load(file)
  if db then
    found[acc] = file
    for id, link in pairs(db.items or {}) do merged.items[id] = link end
    for key, c in pairs(db.chars or {}) do
      local cur = merged.chars[key]
      if not cur or (c.updated or 0) > (cur.updated or 0) then merged.chars[key] = c end
    end
  else
    print(("  %s: no AltVault data yet (log in a character on this account first)"):format(acc))
  end
end

for key, c in pairs(merged.chars) do c.account = owner[key] or c.account end

-- Serializer producing WoW-style SavedVariables
local function ser(v, indent, out)
  local t = type(v)
  if t == "string" then out[#out + 1] = string.format("%q", v):gsub("\\\n", "\\n")
  elseif t == "number" or t == "boolean" then out[#out + 1] = tostring(v)
  elseif t == "table" then
    out[#out + 1] = "{\n"
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
      if type(a) == type(b) then return a < b end
      return type(a) == "number"
    end)
    for _, k in ipairs(keys) do
      out[#out + 1] = indent .. "\t["
      out[#out + 1] = type(k) == "string" and string.format("%q", k) or tostring(k)
      out[#out + 1] = "] = "
      ser(v[k], indent .. "\t", out)
      out[#out + 1] = ",\n"
    end
    out[#out + 1] = indent .. "}"
  else out[#out + 1] = "nil" end
end

local out = { "\nAltVaultDB = " }
ser(merged, "", out)
out[#out + 1] = "\n"
local text = table.concat(out)

local n = 0
for _ in pairs(merged.chars) do n = n + 1 end

for _, acc in ipairs(accounts) do
  local file = accountDir .. "/" .. acc .. "/SavedVariables/AltVault.lua"
  if found[acc] then os.execute("cp " .. q(file) .. " " .. q(file .. ".sync-backup")) end
  local f = assert(io.open(file, "w"))
  f:write(text)
  f:close()
  print(("  %s: wrote %d characters"):format(acc, n))
end
print("AltVault sync done.")
