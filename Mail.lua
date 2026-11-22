-- AltVault mailbox: records items and gold waiting in each character's mailbox.
-- The mailbox can only be read while it's open, so each character's mail shows up
-- after they visit a mailbox (and is refreshed every time they do).

local ADDON, ns = ...

local MAX_ATTACH = ATTACHMENTS_MAX_RECEIVE or 16
local mailOpen = false

local function ScanMail()
  if not mailOpen or not ns.GetDB() then return end
  local num = GetInboxNumItems and GetInboxNumItems() or 0
  local counts, money = {}, 0
  for i = 1, num do
    local ok, _, _, _, _, gold, cod, _, hasItem = pcall(GetInboxHeaderInfo, i)
    if ok then
      if gold and (cod or 0) == 0 then money = money + gold end
      if hasItem then
        for a = 1, MAX_ATTACH do
          local okItem, name, itemID, _, count = pcall(GetInboxItem, i, a)
          if okItem and name then
            local link = GetInboxItemLink and GetInboxItemLink(i, a)
            itemID = itemID or (link and tonumber(link:match("item:(%d+)")))
            if itemID then
              counts[itemID] = (counts[itemID] or 0) + (count or 1)
              ns.Remember(itemID, link)
            end
          end
        end
      end
    end
  end
  local c = ns.Me()
  c.mail = counts
  c.mailMoney = money
  c.mailUpdated = time()
end

local pending = false
local function Queue()
  if pending then return end
  pending = true
  C_Timer.After(0.3, function() pending = false; ScanMail() end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("MAIL_SHOW")
ev:RegisterEvent("MAIL_CLOSED")
ev:RegisterEvent("MAIL_INBOX_UPDATE")
pcall(ev.RegisterEvent, ev, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
local MAILBOX = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.MailInfo
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "MAIL_SHOW" then
    mailOpen = true
    if CheckInbox then CheckInbox() end
    Queue()
  elseif event == "MAIL_CLOSED" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and MAILBOX and arg1 == MAILBOX) then
    -- One last read: taking items out of the mail fires this after the inbox updates.
    if mailOpen then ScanMail() end
    mailOpen = false
  elseif event == "MAIL_INBOX_UPDATE" then
    Queue()
  end
end)
