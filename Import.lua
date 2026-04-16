-- Import.lua — Decode, validate, and resolve imported outfit strings
-- Reverse of the Export pipeline. No feature code beyond decode/validate/resolve.

local _, StyleBound = ...

local Import = StyleBound:NewModule("Import")

-- Valid slot keys (built as a set for O(1) lookup)
local VALID_SLOTS = {}
for _, key in ipairs(StyleBound.SLOTS) do
    VALID_SLOTS[key] = true
end

local WEAPON_SLOTS = { MAINHAND = true, OFFHAND = true }

-------------------------------------------------------------------------------
-- Decode
-------------------------------------------------------------------------------

function Import:DecodeString(encoded)
    if type(encoded) ~= "string" or encoded == "" then
        return nil, "Invalid or corrupted StyleBound outfit string."
    end

    local LibDeflate = LibStub("LibDeflate")
    local SBJSON = LibStub("SBJSON")

    -- DecodeForPrint
    local ok, decoded = xpcall(function()
        return LibDeflate:DecodeForPrint(encoded)
    end, function(err) return err end)

    if not ok or not decoded then
        return nil, "Invalid or corrupted StyleBound outfit string."
    end

    -- DecompressDeflate
    local ok2, decompressed = xpcall(function()
        return LibDeflate:DecompressDeflate(decoded)
    end, function(err) return err end)

    if not ok2 or not decompressed then
        return nil, "Invalid or corrupted StyleBound outfit string."
    end

    -- JSON decode
    local ok3, result = xpcall(function()
        return SBJSON.Decode(decompressed)
    end, function(err) return err end)

    if not ok3 or type(result) ~= "table" then
        return nil, "Invalid or corrupted StyleBound outfit string."
    end

    return result
end

-------------------------------------------------------------------------------
-- Validate
-------------------------------------------------------------------------------

function Import:ValidateSchema(outfit)
    if type(outfit) ~= "table" then
        return false, "Import data is not a valid outfit."
    end

    -- Version check
    if outfit.v == nil then
        return false, "Missing version field. This may not be a StyleBound outfit string."
    end
    if type(outfit.v) ~= "number" or outfit.v ~= math.floor(outfit.v) then
        return false, "Invalid version field."
    end
    if outfit.v > 1 then
        return false, "This outfit was exported with a newer version of StyleBound. Please update the addon."
    end
    if outfit.v < 1 then
        return false, "Unrecognized outfit format version."
    end

    -- Kind check
    if outfit.kind ~= "outfit" then
        return false, "This string is not an outfit export."
    end

    -- Timestamp
    if outfit.t == nil or type(outfit.t) ~= "number" then
        return false, "Missing or invalid timestamp."
    end

    -- Slots
    if type(outfit.slots) ~= "table" then
        return false, "Missing or invalid slot data."
    end

    for slotKey, slotData in pairs(outfit.slots) do
        if not VALID_SLOTS[slotKey] then
            return false, "Unknown slot: " .. tostring(slotKey)
        end

        if type(slotData) ~= "table" then
            return false, "Invalid data for slot " .. slotKey .. "."
        end

        -- appearanceID is required
        if type(slotData.a) ~= "number" or slotData.a <= 0 or slotData.a ~= math.floor(slotData.a) then
            return false, "Invalid or missing appearance ID for slot " .. slotKey .. "."
        end

        -- sourceID is optional but must be valid if present
        if slotData.s ~= nil then
            if type(slotData.s) ~= "number" or slotData.s <= 0 or slotData.s ~= math.floor(slotData.s) then
                return false, "Invalid source ID for slot " .. slotKey .. "."
            end
        end

        -- itemID is optional but must be valid if present
        if slotData.i ~= nil then
            if type(slotData.i) ~= "number" or slotData.i <= 0 or slotData.i ~= math.floor(slotData.i) then
                return false, "Invalid item ID for slot " .. slotKey .. "."
            end
        end

        -- illusionID only allowed on weapon slots
        if slotData.il ~= nil then
            if not WEAPON_SLOTS[slotKey] then
                return false, "Illusion found on non-weapon slot " .. slotKey .. ". Invalid outfit data."
            end
            if type(slotData.il) ~= "number" or slotData.il <= 0 or slotData.il ~= math.floor(slotData.il) then
                return false, "Invalid illusion ID for slot " .. slotKey .. "."
            end
        end

        -- secondaryAppearanceID only allowed on weapon slots
        if slotData.sa ~= nil then
            if not WEAPON_SLOTS[slotKey] then
                return false, "Secondary appearance found on non-weapon slot " .. slotKey .. ". Invalid outfit data."
            end
            if type(slotData.sa) ~= "number" or slotData.sa <= 0 or slotData.sa ~= math.floor(slotData.sa) then
                return false, "Invalid secondary appearance ID for slot " .. slotKey .. "."
            end
        end
    end

    -- Hidden slots (optional)
    if outfit.hidden ~= nil then
        if type(outfit.hidden) ~= "table" then
            return false, "Invalid hidden slots data."
        end
        for _, key in ipairs(outfit.hidden) do
            if not VALID_SLOTS[key] then
                return false, "Unknown slot in hidden list: " .. tostring(key)
            end
        end
    end

    return true
