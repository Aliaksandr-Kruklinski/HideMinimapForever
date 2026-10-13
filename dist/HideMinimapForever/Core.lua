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
    minimapFadeDuration = 0.35,
    minimapFadeLevel = 0,
    backdropFadeDuration = 0.35,
    backdropFadeLevel = 0,
}

local db, cluster, hotspot, button
local parts = {}
local borderObjects = {}
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
    for key, value in pairs(defaults) do
        if db[key] == nil then db[key] = value end
    end
    for _, prefix in ipairs({"minimap", "backdrop"}) do
        local durationKey, levelKey = prefix .. "FadeDuration", prefix .. "FadeLevel"
        if db.fadeDuration and db[durationKey] == defaults[durationKey] then
            db[durationKey] = db.fadeDuration
        end
        if db.hiddenAlpha and db[levelKey] == defaults[levelKey] then
            db[levelKey] = db.hiddenAlpha
        end
        db[durationKey] = clamp(tonumber(db[durationKey]) or defaults[durationKey], 0, 3)
        db[levelKey] = clamp(tonumber(db[levelKey]) or defaults[levelKey], 0, 1)
    end
    db.idleDelay = clamp(tonumber(db.idleDelay) or defaults.idleDelay, 0, 15)
    db.buttonAngle = tonumber(db.buttonAngle) or defaults.buttonAngle
    db.mode, db.fadeDuration, db.hiddenAlpha, db.showInCombat = nil, nil, nil, nil
    db.clusterFadeDuration, db.clusterFadeLevel = nil, nil
end

function ns.GetDB() return db end

local function placeButton()
    if not button or not Minimap then return end
    local radians = math.rad(db.buttonAngle)
    local radius = Minimap:GetWidth() / 2 + 9
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(radians) * radius, math.sin(radians) * radius)
end

local function restoreCluster()
    if internallyHidden and cluster then
        internallyHidden = false
        cluster:Show()
    end
end

-- Fade map and border art independently; never fade the parent cluster.
-- In many WoW builds "MinimapBackdrop" is absent, and the actual border
-- consists of Texture regions such as MinimapBorder/MinimapBorderTop.
local function setPartAlpha(part, value)
    part.alpha = clamp(value, 0, 1)
    if part.prefix == "minimap" then
        if Minimap then Minimap:SetAlpha(part.alpha) end
    else
        for _, region in ipairs(borderObjects) do
            if region.SetAlpha then region:SetAlpha(part.alpha) end
        end
    end
end

local function isAncestorOfMap(obj)
    local current = Minimap
    while current do
        if current == obj then return true end
        current = current.GetParent and current:GetParent() or nil
    end
    return false
end

local function findBorderObjects()
    borderObjects = {}
    local seen = {}
    local function add(obj)
        if obj and obj ~= Minimap and obj ~= cluster and not seen[obj]
            and not isAncestorOfMap(obj) and obj.SetAlpha then
            seen[obj] = true
            borderObjects[#borderObjects + 1] = obj
        end
    end
    -- Stock and version-dependent globals; these may be frames OR textures.
    for _, name in ipairs({
        "MinimapBackdrop", "MinimapBorder", "MinimapBorderTop",
        "MiniMapTrackingBorder", "MinimapCompassTexture", "MinimapNorthTag",
        "MinimapZoomIn", "MinimapZoomOut", "MiniMapMailBorder",
    }) do add(_G[name]) end
    -- Some versions define border as an unnamed Texture on MinimapCluster.
    if cluster and cluster.GetRegions and cluster.GetNumRegions then
        for i = 1, cluster:GetNumRegions() do
            local region = select(i, cluster:GetRegions())
            if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                add(region)
            end
        end
    end
end

local function restoreAll()
    restoreCluster()
    for _, part in ipairs(parts) do
        part.target = 1
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

local function update(dt)
    if not db or not cluster then return end
    if not db.enabled or forcedShown then
        restoreAll()
        return
    end

    local visible = mouseOverMap() or (db.showWhileMoving and playerMoving())
    if visible then
        elapsedIdle = 0
        restoreCluster()
    else
        elapsedIdle = math.min(db.idleDelay, elapsedIdle + dt)
    end
    local idle = not visible and elapsedIdle >= db.idleDelay
    if not idle then restoreCluster() end

    local allFinished = true
    for _, part in ipairs(parts) do
        local wanted = (idle and db[part.prefix .. "FadeLevel"]) or 1
        part.target = wanted
        local duration = db[part.prefix .. "FadeDuration"]
        local change = duration <= 0 and 1 or dt / duration
        if math.abs(part.alpha - wanted) > .001 then
            local nextAlpha = part.alpha + (part.alpha < wanted and change or -change)
            if part.alpha < wanted then nextAlpha = math.min(wanted, nextAlpha)
            else nextAlpha = math.max(wanted, nextAlpha) end
            setPartAlpha(part, nextAlpha)
        end
        if math.abs(part.alpha - wanted) > .001 then allFinished = false end
    end

    -- The complete-hide option hides the cluster only once the independently
    -- configured fades have finished, leaving the hover hotspot available.
    local mayHide = db.completelyHide and idle and allFinished
        and db.minimapFadeLevel <= .001 and db.backdropFadeLevel <= .001
    if mayHide and not internallyHidden then
        if not (InCombatLockdown and InCombatLockdown() and cluster.IsProtected and cluster:IsProtected()) then
            internallyHidden = true
            cluster:Hide()
        end
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
    -- Apply changed fade options immediately rather than waiting for another idle cycle.
    elapsedIdle = db.idleDelay
    restoreCluster()
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
        restoreCluster()
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
    -- Only two independent layers. The container is never alpha-adjusted.
    findBorderObjects()
    parts = {
        {prefix = "minimap", alpha = 1},
        {prefix = "backdrop", alpha = 1},
    }
    for _, part in ipairs(parts) do setPartAlpha(part, 1) end
    createHotspot()
    createButton()
    if ns.BuildOptions then ns.BuildOptions() end
    A:Refresh()
end)
