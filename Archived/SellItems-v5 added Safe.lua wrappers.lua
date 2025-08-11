--[[
SellItems.lua — queued selling + tooltip + buyback popup (TWOW / Lua 5.0)
UPDATED: 9 August, 2025
]]

KaChing = KaChing or {}
KaChing.SellItems = KaChing.SellItems or {}
KaChing.SellItems.itemTable = KaChing.SellItems.itemTable or {}
KaChing.ExclusionList = KaChing.ExclusionList or { ["hearthstone"] = true, ["refreshing spring water"] = true }

local core = KaChing.Core
local dbg  = KaChing.DebugTools
local sell = KaChing.SellItems
local L    = KaChing.L or {}

-- ===========================
-- Static popup for buyback full
-- ===========================
if not StaticPopupDialogs then StaticPopupDialogs = {} end
StaticPopupDialogs["KACHING_SELL_PAUSED"] = {
    text = (L["KACHING_POPUP_TEXT"]),
    button1 = OKAY or "OK",
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}

-- ===========================
-- Hidden tooltip scanner
-- ===========================
if not sell._scanTip then
    local tip = CreateFrame("GameTooltip", "KaChingScanTip", UIParent, "GameTooltipTemplate")
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    sell._scanTip = tip
end

local function tipLeftText(i)
    local font = getglobal("KaChingScanTipTextLeft"..i)
    if font then return font:GetText(), font:GetTextColor() end
end

local function approx(a,b) return a > b-0.05 and a < b+0.05 end

local function isGrayByTooltip(bag, slot)
    local tip = sell._scanTip
    tip:ClearLines()
    tip:SetBagItem(bag, slot)
    local _, r, g, b = tipLeftText(1)
    if not (r and g and b) then return false end
    return approx(r,0.62) and approx(g,0.62) and approx(b,0.62)
end

local function tooltipNameLower(bag, slot)
    local tip = sell._scanTip
    tip:ClearLines()
    tip:SetBagItem(bag, slot)
    local t = tipLeftText(1)
    if type(t) == "string" then return string.lower(t) end
end

-- ===========================
-- Helpers
-- ===========================
local function extractItemNameFromLink(itemLink, bag, slot)
    if type(itemLink) == "string" then
        local _, _, name = string.find(itemLink, "%[(.-)%]")
        if name and name ~= "" then return string.lower(name) end
    end
    return tooltipNameLower(bag, slot)
end

local function isGrayItemByLink(itemLink)
    if type(itemLink) ~= "string" then return false end
    local _, _, hex = string.find(itemLink, "|cff(%x%x%x%x%x%x)")
    return hex == "9d9d9d"
end

local function isBagValid(bag)
    if type(bag) ~= "number" or bag < 0 or bag > 4 then return false end
    local n = GetContainerNumSlots(bag)
    return n and n > 0
end

local function isSlotOccupied(bag, slot)
    local texture = GetContainerItemInfo(bag, slot)
    return texture ~= nil
end

local function formatMoney(copper)
    if not copper or copper <= 0 then return "0g 0s 0c" end
    local g = math.floor(copper / 10000)
    copper = copper - g * 10000
    local s = math.floor(copper / 100)
    local c = copper - s * 100
    local out = ""
    if g > 0 then out = out .. g .. "g " end
    if s > 0 or g > 0 then out = out .. s .. "s " end
    return out .. c .. "c"
end

local function logInfo(msg) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg, 1, 1, 0.5) end end
local function logWarn(msg) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg, 1, 0.82, 0) end end
local function logErr(msg)  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg, 1, 0, 0) end end
local function dprint(msg)
    if core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
        if dbg and dbg.print then dbg:print(msg) else logInfo("[DBG] "..tostring(msg)) end
    end
end

-- ===========================
-- Queue / state machine
-- ===========================
sell._queue   = sell._queue or {}   -- array of jobs: {bag,slot,name,count,tries,t0,buyback0,state}
sell._current = nil
sell._runner  = sell._runner or nil
sell._poke    = false
sell._running = false

-- Tuning
local PROCESS_INTERVAL = 0.20
local ITEM_TIMEOUT     = 3.00
local MAX_RETRIES      = 8

local function merchantOpen() return MerchantFrame and MerchantFrame:IsShown() end

local function buildQueueGray()
    sell._queue = {}
    local bag
    for bag = 0, 4 do
        if isBagValid(bag) then
            local slots = GetContainerNumSlots(bag)
            local slot
            for slot = slots, 1, -1 do
                if isSlotOccupied(bag, slot) then
                    local link = GetContainerItemLink(bag, slot)
                    local info = { GetContainerItemInfo(bag, slot) }
                    local locked = info[3]
                    local count  = info[2] or 1
                    if not locked then
                        local nameLower = extractItemNameFromLink(link, bag, slot) or "unknown"
                        if not KaChing.ExclusionList[nameLower] then
                            if isGrayByTooltip(bag, slot) or isGrayItemByLink(link) then
                                tinsert(sell._queue, { bag = bag, slot = slot, name = nameLower, count = count, tries = 0, t0 = 0, buyback0 = 0, state = "pending" })
                            end
                        end
                    end
                end
            end
        end
    end