end

-------------------------------------------------------------------------------
-- Resolve Collection
-------------------------------------------------------------------------------

function Import:ResolveCollection(outfit)
    local collected = {}

    for slotKey, slotData in pairs(outfit.slots) do
        if slotData.s and slotData.s > 0 then
            collected[slotKey] = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(slotData.s)
        else
            -- No sourceID — can't check collection status
            collected[slotKey] = nil
        end
    end

    return collected
end

-------------------------------------------------------------------------------
-- Debug
-------------------------------------------------------------------------------

function Import:Debug(encoded)
    -- Step 1: Decode
    StyleBound:Print("--- Import Debug ---")

    local outfit, decodeErr = self:DecodeString(encoded)
    if not outfit then
        StyleBound:Print("|cFFFF0000Decode FAILED:|r " .. decodeErr)
        return
    end
    StyleBound:Print("|cFF00FF00Decode:|r OK")

    -- Step 2: Validate
    local valid, validateErr = self:ValidateSchema(outfit)
    if not valid then
        StyleBound:Print("|cFFFF0000Validate FAILED:|r " .. validateErr)
        return
    end
    StyleBound:Print("|cFF00FF00Validate:|r OK (v" .. outfit.v .. ", " .. outfit.kind .. ")")

    -- Step 3: Character info
    if outfit.char then
        local c = outfit.char
        StyleBound:Print("Character: " .. tostring(c.name) .. "-" .. tostring(c.realm)
            .. " (" .. tostring(c.race) .. " " .. tostring(c.class) .. ")")
    end

    -- Step 4: Slot summary
    local slotCount = 0
    for _ in pairs(outfit.slots) do
        slotCount = slotCount + 1
    end
    StyleBound:Print("Slots: " .. slotCount .. " populated")

    -- Step 5: Collection check
    local collected = self:ResolveCollection(outfit)
    local ownedCount = 0
    local missingCount = 0
    local unknownCount = 0
    for slotKey, status in pairs(collected) do
        if status == true then
            ownedCount = ownedCount + 1
        elseif status == false then
            missingCount = missingCount + 1
            StyleBound:Print("  |cFFFF6600Missing:|r " .. slotKey .. " (sourceID " .. outfit.slots[slotKey].s .. ")")
        else
            unknownCount = unknownCount + 1
        end
    end
    StyleBound:Print("Collection: " .. ownedCount .. " owned, " .. missingCount .. " missing, " .. unknownCount .. " unknown")

    -- Hidden slots
    if outfit.hidden and #outfit.hidden > 0 then
        StyleBound:Print("Hidden: " .. table.concat(outfit.hidden, ", "))
    end
end
