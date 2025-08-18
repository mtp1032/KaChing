--[[ 
Command.lua
DATE: 18 August, 2025 (adds /kaching diag; keeps Classic-safe idioms)

PROGRAMMING NOTES (Lua 5.0 - Turtle WoW):
- No string.match; use string.find / string.gfind
- No goto or select()
- _G is not available; use getglobal()
- No '#' length operator; use table.getn(t)
- Use tinsert(t, v) instead of table.insert(t, v)
- Avoid '%' modulo; compute with subtraction
]]

KaChing = KaChing or {}
KaChing.Command = KaChing.Command or {}

local cmd     = KaChing.Command
local sell    = KaChing.SellItems or {}
local options = KaChing.OptionsMenu or {}
local dbg     = KaChing.DebugTools or {}
local core    = KaChing.Core or {}

-- Graceful dbg.print
if not (dbg and dbg.print) then
    dbg = dbg or {}
    function dbg.print() end
end

-- --------- Utilities ---------
local function say(msg, r, g, b)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg, r or 1, g or 1, b or 1) end
end

-- trim + lowercase (no string.match)
local function trimLower(s)
    if not s then return "" end
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    s = string.lower(s)
    return s
end

local function tokenize(s)
    local out = {}
    local it = string.gfind(s or "", "%S+")
    while true do
        local w = it()
        if not w then break end
        tinsert(out, w)
    end
    return out
end

local function parseTwoNums(after)
    local b, s
    local args = tokenize(after)
    if table.getn(args) >= 2 then
        b = tonumber(args[1]); s = tonumber(args[2])
    end
    return b, s
end

-- Money pretty-printer w/o modulo
local function formatMoney(copper)
    if type(copper) ~= "number" then return "0g 0s 0c" end
    local sign = ""
    if copper < 0 then sign = "-" ; copper = -copper end
    local g = math.floor(copper / 10000)
    local rem = copper - g * 10000
    local s = math.floor(rem / 100)
    local c = rem - s * 100
    local out = ""
    if g > 0 then out = out .. g .. "g " end
    if s > 0 or g > 0 then out = out .. s .. "s " end
    out = out .. c .. "c"
    return sign .. out
end

-- --------- Debug gate (tolerant) ---------
local function getDebug()
    if core and core.debuggingIsEnabled then
        local ok, res = pcall(function() return core:debuggingIsEnabled() end)
        if ok then return res and true or false end
    end
    if KaChing_Config and KaChing_Config.debug ~= nil then
        return KaChing_Config.debug and true or false
    end
    if KACHING_SAVED_OPTIONS and KACHING_SAVED_OPTIONS.debug ~= nil then
        return KACHING_SAVED_OPTIONS.debug and true or false
    end
    return false
end

local function setDebug(val)
    if core and (core.SetDebugEnabled or core.setDebugEnabled) then
        local f = core.SetDebugEnabled or core.setDebugEnabled
        pcall(function() return f(core, val and true or false) end)
    end
    KaChing_Config = KaChing_Config or {}
    KaChing_Config.debug = (val and true or false)
    if KACHING_SAVED_OPTIONS then KACHING_SAVED_OPTIONS.debug = (val and true or false) end
end

-- --------- Whites gate (same source as OptionsMenu/SellItems) ---------
local function getWhitesGate()
    if core and (core.GetSellWhiteAW or core.getSellWhiteAW) then
        local f = core.GetSellWhiteAW or core.getSellWhiteAW
        local ok, res = pcall(function() return f(core) end)
        if ok then return res and true or false end
    end
    if KACHING_SAVED_OPTIONS and KACHING_SAVED_OPTIONS.sellWhiteAW ~= nil then
        return KACHING_SAVED_OPTIONS.sellWhiteAW and true or false
    end
    if KaChing_Config and KaChing_Config.sellWhiteAW ~= nil then
        return KaChing_Config.sellWhiteAW and true or false
    end
    return false
end

