-- SellItems.lua (Turtle/1.12, Lua 5.0)
-- ORIGINAL DATE: 4 August, 2025
-- UPDATED: 17 August, 2025 (exposes API for Command.lua; no slash here)

--[[ Lua 5.0 notes:
- No string.match; use string.find / string.gfind
- No goto or select()
- _G is not available; use getglobal()
- No '#' length operator; use table.getn(t)
- Use tinsert(t, v) instead of table.insert(t, v)
- Avoid 'self' in handlers; Classic uses 'this'
]]

KaChing = KaChing or {}
KaChing.SellItems = KaChing.SellItems or {}

local core  = KaChing.Core or {}
local dbg   = KaChing.DebugTools or {}
local L     = KaChing.L or {}
local safe  = KaChing.Safe or {}
local sell  = KaChing.SellItems

-- Saved vars (declared in TOC)
KACHING_SAVED_OPTIONS     = KACHING_SAVED_OPTIONS or {}
KaChing_ExcludedItemsList = KaChing_ExcludedItemsList or {}
KaChing.ExclusionList     = KaChing.ExclusionList or { ["hearthstone"]=true, ["refreshing spring water"]=true }

-- ---------- config for white A/W tooltip slot strings ----------
sell.config = sell.config or {
    includeFinger   = false,
    includeTrinket  = false,
    includeNeck     = false,
    includeHeldOff  = true,   -- "Held In Off-hand"
}

local SLOT_OK = {
    ["Head"] = true, ["Shoulder"] = true, ["Back"] = true,
    ["Chest"] = true, ["Wrist"] = true, ["Hands"] = true,
    ["Waist"] = true, ["Legs"] = true, ["Feet"] = true,
    ["Main Hand"] = true, ["Off Hand"] = true, ["One-Hand"] = true,
    ["Two-Hand"] = true, ["Ranged"] = true, ["Thrown"] = true,
    ["Shield"] = true, ["Wand"] = true, ["Polearm"] = true,
    ["Dagger"] = true, ["Axe"] = true, ["Sword"] = true,
    ["Mace"] = true, ["Staff"] = true, ["Bow"] = true,
    ["Gun"] = true, ["Crossbow"] = true,
    ["Finger"] = "cfg:finger",
    ["Trinket"] = "cfg:trinket",
    ["Neck"] = "cfg:neck",
    ["Held In Off-hand"] = "cfg:heldoff",
}

local function slotAllowed(slotText)
    if not slotText then return false end
    local v = SLOT_OK[slotText]
    if v == true then return true end
    if v == "cfg:finger"  then return sell.config.includeFinger end
    if v == "cfg:trinket" then return sell.config.includeTrinket end
    if v == "cfg:neck"    then return sell.config.includeNeck end
    if v == "cfg:heldoff" then return sell.config.includeHeldOff end
    return false
end

-- ---------- money formatter ----------
local function formatMoney(copper)
    if type(copper) ~= "number" or copper <= 0 then return "0g 0s 0c" end
    local g = math.floor(copper / 10000)
    local rem = copper - g * 10000
    local s = math.floor(rem / 100)
    local c = rem - s * 100
    local out = ""
    if g > 0 then out = out .. g .. "g " end
    if s > 0 or g > 0 then out = out .. s .. "s " end
    out = out .. c .. "c"
    return out
end

-- ---------- hidden tooltip + scanning ----------
local function ensureScanTip()
    if not sell._scanTip then
        local tip
        local ok, obj = pcall(CreateFrame, "GameTooltip", "KaChingPawnScanTip", UIParent, "GameTooltipTemplate")
        if ok and obj then tip = obj end
        if not tip then tip = GameTooltip end
        if tip and tip.SetOwner then tip:SetOwner(UIParent or WorldFrame, "ANCHOR_NONE") end
        sell._scanTip = tip
    end
    return sell._scanTip
end

local function TooltipSetBagItemSafe(tip, bag, slot)
    if not (tip and tip.SetBagItem and tip.ClearLines and tip.SetOwner) then return false end
    tip:SetOwner(UIParent or WorldFrame, "ANCHOR_NONE")
    tip:ClearLines()
    local ok = pcall(tip.SetBagItem, tip, bag, slot)
    if not ok then return false end
    if tip.Show then tip:Show() end
    return true
end

local function approx(a, b) return a > b - 0.05 and a < b + 0.05 end

