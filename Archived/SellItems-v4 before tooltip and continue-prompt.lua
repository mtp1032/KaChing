--[[ 
SellItems.lua
AUTHOR: mtpeterson
DATE: 8 August, 2025

DESCRIPTION:
Implements selling of gray items (hyperlink color |cff9d9d9d) in Turtle WoW, with robust handling for custom items with malformed links and API quirks.

PROGRAMMING NOTES:
Lua 5.0:
- No string.match, use string.find
- No goto, use nested if
- No select(), use explicit variable assignment
- No reliable OnUpdate dt, use GetTime()
- OnUpdate may use globals (arg1, arg2)
- _G is not available (use global environment directly)
- Use table.getn(t) instead of #t
- Use tinsert(t, v) instead of table.insert(t, v)
- Turtle WoW API quirk: Some white items (e.g., Refreshing Spring Water) have quality=-1, itemRarity=0
]]

-- SellItems.lua (TWOW / Lua 5.0 friendly, minimal changes to your structure)

--[[ 
SellItems.lua  — queued, event-driven selling for TWOW (Lua 5.0)
AUTHOR: mtpeterson
UPDATED: 9 August, 2025

Key changes:
- Builds a queue (descending slots per bag) and sells ONE item at a time.
- Waits for confirmation (slot empties or buyback increases) before next sale.
- Handles locked slots, buyback-full, cursor edge cases, and merchant close.
- Uses tooltip color (≈0.62,0.62,0.62) to classify gray; link color as fallback.
]]

KaChing = KaChing or {}
KaChing.SellItems = KaChing.SellItems or {}
KaChing.SellItems.itemTable = KaChing.SellItems.itemTable or {}
KaChing.ExclusionList = KaChing.ExclusionList or { ["hearthstone"] = true, ["refreshing spring water"] = true }

local core = KaChing.Core
local dbg  = KaChing.DebugTools
local sell = KaChing.SellItems

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

local function logInfo(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg, 1, 1, 0.5) end
end
local function logWarn(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg, 1, 0.82, 0) end
end
local function logErr(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg, 1, 0, 0) end
end
local function dprint(msg)
    if core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
        if dbg and dbg.print then dbg:print(msg) else logInfo("[DBG] "..tostring(msg)) end
    end
end

-- ===========================
-- Queue / state machine
-- ===========================
sell._queue = sell._queue or {}       -- array of jobs: {bag,slot,name,count}
sell._current = nil                   -- current job
sell._runner = sell._runner or nil    -- frame
sell._poke = false                    -- event nudge
sell._running = false

-- Tuning
local PROCESS_INTERVAL = 0.20         -- seconds between checks
local ITEM_TIMEOUT     = 3.00         -- per-job wait for confirmation
local MAX_RETRIES      = 8            -- times we can re-attempt a job

-- Build queue (descending within each bag)
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

-- Confirmation checks after UseContainerItem
local function saleConfirmed(job)
    -- Slot gone or changed?
    local tex = GetContainerItemInfo(job.bag, job.slot)
    if not tex then return true end

    -- Buyback increased?
    if GetNumBuybackItems() > job.buyback0 then return true end

    return false
end

local function cursorSafe()
    if CursorHasItem() then
        ClearCursor()
        return false
    end
    return true
end

local function merchantOpen()
    return MerchantFrame and MerchantFrame:IsShown()
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
            -- Merchant closed mid-run
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

        -- Buyback full?
        if GetNumBuybackItems() >= 12 then
            logWarn("KaChing: Buyback tab full—stopping sales.")
            sell._running = false
            sell._current = nil
            sell._queue = {}
            return
        end

        -- If no current job, fetch next
        if not sell._current then
            if queueEmpty() then
                -- Done
                sell._running = false
                dprint("Queue empty; runner idle")
                return
            end
            sell._current = queuePop()
            dprint("Processing: "..sell._current.name.." @ bag "..sell._current.bag.." slot "..sell._current.slot)
        end

        local job = sell._current

        -- Validate slot still occupied & qualifies (avoid stale positions)
        local tex, count, locked = GetContainerItemInfo(job.bag, job.slot)
        if not tex then
            -- Already gone (sold/shifted) -> treat as success
            dprint("Slot empty; treating as sold: "..job.name)
            sell._current = nil
            return
        end
        if locked then
            -- Wait until unlock; OnUpdate will revisit
            dprint("Locked; waiting: "..job.name)
            return
        end
        -- Recheck gray/exclusion quickly
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

        if job.state == "pending" then
            job.buyback0 = GetNumBuybackItems()
            UseContainerItem(job.bag, job.slot)
            job.state = "waiting"
            job.t0 = GetTime()
            dprint("UseContainerItem issued: "..job.name)
            return
        end

        if job.state == "waiting" then
            if saleConfirmed(job) then
                -- Report sale of this single item (optional per-item chat)
                if core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
                    logInfo("Sold: "..nameLower.." x"..(count or 1))
                end
                sell._current = nil
                return
            end
            -- Timeout / retry
            if GetTime() - job.t0 >= ITEM_TIMEOUT then
                job.tries = job.tries + 1
                if job.tries >= MAX_RETRIES then
                    logErr("KaChing: Gave up on "..nameLower.." after "..job.tries.." tries.")
                    sell._current = nil
                else
                    dprint("Retrying "..nameLower.." (try "..job.tries..")")
                    job.state = "pending"
                end
            end
            return
        end
    end)

    -- Event nudges to make it responsive
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

    -- Build queue and start
    buildQueueGray()
    if sell._queue[1] == nil then
        logInfo("KaChing: No gray items to sell.")
        return
    end

    -- Snapshot money to summarize after completion
    sell._moneyStart = GetMoney()
    sell._soldCount  = 0
    sell._summaryShown = false

    -- We’ll tally results by watching completed jobs in runner
    -- (increment each time we confirm; here we hook a tiny watcher)
    if not sell._summaryFrame then
        sell._summaryFrame = CreateFrame("Frame")
        sell._summaryFrame._t = 0
        sell._summaryFrame:SetScript("OnUpdate", function()
            local dt = arg1 or 0
            sell._summaryFrame._t = sell._summaryFrame._t + dt
            if sell._summaryFrame._t < 0.25 then return end
            sell._summaryFrame._t = 0

            -- Count sold implicitly: when _current is nil and queue shrinks, assume progress.
            -- Simpler: Once runner becomes idle (not _running and no _current), emit summary once.
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
    sell._poke = true  -- kick immediately
end

-- ===========================
-- Item table maintenance (used elsewhere)
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

function sell.createKaChingButton()
    if BUTTON_CREATED then return end
    if not MerchantFrame then return end

    local button = CreateFrame("Button", "KaChingBtn", MerchantFrame, "UIPanelButtonTemplate")
    button:SetText("KaChing")
    button:SetWidth(90)
    button:SetHeight(21)
    button:SetPoint("TOPRIGHT", -50, -45)
    button:SetScript("OnClick", 
        function() 
            sell.sellItems() 
        end)
    BUTTON_CREATED = true
end

if DEFAULT_CHAT_FRAME and core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
    DEFAULT_CHAT_FRAME:AddMessage("SellItems.lua (queued) is loaded", 1, 1, 0.5)
end
