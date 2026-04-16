-- Export.lua — Read transmog slots, build outfit table for serialization
-- Uses a hidden DressUpModel + GetItemTransmogInfo to read the actual
-- transmog appearances (not the equipped items).

local _, StyleBound = ...

local Export = StyleBound:NewModule("Export")

-- Reusable hidden model frame for reading transmog data
local transmogModel = nil

local function GetTransmogModel()
    if not transmogModel then
        transmogModel = CreateFrame("DressUpModel", nil, UIParent)
        transmogModel:SetSize(1, 1)
        transmogModel:SetPoint("TOPLEFT", -100, -100)
        -- Do NOT hide — hidden models don't load unit data
    end
    transmogModel:SetUnit("player")
    return transmogModel
end

local function SlugifyRealm(realm)
    return realm:lower():gsub("%s+", "-")
end

local function BuildCharacterBlock()
    local name = UnitName("player")
    local realm = GetRealmName()
    local raceName, _, raceId = UnitRace("player")
    local className, _, classId = UnitClass("player")
    local gender = UnitSex("player")
    local level = UnitLevel("player")

    local spec = nil
    local specIndex = GetSpecialization()
    if specIndex then
        spec = select(2, GetSpecializationInfo(specIndex))
    end

    return {
        name    = name,
        realm   = SlugifyRealm(realm),
        race    = raceName,
        raceId  = raceId,
        class   = className,
        classId = classId,
        gender  = gender,
        spec    = spec,
        level   = level,
    }
end

-------------------------------------------------------------------------------
-- Build outfit from DressUpModel (reads actual transmog appearances)
-------------------------------------------------------------------------------

function Export:BuildCurrentOutfit()
    local model = GetTransmogModel()
    local slots = {}
    local hidden = {}

    for i = 1, #TransmogSlotOrder do
        local slotID = TransmogSlotOrder[i]
        local slotKey = StyleBound.INVSLOT_TO_SLOT[slotID]
        if slotKey then
            local ok, tmogInfo = pcall(model.GetItemTransmogInfo, model, slotID)
            if ok and tmogInfo and tmogInfo.appearanceID and tmogInfo.appearanceID > 0 then
                -- GetItemTransmogInfo returns sourceIDs in the appearanceID field
                local source = C_TransmogCollection.GetSourceInfo(tmogInfo.appearanceID)
                if source then
                    if source.isHideVisual then
                        hidden[#hidden + 1] = slotKey
                    else
                        slots[slotKey] = {
                            s = source.sourceID,
                            a = source.visualID,
                            i = source.itemID,
                        }
                        -- Illusion (weapon slots only)
                        if (slotID == 16 or slotID == 17)
                            and tmogInfo.illusionID and tmogInfo.illusionID > 0 then
                            slots[slotKey].il = tmogInfo.illusionID
                        end
                        -- Secondary appearance (paired weapons)
                        if (slotID == 16 or slotID == 17)
                            and tmogInfo.secondaryAppearanceID
                            and tmogInfo.secondaryAppearanceID > 0 then
                            local secSource = C_TransmogCollection.GetSourceInfo(
                                tmogInfo.secondaryAppearanceID)
                            if secSource then
                                slots[slotKey].sa = secSource.visualID
                            end
                        end
                    end
                end
            end
        end
    end

    local outfit = {
        v     = 1,
        kind  = "outfit",
        char  = BuildCharacterBlock(),
        slots = slots,
        t     = time(),
    }

    if #hidden > 0 then
        outfit.hidden = hidden
    end

    return outfit
end

-------------------------------------------------------------------------------
-- Encode / export string
-------------------------------------------------------------------------------

function Export:EncodeOutfit(outfit)
    local SBJSON = LibStub("SBJSON")
    local LibDeflate = LibStub("LibDeflate")

    local json = SBJSON.Encode(outfit)
    local compressed = LibDeflate:CompressDeflate(json)
    local encoded = LibDeflate:EncodeForPrint(compressed)

    return encoded
end

function Export:GetExportString()
    local outfit = self:BuildCurrentOutfit()
    local encoded = self:EncodeOutfit(outfit)
    return encoded, outfit
end

-------------------------------------------------------------------------------
-- Debug / test helpers
-------------------------------------------------------------------------------

local function PrettyPrint(val, indent)
    indent = indent or ""
    local t = type(val)
    if t == "table" then
        local parts = {}
        for k, v in pairs(val) do
            local key
            if type(k) == "number" then
                key = "[" .. k .. "]"
            else
                key = tostring(k)
            end
            parts[#parts + 1] = indent .. "  " .. key .. " = " .. PrettyPrint(v, indent .. "  ")
        end
        if #parts == 0 then
            return "{}"
        end
        return "{\n" .. table.concat(parts, "\n") .. "\n" .. indent .. "}"
    elseif t == "string" then
        return '"' .. val .. '"'
    else
        return tostring(val)
    end
end

function Export:Debug()
    local outfit = self:BuildCurrentOutfit()
    local lines = PrettyPrint(outfit)
    for line in lines:gmatch("[^\n]+") do
        StyleBound:Print(line)
    end

    local encoded = self:GetExportString()
    StyleBound:Print("--- Export String ---")
    StyleBound:Print(encoded)
    StyleBound:Print("Length: " .. #encoded .. " chars (target: <300)")
end

local function DeepEqual(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not DeepEqual(v, b[k]) then return false, k end
    end
    for k in pairs(b) do
        if a[k] == nil then return false, k end
    end
    return true
end

function Export:SelfTest()
    local Import = StyleBound:GetModule("Import")

    local encoded, originalOutfit = self:GetExportString()
    StyleBound:Print("--- Self Test ---")
    StyleBound:Print("Encoded: " .. #encoded .. " chars")

    local decoded, decodeErr = Import:DecodeString(encoded)
    if not decoded then
        StyleBound:Print("|cFFFF0000FAIL:|r Decode: " .. decodeErr)
        return
    end
    StyleBound:Print("|cFF00FF00Decode:|r OK")

    local valid, validateErr = Import:ValidateSchema(decoded)
    if not valid then
        StyleBound:Print("|cFFFF0000FAIL:|r Validate: " .. validateErr)
        return
    end
    StyleBound:Print("|cFF00FF00Validate:|r OK")

    local collected = Import:ResolveCollection(decoded)
    local owned, missing = 0, 0
    for _, status in pairs(collected) do
        if status then owned = owned + 1 else missing = missing + 1 end
    end
    StyleBound:Print("|cFF00FF00Collection:|r " .. owned .. " owned, " .. missing .. " missing")

    local equal, failKey = DeepEqual(originalOutfit, decoded)
    if equal then
        StyleBound:Print("|cFF00FF00PASS:|r Full round-trip OK.")
    else
        StyleBound:Print("|cFFFF0000FAIL:|r Mismatch at key: " .. tostring(failKey))
    end
end
