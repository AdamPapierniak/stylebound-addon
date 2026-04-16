-- OutfitLibrary.lua — CRUD on StyleBoundDB.global.outfits and folder management

local _, StyleBound = ...

local OutfitLibrary = StyleBound:NewModule("OutfitLibrary")

local function GenerateUUID()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return template:gsub("[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end)
end

local function Outfits()
    return StyleBound.db.global.outfits
end

local function Folders()
    return StyleBound.db.global.folders
end

-------------------------------------------------------------------------------
-- CRUD
-------------------------------------------------------------------------------

function OutfitLibrary:Save(outfitTable, name)
    local now = time()
    local id = GenerateUUID()

    local record = {
        id       = id,
        name     = name or "Untitled",
        source   = outfitTable.source or "manual",
        created  = now,
        modified = now,
        character = outfitTable.char or {},
        slots    = outfitTable.slots or {},
    }

    if outfitTable.hidden and #outfitTable.hidden > 0 then
        record.hidden = outfitTable.hidden
    end

    local outfits = Outfits()
    outfits[#outfits + 1] = record
    return id
end

function OutfitLibrary:Get(id)
    for _, outfit in ipairs(Outfits()) do
        if outfit.id == id then
            return outfit
        end
    end
    return nil
end

function OutfitLibrary:Delete(id)
    local outfits = Outfits()
    for i, outfit in ipairs(outfits) do
        if outfit.id == id then
            table.remove(outfits, i)
            return true
        end
    end
    return false
end

function OutfitLibrary:Rename(id, newName)
    local outfit = self:Get(id)
    if not outfit then return false end
    outfit.name = newName
    outfit.modified = time()
    return true
end

function OutfitLibrary:SetFolder(id, folderName)
    local outfit = self:Get(id)
    if not outfit then return false end
    outfit.folder = folderName
    outfit.modified = time()
    return true
end

function OutfitLibrary:List(folder)
    local results = {}
    for _, outfit in ipairs(Outfits()) do
        if folder == nil or outfit.folder == folder then
            results[#results + 1] = outfit
        end
    end
    return results
end

-------------------------------------------------------------------------------
-- Folders
-------------------------------------------------------------------------------

function OutfitLibrary:CreateFolder(name)
    local folders = Folders()
    for _, existing in ipairs(folders) do
        if existing == name then
            return false
        end
    end
    folders[#folders + 1] = name
    return true
end

function OutfitLibrary:DeleteFolder(name)
    local folders = Folders()
    for i, existing in ipairs(folders) do
        if existing == name then
            table.remove(folders, i)
            -- Unfile any outfits in this folder
            for _, outfit in ipairs(Outfits()) do
                if outfit.folder == name then
                    outfit.folder = nil
                end
            end
            return true
        end
    end
    return false
end

-------------------------------------------------------------------------------
-- Search
-------------------------------------------------------------------------------

function OutfitLibrary:Search(query)
    local results = {}
    local q = query:lower()
    for _, outfit in ipairs(Outfits()) do
        local match = false
        if outfit.name and outfit.name:lower():find(q, 1, true) then
            match = true
        end
        if not match and outfit.tags then
            for _, tag in ipairs(outfit.tags) do
                if tag:lower():find(q, 1, true) then
                    match = true
                    break
                end
            end
        end
        if match then
            results[#results + 1] = outfit
        end
    end
    return results
end
