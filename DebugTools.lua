-- DebugTools.lua
-- ORIGINAL DATE: 4 August, 2025

KaChing = KaChing or {}
KaChing.DebugTools = {}

local dbg = KaChing.DebugTools
local core  = KaChing.Core

local function getPrefix(stackTrace)
    if not stackTrace then
        stackTrace = debugstack(2, 1, 0)
    end

    local newlinePos = string.find(stackTrace, "\n") or (string.len(stackTrace) + 1)
    local firstLine = string.sub(stackTrace, 1, newlinePos - 1)

    local _, _, filePath, lineStr = string.find(firstLine, "^([^:]+):(%d+):")
    if not lineStr then
        lineStr = "0"
    end

    if not filePath or not lineStr then
        return "[unknown:0] "
    end

    -- Use string.find to extract filename from path (no string.match)
    local _, _, fileName = string.find(filePath, "([^/\\]+)$")
    fileName = fileName or "unknown"

    local lineNumber = tonumber(lineStr) or 0
    return string.format("[%s:%d] ", fileName, lineNumber)
end

function dbg:print(...)
    local prefix = getPrefix(debugstack(2, 1, 0)) 
    if not prefix then
        prefix = "[unknown:0] "
    end

    local args = arg  -- Lua 5.0: varargs table

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

-- dbg:print()
-- dbg:print("Hello world!")
-- dbg:print( "arg1", "arg2", "arg3" )
-- dbg:print( "this is a number: ", 42, " and this is a boolean: ", true, " and this is a table: ", {1, 2, 3} )

if core:debuggingIsEnabled() then
    local fileName = "DebugTools.lua"
    local info = string.format("%s is loaded", fileName )
	DEFAULT_CHAT_FRAME:AddMessage( info, 1, 1, 0.5)
end


