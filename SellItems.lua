-- SellItems.lua (Turtle/1.12, Lua 5.0)
-- SIMPLIFIED BATCH SELLER (up to 12 per click; continues on next click)
-- UPDATED: 19 August, 2025

--[[ Lua 5.0 notes:
- No string.match; use string.find / string.gfind
- No '#' length operator; use table.getn(t)
- Use tinsert(t, v) instead of table.insert(t, v)
- Handlers use 'this' and 'event', not 'self'
]]

KaChing = KaChing or {}
KaChing.SellItems = KaChing.SellItems or {}

local core  = KaChing.Core or {}
local dbg   = KaChing.DebugTools or {}
local L     = KaChing.L or {}
local sell  = KaChing.SellItems
local safe  = KaChing.Safe or {}

-- ---------------- Public helpers ----------------
function sell.merchantOpen()
    return (MerchantFrame and MerchantFrame:IsShown()) and true or false
end

function sell.SetButtonEnabled(enabled)
    local btn = getglobal("KaChingBtn")
    if not btn then return end
    if enabled then btn:Enable() else btn:Disable() end
end

-- ---------------- Saved vars ----------------
KACHING_SAVED_OPTIONS     = KACHING_SAVED_OPTIONS or {}
KaChing_ExcludedItemsList = KaChing_ExcludedItemsList or {}
KaChing.ExclusionList     = KaChing.ExclusionList or {
    ["hearthstone"] = true,
    ["refreshing spring water"] = true,
}

-- ---------------- Money + logging ----------------
local function formatMoney(copper)
    if type(copper) ~= "number" or copper <= 0 then return "0g 0s 0c" end
    local g = math.floor(copper / 10000)
    local r = copper - g * 10000
    local s = math.floor(r / 100)
    local c = r - s * 100
    local out = ""
    if g > 0 then out = out .. g .. "g " end
    if s > 0 or g > 0 then out = out .. s .. "s " end
    out = out .. c .. "c"
    return out
end

local function logInfo(msg) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg, 1, 1, 0.5) end end
local function logWarn(msg) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg, 1, 0.82, 0) end end
local function logErr (msg) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg, 1, 0, 0) end end
local function dprint(msg)
    if core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
        if dbg and dbg.print then dbg:print(msg) else logInfo("[DBG] "..tostring(msg)) end
    end
end

-- ---------------- Tooltip scanner ----------------
if not sell._scanTip then
    local ok, tipObj = pcall(CreateFrame, "GameTooltip", "KaChingScanTip", UIParent, "GameTooltipTemplate")
    local tip = ok and tipObj or GameTooltip
    if tip and tip.SetOwner then tip:SetOwner(UIParent or WorldFrame, "ANCHOR_NONE") end
    sell._scanTip = tip
end

local function tipLeftText(i)
    local name = (sell._scanTip and sell._scanTip.GetName) and sell._scanTip:GetName() or "GameTooltip"
    local fs = getglobal(name.."TextLeft"..i)
    if fs then
        if fs.GetTextColor then
            local r,g,b = fs:GetTextColor()
            return fs:GetText(), r,g,b
        end
        return fs:GetText()
    end
end

local function approx(a,b) return a > b - 0.05 and a < b + 0.05 end

local function TooltipSetBagItemSafe(tip, bag, slot)
    if not (tip and tip.SetBagItem and tip.ClearLines and tip.SetOwner) then return false end
    tip:SetOwner(UIParent or WorldFrame, "ANCHOR_NONE")
    tip:ClearLines()
    local ok = pcall(tip.SetBagItem, tip, bag, slot)
    if not ok then return false end
    if tip.Show then tip:Show() end
    return true
end

local function tooltipIsGray(bag, slot)
    local tip = sell._scanTip
    if not TooltipSetBagItemSafe(tip, bag, slot) then
        if tip and tip.Hide then tip:Hide() end
        return false
    end
    local _, r,g,b = tipLeftText(1)
    if tip and tip.Hide then tip:Hide() end
    if not (r and g and b) then return false end
    return approx(r, 0.62) and approx(g, 0.62) and approx(b, 0.62)
