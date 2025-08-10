-- EventHandler.lua
-- UPDATED: 9 August, 2025 (refactored)
KaChing = KaChing or {}
KaChing.EventHandler = KaChing.EventHandler or {}

local core  = KaChing.Core or {}
local dbg   = KaChing.DebugTools or {}
local L     = KaChing.L or {}
local sell  = KaChing.SellItems or {}

-- Track merchant state for BAG_UPDATE gating
local MERCHANT_IS_OPEN = false

-- Event frame
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_CLOSED")  -- fixed name
frame:RegisterEvent("BAG_UPDATE")

frame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "KaChing" then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(L["ADDON_LOADED_MESSAGE"] or "KaChing: Addon loaded", 1.0, 1.0, 0)
        end
        frame:UnregisterEvent("ADDON_LOADED")
        return
    end

    if event == "PLAYER_LOGIN" then
        -- Initialize item tables after everything is loaded
        local sell = KaChing.SellItems
        if sell and sell.initializeItemTable then
            sell.initializeItemTable()
        end
        return
    end

    -- MERCHANT_SHOW
    if event == "MERCHANT_SHOW" then
        MERCHANT_IS_OPEN = true

        -- Re-resolve to avoid any staleness if load order ever changes
        local sell = KaChing.SellItems
        local dbg  = KaChing.DebugTools

        if not sell or not sell.createKaChingButton then
            if dbg and dbg.print then
                dbg:print("SellItems not ready (createKaChingButton missing)")
            end
            return
        end

        sell.createKaChingButton()
        -- Optionally start listening for BAG_UPDATE only while merchant is open:
        -- frame:RegisterEvent("BAG_UPDATE")
        return
    end

    -- MERCHANT_CLOSED
    if event == "MERCHANT_CLOSED" then
        MERCHANT_IS_OPEN = false
        -- Optionally stop listening:
        -- frame:UnregisterEvent("BAG_UPDATE")
        return
    end

    if event == "BAG_UPDATE" then
        -- Only react to bag changes while merchant is open (e.g., to nudge a retry queue)
        if not MERCHANT_IS_OPEN then return end
        -- Intentionally a no-op in Phase I.
        return
    end
end)

-- Optional: file-load ping (respects your core debug flag)
if core:debuggingIsEnabled() and DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("EventHandler.lua is loaded", 1, 1, 0.5)
end
