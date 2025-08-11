-- KaChingLocales.lua (excerpt; keep your file as-is and ensure these keys exist)
if LOCALE == "enUS" then
    local nameAndVersion = string.format("%s v %s (%s)", addonName, version, expansion )
    L["ADDON_NAME_AND_VERSION"]   = nameAndVersion
    L["ADDON_LOADED_MESSAGE"]     = string.format("%s loaded - /kc for help.", nameAndVersion)
    L["KACHING_BTN_TOOLTIP"]      = "Click to start bulk sales."
    L["KACHING_POPUP_TEXT"]       = "Vendor buyback is full (12 items).\n\nClick the KaChing button again to continue selling the remaining items."
    L["KACHING_FUNCTION_NOT_READY"]= "KaChing: Sell function is not ready."

    -- NEW: minimap tooltip lines
    L["MINIMAP_LEFT_CLICK"]       = "Left-Click: Options"
    L["MINIMAP_RIGHT_CLICK"]      = "Right-Click: Exclusion List"
    L["MINIMAP_SHIFT_CLICK"]      = "Shift+Click: Add/Remove Item"

    L["OPTIONS_TITLE"]       = "KaChing Options"
    L["OPT_SELL_WHITE_AW"]   = "Sell white armor & weapons"
    L["TIP_SELL_WHITE_AW"]   = "If checked, all white armor and weapon items will be sold."

    L["EXCL_PLACEHOLDER"]  = "Drag an item here or Shift-Click it…"
    L["EXCL_PLACEHOLDER"]  = ""
    L["EXCL_EDIT_TIP"] = "Drag and drop item here to add it to the list of excluded items (for example, your mining pick and/or fishing pole)."


    L["EXCL_ADD"]          = "Add"
    L["EXCL_REMOVE"]       = "Remove"

end
if DEFAULT_CHAT_FRAME and core and core.debuggingIsEnabled and core:debuggingIsEnabled() then
    DEFAULT_CHAT_FRAME:AddMessage("KaChingLocales.lua (batched build) is loaded", 1, 1, 0.5)
end
