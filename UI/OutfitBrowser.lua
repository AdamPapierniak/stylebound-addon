-- UI/OutfitBrowser.lua — Browse, manage, and promote saved outfits
-- Two-pane layout: folder list + outfit list with action buttons.

local _, StyleBound = ...

local OutfitBrowser = StyleBound:NewModule("OutfitBrowser")

local AceGUI = LibStub("AceGUI-3.0")
local UI = StyleBound.UI

local frame = nil  -- singleton
local browserFolderPane = nil
local browserOutfitPane = nil
local browserSearchBox = nil
local embeddedRoot = nil
local embeddedFolderPane = nil
local embeddedOutfitPane = nil
local embeddedSearchBox = nil
local max = math.max
local min = math.min

local BROWSER_WIDTH = 980
local BROWSER_HEIGHT = 640
local SEARCH_HEIGHT = 58
local REGION_GAP = 10
local FOLDER_PANE_WIDTH = 205
local MIN_OUTFIT_PANE_WIDTH = 420
local MIN_CONTENT_HEIGHT = 180
local BROWSER_LAYOUT = "StyleBoundBrowser"

AceGUI:RegisterLayout(BROWSER_LAYOUT, function(content, children)
    local width = content.width or content:GetWidth() or 0
    local height = content.height or content:GetHeight() or 0
    local bodyTop = SEARCH_HEIGHT + REGION_GAP
    local bodyHeight = max(MIN_CONTENT_HEIGHT, height - bodyTop)
    local outfitWidth = max(MIN_OUTFIT_PANE_WIDTH, width - FOLDER_PANE_WIDTH - REGION_GAP)

    local search = children[1]
    if search then
        search:SetWidth(width)
        search:SetHeight(SEARCH_HEIGHT)
        search.frame:ClearAllPoints()
        search.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        search.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
        search.frame:Show()
        if search.DoLayout then search:DoLayout() end
    end

    local folders = children[2]
    if folders then
        folders:SetWidth(FOLDER_PANE_WIDTH)
        folders:SetHeight(bodyHeight)
        folders.frame:ClearAllPoints()
        folders.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -bodyTop)
        folders.frame:Show()
        if folders.DoLayout then folders:DoLayout() end
    end

    local outfits = children[3]
    if outfits then
        outfits:SetWidth(outfitWidth)
        outfits:SetHeight(bodyHeight)
        outfits.frame:ClearAllPoints()
        outfits.frame:SetPoint("TOPLEFT", content, "TOPLEFT", FOLDER_PANE_WIDTH + REGION_GAP, -bodyTop)
        outfits.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -bodyTop)
        outfits.frame:Show()
        if outfits.DoLayout then outfits:DoLayout() end
    end
end)

-- Slot display names for the detail view
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

local SLOT_ORDER = {
    "HEAD", "SHOULDER", "BACK", "CHEST", "SHIRT", "TABARD",
    "WRIST", "HANDS", "WAIST", "LEGS", "FEET", "MAINHAND", "OFFHAND",
}

local SLOT_SORT_INDEX = {}
for index, slotKey in ipairs(SLOT_ORDER) do
    SLOT_SORT_INDEX[slotKey] = index
end

local SOURCE_BADGES = {
    export = "|cFF00CC00Export|r",
    import = "|cFF3399FFImport|r",
    copy   = "|cFFFF9900Copy|r",
    manual = "|cFFCCCCCCManual|r",
}

local activeFolder = nil  -- nil = All
local BuildFolderPane
local BuildSearchResults

local function GetPaneLabelWidth(container)
    local width = container and container.frame and container.frame:GetWidth() or 0
    if width <= 0 then
        return 660
    end
    return max(280, min(660, width - 32))
end

local function TrimText(value)
    if not value then return "" end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function RefreshView(root, folderPane, outfitPane, searchBox, action)
    if not root or not folderPane or not outfitPane then
        return
    end
    if root.frame and not root.frame:IsShown() then
        return
    end

    if action == "save" then
        activeFolder = nil
        if searchBox then
            searchBox:SetText("")
        end
    end

    local query = searchBox and searchBox:GetText() or ""
    if query and query ~= "" then
        BuildSearchResults(outfitPane, query)
    else
        BuildFolderPane(folderPane, outfitPane)
    end

    if root.DoLayout then
        root:DoLayout()
    end
