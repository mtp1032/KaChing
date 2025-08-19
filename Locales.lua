-- Locales.lua — basic localization scaffolding (Classic/Turtle, Lua 5.0)
-- UPDATED: 11 Aug 2025


KaChing         = KaChing or {}
KaChing.Locales = KaChing.Locales or {}   -- ✅ create the locales table
local L         = KaChing.Locales               -- ✅ alias for convenience

local LOCALE = (GetLocale and GetLocale()) and GetLocale() or "enUS"
local isEN = (LOCALE == "enUS") or (LOCALE == "enGB")

local addonName, addonVersion, addonExpansionName = KaChing.Core:getAddonInfo()

-- ---- English (default) strings ----
local defaults = {
    -- General / UI
    OPTIONS_TITLE      = "KaChing Options",
    EXCL_TITLE         = "Exclusion List",
    EXCL_EDIT_TIP      = "Drag and drop item here to add it to the list of excluded items (for example, your mining pick and/or fishing pole).",
    EXCL_ADD           = "Add",      -- kept for completeness (not currently used)
    EXCL_REMOVE        = "Remove",
    EXCL_REMOVE_TIP    = "Select item and click to remove it.",
    EXCL_CLEAR         = "Clear",
    EXCL_CLEAR_TIP     = "Click to clear the exclusion list of all items.",
    ADDON_LOADED_MESSAGE = string.format("%s %s loaded (%s)", addonName, addonVersion, addonExpansionName),

    -- Checkbox
    OPT_SELL_WHITE_AW  = "Sell white armor & weapons",
    TIP_SELL_WHITE_AW  = "If checked, all white armor and weapon items will be sold.",

    -- Minimap
    KACHING_MINIMAP_TIP = "Left-click: Options • Drag: Move",

    -- Selling summary
    SOLD_SUMMARY       = "KaChing: Sold %d item(s) for %dg %ds %dc.",
    SOLD_NOTHING       = "KaChing: Nothing to sell.",

    -- Class/quality cues (used for detection & tooltip scanning)
    ARMOR              = "Armor",
    WEAPON             = "Weapon",
}

-- Apply English strings for enUS/enGB explicitly
if isEN then
    local k, v
    for k, v in pairs(defaults) do
        L[k] = v
    end
end

do
    local k, v
    for k, v in pairs(defaults) do
        if L[k] == nil then
            L[k] = v  -- fall back to English for missing translations
        end
    end
end

if KaChing.Core and KaChing.Core.debuggingIsEnabled and KaChing.Core.debuggingIsEnabled() then
    DEFAULT_CHAT_FRAME:AddMessage("Locales.lua loaded", 1, 1, 0.5)
end
