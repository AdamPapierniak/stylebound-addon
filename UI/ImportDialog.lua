-- UI/ImportDialog.lua — Paste-to-import modal (AceGUI-3.0)
-- Presentation only. Business logic lives in Import.lua and OutfitLibrary.lua.

local _, StyleBound = ...

local ImportDialog = StyleBound:NewModule("ImportDialog")

local AceGUI = LibStub("AceGUI-3.0")
local UI = StyleBound.UI

local frame = nil  -- singleton

-------------------------------------------------------------------------------
-- Frame helpers: position persistence + full-border dragging
-------------------------------------------------------------------------------

local function ConfigureFrame(aceFrame, positionKey, minWidth, minHeight)
    UI:ApplyFrame(aceFrame)

    -- Position persistence via AceGUI SetStatusTable
    if StyleBound.db and StyleBound.db.global.framePositions then
        aceFrame:SetStatusTable(StyleBound.db.global.framePositions[positionKey])
    end
    UI:EnforceMinimumFrame(aceFrame, minWidth, minHeight)

    -- Enable dragging from anywhere on the frame (not just title bar)
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
        -- Trigger AceGUI's status save by firing a fake "OnDragStop" on the status table
        local status = aceFrame.status or aceFrame.localstatus
        if status then
            status.top = self:GetTop()
            status.left = self:GetLeft()
        end
    end)
end

-- Human-readable slot names for the grid
local SLOT_DISPLAY_NAMES = {
    HEAD      = "Head",
    SHOULDER  = "Shoulders",
    BACK      = "Back",
    CHEST     = "Chest",
    SHIRT     = "Shirt",
    TABARD    = "Tabard",
    WRIST     = "Wrists",
    HANDS     = "Hands",
    WAIST     = "Waist",
    LEGS      = "Legs",
    FEET      = "Feet",
    MAINHAND  = "Main Hand",
    OFFHAND   = "Off Hand",
}

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function GetItemIcon(itemID)
    if not itemID then return 134400 end -- INV_Misc_QuestionMark
    local icon = C_Item.GetItemIconByID(itemID)
    return icon or 134400
end

local function GetItemNameAsync(itemID, callback)
    if not itemID then
        callback("Unknown Item")
        return
    end
    local item = Item:CreateFromItemID(itemID)
    item:ContinueOnItemLoad(function()
        callback(item:GetItemName() or ("Item " .. itemID))
    end)
end

-------------------------------------------------------------------------------
-- Slot grid view (shown after successful decode)
-------------------------------------------------------------------------------