end

local function RefreshBrowser(action)
    RefreshView(frame, browserFolderPane, browserOutfitPane, browserSearchBox, action)
    RefreshView(embeddedRoot, embeddedFolderPane, embeddedOutfitPane, embeddedSearchBox, action)
end

-------------------------------------------------------------------------------
-- Frame helpers: position persistence + full-border dragging
-------------------------------------------------------------------------------

local function ConfigureFrame(aceFrame, positionKey, minWidth, minHeight)
    UI:ApplyFrame(aceFrame)
    UI:HideStatusBar(aceFrame)

    if StyleBound.db and StyleBound.db.global.framePositions then
        if not StyleBound.db.global.framePositions[positionKey] then
            StyleBound.db.global.framePositions[positionKey] = {}
        end
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
    if aceFrame.content and aceFrame.content.SetClipsChildren then
        aceFrame.content:SetClipsChildren(true)
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
-- Folder management dialogs
-------------------------------------------------------------------------------

local function PromptRenameFolder(folderName, refreshCallback)
    local renameFrame = AceGUI:Create("Frame")
    renameFrame:SetTitle("Rename Folder")
    renameFrame:SetWidth(330)
    renameFrame:SetHeight(145)
    renameFrame:SetLayout("List")
    UI:ApplyFrame(renameFrame)
    renameFrame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
    end)

    local nameBox = AceGUI:Create("EditBox")
    nameBox:SetLabel("Folder Name:")
    nameBox:SetFullWidth(true)
    nameBox:SetText(folderName or "")
    renameFrame:AddChild(nameBox)

    local saveBtn = AceGUI:Create("Button")
    saveBtn:SetText("Save")
    saveBtn:SetFullWidth(true)
    saveBtn:SetCallback("OnClick", function()
        local newName = TrimText(nameBox:GetText())
        if newName == "" then
            StyleBound:Print("Folder name cannot be empty.")
            return
        end
        if #newName > 48 then
            newName = newName:sub(1, 48)
        end

        local ok, reason = StyleBound:GetModule("OutfitLibrary"):RenameFolder(folderName, newName)
        if ok then
            activeFolder = newName
            StyleBound:Print("Renamed folder '" .. folderName .. "' to '" .. newName .. "'")
            AceGUI:Release(renameFrame)
            if refreshCallback then refreshCallback() end
        elseif reason == "exists" then
            StyleBound:Print("Folder '" .. newName .. "' already exists.")
        elseif reason == "missing" then
            StyleBound:Print("Folder '" .. folderName .. "' not found.")
        else
            StyleBound:Print("Could not rename folder.")
        end
    end)
    renameFrame:AddChild(saveBtn)

    C_Timer.After(0.05, function()
        nameBox:SetFocus()
        nameBox:HighlightText()
    end)
end

local function ConfirmDeleteFolder(folderName, refreshCallback)
    local deleteFrame = AceGUI:Create("Frame")
    deleteFrame:SetTitle("Delete Folder")
    deleteFrame:SetWidth(360)
    deleteFrame:SetHeight(150)
    deleteFrame:SetLayout("List")
    UI:ApplyFrame(deleteFrame)
    deleteFrame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
    end)

    local label = AceGUI:Create("Label")
    label:SetText("Delete folder |cFFFFD100" .. folderName .. "|r? Outfits stay saved and move back to All Outfits.")
    label:SetFullWidth(true)
    deleteFrame:AddChild(label)

    local btnGroup = AceGUI:Create("SimpleGroup")
    btnGroup:SetFullWidth(true)
    btnGroup:SetLayout("Flow")
    deleteFrame:AddChild(btnGroup)

    local delBtn = AceGUI:Create("Button")
    delBtn:SetText("Delete Folder")
    delBtn:SetWidth(150)
    delBtn:SetCallback("OnClick", function()
        if StyleBound:GetModule("OutfitLibrary"):DeleteFolder(folderName) then
            if activeFolder == folderName then
                activeFolder = nil
            end
            StyleBound:Print("Deleted folder '" .. folderName .. "'")
            AceGUI:Release(deleteFrame)
            if refreshCallback then refreshCallback() end
        else
            StyleBound:Print("Folder '" .. folderName .. "' not found.")
        end
    end)
    btnGroup:AddChild(delBtn)

    local cancelBtn = AceGUI:Create("Button")
    cancelBtn:SetText("Cancel")
    cancelBtn:SetWidth(120)
    cancelBtn:SetCallback("OnClick", function()
        AceGUI:Release(deleteFrame)
    end)
    btnGroup:AddChild(cancelBtn)
