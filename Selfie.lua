-- Selfie.lua — S.E.L.F.I.E. toy integration
-- Detects the S.E.L.F.I.E. buff via UNIT_AURA, wraps the toy's native UI
-- in a StyleBound session for export handoff on completion.
-- Session state is shared with Screenshot.lua via StyleBound.session.

local _, StyleBound = ...

local SelfieModule = StyleBound:NewModule("Selfie", "AceEvent-3.0")

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

local SELFIE_TOY_ID      = 122637    -- S.E.L.F.I.E. Camera
local SELFIE_UPGRADED_ID  = 122674    -- S.E.L.F.I.E. Camera MkII
-- The selfie buff spell IDs (both versions of the toy)
local SELFIE_BUFF_IDS = {
    [181882] = true,  -- S.E.L.F.I.E. Camera (estimated, based on MkII pattern)
    [181884] = true,  -- S.E.L.F.I.E. Camera MkII (confirmed in-game)
}
local WATCHDOG_TIMEOUT = 300  -- 5 minutes

-------------------------------------------------------------------------------
-- Filename reconstruction (shared logic with Screenshot.lua)
-------------------------------------------------------------------------------

local pendingFilename = nil

local function ReconstructFilename()
    return date("WoWScrnShot_%m%d%y_%H%M%S.jpg")
end

-------------------------------------------------------------------------------
-- Name hiding (reuse the same CVars as Screenshot.lua)
-------------------------------------------------------------------------------

local NAME_CVARS = {
    "UnitNameNPC",
    "UnitNameOwn",
    "UnitNameNonCombatCreatureName",
    "UnitNameFriendlyPlayerName",
    "UnitNameFriendlyPetName",
    "UnitNameFriendlyGuardianName",
    "UnitNameFriendlyMinionName",
    "UnitNameFriendlySpecialNPCName",
    "UnitNameInteractiveNPC",
    "UnitNameEnemyPlayerName",
    "UnitNameEnemyPetName",
    "UnitNameEnemyGuardianName",
    "UnitNameEnemyMinionName",
    "UnitNamePlayerGuild",
    "UnitNamePlayerPVPTitle",
    "UnitNameFriendlyTotemName",
    "UnitNameEnemyTotemName",
    "UnitNameGuildTitle",
    "UnitNameHostleNPC",
    "nameplateShowAll",
    "nameplateShowFriends",
    "nameplateShowEnemies",
    "nameplateShowFriendlyNPCs",
    "SoftTargetInteract",
    "SoftTargetIconInteract",
    "SoftTargetForce",
    "SoftTargetEnemy",
    "SoftTargetFriend",
}

local function HideNames(session)
    session.savedNameCVars = {}
    for _, cvar in ipairs(NAME_CVARS) do
        session.savedNameCVars[cvar] = GetCVar(cvar)
        SetCVar(cvar, "0")
    end
end

local function RestoreNames(session)
    if session.savedNameCVars then
        for cvar, val in pairs(session.savedNameCVars) do
            SetCVar(cvar, val)
        end
    end
end

-------------------------------------------------------------------------------
-- Buff detection
-------------------------------------------------------------------------------

local function HasSelfieBuff()
    for spellId in pairs(SELFIE_BUFF_IDS) do
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellId)
        if aura then return true end
    end
    return false
end

-------------------------------------------------------------------------------
-- Secure button creation
-------------------------------------------------------------------------------