local function setWhitesGate(val)
    if core and (core.SetSellWhiteAW or core.setSellWhiteAW) then
        local f = core.SetSellWhiteAW or core.setSellWhiteAW
        local ok = pcall(function() return f(core, val and true or false) end)
        if ok then return end
    end
    KACHING_SAVED_OPTIONS = KACHING_SAVED_OPTIONS or {}
    KACHING_SAVED_OPTIONS.sellWhiteAW = (val and true or false)
    KaChing_Config = KaChing_Config or {}
    KaChing_Config.sellWhiteAW = (val and true or false)
end

-- --------- Helpers used by subcommands ---------
local function linkHex6(link)
    if type(link) ~= "string" then return nil end
    local _, _, hex8 = string.find(link, "|c(%x%x%x%x%x%x%x%x)")
    if not hex8 then return nil end
    return string.sub(hex8, 3, 8)
end

-- ===== Existing utility commands kept =====

-- /slot <slotId> (bag 0)
SLASH_ITEM1 = "/slot"
SlashCmdList["ITEM"] = function(input)
    local bagId = 0
    local slotId = nil
    local args = tokenize(input or "")
    if table.getn(args) >= 1 then slotId = tonumber(args[1]) end
    if not slotId then
        say("KaChing: Invalid slotId")
        return
    end

    local numSlots = GetContainerNumSlots(bagId)
    if not numSlots or slotId > numSlots then
        say("KaChing: Invalid bag " .. bagId .. " or slot " .. slotId .. " (max slots: " .. (numSlots or 0) .. ")")
        return
    end

    local link = GetContainerItemLink(bagId, slotId)
    if link then
        local gi = { GetItemInfo(link) }
        local name = gi[1]
        say("KaChing: Bag " .. bagId .. ", Slot " .. slotId .. ": Name=" .. (name or "nil"))
    else
        say("KaChing: No item in Bag " .. bagId .. ", Slot " .. slotId)
    end
end

-- /kachingmoney
SLASH_KACHINGMONEY1 = "/kachingmoney"
SLASH_KACHINGMONEY2 = "/KachingMoney"
SlashCmdList["KACHINGMONEY"] = function()
    local money = GetMoney()
    say("KaChing Money: " .. (money or "nil") .. " copper (" .. formatMoney(money or 0) .. ")")
end

-- /kachingdebugitem <slotId> (bag 0)
SLASH_KACHINGDEBUGITEM1 = "/kachingdebugitem"
SlashCmdList["KACHINGDEBUGITEM"] = function(input)
    local bagId = 0
    local slotId = nil
    local args = tokenize(input or "")
    if table.getn(args) >= 1 then slotId = tonumber(args[1]) end

    if not slotId then
        say("KaChing: Invalid slotId")
        return
    end

    local numSlots = GetContainerNumSlots(bagId)
    if not numSlots or slotId > numSlots then
        say("KaChing: Invalid bag " .. bagId .. " or slot " .. slotId .. " (max slots: " .. (numSlots or 0) .. ")")
        return
    end

    local link = GetContainerItemLink(bagId, slotId)
    if link then
        local ci = { GetContainerItemInfo(bagId, slotId) }
        local quality = ci[4]
        local gi = { GetItemInfo(link) } -- 1=name, 3=rarity
        local name   = gi[1]
        local rarity = gi[3]
        local sa, sb = string.find(link, "|cff(%x%x%x%x%x%x)")
        local color = "none"
        if sa then color = string.sub(link, sa + 4, sb) end
        say("KaChing Debug: Name=" .. (name or "nil") .. ", Quality=" .. (quality or "nil") .. ", Rarity=" .. (rarity or "nil") .. ", Color=" .. color)
    else
        say("KaChing: No item in Bag " .. bagId .. ", Slot " .. slotId)
    end
end

-- ===== New: /kaching diag =====

local function countTableTrue(t)
    if type(t) ~= "table" then return 0 end
    local n = 0
    local k,v
    for k,v in pairs(t) do
        if v then n = n + 1 end
    end
    return n
end

