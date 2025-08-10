-- MiniMapIcon.lua
-- ORIGINAL DATE: 5 August, 2025

KaChing = KaChing or {}
KaChing.MiniMapIcon = {}

local fileName  = "MiniMapIcon.lua"
local L         = KaChing.L
local minimap   = KaChing.MiniMapIcon
local core      = KaChing.Core

------------ DEBUG TOOL PRESENT IN EVERY FILE -------------------
local function dbgPrefix(stackTrace)
    if not stackTrace then
        stackTrace = debugstack(3, 1, 0)
    end

    -- Grab only the first line
    local firstLine = core:strsplit("\n", stackTrace, 2)[1] or ""

    -- Parse the line number from the string `Core:93: in ...`
    local _, _, lineStr = string.find(firstLine, "^[^:]+:(%d+):")
    local lineNumber = tonumber(lineStr) or 0

    return string.format("[%s:%d] ", fileName, lineNumber)
end
local function dbgPrint(...)
    local prefix = dbgPrefix(debugstack(2))
    local args = arg or {}  -- in case no args are passed

    local message = prefix
    for i = 1, table.getn(args) do
        message = message .. tostring(args[i])
        if i < table.getn(args) then
            message = message .. " "
        end
    end

    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(message, 1, 1, 0.5)
    end
end
-- dbgPrint()
-- dbgPrint("Hello", "world")
-- dbgPrint( 123 )
-------------------------------------------------------------------
function KaChing.MiniMapIcon:Create()
    local icon = CreateFrame("Button", "KaChingMinimapButton", Minimap)
    icon:SetFrameStrata("LOW")
    icon:SetWidth(32)
    icon:SetHeight(32)
    icon:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local tex = icon:CreateTexture(nil, "BACKGROUND")
    tex:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")  -- ID 133785
    tex:SetAllPoints(icon)
    icon.texture = tex

    icon:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 52, -52)

icon:SetScript("OnEnter", function(self)
    dbgPrint("ENTER: Setting tooltip owner")
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")

    dbgPrint("ENTER: Setting text")
    GameTooltip:SetText("KaChing", 1, 1, 1)

    dbgPrint("ENTER: Adding lines")
    GameTooltip:AddLine("Left-Click: Options", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-Click: Exclusion List", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Shift+Click: Add/Remove Item", 0.8, 0.8, 0.8)

    dbgPrint("ENTER: Showing tooltip")
    GameTooltip:Show()
end)
    icon:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    icon:SetScript("OnClick", function(self, button)
        if IsShiftKeyDown() then
            if button == "LeftButton" then
                dbgPrint("Shift-Left Click: Insert item into exclusion list")
                -- TODO: Logic to insert item
            elseif button == "RightButton" then
                dbgPrint("Shift-Right Click: Remove item from exclusion list")
                -- TODO: Logic to remove item
            end
        else
            if button == "LeftButton" then
                dbgPrint("Left Click: Open options menu")
                -- TODO: Show options UI
            elseif button == "RightButton" then
                dbgPrint("Right Click: Open exclusion list")
                -- TODO: Show exclusion list UI
            end
        end
    end)

    self.icon = icon
end

if core:debuggingIsEnabled() then
    local info = string.format("%s is loaded", fileName )
	DEFAULT_CHAT_FRAME:AddMessage( info, 0, 1, 0) 
end