-- Returns: name, isWhite, slotText
local function tooltipNameColorAndSlot(bag, slot)
    local tip = ensureScanTip()
    if not tip then return nil, false, nil end
    if not TooltipSetBagItemSafe(tip, bag, slot) then
        if tip.Hide then tip:Hide() end
        return nil, false, nil
    end

    local tipName = tip.GetName and tip:GetName() or "GameTooltip"
    local left1   = getglobal(tipName.."TextLeft1")
    local name    = left1 and left1:GetText() or nil

    local r, g, b = 1, 1, 1
    if left1 and left1.GetTextColor then r, g, b = left1:GetTextColor() end
    local isWhite = (r and g and b) and (r > 0.95 and g > 0.95 and b > 0.95) or false

    local slotText
    local i
    for i = 1, 12 do
        local fsR = getglobal(tipName.."TextRight"..i)
        if fsR then
            local t = fsR:GetText()
            if t and SLOT_OK[t] ~= nil then slotText = t; break end
        end
        local fsL = getglobal(tipName.."TextLeft"..i)
        if fsL and i ~= 1 then
            local t2 = fsL:GetText()
            if t2 and SLOT_OK[t2] ~= nil then slotText = t2; break end
        end
    end

    if tip.Hide then tip:Hide() end
    return name, isWhite, slotText
end

local function tooltipIsGray(bag, slot)
    local tip = ensureScanTip()
    if not tip then return false end
    if not TooltipSetBagItemSafe(tip, bag, slot) then
        if tip.Hide then tip:Hide() end
        return false
    end
    local tipName = tip.GetName and tip:GetName() or "GameTooltip"
    local left1 = getglobal(tipName.."TextLeft1")
    if not (left1 and left1.GetTextColor) then
        if tip.Hide then tip:Hide() end
        return false
    end
    local r, g, b = left1:GetTextColor()
    if tip.Hide then tip:Hide() end
    return (r and g and b) and approx(r, 0.62) and approx(g, 0.62) and approx(b, 0.62)
end

-- ---------- link/equipLoc fallback ----------
local function linkHex6AndName(link)
    if type(link) ~= "string" then return nil, nil end
    local _, _, hex8, name = string.find(link, "|c(%x%x%x%x%x%x%x%x).-|h%[(.-)%]|h|r")
    if not hex8 then return nil, name end
    return string.sub(hex8, 3, 8), name
end

local function isGrayByLink(link)
    if type(link) ~= "string" then return false end
    local _, _, hex8 = string.find(link, "|c(%x%x%x%x%x%x%x%x)")
    if not hex8 then return false end
    return (string.sub(hex8, 3, 8) == "9d9d9d")
end

local ALLOWED_INV = {
    ["INVTYPE_HEAD"] = true,   ["INVTYPE_SHOULDER"] = true, ["INVTYPE_CHEST"] = true,
    ["INVTYPE_ROBE"] = true,   ["INVTYPE_WAIST"] = true,    ["INVTYPE_LEGS"] = true,
    ["INVTYPE_FEET"] = true,   ["INVTYPE_WRIST"] = true,    ["INVTYPE_HAND"] = true,
    ["INVTYPE_CLOAK"] = true,  ["INVTYPE_HOLDABLE"] = "cfg:heldoff",
    ["INVTYPE_FINGER"] = "cfg:finger", ["INVTYPE_TRINKET"] = "cfg:trinket",
    ["INVTYPE_NECK"] = "cfg:neck",
    ["INVTYPE_WEAPON"] = true, ["INVTYPE_WEAPONMAINHAND"] = true, ["INVTYPE_WEAPONOFFHAND"] = true,
    ["INVTYPE_2HWEAPON"] = true, ["INVTYPE_SHIELD"] = true, ["INVTYPE_RANGED"] = true,
    ["INVTYPE_RANGEDRIGHT"] = true, ["INVTYPE_THROWN"] = true, ["INVTYPE_WAND"] = true,
}

local function equipAllowed(equipLoc)
    if not equipLoc then return false end
    local v = ALLOWED_INV[equipLoc]
    if v == true then return true end
    if v == "cfg:finger"  then return sell.config.includeFinger end
    if v == "cfg:trinket" then return sell.config.includeTrinket end
    if v == "cfg:neck"    then return sell.config.includeNeck end
    if v == "cfg:heldoff" then return sell.config.includeHeldOff end
    return false
end

local function getEquipLoc(item)
    local ok, _, _, _, _, _, _, _, equipLoc = pcall(GetItemInfo, item)
    if not ok then return nil end
    return equipLoc
end

-- ---------- exclusions (by name) ----------
local function isExcluded(name)
    if not name then return false end
    if KaChing_ExcludedItemsList then
        if KaChing_ExcludedItemsList[name] then return true end
        local lname = string.lower(name)
        if KaChing_ExcludedItemsList[lname] then return true end
    end
    local lname2 = string.lower(name)
    if KaChing.ExclusionList and KaChing.ExclusionList[lname2] then return true end
    return false
end

