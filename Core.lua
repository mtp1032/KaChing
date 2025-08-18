--------------------------------------------------------------------------------------
-- Core.lua
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

KaChing = KaChing or {}          -- Create or reuse global addon table
KaChing.Core = KaChing.Core or {} -- Sub-table for your module
local core = KaChing.Core        -- Local alias for easier typing

local addonName = "KaChing"

local DEBUGGING_ENABLED = true

local addonExpansionName = "Classic (Turtle WoW)"
local addonVersion = GetAddOnMetadata( "KaChing", "Version")

function core:getAddonInfo()
    return addonName, addonVersion, addonExpansionName 
end
function core:enableDebugging()
    DEBUGGING_ENABLED = true
end
function core:disableDebugging() 
    DEBUGGING_ENABLED = false
end
function core:debuggingIsEnabled()
    return DEBUGGING_ENABLED
end

-- Optional: debug ping so you can see when this file loads
if KaChing.Core and KaChing.Core.debuggingIsEnabled and KaChing.Core.debuggingIsEnabled() then
    DEFAULT_CHAT_FRAME:AddMessage("Core.lua loaded", 1, 1, 0.5)
end
