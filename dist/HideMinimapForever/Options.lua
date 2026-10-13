local addonName, ns = ...
local panel, category
local checks, sliders = {}, {}
local updating = false

-- Controls
local function text(parent, value, size, color)
    local t = parent:CreateFontString(nil, "OVERLAY")
    t:SetFont(STANDARD_TEXT_FONT, size or 13, "")
    t:SetTextColor(unpack(color or { .83, .89, .96 }))
    t:SetText(value)
    return t
end

local function tooltip(frame, heading, description)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(heading, .4, .85, 1)
        GameTooltip:AddLine(description, .95, .95, .95, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function checkbox(parent, key, label, y, description)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 25, y)
    cb:SetSize(27, 27)
    local title = text(parent, label, 13)
    title:SetPoint("LEFT", cb, "RIGHT", 7, 0)
    tooltip(cb, label, description)
    -- Also make the label hoverable/clickable.
    local hit = CreateFrame("Button", nil, parent)
    hit:SetAllPoints(title)
    tooltip(hit, label, description)
    hit:SetScript("OnClick", function() cb:Click() end)
    cb:SetScript("OnClick", function(self)
        if updating then return end
        ns.GetDB()[key] = not not self:GetChecked()
        ns.core:Refresh()
    end)
    checks[key] = cb
end

local function slider(parent, key, label, y, min, max, step, unit, description)
    local title = text(parent, label, 12)
    title:SetPoint("TOPLEFT", 36, y)
    local value = text(parent, "", 12, { .40, .85, 1 })
    value:SetPoint("LEFT", title, "RIGHT", 12, 0)
    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", 34, y - 23)
    s:SetSize(275, 17)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    if s.Low then s.Low:SetText(string.format("%g", min)) end
    if s.High then s.High:SetText(string.format("%g", max)) end
    if s.Text then s.Text:SetText("") end
    tooltip(s, label, description)
    s:SetScript("OnValueChanged", function(self, v)
        local rounded = math.floor(v / step + .5) * step
        rounded = math.max(min, math.min(max, rounded))
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
    updating = false
end

function ns.BuildOptions()
    if panel then return end
    panel = CreateFrame("Frame", "HideMinimapForeverOptions", UIParent)
    panel:SetSize(620, 690)
    panel.name = "Hide Minimap Forever"

    local heading = text(panel, "HIDE MINIMAP FOREVER", 21, { .36, .82, 1 })
    heading:SetPoint("TOPLEFT", 26, -20)
    local subtitle = text(panel, "Independent fade controls for the map and its frame", 12, { .56, .65, .76 })
    subtitle:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -7)

    checkbox(panel, "enabled", "Enabled", -76,
        "Master switch. Uncheck to immediately restore the entire minimap to full opacity and disable automatic hiding.")
    checkbox(panel, "completelyHide", "Completely hide map", -111,
        "Fully hide after fading only when both idle opacity sliders are set to 0. Mouse-over restores the minimap. Otherwise keep the separately configured opacity levels.")
    checkbox(panel, "showWhileMoving", "Show while moving; hide while stationary", -146,
        "Show the minimap whenever your character is running, walking, swimming, or flying. Once stationary, start the idle delay before fading.")
    checkbox(panel, "showButton", "Show minimap button", -181,
        "Display the stealth-icon button on the minimap edge. Left-click toggles the addon, right-click opens settings, middle-click pins it visible, drag repositions it.")

    local timing = text(panel, "GENERAL TIMING", 13, { .36, .82, 1 })
    timing:SetPoint("TOPLEFT", 36, -221)
    slider(panel, "idleDelay", "Idle delay", -246, 0, 15, .25, " s",
        "How long to wait after movement or mouse-over ends before fading begins.")

    local mapHeading = text(panel, "MINIMAP", 13, { .36, .82, 1 })
    mapHeading:SetPoint("TOPLEFT", 36, -319)
    slider(panel, "minimapFadeDuration", "Fade duration", -341, 0, 3, .05, " s",
        "Number of seconds for the Minimap map image to fade between visible and idle opacity.")
    slider(panel, "minimapFadeLevel", "Idle opacity", -402, 0, 1, .05, "",
        "Opacity of the map image while idle: 0 is invisible, 1 is fully opaque.")

    local backdropHeading = text(panel, "MINIMAP FRAME", 13, { .36, .82, 1 })
    backdropHeading:SetPoint("TOPLEFT", 36, -472)
    slider(panel, "backdropFadeDuration", "Fade duration", -494, 0, 3, .05, " s",
        "Fade time for the surrounding minimap border artwork (MinimapBorder, MinimapBorderTop and other available border elements).")
    slider(panel, "backdropFadeLevel", "Idle opacity", -555, 0, 1, .05, "",
        "Opacity of the surrounding minimap border artwork, independently from the map image.")

    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(120, 27)
    reset:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 10)
    reset:SetText("Reset defaults")
    reset:SetScript("OnClick", function() ns.Reset() end)

    panel:SetScript("OnShow", ns.RefreshOptions)
    ns.RefreshOptions()
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        category = Settings.RegisterCanvasLayoutCategory(panel, "Hide Minimap Forever")
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
