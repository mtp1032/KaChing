-- DebugTools.lua
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
- Can't use 'self.' Must use 'this' instead in frame scripts.
]]

KaChing = KaChing or {}
KaChing.DebugTools = KaChing.DebugTools or {}

local dbg  = KaChing.DebugTools

-- ========= Internal buffer for console =========
dbg._buffer   = dbg._buffer or {}   -- array of lines
dbg._maxLines = 1000
dbg._console  = dbg._console or nil -- frame handle
dbg._edit     = dbg._edit or nil    -- editbox
dbg._scroll   = dbg._scroll or nil  -- scrollframe

-- ========= Prefix helper (kept from your version) =========
local function getPrefix(stackTrace)
    if not stackTrace then
        stackTrace = debugstack(2, 1, 0)
    end

    local newlinePos = string.find(stackTrace, "\n") or (string.len(stackTrace) + 1)
    local firstLine = string.sub(stackTrace, 1, newlinePos - 1)

    local _, _, filePath, lineStr = string.find(firstLine, "^([^:]+):(%d+):")
    if not lineStr then lineStr = "0" end

    if not filePath or not lineStr then
        return "[unknown:0] "
    end

    local _, _, fileName = string.find(filePath, "([^/\\]+)$")
    fileName = fileName or "unknown"

    local lineNumber = tonumber(lineStr) or 0
    return string.format("[%s:%d] ", fileName, lineNumber)
end

-- ========= Append to buffer + console =========
local function buffer_append(line)
    local n = table.getn(dbg._buffer) + 1
    dbg._buffer[n] = line
    while table.getn(dbg._buffer) > (dbg._maxLines or 1000) do
        table.remove(dbg._buffer, 1)
    end

    -- If console exists, refresh text
    if dbg._edit and dbg._scroll then
        -- Build text (cheap enough up to ~1000 lines)
        local text = table.concat(dbg._buffer, "\n")
        dbg._edit:SetText(text)
        dbg._edit:HighlightText(0, 0)      -- clear selection

        -- Size the edit box so scrolling works
        local lineCount = table.getn(dbg._buffer)
        local lineH = dbg._edit:GetLineHeight() or 14
        local minH = (dbg._scroll:GetHeight() or 200) + 50
        local wantH = (lineCount * lineH) + 20
        if wantH < minH then wantH = minH end
        dbg._edit:SetHeight(wantH)

        -- Scroll to bottom
        local range = dbg._scroll:GetVerticalScrollRange() or 0
        dbg._scroll:SetVerticalScroll(range)
    end
end

-- ========= Public: print (kept compatible) =========
function dbg:print(...)
    local prefix = getPrefix(debugstack(2, 1, 0)) or "[unknown:0] "

    local args = arg -- Lua 5.0 varargs table
    local message = prefix
    for i = 1, table.getn(args) do
        message = message .. tostring(args[i])
        if i < table.getn(args) then
            message = message .. " "
        end
    end

    -- Chat
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(message, 1, 1, 0.5)
    end

    -- Console mirror
    buffer_append(message)
end

