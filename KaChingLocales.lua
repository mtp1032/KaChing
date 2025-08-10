-- KaChingLocales.lua
-- ORIGINAL DATE: 4 August, 2025

KaChing = KaChing or {}          -- Create or reuse global addon table
local core = KaChing.Core
local dbg = KaChing.DebugTools

local L = setmetatable({}, { __index = function(t, k)
	local v = tostring(k)
	rawset(t, k, v)
	return v
end })
KaChing.L = L

local addonName, version, expansion = core:getAddonInfo()
local LOCALE = GetLocale()      -- BLIZZ
if LOCALE == "enUS" or LOCALE == "enGB" then
local nameAndVersion = string.format("%s v %s (%s)", addonName, version, expansion )
	L["ADDON_NAME_AND_VERSION"] = nameAndVersion
	L["ADDON_LOADED_MESSAGE"]   = string.format("%s loaded - /kc for help.", nameAndVersion)
	L["KACHING_BTN_TOOLTIP"]     = "Click to start bulk sales."
	L["KACHING_POPUP_TEXT"]      = "Vendor buyback is full (12 items).\n\nClick the KaChing button again to continue selling the remaining items."
	L["KACHING_FUNCTION_NOT_READY"] = "KaChing: Sell function is not ready."
end

if core:debuggingIsEnabled() then
	-- check localilization symbols
-- 	DEFAULT_CHAT_FRAME:AddMessage(L["KACHING_BTN_TOOLTIP"], 0, 1, 0)
-- 	DEFAULT_CHAT_FRAME:AddMessage(L["KACHING_POPUP_TEXT"], 0, 1, 0)
-- 	DEFAULT_CHAT_FRAME:AddMessage(L["KACHING_FUNCTION_NOT_READY"], 0, 1, 0)

	DEFAULT_CHAT_FRAME:AddMessage(string.format("%s is loaded", "KaChingLocales.lua" ), 1, 1, 0.5)
end
