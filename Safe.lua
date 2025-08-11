-- Safe.lua  — Turtle WoW / Lua 5.0 wrappers (no select())
-- ORIGINAL DATE: 10 August, 2025

KaChing = KaChing or {}
KaChing.Safe = KaChing.Safe or {}

local safe = KaChing.Safe
local core = KaChing.Core
local dbg  = KaChing.DebugTools
local L    = KaChing.L or {}
local safe  = KaChing.Safe or {}

-- Generic pcall wrapper (returns up to 6 values; extend if you need more)
local function safeCall(fn, a1,a2,a3,a4,a5,a6)
    local ok, r1,r2,r3,r4,r5,r6 = pcall(fn, a1,a2,a3,a4,a5,a6)
    if not ok then
        if dbg and dbg.print then dbg:print("API error:", tostring(r1)) end
        return nil, "error", r1
    end
    return r1,r2,r3,r4,r5,r6
end

-- Bag range: 0..4 on 1.12
local function valid_bag(bag)
    return type(bag) == "number" and bag >= 0 and bag <= 4
end

-- Normalize locked flags (1/nil → boolean)
local function norm_locked(v)
    if v == true or v == false then return v end
    return (v == 1)
end

-- ========== Container / Item wrappers ==========

function safe.GetContainerNumSlots(bag)
    if not valid_bag(bag) then return 0 end
    local n, tag = safeCall(GetContainerNumSlots, bag)
    if not n or tag == "error" then return 0 end
    return n or 0
end

-- Always returns: texture, count, lockedBool
function safe.GetContainerItemInfo(bag, slot)
    if not valid_bag(bag) then return nil, 0, false end
    if type(slot) ~= "number" or slot < 1 then return nil, 0, false end
    local tex, cnt, locked = safeCall(GetContainerItemInfo, bag, slot)
    return tex, (cnt or 0), norm_locked(locked)
end

-- May be nil or a bare "[Item Name]" on TWOW
function safe.GetContainerItemLink(bag, slot)
    if not valid_bag(bag) then return nil end
    if type(slot) ~= "number" or slot < 1 then return nil end
    local link = safeCall(GetContainerItemLink, bag, slot)
    return link
end

-- Cursor‑safe UseContainerItem
function safe.UseContainerItem(bag, slot)
    if CursorHasItem and CursorHasItem() then
        if ClearCursor then ClearCursor() end
    end
    local ok = safeCall(UseContainerItem, bag, slot)
    return ok ~= nil
end

-- GetItemInfo (pass through nils without exploding)
function safe.GetItemInfo(item)
    return safeCall(GetItemInfo, item)
end

-- Tooltip:SetBagItem (returns true/false)
function safe.TooltipSetBagItem(tip, bag, slot)
    if not tip or not tip.ClearLines or not tip.SetBagItem then return false end
    if not valid_bag(bag) or type(slot) ~= "number" or slot < 1 then return false end
    local ok = safeCall(tip.SetBagItem, tip, bag, slot)
    return ok ~= nil
end

-- Slot occupancy probe
function safe.SlotOccupied(bag, slot)
    local tex = safe.GetContainerItemInfo(bag, slot)
    return tex ~= nil
end

-- Buyback helpers (some UIs throw if called too early)
function safe.GetNumBuybackItems()
    local n = safeCall(GetNumBuybackItems)
    if type(n) ~= "number" then return 0 end
    return n
end

-- Cursor helpers
function safe.CursorHasItem()
    local v = safeCall(CursorHasItem)
    return v and true or false
end
function safe.ClearCursor()
    safeCall(ClearCursor)
end

-- -- Try to read cursor payload safely (Classic)
-- function safe.GetCursorInfo()
--     local ok, ctype, p1, p2, p3 = safeCall(GetCursorInfo)
--     if not ok then return nil end
--     return ctype, p1, p2, p3
-- end

-- === Hidden tooltip for safe name reads ===
local HIDDEN_TIP_NAME = "KaChing_SafeTip"
local hiddenTip = getglobal(HIDDEN_TIP_NAME)
if not hiddenTip then
    hiddenTip = CreateFrame("GameTooltip", HIDDEN_TIP_NAME, UIParent, "GameTooltipTemplate")
    hiddenTip:SetOwner(UIParent, "ANCHOR_NONE")
end

local function safeTooltipGetFirstLineFromBagItem(bag, slot)
    if not hiddenTip or not hiddenTip.ClearLines then return nil end
    hiddenTip:ClearLines()
    local ok = safe.TooltipSetBagItem and safe.TooltipSetBagItem(hiddenTip, bag, slot)
    if not ok then return nil end
    local fs = getglobal(HIDDEN_TIP_NAME.."TextLeft1")
    if fs and fs.GetText then
        local text = fs:GetText()
        if type(text) == "string" and text ~= "" then
            return text
        end
    end
    return nil
end

-- Try to locate the bag/slot that is currently "picked up" (locked) when dragging
local function findLockedCursorBagSlot()
    local bag
    for bag = 0, 4 do
        local slots = safe.GetContainerNumSlots(bag)
        if slots and slots > 0 then
            local slot
            for slot = 1, slots do
                local tex, cnt, locked = safe.GetContainerItemInfo(bag, slot)
                if tex and locked then
                    return bag, slot
                end
            end
        end
    end
    return nil, nil
end

-- Public: Cursor info with Vanilla fallback
function safe.GetCursorInfo()
    -- Modern path (won’t exist on 1.12, but keep for forward compat)
    if type(GetCursorInfo) == "function" then
        local r1, r2, r3, r4 = safeCall(GetCursorInfo)
        -- safeCall returns (nil,"error",errmsg) on failure; we only care about success case
        if r1 ~= nil or r2 ~= "error" then
            -- r1=ctype ("item"|"spell"|...), r2=nameOrID, r3=linkOrRank, r4=extra
            return r1, r2, r3, r4
        end
        return nil
    end

    -- Vanilla/Turtle fallback: infer from locked bag slot while item is on cursor
    if safe.CursorHasItem and safe.CursorHasItem() then
        local bag, slot = findLockedCursorBagSlot()
        if bag ~= nil and slot ~= nil then
            -- Prefer a robust name via tooltip (since GetContainerItemLink may be just "[Name]")
            local name = safeTooltipGetFirstLineFromBagItem(bag, slot)
            -- Also try the link form (may be "[Name]" on 1.12)
            local link = safe.GetContainerItemLink and safe.GetContainerItemLink(bag, slot)
            -- Emulate the modern return shape used by your OptionsMenu.lua:
            -- ctype="item", p1=name, p2=link (may be nil), p3=nil
            if name or link then
                return "item", name, link, nil
            end
        end
    end

    -- No payload we can detect
    return nil
end



if core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
    DEFAULT_CHAT_FRAME:AddMessage("Safe.lua is loaded", 1, 1, 0.5)
end
