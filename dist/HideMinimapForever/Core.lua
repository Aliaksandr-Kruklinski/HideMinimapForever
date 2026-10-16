-- ============================================================================
-- Constants and shared state
-- ============================================================================

local addonName, ns = ...
local A = CreateFrame("Frame")
ns.core = A

-- Single source of truth for defaults and numeric slider limits.
local settings = {
    enabled = {default = true},
    completelyHide = {default = true},
    idleDelay = {default = 2, min = 0, max = 15, step = .25},
    showWhileMoving = {default = false},
    showButton = {default = true},
    buttonAngle = {default = 210},
    minimapFadeInDuration = {default = .50, min = 0, max = 3, step = .05},
    minimapFadeOutDuration = {default = .60, min = 0, max = 3, step = .05},
    minimapFadeLevel = {default = 0, min = 0, max = 1, step = .05},
    clusterFadeInDuration = {default = .50, min = 0, max = 3, step = .05},
    clusterFadeOutDuration = {default = .90, min = 0, max = 3, step = .05},
    clusterFadeLevel = {default = 0, min = 0, max = 1, step = .05},
}
ns.Settings = settings

local db, cluster, hotspot, button
local initialized = false
local parts = {}
local clusterElements = {}
local elapsedIdle = 0
local forcedShown = false
local internallyHidden = false
local accumulator = 0
local UPDATE_ACTIVE = .025
local UPDATE_IDLE = .10
local UPDATE_INACTIVE = .25

-- Adapted from the proven LibDBIcon minimap positioning approach.
-- Round and square minimap layouts require different edge calculations.
local minimapShapes = {
    ROUND = {true, true, true, true},
    SQUARE = {false, false, false, false},
    ["CORNER-TOPLEFT"] = {true, false, false, false},
    ["CORNER-TOPRIGHT"] = {false, false, true, false},
    ["CORNER-BOTTOMLEFT"] = {false, true, false, false},
    ["CORNER-BOTTOMRIGHT"] = {false, false, false, true},
    ["SIDE-LEFT"] = {true, true, false, false},
    ["SIDE-RIGHT"] = {false, false, true, true},
    ["SIDE-TOP"] = {true, false, true, false},
    ["SIDE-BOTTOM"] = {false, true, false, true},
    ["TRICORNER-TOPLEFT"] = {true, true, true, false},
    ["TRICORNER-TOPRIGHT"] = {true, false, true, true},
    ["TRICORNER-BOTTOMLEFT"] = {true, true, false, true},
    ["TRICORNER-BOTTOMRIGHT"] = {false, true, true, true},
}

-- ============================================================================
-- Helpers: settings, visibility, and frame state
-- ============================================================================

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

local function clearLegacySettings()
    db.mode, db.fadeDuration, db.hiddenAlpha, db.showInCombat = nil, nil, nil, nil
    db.backdropFadeDuration, db.backdropFadeLevel = nil, nil
    db.minimapFadeDuration, db.clusterFadeDuration = nil, nil
end

local function copyDefaults()
    -- Called after WoW loads SavedVariables; never replace an existing table.
    HideMinimapForever = type(HideMinimapForever) == "table" and HideMinimapForever or {}
    db = HideMinimapForever

    -- Migrate BEFORE applying defaults, otherwise new default keys mask old values.
    if db.completelyHide == nil and db.mode ~= nil then
        db.completelyHide = db.mode ~= "fade"
    end
    local oldClusterDuration = tonumber(db.clusterFadeDuration) or tonumber(db.backdropFadeDuration)
    local oldClusterLevel = tonumber(db.backdropFadeLevel)
    for _, prefix in ipairs({"minimap", "cluster"}) do
        local oldDuration = (prefix == "cluster" and oldClusterDuration)
            or tonumber(db[prefix .. "FadeDuration"]) or tonumber(db.fadeDuration)
        for _, direction in ipairs({"In", "Out"}) do
            local key = prefix .. "Fade" .. direction .. "Duration"
            if db[key] == nil and oldDuration ~= nil then db[key] = oldDuration end
        end
        local levelKey = prefix .. "FadeLevel"
        if db[levelKey] == nil then
            db[levelKey] = (prefix == "cluster" and oldClusterLevel) or tonumber(db.hiddenAlpha)
        end
    end

    for key, spec in pairs(settings) do
        if db[key] == nil then db[key] = spec.default end
        if spec.min ~= nil then
            db[key] = clamp(tonumber(db[key]) or spec.default, spec.min, spec.max)
        end
    end
    db.buttonAngle = tonumber(db.buttonAngle) or settings.buttonAngle.default
    clearLegacySettings()
