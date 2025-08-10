--[[ 
Command.lua
AUTHOR: mtpeterson
DATE: 7 August, 2025

DESCRIPTION:
Implements slash commands for KaChing addon in Turtle WoW (1.12.1 API).
- /slot <slotId>: Displays item info for Bag 0, Slot <slotId>.
- /kachingmoney: Displays player's current money and formatted value.
- /kachingdebugitem <slotId>: Debugs item in Bag 0, Slot <slotId> for quality, rarity, and color.

PROGRAMMING NOTES:
Lua 5.0:
- No string.match, use string.find or string.gfind
- No goto or select()
- _G is available (not _ENV)
- Use table.getn(t) instead of #t
- Use tinsert(t, v) instead of table.insert(t, v)
]]

KaChing = KaChing or {}
local core = KaChing.Core

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

-- Register slash command: /slot
SLASH_ITEM1 = "/slot"
SlashCmdList["ITEM"] = function(input)
    -- Parse input for slotId
    local bagId = 0
    local slotId = nil
    local args = {}
    for arg in string.gfind(input, "%S+") do
        tinsert(args, arg)
    end
    if table.getn(args) >= 1 then
        slotId = tonumber(args[1])
    end

    if not slotId then
        DEFAULT_CHAT_FRAME:AddMessage("KaChing: Invalid slotId", 1, 0, 0)
        return
    end

    -- Validate bag
    local numSlots = GetContainerNumSlots(bagId)
    if slotId > numSlots then
        DEFAULT_CHAT_FRAME:AddMessage("KaChing: Invalid bag " .. bagId .. " or slot " .. slotId .. " (max slots: " .. numSlots .. ")", 1, 0, 0)
        return
    end

    -- Get item info
    local link = GetContainerItemLink(bagId, slotId)
    if link then
        local start, stop = string.find(link, "item:(%d+)")
        local itemId = start and tonumber(string.sub(link, start + 5, stop))
        local name = GetItemInfo(link)
        DEFAULT_CHAT_FRAME:AddMessage("KaChing: Bag " .. bagId .. ", Slot " .. slotId .. ": Name=" .. (name or "nil") .. ", ID=" .. (itemId or "nil"), 1, 1, 0.5)
    else
        DEFAULT_CHAT_FRAME:AddMessage("KaChing: No item in Bag " .. bagId .. ", Slot " .. slotId, 1, 1, 0.5)
    end
end

-- Register slash command: /kachingmoney
SLASH_KACHINGMONEY1 = "/kachingmoney"
SLASH_KACHINGMONEY2 = "/KachingMoney" -- Alias for case sensitivity
SlashCmdList["KACHINGMONEY"] = function()
    local money = GetMoney()
    local formattedMoney = formatMoney(money)
    DEFAULT_CHAT_FRAME:AddMessage("KaChing Money: " .. (money or "nil") .. " copper (" .. formattedMoney .. ")", 1, 1, 0.5)
end

-- Register slash command: /kachingdebugitem
SLASH_KACHINGDEBUGITEM1 = "/kachingdebugitem"
SlashCmdList["KACHINGDEBUGITEM"] = function(input)
    -- Parse input for slotId
    local bagId = 0
    local slotId = nil
    local args = {}
    for arg in string.gfind(input, "%S+") do
        tinsert(args, arg)
    end
    if table.getn(args) >= 1 then
        slotId = tonumber(args[1])
    end

    if not slotId then
        DEFAULT_CHAT_FRAME:AddMessage("KaChing: Invalid slotId", 1, 0, 0)
        return
    end

    -- Validate bag
    local numSlots = GetContainerNumSlots(bagId)
    if slotId > numSlots then
        DEFAULT_CHAT_FRAME:AddMessage("KaChing: Invalid bag " .. bagId .. " or slot " .. slotId .. " (max slots: " .. numSlots .. ")", 1, 0, 0)
        return
    end

    -- Get item info
    local link = GetContainerItemLink(bagId, slotId)
    if link then
        local info = {GetContainerItemInfo(bagId, slotId)}
        local quality = info[4]
        local name, _, rarity = GetItemInfo(link)
        local color = "none"
        local start, stop = string.find(link, "|cff(%x%x%x%x%x%x)")
        if start then
            color = string.sub(link, start + 4, stop)
        end
        DEFAULT_CHAT_FRAME:AddMessage("KaChing Debug: Name=" .. (name or "nil") .. ", Quality=" .. (quality or "nil") .. ", Rarity=" .. (rarity or "nil") .. ", Color=" .. color, 1, 1, 0.5)
    else
        DEFAULT_CHAT_FRAME:AddMessage("KaChing: No item in Bag " .. bagId .. ", Slot " .. slotId, 1, 1, 0.5)
    end
end


-- Log loading
if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("Command.lua loaded", 0, 1, 0)
end