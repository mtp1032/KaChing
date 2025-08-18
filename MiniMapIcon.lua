--------------------------------------------------------------------------------------
-- MimiMap.lua
-- ORIGINAL DATE: 4 August, 2025

--[[ PROGRAMMING NOTES:
Turtle WoW AddOns are implemented in Lua 5.0:
- No string.match, use string.find or string.gfind
- No goto or select()
- _G is not available, use getglobal() or setfenv(0)
- # is not availble: 
-   Use table.getn(t) instead of #t
--  Use modulo instead of x # y
- Use tinsert(t, v) instead of table.insert(t, v)
- Can't use 'self.' Must use 'this' instead.
 ]]

KaChing = KaChing or {}
KaChing.MinimapIcon = KaChing.MinimapIcon or {}
local mm = KaChing.MinimapIcon 
local dbg = KaChing.DebugTools  -- ??
local L = KaChing.Locales

-- ---------- SavedVars: safe accessor ----------
-- Avoid indexing a nil global by always normalizing to a table.
local function getSV()
    local t = getglobal("KACHING_SAVED_OPTIONS")
    if type(t) ~= "table" then
        t = {}
        KACHING_SAVED_OPTIONS = t
    end
    return t
end

-- ---------- Options opener (defense-in-depth) ----------
local function openOptions()
    local opt = KaChing and KaChing.OptionsMenu
    if not opt then
        DEFAULT_CHAT_FRAME:AddMessage("KaChing: Options module not loaded.", 1, 0.3, 0.3)
        dbg:print("[MinimapIcon] OptionsMenu table is nil at click-time")
        return
    end

    if type(opt.EnsureReady) == "function" then
        opt:EnsureReady()
    elseif type(opt.menuCreate) == "function" then
        opt:menuCreate()
    end

    if type(opt.Toggle) == "function" then
        opt:Toggle()
    else
        DEFAULT_CHAT_FRAME:AddMessage("KaChing: Options menu not available.", 1, 0.3, 0.3)
        dbg:print("[MinimapIcon] OptionsMenu present, but no Toggle()")
    end
end

-- ---------- Minimap orbit drag helpers ----------
local function ensureDefaults()
    local sv = getSV()
    if sv.minimapAngle == nil then
        sv.minimapAngle = 45 -- degrees
    end
end

local function setMinimapPos(frame, angleDeg)
    ensureDefaults()
    local sv = getSV()
    sv.minimapAngle = angleDeg

    local rad = angleDeg * 0.017453292519943 -- pi/180
    local radius = 80
    local x = math.cos(rad) * radius
    local y = math.sin(rad) * radius
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function updateDrag(frame)
    local mx, my = Minimap:GetCenter()
    local scale  = UIParent:GetEffectiveScale()
    local px, py = GetCursorPosition()
    local x = (px / scale) - mx
    local y = (py / scale) - my
    local angle = math.deg(math.atan2(y, x))
    if angle < 0 then angle = angle + 360 end
    setMinimapPos(frame, angle)
end

-- ---------- creation (Blizzard art, always-visible) ----------
local function createOnce()
    if mm.frame then return mm.frame end
    ensureDefaults()

    local f = CreateFrame("Button", "KaChing_MinimapButton", Minimap)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(8)
    f:SetWidth(31); f:SetHeight(31)

    -- Border ring
    local border = f:CreateTexture(nil, "OVERLAY")
    border:SetWidth(53); border:SetHeight(53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)

    -- Icon
    local icon = f:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(20); icon:SetHeight(20)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("CENTER", f, "CENTER", 0, 1)
    f.icon = icon

    -- Tooltip
    f:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    f:SetScript("OnEnter", function()
        if not GameTooltip or not this then return end
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("KaChing", 1, 1, 1)
        GameTooltip:AddLine(L["KACHING_MINIMAP_TIP"] or "Left-click: Options • Drag: Move", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    -- Click (suppress after drag)
    f:RegisterForClicks("LeftButtonUp")
    f:SetScript("OnClick", function()
        if mm._wasDragging then
            mm._wasDragging = false
            return
        end
        openOptions()
    end)

    -- Orbit drag around minimap
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function()
        this:SetScript("OnUpdate", function() updateDrag(this) end)
    end)
    f:SetScript("OnDragStop", function()
        this:SetScript("OnUpdate", nil)
        mm._wasDragging = true
    end)

    -- Initial placement from SV (safe even pre-VARIABLES_LOADED via getSV)
    local sv = getSV()
    setMinimapPos(f, sv.minimapAngle or 45)
    f:Show()

    mm.frame = f
    dbg:print("[MinimapIcon] created at "..tostring(sv.minimapAngle).."°")
    return f
end

-- Public API
function mm:create() return createOnce() end
function mm:show() createOnce():Show() end
function mm:hide() if mm.frame then mm.frame:Hide() end end

-- Auto-create after saved vars load (also re-apply saved angle just in case)
local ev = CreateFrame("Frame")
ev:RegisterEvent("VARIABLES_LOADED")
ev:SetScript("OnEvent", function()
    local sv = getSV()
    if mm.frame then
        setMinimapPos(mm.frame, sv.minimapAngle or 45)
    else
        createOnce()
    end
end)

-- Optional: debug ping so you can see when this file loads
-- Optional: debug ping so you can see when this file loads
if KaChing.Core and KaChing.Core.debuggingIsEnabled and KaChing.Core.debuggingIsEnabled() then
    DEFAULT_CHAT_FRAME:AddMessage("MiniMapIcon.lua loaded", 1, 1, 0.5)
end
