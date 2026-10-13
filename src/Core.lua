local addonName, ns = ...
local A = CreateFrame("Frame")
ns.core = A

local defaults = {
    enabled = true,
    completelyHide = true,
    idleDelay = 2,
    showWhileMoving = false,
    showButton = true,
    buttonAngle = 210,
    minimapFadeInDuration = 0.50,
    minimapFadeOutDuration = 0.60,
    minimapFadeLevel = 0,
    clusterFadeInDuration = 0.50,
    clusterFadeOutDuration = 0.90,
    clusterFadeLevel = 0,
}

local db, cluster, hotspot, button
local parts = {}
local clusterElements = {}
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

local function restoreMinimap()
    if internallyHidden and Minimap then
        internallyHidden = false
        Minimap:Show()
    end
end

-- Minimap is inside MinimapCluster. Changing the cluster's alpha also
-- changes the Minimap's *effective* alpha, making its own slider ineffective.
-- Instead, fade the cluster's other direct children and texture/font regions.
-- Preserve their original alpha so restoring the UI respects Blizzard styling.
local function collectClusterElements()
    clusterElements = {}
    if not cluster or cluster == Minimap then return end

    -- Protect the direct child containing Minimap, even if another addon
    -- reparents it into an intermediate container inside MinimapCluster.
    local minimapBranch = Minimap
    while minimapBranch and minimapBranch:GetParent() ~= cluster do
        minimapBranch = minimapBranch:GetParent()
    end

    local function add(element)
        if element ~= minimapBranch and element ~= Minimap and element.SetAlpha then
            clusterElements[#clusterElements + 1] = {
                frame = element,
                originalAlpha = element:GetAlpha(),
            }
        end
    end
    for _, child in ipairs({ cluster:GetChildren() }) do add(child) end
    for _, region in ipairs({ cluster:GetRegions() }) do add(region) end
    cluster:SetAlpha(1)  -- keep parent alpha neutral for the Minimap
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
    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            if ns.OpenOptions then ns.OpenOptions() end
        else A:Toggle() end
    end)

    button:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local cx, cy = Minimap:GetCenter()
            if not cx then return end
            local px, py = GetCursorPosition()
            -- Cursor coordinates are physical screen pixels. Minimap center is
            -- already expressed in its effective-scale coordinate space.
            local scale = Minimap:GetEffectiveScale()
            if not scale or scale == 0 then return end
            px, py = px / scale, py / scale
            db.buttonAngle = math.deg(math.atan2(py - cy, px - cx)) % 360
            placeButton()
        end)
    end)

    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Hide Minimap Forever", .4, .85, 1)
        GameTooltip:AddLine("Left-click: Enable / disable", 1, 1, 1)
        GameTooltip:AddLine("Right-click: Settings", 1, 1, 1)
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