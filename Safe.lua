--------------------------------------------------------------------------------------
-- Safe.lua
-- UPDATED: 13 August, 2025 (TWOW/1.12 shims + pcall wrappers + SellSlot) — Lua 5.0
-- Notes: no select(), no "..." in locals, use arg1 in OnUpdate, use tinsert
--------------------------------------------------------------------------------------

KaChing = KaChing or {}
KaChing.Safe = KaChing.Safe or {}
local safe  = KaChing.Safe

-- Read-only local aliases
local core = KaChing.Core
local dbg  = KaChing.DebugTools

-- ============================ pcall helper ============================
-- Returns: ok:boolean, r1,r2,r3,r4,r5,r6 (Lua 5.0—no select/unpack here)
local function safeCall(fn, a1,a2,a3,a4,a5,a6)
    if type(fn) ~= "function" then return false, "no_fn" end
    local ok, r1,r2,r3,r4,r5,r6 = pcall(fn, a1,a2,a3,a4,a5,a6)
    if not ok and dbg and dbg.print then
        dbg:print("API error:", tostring(r1))
    end
    return ok, r1,r2,r3,r4,r5,r6
end

-- ============================ Thin wrappers (pcall) ============================
local function w_GetContainerNumSlots(bag)
    if type(bag) ~= "number" or bag < 0 or bag > 4 then return 0 end
    local ok, n = safeCall(GetContainerNumSlots, bag)
    return (ok and n) or 0
end

local function w_GetContainerItemInfo(bag, slot)
    local ok, t,c,l = safeCall(GetContainerItemInfo, bag, slot)
    if not ok then return nil, nil, nil end
    return t,c,l
end

local function w_GetContainerItemLink(bag, slot)
    local ok, link = safeCall(GetContainerItemLink, bag, slot)
    if not ok then return nil end
    return link
end

local function w_UseContainerItem(bag, slot)
    local ok = safeCall(UseContainerItem, bag, slot)
    return ok
end

local function w_GetNumBuybackItems()
    local ok, n = safeCall(GetNumBuybackItems)
    if not ok then return 0 end
    return n or 0
end

local function w_CursorHasItem()
    local ok, has = safeCall(CursorHasItem)
    return ok and (has and true or false) or false
end

local function w_ClearCursor()
    safeCall(ClearCursor)
end

local function w_GetTime()
    local ok, t = safeCall(GetTime)
    return ok and (t or 0) or 0
end

-- Public: keep Blizzard-like names for external callers
function safe.GetContainerNumSlots(bag) 
    return w_GetContainerNumSlots(bag) 
end

-- ============================ Name helpers ============================
-- Extract lower-cased item name via link or tooltip (1.12 safe)
function safe.GetItemNameLower(bag, slot)
    local link = w_GetContainerItemLink(bag, slot)
    if type(link) == "string" then
        local _, _, name = string.find(link, "%[(.-)%]")
        if name and name ~= "" then
            return string.lower(name), name
        end
    end

    -- Tooltip fallback (minimal, 1.12-safe)
    if not KaChing_SafeScanTip then
        local tip = CreateFrame("GameTooltip", "KaChing_SafeScanTip", UIParent, "GameTooltipTemplate")
        tip:SetOwner(UIParent or WorldFrame, "ANCHOR_NONE")
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

-- ============================ Cursor helpers ============================
function safe.FindLockedCursorSlot()
    local bag
    for bag = 0, 4 do
        local n = w_GetContainerNumSlots(bag)
        if n and n > 0 then
            local slot
            for slot = 1, n do
                local tex, cnt, locked = w_GetContainerItemInfo(bag, slot)
                if locked then
                    return bag, slot
                end
            end
        end
    end
    return nil, nil
end

-- Returns: "item", bag, slot, lowerName, displayName, texture OR nil
function safe.GetCursorInfo()
    if w_CursorHasItem() then
        local bag, slot = safe.FindLockedCursorSlot()
        if bag and slot then
            local lowerName, displayName = safe.GetItemNameLower(bag, slot)
            local tex = w_GetContainerItemInfo(bag, slot)
            local texture = (type(tex) == "string") and tex or nil
            return "item", bag, slot, lowerName, displayName, texture
        end
    end
    return nil