-- ========= Debug console UI =========
function dbg:CreateConsole()
    if dbg._console then return end

    local f = CreateFrame("Frame", "KaChingDebugConsole", UIParent)
    f:SetWidth(560)
    f:SetHeight(360)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop",  function() this:StopMovingOrSizing() end)

    -- Backdrop (Classic 1.12 has SetBackdrop)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0, 0, 0, 0.85)
    end

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
    title:SetText("KaChing Debug Console")

    -- Close button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    if close then
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    else
        -- fallback close button
        local cb = CreateFrame("Button", nil, f)
        cb:SetWidth(18); cb:SetHeight(18)
        cb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
        cb:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        cb:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
        cb:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
        cb:SetScript("OnClick", function() this:GetParent():Hide() end)
    end

    -- ScrollFrame + EditBox
    local scroll = CreateFrame("ScrollFrame", "KaChingDebugScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -28)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 40)

    local edit = CreateFrame("EditBox", "KaChingDebugEditBox", scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:EnableMouse(true)
    edit:SetWidth(500)
    edit:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    edit:SetText("KaChing debug output...\n")
    edit:SetScript("OnEscapePressed", function() this:ClearFocus() end)

    -- Sizing: keep scroll child large enough
    local function resize_edit()
        local lineH = edit:GetLineHeight() or 14
        local lines = table.getn(dbg._buffer)
        local minH = (scroll:GetHeight() or 200) + 50
        local wantH = (lines * lineH) + 20
        if wantH < minH then wantH = minH end
        edit:SetHeight(wantH)
        edit:SetWidth(scroll:GetWidth() or 500)
    end

    scroll:SetScrollChild(edit)
    f:SetScript("OnShow", function()
        resize_edit()
        local text = table.concat(dbg._buffer, "\n")
        edit:SetText(text)
        edit:HighlightText(0, 0)
        local range = scroll:GetVerticalScrollRange() or 0
        scroll:SetVerticalScroll(range)
    end)
    f:SetScript("OnSizeChanged", function()
        resize_edit()
    end)

    -- Buttons: Copy All + Clear
    local copyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    copyBtn:SetText("Copy All")
    copyBtn:SetWidth(80); copyBtn:SetHeight(20)
    copyBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    copyBtn:SetScript("OnClick", function()
        edit:SetFocus()
        edit:HighlightText(0, -1) -- highlight everything
    end)

    local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetText("Clear")
    clearBtn:SetWidth(60); clearBtn:SetHeight(20)
    clearBtn:SetPoint("RIGHT", copyBtn, "LEFT", -8, 0)
    clearBtn:SetScript("OnClick", function()
        dbg._buffer = {}
        edit:SetText("")
        resize_edit()
    end)

    dbg._console = f
    dbg._edit    = edit
    dbg._scroll  = scroll
end

function dbg:ShowConsole()
    if not dbg._console then self:CreateConsole() end
    if dbg._console then dbg._console:Show() end
end
function dbg:HideConsole()
    if dbg._console then dbg._console:Hide() end
end
function dbg:ToggleConsole()
    if not dbg._console then self:CreateConsole() end
    if dbg._console:IsShown() then dbg._console:Hide() else dbg._console:Show() end
end

-- ========= Slash commands =========
SLASH_KACHINGDBG1 = "/kcd"
SLASH_KACHINGDBG2 = "/kdbg"
SlashCmdList["KACHINGDBG"] = function(msgText)
    -- normalize
    msgText = (msgText or "")
    local s, e = string.find(msgText, "^%s+")
    if s then msgText = string.sub(msgText, e + 1) end
    s, e = string.find(msgText, "%s+$")
    if s then msgText = string.sub(msgText, 1, s - 1) end
    msgText = string.lower(msgText)

    if msgText == "show" or msgText == "" then
        dbg:ShowConsole(); return
    elseif msgText == "hide" then
        dbg:HideConsole(); return
    elseif msgText == "toggle" then
        dbg:ToggleConsole(); return
    elseif msgText == "clear" then
        dbg._buffer = {}
        if dbg._edit then dbg._edit:SetText("") end
        return
    elseif msgText == "lines" then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("KaChing Debug: "..tostring(table.getn(dbg._buffer)).." lines buffered.", 0.5, 1, 0.5)
        end
        return
    end

    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00/kcd|r or |cffffff00/kdbg|r commands:", 1, 1, 0)
        DEFAULT_CHAT_FRAME:AddMessage("  show | hide | toggle | clear | lines", 1, 1, 0)
    end
end


-- Optional: debug ping so you can see when this file loads
if KaChing.Core and KaChing.Core.debuggingIsEnabled and KaChing.Core.debuggingIsEnabled() then
    DEFAULT_CHAT_FRAME:AddMessage("DebugTools.lua loaded", 1, 1, 0.5)
end
