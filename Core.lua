--------------------------------------------------------------------------------------
-- Core.lua
-- ORIGINAL DATE: 4 August, 2025

KaChing = KaChing or {}          -- Create or reuse global addon table
KaChing.Core = KaChing.Core or {} -- Sub-table for your module
local core = KaChing.Core        -- Local alias for easier typing

local addonName = "KaChing"

local DEBUGGING_ENABLED = true
local isDebuggingEnabled = true
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

if core:debuggingIsEnabled() then
    DEFAULT_CHAT_FRAME:AddMessage( "Core.lua is loaded.", 1, 1, 0.5)
end
