-- AltVault: track bags, bank, equipped items and gold for every character.
-- Data lives in AltVaultDB (account-wide SavedVariables). Use the sync script
-- (AltVault/sync/altvault-sync.lua) to share data between two accounts.

local ADDON, ns = ...
local DB
local playerKey
local bankOpen = false

------------------------------------------------------------------------
-- Compatibility helpers
------------------------------------------------------------------------
local BI = (Enum and Enum.BagIndex) or {}

local GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots

local function GetSlot(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info then return info.itemID, info.stackCount, info.hyperlink end
    return nil
  end
  local _, count, _, _, _, _, link, _, _, id = GetContainerItemInfo(bag, slot)
  return id, count, link
end

local GetIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon

local BAGS = { BI.Backpack or 0, BI.Bag_1 or 1, BI.Bag_2 or 2, BI.Bag_3 or 3, BI.Bag_4 or 4 }
if BI.ReagentBag then table.insert(BAGS, BI.ReagentBag) end
if BI.Keyring then table.insert(BAGS, BI.Keyring) end

local BANK = {}
if BI.CharacterBankTab_1 then
  for i = 1, 9 do
    local idx = BI["CharacterBankTab_" .. i]
    if idx then table.insert(BANK, idx) end
  end
else
  table.insert(BANK, BANK_CONTAINER or -1)
  for i = 1, (NUM_BANKBAGSLOTS or 7) do table.insert(BANK, (NUM_BAG_SLOTS or 4) + i) end
end

local LOCATIONS = { "bags", "bank", "mail", "equipped" }
local LOCATION_LABEL = { bags = "bags", bank = "bank", mail = "mail", equipped = "worn" }

------------------------------------------------------------------------
-- Formatting
------------------------------------------------------------------------
local function ClassColored(char, text)
  local c = char and char.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[char.class]
  if not c then return text end
  local hex = c.colorStr or string.format("ff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
  return "|c" .. hex .. text .. "|r"
end

local function Money(copper)
  copper = copper or 0
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  return string.format("|cffffd700%dg|r |cffc7c7cf%ds|r |cffeda55f%dc|r", g, s, c)
end

local function ShortName(key)
  return (key:match("^(.-)%-") or key)
end

local function Ago(t)
  if not t then return "never" end
  local d = time() - t
  if d < 3600 then return math.floor(d / 60) .. "m ago" end
  if d < 86400 then return math.floor(d / 3600) .. "h ago" end
  return math.floor(d / 86400) .. "d ago"
end

------------------------------------------------------------------------
-- Scanning
------------------------------------------------------------------------
local function Remember(id, link)
  if id and link then DB.items[id] = link end
end

local function ScanContainers(list)
  local counts, slots = {}, 0
  for _, bag in ipairs(list) do
    local n = GetNumSlots(bag) or 0
    slots = slots + n
    for slot = 1, n do
      local id, count, link = GetSlot(bag, slot)
      if id then
        counts[id] = (counts[id] or 0) + (count or 1)
        Remember(id, link)
      end
    end
  end
  return counts, slots
end

local function ScanEquipped()
  local counts = {}
  for slot = 1, 19 do
    local id = GetInventoryItemID("player", slot)
    if id then
      counts[id] = (counts[id] or 0) + 1
      Remember(id, GetInventoryItemLink("player", slot))
    end
  end
  return counts
end

local function Me()
  local c = DB.chars[playerKey]
  if not c then
    c = {}
    DB.chars[playerKey] = c
  end
  return c
end

local function UpdateBasics()
  local c = Me()
  c.class = select(2, UnitClass("player"))
  c.level = UnitLevel("player")
  c.faction = UnitFactionGroup("player")
  c.money = GetMoney()
  c.updated = time()
end

local function ScanBags()
  local c = Me()
  c.bags = ScanContainers(BAGS)
  c.equipped = ScanEquipped()
  UpdateBasics()
end

local function ScanBank()
  if not bankOpen then return end
  local counts, slots = ScanContainers(BANK)
  if slots == 0 then return end -- bank not readable, keep the old snapshot
  local c = Me()
  c.bank = counts
  c.bankUpdated = time()
  UpdateBasics()
end

------------------------------------------------------------------------
-- Queries
------------------------------------------------------------------------
-- Returns total, { {key, char, where, count}, ... } for one itemID
local function WhoHas(id)
  local total, rows = 0, {}
  for key, char in pairs(DB.chars) do
    for _, loc in ipairs(LOCATIONS) do
      local n = char[loc] and char[loc][id]
      if n and n > 0 then
        total = total + n
        table.insert(rows, { key = key, char = char, where = loc, count = n })
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.key < b.key
  end)
  return total, rows
end

local function NameOf(link)
  return link and link:match("%[(.-)%]")
end

local function Search(query)
  query = (query or ""):lower()
  local results = {}
  if query == "" then return results end
  for id, link in pairs(DB.items) do
    local name = NameOf(link)
    if name and name:lower():find(query, 1, true) then
      local total = WhoHas(id)
      if total > 0 then table.insert(results, { id = id, link = link, name = name, total = total }) end
    end
  end
  table.sort(results, function(a, b) return a.name < b.name end)
  return results
end

------------------------------------------------------------------------
-- Tooltip
------------------------------------------------------------------------
local function AddTooltipLines(tt, id)
  if not id or not DB then return end
  local total, rows = WhoHas(id)
  if total == 0 then return end
  tt:AddLine(" ")
  tt:AddDoubleLine("|cff33ff99AltVault|r", "Total: " .. total, 1, 1, 1, 1, 1, 1)
  local per = {}
  local order = {}
  for _, r in ipairs(rows) do
    if not per[r.key] then
      per[r.key] = { char = r.char, parts = {}, n = 0 }
      table.insert(order, r.key)
    end
    per[r.key].n = per[r.key].n + r.count
    table.insert(per[r.key].parts, LOCATION_LABEL[r.where] .. " " .. r.count)
  end
  for _, key in ipairs(order) do
    local p = per[key]
    tt:AddDoubleLine(ClassColored(p.char, ShortName(key)), table.concat(p.parts, ", "), 1, 1, 1, 0.8, 0.8, 0.8)
  end
  tt:Show()
end

local function HookTooltips()
  if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
      if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
      AddTooltipLines(tt, data and data.id)
    end)
  else
    local function hook(tt)
      local _, link = tt:GetItem()
      local id = link and tonumber(link:match("item:(%d+)"))
      AddTooltipLines(tt, id)
    end
    GameTooltip:HookScript("OnTooltipSetItem", hook)
    ItemRefTooltip:HookScript("OnTooltipSetItem", hook)
  end
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local frame