end

function ns.GetDB() return db end

local function restoreMinimap()
    if internallyHidden and Minimap then
        internallyHidden = false
        Minimap:Show()
    end
end

-- Fade surroundings without fading the Minimap through any of its parents.
-- MinimapCluster.MinimapContainer can contain additional UI (coordinates,
-- day/night indicator) alongside the Minimap. Collect those siblings and
-- regions too, but never change the container's alpha or hide it.
-- Preserve original alpha so disabling the addon restores Blizzard styling.
local function collectClusterElements()
    clusterElements = {}
    if not cluster or cluster == Minimap then return end

    -- Build the path from Minimap up to (but excluding) MinimapCluster.
    -- Every frame on that path must stay at its normal alpha because it
    -- contains Minimap; only its siblings and regions may be faded.
    local path = {}
    local current = Minimap
    while current and current ~= cluster do
        path[#path + 1] = current
        current = current:GetParent()
    end

    local function collectFrom(parent, protectedChild)
        for _, child in ipairs({ parent:GetChildren() }) do
            if child ~= protectedChild and child ~= Minimap and child.SetAlpha then
                clusterElements[#clusterElements + 1] = {
                    frame = child,
                    originalAlpha = child:GetAlpha(),
                }
            end
        end
        for _, region in ipairs({ parent:GetRegions() }) do
            if region.SetAlpha then
                clusterElements[#clusterElements + 1] = {
                    frame = region,
                    originalAlpha = region:GetAlpha(),
                }
            end
        end
    end

    if current == cluster then
        -- Walk down the protected branch, collecting siblings at each level.
        -- This includes MinimapCluster.MinimapContainer without touching the
        -- Minimap's own alpha or physical visibility.
        for i = #path, 1, -1 do
            local parent = (i == #path) and cluster or path[i + 1]
            collectFrom(parent, path[i])
            parent:SetAlpha(1)
        end
    else
        -- Fallback when another addon reparents Minimap outside the cluster.
        collectFrom(cluster, nil)
    end
    cluster:SetAlpha(1)
end

local function setPartAlpha(part, value)
    part.alpha = clamp(value, 0, 1)
    if part.prefix == "minimap" then
        if Minimap then Minimap:SetAlpha(part.alpha) end
    else
        for _, entry in ipairs(clusterElements) do
            entry.frame:SetAlpha(entry.originalAlpha * part.alpha)
        end
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

-- ============================================================================
-- Minimap button: placement, appearance, and interaction
-- ============================================================================

local function placeButton()
    if not button or not Minimap or not db then return end
    local angle = math.rad(db.buttonAngle or 210)
    local x, y = math.cos(angle), math.sin(angle)
    local quadrant = 1
    if x < 0 then quadrant = quadrant + 1 end
    if y > 0 then quadrant = quadrant + 2 end

    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    local roundQuadrants = minimapShapes[shape] or minimapShapes.ROUND
    -- Standard LibDBIcon places a 31px button ~80px from a 140px map center.
    -- Use measured dimensions so resized minimaps behave correctly too.
    local halfWidth, halfHeight = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
    local edgeX, edgeY = halfWidth + 10, halfHeight + 10
    if roundQuadrants[quadrant] then
        x, y = x * edgeX, y * edgeY
    else
        local diagonal = math.sqrt(edgeX * edgeX + edgeY * edgeY)
        x = clamp(x * diagonal, -edgeX, edgeX)
        y = clamp(y * diagonal, -edgeY, edgeY)
    end

    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function onButtonClick(_, mouse)
    if mouse == "RightButton" then
        if ns.OpenOptions then ns.OpenOptions() end
    elseif mouse == "LeftButton" then
        A:Toggle()
    end
end

local function onButtonDragUpdate()
    local cx, cy = Minimap:GetCenter()
    if not cx then return end
    local px, py = GetCursorPosition()
    -- Cursor uses physical pixels; minimap coordinates use effective scale.
    local scale = Minimap:GetEffectiveScale()
    if not scale or scale == 0 then return end
    px, py = px / scale, py / scale
    db.buttonAngle = math.deg(math.atan2(py - cy, px - cx)) % 360
    placeButton()
end

local function onButtonDragStart(self)
    self:LockHighlight()
    GameTooltip:Hide()
    self:SetScript("OnUpdate", onButtonDragUpdate)
end

local function onButtonDragStop(self)
    self:SetScript("OnUpdate", nil)
    self:UnlockHighlight()
end

local function onButtonEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Hide Minimap Forever", .4, .85, 1)
    GameTooltip:AddLine("Left-click: Enable / disable", 1, 1, 1)
    GameTooltip:AddLine("Right-click: Settings", 1, 1, 1)
    GameTooltip:AddLine("Drag: Move around minimap", 1, 1, 1)
    GameTooltip:Show()
end

local function onButtonLeave()
    GameTooltip:Hide()
end

local function createButton()
    -- The button belongs to Minimap: it fades and hides with its parent.
    button = CreateFrame("Button", "HideMinimapForeverButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    -- Standard bordered LibDBIcon-style minimap button.
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\Ability_Stealth")
    icon:SetTexCoord(.05, .95, .05, .95)
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button:SetScript("OnClick", onButtonClick)
    button:SetScript("OnDragStart", onButtonDragStart)
    button:SetScript("OnDragStop", onButtonDragStop)
    button:SetScript("OnEnter", onButtonEnter)
    button:SetScript("OnLeave", onButtonLeave)

    placeButton()
end

-- ============================================================================
-- Core logic: independent fades, hide/show, and addon controls
-- ============================================================================

-- Each layer has its own fade clock and may opt into hiding at fade-out completion.
-- Cluster surroundings fade visually only; only Minimap may be physically hidden.
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
        -- Complete hide applies to Minimap only: fade to zero before Hide().
        -- Surrounding cluster elements use independent idle opacity.
        local target = idle and db[part.prefix .. "FadeLevel"] or 1
        if idle and part.prefix == "minimap" and db.completelyHide then
            target = 0
        end
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
    -- Preserve the current idle countdown and fade progress when settings change.
    -- update() will retarget animations only when their desired opacity changes.
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
    clearLegacySettings()
    for key, spec in pairs(settings) do db[key] = spec.default end
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

-- ============================================================================
-- Events, initialization, and slash commands
-- ============================================================================

local function isAnimating()
    for _, part in ipairs(parts) do
        if part.target ~= nil and math.abs(part.alpha - part.target) > .0001 then
            return true
        end
    end
    return false
end

-- Poll slowly at rest (hover and movement still need polling), but keep
-- smooth updates during animations. No per-frame allocations are necessary.
A:SetScript("OnUpdate", function(_, dt)
    accumulator = accumulator + dt
    local interval
    if not db or not db.enabled or forcedShown then
        interval = UPDATE_INACTIVE
    elseif isAnimating() then
        interval = UPDATE_ACTIVE
    else
        interval = UPDATE_IDLE
    end
    if accumulator < interval then return end
    local step = accumulator
    accumulator = 0
    update(step)
end)

-- ADDON_LOADED happens after this addon's SavedVariables are restored.
-- PLAYER_LOGIN is the fallback and the first point where Blizzard's minimap
-- frames can safely be initialized. Both event paths are idempotent.
local function initializeFrames()
    if initialized then return end
    if not db then copyDefaults() end

    cluster = MinimapCluster or Minimap
    if not cluster or not Minimap then
        print("Hide Minimap Forever: minimap frame not found")
        return
    end

    initialized = true
    collectClusterElements()
    parts = {
        {prefix = "minimap", alpha = 1, target = nil, startAlpha = 1, fadeElapsed = 0},
        {prefix = "cluster", alpha = 1, target = nil, startAlpha = 1, fadeElapsed = 0},
    }
    for _, part in ipairs(parts) do setPartAlpha(part, 1) end
    createHotspot()
    createButton()
    if ns.BuildOptions then ns.BuildOptions() end
    A:Refresh()
    if ns.RefreshOptions then ns.RefreshOptions() end
end

A:RegisterEvent("ADDON_LOADED")
A:RegisterEvent("PLAYER_LOGIN")
A:SetScript("OnEvent", function(_, event, loadedAddon)
    if event == "ADDON_LOADED" then
        if loadedAddon ~= addonName then return end
        copyDefaults()
        A:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        -- Fallback if SavedVariables were not initialized at ADDON_LOADED.
        if not db then copyDefaults() end
        initializeFrames()
        A:UnregisterEvent("PLAYER_LOGIN")
    end
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
