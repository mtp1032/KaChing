-- OptionsMenu.lua — KaChing Options + Exclusion List (Classic/TWOW Lua 5.0)
-- UPDATED: 11 August, 2025 (Lua 5.0 safe; uses Safe.lua cursor helpers; aligned layout)

--[[ PROGRAMMING NOTES:
Turtle WoW AddOns are implemented in Lua 5.0:
- No string.match, use string.find or string.gfind
- No goto or select()
- _G is not available, use getglobal() or setfenv(0)
- # is not available:
  * Use table.getn(t) instead of #t
- Use modulo instead of x % y in some edge macros
- Use tinsert(t, v) instead of table.insert(t, v)
- Frame script handlers use 'this' (not 'self')
]]

KaChing = KaChing or {}
KaChing.OptionsMenu = {} or {}

local options = KaChing.OptionsMenu 
local L = KaChing.Locales
local core = KaChing.Core
local dbg = KaChing.Debug
local safe = KaChing.Safe-- Safe.lua helpers (cursor, item name, etc.)

-- Per-character SVs (declared in TOC; MUST be space-separated)
KACHING_SAVED_OPTIONS     = KACHING_SAVED_OPTIONS 
KaChing_ExcludedItemsList = KaChing_ExcludedItemsList    -- map[nameLower] = true
KaChing.ExclusionList     = KaChing.ExclusionList        -- runtime map (SellItems.lua uses)

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
        if v then tinsert(arr, k) end
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

    local i
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
        local msg = L["MSG_SELL_WHITE_AW"] or "Sell white armor & weapons set to: "
        if dbg and dbg.print then dbg:print(msg) end
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

    -- Accept item drop (1.12: use Safe.lua helpers; no GetCursorInfo)
    -- Use the new bag-only drop handler
    options.AttachExclusionDrop(edit)


    -- Press Enter to manually add (typed name or shift-clicked link)
    edit:SetScript("OnEnterPressed", function()
        local txt = this:GetText()
        local nameLower = linkToNameLower(txt) or normalizeName(txt)
        if nameLower then
            addToExclusion(nameLower)
            this:SetText("")
            options._selectedIndex = nil
            refreshList()
            if dbg and dbg.print then dbg:print("Excluded: "..nameLower) end
            local msg = ("Excluded: "..nameLower)
            if dbg and dbg.print then dbg:print(msg) end
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
    local i
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
            if dbg and dbg.print then dbg:print("Removed: "..nameLower ) end
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
    if dbg and dbg.print then dbg:print("Options frame created") end
    
end

function options:Toggle()
    createFrameOnce()
    if options.frame:IsShown() then options.frame:Hide() else options.frame:Show() end
end

-- Optional: let other modules refresh the list after they mutate SVs
function options:refreshExclusionList()
    refreshList()
end

-- Defense-in-depth helpers for external callers
function options:IsReady()
    return options.frame ~= nil
end

function options:EnsureReady()
    createFrameOnce()
    return options.frame ~= nil
end

-- ======================= KaChing Exclusions (bag-only drop) =======================

KaChing = KaChing or {}
KaChing.OptionsMenu = KaChing.OptionsMenu or {}

-- Ensure per-character storage exists (SavedVariablesPerCharacter in TOC includes KaChing_ExcludedItemsList)
local function KM_EnsureExclusionStorage()
    KaChing_ExcludedItemsList = KaChing_ExcludedItemsList or {}
    return KaChing_ExcludedItemsList
end

-- Helper to extract a display name from an item link like |cff..|Hitem:123:..|h[Name]|h|r
local function KM_NameFromLink(link)
    if type(link) ~= "string" then return nil end
    local _, _, name = string.find(link, "%[(.-)%]")
    return name
end

-- Add a display name (mixed case) to storage as lowercase key; refresh list UI if available
local function KM_AddExcludedName(displayName)
    if not displayName or displayName == "" then return false end
    local lname = string.lower(displayName)

    -- Keep SVs and runtime map in sync using your existing helpers
    addToExclusion(lname)

    -- Refresh list UI
    if options.refreshExclusionList then
        options:refreshExclusionList()
    else
        -- fallback if method isn’t there for some reason
        refreshList()
    end
    return true
end

-- Main drop handler for the exclusion list target; **bag-only**
function options.OnExclusionDrop()
    local kind, itemID, itemLink, bag, slot = safe.GetCursorInfo_BagOnly()

    if not kind then
        -- Likely dragged from equipped slot; inform without crashing
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            UIErrorsFrame:AddMessage("KaChing: drag items from your bags (not equipped).")
        else
            DEFAULT_CHAT_FRAME:AddMessage("KaChing: drag items from your bags (not equipped).", 1, 0.2, 0.2)
        end
        if CursorHasItem and CursorHasItem() then ClearCursor() end
        return
    end

    -- Resolve a human-readable name
    local name = KM_NameFromLink(itemLink)
    if (not name or name == "") and bag and slot then
        -- Tooltip fallback from Safe.lua (returns lower + display); we use display
        local _lower, display = safe.GetItemNameLower(bag, slot)
        name = display
    end

    if not name or name == "" then
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            UIErrorsFrame:AddMessage("KaChing: couldn’t read that item’s name. Try again.")
        else
            DEFAULT_CHAT_FRAME:AddMessage("KaChing: couldn’t read that item’s name. Try again.", 1, 0.2, 0.2)
        end
        if CursorHasItem and CursorHasItem() then ClearCursor() end
        return
    end

    if KM_AddExcludedName(name) then
        DEFAULT_CHAT_FRAME:AddMessage("KaChing: excluded “" .. name .. "”.", 0.9, 0.9, 0.1)
    else
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            UIErrorsFrame:AddMessage("KaChing: failed to add to exclusions.")
        else
            DEFAULT_CHAT_FRAME:AddMessage("KaChing: failed to add to exclusions.", 1, 0.2, 0.2)
        end
    end

    -- Clear to avoid ghost cursor
    if CursorHasItem and CursorHasItem() then ClearCursor() end
end

-- Attach to your exclusion drop target frame
-- Call this once after you create the frame (e.g., right after you create the list UI).
function options.AttachExclusionDrop(targetFrame)
    if not targetFrame then return end
    targetFrame:EnableMouse(true)

    -- Classic/1.12: OnReceiveDrag is the primary drop path; also handle mouse-up while dragging
    targetFrame:SetScript("OnReceiveDrag", function()
        options.OnExclusionDrop()
    end)
    targetFrame:SetScript("OnMouseUp", function()
        if CursorHasItem and CursorHasItem() then
            options.OnExclusionDrop()
        end
    end)
end


-- Optional: debug ping so you can see when this file loads
-- Optional: debug ping so you can see when this file loads
if KaChing.Core and KaChing.Core.debuggingIsEnabled and KaChing.Core.debuggingIsEnabled() then
    DEFAULT_CHAT_FRAME:AddMessage("OptionsMenu.lua loaded", 1, 1, 0.5)
end
