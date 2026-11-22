-- AltVault crafting panel: while a profession window is open, a panel beside it lists
-- the selected recipe's reagents with how many you have, what's in your bank/mail,
-- and which alts are holding more.

local ADDON, ns = ...

local panel, lastSig
local THROTTLE = 0.25

-- Retail-style, Classic trade skill and Classic enchanting windows (whichever this client has).
local HOSTS = { "ProfessionsFrame", "TradeSkillFrame", "CraftFrame" }

local function VisibleHost()
  for _, name in ipairs(HOSTS) do
    local f = _G[name]
    if f and f.IsShown and f:IsShown() then return f end
  end
end

local function IDFromLink(link) return link and tonumber(link:match("item:(%d+)")) end

-- Returns recipe name and { {id=, need=, name=}, ... } for the selected recipe.
local function SelectedReagents(host)
  local list, title = {}, nil
  if host == TradeSkillFrame and GetTradeSkillSelectionIndex then
    local i = GetTradeSkillSelectionIndex()
    if not i or i == 0 then return end
    title = GetTradeSkillInfo(i)
    for r = 1, (GetTradeSkillNumReagents(i) or 0) do
      local name, _, need = GetTradeSkillReagentInfo(i, r)
      local id = IDFromLink(GetTradeSkillReagentItemLink(i, r))
      if id then table.insert(list, { id = id, need = need or 1, name = name }) end
    end
  elseif host == CraftFrame and GetCraftSelectionIndex then
    local i = GetCraftSelectionIndex()
    if not i or i == 0 then return end
    title = GetCraftInfo(i)
    for r = 1, (GetCraftNumReagents(i) or 0) do
      local name, _, need = GetCraftReagentInfo(i, r)
      local id = IDFromLink(GetCraftReagentItemLink(i, r))
      if id then table.insert(list, { id = id, need = need or 1, name = name }) end
    end
  elseif host == ProfessionsFrame and C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then
    local form = host.CraftingPage and host.CraftingPage.SchematicForm
    local info = form and form.GetRecipeInfo and form:GetRecipeInfo()
    if not info or not info.recipeID then return end
    title = info.name
    local schematic = C_TradeSkillUI.GetRecipeSchematic(info.recipeID, false)
    for _, slot in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
      local reagent = slot.reagents and slot.reagents[1]
      if reagent and reagent.itemID then
        table.insert(list, { id = reagent.itemID, need = slot.quantityRequired or 1 })
      end
    end
  end
  return title, list
end

local function Line(r)
  local _, rows = ns.WhoHas(r.id)
  local me = ns.PlayerKey()
  local mine, alts, altParts = {}, 0, {}
  local perAlt, order = {}, {}
  for _, row in ipairs(rows) do
    if row.key == me then
      table.insert(mine, ns.LocationLabel(row.where) .. " " .. row.count)
    else
      alts = alts + row.count
      if not perAlt[row.key] then perAlt[row.key] = { char = row.char, n = 0 }; table.insert(order, row.key) end
      perAlt[row.key].n = perAlt[row.key].n + row.count
    end
  end
  table.sort(order, function(a, b) return perAlt[a].n > perAlt[b].n end)
  for i, key in ipairs(order) do
    if i > 3 then table.insert(altParts, "...") break end
    table.insert(altParts, ns.ClassColored(perAlt[key].char, ns.ShortName(key)) .. " " .. perAlt[key].n)
  end
  local icon = (C_Item and C_Item.GetItemIconByID or GetItemIcon)(r.id)
  local link = ns.GetDB().items[r.id]
  local name = (link and link:match("%[(.-)%]")) or r.name or ("item " .. r.id)
  local text = string.format("%s|cffffffff%s|r |cffaaaaaax%d|r", icon and ("|T" .. icon .. ":14|t ") or "", name, r.need)
  text = text .. "\n      |cff88ccffYou:|r " .. (#mine > 0 and table.concat(mine, ", ") or "|cff888888none|r")
  if alts > 0 then
    text = text .. "\n      |cffffcc66Alts " .. alts .. ":|r " .. table.concat(altParts, ", ")
  end
  return text
end

local function Render(title, list)
  local lines = { "|cff33ff99AltVault|r  " .. (title or "") }
  if #list == 0 then table.insert(lines, "|cff888888No reagents.|r") end
  for _, r in ipairs(list) do table.insert(lines, Line(r)) end
  panel.text:SetText(table.concat(lines, "\n"))
  panel:SetHeight(panel.text:GetStringHeight() + 20)
end

local function Update()
  if not ns.GetDB() or ns.GetDB().crafting == false then panel:Hide() return end
  local host = VisibleHost()
  if not host then panel:Hide(); lastSig = nil; return end
  local ok, title, list = pcall(SelectedReagents, host)
  if not ok or not list then panel:Hide(); lastSig = nil; return end
  local sig = tostring(host) .. (title or "")
  for _, r in ipairs(list) do sig = sig .. ":" .. r.id end
  if panel.host ~= host then
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", host, "TOPRIGHT", 4, 0)
    panel.host = host
  end
  panel:Show()
  if sig ~= lastSig or panel.dirty then
    lastSig, panel.dirty = sig, false
    Render(title, list)
  end
end

local function Create()
  panel = CreateFrame("Frame", "AltVaultCraftingPanel", UIParent, "BackdropTemplate")
  panel:SetWidth(250)
  panel:SetFrameStrata("HIGH")
  if panel.SetBackdrop then
    panel:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 14,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel:SetBackdropColor(0, 0, 0, 0.85)
  end
  panel.text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.text:SetPoint("TOPLEFT", 10, -10)
  panel.text:SetWidth(230)
  panel.text:SetJustifyH("LEFT")
  panel.text:SetSpacing(2)
  panel:Hide()
end

-- A tiny always-on watcher; it does almost nothing while no profession window is open.
local watcher = CreateFrame("Frame")
local elapsed = 0
watcher:SetScript("OnUpdate", function(_, dt)
  elapsed = elapsed + dt
  if elapsed < THROTTLE then return end
  elapsed = 0
  if not ns.GetDB() then return end
  if not panel then
    if not VisibleHost() then return end
    Create()
  end
  Update()
end)

-- Bag changes while crafting: redraw counts.
watcher:RegisterEvent("BAG_UPDATE_DELAYED")
watcher:SetScript("OnEvent", function() if panel then panel.dirty = true end end)

function ns.ToggleCraftingPanel()
  local db = ns.GetDB()
  db.crafting = (db.crafting == false)
  print("|cff33ff99AltVault|r: crafting reagent panel " .. (db.crafting and "on" or "off"))
end