end

-------------------------------------------------------------------------------
-- Save as Custom Set
-------------------------------------------------------------------------------

local function SaveAsCustomSet(outfit)
    -- Check cap
    local currentSets = C_TransmogCollection.GetCustomSets()
    local maxSets = C_TransmogCollection.GetNumMaxCustomSets()
    if #currentSets >= maxSets then
        StyleBound:Print("|cFFFF0000You've reached the Custom Set cap (" .. maxSets .. "). Delete one in Collections → Sets → Custom Sets first.|r")
        return
    end

    -- Validate name
    local name = outfit.name or "StyleBound Outfit"
    if not C_TransmogCollection.IsValidCustomSetName(name) then
        -- Try appending a number to make it unique
        for i = 2, 99 do
            local tryName = name .. " " .. i
            if C_TransmogCollection.IsValidCustomSetName(tryName) then
                name = tryName
                break
            end
            if i == 99 then
                StyleBound:Print("|cFFFF0000Could not find a valid name for the Custom Set. Try renaming the outfit first.|r")
                return
            end
        end
    end

    -- Build the ItemTransmogInfoList from the same source IDs used for preview.
    local list = StyleBound:BuildItemTransmogInfoList(outfit)
    if not list then
        StyleBound:Print("|cFFFF0000Could not build a transmog set from this outfit.|r")
        return
    end

    -- Create
    local newSetID = C_TransmogCollection.NewCustomSet(name, 0, list)
    if newSetID then
        StyleBound:Print("|cFF00FF00Custom Set '" .. name .. "' created!|r Open Collections → Sets → Custom Sets to load it into an Outfit Slot.")
    else
        StyleBound:Print("|cFFFF0000Failed to create Custom Set. The name may be invalid or a set with that name may already exist.|r")
    end
end

-------------------------------------------------------------------------------
-- Preview in Dressing Room
-------------------------------------------------------------------------------

local function PreviewOutfit(outfit)
    StyleBound:PreviewOutfitInDressingRoom(outfit)
end

-------------------------------------------------------------------------------
-- Share (export string without char metadata)
-------------------------------------------------------------------------------

local function ShareOutfit(outfit)
    -- Build a stripped copy without character data
    local shareOutfit = {
        v     = outfit.v or 1,
        kind  = "outfit",
        slots = outfit.slots,
        t     = outfit.t or time(),
    }
    if outfit.hidden then
        shareOutfit.hidden = outfit.hidden
    end

    local Export = StyleBound:GetModule("Export")
    local encoded = Export:EncodeOutfit(shareOutfit)

    -- Show in a small dialog
    local shareFrame = AceGUI:Create("Frame")
    shareFrame:SetTitle("Share Outfit: " .. (outfit.name or "Untitled"))
    shareFrame:SetWidth(420)
    shareFrame:SetHeight(150)
    shareFrame:SetLayout("List")
    ConfigureFrame(shareFrame, "shareDialog")
    shareFrame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
    end)

    local editBox = AceGUI:Create("EditBox")
    editBox:SetLabel("Copy this string (Ctrl+A, Ctrl+C):")
    editBox:SetFullWidth(true)
    editBox:SetText(encoded)
    editBox:DisableButton(true)
    shareFrame:AddChild(editBox)

    C_Timer.After(0.05, function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
end

-------------------------------------------------------------------------------
-- Rename dialog
-------------------------------------------------------------------------------

local function PromptRename(outfit, refreshCallback)
    local renameFrame = AceGUI:Create("Frame")
    renameFrame:SetTitle("Rename Outfit")
    renameFrame:SetWidth(350)
    renameFrame:SetHeight(150)
    renameFrame:SetLayout("List")
    UI:ApplyFrame(renameFrame)
    renameFrame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
    end)

    local nameBox = AceGUI:Create("EditBox")
    nameBox:SetLabel("New Name:")
    nameBox:SetFullWidth(true)
    nameBox:SetText(outfit.name or "")
    renameFrame:AddChild(nameBox)

    local saveBtn = AceGUI:Create("Button")
    saveBtn:SetText("Save")
    saveBtn:SetFullWidth(true)
    saveBtn:SetCallback("OnClick", function()
        local newName = nameBox:GetText()
        if newName and newName ~= "" then
            if #newName > 64 then newName = newName:sub(1, 64) end
            StyleBound:GetModule("OutfitLibrary"):Rename(outfit.id, newName)
            StyleBound:Print("Renamed to '" .. newName .. "'")
            AceGUI:Release(renameFrame)
            if refreshCallback then refreshCallback() end
        end
    end)
    renameFrame:AddChild(saveBtn)

    C_Timer.After(0.05, function()
        nameBox:SetFocus()
        nameBox:HighlightText()
    end)
