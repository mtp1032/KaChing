-- OptionsMenu.lua — KaChing Options (Classic/TWOW Lua 5.0)
-- UPDATED: 10 August, 2025

KaChing = KaChing or {}
KaChing.OptionsMenu = KaChing.OptionsMenu or {}

local options = KaChing.OptionsMenu
local core    = KaChing.Core
local dbg     = KaChing.DebugTools
local L       = KaChing.L or {}

-- Per-character saved vars (declared in TOC; space-separated)
KACHING_SAVED_OPTIONS = KACHING_SAVED_OPTIONS or {}

local function dprint(msg)
    if core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
        if dbg and dbg.print then dbg:print(msg) end
    end
end

local function ensureDefaults()
    if type(KACHING_SAVED_OPTIONS) ~= "table" then KACHING_SAVED_OPTIONS = {} end
    if KACHING_SAVED_OPTIONS.sellWhiteAW == nil then
        KACHING_SAVED_OPTIONS.sellWhiteAW = false
    end
end

local function createFrameOnce()
    if options.frame then return options.frame end
    ensureDefaults()

    local f = CreateFrame("Frame", "KaChingOptionsFrame", UIParent)
    f:SetWidth(340); f:SetHeight(160)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop",  function() this:StopMovingOrSizing() end)
    f:Hide()

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetText(L["OPTIONS_TITLE"] or "KaChing Options")
    title:SetPoint("TOP", f, "TOP", 0, -16)

    -- Close button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

    -- === Checkbox: Sell white armor & weapons ===
    local cb = CreateFrame("CheckButton", "KaChing_Opt_SellWhiteAW", f, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -48)

    local label = getglobal(cb:GetName().."Text")
    label:SetText(L["OPT_SELL_WHITE_AW"] or "Sell white armor & weapons")
    label:ClearAllPoints()
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)

    -- Expand hit area to include the label text
    local w = label:GetStringWidth() or 140
    cb:SetHitRectInsets(0, - (w + 8), 0, 0)

    -- Tooltip on hover (Classic uses 'this')
    local function ShowTip()
        if not GameTooltip or not this then return end
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:SetText(L["OPT_SELL_WHITE_AW"] or "Sell white armor & weapons", 1, 1, 1)
        GameTooltip:AddLine(
            L["TIP_SELL_WHITE_AW"] or "If checked, all white armor and weapon items will be sold.",
            0.9, 0.9, 0.9, true
        )
        GameTooltip:Show()
    end
    local function HideTip()
        if GameTooltip then GameTooltip:Hide() end
    end
    cb:SetScript("OnEnter", ShowTip)
    cb:SetScript("OnLeave", HideTip)

    -- State + click handler (stubbed: just saves)
    cb:SetChecked(KACHING_SAVED_OPTIONS.sellWhiteAW and 1 or 0)
    cb:SetScript("OnClick", function()
        KACHING_SAVED_OPTIONS.sellWhiteAW = (this:GetChecked() and true or false)
        dprint("sellWhiteAW set to: "..tostring(KACHING_SAVED_OPTIONS.sellWhiteAW))
    end)

    options.frame = f
    return f
end

-- Public API used by minimap icon (left-click)
function options:menuCreate()
    createFrameOnce()
    dprint("Options frame created")
end

function options:Toggle()
    createFrameOnce()
    if options.frame:IsShown() then options.frame:Hide() else options.frame:Show() end
end

if core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
    DEFAULT_CHAT_FRAME:AddMessage("OptionsMenu.lua is loaded", 1, 1, 0.5)
end
