-- EventHandler.lua
-- UPDATED: 10 August, 2025 (adds minimap icon create on login)

KaChing = KaChing or {}
KaChing.EventHandler = KaChing.EventHandler or {}

local core  = KaChing.Core or {}
local dbg   = KaChing.DebugTools or {}
local L     = KaChing.L or {}
local sell  = KaChing.SellItems or {}

local MERCHANT_IS_OPEN = false

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_CLOSED")
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
        local sell = KaChing.SellItems
        if sell and sell.initializeItemTable then
            sell.initializeItemTable()
        end

        -- Create minimap icon once, on login
        local mini = KaChing.MiniMapIcon
        if mini and mini.Create then
            mini:Create()
        end
        return
    end

    if event == "MERCHANT_SHOW" then
        MERCHANT_IS_OPEN = true
        local sell = KaChing.SellItems
        local dbg  = KaChing.DebugTools
        if not sell or not sell.createKaChingButton then
            if dbg and dbg.print then
                dbg:print("SellItems not ready (createKaChingButton missing)")
            end
            return
        end
        sell.createKaChingButton()
        return
    end

    if event == "MERCHANT_CLOSED" then
        MERCHANT_IS_OPEN = false
        return
    end

    if event == "BAG_UPDATE" then
        if not MERCHANT_IS_OPEN then return end
        return
    end
end)

if core:debuggingIsEnabled() and DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("EventHandler.lua is loaded", 0, 1, 0)
end