end

-------------------------------------------------------------------------------
-- Delete confirmation
-------------------------------------------------------------------------------

local function ConfirmDelete(outfit, refreshCallback)
    local deleteFrame = AceGUI:Create("Frame")
    deleteFrame:SetTitle("Delete Outfit")
    deleteFrame:SetWidth(350)
    deleteFrame:SetHeight(130)
    deleteFrame:SetLayout("List")
    UI:ApplyFrame(deleteFrame)
    deleteFrame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
    end)

    local label = AceGUI:Create("Label")
    label:SetText("Delete |cFFFFD100" .. (outfit.name or "Untitled") .. "|r? This cannot be undone.")
    label:SetFullWidth(true)
    deleteFrame:AddChild(label)

    local btnGroup = AceGUI:Create("SimpleGroup")
    btnGroup:SetFullWidth(true)
    btnGroup:SetLayout("Flow")
    deleteFrame:AddChild(btnGroup)

    local delBtn = AceGUI:Create("Button")
    delBtn:SetText("Delete")
    delBtn:SetWidth(120)
    delBtn:SetCallback("OnClick", function()
        StyleBound:GetModule("OutfitLibrary"):Delete(outfit.id)
        StyleBound:Print("Deleted '" .. (outfit.name or "Untitled") .. "'")
        AceGUI:Release(deleteFrame)
        if refreshCallback then refreshCallback() end
    end)
    btnGroup:AddChild(delBtn)

    local cancelBtn = AceGUI:Create("Button")
    cancelBtn:SetText("Cancel")
    cancelBtn:SetWidth(120)
    cancelBtn:SetCallback("OnClick", function()
        AceGUI:Release(deleteFrame)
    end)
    btnGroup:AddChild(cancelBtn)
end

-------------------------------------------------------------------------------
-- Move to folder dialog
-------------------------------------------------------------------------------

local function PromptMoveToFolder(outfit, refreshCallback)
    local moveFrame = AceGUI:Create("Frame")
    moveFrame:SetTitle("Move to Folder")
    moveFrame:SetWidth(300)
    moveFrame:SetHeight(200)
    moveFrame:SetLayout("List")
    UI:ApplyFrame(moveFrame)
    moveFrame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
    end)

    local label = AceGUI:Create("Label")
    label:SetText("Move |cFFFFD100" .. (outfit.name or "Untitled") .. "|r to:")
    label:SetFullWidth(true)
    moveFrame:AddChild(label)

    local spacer = AceGUI:Create("Label")
    spacer:SetText(" ")
    spacer:SetFullWidth(true)
    moveFrame:AddChild(spacer)

    -- "No Folder" option
    local noneBtn = AceGUI:Create("Button")
    noneBtn:SetText("No Folder")
    noneBtn:SetFullWidth(true)
    noneBtn:SetCallback("OnClick", function()
        StyleBound:GetModule("OutfitLibrary"):SetFolder(outfit.id, nil)
        StyleBound:Print("Removed '" .. (outfit.name or "Untitled") .. "' from folder.")
        AceGUI:Release(moveFrame)
        if refreshCallback then refreshCallback() end
    end)
    moveFrame:AddChild(noneBtn)

    -- One button per folder
    local folders = StyleBound.db.global.folders or {}
    for _, folderName in ipairs(folders) do
        local folderBtn = AceGUI:Create("Button")
        local btnText = folderName
        if outfit.folder == folderName then
            btnText = "► " .. folderName .. " (current)"
        end
        folderBtn:SetText(btnText)
        folderBtn:SetFullWidth(true)
        folderBtn:SetCallback("OnClick", function()
            StyleBound:GetModule("OutfitLibrary"):SetFolder(outfit.id, folderName)
            StyleBound:Print("Moved '" .. (outfit.name or "Untitled") .. "' to '" .. folderName .. "'.")
            AceGUI:Release(moveFrame)
            if refreshCallback then refreshCallback() end
        end)
        moveFrame:AddChild(folderBtn)
    end

    if #folders == 0 then
        local hint = AceGUI:Create("Label")
        hint:SetText("|cFF888888No folders yet. Create one from the left panel.|r")
        hint:SetFullWidth(true)
        moveFrame:AddChild(hint)
    end