end

local function queueEmpty() return sell._queue[1] == nil end
local function queuePop() return table.remove(sell._queue, 1) end

local function saleConfirmed(job)
    local tex = GetContainerItemInfo(job.bag, job.slot)
    if not tex then return true end
    -- if GetNumBuybackItems() > job.buyback0 then return true end
    -- return false
    -- Buyback full?
    if GetNumBuybackItems() >= 12 then
        logWarn("KaChing: Buyback tab full—stopping sales.")
        sell._running = false
        sell._current = nil
        sell._queue = {}
        if StaticPopup_Show then StaticPopup_Show("KACHING_SELL_PAUSED") end
        return
end

end

local function cursorSafe()
    if CursorHasItem() then
        ClearCursor()
        return false
    end
    return true
end

local function startRunner()
    if sell._runner then return end
    sell._runner = CreateFrame("Frame")
    sell._runner._accum = 0
    sell._runner:SetScript("OnUpdate", function()
        local dt = arg1 or 0
        sell._runner._accum = sell._runner._accum + dt
        if sell._runner._accum < PROCESS_INTERVAL and not sell._poke then return end
        sell._runner._accum = 0
        sell._poke = false

        if not sell._running then return end
        if not merchantOpen() then
            sell._running = false
            sell._current = nil
            sell._queue = {}
            dprint("Runner stopped: merchant closed")
            return
        end

        if not cursorSafe() then
            dprint("Cleared stray cursor item")
            return
        end

        -- Buyback full? Pause and instruct user to click again.
        if GetNumBuybackItems() >= 12 then
            logWarn("KaChing: Buyback tab full—stopping sales.")
            sell._running = false
            sell._current = nil
            sell._queue = {}
            if StaticPopup_Show then StaticPopup_Show("KACHING_SELL_PAUSED") end
            return
        end

        if not sell._current then
            if queueEmpty() then
                sell._running = false
                dprint("Queue empty; runner idle")
                return
            end
            sell._current = queuePop()
            dprint("Processing: "..sell._current.name.." @ bag "..sell._current.bag.." slot "..sell._current.slot)
        end

        local job = sell._current
        local tex, count, locked = GetContainerItemInfo(job.bag, job.slot)
        if not tex then
            dprint("Slot empty; treating as sold: "..job.name)
            sell._current = nil
            return
        end
        if locked then
            dprint("Locked; waiting: "..job.name)
            return
        end

        local link = GetContainerItemLink(job.bag, job.slot)
        local nameLower = extractItemNameFromLink(link, job.bag, job.slot) or job.name
        if KaChing.ExclusionList[nameLower] then
            dprint("Excluded now; skipping: "..nameLower)
            sell._current = nil
            return
        end
        local isGray = isGrayByTooltip(job.bag, job.slot) or isGrayItemByLink(link)
        if not isGray then
            dprint("Not gray anymore; skipping: "..nameLower)
            sell._current = nil
            return
        end

        -- if job.state == "pending" then
        --     job.buyback0 = GetNumBuybackItems()
        --     UseContainerItem(job.bag, job.slot)
        --     job.state = "waiting"
        --     job.t0 = GetTime()
        --     dprint("UseContainerItem issued: "..job.name)
        --     return
        -- end
        

        -- if job.state == "waiting" then
        --     if saleConfirmed(job) then
        --         if core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
        --             logInfo("Sold: "..nameLower.." x"..(count or 1))
        --         end
        --         sell._current = nil
        --         return
        --     end
        --     if GetTime() - job.t0 >= ITEM_TIMEOUT then
        --         job.tries = job.tries + 1
        --         if job.tries >= MAX_RETRIES then
        --             logErr("KaChing: Gave up on "..nameLower.." after "..job.tries.." tries.")
        --             sell._current = nil
        --         else
        --             dprint("Retrying "..nameLower.." (try "..job.tries..")")
        --             job.state = "pending"
        --         end
        --     end
        --     return
        -- end
if job.state == "waiting" then
    if saleConfirmed(job) then
        if core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
            logInfo("Sold: "..nameLower.." x"..(count or 1))
        end
        sell._current = nil

        -- NEW: per-run cap of 12, then show popup and pause
        sell._soldThisRun = (sell._soldThisRun or 0) + 1
        if sell._soldThisRun >= 12 then
            if StaticPopup_Show then StaticPopup_Show("KACHING_SELL_PAUSED") end
            sell._running = false
            sell._queue = {}
            return
        end
        return
    end
end


    end)

    if not sell._evt then
        sell._evt = CreateFrame("Frame")
        sell._evt:RegisterEvent("ITEM_LOCK_CHANGED")
        sell._evt:RegisterEvent("BAG_UPDATE")
        sell._evt:RegisterEvent("MERCHANT_CLOSED")
        sell._evt:SetScript("OnEvent", function()
            if event == "MERCHANT_CLOSED" then
                sell._running = false
                sell._current = nil
                sell._queue = {}
            else
                sell._poke = true
            end
        end)
    end
