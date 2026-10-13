local addonName, ns = ...
local A = CreateFrame("Frame")
ns.core = A

local defaults = {
    enabled = true,
    completelyHide = true,
    idleDelay = 1.5,
    showWhileMoving = false,
    showButton = true,
    buttonAngle = 210,
    minimapFadeInDuration = 0.35,
    minimapFadeOutDuration = 0.35,
    minimapFadeLevel = 0,
    clusterFadeInDuration = 0.35,
    clusterFadeOutDuration = 0.35,
    clusterFadeLevel = 0,
}

local db, cluster, hotspot, button
local parts = {}
local elapsedIdle = 0
local forcedShown = false
local internallyHidden = false
local accumulator = 0
local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

local function copyDefaults()
    HideMinimapForever = type(HideMinimapForever) == "table" and HideMinimapForever or {}
    db = HideMinimapForever
    -- Convert settings saved by older releases.
    if db.completelyHide == nil and db.mode ~= nil then db.completelyHide = db.mode ~= "fade" end
    -- Migrate settings from the previous frame/backdrop implementation.
    if db.clusterFadeDuration == nil then
        db.clusterFadeDuration = tonumber(db.backdropFadeDuration)
    end
    if db.clusterFadeLevel == nil then
        db.clusterFadeLevel = tonumber(db.backdropFadeLevel)
    end
    for key, value in pairs(defaults) do
        if db[key] == nil then db[key] = value end
    end
    for _, prefix in ipairs({"minimap", "cluster"}) do
        local oldDuration = tonumber(db[prefix .. "FadeDuration"]) or tonumber(db.fadeDuration)
        for _, direction in ipairs({"In", "Out"}) do
            local key = prefix .. "Fade" .. direction .. "Duration"
            if db[key] == nil then db[key] = oldDuration or defaults[key] end
            db[key] = clamp(tonumber(db[key]) or defaults[key], 0, 3)
        end
        local levelKey = prefix .. "FadeLevel"
        if db[levelKey] == nil then db[levelKey] = tonumber(db.hiddenAlpha) or defaults[levelKey] end
        db[levelKey] = clamp(tonumber(db[levelKey]) or defaults[levelKey], 0, 1)
        db[prefix .. "FadeDuration"] = nil
    end
    db.idleDelay = clamp(tonumber(db.idleDelay) or defaults.idleDelay, 0, 15)
    db.buttonAngle = tonumber(db.buttonAngle) or defaults.buttonAngle
    db.mode, db.fadeDuration, db.hiddenAlpha, db.showInCombat = nil, nil, nil, nil
    db.backdropFadeDuration, db.backdropFadeLevel = nil, nil
    db.minimapFadeDuration, db.clusterFadeDuration = nil, nil
end

function ns.GetDB() return db end

local function placeButton()
    if not button or not Minimap then return end
    local radians = math.rad(db.buttonAngle)
    local radius = Minimap:GetWidth() / 2 + 9
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(radians) * radius, math.sin(radians) * radius)
end

local function restoreMinimap()
    if internallyHidden and Minimap then
        internallyHidden = false
        Minimap:Show()
    end
end

-- Fade the Minimap and its parent MinimapCluster separately.
-- Their effective on-screen opacity is multiplicative.
local function setPartAlpha(part, value)
    part.alpha = clamp(value, 0, 1)
    if part.prefix == "minimap" then
        if Minimap then Minimap:SetAlpha(part.alpha) end
    elseif cluster then
        cluster:SetAlpha(part.alpha)
    end
end

local function restoreAll()
    restoreMinimap()
    for _, part in ipairs(parts) do
        part.target = 1
        part.startAlpha = 1
        part.fadeElapsed = 0
        setPartAlpha(part, 1)
    end
    if hotspot then hotspot:Hide() end
end

local function mouseOverMap()
    return (cluster and cluster:IsShown() and cluster:IsMouseOver())
        or (hotspot and hotspot:IsShown() and hotspot:IsMouseOver())
        or (button and button:IsShown() and button:IsMouseOver())
end

local function playerMoving()
    return GetUnitSpeed and (GetUnitSpeed("player") or 0) > 0.05
end

-- Each layer has its own fade clock and may opt into hiding at fade-out completion.
-- MinimapCluster fades visually only; only Minimap may be physically hidden.
local function fadeFrame(part, frame, target, dt, hideAfterFade)
    if not frame then return end
    if part.target ~= target then
        part.target = target
        part.startAlpha = part.alpha
        part.fadeElapsed = 0
        local direction = target < part.alpha and "Out" or "In"
        part.duration = db[part.prefix .. "Fade" .. direction .. "Duration"] or 0
    end
    if math.abs(part.alpha - target) > .0001 then
        part.fadeElapsed = math.min(part.duration, part.fadeElapsed + dt)
        local fraction = part.duration <= 0 and 1 or part.fadeElapsed / part.duration
        setPartAlpha(part, part.startAlpha + (target - part.startAlpha) * fraction)
    end
    if hideAfterFade and db.completelyHide and target < 1
        and math.abs(part.alpha - target) < .001 and not internallyHidden then
        if not (InCombatLockdown and InCombatLockdown() and frame.IsProtected and frame:IsProtected()) then
            internallyHidden = true
            frame:Hide()
        end
    end
end