end

-------------------------------------------------------------------------------
-- Collection status check for an outfit
-------------------------------------------------------------------------------

local function GetMissingSlots(outfit)
    local missing = {}
    local hasAppearance = C_TransmogCollection and C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance

    if not hasAppearance then
        return missing
    end

    for slotKey, slotData in pairs(outfit.slots or {}) do
        if slotData.s and slotData.s > 0 then
            local ok, collected = pcall(hasAppearance, slotData.s)
            if ok and not collected then
                missing[#missing + 1] = slotKey
            end
        end
    end
    table.sort(missing, function(a, b)
        local aIndex = SLOT_SORT_INDEX[a] or 99
        local bIndex = SLOT_SORT_INDEX[b] or 99
        if aIndex == bIndex then
            return a < b
        end
        return aIndex < bIndex
    end)
    return missing
end

local function FormatMissingSlots(missing)
    local names = {}
    for _, slotKey in ipairs(missing) do
        names[#names + 1] = SLOT_DISPLAY_NAMES[slotKey] or slotKey
    end
    return table.concat(names, ", ")
end

local function AddActionLink(container, text, width, callback, tint)
    local link = AceGUI:Create("InteractiveLabel")
    link:SetText((tint or "|cFFC9A84C") .. text .. "|r")
    link:SetWidth(width)
    link:SetFontObject(GameFontHighlightSmall)
    link:SetCallback("OnClick", callback)
    container:AddChild(link)
    return link
end

local function AttachTooltip(widget, title, body)
    if not widget or not widget.frame then
        return
    end

    widget.frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, 1, 0.82, 0)
        if body and body ~= "" then
            GameTooltip:AddLine(body, 0.85, 0.80, 0.70, true)
        end
        GameTooltip:Show()
    end)
    widget.frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-------------------------------------------------------------------------------
-- Build outfit list pane
-------------------------------------------------------------------------------

