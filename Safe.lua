-- Safe.lua  — Turtle WoW / Lua 5.0 wrappers (no select())
-- ORIGINAL DATE: 10 August, 2025

KaChing = KaChing or {}
KaChing.Safe = KaChing.Safe or {}

local safe = KaChing.Safe
local core = KaChing.Core
local dbg  = KaChing.DebugTools
local L    = KaChing.L or {}

-- Compact debug helper (Lua 5.0 varargs via 'arg')
local function dprint(...)
    if core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
        if dbg and dbg.print then dbg:print(unpack(arg)) end
    end
end

-- Generic pcall wrapper (returns up to 6 values; extend if you need more)
local function safe_call(fn, a1,a2,a3,a4,a5,a6)
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
    local n, tag = safe_call(GetContainerNumSlots, bag)
    if not n or tag == "error" then return 0 end
    return n or 0
end

-- Always returns: texture, count, lockedBool
function safe.GetContainerItemInfo(bag, slot)
    if not valid_bag(bag) then return nil, 0, false end
    if type(slot) ~= "number" or slot < 1 then return nil, 0, false end
    local tex, cnt, locked = safe_call(GetContainerItemInfo, bag, slot)
    return tex, (cnt or 0), norm_locked(locked)
end

-- May be nil or a bare "[Item Name]" on TWOW
function safe.GetContainerItemLink(bag, slot)
    if not valid_bag(bag) then return nil end
    if type(slot) ~= "number" or slot < 1 then return nil end
    local link = safe_call(GetContainerItemLink, bag, slot)
    return link
end

-- Cursor‑safe UseContainerItem
function safe.UseContainerItem(bag, slot)
    if CursorHasItem and CursorHasItem() then
        if ClearCursor then ClearCursor() end
    end
    local ok = safe_call(UseContainerItem, bag, slot)
    return ok ~= nil
end

-- GetItemInfo (pass through nils without exploding)
function safe.GetItemInfo(item)
    return safe_call(GetItemInfo, item)
end

-- Tooltip:SetBagItem (returns true/false)
function safe.TooltipSetBagItem(tip, bag, slot)
    if not tip or not tip.ClearLines or not tip.SetBagItem then return false end
    if not valid_bag(bag) or type(slot) ~= "number" or slot < 1 then return false end
    local ok = safe_call(tip.SetBagItem, tip, bag, slot)
    return ok ~= nil
end

-- Slot occupancy probe
function safe.SlotOccupied(bag, slot)
    local tex = safe.GetContainerItemInfo(bag, slot)
    return tex ~= nil
end

-- Buyback helpers (some UIs throw if called too early)
function safe.GetNumBuybackItems()
    local n = safe_call(GetNumBuybackItems)
    if type(n) ~= "number" then return 0 end
    return n
end

-- Cursor helpers
function safe.CursorHasItem()
    local v = safe_call(CursorHasItem)
    return v and true or false
end
function safe.ClearCursor()
    safe_call(ClearCursor)
end

if core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
    DEFAULT_CHAT_FRAME:AddMessage("Safe.lua is loaded", 1, 1, 0.5)
end
