--[[
SellItems.lua — queued selling + tooltip + 12-per-click batches (TWOW / Lua 5.0)
UPDATED: 22 Aug 2025

What’s new in this build:
- Fix: Button stayed gray after a batch finished until /reload.
  * Post-run button decision is now gated by `sell._summaryShown` so it runs ONCE per click.
  * On MERCHANT_SHOW we set `_summaryShown = true` and force the button red; summary logic won’t override it.
- Keeps: pause when buyback first hits 12, resume next click even if still full,
  exact 12-item quota per click, tooltip rarity, exclusions, locked-slot queue, guarded fonts.
]]

KaChing = KaChing or {}
KaChing.SellItems = KaChing.SellItems or {}
KaChing.SellItems.itemTable = KaChing.SellItems.itemTable or {}
KaChing.ExclusionList = KaChing.ExclusionList or { ["hearthstone"] = true, ["refreshing spring water"] = true }

local core = KaChing.Core
local dbg  = KaChing.DebugTools
local sell = KaChing.SellItems
local L    = KaChing.L or {}

-- ===========================
-- Config (Phase I placeholder; Phase II UI will toggle these)
-- ===========================
sell.cfg = sell.cfg or {
    sellWhites = true,   -- allow selling white Armor/Weapon/Shirt via tooltip detection
}

-- ===========================
-- Static popups
-- ===========================
if not StaticPopupDialogs then StaticPopupDialogs = {} end
StaticPopupDialogs["KACHING_SELL_PAUSED"] = {
    text = (L["KACHING_POPUP_TEXT"] or "Vendor buyback holds 12 items.\n\nClick the KaChing button to continue."),
    button1 = OKAY or "OK",
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}
StaticPopupDialogs["KACHING_NO_ELIGIBLE"] = {
    text = "No eligible items to sell.",
    button1 = OKAY or "OK",
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}

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

-- ===========================
-- Tooltip rarity + classifiers
-- ===========================
local function approx(a,b) return a > b-0.05 and a < b+0.05 end

local function isGrayByTooltip(bag, slot)
    local tip = sell._scanTip
    tip:ClearLines(); tip:SetBagItem(bag, slot)
    local _, r, g, b = tipLeftText(1)
    if not (r and g and b) then return false end
    return approx(r,0.62) and approx(g,0.62) and approx(b,0.62)
end

local function isWhiteByTooltip(bag, slot)
    local tip = sell._scanTip
    tip:ClearLines(); tip:SetBagItem(bag, slot)
    local _, r, g, b = tipLeftText(1)
    if not (r and g and b) then return false end
    return (r > 0.95 and g > 0.95 and b > 0.95)
end

local function tooltipNameLower(bag, slot)
    local tip = sell._scanTip
    tip:ClearLines(); tip:SetBagItem(bag, slot)
    local t = tipLeftText(1)
    if type(t) == "string" then return string.lower(t) end
end

-- Classify by tokens present in the tooltip
local WEAPON_TOKENS = { "Sword","Axe","Mace","Dagger","Staff","Polearm","Wand","Fist Weapon","Gun","Bow","Crossbow","Thrown" }
local ARMOR_TOKENS  = { "Cloth","Leather","Mail","Plate","Shield" }
local SLOT_TOKENS   = { "Head","Neck","Shoulder","Back","Cloak","Chest","Wrist","Hands","Waist","Legs","Feet","Finger","Trinket","Ranged","Main Hand","Off Hand","One-Hand","Two-Hand","Shield","Shirt","Tabard" }

local function textHasAnyToken(text, list)
    local i
    for i = 1, table.getn(list) do
        if string.find(text, list[i], 1, true) then return true end
    end
    return false
end

