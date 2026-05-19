-- Screenshot.lua — Session-based screenshot workflow
-- Hides UI, captures shots, hands off to export on completion.
-- Session state is in-memory only and does not survive /reload.

local _, StyleBound = ...

-- Capture the global Screenshot function before our module name shadows it
local TakeScreenshot = _G.Screenshot

local ScreenshotModule = StyleBound:NewModule("Screenshot", "AceEvent-3.0")

local function IsDebugLogging()
    return StyleBound.db
        and StyleBound.db.global
        and StyleBound.db.global.settings
        and StyleBound.db.global.settings.debugMode
end

local function DebugPrint(message)
    if IsDebugLogging() then
        StyleBound:Print(message)
    end
end

local function PrintDebugHandoff(title, shots, outfitSnapshot)
    if not IsDebugLogging() then
        return
    end

    local Export = StyleBound:GetModule("Export")
    local encoded = Export:EncodeOutfit(outfitSnapshot)

    StyleBound:Print("--- " .. title .. " Details ---")
    for i, shot in ipairs(shots) do
        local label = shot.label and (shot.label .. ": ") or ""
        StyleBound:Print("  " .. i .. ". " .. label .. shot.filename)
    end
    StyleBound:Print("--- Export String ---")
    StyleBound:Print(encoded)
    StyleBound:Print("Screenshots folder: [World of Warcraft\\_retail_\\Screenshots]")
end

-------------------------------------------------------------------------------
-- UI Hide / Restore
-------------------------------------------------------------------------------

-- All CVars that control in-world name rendering
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

local function HideUI(session)
    session.uiParentWasShown = UIParent:IsShown()
    UIParent:Hide()
    HideNames(session)
    -- Re-parent overlay to WorldFrame so it stays visible
    session.overlay:SetParent(WorldFrame)
    session.overlay:SetFrameStrata("FULLSCREEN_DIALOG")
    session.overlay:Show()
end

local function RestoreUI(session)
    RestoreNames(session)
    if session.uiParentWasShown then
        UIParent:Show()
    end
end

-------------------------------------------------------------------------------
-- Overlay Frame
-------------------------------------------------------------------------------

local function CreateOverlay(session)
    local f = CreateFrame("Frame", "StyleBoundScreenshotOverlay", UIParent, "BackdropTemplate")
    f:SetSize(200, 100)
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -20)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })

    -- Shot counter
    local counter = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    counter:SetPoint("TOP", f, "TOP", 0, -12)
    counter:SetText("Shots: 0")
    f.counter = counter

    -- Take Shot button
    local takeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    takeBtn:SetSize(80, 22)
    takeBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
    takeBtn:SetText("Take Shot")
    takeBtn:SetScript("OnClick", function()
        ScreenshotModule:Capture()
    end)

    -- Done button
    local doneBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    doneBtn:SetSize(80, 22)
    doneBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
    doneBtn:SetText("Done")
    doneBtn:SetScript("OnClick", function()
        ScreenshotModule:EndSession()
    end)

    -- Hint
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOP", counter, "BOTTOM", 0, -4)
    hint:SetText("Escape to finish")

    f:Show()
    return f
end

local function DestroyOverlay(session)
    if session.overlay then
        session.overlay:Hide()
        session.overlay:SetParent(nil)
        session.overlay = nil
    end
end

