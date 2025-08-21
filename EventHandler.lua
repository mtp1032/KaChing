-- EventHandler.lua
-- UPDATED: 21 Aug 2025 (dedupe MERCHANT_SHOW; correct L; clean earnings/session)

KaChing = KaChing or {}
KaChing.EventHandler = KaChing.EventHandler or {}

local core  = KaChing.Core or {}
local dbg   = KaChing.DebugTools or {}
local L     = KaChing.L or {}               -- ✅ use the canonical locales table
local sell  = KaChing.SellItems or {}

-- Track merchant state + earnings for one session
local MERCHANT_IS_OPEN = false

-- These track a single “merchant session” and prevent duplicate close prints
KaChing._merchantSessionId    = KaChing._merchantSessionId or 0
KaChing._merchantMoneyStart   = KaChing._merchantMoneyStart or nil
KaChing._printedCloseEarnings = KaChing._printedCloseEarnings or nil

local function formatMoney(copper)
    if type(copper) ~= "number" or copper <= 0 then return "0g 0s 0c" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper - g * 10000) / 100)
    local c = copper - g * 10000 - s * 100
    local out = ""
    if g > 0 then out = out .. g .. "g " end
    if s > 0 or g > 0 then out = out .. s .. "s " end
    return out .. c .. "c"
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("MERCHANT_CLOSED")
-- Optional in Phase I; keep registered only if you need it:
-- f:RegisterEvent("BAG_UPDATE")

f:SetScript("OnEvent", function()
    local e, a1 = event, arg1

    -- Addon bootstrap
    if e == "ADDON_LOADED" and a1 == "KaChing" then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(L["ADDON_LOADED_MESSAGE"] or "KaChing: Addon loaded", 1, 1, 0)
        end
        f:UnregisterEvent("ADDON_LOADED")
        return
    end

    if e == "PLAYER_LOGIN" then
        -- Safe late-bind of modules that may load after .toc order
        sell = KaChing.SellItems or sell
        if sell and sell.initializeItemTable then
            sell.initializeItemTable()
        end
        return
    end

    -- ===== SINGLE, DEDUPED MERCHANT_SHOW =====
    if e == "MERCHANT_SHOW" then
        MERCHANT_IS_OPEN = true

        -- Start a new merchant session
        KaChing._merchantSessionId  = (KaChing._merchantSessionId or 0) + 1
        KaChing._merchantMoneyStart = GetMoney and GetMoney() or 0
        KaChing._printedCloseEarnings = nil

        -- Create/ensure the KaChing button (SellItems guards duplicates internally)
        sell = KaChing.SellItems or sell
        if not sell or not sell.createKaChingButton then
            if dbg and dbg.print then dbg:print("SellItems not ready (createKaChingButton missing)") end
            return
        end
        sell.createKaChingButton()

        -- If you have an enable API, call it here (optional)
        if sell.SetButtonEnabled then sell.SetButtonEnabled(true) end

        return
    end

    if e == "MERCHANT_CLOSED" then
        MERCHANT_IS_OPEN = false

        -- One-shot guard per merchant session so we don’t print twice
        local sid = KaChing._merchantSessionId or 0
        if KaChing._printedCloseEarnings ~= sid then
            KaChing._printedCloseEarnings = sid

            local start = KaChing._merchantMoneyStart or 0
            local now   = GetMoney and GetMoney() or start
            KaChing._merchantMoneyStart = nil

            local delta = now - start
            if delta and delta > 0 then
                local line = "Transaction Completed. Earnings: " .. formatMoney(delta)
                if UIErrorsFrame and UIErrorsFrame.AddMessage then
                    UIErrorsFrame:AddMessage(line, 1.0, 0.1, 0.1, nil, 10)  -- fades after ~10s
                elseif DEFAULT_CHAT_FRAME then
                    DEFAULT_CHAT_FRAME:AddMessage(line, 1.0, 0.1, 0.1)
                end
            end
        end

        -- Optional: hide/disable button on close (if you expose an API)
        if sell and sell.hideKaChingButton then sell.hideKaChingButton() end
        if sell and sell.SetButtonEnabled then sell.SetButtonEnabled(false) end
        return
    end

    -- If you keep BAG_UPDATE in Phase I, gate it behind merchant open
    if e == "BAG_UPDATE" then
        if not MERCHANT_IS_OPEN then return end
        -- no-op in Phase I; handy as a “poke” signal for queues if needed
        return
    end
end)

-- Optional: file-load ping (respects core debug flag)
if core and core.debuggingIsEnabled and core:debuggingIsEnabled() and DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("EventHandler.lua loaded", 0, 1, 0)
end