local function BuildSlotGrid(container, outfit, collected)
    local scrollFrame = AceGUI:Create("ScrollFrame")
    scrollFrame:SetLayout("List")
    scrollFrame:SetFullWidth(true)
    scrollFrame:SetFullHeight(true)
    container:AddChild(scrollFrame)

    for _, slotKey in ipairs(StyleBound.SLOTS) do
        local slotData = outfit.slots[slotKey]
        if slotData then
            local row = UI:CreateRow(scrollFrame, collected[slotKey] == false and "gold" or "subtle", "Flow")

            -- Icon
            local icon = AceGUI:Create("Icon")
            icon:SetImage(GetItemIcon(slotData.i))
            icon:SetImageSize(24, 24)
            icon:SetWidth(32)
            icon:SetHeight(32)
            row:AddChild(icon)

            -- Slot name + item name label
            local label = AceGUI:Create("Label")
            local displayName = SLOT_DISPLAY_NAMES[slotKey] or slotKey
            local collectedStatus = collected[slotKey]

            if collectedStatus == false then
                label:SetText(displayName .. ": |cFFFF6600Loading...|r  |cFFFF0000(Not Collected)|r")
            else
                label:SetText(displayName .. ": Loading...")
            end
            label:SetWidth(350)
            label:SetFontObject(GameFontHighlight)
            UI:SetLabelColor(label, UI.Colors.text)
            row:AddChild(label)

            -- Async item name resolution
            if slotData.i then
                GetItemNameAsync(slotData.i, function(name)
                    if collectedStatus == false then
                        label:SetText(displayName .. ": |cFFFF6600" .. name .. "|r  |cFFFF0000(Not Collected)|r")
                    else
                        label:SetText(displayName .. ": " .. name)
                    end
                end)
            else
                local fallback = "Appearance " .. slotData.a
                if collectedStatus == false then
                    label:SetText(displayName .. ": |cFFFF6600" .. fallback .. "|r  |cFFFF0000(Not Collected)|r")
                else
                    label:SetText(displayName .. ": " .. fallback)
                end
            end

            -- Update icon once item loads
            if slotData.i then
                local item = Item:CreateFromItemID(slotData.i)
                item:ContinueOnItemLoad(function()
                    icon:SetImage(C_Item.GetItemIconByID(slotData.i) or 134400)
                end)
            end
        end
    end

    -- Hidden slots note
    if outfit.hidden and #outfit.hidden > 0 then
        local hiddenLabel = AceGUI:Create("Label")
        local names = {}
        for _, key in ipairs(outfit.hidden) do
            names[#names + 1] = SLOT_DISPLAY_NAMES[key] or key
        end
        hiddenLabel:SetText("Hidden: " .. table.concat(names, ", "))
        hiddenLabel:SetFullWidth(true)
        UI:SetLabelColor(hiddenLabel, UI.Colors.muted)
        scrollFrame:AddChild(hiddenLabel)
    end
end

-------------------------------------------------------------------------------
-- Preview in Dressing Room
-------------------------------------------------------------------------------

local function PreviewInDressingRoom(outfit)
    StyleBound:PreviewOutfitInDressingRoom(outfit)
end

------------------------------------------------------------------------------
-- Save to Library
------------------------------------------------------------------------------

local function GetDefaultOutfitName(outfit)
    local defaultName = "Imported outfit"
    if outfit.char and outfit.char.name then
        defaultName = outfit.char.name .. " outfit"
    end
    return defaultName
end

local function NormalizeOutfitName(name, fallback)
    name = name or ""
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then name = fallback end
    if #name > 64 then name = name:sub(1, 64) end
    return name
end

local function SaveToLibrary(outfit, name)
    local defaultName = GetDefaultOutfitName(outfit)
    local normalizedName = NormalizeOutfitName(name, defaultName)
    outfit.source = outfit.source or "import"

    local OutfitLibrary = StyleBound:GetModule("OutfitLibrary")
    local id = OutfitLibrary:Save(outfit, normalizedName)

    StyleBound:Print("Outfit saved: " .. normalizedName)
    return id, normalizedName
end

-------------------------------------------------------------------------------
-- Main dialog states
-------------------------------------------------------------------------------

local ShowResultState

local function ShowInputState(container)
    container:ReleaseChildren()
    container:SetLayout("List")

    local panel = UI:CreatePanel(container, "gold")
    UI:AddText(panel, "Paste an outfit string to inspect its slots, collection status, and dressing-room preview.", UI.Colors.muted)
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

        -- Strip whitespace
        encoded = encoded:gsub("%s+", "")

        local Import = StyleBound:GetModule("Import")

        -- Decode
        local outfit, decodeErr = Import:DecodeString(encoded)
        if not outfit then
            errorLabel:SetText("|cFFFF0000" .. decodeErr .. "|r")
            return
        end

        -- Validate
        local valid, validateErr = Import:ValidateSchema(outfit)
        if not valid then
            errorLabel:SetText("|cFFFF0000" .. validateErr .. "|r")
            return
        end

        -- Resolve collection
        local collected = Import:ResolveCollection(outfit)

        -- Show result state
        ShowResultState(container, outfit, collected, {
            back = function()
                ShowInputState(container)
            end,
            closeOnSave = true,
        })
    end)
    panel:AddChild(decodeBtn)
    UI:AddSpacer(panel, 8)

    C_Timer.After(0.05, function()
        editBox:SetFocus()
    end)
end

