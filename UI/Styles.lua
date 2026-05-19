-- UI/Styles.lua - Small shared styling helpers for StyleBound AceGUI screens.

local _, StyleBound = ...

StyleBound.UI = StyleBound.UI or {}

local UI = StyleBound.UI
local AceGUI = LibStub("AceGUI-3.0")

UI.Colors = {
    bg       = { 0.039, 0.039, 0.039, 0.98 }, -- #0A0A0A
    panel    = { 0.067, 0.067, 0.067, 0.96 }, -- #111111
    panelAlt = { 0.032, 0.032, 0.032, 0.94 },
    border   = { 0.165, 0.145, 0.125, 1.00 }, -- #2A2520
    gold     = { 0.788, 0.659, 0.298, 1.00 }, -- #C9A84C
    goldDim  = { 0.34, 0.27, 0.12, 1.00 },
    text     = { 0.91, 0.85, 0.71, 1.00 }, -- #E8D9B5
    muted    = { 0.60, 0.56, 0.48, 1.00 }, -- #9A8F7A
    faint    = { 0.29, 0.27, 0.25, 1.00 },
    green    = { 0.28, 0.82, 0.38, 1.00 },
    orange   = { 1.00, 0.50, 0.13, 1.00 },
    red      = { 1.00, 0.22, 0.22, 1.00 },
}

local function SetTextureColor(texture, color)
    texture:SetColorTexture(color[1], color[2], color[3], color[4])
end

local function EnsureTexture(frame, key, layer)
    if not frame[key] then
        frame[key] = frame:CreateTexture(nil, layer or "BACKGROUND")
    end
    return frame[key]
end

function UI:SetLabelColor(widget, color)
    if widget and widget.SetColor then
        widget:SetColor(color[1], color[2], color[3])
    end
end

function UI:ApplyFrame(aceFrame)
    if not aceFrame or not aceFrame.frame then return end

    local colors = self.Colors
    local frame = aceFrame.frame
    if frame.SetBackdropColor then
        frame:SetBackdropColor(colors.bg[1], colors.bg[2], colors.bg[3], colors.bg[4])
    end
    if frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(colors.goldDim[1], colors.goldDim[2], colors.goldDim[3], 1)
    end
    if aceFrame.titletext and aceFrame.titletext.SetTextColor then
        aceFrame.titletext:SetTextColor(colors.text[1], colors.text[2], colors.text[3])
    end
    if aceFrame.statustext and aceFrame.statustext.SetTextColor then
        aceFrame.statustext:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
    end
end

function UI:EnforceMinimumFrame(aceFrame, minWidth, minHeight)
    if not aceFrame or not aceFrame.frame then return end

    local status = aceFrame.status or aceFrame.localstatus
    local width = aceFrame.frame:GetWidth() or 0
    local height = aceFrame.frame:GetHeight() or 0

    if minWidth and width < minWidth then
        aceFrame:SetWidth(minWidth)
        if status then status.width = minWidth end
    end
    if minHeight and height < minHeight then
        aceFrame:SetHeight(minHeight)
        if status then status.height = minHeight end
    end
end

function UI:StylePanel(widget, variant)
    if not widget or not widget.frame then return end

    local colors = self.Colors
    local frame = widget.frame
    local bg = EnsureTexture(frame, "StyleBoundBg", "BACKGROUND")
    local top = EnsureTexture(frame, "StyleBoundBorderTop", "BORDER")
    local bottom = EnsureTexture(frame, "StyleBoundBorderBottom", "BORDER")
    local left = EnsureTexture(frame, "StyleBoundBorderLeft", "BORDER")
    local right = EnsureTexture(frame, "StyleBoundBorderRight", "BORDER")

    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    top:SetHeight(1)

    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(1)

    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    left:SetWidth(1)

    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(1)

    local transparent = { 0, 0, 0, 0 }
    local bgColor = colors.panel
    local borderColor = colors.border
    local topColor = nil
    local bottomColor = nil
    local sideColor = transparent
    if variant == "subtle" then
        bgColor = colors.panelAlt
    elseif variant == "gold" then
        borderColor = colors.goldDim
    elseif variant == "card" then
        bgColor = colors.panelAlt
        borderColor = colors.faint
        topColor = transparent
        bottomColor = transparent
    elseif variant == "cardGold" then
        bgColor = { 0.052, 0.045, 0.035, 0.96 }
        borderColor = colors.goldDim
        topColor = transparent
        bottomColor = transparent
    elseif variant == "titleStrip" then
        bgColor = { 0.070, 0.066, 0.058, 0.98 }
        borderColor = colors.border
    elseif variant == "titleStripGold" then
        bgColor = { 0.085, 0.071, 0.043, 0.98 }
        borderColor = colors.goldDim
    elseif variant == "selected" then
        bgColor = { 0.105, 0.092, 0.061, 0.98 }
        borderColor = colors.gold
    end

    SetTextureColor(bg, bgColor)
    SetTextureColor(top, topColor or borderColor)
    SetTextureColor(bottom, bottomColor or borderColor)
    SetTextureColor(left, sideColor)
    SetTextureColor(right, sideColor)
end

function UI:AddSpacer(container, height)
    local spacer = AceGUI:Create("SimpleGroup")
    spacer:SetFullWidth(true)
    spacer:SetHeight(height or 8)
    spacer.noAutoHeight = true
    container:AddChild(spacer)
    return spacer
end

function UI:AddDivider(container)
    local sep = AceGUI:Create("SimpleGroup")
    sep:SetFullWidth(true)
    sep:SetHeight(12)
    sep.noAutoHeight = true

    local line = sep.frame:CreateTexture(nil, "BORDER")
    line:SetPoint("LEFT", sep.frame, "LEFT", 4, 0)
    line:SetPoint("RIGHT", sep.frame, "RIGHT", -4, 0)
    line:SetPoint("CENTER", sep.frame, "CENTER", 0, 0)
    line:SetHeight(1)
    SetTextureColor(line, self.Colors.border)

    container:AddChild(sep)
    return sep
end

function UI:AddText(container, text, color, fontObject)
    local label = AceGUI:Create("Label")
    label:SetText(text or "")
    label:SetFullWidth(true)
    if label.SetFontObject then
        label:SetFontObject(fontObject or GameFontHighlight)
    end
    if color then
        self:SetLabelColor(label, color)
    end
    container:AddChild(label)
    return label
end

function UI:CreatePanel(container, variant, paddingTop)
    local panel = AceGUI:Create("SimpleGroup")
    panel:SetFullWidth(true)
    panel:SetLayout("List")
    self:StylePanel(panel, variant)
    container:AddChild(panel)
    if paddingTop ~= false then
        self:AddSpacer(panel, paddingTop or 8)
    end
    return panel
end

function UI:CreateRow(container, variant, layout)
    local row = AceGUI:Create("SimpleGroup")
    row:SetFullWidth(true)
    row:SetLayout(layout or "Flow")
    self:StylePanel(row, variant or "subtle")
    container:AddChild(row)
    self:AddSpacer(row, 4)
    return row
end
