-- OptionsMenu.lua — KaChing Options + Exclusion List (Classic/TWOW Lua 5.0)
-- UPDATED: 11 August, 2025 (aligned layout + tooltip input, no Add button, Safe.lua integration)

KaChing = KaChing or {}
KaChing.OptionsMenu = KaChing.OptionsMenu or {}

local options = KaChing.OptionsMenu
local core    = KaChing.Core
local dbg     = KaChing.DebugTools
local L       = KaChing.L or {}
local safe    = KaChing.Safe or {}   -- Safe.lua wrappers

-- Per-character SVs (declared in TOC; MUST be space-separated)
KACHING_SAVED_OPTIONS     = KACHING_SAVED_OPTIONS or {}
KaChing_ExcludedItemsList = KaChing_ExcludedItemsList or {}   -- map[nameLower] = true
KaChing.ExclusionList     = KaChing.ExclusionList or {}       -- runtime map (SellItems.lua uses)

-- ---------- debug helper ----------
local function dprint(msg)
    if core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
        if dbg and dbg.print then dbg:print(msg) end
    end
end

-- ---------- SV guards ----------
local function ensureSavedVars()
    if type(KACHING_SAVED_OPTIONS) ~= "table" then KACHING_SAVED_OPTIONS = {} end
    if type(KaChing_ExcludedItemsList) ~= "table" then KaChing_ExcludedItemsList = {} end
    if type(KaChing.ExclusionList) ~= "table" then KaChing.ExclusionList = {} end
end
ensureSavedVars()

