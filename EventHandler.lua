-- EventHandler.lua
-- UPDATED: 13 August, 2025 (align Locales; keep existing semantics + minimap create)

KaChing = KaChing or {}                      -- addon namespace
KaChing.EventHandler = KaChing.EventHandler or {}
local ev = KaChing.EventHandler              -- this module

-- Don’t freeze references to other modules yet; declare locals…
local core, L, dbg, safe, sell, options, mm

local function bindModules()
    core    = KaChing.Core
    L       = KaChing.Locales                -- ✅ aligned: use the single canonical name
    dbg     = KaChing.DebugTools
    safe    = KaChing.Safe
    sell    = KaChing.SellItems
    options = KaChing.OptionsMenu
    mm      = KaChing.MinimapIcon            -- keep your chosen name consistent project-wide
    ev      = KaChing.EventHandler
end

-- Pretty-print copper as "Xg Ys Zc"
local function formatMoney(copper)
    if type(copper) ~= "number" or copper <= 0 then
        return "0g 0s 0c"
    end
    local g = math.floor(copper / 10000)
    local rem = copper - g * 10000
    local s = math.floor(rem / 100)
    local c = rem - s * 100

    local out = ""
    if g > 0 then out = out .. g .. "g " end
    if s > 0 or g > 0 then out = out .. s .. "s " end
    out = out .. c .. "c"
    return out
end

local MERCHANT_IS_OPEN = false
local EARNED_MONEY = 0

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_CLOSED")
frame:RegisterEvent("BAG_UPDATE")

frame:SetScript("OnEvent", function()
    local e, a1 = event, arg1

    if e == "ADDON_LOADED" and a1 == "KaChing" then
        bindModules()  -- bind BEFORE using L, core, etc.

        local addonName, addonVersion, addonExpansionName = core:getAddonInfo()
        local addonLoadedMsg = (L and L.ADDON_LOADED_MESSAGE)
            or string.format("%s %s loaded (%s)", addonName, addonVersion or "?", addonExpansionName or "?")

        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(addonLoadedMsg, 0.0, 1.0, 0.0)
        end

        frame:UnregisterEvent("ADDON_LOADED")
        return
    end

    if e == "PLAYER_LOGIN" then
        if sell and sell.initializeItemTable then
            sell.initializeItemTable()
        end
        -- Create minimap icon once, on login
        if mm and mm.create then
            mm:create()
        end
        return
    end

    if e == "MERCHANT_SHOW" then
        MERCHANT_IS_OPEN = true
        EARNED_MONEY = GetMoney()

        -- Re-resolve to avoid any staleness if load order ever changes
        local sell = KaChing.SellItems
        local dbg  = KaChing.DebugTools

        if not sell or not (sell.createKaChingButton or sell.CreateKaChingButton) then
            if dbg and dbg.print then
                dbg:print("SellItems not ready (create/CreateKaChingButton missing)")
            end
            return
        end

        -- support either naming
        if sell.createKaChingButton then
            sell.createKaChingButton()
        else
            sell.CreateKaChingButton(sell)
        end
        return
    end

    if e == "MERCHANT_CLOSED" then
        MERCHANT_IS_OPEN = false
        local moneyMade = GetMoney() - (EARNED_MONEY or 0)
        local earnedMoney = formatMoney(moneyMade)

        -- TODO: Also display this message in a frame where error frames usually appear
        DEFAULT_CHAT_FRAME:AddMessage(string.format("You earned %s", earnedMoney), 0, 1, 0)   
        return
    end

    if e == "BAG_UPDATE" then
        if not MERCHANT_IS_OPEN then return end
        -- Intentionally a no-op in Phase I.
        return
    end
end)

-- Optional: debug ping so you can see when this file loads
if KaChing.Core and KaChing.Core.debuggingIsEnabled and KaChing.Core.debuggingIsEnabled() then
    DEFAULT_CHAT_FRAME:AddMessage("EventHandler.lua loaded", 1, 1, 0.5)
end
