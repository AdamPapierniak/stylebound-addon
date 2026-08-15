-- UI/HousingDialog.lua - Copyable website manifest for a housing blueprint.

local _, StyleBound = ...

local HousingDialog = StyleBound:NewModule("HousingDialog")
local AceGUI = LibStub("AceGUI-3.0")
local UI = StyleBound.UI
local frame

function HousingDialog:ShowManifest(manifest, encoded)
    if frame then
        frame:Release()
        frame = nil
    end

    frame = AceGUI:Create("Frame")
    frame:SetTitle("StyleBound Housing Blueprint")
    frame:SetLayout("List")
    frame:SetWidth(620)
    frame:SetHeight(440)
    UI:ApplyFrame(frame)
    UI:HideStatusBar(frame)
    frame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        frame = nil
    end)

    local intro = AceGUI:Create("Label")
    intro:SetFullWidth(true)
    intro:SetText(
        "WoW verified this code and returned " .. tostring(#(manifest.requirements or {})) ..
        " requirement entries. Copy the manifest below into the Housing submission form on stylebound.gg."
    )
    UI:SetLabelColor(intro, UI.Colors.text)
    frame:AddChild(intro)

    local editBox = AceGUI:Create("MultiLineEditBox")
    editBox:SetLabel("Housing manifest:")
    editBox:SetFullWidth(true)
    editBox:SetNumLines(12)
    editBox:DisableButton(true)
    editBox:SetText(encoded)
    frame:AddChild(editBox)

    local note = AceGUI:Create("Label")
    note:SetFullWidth(true)
    note:SetText("The manifest includes the public share code, object totals, item/catalog IDs, names, sources, icons, placement costs, and blueprint budget costs. It does not include your personal missing-item counts.")
    UI:SetLabelColor(note, UI.Colors.muted)
    frame:AddChild(note)

    C_Timer.After(0, function()
        if editBox and editBox.editBox then
            editBox.editBox:SetFocus()
            editBox.editBox:HighlightText()
        end
    end)
end
