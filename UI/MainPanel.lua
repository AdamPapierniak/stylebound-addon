-- UI/MainPanel.lua — Primary addon window (AceGUI-3.0)
-- Presentation only. Business logic lives in the root-level feature files.

local _, StyleBound = ...

local MainPanel = StyleBound:NewModule("MainPanel")

local AceGUI = LibStub("AceGUI-3.0")

local frame = nil  -- singleton AceGUI frame

-------------------------------------------------------------------------------
-- Frame helpers: position persistence + full-border dragging
-------------------------------------------------------------------------------

local function ConfigureFrame(aceFrame, positionKey)
    if StyleBound.db and StyleBound.db.global.framePositions then
        aceFrame:SetStatusTable(StyleBound.db.global.framePositions[positionKey])
    end

    local rawFrame = aceFrame.frame
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

local function ShowExportView(container)
    container:ReleaseChildren()
    container:SetLayout("List")

    local Export = StyleBound:GetModule("Export")
    local encoded = Export:GetExportString()

    local editBox = AceGUI:Create("EditBox")
    editBox:SetLabel("Your export string (Ctrl+A, Ctrl+C to copy):")
    editBox:SetFullWidth(true)
    editBox:SetText(encoded)
    editBox:DisableButton(true)
    container:AddChild(editBox)

    C_Timer.After(0.05, function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
end

-------------------------------------------------------------------------------
-- Screenshot view
-------------------------------------------------------------------------------

local function ShowScreenshotView(container)
    container:ReleaseChildren()

    local desc = AceGUI:Create("Label")
    desc:SetText("Take screenshots with the UI hidden. Your current outfit is captured automatically for export.")
    desc:SetFullWidth(true)
    container:AddChild(desc)

    local spacer = AceGUI:Create("Label")
    spacer:SetText(" ")
    spacer:SetFullWidth(true)
    container:AddChild(spacer)

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
    container:AddChild(ssBtn)

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
    container:AddChild(autoBtn)

    -- S.E.L.F.I.E. button (secure frame, embedded)
    local selfieGroup = AceGUI:Create("SimpleGroup")
    selfieGroup:SetFullWidth(true)
    selfieGroup:SetLayout("Flow")
    container:AddChild(selfieGroup)

    local selfieLabel = AceGUI:Create("Label")
    selfieLabel:SetText("\nS.E.L.F.I.E. — Use the toy directly. The addon detects the buff and tracks your shots automatically.")
    selfieLabel:SetFullWidth(true)
    selfieGroup:AddChild(selfieLabel)
end

-------------------------------------------------------------------------------
-- Placeholder views
-------------------------------------------------------------------------------

local function ShowImportView(container)
    container:ReleaseChildren()
    container:SetLayout("List")

    local Import = StyleBound:GetModule("Import")

    local desc = AceGUI:Create("Label")
    desc:SetText("Paste a StyleBound export string below to preview and import a transmog outfit.")
    desc:SetFullWidth(true)
    container:AddChild(desc)

    local spacer = AceGUI:Create("Label")
    spacer:SetText(" ")
    spacer:SetFullWidth(true)
    container:AddChild(spacer)

    local editBox = AceGUI:Create("MultiLineEditBox")
    editBox:SetLabel("Export String:")
    editBox:SetFullWidth(true)
    editBox:SetNumLines(6)
    editBox:DisableButton(true)
    container:AddChild(editBox)

    local errorLabel = AceGUI:Create("Label")
    errorLabel:SetText("")
    errorLabel:SetFullWidth(true)
    container:AddChild(errorLabel)

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

        -- Open standalone result dialog
        local ImportDialog = StyleBound:GetModule("ImportDialog")
        ImportDialog:ShowResult(outfit, collected)
    end)
    container:AddChild(decodeBtn)

    C_Timer.After(0.05, function()
        editBox:SetFocus()
    end)
end

local function ShowOutfitsView(container)
    container:ReleaseChildren()

    local desc = AceGUI:Create("Label")
    desc:SetText("Click below to open the full Outfit Browser, or use /sb outfits.")
    desc:SetFullWidth(true)
    container:AddChild(desc)

    local count = #StyleBound.db.global.outfits
    local countLabel = AceGUI:Create("Label")
    countLabel:SetText("\nYou have " .. count .. " saved outfit(s).")
    countLabel:SetFullWidth(true)
    container:AddChild(countLabel)

    local spacer = AceGUI:Create("Label")
    spacer:SetText(" ")
    spacer:SetFullWidth(true)
    container:AddChild(spacer)

    local browseBtn = AceGUI:Create("Button")
    browseBtn:SetText("Open Outfit Browser")
    browseBtn:SetWidth(200)
    browseBtn:SetCallback("OnClick", function()
        StyleBound:GetModule("OutfitBrowser"):Show()
    end)
    container:AddChild(browseBtn)
end

-------------------------------------------------------------------------------
-- Tab definitions
-------------------------------------------------------------------------------

local TABS = {
    { value = "export",     text = "Export"     },
    { value = "import",     text = "Import"     },
    { value = "outfits",    text = "Outfits"    },
    { value = "screenshot", text = "Screenshot" },
}

local TAB_VIEWS = {
    export     = ShowExportView,
    import     = ShowImportView,
    outfits    = ShowOutfitsView,
    screenshot = ShowScreenshotView,
}

-------------------------------------------------------------------------------
-- Panel creation
-------------------------------------------------------------------------------

local function CreatePanel()
    local f = AceGUI:Create("Frame")
    f:SetTitle("StyleBound")
    f:SetStatusText("StyleBound v0.1.0  |  stylebound.gg")
    f:SetWidth(500)
    f:SetHeight(450)
    f:SetLayout("Fill")
    ConfigureFrame(f, "mainPanel")
    f:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        frame = nil
    end)

    local tabGroup = AceGUI:Create("TabGroup")
    tabGroup:SetTabs(TABS)
    tabGroup:SetLayout("Fill")
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
