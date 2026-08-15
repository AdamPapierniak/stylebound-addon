-- Housing.lua - Resolve a Blizzard housing blueprint into a shareable manifest.

local _, StyleBound = ...

local Housing = StyleBound:NewModule("Housing", "AceEvent-3.0")

local CONTENT_NAMES = {
    [1] = "house_type",
    [2] = "room",
    [3] = "decor",
    [4] = "dye",
    [5] = "fixture",
    [6] = "other",
}

local function NormalizeCode(code)
    return tostring(code or ""):gsub("%s+", "")
end

local function BlueprintTypeName(value)
    local types = Enum and Enum.HousingBlueprintType
    if not types then return nil end
    if value == types.House then return "house" end
    if value == types.Room then return "room" end
    if value == types.Interior then return "interior" end
    if value == types.Exterior then return "exterior" end
    return nil
end

local function CatalogInfoFor(contentType, recordID)
    if not C_HousingCatalog or not C_HousingCatalog.GetCatalogEntryInfoByRecordID then
        return nil
    end
    local entryTypes = Enum and Enum.HousingCatalogEntryType
    if not entryTypes then return nil end

    local entryType
    if contentType == 3 then
        entryType = entryTypes.Decor
    elseif contentType == 2 then
        entryType = entryTypes.Room
    else
        return nil
    end

    local ok, info = pcall(C_HousingCatalog.GetCatalogEntryInfoByRecordID, entryType, recordID)
    if ok then return info end
    return nil
end

local function NormalizeBudgets(source)
    local budgets = {}
    for budgetType, entry in pairs(source or {}) do
        if type(entry) == "table" then
            budgets[#budgets + 1] = {
                budgetType = tonumber(entry.budgetType) or tonumber(budgetType) or 0,
                cost = tonumber(entry.cost) or 0,
            }
        end
    end
    table.sort(budgets, function(a, b) return a.budgetType < b.budgetType end)
    return budgets
end

function Housing:OnEnable()
    self:RegisterEvent("HOUSING_BLUEPRINT_CONTENTS_RECEIVED")
    self:RegisterEvent("HOUSING_BLUEPRINT_CONTENTS_FAILURE")

    if not self:InstallDashboardHook() then
        self:RegisterEvent("ADDON_LOADED")
    end
    self:StartDashboardWatcher()
end

function Housing:OnDisable()
    if self.dashboardWatcher then
        self.dashboardWatcher:Cancel()
        self.dashboardWatcher = nil
    end
end

function Housing:EncodeManifest(manifest)
    local SBJSON = LibStub("SBJSON")
    local LibDeflate = LibStub("LibDeflate")
    local json = SBJSON.Encode(manifest)
    return LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(json))
end

function Housing:BuildManifest(contentInfo)
    local requirements = {}
    for _, group in ipairs(contentInfo.contentGroups or {}) do
        for _, entry in ipairs(group.entries or {}) do
            local contentType = tonumber(entry.contentType or group.contentType) or 6
            local catalog = CatalogInfoFor(contentType, entry.recordID)
            requirements[#requirements + 1] = {
                contentType = CONTENT_NAMES[contentType] or "other",
                recordId = tonumber(entry.recordID) or 0,
                itemId = catalog and catalog.itemID or nil,
                name = (catalog and catalog.name) or entry.name or ("Housing object " .. tostring(entry.recordID)),
                quantity = math.max(1, tonumber(entry.total) or 1),
                iconFileDataId = catalog and type(catalog.iconTexture) == "number" and catalog.iconTexture or nil,
                sourceText = catalog and catalog.sourceText ~= "" and catalog.sourceText or nil,
                placementCost = catalog and catalog.placementCost or nil,
            }
        end
    end

    local budgetInfo = contentInfo.budgetInfo or {}
    return {
        v = 1,
        kind = "housing_blueprint",
        code = contentInfo.shareCode,
        blueprintType = BlueprintTypeName(C_HousingBlueprint.GetBlueprintTypeForCode(contentInfo.shareCode)),
        requirements = requirements,
        budgetInfo = {
            exterior = NormalizeBudgets(budgetInfo.exteriorBudgets),
            interior = NormalizeBudgets(budgetInfo.interiorBudgets),
        },
        t = time(),
    }
end

function Housing:ShowManifest(contentInfo)
    local manifest = self:BuildManifest(contentInfo)
    if not manifest.blueprintType then
        StyleBound:Print("Blueprint loaded, but its type was not recognized by this addon version.")
        return false
    end

    local encoded = self:EncodeManifest(manifest)
    StyleBound:GetModule("HousingDialog"):ShowManifest(manifest, encoded)
    return true
end

function Housing:RequestManifest(code, targetHouseGUID)
    code = NormalizeCode(code)
    if code == "" then
        StyleBound:Print("Usage: /sb housing <blueprint-code>")
        return
    end
    if not C_HousingBlueprint or not C_HousingBlueprint.RequestBlueprintContentsForContext then
        StyleBound:Print("Housing blueprint APIs are not available in this WoW client.")
        return
    end
    if not C_HousingBlueprint.IsShareCodeValid(code) then
        StyleBound:Print("That does not match WoW's housing blueprint code format.")
        return
    end

    self.pendingCode = code
    C_HousingBlueprint.RequestBlueprintContentsForContext(code, targetHouseGUID)
    StyleBound:Print("Reading blueprint contents from WoW...")