end

local function ensureRunner()
    if not sell._runner then startRunner() end
end

-- ===========================
-- Public: start selling grays
-- ===========================
function sell.sellItems()
    if not merchantOpen() then
        logErr("KaChing: Please open a merchant window to sell items.")
        return
    end

    buildQueueGray()
    if sell._queue[1] == nil then
        logInfo("KaChing: No gray items to sell.")
        return
    end

    -- (Optional) summary: announce total gold after run; kept minimal for now.
    sell._moneyStart   = GetMoney()
    sell._summaryShown = false
    if not sell._summaryFrame then
        sell._summaryFrame = CreateFrame("Frame")
        sell._summaryFrame._t = 0
        sell._summaryFrame:SetScript("OnUpdate", function()
            local dt = arg1 or 0
            sell._summaryFrame._t = sell._summaryFrame._t + dt
            if sell._summaryFrame._t < 0.25 then return end
            sell._summaryFrame._t = 0
            if not sell._running and not sell._current then
                if not sell._summaryShown then
                    local gain = GetMoney() - (sell._moneyStart or 0)
                    local priceText = (gain > 0) and formatMoney(gain) or "unknown price"
                    logInfo("KaChing: Finished selling. Gold gained: "..priceText)
                    sell._summaryShown = true
                end
            end
        end)
    end

    ensureRunner()
    sell._running = true
    sell._poke = true
end

-- ===========================
-- Item table maintenance
-- ===========================
local BUTTON_CREATED = false

function sell.updateItemList(bagId)
    local newTable = {}
    local _, item
    for _, item in pairs(sell.itemTable) do
        if item.bagId ~= bagId then
            tinsert(newTable, item)
        end
    end
    local slots = GetContainerNumSlots(bagId) or 0
    local slot
    for slot = slots, 1, -1 do
        if isSlotOccupied(bagId, slot) then
            local link = GetContainerItemLink(bagId, slot)
            local info = { GetContainerItemInfo(bagId, slot) }
            local locked = info[3]
            local count  = info[2] or 1
            local name   = extractItemNameFromLink(link, bagId, slot) or "unknown"
            if not locked and not KaChing.ExclusionList[name] and (isGrayByTooltip(bagId, slot) or isGrayItemByLink(link)) then
                tinsert(newTable, { bagId = bagId, slotId = slot, name = name, isGray = true, itemCount = count })
            end
        end
    end
    sell.itemTable = newTable
end

function sell.initializeItemTable()
    sell.itemTable = {}
    local bag
    for bag = 0, 4 do
        if isBagValid(bag) then
            sell.updateItemList(bag)
        end
    end
end

-- function sell.createKaChingButton()
--     if BUTTON_CREATED then return end
--     if not MerchantFrame then return end

--     local button = CreateFrame("Button", "KaChingBtn", MerchantFrame, "UIPanelButtonTemplate")
--     button:SetText("KaChing")
--     button:SetWidth(90)
--     button:SetHeight(21)
--     button:SetPoint("TOPRIGHT", -50, -45)
--     button:SetScript("OnClick", function() sell.sellItems() end)

--     -- Safe tooltip on hover (Classic/Lua 5.0)
--     button:EnableMouse(true)
--     button:SetScript("OnEnter", function(self)

--         if GameTooltip and self then
--             GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
--             GameTooltip:ClearLines()
--             GameTooltip:AddLine(L["KACHING_BTN_TOOLTIP"], 1, 1, 1, true)
--             GameTooltip:Show()
--         end
--     end)
--     button:SetScript("OnLeave", function()
--         if GameTooltip then GameTooltip:Hide() end
--     end)

--     BUTTON_CREATED = true
-- end

function sell.createKaChingButton()
    if BUTTON_CREATED then return end
    if not MerchantFrame then return end

    local button = CreateFrame("Button", "KaChingBtn", MerchantFrame, "UIPanelButtonTemplate")
    button:SetText("KaChing")
    button:SetWidth(90)
    button:SetHeight(21)
    button:SetPoint("TOPRIGHT", -50, -45)

    -- Each click starts/continues a selling run (next batch of up to 12)
    button:SetScript("OnClick", function()
        if sell and sell.sellItems then
            sell.sellItems()
        elseif DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage( L["KACHING_FUNCTION_NOT_READY"], 1, 0, 0)
        end
    end)

    -- Safe tooltip on hover (Classic/Lua 5.0)
    button:EnableMouse(true)
    button:SetScript("OnEnter", function(self)

        if GameTooltip and self then
            GameTooltip:Hide() -- reset any prior owner
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(L["KACHING_BTN_TOOLTIP"], 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    BUTTON_CREATED = true
end


if DEFAULT_CHAT_FRAME and core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
    DEFAULT_CHAT_FRAME:AddMessage("SellItems.lua (queued+popup) is loaded", 1, 1, 0.5)
end
