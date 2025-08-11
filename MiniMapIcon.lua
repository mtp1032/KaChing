-- MiniMapIcon.lua
-- UPDATED: 10 August, 2025 (Classic/TWOW Lua 5.0, draggable, inside/outside rim)

KaChing = KaChing or {}
KaChing.MiniMapIcon = KaChing.MiniMapIcon or {}

local minimap  = KaChing.MiniMapIcon
local core     = KaChing.Core
local dbg      = KaChing.DebugTools
local L        = KaChing.L or {}
local options  = KaChing.OptionsMenu

local PI = 3.141592653589793

local function dprint(msg)
    if core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
        if dbg and dbg.print then dbg:print(msg) end
    end
end

-- Ensure SavedVariables exist + defaults
local function ensureSV()
    if type(KaChingDB) ~= "table" then KaChingDB = {} end
    if type(KaChingDB.minimap) ~= "table" then KaChingDB.minimap = {} end
    -- Default: place outside the minimap rim so it stands out
    if KaChingDB.minimap.outside == nil then KaChingDB.minimap.outside = true end
    if type(KaChingDB.minimap.insideOffset) ~= "number" then KaChingDB.minimap.insideOffset = 10 end
    if type(KaChingDB.minimap.outsideOffset) ~= "number" then KaChingDB.minimap.outsideOffset = 12 end
    if type(KaChingDB.minimap.angle) ~= "number" then KaChingDB.minimap.angle = PI / 4 end -- 45°
end

-- Compute radius based on inside/outside mode
local function computeRadius()
    local half = (Minimap:GetWidth() or 140) / 2
    ensureSV()
    if KaChingDB.minimap.outside then
        return half + KaChingDB.minimap.outsideOffset
    else
        return half - KaChingDB.minimap.insideOffset
    end
end

-- Keep button on a circle around the minimap center
local function placeButtonAtAngle(btn, angle)
    btn._angle = angle
    local radius = computeRadius()
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Angle from cursor to minimap center
local function cursorAngleToMinimap()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale() or UIParent:GetEffectiveScale() or 1
    px = px / scale; py = py / scale
    return math.atan2(py - my, px - mx)
end

-- Handlers (Classic uses 'this' / 'arg1')
local function OnEnter()
    if GameTooltip and this then
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:ClearLines()
        GameTooltip:SetText("KaChing", 1, 1, 1)
        GameTooltip:AddLine(L["MINIMAP_LEFT_CLICK"]  or "Left-Click: Options",         0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["MINIMAP_RIGHT_CLICK"] or "Right-Click: Exclusion List", 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["MINIMAP_SHIFT_CLICK"] or "Shift+Click: Add/Remove Item",0.8, 0.8, 0.8)
        local mode = (KaChingDB and KaChingDB.minimap and KaChingDB.minimap.outside) and "Outside" or "Inside"
        GameTooltip:AddLine("Drag to move • "..mode, 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end
end

local function OnLeave()
    if GameTooltip then GameTooltip:Hide() end
end

local function OnClick()
    if arg1 == "LeftButton" then
        options = options or KaChing.OptionsMenu
        if options and options.Toggle then
            options:Toggle()
        elseif options and options.menuCreate then
            options:menuCreate(); options:Toggle()
        else
            dprint("OptionsMenu not ready")
        end
    elseif arg1 == "RightButton" then
        dprint("Right-click: exclusion list (stub)")
    end
end

-- Drag: hold ALT while releasing to toggle inside/outside quickly (handy!)
local function OnUpdateDrag()
    local a = cursorAngleToMinimap()
    placeButtonAtAngle(this, a)
end

local function OnDragStart()
    this:SetScript("OnUpdate", OnUpdateDrag)
end

local function OnDragStop()
    this:SetScript("OnUpdate", nil)
    ensureSV()
    KaChingDB.minimap.angle = this._angle or (PI / 4)

    -- Optional quick toggle: ALT+drag+release flips inside/outside
    if IsAltKeyDown and IsAltKeyDown() then
        KaChingDB.minimap.outside = not KaChingDB.minimap.outside
        placeButtonAtAngle(this, KaChingDB.minimap.angle)
        dprint("Minimap icon mode: "..(KaChingDB.minimap.outside and "outside" or "inside"))
    end

    dprint("Minimap angle saved: "..string.format("%.2f", KaChingDB.minimap.angle))
end

-- Public helper (if you later want to flip via Options UI)
function minimap:SetOutsideMode(isOutside)
    ensureSV()
    KaChingDB.minimap.outside = (isOutside and true or false)
    if self.icon then
        placeButtonAtAngle(self.icon, KaChingDB.minimap.angle or (PI/4))
    end
end

function minimap:Create()
    local existing = getglobal("KaChingMinimapButton")
    if existing then return existing end
    if not Minimap then return end
    ensureSV()

    -- Base button (31x31 = standard)
    local btn = CreateFrame("Button", "KaChingMinimapButton", Minimap)
    btn:SetFrameStrata("MEDIUM")
    btn:SetWidth(31); btn:SetHeight(31); btn:SetFrameLevel(8)
    btn:EnableMouse(true)

    -- Border ring (gives the round look)
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetWidth(54); border:SetHeight(54)
    border:SetPoint("TOPLEFT", 0, 0)

    -- Icon (cropped)
    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01") -- 133785
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:SetWidth(20); icon:SetHeight(20)
    icon:SetPoint("CENTER", 0, 0)
    btn.icon = icon

    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Initial placement
    placeButtonAtAngle(btn, KaChingDB.minimap.angle or (PI / 4))

    -- Scripts
    btn:SetScript("OnEnter",     OnEnter)
    btn:SetScript("OnLeave",     OnLeave)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick",     OnClick)
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", OnDragStart)
    btn:SetScript("OnDragStop",  OnDragStop)

    self.icon = btn
    dprint("MiniMapIcon created ("..(KaChingDB.minimap.outside and "outside" or "inside")..")")
    return btn
end

if core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
    DEFAULT_CHAT_FRAME:AddMessage("MiniMapIcon.lua is loaded", 1, 1, 0)
end

