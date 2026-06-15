-- UI/MainPanel.lua — Primary addon window (AceGUI-3.0)
-- Presentation only. Business logic lives in the root-level feature files.

local _, StyleBound = ...

local MainPanel = StyleBound:NewModule("MainPanel")

local AceGUI = LibStub("AceGUI-3.0")
local UI = StyleBound.UI

local frame = nil  -- singleton AceGUI frame

-------------------------------------------------------------------------------
-- Frame helpers: position persistence + full-border dragging
-------------------------------------------------------------------------------

local function ConfigureFrame(aceFrame, positionKey, minWidth, minHeight)
    UI:ApplyFrame(aceFrame)
    UI:HideStatusBar(aceFrame)

    if StyleBound.db and StyleBound.db.global.framePositions then
        aceFrame:SetStatusTable(StyleBound.db.global.framePositions[positionKey])
    end
    UI:EnforceMinimumFrame(aceFrame, minWidth, minHeight)

    local rawFrame = aceFrame.frame
    if minWidth and minHeight then
        if rawFrame.SetResizeBounds then
            rawFrame:SetResizeBounds(minWidth, minHeight)
        elseif rawFrame.SetMinResize then
            rawFrame:SetMinResize(minWidth, minHeight)
        end
    end
    rawFrame:SetMovable(true)
    rawFrame:EnableMouse(true)
    rawFrame:RegisterForDrag("LeftButton")
    rawFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    rawFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local status = aceFrame.status or aceFrame.localstatus
        if status then
            status.top = self:GetTop()
            status.left = self:GetLeft()
        end
    end)
end

-------------------------------------------------------------------------------
-- Export view
-------------------------------------------------------------------------------

local function AddCopyBox(container, labelText, text, lines)
    local box = AceGUI:Create("MultiLineEditBox")
    box:SetLabel(labelText)
    box:SetFullWidth(true)
    box:SetNumLines(lines or 4)
    box:SetText(text)
    box:DisableButton(true)
    container:AddChild(box)
    return box
end

