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

function Housing:RequestManifest(code)
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
    C_HousingBlueprint.RequestBlueprintContentsForContext(code)
    StyleBound:Print("Reading blueprint contents from WoW...")
end

function Housing:HOUSING_BLUEPRINT_CONTENTS_RECEIVED(_, contentInfo)
    if not contentInfo or contentInfo.shareCode ~= self.pendingCode then return end
    self.pendingCode = nil

    local manifest = self:BuildManifest(contentInfo)
    if not manifest.blueprintType then
        StyleBound:Print("Blueprint loaded, but its type was not recognized by this addon version.")
        return
    end
    local encoded = self:EncodeManifest(manifest)
    StyleBound:GetModule("HousingDialog"):ShowManifest(manifest, encoded)
end

function Housing:HOUSING_BLUEPRINT_CONTENTS_FAILURE(_, blueprintShareCode, result)
    if blueprintShareCode ~= self.pendingCode then return end
    self.pendingCode = nil
    StyleBound:Print("WoW could not load that blueprint code (result " .. tostring(result) .. ").")
end