-- ---------- helpers ----------
local function normalizeName(name)
    if type(name) ~= "string" then return nil end
    name = string.gsub(name, "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    if name == "" then return nil end
    return string.lower(name)
end

local function linkToNameLower(link)
    if type(link) ~= "string" then return nil end
    local _, _, n = string.find(link, "%[(.-)%]")
    return normalizeName(n)
end

-- Keep runtime and SV maps in sync
local function addToExclusion(nameLower)
    if not nameLower then return end
    ensureSavedVars()
    KaChing_ExcludedItemsList[nameLower] = true
    KaChing.ExclusionList[nameLower]     = true
end
local function removeFromExclusion(nameLower)
    if not nameLower then return end
    ensureSavedVars()
    KaChing_ExcludedItemsList[nameLower] = nil
    KaChing.ExclusionList[nameLower]     = nil
end

-- Seed runtime map from saved (carry over any existing defaults too)
local function seedRuntimeMapFromSaved()
    ensureSavedVars()
    local k,v
    for k,v in pairs(KaChing_ExcludedItemsList) do
        if v then KaChing.ExclusionList[k] = true end
    end
end

-- Build a sorted array of names for the UI list
local function buildSortedNames()
    ensureSavedVars()
    local arr = {}
    local k, v
    for k, v in pairs(KaChing_ExcludedItemsList) do
        if v then table.insert(arr, k) end
    end
    table.sort(arr)
    return arr
end

-- ---------- options defaults ----------
local function ensureOptionDefaults()
    ensureSavedVars()
    if KACHING_SAVED_OPTIONS.sellWhiteAW == nil then
        KACHING_SAVED_OPTIONS.sellWhiteAW = false
    end
end

-- ---------- layout constants (grid) ----------
local PAD        = 24       -- left/right inner padding
local GAP_Y      = 8        -- vertical gap between stacked controls
local GAP_X      = 8        -- horizontal gap between neighbors
local ROWS       = 8
local LIST_WIDTH = 260      -- width for list
local EDIT_WIDTH = LIST_WIDTH + 88  -- reclaim space from removed Add button

options._rows = options._rows or {}
options._sorted = options._sorted or {}
options._selectedIndex = nil

-- ---------- list refresh ----------
local function refreshList()
    options._sorted = buildSortedNames()
    local offset = FauxScrollFrame_GetOffset(KaChing_Excl_Scroll) or 0
    local total  = table.getn(options._sorted)

    for i = 1, ROWS do
        local idx = i + offset
        local row = options._rows[i]
        if idx <= total then
            local nameLower = options._sorted[idx]
            row.text:SetText(nameLower)
            row:Show()
            if options._selectedIndex == idx then row:LockHighlight() else row:UnlockHighlight() end
        else
            row.text:SetText("")
            row:Hide()
        end
    end

    FauxScrollFrame_Update(KaChing_Excl_Scroll, total, ROWS, 18)
end

local function onRowClick()
    local offset = FauxScrollFrame_GetOffset(KaChing_Excl_Scroll) or 0
    local idx = this._rowIndex + offset
    options._selectedIndex = idx
    refreshList()
end

-- ---------- frame creation ----------
local function createFrameOnce()
    if options.frame then return options.frame end

    ensureOptionDefaults()
    seedRuntimeMapFromSaved()

    local f = CreateFrame("Frame", "KaChingOptionsFrame", UIParent)
    f:SetWidth(420); f:SetHeight(300) -- tall enough for right-side Remove button
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

    -- Close
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

    -- === Checkbox: Sell white armor & weapons ===
    local cb = CreateFrame("CheckButton", "KaChing_Opt_SellWhiteAW", f, "UICheckButtonTemplate")
    cb:ClearAllPoints()
    cb:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -48)

    local label = getglobal(cb:GetName().."Text")
    label:SetText(L["OPT_SELL_WHITE_AW"] or "Sell white armor & weapons")
    label:ClearAllPoints()
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)

    local w = label:GetStringWidth() or 140
    cb:SetHitRectInsets(0, - (w + 8), 0, 0)

    cb:SetScript("OnEnter", function()
        if not GameTooltip or not this then return end
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:SetText(L["OPT_SELL_WHITE_AW"] or "Sell white armor & weapons", 1, 1, 1)
        GameTooltip:AddLine(
            L["TIP_SELL_WHITE_AW"] or "If checked, all white armor and weapon items will be sold.",
            0.9, 0.9, 0.9, true
        )
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    cb:SetChecked(KACHING_SAVED_OPTIONS.sellWhiteAW and 1 or 0)
    cb:SetScript("OnClick", function()
        KACHING_SAVED_OPTIONS.sellWhiteAW = (this:GetChecked() and true or false)
        dprint("sellWhiteAW set to: "..tostring(KACHING_SAVED_OPTIONS.sellWhiteAW))
    end)

    -- === Exclusion List header ===
    local exclTitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    exclTitle:SetText(L["EXCL_TITLE"] or "Exclusion List")
    exclTitle:ClearAllPoints()
    exclTitle:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -88)

    -- === Input box (accepts drag or shift-click) — tooltip-only (no placeholder text)
    local edit = CreateFrame("EditBox", "KaChing_Excl_Edit", f)
    edit:ClearAllPoints()
    edit:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -110)
    edit:SetWidth(EDIT_WIDTH); edit:SetHeight(22)
    edit:SetAutoFocus(false)
    edit:SetFontObject(GameFontHighlightSmall)
    edit:SetTextInsets(6, 6, 2, 2)
    edit:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    edit:SetBackdropColor(0, 0, 0, 0.5)
    edit:EnableMouse(true)

    -- Tooltip on hover
    edit:SetScript("OnEnter", function()
        if not GameTooltip or not this then return end
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:SetText(
            L["EXCL_EDIT_TIP"] or
            "Drag and drop item here to add it to the list of excluded items (for example, your mining pick and/or fishing pole).",
            1, 1, 1, true
        )
        GameTooltip:Show()
    end)
    edit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    -- Accept item drop
    edit:SetScript("OnReceiveDrag", function()
        local ctype, p1, p2 = safe.GetCursorInfo()
        local nameLower = nil
        if ctype == "item" then
            nameLower = linkToNameLower(p2) or normalizeName(p1)
        end
        if nameLower then
            addToExclusion(nameLower)
            this:SetText("")
            options._selectedIndex = nil
            refreshList()
            if ClearCursor then ClearCursor() end
            dprint("Excluded: "..nameLower)
        else
            if ClearCursor then ClearCursor() end
        end
    end)

    -- Click-in with item on cursor also adds
    edit:SetScript("OnMouseUp", function()
        if CursorHasItem and CursorHasItem() then
            local ctype, p1, p2 = safe.GetCursorInfo()
            local nameLower = nil
            if ctype == "item" then
                nameLower = linkToNameLower(p2) or normalizeName(p1)
            end
            if nameLower then
                addToExclusion(nameLower)
                this:SetText("")
                options._selectedIndex = nil
                refreshList()
                if ClearCursor then ClearCursor() end
                dprint("Excluded: "..nameLower)
                return
            end
        end
    end)

    -- Press Enter to manually add (typed name or shift-clicked link)
    edit:SetScript("OnEnterPressed", function()
        local txt = this:GetText()
        local nameLower = linkToNameLower(txt) or normalizeName(txt)
        if nameLower then
            addToExclusion(nameLower)
            this:SetText("")
            options._selectedIndex = nil
            refreshList()
            dprint("Excluded: "..nameLower)
        end
        this:ClearFocus()
    end)

    -- === Scroll list frame (aligned with edit; LIST_WIDTH)
    local listBG = CreateFrame("Frame", nil, f)
    listBG:ClearAllPoints()
    listBG:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 0, -GAP_Y)
    listBG:SetWidth(LIST_WIDTH); listBG:SetHeight( ROWS * 18 + 8 )
    listBG:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    listBG:SetBackdropColor(0, 0, 0, 0.3)

    local scroll = CreateFrame("ScrollFrame", "KaChing_Excl_Scroll", listBG, "FauxScrollFrameTemplate")
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", listBG, "TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", listBG, "BOTTOMRIGHT", -24, 4)
    scroll:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(18, refreshList)
    end)

    -- Rows (buttons for selection)
    for i = 1, ROWS do
        local row = options._rows[i] or CreateFrame("Button", "KaChing_Excl_Row"..i, listBG)
        row:SetWidth(LIST_WIDTH - 30); row:SetHeight(16)
        row:ClearAllPoints()
        if i == 1 then
            row:SetPoint("TOPLEFT", listBG, "TOPLEFT", 8, -6)
        else
            row:SetPoint("TOPLEFT", options._rows[i-1], "BOTTOMLEFT", 0, -2)
        end
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        if not row.text then
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", row, "LEFT", 2, 0)
            row.text = fs
        end
        row._rowIndex = i
        row:SetScript("OnClick", onRowClick)
        options._rows[i] = row
    end

    -- === Remove button (aligned to list TOPRIGHT)
    local remBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    remBtn:SetWidth(80); remBtn:SetHeight(22)
    remBtn:ClearAllPoints()
    remBtn:SetPoint("TOPLEFT", listBG, "TOPRIGHT", GAP_X + 2, 0)
    remBtn:SetText(L["EXCL_REMOVE"] or "Remove")
    remBtn:SetScript("OnClick", function()
        local idx = options._selectedIndex
        if not idx then return end
        local nameLower = options._sorted[idx]
        if nameLower then
            removeFromExclusion(nameLower)
            options._selectedIndex = nil
            refreshList()
            dprint("Removed: "..nameLower)
        end
    end)

    -- Auto-refresh list whenever the options window is shown
    f:SetScript("OnShow", function()
        options._selectedIndex = nil
        refreshList()
    end)

    options.frame = f
    refreshList()
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

-- Defense-in-depth helpers for external callers
function options:IsReady()
    return options.frame ~= nil
end

function options:EnsureReady()
    createFrameOnce()
    return options.frame ~= nil
end

if core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
    DEFAULT_CHAT_FRAME:AddMessage("OptionsMenu.lua is loaded", 1, 1, 0.5)
end