end

-- Provide global alias if missing (older code might call GetCursorInfo())
if not GetCursorInfo then
    function GetCursorInfo()
        return safe.GetCursorInfo()
    end
end

-- Helper: extract itemID from item link (Lua 5.0)
local function KC_Safe_ExtractItemIDFromLink(link)
    if type(link) ~= "string" then return nil end
    local _, _, id = string.find(link, "item:(%d+)")
    if id then return tonumber(id) end
    return nil
end

-- Retail-shaped, but **bag-only** (used by Options UI)
-- Returns: "item", itemID, itemLink, bag, slot  OR  nil, "reason"
function safe.GetCursorInfo_BagOnly()
    if not w_CursorHasItem() then
        if core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
            DEFAULT_CHAT_FRAME:AddMessage("Safe:GetCursorInfo_BagOnly(): no_item", 1, 0.4, 0.4)
        end
        return nil, "no_item"
    end
    local bag, slot = safe.FindLockedCursorSlot()
    if not bag then
        if core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
            DEFAULT_CHAT_FRAME:AddMessage("Safe:GetCursorInfo_BagOnly(): not_from_bag", 1, 0.4, 0.4)
        end
        return nil, "not_from_bag"
    end

    local link = w_GetContainerItemLink(bag, slot)
    local itemID = KC_Safe_ExtractItemIDFromLink(link) or 0

    if core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
        DEFAULT_CHAT_FRAME:AddMessage("Safe:GetCursorInfo_BagOnly(): ok bag="..bag.." slot="..slot, 0.6, 1, 0.6)
    end

    return "item", itemID, link, bag, slot
end

-- ============================ Selling (pcall + timing) ============================
-- onDone(sold:boolean, reason:string)
-- opts = { timeout_sec = 0.35, max_retries = 1 }
function safe.SellSlot(bag, slot, onDone, opts)
    local timeout     = (opts and opts.timeout_sec) or 0.35
    local max_retries = (opts and opts.max_retries) or 0
    local tries       = 0

    local f = CreateFrame("Frame")
    local elapsed = 0
    local state = "issue"   -- "issue" -> UseContainerItem; "wait" -> watch disappearance

    local function done(sold, reason)
        f:SetScript("OnUpdate", nil)
        f:Hide()
        if onDone then
            local ok = pcall(onDone, sold, reason)
            if not ok and dbg and dbg.print then dbg:print("safe.SellSlot onDone error") end
        end
    end

    f:SetScript("OnUpdate", function()
        local dt = arg1 or 0
        elapsed = elapsed + dt

        -- NEW (honors opts.ignore_buyback):
        if not (opts and opts.ignore_buyback) and w_GetNumBuybackItems() >= 12 then
            done(false, "buyback_full")
            return
        end

        -- Clear ghost cursor if present
        if w_CursorHasItem() then
            w_ClearCursor()
            return
        end

        local tex, cnt, locked = w_GetContainerItemInfo(bag, slot)

        if state == "issue" then
            if not tex then done(true, "already_empty"); return end
            if locked then return end

            if not w_UseContainerItem(bag, slot) then
                done(false, "use_error")
                return
            end
            state = "wait"
            elapsed = 0
            return
        end

        -- state == "wait": did the item leave the slot?
        tex, cnt, locked = w_GetContainerItemInfo(bag, slot)
        if not tex then
            done(true, "sold")
            return
        end

        if elapsed >= timeout then
            tries = tries + 1
            if tries > max_retries then
                done(false, "timeout")
            else
                state = "issue"
                elapsed = 0
            end
        end
    end)

    f:Show()
end

-- ============================ Debug ping ============================
if core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
    DEFAULT_CHAT_FRAME:AddMessage("Safe.lua loaded", 1, 1, 0.5)
end
