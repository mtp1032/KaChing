--[[ 
SellItems.lua
AUTHOR: mtpeterson
DATE: 7 August, 2025

DESCRIPTION:
Implements selling of gray items (hyperlink color |cff9d9d9d) in Turtle WoW, with robust handling for custom items with malformed links and API quirks.

PROGRAMMING NOTES:
Lua 5.0:
- No string.match, use string.find
- No goto, use nested if
- No select(), use explicit variable assignment
- No reliable OnUpdate dt, use GetTime()
- OnUpdate may use globals (arg1, arg2)
- _G is not available in 5.0
- Use table.getn(t) instead of #t
- Use tinsert(t, v) instead of table.insert(t, v)
- Turtle WoW API quirk: Some white items (e.g., Refreshing Spring Water) have quality=-1, itemRarity=0
]]

KaChing = KaChing or {}
KaChing.SellItems = {}
KaChing.ExclusionList = KaChing.ExclusionList or { ["hearthstone"] = true, ["refreshing spring water"] = true } -- Exclude known white items
local core = KaChing.Core
local dbg = KaChing.DebugTools
local sell = KaChing.SellItems

-- Extracts item name from itemLink (handles malformed links like [Snapped Spider Limb])
local function extractItemNameFromLink(itemLink)
    if not itemLink then return nil end
    local start, stop = string.find(itemLink, "%[(.+)%]")
    local name = start and string.sub(itemLink, start + 1, stop - 1) or itemLink or "unknown"
    return string.lower(name) -- Case-insensitive for exclusion list
end

-- Checks if item is gray by hyperlink color (|cff9d9d9d)
local function isGrayItem(itemLink)
    if not itemLink then return false end
    local start, stop = string.find(itemLink, "|cff(%x%x%x%x%x%x)")
    if start then
        local color = string.sub(itemLink, start + 4, stop)
        return color == "9d9d9d" -- Gray items
    end
    return false
end

-- Checks if a bag exists and has slots
-- Checks if the specified bag is valid (exists and has slots)
local function isBagValid(bag)
    if not bag or type(bag) ~= "number" or bag < 0 or bag > 4 then
        return false
    end
    
    if GetContainerNumSlots(bag) == 0 then
        return false
    end
    return true
end
-- Checks if a slot is occupied and logs item info (skip empty slots)
local function isSlotOccupied(bag, slot)
    local info = {GetContainerItemInfo(bag, slot)}
    local itemLink = GetContainerItemLink(bag, slot)
    if info[1] ~= nil and core:debuggingIsEnabled() then
        local logStr = "Checking Bag " .. bag .. ", Slot " .. slot .. ": "
        for i = 1, table.getn(info) do
            logStr = logStr .. "info[" .. i .. "]=" .. tostring(info[i] or "nil") .. (i < table.getn(info) and ", " or "")
        end
        logStr = logStr .. ", link=" .. tostring(itemLink or "nil")
        DEFAULT_CHAT_FRAME:AddMessage(logStr, 1, 1, 0.5)
    end
    return info[1] ~= nil
end

-- Custom money formatter (replaces GetCoinText, avoids % operator)
local function formatMoney(copper)
    if not copper or copper == 0 then return "0g 0s 0c" end
    local gold = math.floor(copper / 10000)
    copper = copper - (gold * 10000)
    local silver = math.floor(copper / 100)
    copper = copper - (silver * 100)
    local bronze = copper
    local result = ""
    if gold > 0 then
        result = result .. gold .. "g "
    end
    if silver > 0 or gold > 0 then
        result = result .. silver .. "s "
    end
    result = result .. bronze .. "c"
    return result
end