end

function Housing:HOUSING_BLUEPRINT_CONTENTS_RECEIVED(_, contentInfo)
    if not contentInfo or contentInfo.shareCode ~= self.pendingCode then return end
    self.pendingCode = nil
    self:ShowManifest(contentInfo)
end

function Housing:HOUSING_BLUEPRINT_CONTENTS_FAILURE(_, blueprintShareCode, result)
    if blueprintShareCode ~= self.pendingCode then return end
    self.pendingCode = nil
    StyleBound:Print("WoW could not load that blueprint code (result " .. tostring(result) .. ").")
end

function Housing:UpdateDashboardButton(details)
    local button = details and details.StyleBoundExportButton
    if not button then return end

    local blueprintInfo = details.blueprintInfo
    local contentInfo = details.ContentSummary and details.ContentSummary.blueprintContentInfo
    local hasCurrentContent = blueprintInfo
        and contentInfo
        and contentInfo.shareCode == blueprintInfo.shareCode

    button:SetShown(blueprintInfo ~= nil)
    button:SetEnabled(hasCurrentContent and true or false)
end

function Housing:AttachDashboardButton(details)
    if not details or details.StyleBoundExportButton or not details.ContentSummary then
        return
    end

    local summary = details.ContentSummary
    local button = CreateFrame("Button", nil, details, "UIPanelButtonTemplate")
    button:SetSize(180, 28)
    button:SetPoint("TOP", summary.ContentsListButton, "BOTTOM", 0, -8)
    button:SetFrameLevel(summary:GetFrameLevel() + 5)
    button:SetMotionScriptsWhileDisabled(true)
    button:SetText("Export to StyleBound")
    button:SetScript("OnClick", function()
        local blueprintInfo = details.blueprintInfo
        local contentInfo = summary.blueprintContentInfo
        if not blueprintInfo or not contentInfo or contentInfo.shareCode ~= blueprintInfo.shareCode then
            StyleBound:Print("That blueprint's item list is still loading.")
            return
        end

        PlaySound(SOUNDKIT.HOUSING_BLUEPRINTS_BUTTONS)
        self:ShowManifest(contentInfo)
    end)
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        if button:IsEnabled() then
            GameTooltip:SetText("Export to StyleBound")
            GameTooltip:AddLine("Create a copyable StyleBound manifest from this blueprint and its item list.", 1, 1, 1, true)
        else
            GameTooltip:SetText("Blueprint contents are loading")
            GameTooltip:AddLine("The export will become available when WoW finishes loading the item list.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    details.StyleBoundExportButton = button
    self:UpdateDashboardButton(details)
end

function Housing:InstallDashboardHook()
    if self.dashboardHooked then return true end
    if type(HousingDashboardBlueprintDetailsMixin) ~= "table" then return false end

    self.dashboardHooked = true
    hooksecurefunc(HousingDashboardBlueprintDetailsMixin, "OnLoad", function(details)
        self:AttachDashboardButton(details)
    end)
    hooksecurefunc(HousingDashboardBlueprintDetailsMixin, "ShowBlueprint", function(details)
        self:AttachDashboardButton(details)
        self:UpdateDashboardButton(details)
    end)
    hooksecurefunc(HousingDashboardBlueprintDetailsMixin, "OnShow", function(details)
        self:AttachDashboardButton(details)
        self:UpdateDashboardButton(details)
    end)
    hooksecurefunc(HousingDashboardBlueprintDetailsMixin, "ClearData", function(details)
        self:UpdateDashboardButton(details)
    end)

    if type(HousingBlueprintContentSummaryMixin) == "table" then
        hooksecurefunc(HousingBlueprintContentSummaryMixin, "OnBlueprintContentsReceived", function(summary)
            local details = summary:GetParent()
            if details and details.StyleBoundExportButton then
                self:UpdateDashboardButton(details)
            end
        end)
        hooksecurefunc(HousingBlueprintContentSummaryMixin, "OnContentRequestFailure", function(summary)
            local details = summary:GetParent()
            if details and details.StyleBoundExportButton then
                self:UpdateDashboardButton(details)
            end
        end)
    end

    self:TryAttachDashboardFrame()

    return true
end

function Housing:TryAttachDashboardFrame()
    local dashboard = HousingDashboardFrame
    local details = dashboard and dashboard.CollectionContent and dashboard.CollectionContent.BlueprintDetails
    if not details then return false end

    self:AttachDashboardButton(details)
    self:UpdateDashboardButton(details)
    return details.StyleBoundExportButton ~= nil
end

function Housing:StartDashboardWatcher()
    if self:TryAttachDashboardFrame() or self.dashboardWatcher then return end

    local attempts = 0
    self.dashboardWatcher = C_Timer.NewTicker(1, function(ticker)
        attempts = attempts + 1
        if self:TryAttachDashboardFrame() or attempts >= 30 then
            ticker:Cancel()
            self.dashboardWatcher = nil
        end
    end)
end

function Housing:ADDON_LOADED(_, addonName)
    if addonName == "Blizzard_HousingDashboard" and self:InstallDashboardHook() then
        self:UnregisterEvent("ADDON_LOADED")
        self:TryAttachDashboardFrame()
    end
end