end

local function tooltipNameLower(bag, slot)
    local tip = sell._scanTip
    if not TooltipSetBagItemSafe(tip, bag, slot) then
        if tip and tip.Hide then tip:Hide() end
        return nil
    end
    local t = tipLeftText(1)
    if tip and tip.Hide then tip:Hide() end
    if type(t) == "string" then return string.lower(t) end
end

-- ---------------- Helpers: link + slot ----------------
local function isGrayByLink(link)
    if type(link) ~= "string" then return false end
    local _, _, hex = string.find(link, "|cff(%x%x%x%x%x%x)")
    return hex == "9d9d9d"
end

local function linkHex6AndName(link)
    if type(link) ~= "string" then return nil, nil end
    local _, _, hex8, name = string.find(link, "|c(%x%x%x%x%x%x%x%x).-|h%[(.-)%]|h|r")
    if not hex8 then return nil, name end
    return string.sub(hex8, 3, 8), name
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

-- ---------------- Option gate for whites (future) ----------------
local function whitesEnabled()
    if type(KACHING_SAVED_OPTIONS) ~= "table" then return false end
    return KACHING_SAVED_OPTIONS.sellWhiteAW and true or false
end

-- Classic-safe slot/equip filters (kept minimal for Phase I)
local SLOT_OK = {
    ["Head"] = true, ["Shoulder"] = true, ["Back"] = true,
    ["Chest"] = true, ["Wrist"] = true, ["Hands"] = true,
    ["Waist"] = true, ["Legs"] = true, ["Feet"] = true,
    ["Main Hand"] = true, ["Off Hand"] = true, ["One-Hand"] = true,
    ["Two-Hand"] = true, ["Ranged"] = true, ["Thrown"] = true,
    ["Shield"] = true, ["Wand"] = true, ["Polearm"] = true,
    ["Dagger"] = true, ["Axe"] = true, ["Sword"] = true,
    ["Mace"] = true, ["Staff"] = true, ["Bow"] = true,
    ["Gun"] = true, ["Crossbow"] = true, ["Held In Off-hand"] = true,
}
local function slotAllowed(slotText) return SLOT_OK[slotText] and true or false end

-- ---------------- Unified “should sell?” ----------------
function sell.wantSell(bag, slot)
    local texture = GetContainerItemInfo(bag, slot)
    if not texture then return false end

    local link = GetContainerItemLink(bag, slot)
    if isGrayByLink(link) then return true, "(gray)" end

    local name, isWhite, slotText
    -- read name via tooltip
    name = tooltipNameLower(bag, slot)
    -- exclusion check (use both explicit and runtime maps)
    if name and (KaChing_ExcludedItemsList[name] or KaChing.ExclusionList[name]) then
        return false
    end

    -- fallback gray via tooltip color
    if tooltipIsGray(bag, slot) then
        return true, name or "(gray)"
    end

    -- white armor/weapon (Phase I: optional)
    if whitesEnabled() then
        if link then
            local hex6, disp = linkHex6AndName(link)
            if (disp and (KaChing_ExcludedItemsList[string.lower(disp)] or KaChing.ExclusionList[string.lower(disp)])) then
                return false
            end
            if hex6 == "ffffff" then
                -- minimal slot check through tooltip (Classic-friendly)
                local tip = sell._scanTip
                if TooltipSetBagItemSafe(tip, bag, slot) then
                    local tipName = tip.GetName and tip:GetName() or "GameTooltip"
                    local i
                    for i = 2, 12 do
                        local fsR = getglobal(tipName.."TextRight"..i)
                        if fsR and slotAllowed(fsR:GetText()) then return true, disp or name end
                        local fsL = getglobal(tipName.."TextLeft"..i)
                        if fsL and slotAllowed(fsL:GetText()) then return true, disp or name end
                    end
                    if tip and tip.Hide then tip:Hide() end
                end
            end
        end
    end

    return false
end

-- ---------------- Persistent queue across clicks ----------------
sell._queue = sell._queue or {}