local function classifyTooltip(bag, slot)
    local tip = sell._scanTip
    tip:ClearLines(); tip:SetBagItem(bag, slot)

    local isArmor, isWeapon, isShirt, equipSlot = false, false, false, nil
    local i = 2
    while i <= 8 do
        local left = getglobal("KaChingScanTipTextLeft"..i); if not left then break end
        local text = left:GetText(); if not text then break end
        if textHasAnyToken(text, WEAPON_TOKENS) then isWeapon = true end
        if textHasAnyToken(text, ARMOR_TOKENS)  then isArmor  = true end
        if textHasAnyToken(text, SLOT_TOKENS) then
            equipSlot = text
            if string.find(text, "Shirt", 1, true) then isShirt = true end
        end
        i = i + 1
    end
    return isArmor, isWeapon, isShirt, equipSlot
end

-- ===========================
-- EXCLUSIONS (case-insensitive, merged)
-- ===========================
sell._exclSet = sell._exclSet or {}

local function rebuildExclusionSet()
    sell._exclSet = {}
    local src1 = getglobal("KaChing_ExcludedItemsList")
    local src2 = KaChing.ExclusionList
    if type(src1) == "table" then
        for k, v in pairs(src1) do if v then sell._exclSet[string.lower(tostring(k))] = true end end
    end
    if type(src2) == "table" then
        for k, v in pairs(src2) do if v then sell._exclSet[string.lower(tostring(k))] = true end end
    end
end
local function isExcludedLower(nameLower) return nameLower and sell._exclSet[nameLower] and true or false end

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
    local n = GetContainerNumSlots(bag); return n and n > 0
end
local function isSlotOccupied(bag, slot)
    local texture = GetContainerItemInfo(bag, slot)
    return texture ~= nil
end

local function logInfo(msg) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg, 1, 1, 0.5) end end
local function logWarn(msg) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg, 1, 0.82, 0) end end
local function logErr(msg)  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg, 1, 0, 0) end end
local function dprint(msg)
    if core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
        if dbg and dbg.print then dbg:print(msg) else logInfo("[DBG] "..tostring(msg)) end
    end
end

-- ===========================
-- Button fonts (optional; guard for 1.12)
-- ===========================
if CreateFont then
    if not getglobal("KaChingBtnFontEnabled") then
        local f = CreateFont("KaChingBtnFontEnabled")
        if f.SetFontObject then f:SetFontObject(GameFontNormal) end
        if f.SetTextColor then f:SetTextColor(1, 0.25, 0.25) end
    end
    if not getglobal("KaChingBtnFontDisabled") then
        local f = CreateFont("KaChingBtnFontDisabled")
        if f.SetFontObject then f:SetFontObject(GameFontDisable) end
        if f.SetTextColor then f:SetTextColor(0.6, 0.6, 0.6) end
    end
end

-- ===========================
-- Button state helper
-- ===========================
local function setButtonEnabled(enabled)
    local btn = getglobal("KaChingBtn"); if not btn then return end
    if enabled then if btn.Enable then btn:Enable() end else if btn.Disable then btn:Disable() end end
end

-- Fast scan: do we still have eligible items?
local function hasEligibleItems()
    rebuildExclusionSet()
    local bag
    for bag = 0, 4 do
        if isBagValid(bag) then
            local slots = GetContainerNumSlots(bag) or 0
            local slot
            for slot = slots, 1, -1 do
                if isSlotOccupied(bag, slot) then
                    local link = GetContainerItemLink(bag, slot)
                    local nameLower = extractItemNameFromLink(link, bag, slot) or "unknown"
                    if isEligibleToSell and isEligibleToSell(bag, slot, link, nameLower) then return true end
                end
            end
        end
    end
    return false
end

-- ===========================
-- Eligibility
-- ===========================
local function isEligibleToSell(bag, slot, link, nameLower)
    if isExcludedLower(nameLower) then return false end
    if isGrayByTooltip(bag, slot) or isGrayItemByLink(link) then return true end
    if sell.cfg.sellWhites and isWhiteByTooltip(bag, slot) then
        local isArmor, isWeapon, isShirt, equipSlot = classifyTooltip(bag, slot)
        if isArmor or isWeapon or isShirt then return true end
        if equipSlot and equipSlot ~= "" and not string.find(equipSlot, "Tabard", 1, true) then return true end
    end
    return false