local function ShowExportView(container)
    StyleBound:GetModule("OutfitBrowser"):ClearEmbedded()
    container:ReleaseChildren()
    container:SetLayout("List")

    local Export = StyleBound:GetModule("Export")
    local encoded = Export:GetExportString()

    local panel = UI:CreateSection(container, 4)
    UI:AddText(panel, "Copy this outfit string into stylebound.gg when you submit or share your current transmog.", UI.Colors.muted)
    UI:AddDivider(panel)

    local editBox = AddCopyBox(panel, "Current outfit string:", encoded, 3)
    UI:AddSpacer(panel, 8)

    local commandPanel = UI:CreateSection(container, 8)
    UI:AddText(commandPanel, "Using StyleBound", UI.Colors.text, GameFontNormalLarge)
    UI:AddDivider(commandPanel)
    UI:AddText(commandPanel, "|cFFFFD100/sb|r opens this panel.", UI.Colors.muted)
    UI:AddText(commandPanel, "|cFFFFD100/sb screenshot|r starts a manual clean screenshot session. Press Escape when you are done.", UI.Colors.muted)
    UI:AddText(commandPanel, "|cFFFFD100/sb autoshoot|r captures a quick three-angle screenshot set.", UI.Colors.muted)
    UI:AddText(commandPanel, "|cFFFFD100/sb copy|r copies your target's transmog into an import preview. For regular use, make a macro with /sb copy as the body, drag it to your bars, target a player, then press it.", UI.Colors.muted)
    UI:AddDivider(commandPanel)
    UI:AddText(commandPanel, "Screenshots are saved by WoW in |cFFFFD100World of Warcraft\\_retail_\\Screenshots|r. Sort that folder by date to find the newest StyleBound shots.", UI.Colors.muted)
    UI:AddText(commandPanel, "On |cFFFFD100stylebound.gg|r, import the outfit string from this Export tab and attach the matching screenshots from that folder.", UI.Colors.muted)
    UI:AddSpacer(commandPanel, 8)

    C_Timer.After(0.05, function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
end

-------------------------------------------------------------------------------
-- Screenshot view
-------------------------------------------------------------------------------

local function ShowScreenshotView(container)
    StyleBound:GetModule("OutfitBrowser"):ClearEmbedded()
    container:ReleaseChildren()
    container:SetLayout("List")

    local panel = UI:CreateSection(container, 4)
    UI:AddText(panel, "Take clean screenshots with the UI hidden. The addon keeps the matching outfit export ready when you finish.", UI.Colors.muted)
    UI:AddDivider(panel)

    local btnGroup = AceGUI:Create("SimpleGroup")
    btnGroup:SetFullWidth(true)
    btnGroup:SetLayout("Flow")
    panel:AddChild(btnGroup)

    -- Manual screenshot session
    local ssBtn = AceGUI:Create("Button")
    ssBtn:SetText("Screenshot Mode")
    ssBtn:SetWidth(200)
    ssBtn:SetCallback("OnClick", function()
        MainPanel:Hide()
        C_Timer.After(0.1, function()
            StyleBound:GetModule("Screenshot"):StartSession()
        end)
    end)
    btnGroup:AddChild(ssBtn)

    -- Auto-shoot
    local autoBtn = AceGUI:Create("Button")
    autoBtn:SetText("Auto-Shoot (3 Angles)")
    autoBtn:SetWidth(200)
    autoBtn:SetCallback("OnClick", function()
        MainPanel:Hide()
        C_Timer.After(0.1, function()
            StyleBound:GetModule("Screenshot"):StartAutoShoot()
        end)
    end)
    btnGroup:AddChild(autoBtn)

    -- S.E.L.F.I.E. button (secure frame, embedded)
    local selfieGroup = AceGUI:Create("SimpleGroup")
    selfieGroup:SetFullWidth(true)
    selfieGroup:SetLayout("Flow")
    panel:AddChild(selfieGroup)

    local selfieEnabled = StyleBound.db.global.settings.interceptSelfieCamera ~= false
    local selfieLabel = AceGUI:Create("Label")
    if selfieEnabled then
        selfieLabel:SetText("S.E.L.F.I.E. - use the toy directly. The addon detects the buff and tracks your shots automatically.")
    else
        selfieLabel:SetText("S.E.L.F.I.E. tracking is off. Enable it in Settings if you want StyleBound to track selfie shots.")
    end
    selfieLabel:SetFullWidth(true)
    UI:SetLabelColor(selfieLabel, UI.Colors.muted)
    selfieGroup:AddChild(selfieLabel)
    UI:AddSpacer(panel, 8)
end

-------------------------------------------------------------------------------
-- Placeholder views
-------------------------------------------------------------------------------

local function ShowImportView(container)
    StyleBound:GetModule("OutfitBrowser"):ClearEmbedded()
    container:ReleaseChildren()
    container:SetLayout("List")

    local Import = StyleBound:GetModule("Import")

    local panel = UI:CreateSection(container, 4)
    UI:AddText(panel, "Paste a StyleBound export string below to preview it in-game, check collection status, or save it to your library.", UI.Colors.muted)
    UI:AddDivider(panel)

    local editBox = AceGUI:Create("MultiLineEditBox")
    editBox:SetLabel("Export String:")
    editBox:SetFullWidth(true)
    editBox:SetNumLines(6)
    editBox:DisableButton(true)
    panel:AddChild(editBox)

    local errorLabel = AceGUI:Create("Label")
    errorLabel:SetText("")
    errorLabel:SetFullWidth(true)
    panel:AddChild(errorLabel)

    local decodeBtn = AceGUI:Create("Button")
    decodeBtn:SetText("Decode")
    decodeBtn:SetWidth(150)
    decodeBtn:SetCallback("OnClick", function()
        local encoded = editBox:GetText()
        if not encoded or encoded:match("^%s*$") then
            errorLabel:SetText("|cFFFF0000Please paste an export string.|r")
            return
        end
        encoded = encoded:gsub("%s+", "")

        local outfit, decodeErr = Import:DecodeString(encoded)
        if not outfit then
            errorLabel:SetText("|cFFFF0000" .. decodeErr .. "|r")
            return
        end

        local valid, validateErr = Import:ValidateSchema(outfit)
        if not valid then
            errorLabel:SetText("|cFFFF0000" .. validateErr .. "|r")
            return
        end

        local collected = Import:ResolveCollection(outfit)

        local ImportDialog = StyleBound:GetModule("ImportDialog")
        ImportDialog:RenderResult(container, outfit, collected, {
            back = function()
                ShowImportView(container)
            end,
        })
    end)
    panel:AddChild(decodeBtn)
    UI:AddSpacer(panel, 8)

    C_Timer.After(0.05, function()
        editBox:SetFocus()
    end)
end

local function ShowOutfitsView(container)
    local OutfitBrowser = StyleBound:GetModule("OutfitBrowser")
    OutfitBrowser:Hide()
    OutfitBrowser:ClearEmbedded()
    container:ReleaseChildren()
    OutfitBrowser:Render(container)
end

local function ShowSettingsView(container)
    StyleBound:GetModule("OutfitBrowser"):ClearEmbedded()
    container:ReleaseChildren()
    container:SetLayout("List")

    local panel = UI:CreateSection(container, 4)
    UI:AddText(panel, "Settings", UI.Colors.text, GameFontNormalLarge)
    UI:AddDivider(panel)

    local showMinimap = AceGUI:Create("CheckBox")
    showMinimap:SetLabel("Show minimap button")
    showMinimap:SetDescription("Toggle the StyleBound minimap launcher. You can always reopen this panel with /sb.")
    showMinimap:SetFullWidth(true)
    showMinimap:SetValue(StyleBound.db.global.settings.showMinimapButton ~= false)
    showMinimap:SetCallback("OnValueChanged", function(_, _, value)
        StyleBound:SetMinimapButtonShown(value)
    end)
    panel:AddChild(showMinimap)

    local interceptSelfie = AceGUI:Create("CheckBox")
    interceptSelfie:SetLabel("Track S.E.L.F.I.E. Camera toy")
    interceptSelfie:SetDescription("When enabled, StyleBound starts a screenshot handoff when the toy camera is active.")
    interceptSelfie:SetFullWidth(true)
    interceptSelfie:SetValue(StyleBound.db.global.settings.interceptSelfieCamera ~= false)
    interceptSelfie:SetCallback("OnValueChanged", function(_, _, value)
        StyleBound:GetModule("Selfie"):SetInterceptEnabled(value)
    end)
    panel:AddChild(interceptSelfie)

    UI:AddSpacer(panel, 8)
end

-------------------------------------------------------------------------------
-- Tab definitions
-------------------------------------------------------------------------------

local TABS = {
    { value = "export",     text = "Export"     },
    { value = "import",     text = "Import"     },
    { value = "outfits",    text = "Outfits"    },
    { value = "screenshot", text = "Screenshot" },
    { value = "settings",   text = "Settings"   },
}

local TAB_VIEWS = {
    export     = ShowExportView,
    import     = ShowImportView,
    outfits    = ShowOutfitsView,
    screenshot = ShowScreenshotView,
    settings   = ShowSettingsView,
}

-------------------------------------------------------------------------------
-- Panel creation
-------------------------------------------------------------------------------

local function CreatePanel()
    local f = AceGUI:Create("Frame")
    f:SetTitle("StyleBound")
    f:SetWidth(760)
    f:SetHeight(560)
    f:SetLayout("Fill")
    ConfigureFrame(f, "mainPanel", 760, 560)
    f:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        frame = nil
    end)

    local tabGroup = AceGUI:Create("TabGroup")
    tabGroup:SetTabs(TABS)
    tabGroup:SetLayout("Fill")
    UI:StyleTabGroup(tabGroup)
    tabGroup:SetCallback("OnGroupSelected", function(container, _, group)
        local viewFn = TAB_VIEWS[group]
        if viewFn then
            viewFn(container)
        end
    end)
    f:AddChild(tabGroup)

    -- Select the Export tab by default
    tabGroup:SelectTab("export")

    return f
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

function MainPanel:Toggle()
    if frame then
        self:Hide()
    else
        self:Show()
    end
end

function MainPanel:Show()
    if frame then return end
    frame = CreatePanel()
end

function MainPanel:Hide()
    if not frame then return end
    frame:Hide()
    -- OnClose callback handles release and nil
end

function MainPanel:IsShown()
    return frame ~= nil
end

function MainPanel:SelectTab(tabName)
    if not frame then
        self:Show()
    end
    -- The TabGroup is the first child of the frame
    if frame and frame.children and frame.children[1] then
        frame.children[1]:SelectTab(tabName)
    end
end