-- Main sell function (only gray items: hyperlink color |cff9d9d9d)
function sell.sellItems()
    local moneyBefore = GetMoney()
    local itemsSold = 0
    local pendingSales = {}

    if core:debuggingIsEnabled() then
        dbg:print("Initial GetMoney: " .. (moneyBefore or "nil"))
    end

    for bag = 0, 4 do
        if isBagValid(bag) then
            for slot = 1, GetContainerNumSlots(bag) do
                if isSlotOccupied(bag, slot) then
                    local itemLink = GetContainerItemLink(bag, slot)
                    if itemLink then
                        local info = {GetContainerItemInfo(bag, slot)}
                        local texture, itemCount, locked, quality = info[1], info[2], info[3], info[4]
                        local name, _, itemRarity = GetItemInfo(itemLink) or {}
                        local extractedName = extractItemNameFromLink(itemLink) or "unknown"

                        if core:debuggingIsEnabled() then
                            local itemId = nil
                            local start, stop = string.find(itemLink, "item:(%d+)")
                            if start then
                                itemId = tonumber(string.sub(itemLink, start + 5, stop))
                            end
                            local color = "unknown"
                            local colorStart, colorStop = string.find(itemLink, "|cff(%x%x%x%x%x%x)")
                            if colorStart then
                                color = string.sub(itemLink, colorStart + 4, colorStop)
                            end
                            dbg:print("Item: " .. extractedName .. ", link=" .. tostring(itemLink) .. ", itemId=" .. (itemId or "nil") .. ", quality=" .. (quality or "nil") .. ", itemRarity=" .. (itemRarity or "nil") .. ", color=" .. color)
                        end

                        -- Skip excluded or locked items using nested if
                        if not KaChing.ExclusionList[extractedName] then
                            if not locked then
                                if GetNumBuybackItems() < 12 then
                                    local shouldSell = false
                                    if isGrayItem(itemLink) then -- Only gray items by hyperlink color
                                        shouldSell = true
                                    end

                                    if core:debuggingIsEnabled() then
                                        dbg:print("Shouldsell: " .. extractedName .. " = " .. tostring(shouldSell) .. ", quality=" .. (quality or "nil") .. ", itemRarity=" .. (itemRarity or "nil"))
                                    end

                                    if shouldSell then
                                        tinsert(pendingSales, {name = extractedName, count = itemCount or 1, bag = bag, slot = slot})
                                        UseContainerItem(bag, slot)
                                        itemsSold = itemsSold + 1
                                    end
                                else
                                    if core:debuggingIsEnabled() then
                                        DEFAULT_CHAT_FRAME:AddMessage("KaChing: Buyback tab full, stopping sales.", 1, 0, 0)
                                    end
                                    return
                                end
                            else
                                if core:debuggingIsEnabled() then
                                    DEFAULT_CHAT_FRAME:AddMessage("Item " .. extractedName .. " is locked, cannot sell.", 1, 1, 0.5)
                                end
                            end
                        else
                            if core:debuggingIsEnabled() then
                                DEFAULT_CHAT_FRAME:AddMessage("Item " .. extractedName .. " is in exclusion list, skipped.", 1, 1, 0.5)
                            end
                        end
                    end
                end
            end
        end
    end

    if itemsSold > 0 then
        local delayFrame = CreateFrame("Frame")
        local startTime = GetTime()
        delayFrame:SetScript("OnUpdate", function()
            -- Debug globals to confirm argument passing
            if GetTime() - startTime >= 0.5 then
                local moneyAfter = GetMoney()
                local formattedMoney = formatMoney(moneyAfter)
                if core:debuggingIsEnabled() then
                    dbg:print("Money: " .. (moneyAfter or "nil") .. ", Formatted: " .. formattedMoney .. ", Time: " .. GetTime())
                    dbg:print("MoneyBefore: " .. (moneyBefore or "nil") .. ", MoneyAfter: " .. (moneyAfter or "nil"))
                end
                local priceText = (moneyAfter > moneyBefore and moneyAfter ~= 0) and formatMoney(moneyAfter - moneyBefore) or "unknown price"
                for _, sale in pairs(pendingSales) do
                    -- Verify item was sold (no longer in bag/slot)
                    local link = GetContainerItemLink(sale.bag, sale.slot)
                    if not link then
                        DEFAULT_CHAT_FRAME:AddMessage("Sold: " .. sale.name .. " x" .. sale.count .. " for " .. priceText, 1, 1, 0.5)
                    else
                        if core:debuggingIsEnabled() then
                            DEFAULT_CHAT_FRAME:AddMessage("Failed to sell: " .. sale.name .. " x" .. sale.count, 1, 0, 0)
                        end
                    end
                end
                DEFAULT_CHAT_FRAME:AddMessage("KaChing: Sold " .. itemsSold .. " items for " .. priceText, 1, 1, 0.5)
                delayFrame:SetScript("OnUpdate", nil)
            end
        end)
    else
        DEFAULT_CHAT_FRAME:AddMessage("KaChing: No items sold.", 1, 1, 0.5)
    end
end

-- Creates the KaChing button in the merchant frame
local buttonCreated
function sell.createKaChingButton()
    if buttonCreated then return end

    local button = CreateFrame("Button", "KaChingBtn", MerchantFrame, "UIPanelButtonTemplate")
    button:SetText("KaChing")
    button:SetWidth(90)
    button:SetHeight(21)
    button:SetPoint("TOPRIGHT", -50, -45)
    button:SetScript("OnClick", function()
        sell.sellItems()
    end)

    buttonCreated = true
end

-- Log file loading if debugging is enabled
if DEFAULT_CHAT_FRAME and core:debuggingIsEnabled() then
    DEFAULT_CHAT_FRAME:AddMessage("SellItems.lua is loaded", 1, 1, 0.5)
end 