local function minimapInfo()
    local angle, radius, inside, shown = nil, nil, nil, nil
    if KaChingDB and type(KaChingDB) == "table" then
        local mm = KaChingDB.minimap or KaChingDB.Minimap or KaChingDB.MM
        if type(mm) == "table" then
            angle  = mm.angleDeg or mm.angle or mm.deg
            radius = mm.radius or mm.r or mm.rad
            inside = mm.inside or mm.insideRing or mm.inner
        end
    end
    local btn = getglobal("KaChingMinimapButton")
    if btn and btn.IsShown then shown = btn:IsShown() and true or false end
    return angle, radius, inside, shown
end

local function inventorySummary()
    local present, eligTotal, eligGray, eligWhite = 0, 0, 0, 0
    local items = {}

    local b = 0
    while b <= 4 do
        local slots = GetContainerNumSlots(b)
        if slots and slots > 0 then
            local s = 1
            while s <= slots do
                local tex = GetContainerItemInfo(b, s)
                if tex then
                    present = present + 1
                    if sell and sell.scanSlot then
                        local d = sell.scanSlot(b, s)
                        if d and d.eligible then
                            eligTotal = eligTotal + 1
                            if d.color == "gray" then
                                eligGray = eligGray + 1
                            elseif d.color == "white" then
                                eligWhite = eligWhite + 1
                            end
                            -- collect small preview (up to 5)
                            if table.getn(items) < 5 then
                                local link = GetContainerItemLink(b, s)
                                local label = (d.name or link or "(unknown)")
                                tinsert(items, string.format("  [%d:%d] %s", b, s, label))
                            end
                        end
                    end
                end
                s = s + 1
            end
        end
        b = b + 1
    end

    return present, eligTotal, eligGray, eligWhite, items
end

