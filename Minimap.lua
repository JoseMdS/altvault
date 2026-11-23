-- AltVault minimap button. Left-click: open/close the window. Right-click: characters & gold.
-- Drag to move it around the minimap. /vault minimap hides or shows it.

local ADDON, ns = ...

local button

local function Settings()
  local db = ns.GetDB()
  db.minimap = db.minimap or { angle = 200, hide = false }
  return db.minimap
end

local function Place()
  local angle = math.rad(Settings().angle or 200)
  local w = (Minimap:GetWidth() / 2) + 5
  local h = (Minimap:GetHeight() / 2) + 5
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * w, math.sin(angle) * h)
end

local function OnDragUpdate()
  local mx, my = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  px, py = px / scale, py / scale
  Settings().angle = math.deg(math.atan2(py - my, px - mx)) % 360
  Place()
end

local function Create()
  button = CreateFrame("Button", "AltVaultMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local overlay = button:CreateTexture(nil, "OVERLAY")
  overlay:SetSize(53, 53)
  overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  overlay:SetPoint("TOPLEFT")
  local bg = button:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20)
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetSize(17, 17)
  icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
  icon:SetPoint("TOPLEFT", 7, -6)

  button:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then ns.OpenWindow("", true) else ns.ToggleWindow() end
  end)
  button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("AltVault")
    local total, n = 0, 0
    for _, c in pairs(ns.GetDB().chars) do
      total = total + (c.money or 0) + (c.mailMoney or 0)
      n = n + 1
    end
    GameTooltip:AddDoubleLine(n .. " characters", ns.Money(total), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddLine("|cffaaaaaaLeft-click: search   Right-click: characters & gold|r")
    GameTooltip:AddLine("|cffaaaaaaDrag to move. /vault minimap to hide.|r")
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  Place()
end

function ns.UpdateMinimapButton()
  if not Minimap then return end
  if not button then Create() end
  button:SetShown(not Settings().hide)
end

function ns.ToggleMinimapButton()
  local s = Settings()
  s.hide = not s.hide
  ns.UpdateMinimapButton()
  print("|cff33ff99AltVault|r: minimap button " .. (s.hide and "hidden (/vault minimap to show it)" or "shown"))
end