-- ---------- option gate ----------
local function whitesEnabled()
    if type(KACHING_SAVED_OPTIONS) ~= "table" then return false end
    return KACHING_SAVED_OPTIONS.sellWhiteAW and true or false
end

-- ---------- unified “should sell?” ----------
function sell.wantSell(bag, slot)
    local texture = GetContainerItemInfo(bag, slot)
    if not texture then return false end

    -- Fast gray by link
    local link = GetContainerItemLink(bag, slot)
    if isGrayByLink(link) then return true, "(gray)" end

    -- Tooltip route
    local name, isWhite, slotText = tooltipNameColorAndSlot(bag, slot)
    if name and isExcluded(name) then return false end

    -- Fallback gray via tooltip color
    if tooltipIsGray(bag, slot) then return true, name or "(gray)" end

    -- Whites (armor/weapon): only if option enabled
    if whitesEnabled() then
        if isWhite and slotAllowed(slotText) then return true, name end
        if link then
            local hex6, lname = linkHex6AndName(link)
            local n = name or lname
            if n and isExcluded(n) then return false end
            if hex6 == "ffffff" then
                local equipLoc = getEquipLoc(link)
                if equipAllowed(equipLoc) then return true, n end
            end
        end
    end

    return false
end

-- ---------- queue builder (used by Command.lua) ----------
function sell.buildQueue()
    local q = {}
    local bag
    for bag = 0, 4 do
        local n = GetContainerNumSlots(bag)
        if n and n > 0 then
            local slot
            for slot = 1, n do
                local ok = sell.wantSell(bag, slot)
                if ok then tinsert(q, { bag = bag, slot = slot }) end
            end
        end
    end
    table.sort(q, function(a, b)
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    return q
end

-- ---------- selling loop (Safe.SellSlot) ----------
function sell.sellItems()
    if not MerchantFrame or not MerchantFrame:IsShown() then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("[KaChing] Open a merchant first.", 1, 0.2, 0.2)
        end
        return
    end

    local queue = sell.buildQueue()
    local qn = table.getn(queue)
    if qn == 0 then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("[KaChing] Nothing eligible to sell.", 1, 1, 0)
        end
        return
    end

    local moneyStart = GetMoney()
    local i = 1
    local function step()
        local entry = queue[i]
        if not entry then
            if DEFAULT_CHAT_FRAME then
                local gain = GetMoney() - (moneyStart or 0)
                DEFAULT_CHAT_FRAME:AddMessage("[KaChing] Done. Gold gained: "..formatMoney(gain), 0.2, 1, 0.2)
            end
            return
        end

        safe.SellSlot(entry.bag, entry.slot, function()
            i = i + 1
            local f = CreateFrame("Frame")
            f:SetScript("OnUpdate", function()
                f:SetScript("OnUpdate", nil); f:Hide(); step()
            end)
            f:Show()
        end, { timeout_sec = 0.35, max_retries = 1 })
    end

    step()
end

-- ---------- Merchant "KaChing" button ----------
local BUTTON_CREATED = false
function sell.createKaChingButton()
    if BUTTON_CREATED then return end
    if not MerchantFrame then return end

    local button = getglobal("KaChingBtn")
    if not button then
        button = CreateFrame("Button", "KaChingBtn", MerchantFrame, "UIPanelButtonTemplate")
    end

    button:SetText("KaChing")
    button:SetWidth(90); button:SetHeight(21)
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -50, -45)

    if button.SetFrameStrata then button:SetFrameStrata("HIGH") end
    if button.SetFrameLevel and MerchantFrame.GetFrameLevel then
        button:SetFrameLevel(MerchantFrame:GetFrameLevel() + 3)
    end

    button:SetScript("OnClick", function()
        if sell and sell.sellItems then
            sell.sellItems()
        elseif DEFAULT_CHAT_FRAME then
            local LL = KaChing.L or {}
            DEFAULT_CHAT_FRAME:AddMessage(LL["KACHING_FUNCTION_NOT_READY"] or "KaChing: Sell function is not ready.", 1, 0, 0)
        end
    end)

    button:EnableMouse(true)
    button:SetScript("OnEnter", function()
        if GameTooltip and this then
            GameTooltip:Hide()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            local LL = KaChing.L or {}
            GameTooltip:AddLine(LL["KACHING_BTN_TOOLTIP"] or "Click to start bulk sales.", 1, 1, 1, true)
            local onoff = (KACHING_SAVED_OPTIONS.sellWhiteAW and true or false) and "|cff00ff00ON|r" or "|cffff5555OFF|r"
            GameTooltip:AddLine("White armor/weapons: "..onoff, 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    BUTTON_CREATED = true
end

-- ---------- load ping ----------
if core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
    DEFAULT_CHAT_FRAME:AddMessage("SellItems.lua loaded.", 1, 1, 0.5)
end