end

-- ===========================
-- Queue / state machine
-- ===========================
sell._queue   = sell._queue or {}   -- jobs: {bag,slot,name,count,tries,t0,buyback0,state}
sell._current = nil
sell._runner  = sell._runner or nil
sell._poke    = false
sell._running = false

-- Pausing & quotas
sell._pausedForBuybackFull = false
sell._pausedForQuota       = false
sell._allowOverBuyback     = false  -- set true on the NEXT click after a buyback/ quota pause
sell._quotaThisClick       = 0      -- 12 per click
sell._summaryShown         = true   -- gate final button decision (true until a click starts)

local PROCESS_INTERVAL = 0.20
local ITEM_TIMEOUT     = 3.00
local MAX_RETRIES      = 8

local function merchantOpen() return MerchantFrame and MerchantFrame:IsShown() end
local function buybackCount() return (GetNumBuybackItems and (GetNumBuybackItems() or 0)) or 0 end

local function buildQueueEligible()
    sell._queue = {}
    local bag
    for bag = 0, 4 do
        if isBagValid(bag) then
            local slots = GetContainerNumSlots(bag)
            local slot
            for slot = slots, 1, -1 do
                if isSlotOccupied(bag, slot) then
                    local link = GetContainerItemLink(bag, slot)
                    local _, count = GetContainerItemInfo(bag, slot)
                    count = count or 1
                    local nameLower = extractItemNameFromLink(link, bag, slot) or "unknown"
                    if isEligibleToSell(bag, slot, link, nameLower) then
                        tinsert(sell._queue, { bag=bag, slot=slot, name=nameLower, count=count, tries=0, t0=0, buyback0=0, state="pending" })
                    end
                end
            end
        end
    end
end
local function queueEmpty() return sell._queue[1] == nil end
local function queuePop() return table.remove(sell._queue, 1) end

local function saleConfirmed(job)
    local tex = GetContainerItemInfo(job.bag, job.slot)
    if not tex then return true end
    if buybackCount() > (job.buyback0 or 0) then return true end
    return false
end
local function cursorSafe()
    if CursorHasItem() then ClearCursor(); return false end
    return true
end