local function UpdateOverlay(session)
    if not session.overlay then return end
    session.overlay.counter:SetText("Shots: " .. #session.shots)
end

-------------------------------------------------------------------------------
-- Filename reconstruction
-------------------------------------------------------------------------------

local pendingFilename = nil

local function ReconstructFilename()
    return date("WoWScrnShot_%m%d%y_%H%M%S.jpg")
end

-------------------------------------------------------------------------------
-- Session lifecycle
-------------------------------------------------------------------------------

function ScreenshotModule:StartSession()
    if StyleBound.session and StyleBound.session.active then
        StyleBound:Print("A screenshot session is already active.")
        return
    end

    if InCombatLockdown() then
        StyleBound:Print("Cannot enter screenshot mode during combat.")
        return
    end

    local Export = StyleBound:GetModule("Export")

    local session = {
        active         = true,
        mode           = "screenshot",
        startedAt      = GetTime(),
        shots          = {},
        outfitSnapshot = Export:BuildCurrentOutfit(),
        hiddenFrames   = nil,
        overlay        = nil,
    }

    StyleBound.session = session

    -- Create overlay BEFORE hiding UI so we can exclude it
    session.overlay = CreateOverlay(session)

    -- Hide UI (overlay is excluded via the check in HideUI)
    HideUI(session)

    -- Bind Escape to end session
    local escBtn = CreateFrame("Button", "StyleBoundScreenshotEscBtn", session.overlay)
    escBtn:SetScript("OnClick", function() ScreenshotModule:EndSession() end)
    SetOverrideBindingClick(session.overlay, true, "ESCAPE", "StyleBoundScreenshotEscBtn")

    -- Register events
    self:RegisterEvent("SCREENSHOT_SUCCEEDED", "OnScreenshotSucceeded")
    self:RegisterEvent("SCREENSHOT_FAILED", "OnScreenshotFailed")

    -- Safety net: auto-restore after 5 minutes
    self:StartWatchdog()

    StyleBound:Print("Screenshot mode active. Take shots and press Escape when done.")
end

function ScreenshotModule:Capture()
    local session = StyleBound.session
    if not session or not session.active then return end

    -- Record the expected filename before the capture
    pendingFilename = ReconstructFilename()

    -- Hide overlay, wait a frame, then capture
    if session.overlay then
        session.overlay:Hide()
    end

    C_Timer.After(0.1, function()
        TakeScreenshot()
    end)
end

function ScreenshotModule:OnScreenshotSucceeded()
    local session = StyleBound.session
    if not session or not session.active then return end

    local filename = pendingFilename or ReconstructFilename()
    pendingFilename = nil

    session.shots[#session.shots + 1] = {
        filename = filename,
        takenAt  = time(),
    }

    -- Show overlay after a brief delay
    C_Timer.After(0.1, function()
        if session and session.overlay then
            session.overlay:Show()
            UpdateOverlay(session)
        end
    end)

    -- Reset watchdog
    self:StartWatchdog()
end

function ScreenshotModule:OnScreenshotFailed()
    local session = StyleBound.session
    if not session or not session.active then return end

    pendingFilename = nil

    if session.overlay then
        session.overlay:Show()
    end

    StyleBound:Print("Screenshot failed. Try again.")
end

function ScreenshotModule:EndSession()
    local session = StyleBound.session
    if not session or not session.active then return end

    -- Stop watchdog
    self:StopWatchdog()

    -- Unregister events
    self:UnregisterEvent("SCREENSHOT_SUCCEEDED")
    self:UnregisterEvent("SCREENSHOT_FAILED")

    -- Clear keybind override
    if session.overlay then
        ClearOverrideBindings(session.overlay)
    end

    -- Destroy overlay
    DestroyOverlay(session)

    -- Restore UI
    RestoreUI(session)

    -- Export handoff
    if #session.shots > 0 then
        StyleBound:Print("Screenshot session complete: " .. #session.shots .. " shot(s) saved.")
        PrintDebugHandoff("Screenshot Session", session.shots, session.outfitSnapshot)
    else
        StyleBound:Print("No shots taken. Session ended.")
    end

    -- Clear session
    StyleBound.session = nil
end

-------------------------------------------------------------------------------
-- Watchdog safety net
-------------------------------------------------------------------------------

local watchdogTimer = nil
local WATCHDOG_TIMEOUT = 300 -- 5 minutes

function ScreenshotModule:StartWatchdog()
    self:StopWatchdog()
    watchdogTimer = C_Timer.NewTimer(WATCHDOG_TIMEOUT, function()
        if StyleBound.session and StyleBound.session.active and StyleBound.session.mode == "screenshot" then
            StyleBound:Print("Screenshot session timed out. Restoring UI.")
            ScreenshotModule:EndSession()
        end
    end)
end

function ScreenshotModule:StopWatchdog()
    if watchdogTimer then
        watchdogTimer:Cancel()
        watchdogTimer = nil
    end
end

-------------------------------------------------------------------------------
-- Auto-Shoot Mode
-- Takes 3 screenshots from different angles automatically:
--   1. Front (current view flipped 180°)
--   2. Three-quarter (flipped back 135° from front, so 45° from original back)
--   3. Close-up front (zoomed in, same angle as shot 1 re-approached)
-- Saves/restores the original camera position using SaveView/SetView slot 5.
-------------------------------------------------------------------------------

local AUTO_SHOTS = {
    { label = "Full Body",     yaw = 180, zoom = 5.2 },
    { label = "Three-Quarter", yaw = 150, zoom = 3 },
    { label = "Close-Up",      yaw = 180, zoom = 2 },
}

local AUTO_PITCH_ADJUST = {
    -- A small downward view nudge levels the camera after SetView(2)'s high angle.
    enabled = true,
    direction = "down",
    speed = 0.18,
    duration = 0.14,
}

local autoShootState = nil

local function ZoomToDistance(targetDist)
    local current = GetCameraZoom()
    local diff = targetDist - current
    if diff > 0 then
        CameraZoomOut(diff)
    elseif diff < 0 then
        CameraZoomIn(-diff)
    end
end

local function StopCameraMotion()
    if MoveViewUpStop then
        MoveViewUpStop()
    elseif MoveViewUpStart then
        MoveViewUpStart(0)
    end

    if MoveViewDownStop then
        MoveViewDownStop()
    elseif MoveViewDownStart then
        MoveViewDownStart(0)
    end

    if MoveViewLeftStop then
        MoveViewLeftStop()
    elseif MoveViewLeftStart then
        MoveViewLeftStart(0)
    end

    if MoveViewRightStop then
        MoveViewRightStop()
    elseif MoveViewRightStart then
        MoveViewRightStart(0)
    end

    if MoveViewInStop then
        MoveViewInStop()
    elseif MoveViewInStart then
        MoveViewInStart(0)
    end

    if MoveViewOutStop then
        MoveViewOutStop()
    elseif MoveViewOutStart then
        MoveViewOutStart(0)
    end
end

local function NudgeAutoShootPitch(callback)
    if not AUTO_PITCH_ADJUST.enabled or AUTO_PITCH_ADJUST.duration <= 0 then
        if callback then callback() end
        return
    end

    local startPitch = AUTO_PITCH_ADJUST.direction == "down" and MoveViewDownStart or MoveViewUpStart
    if not startPitch then
        if callback then callback() end
        return
    end

    startPitch(AUTO_PITCH_ADJUST.speed)
    C_Timer.After(AUTO_PITCH_ADJUST.duration, function()
        StopCameraMotion()
        if callback then callback() end
    end)
end

local function RestoreAutoShootCamera()
    StopCameraMotion()

    -- Unwind the yaw first so movement/camera controls do not stay front-facing.
    if autoShootState and autoShootState.currentYaw ~= 0 then
        FlipCameraYaw(-autoShootState.currentYaw)
        autoShootState.currentYaw = 0
    end

    if SetView then
        SetView(5)
        C_Timer.After(0.05, function()
            StopCameraMotion()
            SetView(5)
        end)
        return
    end

    if autoShootState and autoShootState.originalZoom then
        ZoomToDistance(autoShootState.originalZoom)
    end
end

function ScreenshotModule:StartAutoShoot()
    if StyleBound.session and StyleBound.session.active then
        StyleBound:Print("A screenshot session is already active.")
        return
    end

    if InCombatLockdown() then
        StyleBound:Print("Cannot enter screenshot mode during combat.")
        return
    end

    local Export = StyleBound:GetModule("Export")

    local session = {
        active         = true,
        mode           = "autoshoot",
        startedAt      = GetTime(),
        shots          = {},
        outfitSnapshot = Export:BuildCurrentOutfit(),
        overlay        = nil,
    }

    StyleBound.session = session

    -- Save current camera position to slot 5
    SaveView(5)

    -- Hide UI and in-world names
    local anchor = CreateFrame("Frame", "StyleBoundAutoShootAnchor", UIParent)
    anchor:SetSize(1, 1)
    session.overlay = anchor
    session.uiParentWasShown = UIParent:IsShown()
    UIParent:Hide()
    HideNames(session)

    -- Register events for counting
    self:RegisterEvent("SCREENSHOT_SUCCEEDED", "OnAutoShootSucceeded")
    self:RegisterEvent("SCREENSHOT_FAILED", "OnAutoShootFailed")

    autoShootState = {
        shotIndex = 0,
        currentYaw = 0,           -- tracks accumulated FlipCameraYaw
        originalZoom = GetCameraZoom(),
    }

    StyleBound:Print("Auto-shoot starting: " .. #AUTO_SHOTS .. " shots.")

    -- Reset camera to a known baseline: directly behind the character
    -- SetView(2) is WoW's built-in "behind character" preset
    SetView(2)

    -- Wait for the camera to settle into the baseline position, then start
    C_Timer.After(1.5, function()
        if not session.active then return end
        NudgeAutoShootPitch(function()
            if not session.active then return end
            self:AutoShootNext()
        end)
    end)
end

function ScreenshotModule:AutoShootNext()
    local session = StyleBound.session
    if not session or not session.active then return end

    local state = autoShootState
    state.shotIndex = state.shotIndex + 1

    if state.shotIndex > #AUTO_SHOTS then
        -- All shots taken, finish up
        self:FinishAutoShoot()
        return
    end

    local shot = AUTO_SHOTS[state.shotIndex]

    -- Compute delta yaw from current accumulated yaw to desired yaw
    local yawDelta = shot.yaw - state.currentYaw
    if yawDelta ~= 0 then
        FlipCameraYaw(yawDelta)
    end
    state.currentYaw = shot.yaw

    ZoomToDistance(shot.zoom)

    -- Wait for camera to settle, then capture
    C_Timer.After(1.5, function()
        if not session.active then return end

        pendingFilename = ReconstructFilename()
        DebugPrint("Taking shot " .. state.shotIndex .. "/" .. #AUTO_SHOTS .. ": " .. shot.label)

        C_Timer.After(0.2, function()
            if not session.active then return end
            TakeScreenshot()
        end)
    end)
end

function ScreenshotModule:OnAutoShootSucceeded()
    local session = StyleBound.session
    if not session or not session.active or session.mode ~= "autoshoot" then return end

    local filename = pendingFilename or ReconstructFilename()
    pendingFilename = nil

    local label = AUTO_SHOTS[autoShootState.shotIndex] and AUTO_SHOTS[autoShootState.shotIndex].label or "Unknown"
    session.shots[#session.shots + 1] = {
        filename = filename,
        takenAt  = time(),
        label    = label,
    }

    -- Brief delay then take next shot
    C_Timer.After(0.3, function()
        self:AutoShootNext()
    end)
end

function ScreenshotModule:OnAutoShootFailed()
    local session = StyleBound.session
    if not session or not session.active or session.mode ~= "autoshoot" then return end

    pendingFilename = nil
    StyleBound:Print("Shot failed, skipping.")

    -- Continue to next shot
    C_Timer.After(0.3, function()
        self:AutoShootNext()
    end)
end

function ScreenshotModule:FinishAutoShoot()
    local session = StyleBound.session
    if not session then return end

    -- Unregister events
    self:UnregisterEvent("SCREENSHOT_SUCCEEDED")
    self:UnregisterEvent("SCREENSHOT_FAILED")

    -- Restore original yaw, pitch, and zoom.
    RestoreAutoShootCamera()

    -- Restore names and UI
    RestoreNames(session)

    if session.uiParentWasShown then
        UIParent:Show()
    end

    -- Clean up anchor frame
    if session.overlay then
        session.overlay:Hide()
        session.overlay:SetParent(nil)
        session.overlay = nil
    end

    -- Export handoff
    if #session.shots > 0 then
        StyleBound:Print("Auto-shoot complete: " .. #session.shots .. " screenshot(s) saved.")
        PrintDebugHandoff("Auto-Shoot", session.shots, session.outfitSnapshot)
    else
        StyleBound:Print("Auto-shoot complete but no shots captured.")
    end

    -- Clear state
    autoShootState = nil
    StyleBound.session = nil
end