ShowResultState = function(container, outfit, collected, options)
    options = options or {}
    container:ReleaseChildren()
    container:SetLayout("List")

    local summaryPanel = UI:CreatePanel(container, "gold")

    -- Character info header
    if outfit.char then
        local c = outfit.char
        local charText = (c.name or "Unknown") .. "-" .. (c.realm or "Unknown")
        local parts = {}
        if c.race then parts[#parts + 1] = c.race end
        if c.class then parts[#parts + 1] = c.class end
        if c.sex then parts[#parts + 1] = c.sex end
        if c.faction then parts[#parts + 1] = c.faction end
        if #parts > 0 then
            charText = charText .. "  (" .. table.concat(parts, " ") .. ")"
        end
        local charLabel = AceGUI:Create("Label")
        charLabel:SetText("|cFFFFD100" .. charText .. "|r")
        charLabel:SetFullWidth(true)
        charLabel:SetFontObject(GameFontNormalLarge)
        summaryPanel:AddChild(charLabel)
    end

    -- Slot count + collection summary
    local slotCount = 0
    local missingCount = 0
    for slotKey in pairs(outfit.slots) do
        slotCount = slotCount + 1
        if collected[slotKey] == false then
            missingCount = missingCount + 1
        end
    end

    local summaryText = slotCount .. " slots"
    if missingCount > 0 then
        summaryText = summaryText .. "  |cFFFF6600(" .. missingCount .. " not collected)|r"
    end
    local summaryLabel = AceGUI:Create("Label")
    summaryLabel:SetText(summaryText)
    summaryLabel:SetFullWidth(true)
    summaryLabel:SetFontObject(GameFontHighlight)
    UI:SetLabelColor(summaryLabel, UI.Colors.text)
    summaryPanel:AddChild(summaryLabel)
    UI:AddDivider(summaryPanel)
    UI:AddSpacer(summaryPanel, 8)

    -- Slot grid (scrollable)
    local gridGroup = AceGUI:Create("SimpleGroup")
    gridGroup:SetFullWidth(true)
    gridGroup:SetHeight(280)
    gridGroup:SetLayout("Fill")
    UI:StylePanel(gridGroup, "subtle")
    container:AddChild(gridGroup)

    BuildSlotGrid(gridGroup, outfit, collected)

    -- Save + action buttons
    local actionPanel = UI:CreatePanel(container, "subtle")

    local nameBox = AceGUI:Create("EditBox")
    nameBox:SetLabel("Outfit Name:")
    nameBox:SetWidth(420)
    nameBox:SetText(GetDefaultOutfitName(outfit))
    actionPanel:AddChild(nameBox)

    local saveStatus = AceGUI:Create("Label")
    saveStatus:SetText("")
    saveStatus:SetFullWidth(true)
    UI:SetLabelColor(saveStatus, UI.Colors.green)
    actionPanel:AddChild(saveStatus)

    local btnGroup = AceGUI:Create("SimpleGroup")
    btnGroup:SetFullWidth(true)
    btnGroup:SetLayout("Flow")
    actionPanel:AddChild(btnGroup)

    local previewBtn = AceGUI:Create("Button")
    previewBtn:SetText("Preview in Dressing Room")
    previewBtn:SetWidth(200)
    previewBtn:SetCallback("OnClick", function()
        PreviewInDressingRoom(outfit)
    end)
    btnGroup:AddChild(previewBtn)

    local saveBtn = AceGUI:Create("Button")
    saveBtn:SetText("Save to Library")
    saveBtn:SetWidth(150)
    saveBtn:SetCallback("OnClick", function()
        local _, savedName = SaveToLibrary(outfit, nameBox:GetText())
        saveStatus:SetText("Saved: " .. savedName)
        saveBtn:SetText("Saved")
        saveBtn:SetDisabled(true)
        if nameBox.SetDisabled then
            nameBox:SetDisabled(true)
        end
        if options.afterSave then
            options.afterSave(savedName)
        end
        if options.closeOnSave and frame then
            C_Timer.After(0.15, function()
                if frame then
                    frame:Hide()
                end
            end)
        end
    end)
    btnGroup:AddChild(saveBtn)

    -- Back button
    local backBtn = AceGUI:Create("Button")
    backBtn:SetText("Back")
    backBtn:SetWidth(80)
    backBtn:SetCallback("OnClick", function()
        if options.back then
            options.back()
        else
            ShowInputState(container)
        end
    end)
    btnGroup:AddChild(backBtn)
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

function ImportDialog:Show()
    if frame then return end

    frame = AceGUI:Create("Frame")
    frame:SetTitle("StyleBound — Import Outfit")
    frame:SetWidth(640)
    frame:SetHeight(560)
    frame:SetLayout("Fill")
    ConfigureFrame(frame, "importDialog", 640, 560)
    frame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        frame = nil
    end)

    local content = AceGUI:Create("SimpleGroup")
    content:SetFullWidth(true)
    content:SetFullHeight(true)
    content:SetLayout("List")
    frame:AddChild(content)

    ShowInputState(content)
end

function ImportDialog:ShowResult(outfit, collected)
    if frame then
        frame:Hide()
    end

    frame = AceGUI:Create("Frame")
    frame:SetTitle("StyleBound — Import Preview")
    frame:SetWidth(640)
    frame:SetHeight(560)
    frame:SetLayout("Fill")
    ConfigureFrame(frame, "importDialog", 640, 560)
    frame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        frame = nil
    end)

    local content = AceGUI:Create("SimpleGroup")
    content:SetFullWidth(true)
    content:SetFullHeight(true)
    content:SetLayout("List")
    frame:AddChild(content)

    ShowResultState(content, outfit, collected, {
        closeOnSave = true,
    })
end

function ImportDialog:RenderResult(container, outfit, collected, options)
    ShowResultState(container, outfit, collected, options)
end

function ImportDialog:Hide()
    if not frame then return end
    frame:Hide()
end

function ImportDialog:IsShown()
    return frame ~= nil
end