local function pause(reason)
    if reason == "buyback" then sell._pausedForBuybackFull = true end
    if reason == "quota"   then sell._pausedForQuota       = true end
    if StaticPopup_Show then StaticPopup_Show("KACHING_SELL_PAUSED") end
    sell._running = false
    sell._current = nil
    sell._queue   = {}
    setButtonEnabled(true) -- keep red; user must click KaChing again
    -- Allow next click to proceed over full buyback if we paused for buyback/quota
    -- (set in sell.sellItems, not here, so it resets correctly per click)
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
            sell._running = false
            sell._current = nil
            sell._queue   = {}
            dprint("Runner stopped: merchant closed")
            return
        end
        if not cursorSafe() then dprint("Cleared stray cursor item"); return end

        -- Gate 1: quota per click
        if sell._quotaThisClick <= 0 then
            pause("quota")
            return
        end

        -- Gate 2: buyback full — only pause if we haven't allowed over-buyback yet
        if (not sell._allowOverBuyback) and buybackCount() >= 12 then
            pause("buyback")
            return
        end

        if not sell._current then
            if queueEmpty() then
                sell._running = false
                dprint("Queue empty; runner idle")
                return
            end
            sell._current = queuePop()
            dprint("Processing: "..sell._current.name.." @ bag "..sell._current.bag.." slot "..sell._current.slot)
        end

        local job = sell._current
        local tex, _, locked = GetContainerItemInfo(job.bag, job.slot)
        if not tex then
            dprint("Slot empty; treating as sold: "..job.name)
            sell._current = nil
            return
        end
        if locked then dprint("Locked; waiting: "..job.name); return end

        -- Re-evaluate exclusion/eligibility
        local link = GetContainerItemLink(job.bag, job.slot)
        local nameLower = extractItemNameFromLink(link, job.bag, job.slot) or job.name
        if isExcludedLower(nameLower) then dprint("Excluded now; skipping: "..nameLower); sell._current = nil; return end
        if not isEligibleToSell(job.bag, job.slot, link, nameLower) then dprint("No longer eligible; skipping: "..nameLower); sell._current = nil; return end

        if job.state == "pending" then
            job.buyback0 = buybackCount()
            -- Decrement quota BEFORE issuing the sell to guarantee <=12 UseContainerItem per click
            sell._quotaThisClick = sell._quotaThisClick - 1

            ClearCursor()
            UseContainerItem(job.bag, job.slot)
            ClearCursor()

            job.state = "waiting"
            job.t0 = GetTime()
            dprint("UseContainerItem issued: "..job.name.." (quota left "..sell._quotaThisClick..")")
            return
        end

        if job.state == "waiting" then
            if saleConfirmed(job) then
                sell._current = nil
                return
            end
            if GetTime() - (job.t0 or 0) >= ITEM_TIMEOUT then
                job.tries = (job.tries or 0) + 1
                if job.tries >= MAX_RETRIES then
                    logErr("KaChing: Gave up on "..nameLower.." after "..job.tries.." tries.")
                    sell._current = nil
                else
                    dprint("Retrying "..nameLower.." (try "..job.tries..")")
                    job.state = "pending"
                    -- Quota is not re-incremented; the retry will consume one again when re-issued.
                end
            end
            return
        end
    end)

    if not sell._evt then
        sell._evt = CreateFrame("Frame")
        sell._evt:RegisterEvent("ITEM_LOCK_CHANGED")
        sell._evt:RegisterEvent("BAG_UPDATE")
        sell._evt:RegisterEvent("MERCHANT_CLOSED")
        sell._evt:RegisterEvent("MERCHANT_SHOW")
        sell._evt:SetScript("OnEvent", function()
            if event == "MERCHANT_CLOSED" then
                sell._running = false
                sell._current = nil
                sell._queue   = {}
                sell._pausedForBuybackFull = false
                sell._pausedForQuota       = false
                sell._allowOverBuyback     = false
                sell._quotaThisClick       = 0
                -- don't touch _summaryShown here
            elseif event == "MERCHANT_SHOW" then
                -- Force red when the merchant opens, and make sure the summary
                -- logic won't override it until the user clicks KaChing again.
                setButtonEnabled(true)
                sell._poke = true
                sell._allowOverBuyback = false
                sell._summaryShown = true
            else
                sell._poke = true
            end
        end)
    end
end

local function ensureRunner() if not sell._runner then startRunner() end end

