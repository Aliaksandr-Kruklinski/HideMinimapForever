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

local function slider(parent, key, label, x, y, min, max, step, unit, description)
    local title = text(parent, label, 12)
    title:SetPoint("TOPLEFT", x, y)
    local value = text(parent, "", 12, { .40, .85, 1 })
    value:SetPoint("LEFT", title, "RIGHT", 12, 0)
    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", x, y - 25)
    s:SetSize(220, 17)
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
    for key, sliderFrame in pairs(sliders) do
        local value = tonumber(db[key])
        if value == nil then
            value = (key == "idleDelay" and 1.5)
                or (key:find("FadeDuration") and 0.35)
                or 0
            db[key] = value
        end
        sliderFrame:SetValue(value)
    end
    updating = false
end

function ns.BuildOptions()
    if panel then return end
    panel = CreateFrame("Frame", "HideMinimapForeverOptions", UIParent)
    panel:SetSize(600, 580)
    panel.name = "Hide Minimap Forever"

    -- Keep the viewport compact; contents can scroll on smaller displays.
    local scroll = CreateFrame("ScrollFrame", "HideMinimapForeverOptionsScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -8)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 45)
    scroll:EnableMouseWheel(true)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(550, 760)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        local nextPosition = math.max(0, math.min(range, self:GetVerticalScroll() - delta * 38))
        self:SetVerticalScroll(nextPosition)
    end)

    local heading = text(content, "HIDE MINIMAP FOREVER", 21, { .36, .82, 1 })
    heading:SetPoint("TOPLEFT", 26, -16)
    local subtitle = text(content, "Separate fade-in and fade-out for map and cluster", 12, { .56, .65, .76 })
    subtitle:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -7)

    checkbox(content, "enabled", "Enabled", -72,
        "Disabling the addon immediately restores both minimap layers and stops automatic hiding.")
    checkbox(content, "completelyHide", "Completely hide map", -107,
        "Hide Minimap itself only after its fade-out finishes. MinimapCluster never gets hidden by this option. Mouse-over restores Minimap.")
    checkbox(content, "showWhileMoving", "Show while moving; hide while stationary", -142,
        "Show the map while moving. After stopping, the idle timer begins before fade-out.")
    checkbox(content, "showButton", "Show minimap button", -177,
        "Show the stealth-icon button attached to Minimap. Left-click toggles; right-click opens settings; middle-click pins; drag moves.")

    local timing = text(content, "GENERAL TIMING", 13, { .36, .82, 1 })
    timing:SetPoint("TOPLEFT", 36, -225)
    slider(content, "idleDelay", "Idle delay", 36, -252, 0, 15, .25, " s",
        "Time after mouse-over ends or movement stops before fading begins.")

    local mapHeading = text(content, "MINIMAP", 13, { .36, .82, 1 })
    mapHeading:SetPoint("TOPLEFT", 36, -325)
    slider(content, "minimapFadeInDuration", "Fade in", 36, -356, 0, 3, .05, " s",
        "How long Minimap takes to fade in from its current opacity.")
    slider(content, "minimapFadeOutDuration", "Fade out", 300, -356, 0, 3, .05, " s",
        "How long Minimap takes to fade out. Complete hide waits only for this animation.")
    slider(content, "minimapFadeLevel", "Idle opacity", 36, -423, 0, 1, .05, "",
        "Idle opacity of Minimap. A parent cluster opacity also affects its effective visibility.")

    local clusterHeading = text(content, "MINIMAP CLUSTER", 13, { .36, .82, 1 })
    clusterHeading:SetPoint("TOPLEFT", 36, -500)
    slider(content, "clusterFadeInDuration", "Fade in", 36, -531, 0, 3, .05, " s",
        "How long MinimapCluster takes to fade in.")
    slider(content, "clusterFadeOutDuration", "Fade out", 300, -531, 0, 3, .05, " s",
        "How long MinimapCluster takes to fade out. It is never physically hidden.")
    slider(content, "clusterFadeLevel", "Idle opacity", 36, -598, 0, 1, .05, "",
        "Idle opacity of MinimapCluster, which multiplies the opacity of all its children.")

    local note = text(content, "Complete hide affects only Minimap, not MinimapCluster.", 11, { .60, .69, .78 })
    note:SetPoint("TOPLEFT", 36, -683)

    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(120, 27)
    reset:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 10)
    reset:SetText("Reset defaults")
    reset:SetScript("OnClick", function() ns.Reset() end)

    panel:SetScript("OnShow", function()
        panel:SetHeight(math.max(250, math.min(580, UIParent:GetHeight() - 145)))
        ns.RefreshOptions()
    end)
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