local function update(dt)
    if not db or not cluster then return end
    if not db.enabled or forcedShown then
        restoreAll()
        return
    end

    local visible = mouseOverMap() or (db.showWhileMoving and playerMoving())
    if visible then
        elapsedIdle = 0
    else
        elapsedIdle = math.min(db.idleDelay, elapsedIdle + dt)
    end
    local idle = not visible and elapsedIdle >= db.idleDelay
    if not idle or not db.completelyHide then restoreMinimap() end

    for _, part in ipairs(parts) do
        local target = idle and db[part.prefix .. "FadeLevel"] or 1
        local frame = part.prefix == "minimap" and Minimap or cluster
        fadeFrame(part, frame, target, dt, part.prefix == "minimap" and idle)
    end
    if hotspot then hotspot:SetShown(internallyHidden) end
end

function A:Refresh()
    if not db or not cluster then return end
    if button then button:SetShown(db.showButton) placeButton() end
    if not db.enabled or forcedShown then
        elapsedIdle = 0
        restoreAll()
        return
    end
    -- Recompute targets immediately. Animations still use their own durations.
    elapsedIdle = db.idleDelay
    restoreMinimap()
    for _, part in ipairs(parts) do part.target = nil end
    update(0)
end

function A:Toggle()
    if not db then return end
    db.enabled = not db.enabled
    forcedShown = false
    self:Refresh()
    if ns.RefreshOptions then ns.RefreshOptions() end
    print("|cff65d6ffHide Minimap Forever:|r " .. (db.enabled and "enabled" or "disabled"))
end

function A:TogglePin()
    if not db then return end
    forcedShown = not forcedShown
    self:Refresh()
    print("|cff65d6ffHide Minimap Forever:|r " .. (forcedShown and "minimap pinned visible" or "automatic fade resumed"))
end

function ns.Reset()
    if not db then return end
    -- Clear obsolete persisted fields, then restore every current default.
    db.backdropFadeDuration, db.backdropFadeLevel = nil, nil
    db.minimapFadeDuration, db.clusterFadeDuration = nil, nil
    db.mode, db.fadeDuration, db.hiddenAlpha, db.showInCombat = nil, nil, nil, nil
    for key, value in pairs(defaults) do db[key] = value end
    forcedShown = false
    A:Refresh()
    if ns.RefreshOptions then ns.RefreshOptions() end
end

local function createHotspot()
    hotspot = CreateFrame("Frame", nil, UIParent)
    hotspot:SetSize(math.max(cluster:GetWidth(), 210), math.max(cluster:GetHeight(), 210))
    hotspot:SetPoint("CENTER", cluster, "CENTER")
    hotspot:SetFrameStrata("HIGH")
    hotspot:EnableMouse(true)
    hotspot:SetScript("OnEnter", function()
        elapsedIdle = 0
        restoreMinimap()
        if hotspot then hotspot:Hide() end
        update(0)
    end)
    hotspot:Hide()
end

local function createButton()
    -- The button belongs to Minimap: it fades and hides with its parent.
    button = CreateFrame("Button", "HideMinimapForeverButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    button:RegisterForDrag("LeftButton")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\Ability_Stealth")
    icon:SetSize(19, 19)
    icon:SetPoint("CENTER")
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(52, 52)
    border:SetPoint("TOPLEFT", 0, 0)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")
    highlight:SetAllPoints()
    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            if ns.OpenOptions then ns.OpenOptions() end
        elseif mouse == "MiddleButton" then A:TogglePin()
        else A:Toggle() end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            x, y = x / scale, y / scale
            local cx, cy = Minimap:GetCenter()
            if not cx then return end
            db.buttonAngle = math.deg(math.atan2(y - cy, x - cx))
            placeButton()
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Hide Minimap Forever", .4, .85, 1)
        GameTooltip:AddLine("Left-click: Enable / disable", 1, 1, 1)
        GameTooltip:AddLine("Right-click: Settings", 1, 1, 1)
        GameTooltip:AddLine("Middle-click: Pin visible / unpin", 1, 1, 1)
        GameTooltip:AddLine("Drag: Move around minimap", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    placeButton()
end

A:SetScript("OnUpdate", function(_, dt)
    accumulator = accumulator + math.min(dt, .1)
    if accumulator < .025 then return end
    local step = accumulator
    accumulator = 0
    update(step)
end)

A:RegisterEvent("PLAYER_LOGIN")
A:SetScript("OnEvent", function()
    copyDefaults()
    cluster = MinimapCluster or Minimap
    if not cluster then print("Hide Minimap Forever: minimap frame not found") return end
    parts = {
        {prefix = "minimap", alpha = 1, target = nil, startAlpha = 1, fadeElapsed = 0},
        {prefix = "cluster", alpha = 1, target = nil, startAlpha = 1, fadeElapsed = 0},
    }
    for _, part in ipairs(parts) do setPartAlpha(part, 1) end
    createHotspot()
    createButton()
    if ns.BuildOptions then ns.BuildOptions() end
    A:Refresh()
end)


-- Slash commands
SLASH_HIDEMINIMAPFOREVER1 = "/hmf"
SlashCmdList["HIDEMINIMAPFOREVER"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")

    if msg == "reset" then
        ns.Reset()
        print("|cff65d6ffHide Minimap Forever:|r Settings reset to defaults.")
    elseif msg == "" then
        if ns.OpenOptions then ns.OpenOptions() end
    else
        print("|cff65d6ffHide Minimap Forever:|r Commands: /hmf, /hmf reset")
    end
end