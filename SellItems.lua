--[[
SellItems.lua — batched selling + tooltip (TWOW / Lua 5.0, no C_Timer)
UPDATED: 10 August, 2025
Behavior:
- Sells in batches of BATCH_LIMIT, then waits SELL_DELAY seconds, then continues automatically.
- Ignores the vendor's 12-item buyback depth (still confirms via slot-empty or buyback++ for robustness).
]]

KaChing = KaChing or {}
KaChing.SellItems = KaChing.SellItems or {}
KaChing.SellItems.itemTable = KaChing.SellItems.itemTable or {}
KaChing.ExclusionList = KaChing.ExclusionList or { ["hearthstone"] = true, ["refreshing spring water"] = true }

local core  = KaChing.Core
local dbg   = KaChing.DebugTools
local sell  = KaChing.SellItems
local L     = KaChing.L or {}
local safe  = KaChing.Safe

-- ===========================
-- Config: batching
-- ===========================
local BATCH_LIMIT = 12      -- items per burst
local SELL_DELAY  = 0.75    -- seconds to wait between bursts

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
    if not safe.TooltipSetBagItem(tip, bag, slot) then return false end
    local _, r, g, b = tipLeftText(1)
    if not (r and g and b) then return false end
    return approx(r,0.62) and approx(g,0.62) and approx(b,0.62)
end

local function tooltipNameLower(bag, slot)
    local tip = sell._scanTip
    tip:ClearLines()
    if not safe.TooltipSetBagItem(tip, bag, slot) then return nil end
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
    local n = safe.GetContainerNumSlots(bag)
    return n and n > 0
end

local function isSlotOccupied(bag, slot)
    local texture = safe.GetContainerItemInfo(bag, slot)
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
sell._queue        = sell._queue or {}   -- jobs: {bag,slot,name,count,tries,t0,buyback0,state}
sell._current      = nil
sell._runner       = sell._runner or nil
sell._poke         = false
sell._running      = false
sell._batchCount   = 0
sell._cooldownUntil= nil

-- Tuning
local PROCESS_INTERVAL = 0.20
local ITEM_TIMEOUT     = 3.00
local MAX_RETRIES      = 8

local function merchantOpen() return MerchantFrame and MerchantFrame:IsShown() end

local function buildQueueGray()
    sell._queue = {}
    for bag = 0, 4 do
        if isBagValid(bag) then
            local slots = safe.GetContainerNumSlots(bag)
            for slot = slots, 1, -1 do
                if isSlotOccupied(bag, slot) then
                    local link = safe.GetContainerItemLink(bag, slot)
                    local tex, count, locked = safe.GetContainerItemInfo(bag, slot)
                    count = count or 1
                    if not locked then
                        local nameLower = extractItemNameFromLink(link, bag, slot) or "unknown"
                        if not KaChing.ExclusionList[nameLower] then
                            if isGrayByTooltip(bag, slot) or isGrayItemByLink(link) then
                                tinsert(sell._queue, {
                                    bag = bag, slot = slot, name = nameLower, count = count,
                                    link = link, tries = 0, t0 = 0, buyback0 = 0, state = "pending"
                                })
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

-- Confirmed if slot is now empty OR buyback count increased
local function saleConfirmed(job)
    local tex = safe.GetContainerItemInfo(job.bag, job.slot)
    if not tex then return true end
    if safe.GetNumBuybackItems() > (job.buyback0 or 0) then return true end
    return false
end

