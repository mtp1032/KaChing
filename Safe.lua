--------------------------------------------------------------------------------------
-- Safe.lua
-- UPDATED: 20 Aug 2025 (Classic/Turtle 1.12, Lua 5.0)
-- - Consolidates helpers
-- - Adds robust safe.SellSlot() (no buyback gating; Classic overwrites oldest)
-- - 5.0-safe: no string.match, no select, uses arg1 in OnUpdate
--------------------------------------------------------------------------------------

KaChing      = KaChing or {}
KaChing.Safe = KaChing.Safe or {}
local safe   = KaChing.Safe

-- (Optional) tiny debug helper
local function kcdebug(...)
    local core = KaChing.Core
    if core and core.debuggingIsEnabled and core:debuggingIsEnabled() and DEFAULT_CHAT_FRAME then
        local out = ""
        local i, v
        for i = 1, arg.n do
            v = arg[i]
            out = out .. (i > 1 and " " or "") .. tostring(v)
        end
        DEFAULT_CHAT_FRAME:AddMessage("[KaChing] "..out, 0.75, 0.9, 1.0)
    end
end

-- =========================
-- Utilities
-- =========================
local function safeCall(fn, a1,a2,a3,a4,a5,a6)
    local ok, r1,r2,r3,r4,r5,r6 = pcall(fn, a1,a2,a3,a4,a5,a6)
    if not ok then
        kcdebug("API error:", tostring(r1))
        return nil, "error", r1
    end
    return r1,r2,r3,r4,r5,r6
end

local function valid_bag(bag)
    return type(bag) == "number" and bag >= 0 and bag <= 4
end

-- =========================
-- Shims / wrappers
-- =========================

-- GetContainerNumSlots (single definition)
function safe.GetContainerNumSlots(bag)
    if not valid_bag(bag) then return 0 end
    if GetContainerNumSlots then
        local n = GetContainerNumSlots(bag)
        return n or 0
    end
    return 0
end

-- Lower-cased item name via link or tooltip (safe for 1.12)
function safe.GetItemNameLower(bag, slot)
    local link = GetContainerItemLink and GetContainerItemLink(bag, slot)
    if type(link) == "string" then
        local _, _, name = string.find(link, "%[(.-)%]")
        if name and name ~= "" then
            return string.lower(name), name
        end
    end
    -- Tooltip fallback
    if not KaChing_SafeScanTip then
        local tip = CreateFrame("GameTooltip", "KaChing_SafeScanTip", UIParent, "GameTooltipTemplate")
        tip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    KaChing_SafeScanTip:ClearLines()
    if KaChing_SafeScanTip.SetBagItem then
        KaChing_SafeScanTip:SetBagItem(bag, slot)
        local fs = getglobal("KaChing_SafeScanTipTextLeft1")
        if fs then
            local t = fs:GetText()
            if type(t) == "string" and t ~= "" then
                return string.lower(t), t
            end
        end
    end
    return nil, nil
end

-- Find the bag/slot whose item is currently "locked"
function safe.FindLockedCursorSlot()
    local bag
    for bag = 0, 4 do
        local n = safe.GetContainerNumSlots(bag)
        if n and n > 0 then
            local slot
            for slot = 1, n do
                local tex, cnt, locked = GetContainerItemInfo(bag, slot)
                if locked then return bag, slot end
            end
        end
    end
    return nil, nil
end

-- 1.12 replacement for GetCursorInfo() for items only
function safe.GetCursorInfo()
    if CursorHasItem and CursorHasItem() then
        local bag, slot = safe.FindLockedCursorSlot()
        if bag and slot then
            local lowerName, displayName = safe.GetItemNameLower(bag, slot)
            local tex = GetContainerItemInfo and GetContainerItemInfo(bag, slot)
            local texture = (type(tex) == "string") and tex or nil
            return "item", bag, slot, lowerName, displayName, texture
        end
    end
    return nil
end

-- Provide global alias if missing
if not GetCursorInfo then
    function GetCursorInfo()
        return safe.GetCursorInfo()
    end
end

-- Extract itemID from link (Lua 5.0-safe)
local function KC_Safe_ExtractItemIDFromLink(link)
    if type(link) ~= "string" then return nil end
    local _, _, id = string.find(link, "item:(%d+)")
    if id then return tonumber(id) end
    return nil
end

-- Bag-only cursor helper (retail-shaped)
-- Returns: "item", itemID, itemLink, bag, slot    OR    nil, "reason"
function safe.GetCursorInfo_BagOnly()
    if not (CursorHasItem and CursorHasItem()) then
        kcdebug("Safe:GetCursorInfo_BagOnly(): no_item")
        return nil, "no_item"
    end
    local bag, slot = safe.FindLockedCursorSlot()
    if not bag then
        kcdebug("Safe:GetCursorInfo_BagOnly(): not_from_bag")
        return nil, "not_from_bag"
    end
    local link = GetContainerItemLink and GetContainerItemLink(bag, slot)
    local itemID = KC_Safe_ExtractItemIDFromLink(link) or 0
    kcdebug("Safe:GetCursorInfo_BagOnly(): ok bag="..bag.." slot="..slot)
    return "item", itemID, link, bag, slot
end

-- =========================
-- The important bit: SellSlot
-- =========================
-- Attempts to sell the item at (bag,slot) to an open merchant.
-- Calls: done(sold:boolean, reason:string|nil)
-- opts: { timeout_sec=0.4, max_retries=1 }
-- NOTE: We DO NOT gate on buyback being 12/12. Classic overwrites the oldest entry.
function safe.SellSlot(bag, slot, done, opts)
    local timeout   = (opts and opts.timeout_sec) or 0.4
    local maxRetry  = (opts and opts.max_retries) or 1
    local tries     = 0

    local function attempt()
        tries = tries + 1

        -- Preconditions
        if not (MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown()) then
            if done then done(false, "no_merchant") end
            return
        end

        local tex, count = GetContainerItemInfo(bag, slot)
        if not tex then
            if done then done(false, "empty") end
            return
        end
        local startTex  = tex
        local startCnt  = count or 0

        -- Try sell
        safeCall(UseContainerItem, bag, slot)

        -- Poll for change
        local elapsed = 0
        local f = CreateFrame("Frame")
        f:SetScript("OnUpdate", function()
            elapsed = elapsed + (arg1 or 0)

            local t2, c2 = GetContainerItemInfo(bag, slot)
            local changed = (t2 ~= startTex) or ((c2 or 0) ~= startCnt)

            if changed then
                f:SetScript("OnUpdate", nil); f:Hide()
                if done then done(true) end
                return
            end

            if elapsed >= timeout then
                f:SetScript("OnUpdate", nil); f:Hide()
                if tries < maxRetry then
                    attempt()
                else
                    -- No observable change: treat as not sold; caller decides to skip/continue
                    if done then done(false, "no_change") end
                end
            end
        end)
        f:Show()
    end

    attempt()
end

-- Optional: debug ping so you can see when this file loads
if KaChing.Core and KaChing.Core.debuggingIsEnabled and KaChing.Core.debuggingIsEnabled() then
    DEFAULT_CHAT_FRAME:AddMessage("Safe.lua loaded", 1, 1, 0.5)
end
