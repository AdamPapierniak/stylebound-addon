-- DB.lua — AceDB-3.0 schema defaults and migration logic
-- This is the only file that writes defaults to StyleBoundDB.

local _, StyleBound = ...

local CURRENT_VERSION = 1

StyleBound.dbDefaults = {
    global = {
        version = CURRENT_VERSION,
        outfits = {},       -- array of outfit records
        wishlist = {
            items = {},     -- keyed by appearanceID (as string), value = { added, source }
            syncedAt = 0,
            syncSource = "",
        },
        folders = {},       -- array of folder name strings
        framePositions = {
            mainPanel      = {},
            importDialog   = {},
            savePrompt     = {},
            outfitBrowser  = {},
            shareDialog    = {},
        },
        settings = {
            dataCollectionEnabled       = false,
            dataCollectionVendors       = true,
            dataCollectionQuests        = true,
            dataCollectionTradingPost   = true,
            dataCollectionAchievements  = true,
            screenshotCameraPreset      = "front",
            screenshotHideNameplates    = true,
            screenshotHideChat          = true,
            showMinimapButton           = true,
            chatNotifications           = true,
            tooltipIntegration          = true,
            instanceLootAlerts          = true,
            debugMode                   = false,
        },
    },
    char = {
        collectedData = {
            vendors       = {},
            quests        = {},
            tradingPost   = {},
            achievements  = {},
            lastFlush     = 0,
        },
        debugLog       = {},   -- ring buffer, max 100
        outfitHistory  = {},   -- ring buffer, max 50
    },
}

function StyleBound:InitDB()
    self.db = LibStub("AceDB-3.0"):New("StyleBoundDB", self.dbDefaults, true)
    self.charDB = LibStub("AceDB-3.0"):New("StyleBoundCharDB", {
        profile = {
            collectedData = {
                vendors       = {},
                quests        = {},
                tradingPost   = {},
                achievements  = {},
                lastFlush     = 0,
            },
            debugLog       = {},
            outfitHistory  = {},
        },
    }, true)
    self:CheckMigrations()
end

function StyleBound:CheckMigrations()
    local version = self.db.global.version or 0
    if version < CURRENT_VERSION then
        -- Future migrations go here in version order
        self.db.global.version = CURRENT_VERSION
    end
end