local function cursorSafe()
    if safe.CursorHasItem and safe.CursorHasItem() then
        safe.ClearCursor()
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

        -- Batch cooldown (C_Timer.After equivalent)
        if sell._cooldownUntil then
            if GetTime() < sell._cooldownUntil then
                return
            end
            sell._cooldownUntil = nil
            dprint("Batch cooldown finished; resuming.")
        end

        if not cursorSafe() then
            dprint("Cleared stray cursor item")
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
        local tex, count, locked = safe.GetContainerItemInfo(job.bag, job.slot)

        -- STATE: pending => validate and issue UseContainerItem
        if job.state == "pending" then
            if not tex then
                dprint("Slot empty before sale; skipping: "..job.name)
                sell._current = nil
                return
            end
            if locked then
                dprint("Locked; waiting pre-sale: "..job.name)
                return
            end

            local link = safe.GetContainerItemLink(job.bag, job.slot)
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

            job.buyback0 = safe.GetNumBuybackItems()
            safe.UseContainerItem(job.bag, job.slot)
            job.state = "waiting"
            job.t0 = GetTime()
            dprint("UseContainerItem issued: "..job.name)
            return
        end

        -- STATE: waiting => confirm success; count and batch throttle
        if job.state == "waiting" then
            if saleConfirmed(job) then
                sell._current = nil

                -- Count towards batch and gate if needed
                sell._batchCount = (sell._batchCount or 0) + 1
                if sell._batchCount >= BATCH_LIMIT and not queueEmpty() then
                    sell._batchCount    = 0
                    sell._cooldownUntil = GetTime() + SELL_DELAY
                    dprint("Batch limit reached; pausing for "..SELL_DELAY.."s.")
                end

                -- (Optional) debug info
                if core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
                    logInfo("Sold: "..(job.name or "item").." x"..(count or 1))
                end
                return
            end

            if GetTime() - (job.t0 or 0) >= ITEM_TIMEOUT then
                job.tries = (job.tries or 0) + 1
                if job.tries >= MAX_RETRIES then
                    logErr("KaChing: Gave up on "..(job.name or "item").." after "..job.tries.." tries.")
                    sell._current = nil
                else
                    dprint("Retrying "..(job.name or "item").." (try "..job.tries..")")
                    job.state = "pending"
                end
            end
            return
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
                sell._cooldownUntil = nil
                sell._batchCount = 0
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

    -- Reset run state
    sell._batchCount    = 0
    sell._cooldownUntil = nil

    -- (Optional) summary: announce total gold after run
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
    for _, item in pairs(sell.itemTable) do
        if item.bagId ~= bagId then
            tinsert(newTable, item)
        end
    end
    local slots = safe.GetContainerNumSlots(bagId) or 0
    for slot = slots, 1, -1 do
        if isSlotOccupied(bagId, slot) then
            local link = safe.GetContainerItemLink(bagId, slot)
            local _, count, locked = safe.GetContainerItemInfo(bagId, slot)
            local name   = extractItemNameFromLink(link, bagId, slot) or "unknown"
            if not locked and not KaChing.ExclusionList[name] and (isGrayByTooltip(bagId, slot) or isGrayItemByLink(link)) then
                tinsert(newTable, { bagId = bagId, slotId = slot, name = name, isGray = true, itemCount = count or 1 })
            end
        end
    end
    sell.itemTable = newTable
end

function sell.initializeItemTable()
    sell.itemTable = {}
    for bag = 0, 4 do
        if isBagValid(bag) then
            sell.updateItemList(bag)
        end
    end
end

function sell.createKaChingButton()
    if BUTTON_CREATED then return end
    if not MerchantFrame then return end

    local button = CreateFrame("Button", "KaChingBtn", MerchantFrame, "UIPanelButtonTemplate")
    button:SetText("KaChing")
    button:SetWidth(90)
    button:SetHeight(21)
    button:SetPoint("TOPRIGHT", -50, -45)

    -- Click: start/continue selling
    button:SetScript("OnClick", function()
        if sell and sell.sellItems then
            sell.sellItems()
        elseif DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(L["KACHING_FUNCTION_NOT_READY"], 1, 0, 0)
        end
    end)

    -- Tooltip (Lua 5.0 / Classic uses 'this')
    button:EnableMouse(true)
    button:SetScript("OnEnter", function()
        if GameTooltip and this then
            GameTooltip:Hide()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
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
    DEFAULT_CHAT_FRAME:AddMessage("SellItems.lua (batched build) is loaded", 1, 1, 0.5)
end