local function buildQueueIfNeeded()
    -- If queue already has pending entries, keep them (player is continuing)
    if sell._queue and sell._queue[1] ~= nil then return end

    local q = {}
    local bag
    for bag = 0, 4 do
        if isBagValid(bag) then
            local slots = GetContainerNumSlots(bag)
            local slot
            for slot = 1, slots do
                local ok, _ = sell.wantSell(bag, slot)
                if ok then tinsert(q, { bag = bag, slot = slot }) end
            end
        end
    end

    table.sort(q, function(a, b)
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    sell._queue = q
end

-- ---------------- Sell up to 12 per click ----------------
function sell.sellItems()
    if not sell.merchantOpen() then
        logErr("KaChing: Please open a merchant window to sell items.")
        return
    end

    buildQueueIfNeeded()
    local total = table.getn(sell._queue or {})
    if total == 0 then
        logInfo("KaChing: No eligible items to sell.")
        sell.SetButtonEnabled(false)
        return
    end

    local moneyStart = GetMoney()
    local batch = (total > 12) and 12 or total
    local processed = 0

    local function proceed()
        if processed >= batch then
            -- remove processed from the front
            local i
            for i = 1, processed do
                table.remove(sell._queue, 1)
            end
            local gain = GetMoney() - (moneyStart or 0)
            if gain > 0 then
                logInfo("[KaChing] Sold "..processed.." item(s). Gold gained: "..formatMoney(gain))
            end
            -- DO NOT disable here; only disable if queue is empty (we check below)
            -- defer a half-second-ish to let buyback settle, then update button state
            local f = CreateFrame("Frame"); local t = 0
            f:SetScript("OnUpdate", function()
                t = t + (arg1 or 0)
                if t >= 0.5 then
                    f:SetScript("OnUpdate", nil)
                    if not sell._queue or sell._queue[1] == nil then
                        sell.SetButtonEnabled(false)
                    else
                        sell.SetButtonEnabled(true)
                    end
                end
            end)
            return
        end

        processed = processed + 1
        local job = sell._queue[processed]
        if not job then processed = processed - 1; return proceed() end

        -- Sell a single slot, then continue next frame
        -- (Use your Safe.lua helper if available; otherwise UseContainerItem)
        local function afterOne()
            local f = CreateFrame("Frame")
            f:SetScript("OnUpdate", function()
                f:SetScript("OnUpdate", nil); f:Hide()
                proceed()
            end)
            f:Show()
        end

        if safe and safe.SellSlot then
            safe.SellSlot(job.bag, job.slot, afterOne, { timeout_sec = 0.35, max_retries = 1 })
        else
            -- fallback
            UseContainerItem(job.bag, job.slot)
            afterOne()
        end
    end

    proceed()
end

-- ---------------- Merchant button ----------------
local BUTTON_CREATED = false
function sell.createKaChingButton()
    if BUTTON_CREATED then return end
    if not MerchantFrame then return end

    local button = CreateFrame("Button", "KaChingBtn", MerchantFrame, "UIPanelButtonTemplate")
    button:SetText("KaChing")
    button:SetWidth(90)
    button:SetHeight(21)
    button:SetPoint("TOPRIGHT", -50, -45)

    button:SetScript("OnClick", function()
        -- NOTE: we do NOT clear the queue here; multiple clicks continue the queue
        sell.sellItems()
        -- post-sell: re-check after half a second and toggle button state
        local f = CreateFrame("Frame"); local t = 0
        f:SetScript("OnUpdate", function()
            t = t + (arg1 or 0)
            if t >= 0.5 then
                f:SetScript("OnUpdate", nil)
                if not sell._queue or sell._queue[1] == nil then
                    button:Disable()
                else
                    button:Enable()
                end
            end
        end)
    end)

    -- Tooltip
    button:EnableMouse(true)
    button:SetScript("OnEnter", function(self)
        if GameTooltip and self then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(L["KACHING_BTN_TOOLTIP"] or "Click to sell up to 12 items", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    BUTTON_CREATED = true
end

-- ---------------- Load ping ----------------
if core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
    DEFAULT_CHAT_FRAME:AddMessage("SellItems.lua (batch) loaded", 1, 1, 0.5)
end
