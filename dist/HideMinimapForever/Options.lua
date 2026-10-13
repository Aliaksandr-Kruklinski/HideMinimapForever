local addonName, ns = ...
local panel, category
local checks, sliders = {}, {}
local updating = false

local function text(parent, value, size, color)
    local t = parent:CreateFontString(nil, "OVERLAY")
    t:SetFont(STANDARD_TEXT_FONT, size or 13, "")
    t:SetTextColor(unpack(color or { .83, .89, .96 }))
    t:SetText(value)
    return t
end

local function backdrop(frame, r, g, b, a)
    if frame.SetBackdrop then
        frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        frame:SetBackdropColor(r, g, b, a or 1)
        frame:SetBackdropBorderColor(.19, .27, .36, 1)
    end
end

local function checkbox(parent, key, label, y, note)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 25, y)
    cb:SetSize(27, 27)
    local title = text(parent, label, 13)
    title:SetPoint("LEFT", cb, "RIGHT", 7, 0)
    if note then
        local hint = text(parent, note, 11, { .54, .62, .72 })
        hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    end
    cb:SetScript("OnClick", function(self)
        if updating then return end
        ns.GetDB()[key] = not not self:GetChecked()
        ns.core:Refresh()
    end)
    checks[key] = cb
end

local function slider(parent, key, label, y, min, max, step, unit)
    local title = text(parent, label, 13)
    title:SetPoint("TOPLEFT", 36, y)
    local value = text(parent, "", 12, { .40, .85, 1 })
    value:SetPoint("LEFT", title, "RIGHT", 12, 0)
    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", 34, y - 27)
    s:SetSize(320, 18)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    if s.Low then s.Low:SetText(string.format("%g", min)) end
    if s.High then s.High:SetText(string.format("%g", max)) end
    if s.Text then s.Text:SetText("") end
    s:SetScript("OnValueChanged", function(self, v)
        local rounded = math.floor(v / step + .5) * step
        value:SetText(string.format("%.2f%s", rounded, unit or ""))
        if updating then return end
        ns.GetDB()[key] = rounded
        ns.core:Refresh()
    end)
    sliders[key] = s
end

function ns.RefreshOptions()
    if not panel or not ns.GetDB() then return end
    local db = ns.GetDB()
    updating = true
    for key, cb in pairs(checks) do cb:SetChecked(db[key]) end
    for key, sliderFrame in pairs(sliders) do sliderFrame:SetValue(db[key]) end
    if panel.fadeRadio then panel.fadeRadio:SetChecked(db.mode == "fade") end
    if panel.hideRadio then panel.hideRadio:SetChecked(db.mode == "hide") end
    updating = false
end

function ns.BuildOptions()
    if panel then return end
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    panel = CreateFrame("Frame", "ForeverMinimapFadeOptions", UIParent, template)
    panel:SetSize(620, 650)
    backdrop(panel, .045, .065, .095, .96)
    panel.name = "Forever Minimap Fade"

    local heading = text(panel, "FOREVER  /  MINIMAP FADE", 21, { .36, .82, 1 })
    heading:SetPoint("TOPLEFT", 26, -24)
    local subtitle = text(panel, "Minimal map. Full control.", 12, { .56, .65, .76 })
    subtitle:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -8)
    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface\\Buttons\\WHITE8X8")
    divider:SetColorTexture(.18, .28, .39, .8)
    divider:SetPoint("TOPLEFT", 26, -87)
    divider:SetSize(540, 1)

    checkbox(panel, "enabled", "Enable automatic minimap fading", -100)
    checkbox(panel, "showInCombat", "Keep minimap visible in combat", -143)
    checkbox(panel, "showButton", "Show movable minimap button", -186)

    local modeLabel = text(panel, "WHEN IDLE", 13, { .36, .82, 1 })
    modeLabel:SetPoint("TOPLEFT", 36, -238)
    local function radio(label, x, mode)
        local rb = CreateFrame("CheckButton", nil, panel, "UIRadioButtonTemplate")
        rb:SetPoint("TOPLEFT", x, -258)
        local t = text(panel, label, 13)
        t:SetPoint("LEFT", rb, "RIGHT", 6, 0)
        rb:SetScript("OnClick", function()
            ns.GetDB().mode = mode
            ns.core:Refresh()
            ns.RefreshOptions()
        end)
        return rb
    end
    panel.hideRadio = radio("Fade + fully hide", 33, "hide")
    panel.fadeRadio = radio("Fade only", 240, "fade")

    slider(panel, "idleDelay", "Idle delay", -319, 0, 15, .25, " s")
    slider(panel, "fadeDuration", "Fade duration", -395, 0, 3, .05, " s")
    slider(panel, "hiddenAlpha", "Fade-only opacity", -471, 0, .7, .05, "")

    local help = text(panel, "Left-click button: toggle  |  Right-click: settings  |  Middle-click: pin", 11, { .60, .69, .78 })
    help:SetPoint("TOPLEFT", 35, -556)
    local cmd = text(panel, "Commands: /fmf  /fmf on  /fmf off  /fmf pin  /fmf reset", 11, { .60, .69, .78 })
    cmd:SetPoint("TOPLEFT", 35, -578)

    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(120, 27)
    reset:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 22)
    reset:SetText("Reset defaults")
    reset:SetScript("OnClick", function() ns.Reset() end)

    panel:SetScript("OnShow", ns.RefreshOptions)
    ns.RefreshOptions()

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        category = Settings.RegisterCanvasLayoutCategory(panel, "Forever Minimap Fade")
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    else
        panel:SetPoint("CENTER")
        panel:SetMovable(true)
        panel:EnableMouse(true)
        panel:RegisterForDrag("LeftButton")
        panel:SetScript("OnDragStart", panel.StartMoving)
        panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
        panel:Hide()
    end
end

function ns.OpenOptions()
    if not panel then return end
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
    else
        panel:SetShown(not panel:IsShown())
    end
end
