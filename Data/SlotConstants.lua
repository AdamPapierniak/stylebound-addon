-- SlotConstants.lua — Transmog slot string constants
-- These keys are the contract between the addon and the website.
-- Changing them breaks every existing export string.

local _, StyleBound = ...
StyleBound = StyleBound or {}

StyleBound.SLOTS = {
    "HEAD",
    "SHOULDER",
    "BACK",
    "CHEST",
    "SHIRT",
    "TABARD",
    "WRIST",
    "HANDS",
    "WAIST",
    "LEGS",
    "FEET",
    "MAINHAND",
    "OFFHAND",
}

-- Mapping from slot key to Blizzard inventory slot ID
StyleBound.SLOT_TO_INVSLOT = {
    HEAD      = 1,
    SHOULDER  = 3,
    BACK      = 15,
    CHEST     = 5,
    SHIRT     = 4,
    TABARD    = 19,
    WRIST     = 9,
    HANDS     = 10,
    WAIST     = 6,
    LEGS      = 7,
    FEET      = 8,
    MAINHAND  = 16,
    OFFHAND   = 17,
}

-- Reverse mapping from inventory slot ID to slot key
StyleBound.INVSLOT_TO_SLOT = {}
for key, id in pairs(StyleBound.SLOT_TO_INVSLOT) do
    StyleBound.INVSLOT_TO_SLOT[id] = key
end

-- Mapping from inventory slot ID to ItemTransmogInfoList index
-- Used by NewCustomSet(name, icon, list). List index = inventory slot ID.
-- Verified via /sb probe8: all 13 slots MATCH on round-trip.
-- Note: paired weapons (same appearance on MH+OH) need special handling —
-- the OH appearance goes into MH's secondaryAppearanceID instead.
StyleBound.SLOT_LIST_INDEX = {
    [1]  = 1,   -- HEAD
    [3]  = 3,   -- SHOULDER
    [15] = 15,  -- BACK
    [5]  = 5,   -- CHEST
    [4]  = 4,   -- SHIRT
    [19] = 19,  -- TABARD
    [9]  = 9,   -- WRIST
    [10] = 10,  -- HANDS
    [6]  = 6,   -- WAIST
    [7]  = 7,   -- LEGS
    [8]  = 8,   -- FEET
    [16] = 16,  -- MAINHAND
    [17] = 17,  -- OFFHAND
}
