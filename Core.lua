-- Core.lua — AceAddon init, slash commands, global event bus
-- This file only orchestrates. It does not implement any feature logic.

local ADDON_NAME, StyleBound = ...

StyleBound = LibStub("AceAddon-3.0"):NewAddon(StyleBound, ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0")

function StyleBound:OnInitialize()
    self:InitDB()
    self:RegisterChatCommand("stylebound", "SlashCommand")
    self:RegisterChatCommand("sb", "SlashCommand")
    self:CreateMinimapButton()
end

function StyleBound:OnEnable()
    self:Print("StyleBound v0.1.0 loaded.")
end

-------------------------------------------------------------------------------
-- Minimap Button (LibDBIcon + LibDataBroker)
-------------------------------------------------------------------------------

function StyleBound:CreateMinimapButton()
    local LDB = LibStub("LibDataBroker-1.1")
    local LDBIcon = LibStub("LibDBIcon-1.0")

    local launcher = LDB:NewDataObject("StyleBound", {
        type  = "launcher",
        icon  = "Interface\\AddOns\\StyleBound\\icon.tga",
        label = "StyleBound",
        OnClick = function(_, button)
            if button == "RightButton" then
                StyleBound:Print("Settings panel coming soon.")
            else
                StyleBound:GetModule("MainPanel"):Toggle()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("StyleBound")
            tooltip:AddLine("|cFFFFFFFFLeft-click:|r Toggle panel", 0.8, 0.8, 0.8)
            tooltip:AddLine("|cFFFFFFFFRight-click:|r Settings", 0.8, 0.8, 0.8)
        end,
    })

    -- Use the minimap table from SavedVariables for position persistence
    if not self.db.global.minimap then
        self.db.global.minimap = {}
    end

    LDBIcon:Register("StyleBound", launcher, self.db.global.minimap)

    if self.db.global.settings.showMinimapButton == false then
        LDBIcon:Hide("StyleBound")
    end
end

function StyleBound:FindOutfitByPrefix(prefix)
    for _, outfit in ipairs(self.db.global.outfits) do
        if outfit.id:sub(1, #prefix) == prefix then
            return outfit
        end
    end
    return nil
end

function StyleBound:SlashCommand(input)
    local cmd = self:GetArgs(input)
    if not cmd or cmd == "" then
        self:GetModule("MainPanel"):Toggle()
        return
    elseif cmd == "help" then
        self:Print("Commands: /sb help | /sb dbcheck | /sb export | /sb selftest")
        self:Print("  /sb save <name> | /sb list | /sb get <id> | /sb delete <id>")
        self:Print("  /sb rename <id> <name> | /sb folder <id> <folder>")
        self:Print("  /sb folders | /sb mkfolder <name> | /sb rmfolder <name>")
        self:Print("  /sb search <query> | /sb screenshot | /sb autoshoot | /sb selfie")
        self:Print("  /sb copy — copy targeted player's transmog (use in a macro)")
    elseif cmd == "export" then
        self:GetModule("Export"):Debug()
    elseif cmd == "selftest" then
        self:GetModule("Export"):SelfTest()
    elseif cmd == "import" then
        local _, rest = self:GetArgs(input, 1)
        if not rest or rest == "" then
            self:Print("Usage: /sb import <encoded string>")
        else
            self:GetModule("Import"):Debug(rest)
        end
    elseif cmd == "save" then
        local _, name = self:GetArgs(input, 1)
        if not name or name == "" then name = "Untitled" end
        local Export = self:GetModule("Export")
        local outfit = Export:BuildCurrentOutfit()
        outfit.source = "export"
        local id = self:GetModule("OutfitLibrary"):Save(outfit, name)
        self:Print("Saved as '" .. name .. "' (id: " .. id .. ")")
    elseif cmd == "list" then
        local lib = self:GetModule("OutfitLibrary")
        local outfits = lib:List()
        if #outfits == 0 then
            self:Print("No saved outfits.")
        else
            for _, o in ipairs(outfits) do
                local folder = o.folder and (" [" .. o.folder .. "]") or ""
                self:Print("  " .. o.id:sub(1, 8) .. "  " .. o.name .. folder)
            end
            self:Print(#outfits .. " outfit(s) total.")
        end
    elseif cmd == "get" then
        local _, id = self:GetArgs(input, 1)
        if not id or id == "" then self:Print("Usage: /sb get <id-prefix>"); return end
        local outfit = self:FindOutfitByPrefix(id)
        if not outfit then self:Print("No outfit matching '" .. id .. "'"); return end
        self:Print(outfit.name .. " (" .. outfit.id .. ")")
        self:Print("  source: " .. tostring(outfit.source) .. "  folder: " .. tostring(outfit.folder))
        self:Print("  created: " .. date("%Y-%m-%d %H:%M", outfit.created))
        local slotCount = 0
        for _ in pairs(outfit.slots) do slotCount = slotCount + 1 end
        self:Print("  slots: " .. slotCount)
    elseif cmd == "delete" then
        local _, id = self:GetArgs(input, 1)
        if not id or id == "" then self:Print("Usage: /sb delete <id-prefix>"); return end
        local outfit = self:FindOutfitByPrefix(id)
        if not outfit then self:Print("No outfit matching '" .. id .. "'"); return end
        local name = outfit.name
        if self:GetModule("OutfitLibrary"):Delete(outfit.id) then
            self:Print("Deleted '" .. name .. "'")
        end
    elseif cmd == "rename" then
        local _, id, newName = self:GetArgs(input, 2)
        if not id or not newName or newName == "" then self:Print("Usage: /sb rename <id-prefix> <new name>"); return end
        local outfit = self:FindOutfitByPrefix(id)
        if not outfit then self:Print("No outfit matching '" .. id .. "'"); return end
        local old = outfit.name
        self:GetModule("OutfitLibrary"):Rename(outfit.id, newName)
        self:Print("Renamed '" .. old .. "' → '" .. newName .. "'")
    elseif cmd == "folder" then
        local _, id, folderName = self:GetArgs(input, 2)
        if not id or not folderName then self:Print("Usage: /sb folder <id-prefix> <folder>"); return end
        local outfit = self:FindOutfitByPrefix(id)
        if not outfit then self:Print("No outfit matching '" .. id .. "'"); return end
        self:GetModule("OutfitLibrary"):SetFolder(outfit.id, folderName)
        self:Print("Moved '" .. outfit.name .. "' to folder '" .. folderName .. "'")
    elseif cmd == "folders" then
        local folders = self.db.global.folders
        if #folders == 0 then
            self:Print("No folders.")
        else
            for _, f in ipairs(folders) do
                self:Print("  " .. f)
            end
        end
    elseif cmd == "mkfolder" then
        local _, name = self:GetArgs(input, 1)
        if not name or name == "" then self:Print("Usage: /sb mkfolder <name>"); return end
        if self:GetModule("OutfitLibrary"):CreateFolder(name) then
            self:Print("Created folder '" .. name .. "'")
        else
            self:Print("Folder '" .. name .. "' already exists.")
        end
    elseif cmd == "rmfolder" then
        local _, name = self:GetArgs(input, 1)
        if not name or name == "" then self:Print("Usage: /sb rmfolder <name>"); return end
        if self:GetModule("OutfitLibrary"):DeleteFolder(name) then
            self:Print("Deleted folder '" .. name .. "'")
        else
            self:Print("Folder '" .. name .. "' not found.")
        end
    elseif cmd == "search" then
        local _, query = self:GetArgs(input, 1)
        if not query or query == "" then self:Print("Usage: /sb search <query>"); return end
        local results = self:GetModule("OutfitLibrary"):Search(query)
        if #results == 0 then
            self:Print("No outfits matching '" .. query .. "'")
        else
            for _, o in ipairs(results) do
                self:Print("  " .. o.id:sub(1, 8) .. "  " .. o.name)
            end
        end
    elseif cmd == "outfits" or cmd == "browse" then
        self:GetModule("OutfitBrowser"):Toggle()
    elseif cmd == "screenshot" or cmd == "ss" then
        self:GetModule("Screenshot"):StartSession()
    elseif cmd == "autoshoot" or cmd == "auto" then
        self:GetModule("Screenshot"):StartAutoShoot()
    elseif cmd == "selfie" then
        StyleBound:Print("Use the S.E.L.F.I.E. Camera toy to start a selfie session.")
        StyleBound:Print("The addon will detect the buff automatically.")
    elseif cmd == "copy" then
        -- Copy the targeted player's transmog outfit via inspect
        if not UnitExists("target") then
            self:Print("No target selected. Target a player and try again.")
            return
        end
        if not UnitIsPlayer("target") then
            self:Print("Target is not a player.")
            return
        end
        if not CheckInteractDistance("target", 1) then
            self:Print("Target is too far away to inspect.")
            return
        end

        self:Print("Inspecting " .. (UnitName("target") or "target") .. "...")
        NotifyInspect("target")

        -- Wait for inspect data, then build outfit and open import preview
        local attempts = 0
        local ticker
        ticker = C_Timer.NewTicker(0.5, function()
            attempts = attempts + 1
            local list = C_TransmogCollection.GetInspectItemTransmogInfoList("target")
            if list and #list > 0 then
                ticker:Cancel()

                -- Build outfit table from inspect data
                local slots = {}
                local hidden = {}
                for i, info in ipairs(list) do
                    local slotKey = StyleBound.INVSLOT_TO_SLOT[i]
                    if slotKey and info.appearanceID and info.appearanceID > 0 then
                        local source = C_TransmogCollection.GetSourceInfo(info.appearanceID)
                        if source then
                            if source.isHideVisual then
                                hidden[#hidden + 1] = slotKey
                            else
                                slots[slotKey] = {
                                    s = source.sourceID,
                                    a = source.visualID,
                                    i = source.itemID,
                                }
                                if (i == 16 or i == 17) and info.illusionID and info.illusionID > 0 then
                                    slots[slotKey].il = info.illusionID
                                end
                                if (i == 16 or i == 17) and info.secondaryAppearanceID and info.secondaryAppearanceID > 0 then
                                    local secSource = C_TransmogCollection.GetSourceInfo(info.secondaryAppearanceID)
                                    if secSource then
                                        slots[slotKey].sa = secSource.visualID
                                    end
                                end
                            end
                        end
                    end
                end

                -- Build character block from target unit
                local tName, tRealm = UnitName("target")
                if not tRealm or tRealm == "" then tRealm = GetRealmName() end
                local raceName, _, raceId = UnitRace("target")
                local className, _, classId = UnitClass("target")
                local gender = UnitSex("target")
                local level = UnitLevel("target")

                local outfit = {
                    v     = 1,
                    kind  = "outfit",
                    char  = {
                        name    = tName,
                        realm   = tRealm:lower():gsub("%s+", "-"),
                        race    = raceName,
                        raceId  = raceId,
                        class   = className,
                        classId = classId,
                        gender  = gender,
                        level   = level,
                    },
                    slots = slots,
                    t     = time(),
                }
                if #hidden > 0 then
                    outfit.hidden = hidden
                end

                ClearInspectPlayer()

                -- Resolve collection and open import preview
                local Import = StyleBound:GetModule("Import")
                local collected = Import:ResolveCollection(outfit)
                local ImportDialog = StyleBound:GetModule("ImportDialog")
                ImportDialog:ShowResult(outfit, collected)

                local slotCount = 0
                for _ in pairs(slots) do slotCount = slotCount + 1 end
                StyleBound:Print("Copied " .. slotCount .. " slots from " .. tName .. ".")
            elseif attempts >= 10 then
                ticker:Cancel()
                ClearInspectPlayer()
                StyleBound:Print("Could not inspect target. Make sure they are nearby and visible.")
            end
        end)

    elseif cmd == "probe" then
        -- Dump GetSlotVisualInfo fields for every transmog slot so we can see
        -- which field holds the transmog visual vs the equipped item.
        self:Print("--- Slot Visual Probe ---")
        for i = 1, #TransmogSlotOrder do
            local slotID = TransmogSlotOrder[i]
            local slotKey = StyleBound.INVSLOT_TO_SLOT[slotID] or tostring(slotID)
            local loc = TransmogUtil.CreateTransmogLocation(
                slotID, Enum.TransmogType.Appearance, Enum.TransmogModification.Main)
            local v = C_Transmog.GetSlotVisualInfo(loc)
            if v then
                -- Resolve item names for base and applied sources
                local baseName = "?"
                local appliedName = "?"
                if v.baseSourceID and v.baseSourceID > 0 then
                    local info = C_TransmogCollection.GetSourceInfo(v.baseSourceID)
                    if info then baseName = tostring(info.name) .. " (item " .. tostring(info.itemID) .. ")" end
                end
                if v.appliedSourceID and v.appliedSourceID > 0 then
                    local info = C_TransmogCollection.GetSourceInfo(v.appliedSourceID)
                    if info then appliedName = tostring(info.name) .. " (item " .. tostring(info.itemID) .. ")" end
                end
                self:Print("|cFFFFD100" .. slotKey .. "|r (slot " .. slotID .. "):")
                self:Print("  baseSourceID=" .. tostring(v.baseSourceID) .. "  baseVisualID=" .. tostring(v.baseVisualID))
                self:Print("  appliedSourceID=" .. tostring(v.appliedSourceID) .. "  appliedVisualID=" .. tostring(v.appliedVisualID))
                self:Print("  pendingSourceID=" .. tostring(v.pendingSourceID) .. "  pendingVisualID=" .. tostring(v.pendingVisualID))
                self:Print("  isHideVisual=" .. tostring(v.isHideVisual) .. "  hasUndo=" .. tostring(v.hasUndo))
                self:Print("  base → " .. baseName)
                self:Print("  applied → " .. appliedName)
                -- Dump any fields we might not know about
                local known = {baseSourceID=1, baseVisualID=1, appliedSourceID=1, appliedVisualID=1,
                    pendingSourceID=1, pendingVisualID=1, isHideVisual=1, hasUndo=1, itemSubclass=1}
                for k2, v2 in pairs(v) do
                    if not known[k2] then
                        self:Print("  |cFF00FF00EXTRA:|r " .. tostring(k2) .. "=" .. tostring(v2))
                    end
                end
            else
                self:Print("|cFFFFD100" .. slotKey .. "|r: nil")
            end
        end
    elseif cmd == "probe2" then
        -- Deep probe on SHOULDER (slot 3) to find where the transmog visual lives
        local slotID = 3
        self:Print("--- Deep Probe: SHOULDER (slot 3) ---")

        -- 1. C_Item.GetAppliedItemTransmogInfo
        self:Print("|cFFFFD100[1] C_Item.GetAppliedItemTransmogInfo:|r")
        local itemLoc = ItemLocation:CreateFromEquipmentSlot(slotID)
        if C_Item.DoesItemExist(itemLoc) then
            local ok, tmogInfo = pcall(C_Item.GetAppliedItemTransmogInfo, itemLoc)
            if ok and tmogInfo then
                self:Print("  appearanceID=" .. tostring(tmogInfo.appearanceID))
                self:Print("  secondaryAppearanceID=" .. tostring(tmogInfo.secondaryAppearanceID))
                self:Print("  illusionID=" .. tostring(tmogInfo.illusionID))
                if tmogInfo.appearanceID and tmogInfo.appearanceID > 0 then
                    local sources = C_TransmogCollection.GetAppearanceSources(tmogInfo.appearanceID)
                    if sources and #sources > 0 then
                        local srcInfo = C_TransmogCollection.GetSourceInfo(sources[1].sourceID)
                        if srcInfo then
                            self:Print("  → first source name: " .. tostring(srcInfo.name))
                        end
                    end
                end
            else
                self:Print("  returned nil or error: " .. tostring(tmogInfo))
            end
        else
            self:Print("  no item in slot")
        end

        -- 2. C_TransmogCollection.GetItemInfo on equipped item
        self:Print("|cFFFFD100[2] GetItemInfo on equipped item link:|r")
        local itemLink = GetInventoryItemLink("player", slotID)
        if itemLink then
            self:Print("  itemLink=" .. itemLink)
            local ok2, appearanceID, sourceID = pcall(C_TransmogCollection.GetItemInfo, itemLink)
            if ok2 then
                self:Print("  appearanceID=" .. tostring(appearanceID) .. "  sourceID=" .. tostring(sourceID))
                if sourceID and sourceID > 0 then
                    local srcInfo = C_TransmogCollection.GetSourceInfo(sourceID)
                    if srcInfo then
                        self:Print("  → source name: " .. tostring(srcInfo.name) .. " (item " .. tostring(srcInfo.itemID) .. ")")
                    end
                end
            else
                self:Print("  error: " .. tostring(appearanceID))
            end
        end

        -- 3. GetSlotVisualInfo — dump the raw table with type() of each value
        self:Print("|cFFFFD100[3] GetSlotVisualInfo raw dump:|r")
        local loc = TransmogUtil.CreateTransmogLocation(slotID, 0, 0)
        local v = C_Transmog.GetSlotVisualInfo(loc)
        if v then
            for k, val in pairs(v) do
                self:Print("  " .. tostring(k) .. " = " .. tostring(val) .. " (" .. type(val) .. ")")
            end
        end

        -- 4. Try reading the active outfit slot info
        self:Print("|cFFFFD100[4] Outfit exploration:|r")
        -- Check if GetOutfits / outfit functions exist
        local outfitFuncs = {"GetOutfits", "GetActiveOutfitID", "GetOutfitInfo",
            "GetOutfitItemTransmogInfoList", "GetCurrentOutfitSlotAppearance"}
        for _, fname in ipairs(outfitFuncs) do
            local exists = (C_TransmogCollection[fname] ~= nil) and "YES" or "no"
            self:Print("  C_TransmogCollection." .. fname .. ": " .. exists)
        end
        for _, fname in ipairs({"GetActiveOutfit", "GetOutfitSlotInfo", "GetOutfitSlotData"}) do
            local exists = (C_Transmog[fname] ~= nil) and "YES" or "no"
            self:Print("  C_Transmog." .. fname .. ": " .. exists)
        end

        -- 5. Try GetSlotInfo (doc says removed, but let's check)
        self:Print("|cFFFFD100[5] C_Transmog.GetSlotInfo existence:|r")
        self:Print("  " .. tostring(C_Transmog.GetSlotInfo ~= nil))
        if C_Transmog.GetSlotInfo then
            local ok5, r1, r2, r3, r4 = pcall(C_Transmog.GetSlotInfo, loc)
            self:Print("  ok=" .. tostring(ok5) .. "  r1=" .. tostring(r1) .. "  r2=" .. tostring(r2)
                .. "  r3=" .. tostring(r3) .. "  r4=" .. tostring(r4))
        end

        -- 6. TransmogUtil.GetInfoForEquippedSlot
        self:Print("|cFFFFD100[6] TransmogUtil.GetInfoForEquippedSlot:|r")
        if TransmogUtil.GetInfoForEquippedSlot then
            local ok6, res = pcall(TransmogUtil.GetInfoForEquippedSlot, loc)
            if ok6 then
                if type(res) == "table" then
                    for k, val in pairs(res) do
                        self:Print("  " .. tostring(k) .. " = " .. tostring(val))
                    end
                else
                    self:Print("  result=" .. tostring(res))
                end
            else
                self:Print("  error: " .. tostring(res))
            end
        else
            self:Print("  function does not exist")
        end

    elseif cmd == "probe3" then
        local slotID = 3  -- SHOULDER
        self:Print("--- Probe 3: API Scan + Tooltip ---")

        -- 1. Enumerate ALL C_Transmog functions
        self:Print("|cFFFFD100[1] C_Transmog functions:|r")
        local tmogFuncs = {}
        for k, v in pairs(C_Transmog) do
            if type(v) == "function" then
                tmogFuncs[#tmogFuncs + 1] = k
            end
        end
        table.sort(tmogFuncs)
        self:Print("  " .. table.concat(tmogFuncs, ", "))

        -- 2. Enumerate C_TransmogCollection functions (just count + interesting ones)
        self:Print("|cFFFFD100[2] C_TransmogCollection scan:|r")
        local collFuncs = {}
        for k, v in pairs(C_TransmogCollection) do
            if type(v) == "function" then
                collFuncs[#collFuncs + 1] = k
            end
        end
        table.sort(collFuncs)
        self:Print("  Count: " .. #collFuncs)
        -- Print ones with "outfit", "slot", "visual", "active", "applied", "current" in name
        for _, fname in ipairs(collFuncs) do
            local fl = fname:lower()
            if fl:find("outfit") or fl:find("slot") or fl:find("visual") or fl:find("active")
                or fl:find("applied") or fl:find("current") or fl:find("transmog") then
                self:Print("  → " .. fname)
            end
        end

        -- 3. C_TooltipInfo.GetInventoryItem — structured tooltip data
        self:Print("|cFFFFD100[3] C_TooltipInfo.GetInventoryItem:|r")
        if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
            local ok, tipData = pcall(C_TooltipInfo.GetInventoryItem, "player", slotID)
            if ok and tipData then
                if tipData.lines then
                    for i, line in ipairs(tipData.lines) do
                        local txt = line.leftText or ""
                        local rtxt = line.rightText or ""
                        -- Show all lines but highlight transmog-related ones
                        local prefix = "  "
                        if txt:lower():find("transmog") or txt:lower():find("appearance") then
                            prefix = "  |cFF00FF00>>|r "
                        end
                        self:Print(prefix .. "L" .. i .. ": " .. txt .. (rtxt ~= "" and ("  |  " .. rtxt) or ""))
                    end
                end
                -- Check for transmog-specific fields on the data object
                for k, v in pairs(tipData) do
                    if k ~= "lines" then
                        self:Print("  field: " .. tostring(k) .. " = " .. tostring(v) .. " (" .. type(v) .. ")")
                    end
                end
            else
                self:Print("  error: " .. tostring(tipData))
            end
        else
            self:Print("  C_TooltipInfo.GetInventoryItem does not exist")
        end

        -- 4. Try GameTooltip scan as fallback
        self:Print("|cFFFFD100[4] GameTooltip scan:|r")
        local tip = CreateFrame("GameTooltip", "SBProbeTip", nil, "GameTooltipTemplate")
        tip:SetOwner(WorldFrame, "ANCHOR_NONE")
        tip:SetInventoryItem("player", slotID)
        for i = 1, tip:NumLines() do
            local left = _G["SBProbeTipTextLeft" .. i]
            local right = _G["SBProbeTipTextRight" .. i]
            local lt = left and left:GetText() or ""
            local rt = right and right:GetText() or ""
            if lt:lower():find("transmog") or lt:lower():find("appearance") then
                self:Print("  |cFF00FF00>>|r L" .. i .. ": " .. lt)
            end
        end
        tip:Hide()

        -- 5. Check TransmogUtil for anything we missed
        self:Print("|cFFFFD100[5] TransmogUtil functions:|r")
        local tuFuncs = {}
        for k, v in pairs(TransmogUtil) do
            if type(v) == "function" then
                tuFuncs[#tuFuncs + 1] = k
            end
        end
        table.sort(tuFuncs)
        self:Print("  " .. table.concat(tuFuncs, ", "))

    elseif cmd == "probe4" then
        local slotID = 3  -- SHOULDER
        self:Print("--- Probe 4: Tooltip line fields + InspectList ---")

        -- 1. Deep inspect of tooltip lines (especially L4/L5 transmog lines)
        self:Print("|cFFFFD100[1] C_TooltipInfo line deep inspect:|r")
        if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
            local ok, tipData = pcall(C_TooltipInfo.GetInventoryItem, "player", slotID)
            if ok and tipData and tipData.lines then
                for i = 4, math.min(6, #tipData.lines) do
                    local line = tipData.lines[i]
                    self:Print("  --- Line " .. i .. " ---")
                    for k, v in pairs(line) do
                        if type(v) == "table" then
                            local parts = {}
                            for k2, v2 in pairs(v) do
                                parts[#parts + 1] = tostring(k2) .. "=" .. tostring(v2)
                            end
                            self:Print("  " .. tostring(k) .. " = {" .. table.concat(parts, ", ") .. "}")
                        else
                            self:Print("  " .. tostring(k) .. " = " .. tostring(v) .. " (" .. type(v) .. ")")
                        end
                    end
                end
            end
        end

        -- 2. GetInspectItemTransmogInfoList on player
        self:Print("|cFFFFD100[2] GetInspectItemTransmogInfoList('player'):|r")
        local ok2, list = pcall(C_TransmogCollection.GetInspectItemTransmogInfoList, "player")
        if ok2 and list then
            self:Print("  length=" .. #list)
            for i, info in ipairs(list) do
                if info.appearanceID and info.appearanceID > 0 then
                    self:Print("  [" .. i .. "] app=" .. info.appearanceID
                        .. " sec=" .. tostring(info.secondaryAppearanceID)
                        .. " ill=" .. tostring(info.illusionID))
                    -- Look up a source for this appearance
                    local sources = C_TransmogCollection.GetAppearanceSources(info.appearanceID)
                    if sources and #sources > 0 then
                        local srcInfo = C_TransmogCollection.GetSourceInfo(sources[1].sourceID)
                        if srcInfo then
                            self:Print("       → " .. tostring(srcInfo.name))
                        end
                    end
                end
            end
        else
            self:Print("  error or nil: " .. tostring(list))
        end

        -- 3. Try NotifyInspect on self first then GetInspect...
        self:Print("|cFFFFD100[3] NotifyInspect + GetInspect:|r")
        local ok3 = pcall(NotifyInspect, "player")
        self:Print("  NotifyInspect ok=" .. tostring(ok3))
        if ok3 then
            C_Timer.After(0.5, function()
                local ok4, list2 = pcall(C_TransmogCollection.GetInspectItemTransmogInfoList, "player")
                if ok4 and list2 then
                    self:Print("  post-inspect length=" .. #list2)
                    for i, info in ipairs(list2) do
                        if info.appearanceID and info.appearanceID > 0 then
                            self:Print("  [" .. i .. "] app=" .. info.appearanceID)
                            local sources = C_TransmogCollection.GetAppearanceSources(info.appearanceID)
                            if sources and #sources > 0 then
                                local srcInfo = C_TransmogCollection.GetSourceInfo(sources[1].sourceID)
                                if srcInfo then
                                    self:Print("       → " .. tostring(srcInfo.name))
                                end
                            end
                        end
                    end
                else
                    self:Print("  post-inspect error: " .. tostring(list2))
                end
                ClearInspectPlayer()
            end)
        end

    elseif cmd == "probe5" then
        self:Print("--- Probe 5: Resolve inspect appearanceIDs ---")
        self:Print("Running NotifyInspect, wait...")
        NotifyInspect("player")
        C_Timer.After(0.5, function()
            local list = C_TransmogCollection.GetInspectItemTransmogInfoList("player")
            if not list or #list == 0 then
                self:Print("Inspect list empty. Try again.")
                ClearInspectPlayer()
                return
            end
            for i, info in ipairs(list) do
                if info.appearanceID and info.appearanceID > 0 then
                    local id = info.appearanceID
                    local slotKey = StyleBound.INVSLOT_TO_SLOT[i] or ("idx" .. i)
                    self:Print("|cFFFFD100[" .. i .. "] " .. slotKey .. "  appID=" .. id .. "|r")

                    -- Try as sourceID
                    local srcInfo = C_TransmogCollection.GetSourceInfo(id)
                    if srcInfo and srcInfo.name then
                        self:Print("  AsSource: " .. srcInfo.name .. " (item=" .. tostring(srcInfo.itemID)
                            .. " visualID=" .. tostring(srcInfo.visualID) .. ")")
                    else
                        self:Print("  AsSource: nil")
                    end

                    -- Try as visualID / appearanceID for GetAppearanceSources
                    local ok, sources = pcall(C_TransmogCollection.GetAppearanceSources, id)
                    if ok and sources and #sources > 0 then
                        local first = C_TransmogCollection.GetSourceInfo(sources[1].sourceID)
                        self:Print("  AsAppearance: " .. #sources .. " sources, first="
                            .. (first and first.name or "?")
                            .. " (sourceID=" .. sources[1].sourceID .. ")")
                    else
                        self:Print("  AsAppearance: no sources")
                    end

                    -- Try GetItemIDForSource
                    local ok2, itemID = pcall(C_Transmog.GetItemIDForSource, id)
                    if ok2 and itemID and itemID > 0 then
                        self:Print("  GetItemIDForSource: " .. itemID)
                    end
                end
            end
            ClearInspectPlayer()
        end)

    elseif cmd == "probe6" then
        self:Print("--- Probe 6: Blizzard UI source inspection ---")

        -- 1. Check if TransmogUtil functions are Lua or C (pcall string.dump)
        self:Print("|cFFFFD100[1] Function type check:|r")
        local funcsToCheck = {
            {"TransmogUtil.GetInfoForEquippedSlot", TransmogUtil.GetInfoForEquippedSlot},
            {"TransmogUtil.GetUseTransmogSkin", TransmogUtil.GetUseTransmogSkin},
            {"TransmogUtil.CreateTransmogLocation", TransmogUtil.CreateTransmogLocation},
            {"TransmogUtil.GetWardrobeModelSetupData", TransmogUtil.GetWardrobeModelSetupData},
        }
        for _, entry in ipairs(funcsToCheck) do
            local fname, func = entry[1], entry[2]
            if func then
                local isLua = pcall(string.dump, func)
                self:Print("  " .. fname .. ": " .. (isLua and "Lua" or "C/built-in"))
            else
                self:Print("  " .. fname .. ": does not exist")
            end
        end

        -- 2. Look at WardrobeCollectionFrame if it exists
        self:Print("|cFFFFD100[2] Wardrobe frame inspection:|r")
        local wf = _G["WardrobeCollectionFrame"]
        if wf then
            self:Print("  WardrobeCollectionFrame exists")
            local interesting = {}
            for k, v in pairs(wf) do
                local kl = tostring(k):lower()
                if type(v) == "function" and (kl:find("equip") or kl:find("transmog")
                    or kl:find("current") or kl:find("visual") or kl:find("applied")
                    or kl:find("source") or kl:find("outfit")) then
                    interesting[#interesting + 1] = tostring(k)
                end
            end
            table.sort(interesting)
            if #interesting > 0 then
                self:Print("  Methods: " .. table.concat(interesting, ", "))
            else
                self:Print("  No matching methods on frame")
            end
        else
            self:Print("  Not loaded (open Collections > Appearances first)")
        end

        -- 3. Check WardrobeOutfitMixin / WardrobeOutfitDropdownMixin
        self:Print("|cFFFFD100[3] Outfit mixins:|r")
        for _, name in ipairs({"WardrobeOutfitMixin", "WardrobeOutfitDropdownMixin",
            "WardrobeOutfitFrameMixin", "WardrobeTransmogSetMixin"}) do
            local obj = _G[name]
            if obj then
                local methods = {}
                for k, v in pairs(obj) do
                    if type(v) == "function" then
                        methods[#methods + 1] = k
                    end
                end
                table.sort(methods)
                self:Print("  " .. name .. ": " .. table.concat(methods, ", "))
            else
                self:Print("  " .. name .. ": not found")
            end
        end

        -- 4. DressUpFrame actor methods
        self:Print("|cFFFFD100[4] DressUpFrame actor methods:|r")
        if DressUpFrame and DressUpFrame.ModelScene then
            local actor = DressUpFrame.ModelScene:GetPlayerActor()
            if actor then
                local mt = getmetatable(actor)
                if mt and mt.__index then
                    local methods = {}
                    for k, v in pairs(mt.__index) do
                        local kl = tostring(k):lower()
                        if type(v) == "function" and (kl:find("transmog") or kl:find("dress")
                            or kl:find("appearance") or kl:find("undress") or kl:find("equip")
                            or kl:find("source") or kl:find("visual") or kl:find("outfit")) then
                            methods[#methods + 1] = tostring(k)
                        end
                    end
                    table.sort(methods)
                    self:Print("  " .. table.concat(methods, ", "))
                else
                    self:Print("  No metatable on actor")
                end
            else
                self:Print("  No player actor (open Dressing Room first)")
            end
        else
            self:Print("  DressUpFrame or ModelScene not available")
        end

        -- 5. Scan globals for transmog-related functions
        self:Print("|cFFFFD100[5] Global transmog function scan:|r")
        local hits = {}
        for k, v in pairs(_G) do
            if type(v) == "function" then
                local kl = tostring(k):lower()
                if kl:find("transmog") and (kl:find("equip") or kl:find("current")
                    or kl:find("active") or kl:find("outfit") or kl:find("dress")) then
                    hits[#hits + 1] = tostring(k)
                end
            end
        end
        table.sort(hits)
        self:Print("  " .. (#hits > 0 and table.concat(hits, ", ") or "none found"))

        -- 6. Check DressUpVisual / DressUpSources — how do THEY resolve?
        self:Print("|cFFFFD100[6] DressUp function check:|r")
        for _, fname in ipairs({"DressUpVisual", "DressUpSources", "DressUpItemLink",
            "DressUpTransmogLink", "DressUpOutfitFromSlotData"}) do
            local func = _G[fname]
            if func then
                local isLua = pcall(string.dump, func)
                self:Print("  " .. fname .. ": exists (" .. (isLua and "Lua" or "C") .. ")")
            else
                self:Print("  " .. fname .. ": not found")
            end
        end

    elseif cmd == "probe7" then
        self:Print("--- Probe 7: DressUpModel GetItemTransmogInfo ---")

        -- 1. Create a hidden DressUpModel and set it to the player
        self:Print("|cFFFFD100[1] DressUpModel approach:|r")
        local model = CreateFrame("DressUpModel", nil, UIParent)
        model:SetSize(1, 1)
        model:SetPoint("TOPLEFT", -100, -100)  -- off screen
        model:SetUnit("player")
        -- Give the model a frame to load
        C_Timer.After(0.1, function()
            for i = 1, #TransmogSlotOrder do
                local slotID = TransmogSlotOrder[i]
                local slotKey = StyleBound.INVSLOT_TO_SLOT[slotID] or tostring(slotID)
                local ok, tmogInfo = pcall(model.GetItemTransmogInfo, model, slotID)
                if ok and tmogInfo then
                    local appID = tmogInfo.appearanceID or 0
                    if appID > 0 then
                        local srcInfo = C_TransmogCollection.GetSourceInfo(appID)
                        local name = srcInfo and srcInfo.name or "?"
                        self:Print("  " .. slotKey .. ": appID=" .. appID .. " → " .. name)
                    else
                        self:Print("  " .. slotKey .. ": empty (appID=0)")
                    end
                else
                    self:Print("  " .. slotKey .. ": error=" .. tostring(tmogInfo))
                end
            end

            -- 2. Also try via ModelScene + PlayerActor if available
            self:Print("|cFFFFD100[2] ModelScene actor approach:|r")
            local scene = CreateFrame("ModelScene", nil, UIParent, "DressUpModelScene")
            if scene then
                scene:SetSize(1, 1)
                scene:SetPoint("TOPLEFT", -200, -200)
                local actor = scene:GetPlayerActor()
                if actor then
                    actor:SetModelByUnit("player", false, true)
                    C_Timer.After(0.2, function()
                        for i = 1, #TransmogSlotOrder do
                            local slotID = TransmogSlotOrder[i]
                            local slotKey = StyleBound.INVSLOT_TO_SLOT[slotID] or tostring(slotID)
                            local ok2, tmogInfo2 = pcall(actor.GetItemTransmogInfo, actor, slotID)
                            if ok2 and tmogInfo2 then
                                local appID2 = tmogInfo2.appearanceID or 0
                                if appID2 > 0 then
                                    local srcInfo2 = C_TransmogCollection.GetSourceInfo(appID2)
                                    local name2 = srcInfo2 and srcInfo2.name or "?"
                                    self:Print("  " .. slotKey .. ": appID=" .. appID2 .. " → " .. name2)
                                else
                                    self:Print("  " .. slotKey .. ": empty")
                                end
                            else
                                self:Print("  " .. slotKey .. ": error=" .. tostring(tmogInfo2))
                            end
                        end
                        scene:Hide()
                    end)
                else
                    self:Print("  No player actor on ModelScene")
                end
            else
                self:Print("  Could not create ModelScene")
            end

            model:Hide()
        end)

    elseif cmd == "probe8" then
        self:Print("--- Probe 8: ItemTransmogInfoList index mapping ---")

        -- 1. Check for existing Custom Sets first
        local sets = C_TransmogCollection.GetCustomSets()
        self:Print("Existing Custom Sets: " .. #sets)

        -- 2. Read the empty list to see its length
        local emptyList = TransmogUtil.GetEmptyItemTransmogInfoList()
        self:Print("Empty list length: " .. #emptyList)

        -- 3. If we have an existing Custom Set, read it
        if #sets > 0 then
            local setID = sets[1]
            local info = C_TransmogCollection.GetCustomSetInfo(setID)
            self:Print("|cFFFFD100Reading Custom Set " .. setID .. ":|r")
            if info then
                if type(info) == "table" then
                    for k, v in pairs(info) do
                        self:Print("  info." .. tostring(k) .. " = " .. tostring(v))
                    end
                else
                    self:Print("  info = " .. tostring(info) .. " (type: " .. type(info) .. ")")
                end
            end
            local setList = C_TransmogCollection.GetCustomSetItemTransmogInfoList(setID)
            if setList then
                self:Print("  List length: " .. #setList)
                for i, entry in ipairs(setList) do
                    if entry.appearanceID and entry.appearanceID > 0 then
                        local src = C_TransmogCollection.GetSourceInfo(entry.appearanceID)
                        local name = src and src.name or "?"
                        local catID = src and src.categoryID or "?"
                        self:Print("  [" .. i .. "] app=" .. entry.appearanceID
                            .. " sec=" .. tostring(entry.secondaryAppearanceID)
                            .. " ill=" .. tostring(entry.illusionID)
                            .. " → " .. name .. " (cat=" .. tostring(catID) .. ")")
                    end
                end
            end
        end

        -- 4. Create a test Custom Set from current transmog, then read it back
        self:Print("|cFFFFD100Creating test Custom Set...|r")
        local model = CreateFrame("DressUpModel", nil, UIParent)
        model:SetSize(1, 1)
        model:SetPoint("TOPLEFT", -100, -100)
        model:SetUnit("player")

        C_Timer.After(0.1, function()
            local testList = TransmogUtil.GetEmptyItemTransmogInfoList()
            local written = {}

            -- Try writing with list index = inventory slot ID
            for i = 1, #TransmogSlotOrder do
                local slotID = TransmogSlotOrder[i]
                local slotKey = StyleBound.INVSLOT_TO_SLOT[slotID] or tostring(slotID)
                local ok, tmogInfo = pcall(model.GetItemTransmogInfo, model, slotID)
                if ok and tmogInfo and tmogInfo.appearanceID and tmogInfo.appearanceID > 0 then
                    local source = C_TransmogCollection.GetSourceInfo(tmogInfo.appearanceID)
                    if source and not source.isHideVisual then
                        -- Hypothesis: list index = inventory slot ID
                        testList[slotID]:Init(source.visualID, 0, 0)
                        written[slotID] = { key = slotKey, vis = source.visualID, name = source.name }
                        self:Print("  Write [" .. slotID .. "] = " .. slotKey .. " vis=" .. source.visualID .. " (" .. (source.name or "?") .. ")")
                    end
                end
            end

            -- Check cap
            local count = #C_TransmogCollection.GetCustomSets()
            local max = C_TransmogCollection.GetNumMaxCustomSets()
            self:Print("Custom Set cap: " .. count .. "/" .. max)
            if count >= max then
                self:Print("|cFFFF0000Cap reached, can't create test set. Delete one first.|r")
                return
            end

            -- Create
            local newID = C_TransmogCollection.NewCustomSet("SB_PROBE_TEST", 0, testList)
            if not newID then
                self:Print("|cFFFF0000NewCustomSet returned nil!|r")
                return
            end
            self:Print("|cFF00FF00Created test set ID=" .. tostring(newID) .. "|r")

            -- Read it back
            C_Timer.After(0.2, function()
                local readBack = C_TransmogCollection.GetCustomSetItemTransmogInfoList(newID)
                if readBack then
                    self:Print("|cFFFFD100Read-back (list index = invSlot hypothesis):|r")
                    for i, entry in ipairs(readBack) do
                        if entry.appearanceID and entry.appearanceID > 0 then
                            local src = C_TransmogCollection.GetSourceInfo(entry.appearanceID)
                            local name = src and src.name or "?"
                            local match = written[i] and "MATCH" or "MISMATCH"
                            if written[i] and written[i].vis ~= entry.appearanceID then
                                match = "WRONG_VIS"
                            end
                            self:Print("  [" .. i .. "] app=" .. entry.appearanceID
                                .. " → " .. name .. " |cFF00FF00" .. match .. "|r")
                        end
                    end
                    -- Show which written slots came back empty
                    for slotID, data in pairs(written) do
                        local readEntry = readBack[slotID]
                        if not readEntry or readEntry.appearanceID == 0 then
                            self:Print("  |cFFFF0000MISSING [" .. slotID .. "] " .. data.key .. " was written but read back as 0|r")
                        end
                    end
                end

                -- Cleanup: delete the test set
                C_TransmogCollection.DeleteCustomSet(newID)
                self:Print("Deleted test set.")
            end)
        end)

    elseif cmd == "dbcheck" then
        self:Print("db.global.version: " .. tostring(self.db.global.version))
        self:Print("db.global.settings.debugMode: " .. tostring(self.db.global.settings.debugMode))
        self:Print("charDB.profile.collectedData.lastFlush: " .. tostring(self.charDB.profile.collectedData.lastFlush))
    else
        self:Print("Unknown command: " .. cmd .. ". Type /sb help")
    end
end