local function AddOutfitCards(container, outfits, refreshCallback)
    for _, outfit in ipairs(outfits) do
        local missing = GetMissingSlots(outfit)
        local slotCount = 0
        local labelWidth = GetPaneLabelWidth(container)
        for _ in pairs(outfit.slots or {}) do slotCount = slotCount + 1 end

        local card = UI:CreatePanel(container, #missing > 0 and "cardGold" or "card", false)
        card:SetHeight(60)
        card.noAutoHeight = true

        local row = AceGUI:Create("SimpleGroup")
        row:SetFullWidth(true)
        row:SetHeight(24)
        row.noAutoHeight = true
        row:SetLayout("Flow")
        UI:StylePanel(row, #missing > 0 and "titleStripGold" or "titleStrip")
        card:AddChild(row)

        local badge = SOURCE_BADGES[outfit.source] or ""
        local nameText = "|cFFFFD100" .. (outfit.name or "Untitled") .. "|r"
        if badge ~= "" then
            nameText = nameText .. "  " .. badge
        end
        nameText = nameText .. "  |cFF888888" .. slotCount .. " slots|r"
        if #missing > 0 then
            nameText = nameText .. "  |cFFFF6600" .. #missing .. " missing|r"
        end
        if outfit.folder then
            nameText = nameText .. "  |cFF888888[" .. outfit.folder .. "]|r"
        end

        local nameLabel = AceGUI:Create("InteractiveLabel")
        nameLabel:SetText(nameText)
        nameLabel:SetWidth(labelWidth)
        nameLabel:SetFontObject(GameFontNormal)
        nameLabel:SetCallback("OnClick", function()
            PreviewOutfit(outfit)
        end)
        row:AddChild(nameLabel)

        if #missing > 0 then
            AttachTooltip(nameLabel, "Missing appearances", FormatMissingSlots(missing))
        elseif outfit.folder then
            AttachTooltip(nameLabel, "Folder", outfit.folder)
        end

        local actionRow = AceGUI:Create("SimpleGroup")
        actionRow:SetFullWidth(true)
        actionRow:SetHeight(18)
        actionRow.noAutoHeight = true
        actionRow:SetLayout("Flow")
        card:AddChild(actionRow)

        AddActionLink(actionRow, "Preview", 56, function()
            PreviewOutfit(outfit)
        end)

        AddActionLink(actionRow, "Save Set", 70, function()
            SaveAsCustomSet(outfit)
        end)

        AddActionLink(actionRow, "Share", 48, function()
            ShareOutfit(outfit)
        end)

        AddActionLink(actionRow, "Folder", 52, function()
            PromptMoveToFolder(outfit, refreshCallback)
        end)

        AddActionLink(actionRow, "Rename", 58, function()
            PromptRename(outfit, refreshCallback)
        end)

        AddActionLink(actionRow, "Delete", 48, function()
            ConfirmDelete(outfit, refreshCallback)
        end, "|cFFFF6B5E")
    end
end

local function BuildOutfitList(container, refreshCallback)
    container:ReleaseChildren()

    local OutfitLibrary = StyleBound:GetModule("OutfitLibrary")
    local outfits = OutfitLibrary:List(activeFolder)

    if #outfits == 0 then
        local emptyPanel = UI:CreateSection(container, 4)
        emptyPanel:SetFullHeight(true)

        local emptyLabel = AceGUI:Create("Label")
        if activeFolder then
            emptyLabel:SetText("No outfits in folder '" .. activeFolder .. "'. Select All Outfits to see the rest of your library.")
        else
            emptyLabel:SetText("No saved outfits yet. Save outfits via /sb save, the Import screen, or /sb copy.")
        end
        emptyLabel:SetFullWidth(true)
        if emptyLabel.SetFontObject then
            emptyLabel:SetFontObject(GameFontHighlight)
        end
        UI:SetLabelColor(emptyLabel, UI.Colors.muted)
        emptyPanel:AddChild(emptyLabel)
        return
    end

    AddOutfitCards(container, outfits, refreshCallback)

    if container.DoLayout then
        container:DoLayout()
    end
end

-------------------------------------------------------------------------------
-- Build folder pane
-------------------------------------------------------------------------------

function BuildFolderPane(container, outfitContainer)
    container:ReleaseChildren()

    -- Rebuild both panes after selection changes or outfit edits.
    local refreshAll = function()
        BuildFolderPane(container, outfitContainer)
    end

    -- "All" button
    local allBtn = AceGUI:Create("InteractiveLabel")
    local outfitRecords = StyleBound.db.global.outfits or {}
    local allText = "All Outfits |cFF888888(" .. #outfitRecords .. ")|r"
    if activeFolder == nil then
        allText = "|cFF00FF00> |r" .. allText
    end
    allBtn:SetText(allText)
    allBtn:SetFullWidth(true)
    allBtn:SetFontObject(GameFontHighlight)
    allBtn:SetCallback("OnClick", function()
        activeFolder = nil
        refreshAll()
    end)
    container:AddChild(allBtn)

    -- Folder list
    local folders = StyleBound.db.global.folders or {}
    for _, folderName in ipairs(folders) do
        local currentFolder = folderName
        local folderBtn = AceGUI:Create("InteractiveLabel")
        local text = currentFolder
        if activeFolder == currentFolder then
            text = "|cFF00FF00> |r" .. text
        end
        -- Count outfits in folder
        local count = 0
        for _, o in ipairs(outfitRecords) do
            if o.folder == currentFolder then count = count + 1 end
        end
        text = text .. " |cFF888888(" .. count .. ")|r"
        folderBtn:SetText(text)
        folderBtn:SetFullWidth(true)
        folderBtn:SetFontObject(GameFontHighlight)
        folderBtn:SetCallback("OnClick", function()
            activeFolder = currentFolder
            refreshAll()
        end)
        container:AddChild(folderBtn)

        if activeFolder == currentFolder then
            local actions = AceGUI:Create("SimpleGroup")
            actions:SetFullWidth(true)
            actions:SetHeight(18)
            actions.noAutoHeight = true
            actions:SetLayout("Flow")
            container:AddChild(actions)

            AddActionLink(actions, "Rename", 68, function()
                PromptRenameFolder(currentFolder, refreshAll)
            end)

            AddActionLink(actions, "Delete", 52, function()
                ConfirmDeleteFolder(currentFolder, refreshAll)
            end, "|cFFFF6B5E")
        end
    end

    UI:AddSpacer(container, 6)

    -- New Folder button
    local newFolderBtn = AceGUI:Create("InteractiveLabel")
    newFolderBtn:SetText("|cFFFFD100+ New Folder|r")
    newFolderBtn:SetFullWidth(true)
    newFolderBtn:SetFontObject(GameFontHighlightSmall)
    newFolderBtn:SetCallback("OnClick", function()
        local promptFrame = AceGUI:Create("Frame")
        promptFrame:SetTitle("New Folder")
        promptFrame:SetWidth(300)
        promptFrame:SetHeight(130)
        promptFrame:SetLayout("List")
        UI:ApplyFrame(promptFrame)
        promptFrame:SetCallback("OnClose", function(widget)
            AceGUI:Release(widget)
        end)

        local nameBox = AceGUI:Create("EditBox")
        nameBox:SetLabel("Folder Name:")
        nameBox:SetFullWidth(true)
        promptFrame:AddChild(nameBox)

        local createBtn = AceGUI:Create("Button")
        createBtn:SetText("Create")
        createBtn:SetFullWidth(true)
        createBtn:SetCallback("OnClick", function()
            local name = TrimText(nameBox:GetText())
            if name and name ~= "" then
                if #name > 48 then
                    name = name:sub(1, 48)
                end

                local ok, reason = StyleBound:GetModule("OutfitLibrary"):CreateFolder(name)
                if ok then
                    StyleBound:Print("Created folder '" .. name .. "'")
                    AceGUI:Release(promptFrame)
                    refreshAll()
                elseif reason == "exists" then
                    StyleBound:Print("Folder '" .. name .. "' already exists.")
                else
                    StyleBound:Print("Folder name cannot be empty.")
                end
            else
                StyleBound:Print("Folder name cannot be empty.")
            end
        end)
        promptFrame:AddChild(createBtn)

        C_Timer.After(0.05, function()
            nameBox:SetFocus()
        end)
    end)
    container:AddChild(newFolderBtn)

    -- Build outfit list with the shared refresh
    BuildOutfitList(outfitContainer, refreshAll)
end

-------------------------------------------------------------------------------
-- Search
-------------------------------------------------------------------------------

function BuildSearchResults(outfitContainer, query)
    outfitContainer:ReleaseChildren()

    local OutfitLibrary = StyleBound:GetModule("OutfitLibrary")
    local results = OutfitLibrary:Search(query)

    if #results == 0 then
        local emptyPanel = UI:CreateSection(outfitContainer, 4)
        emptyPanel:SetFullHeight(true)

        local label = AceGUI:Create("Label")
        label:SetText("No outfits matching '" .. query .. "'.")
        label:SetFullWidth(true)
        if label.SetFontObject then
            label:SetFontObject(GameFontHighlight)
        end
        UI:SetLabelColor(label, UI.Colors.muted)
        emptyPanel:AddChild(label)
        return
    end

    local refreshSearch = function()
        BuildSearchResults(outfitContainer, query)
    end
    AddOutfitCards(outfitContainer, results, refreshSearch)

    if outfitContainer.DoLayout then
        outfitContainer:DoLayout()
    end
end

-------------------------------------------------------------------------------
-- Library chrome
-------------------------------------------------------------------------------

local function BuildLibraryChrome(root, target)
    -- Search bar at top
    local searchGroup = AceGUI:Create("SimpleGroup")
    searchGroup:SetHeight(SEARCH_HEIGHT)
    searchGroup.noAutoHeight = true
    searchGroup:SetLayout("Flow")
    root:AddChild(searchGroup)

    local searchBox = AceGUI:Create("EditBox")
    searchBox:SetLabel("Search:")
    searchBox:SetWidth(420)
    searchGroup:AddChild(searchBox)

    -- Left pane: folders (narrow)
    local folderPane = AceGUI:Create("SimpleGroup")
    folderPane:SetWidth(FOLDER_PANE_WIDTH)
    folderPane.noAutoHeight = true
    folderPane:SetLayout("List")
    root:AddChild(folderPane)

    -- Right pane: outfit list (fills remaining)
    local outfitPane = AceGUI:Create("ScrollFrame")
    outfitPane:SetLayout("List")
    root:AddChild(outfitPane)

    if target == "standalone" then
        browserFolderPane = folderPane
        browserOutfitPane = outfitPane
        browserSearchBox = searchBox
    elseif target == "embedded" then
        embeddedRoot = root
        embeddedFolderPane = folderPane
        embeddedOutfitPane = outfitPane
        embeddedSearchBox = searchBox
    end

    -- Wire up search
    searchBox:SetCallback("OnEnterPressed", function(_, _, text)
        if text and text ~= "" then
            BuildSearchResults(outfitPane, text)
        else
            BuildFolderPane(folderPane, outfitPane)
        end
    end)

    -- Initial render
    if root.DoLayout then
        root:DoLayout()
    end
    BuildFolderPane(folderPane, outfitPane)
end

-------------------------------------------------------------------------------
-- Panel creation
-------------------------------------------------------------------------------

local function CreateBrowser()
    local f = AceGUI:Create("Frame")
    f:SetTitle("StyleBound - Outfit Library")
    f:SetWidth(BROWSER_WIDTH)
    f:SetHeight(BROWSER_HEIGHT)
    f:SetLayout(BROWSER_LAYOUT)
    ConfigureFrame(f, "outfitBrowser", BROWSER_WIDTH, BROWSER_HEIGHT)
    f:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        frame = nil
        browserFolderPane = nil
        browserOutfitPane = nil
        browserSearchBox = nil
    end)

    BuildLibraryChrome(f, "standalone")
    return f
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

function OutfitBrowser:Toggle()
    if frame then
        self:Hide()
    else
        self:Show()
    end
end

function OutfitBrowser:Show()
    if frame then
        AceGUI:Release(frame)
        frame = nil
    end
    activeFolder = nil
    frame = CreateBrowser()
end

function OutfitBrowser:Hide()
    if not frame then return end
    frame:Hide()
end

function OutfitBrowser:IsShown()
    return frame ~= nil
end

function OutfitBrowser:Render(container)
    activeFolder = nil
    embeddedRoot = nil
    embeddedFolderPane = nil
    embeddedOutfitPane = nil
    embeddedSearchBox = nil

    container:SetLayout("Fill")

    local root = AceGUI:Create("SimpleGroup")
    root:SetFullWidth(true)
    root:SetFullHeight(true)
    root:SetLayout(BROWSER_LAYOUT)
    container:AddChild(root)

    BuildLibraryChrome(root, "embedded")
end

function OutfitBrowser:ClearEmbedded()
    embeddedRoot = nil
    embeddedFolderPane = nil
    embeddedOutfitPane = nil
    embeddedSearchBox = nil
end

function OutfitBrowser:Refresh(_, action)
    RefreshBrowser(action)
end

function OutfitBrowser:OnEnable()
    if StyleBound.RegisterMessage then
        StyleBound.RegisterMessage(self, "STYLEBOUND_OUTFITS_CHANGED", "Refresh")
    end
end

function OutfitBrowser:OnDisable()
    if StyleBound.UnregisterMessage then
        StyleBound.UnregisterMessage(self, "STYLEBOUND_OUTFITS_CHANGED")
    end
end