function SelfieModule:CreateButton(parent)
    local btn = CreateFrame("Button", "StyleBoundSelfieButton", parent, "SecureActionButtonTemplate")
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("macrotext", "/use item:122637")
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetSize(120, 26)

    -- Visual styling (UIPanelButtonTemplate-like)
    btn:SetNormalFontObject("GameFontNormal")
    btn:SetHighlightFontObject("GameFontHighlight")
    btn:SetDisabledFontObject("GameFontDisable")

    local ntex = btn:CreateTexture()
    ntex:SetTexture("Interface\\Buttons\\UI-Panel-Button-Up")
    ntex:SetTexCoord(0, 0.625, 0, 0.6875)
    ntex:SetAllPoints()
    btn:SetNormalTexture(ntex)

    local htex = btn:CreateTexture()
    htex:SetTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
    htex:SetTexCoord(0, 0.625, 0, 0.6875)
    htex:SetAllPoints()
    btn:SetHighlightTexture(htex)

    local ptex = btn:CreateTexture()
    ptex:SetTexture("Interface\\Buttons\\UI-Panel-Button-Down")
    ptex:SetTexCoord(0, 0.625, 0, 0.6875)
    ptex:SetAllPoints()
    btn:SetPushedTexture(ptex)

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    text:SetText("S.E.L.F.I.E.")
    btn.text = text

    -- Check if the player has the toy
    local hasToy = C_ToyBox.HasToy(SELFIE_TOY_ID) or C_ToyBox.HasToy(SELFIE_UPGRADED_ID)
    if not hasToy then
        btn:Disable()
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("S.E.L.F.I.E. Camera", 1, 1, 1)
            GameTooltip:AddLine("Requires the S.E.L.F.I.E. Camera toy.\nGet it from Sha'tari Defense\nquartermaster in Draenor.", 1, 0.8, 0, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        -- Fall through to regular screenshot mode on click
        btn:SetAttribute("type", nil)
        btn:SetScript("OnClick", function()
            StyleBound:GetModule("Screenshot"):StartSession()
        end)
    end

    self.button = btn
    return btn
end

-------------------------------------------------------------------------------
-- Session lifecycle
-------------------------------------------------------------------------------

function SelfieModule:StartSession()
    if StyleBound.session and StyleBound.session.active then
        StyleBound:Print("A session is already active.")
        return
    end

    local Export = StyleBound:GetModule("Export")

    local session = {
        active         = true,
        mode           = "selfie",
        startedAt      = GetTime(),
        shots          = {},
        outfitSnapshot = Export:BuildCurrentOutfit(),
        savedNameCVars = nil,
    }

    StyleBound.session = session

    -- Hide in-world names for cleaner selfies
    HideNames(session)

    -- Target name is hidden by CVars above

    -- Register for screenshot events
    self:RegisterEvent("SCREENSHOT_SUCCEEDED", "OnScreenshotSucceeded")
    self:RegisterEvent("SCREENSHOT_FAILED", "OnScreenshotFailed")

    -- Safety net: auto-end after 5 minutes
    self:StartWatchdog()

    StyleBound:Print("Selfie mode active. Take shots with the S.E.L.F.I.E. camera!")
end

function SelfieModule:EndSession()
    local session = StyleBound.session
    if not session or not session.active or session.mode ~= "selfie" then return end

    -- Stop watchdog
    self:StopWatchdog()

    -- Unregister events
    self:UnregisterEvent("SCREENSHOT_SUCCEEDED")
    self:UnregisterEvent("SCREENSHOT_FAILED")

    -- Restore names
    RestoreNames(session)

    -- Export handoff
    if #session.shots > 0 then
        local Export = StyleBound:GetModule("Export")
        local encoded = Export:EncodeOutfit(session.outfitSnapshot)

        StyleBound:Print("--- Selfie Session Complete ---")
        StyleBound:Print(#session.shots .. " shot(s) captured:")
        for i, shot in ipairs(session.shots) do
            StyleBound:Print("  " .. i .. ". " .. shot.filename)
        end
        StyleBound:Print("--- Export String ---")
        StyleBound:Print(encoded)
        StyleBound:Print("Screenshots folder: [World of Warcraft\\_retail_\\Screenshots]")
    else
        StyleBound:Print("Selfie session ended. No shots taken.")
    end

    -- Clear session
    StyleBound.session = nil
end

-------------------------------------------------------------------------------
-- Screenshot event handlers
-------------------------------------------------------------------------------

function SelfieModule:OnScreenshotSucceeded()
    local session = StyleBound.session
    if not session or not session.active or session.mode ~= "selfie" then return end

    local filename = pendingFilename or ReconstructFilename()
    pendingFilename = nil

    session.shots[#session.shots + 1] = {
        filename = filename,
        takenAt  = time(),
    }

    StyleBound:Print("StyleBound: shot #" .. #session.shots .. " captured")

    -- Reset watchdog
    self:StartWatchdog()
end

function SelfieModule:OnScreenshotFailed()
    local session = StyleBound.session
    if not session or not session.active or session.mode ~= "selfie" then return end

    pendingFilename = nil
    StyleBound:Print("Screenshot failed. Try again.")
end

-------------------------------------------------------------------------------
-- UNIT_AURA buff detection
-------------------------------------------------------------------------------

local wasBuffActive = false

function SelfieModule:OnEnable()
    self:RegisterEvent("UNIT_AURA", "OnUnitAura")
end

function SelfieModule:OnUnitAura(_, unit)
    if unit ~= "player" then return end

    local isBuffActive = HasSelfieBuff()

    if isBuffActive and not wasBuffActive then
        -- Buff just appeared — start session
        wasBuffActive = true
        self:StartSession()
    elseif not isBuffActive and wasBuffActive then
        -- Buff just faded — end session
        wasBuffActive = false
        self:EndSession()
    end
end

-------------------------------------------------------------------------------
-- Watchdog safety net
-------------------------------------------------------------------------------

local watchdogTimer = nil

function SelfieModule:StartWatchdog()
    self:StopWatchdog()
    watchdogTimer = C_Timer.NewTimer(WATCHDOG_TIMEOUT, function()
        if StyleBound.session and StyleBound.session.active and StyleBound.session.mode == "selfie" then
            StyleBound:Print("Selfie session timed out. Ending session.")
            wasBuffActive = false
            SelfieModule:EndSession()
        end
    end)
end

function SelfieModule:StopWatchdog()
    if watchdogTimer then
        watchdogTimer:Cancel()
        watchdogTimer = nil
    end
end