-- ===========================
-- Public: start selling (grays + optional whites)
-- ===========================
function sell.sellItems()
    if not merchantOpen() then logErr("KaChing: Please open a merchant window to sell items."); return end

    -- This is a new click: allow selling over full buyback if we paused last time.
    sell._allowOverBuyback = (sell._pausedForBuybackFull or sell._pausedForQuota) and true or false
    sell._pausedForBuybackFull = false
    sell._pausedForQuota       = false

    -- Reset per-click quota and summary gate
    sell._quotaThisClick = 12
    sell._summaryShown   = false

    rebuildExclusionSet()
    buildQueueEligible()

    if sell._queue[1] == nil then
        if StaticPopup_Show then StaticPopup_Show("KACHING_NO_ELIGIBLE") end
        setButtonEnabled(false)
        sell._summaryShown = true  -- nothing to do; don't let summary flip state afterwards
        return
    end

    -- Summary frame: decide the FINAL button state AFTER the click's run ends (run once)
    if not sell._summaryFrame then
        sell._summaryFrame = CreateFrame("Frame")
        sell._summaryFrame._t = 0
        sell._summaryFrame:SetScript("OnUpdate", function()
            local dt = arg1 or 0
            sell._summaryFrame._t = sell._summaryFrame._t + dt
            if sell._summaryFrame._t < 0.25 then return end
            sell._summaryFrame._t = 0

            -- Only run once per click; guarded by sell._summaryShown
            if sell._summaryShown then return end

            if not sell._running and not sell._current then
                -- Decide final state once, then mark as shown
                if sell._pausedForBuybackFull or sell._pausedForQuota then
                    setButtonEnabled(true)      -- user needs to click again
                else
                    if hasEligibleItems() then setButtonEnabled(true) else setButtonEnabled(false) end
                end
                sell._summaryShown = true
            end
        end)
    end

    ensureRunner()
    sell._running = true
    sell._poke = true
    setButtonEnabled(true)   -- red during run
end

-- ===========================
-- Item table maintenance (debug/aux)
-- ===========================
local BUTTON_CREATED = false

function sell.updateItemList(bagId)
    local newTable = {}
    local _, item
    for _, item in pairs(sell.itemTable) do
        if item.bagId ~= bagId then tinsert(newTable, item) end
    end
    local slots = GetContainerNumSlots(bagId) or 0
    local slot
    for slot = slots, 1, -1 do
        if isSlotOccupied(bagId, slot) then
            local link = GetContainerItemLink(bagId, slot)
            local info = { GetContainerItemInfo(bagId, slot) }
            local locked = info[3]; local count = info[2] or 1
            local name   = extractItemNameFromLink(link, bagId, slot) or "unknown"
            if not locked and not isExcludedLower(name) and (isGrayByTooltip(bagId, slot) or isGrayItemByLink(link)) then
                tinsert(newTable, { bagId=bagId, slotId=slot, name=name, isGray=true, itemCount=count })
            end
        end
    end
    sell.itemTable = newTable
end

function sell.initializeItemTable()
    sell.itemTable = {}
    local bag
    for bag = 0, 4 do if isBagValid(bag) then sell.updateItemList(bag) end end
end

function sell.createKaChingButton()
    if BUTTON_CREATED then return end
    if not MerchantFrame then return end

    local button = CreateFrame("Button", "KaChingBtn", MerchantFrame, "UIPanelButtonTemplate")
    button:SetText("KaChing"); button:SetWidth(90); button:SetHeight(21)
    button:SetPoint("TOPRIGHT", -50, -45)

    -- Apply clean fonts if the API exists; otherwise default Blizzard fonts
    if button.SetNormalFontObject and getglobal("KaChingBtnFontEnabled") then button:SetNormalFontObject(KaChingBtnFontEnabled) end
    if button.SetDisabledFontObject and getglobal("KaChingBtnFontDisabled") then button:SetDisabledFontObject(KaChingBtnFontDisabled) end

    button:SetScript("OnClick", function()
        if sell and sell.sellItems then sell.sellItems()
        elseif DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(L["SELL_FUNCTION_NOT_READY"] or "KaChing: Sell function is not ready.", 1, 0, 0) end
    end)

    button:EnableMouse(true)
    button:SetScript("OnEnter", function()
        if GameTooltip and this then
            GameTooltip:Hide(); GameTooltip:SetOwner(this, "ANCHOR_RIGHT"); GameTooltip:ClearLines()
            GameTooltip:AddLine(L["KACHING_BTN_TOOLTIP"] or "Click to start bulk sales.", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    setButtonEnabled(true)
    BUTTON_CREATED = true
end

if DEFAULT_CHAT_FRAME and core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
    DEFAULT_CHAT_FRAME:AddMessage("SellItems.lua (batch=12, pause+resume, summary-gated button) loaded", 1, 1, 0.5)
end