local function cmd_diag()
    local dbgOn = getDebug()
    local wOn   = getWhitesGate()

    local exclSaved  = countTableTrue(KaChing_ExcludedItemsList)
    local exclRuntime = countTableTrue(KaChing and KaChing.ExclusionList)

    local angle, radius, inside, shown = minimapInfo()
    local merchOpen = (MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown()) and true or false
    local buyback = GetNumBuybackItems and GetNumBuybackItems() or 0

    local qSize = 0
    if sell and sell.buildQueue then
        local q = sell.buildQueue()
        qSize = table.getn(q)
    end

    local present, eligTotal, eligGray, eligWhite, items = inventorySummary()

    say("|cffffff00KaChing diag|r:")
    say("  Debug: " .. (dbgOn and "|cff00ff00ON|r" or "|cffff0000OFF|r")
        .. "   Whites A/W: " .. (wOn and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
    say("  Exclusions: saved=" .. tostring(exclSaved) .. " runtime=" .. tostring(exclRuntime))

    local mmBits = {}
    tinsert(mmBits, "button=" .. ((shown == nil) and "unknown" or (shown and "shown" or "hidden")))
    tinsert(mmBits, "angle=" .. (angle and tostring(math.floor(angle+0.5)).."°" or "n/a"))
    tinsert(mmBits, "radius=" .. (radius and tostring(radius) or "n/a"))
    tinsert(mmBits, "inside=" .. ((inside == nil) and "n/a" or (inside and "true" or "false")))
    say("  Minimap: " .. table.concat(mmBits, "  "))

    say("  Merchant: " .. (merchOpen and "open" or "closed") .. "   Buyback=" .. tostring(buyback))
    say("  Inventory: items=" .. tostring(present) .. "   eligibleNow=" .. tostring(eligTotal)
        .. " (gray=" .. tostring(eligGray) .. ", whiteAW=" .. tostring(eligWhite) .. ")")
    say("  Queue size (buildQueue): " .. tostring(qSize))

    if table.getn(items) > 0 then
        say("  Preview (up to 5):")
        local i
        for i = 1, table.getn(items) do
            say(items[i])
        end
    end

    say("  Tip: /kaching list   /kaching whites on|off|status   /kaching debug status")
end

-- ===== Existing /kaching master command =====

KaChing.Commands = KaChing.Commands or {}

function KaChing.Commands.Handle(msg)
    msg = trimLower(msg or "")

    if msg == "" or msg == "sell" then
        if sell and sell.sellItems then
            sell.sellItems()
        else
            say("KaChing: sell unavailable (SellItems module missing).", 1, 0.3, 0.3)
        end
        return
    end

    -- "/kaching scan <bag> <slot>"
    if string.find(msg, "^scan") then
        if sell and sell.scanSlot then
            local after = string.gsub(msg, "^scan%s*", "")
            local b, s = parseTwoNums(after)
            if b and s then
                local d = sell.scanSlot(b, s)
                if not d then
                    say(string.format("[KaChing] [%d:%d] Empty or unreadable.", b, s), 1, 0.6, 0.2)
                    return
                end
                local link = GetContainerItemLink(b, s)
                local name = d.name or (link or "(unknown)")
                local color = d.color or "?"
                local slot  = d.slotText or "?"
                local elig  = d.eligible and "|cff00ff00YES|r" or "|cffff5555NO|r"
                local excl  = d.excluded and " [EXCLUDED]" or ""
                say(string.format("[KaChing] [%d:%d] %s — color=%s, slot=%s, eligible=%s%s",
                    b, s, name, color, slot, elig, excl))
            else
                say("Usage: /kaching scan <bag> <slot>", 1, 0.6, 0.2)
            end
        else
            say("KaChing: scan unavailable (SellItems.scanSlot missing).")
        end
        return
    end

    -- "/kaching list"
    if msg == "list" then
        if sell and sell.buildQueue then
            local q = sell.buildQueue()
            local n = table.getn(q)
            if n == 0 then
                say("[KaChing] Nothing eligible to sell.", 1, 1, 0)
                return
            end
            say(string.format("[KaChing] %d item(s) eligible:", n), 0.6, 1, 0.6)
            local i
            for i = 1, n do
                local b, s = q[i].bag, q[i].slot
                local link = GetContainerItemLink(b, s)
                say(string.format("  [%d:%d] %s", b, s, link or "(unknown)"))
            end
        else
            say("KaChing: list unavailable (SellItems.buildQueue missing).", 1, 0.3, 0.3)
        end
        return
    end

    -- "/kaching whites ..."
    if string.find(msg, "^whites%s+on$") then
        setWhitesGate(true);  say("KaChing: white Armor/Weapon selling |cff00ff00ON|r"); return
    elseif string.find(msg, "^whites%s+off$") then
        setWhitesGate(false); say("KaChing: white Armor/Weapon selling |cffff0000OFF|r"); return
    elseif string.find(msg, "^whites%s+status$") then
        say("KaChing: whites gate = " .. (getWhitesGate() and "|cff00ff00ON|r" or "|cffff0000OFF|r")); return
    end

    -- "/kaching debug ..."
    if string.find(msg, "^debug%s+on$") then
        setDebug(true);  say("KaChing: debug |cff00ff00ON|r"); return
    elseif string.find(msg, "^debug%s+off$") then
        setDebug(false); say("KaChing: debug |cffff0000OFF|r"); return
    elseif string.find(msg, "^debug%s+toggle$") then
        local now = getDebug(); setDebug(not now)
        say("KaChing: debug " .. ((not now) and "|cff00ff00ON|r" or "|cffff0000OFF|r")); return
    elseif string.find(msg, "^debug%s+status$") then
        say("KaChing: debug = " .. (getDebug() and "|cff00ff00ON|r" or "|cffff0000OFF|r")); return
    end

    -- NEW: "/kaching diag"
    if msg == "diag" then
        cmd_diag()
        return
    end

    -- Help
    say("KaChing: /kaching [sell] | scan <bag> <slot> | list | whites on|off|status | debug on|off|toggle|status | diag")
end

-- Global registration (Lua 5.0 requires globals)
if not SlashCmdList then SlashCmdList = {} end
SLASH_KACHING1 = "/kaching"
SlashCmdList["KACHING"] = function(m) KaChing.Commands.Handle(m) end

-- Optional short alias
SLASH_KC1 = "/kc"
SlashCmdList["KC"] = SlashCmdList["KACHING"]

-- Load ping when debug on
local dbgOn = getDebug()
if dbgOn and DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("Command.lua loaded.", 1.0, 1.0, 0.5)
end