local function SetBody(text)
  frame.body:SetText(text)
  frame.child:SetHeight(frame.body:GetStringHeight() + 20)
  frame.scroll:SetVerticalScroll(0)
end

local function ShowSearch(query)
  local results = Search(query)
  if #results == 0 then
    SetBody(query == "" and "|cff888888Type an item name above.|r" or "|cff888888No matches for '" .. query .. "'.|r")
    return
  end
  local lines = {}
  local shown = 0
  for _, r in ipairs(results) do
    shown = shown + 1
    if shown > 60 then
      table.insert(lines, "|cff888888... " .. (#results - 60) .. " more, refine your search.|r")
      break
    end
    local icon = GetIcon(r.id)
    table.insert(lines, (icon and ("|T" .. icon .. ":16|t ") or "") .. r.link .. "  |cffffffffx" .. r.total .. "|r")
    local _, rows = WhoHas(r.id)
    for _, row in ipairs(rows) do
      table.insert(lines, string.format("      %s  |cffaaaaaa%s|r  %d",
        ClassColored(row.char, ShortName(row.key)), LOCATION_LABEL[row.where], row.count))
    end
  end
  SetBody(table.concat(lines, "\n"))
end

local function ShowCharacters()
  local keys = {}
  local total = 0
  for key, c in pairs(DB.chars) do
    table.insert(keys, key)
    total = total + (c.money or 0) + (c.mailMoney or 0)
  end
  table.sort(keys, function(a, b) return (DB.chars[a].money or 0) > (DB.chars[b].money or 0) end)
  local lines = { "|cffffffffAll characters: " .. Money(total) .. "|r", " " }
  for _, key in ipairs(keys) do
    local c = DB.chars[key]
    table.insert(lines, string.format("%s |cffaaaaaa(%s%s)|r", ClassColored(c, key),
      c.level and ("lvl " .. c.level) or "?", c.account and (", " .. c.account) or ""))
    table.insert(lines, string.format("      %s%s   |cff888888bags %s, bank %s, mail %s|r", Money(c.money),
      (c.mailMoney or 0) > 0 and ("  |cff888888+ in mail|r " .. Money(c.mailMoney)) or "",
      Ago(c.updated), c.bankUpdated and Ago(c.bankUpdated) or "not seen - visit a bank",
      c.mailUpdated and Ago(c.mailUpdated) or "not seen - visit a mailbox"))
  end
  SetBody(table.concat(lines, "\n"))
end

local function CreateWindow()
  frame = CreateFrame("Frame", "AltVaultFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(480, 460)
  frame:SetPoint("CENTER")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetFrameStrata("HIGH")
  frame:Hide()
  table.insert(UISpecialFrames, "AltVaultFrame")

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", 0, -5)
  title:SetText("AltVault")

  local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  box:SetSize(290, 22)
  box:SetPoint("TOPLEFT", 20, -32)
  box:SetAutoFocus(false)
  box:SetScript("OnTextChanged", function(self) ShowSearch(self:GetText()) end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  frame.box = box

  local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  btn:SetSize(130, 22)
  btn:SetPoint("LEFT", box, "RIGHT", 10, 0)
  btn:SetText("Characters & Gold")
  btn:SetScript("OnClick", function() box:SetText(""); box:ClearFocus(); ShowCharacters() end)

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -62)
  scroll:SetPoint("BOTTOMRIGHT", -32, 12)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(420, 10)
  scroll:SetScrollChild(child)
  local body = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  body:SetPoint("TOPLEFT", 4, -4)
  body:SetWidth(410)
  body:SetJustifyH("LEFT")
  body:SetSpacing(3)
  frame.scroll, frame.child, frame.body = scroll, child, body
end

local function OpenWindow(query, characters)
  if not frame then CreateWindow() end
  frame:Show()
  if query and query ~= "" then
    frame.box:SetText(query)
  else
    frame.box:SetText("")
    ShowCharacters()
    if not characters then frame.box:SetFocus() end
  end
end

-- Shared with Mail.lua, Minimap.lua and Crafting.lua
ns.GetDB = function() return DB end
ns.PlayerKey = function() return playerKey end
ns.Me = Me
ns.Remember = Remember
ns.WhoHas = WhoHas
ns.Money = Money
ns.ClassColored = ClassColored
ns.ShortName = ShortName
ns.LocationLabel = function(where) return LOCATION_LABEL[where] or where end
ns.OpenWindow = OpenWindow
ns.ToggleWindow = function()
  if frame and frame:IsShown() then frame:Hide() else OpenWindow("") end
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
SLASH_ALTVAULT1 = "/vault"
SLASH_ALTVAULT2 = "/altvault"
SlashCmdList.ALTVAULT = function(msg)
  msg = strtrim(msg or "")
  local cmd, rest = msg:match("^(%S+)%s*(.-)$")
  cmd = cmd and cmd:lower()
  if cmd == "delete" and rest ~= "" then
    if DB.chars[rest] then
      DB.chars[rest] = nil
      print("|cff33ff99AltVault|r: removed " .. rest)
    else
      print("|cff33ff99AltVault|r: no character named '" .. rest .. "' (use Name-Realm, see /vault)")
    end
  elseif cmd == "minimap" and rest == "" then
    ns.ToggleMinimapButton()
  elseif cmd == "crafting" and rest == "" then
    ns.ToggleCraftingPanel()
  elseif cmd == "help" then
    print("|cff33ff99AltVault|r: /vault - open window | /vault <item> - search | /vault delete Name-Realm")
    print("|cff33ff99AltVault|r: /vault minimap - hide/show minimap button | /vault crafting - reagent panel on/off")
  elseif frame and frame:IsShown() and msg == "" then
    frame:Hide()
  else
    OpenWindow(msg)
  end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
ev:RegisterEvent("BANKFRAME_OPENED")
ev:RegisterEvent("BANKFRAME_CLOSED")
ev:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
ev:RegisterEvent("PLAYER_MONEY")
ev:RegisterEvent("PLAYER_LOGOUT")

local pending = false
local function QueueScan()
  if pending then return end
  pending = true
  C_Timer.After(0.5, function()
    pending = false
    ScanBags()
    ScanBank()
  end)
end

ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    AltVaultDB = AltVaultDB or {}
    DB = AltVaultDB
    DB.chars = DB.chars or {}
    DB.items = DB.items or {}
    DB.version = 1
  elseif event == "PLAYER_LOGIN" then
    playerKey = UnitName("player") .. "-" .. GetRealmName()
    HookTooltips()
    ns.UpdateMinimapButton()
    C_Timer.After(3, ScanBags)
  elseif not playerKey then
    return
  elseif event == "BANKFRAME_OPENED" then
    bankOpen = true
    C_Timer.After(0.5, ScanBank)
  elseif event == "BANKFRAME_CLOSED" then
    bankOpen = false
  elseif event == "PLAYER_MONEY" then
    UpdateBasics()
  elseif event == "PLAYER_LOGOUT" then
    ScanBags()
  else
    QueueScan()
  end
end)
