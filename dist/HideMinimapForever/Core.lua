local addonName, ns = ...
local A = CreateFrame("Frame")
ns.core = A

local defaults = {
    enabled = true,
    mode = "hide", -- "fade" keeps the minimap frame shown; "hide" calls Hide() after fading
    idleDelay = 1.5,
    fadeDuration = 0.35,
    hiddenAlpha = 0,
    showButton = true,
    buttonAngle = 210,
    showInCombat = true,
}

local db, cluster, hotspot, button
local elapsedIdle = 0
local alpha = 1
local targetAlpha = 1
local forcedShown = false
local internallyHidden = false
local lastTime = 0

local function clamp(x, a, b) return math.max(a, math.min(b, x)) end

local function copyDefaults()
    ForeverMinimapFadeDB = type(ForeverMinimapFadeDB) == "table" and ForeverMinimapFadeDB or {}
    db = ForeverMinimapFadeDB
    for k, v in pairs(defaults) do
        if db[k] == nil then db[k] = v end
    end
    db.mode = db.mode == "fade" and "fade" or "hide"
    db.idleDelay = clamp(tonumber(db.idleDelay) or defaults.idleDelay, 0, 15)
    db.fadeDuration = clamp(tonumber(db.fadeDuration) or defaults.fadeDuration, 0, 3)
    db.hiddenAlpha = clamp(tonumber(db.hiddenAlpha) or defaults.hiddenAlpha, 0, .7)
    db.buttonAngle = tonumber(db.buttonAngle) or defaults.buttonAngle
end

function ns.GetDB() return db end

function ns.Reset()
    if not db then return end
    for k, v in pairs(defaults) do db[k] = v end
    forcedShown = false
    A:Refresh()
    if ns.RefreshOptions then ns.RefreshOptions() end
end

local function placeButton()
    if not button or not cluster then return end
    local rad = math.rad(db.buttonAngle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", cluster, "CENTER", math.cos(rad) * 104, math.sin(rad) * 104)
end

local function showMap()
    if not cluster then return end
    if internallyHidden then
        internallyHidden = false
        cluster:Show()
    end
end

local function setAlpha(value)
    alpha = clamp(value, 0, 1)
    if cluster then cluster:SetAlpha(alpha) end
end

function A:Refresh()
    if not db or not cluster then return end
    if button then button:SetShown(db.showButton) placeButton() end
    elapsedIdle = 0
    showMap()
    if not db.enabled or forcedShown then
        targetAlpha = 1
        setAlpha(1)
    end
end

function A:Toggle()
    if not db then return end
    db.enabled = not db.enabled
    forcedShown = false
    self:Refresh()
    if ns.RefreshOptions then ns.RefreshOptions() end
    print("|cff65d6ffForever Minimap Fade:|r " .. (db.enabled and "enabled" or "disabled"))
end

function A:TogglePin()
    forcedShown = not forcedShown
    self:Refresh()
    print("|cff65d6ffForever Minimap Fade:|r " .. (forcedShown and "minimap pinned visible" or "automatic fade resumed"))
end

local function createHotspot()
    hotspot = CreateFrame("Frame", nil, UIParent)
    hotspot:SetSize(210, 210)
    hotspot:SetPoint("CENTER", cluster, "CENTER")
    hotspot:SetFrameStrata("HIGH")
    hotspot:EnableMouse(true)
    hotspot:SetScript("OnEnter", function()
        elapsedIdle = 0
        showMap()
        targetAlpha = 1
    end)
    -- Only capture mouse input while the minimap is fully hidden.
    hotspot:Hide()
end

local function createButton()
    button = CreateFrame("Button", "ForeverMinimapFadeButton", UIParent)
    button:SetSize(31, 31)
    button:SetFrameStrata("HIGH")
    button:SetMovable(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    button:RegisterForDrag("LeftButton")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\Spell_Nature_Sleep")
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
        elseif mouse == "MiddleButton" then
            A:TogglePin()
        else
            A:Toggle()
        end
    end)

    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            x, y = x / scale, y / scale
            local cx, cy = cluster:GetCenter()
            if not cx then return end
            db.buttonAngle = math.deg(math.atan2(y - cy, x - cx))
            placeButton()
        end)
    end)

    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Forever Minimap Fade", .4, .85, 1)
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
    if not db or not cluster then return end
    dt = math.min(dt, 0.1)
    lastTime = lastTime + dt
    if lastTime < .025 then return end
    dt, lastTime = lastTime, 0

    -- Do not alter the minimap while the addon is disabled.
    if not db.enabled or forcedShown then
        if internallyHidden or alpha < 1 then showMap() setAlpha(1) end
        hotspot:Hide()
        return
    end

    local inCombat = db.showInCombat and InCombatLockdown()
    local mouseOver = (cluster:IsShown() and cluster:IsMouseOver()) or hotspot:IsMouseOver() or (button and button:IsMouseOver())
    if mouseOver or inCombat then
        elapsedIdle = 0
        showMap()
        targetAlpha = 1
    else
        elapsedIdle = elapsedIdle + dt
        if elapsedIdle >= db.idleDelay then
            targetAlpha = (db.mode == "fade") and db.hiddenAlpha or 0
        end
    end

    if db.mode == "hide" and internallyHidden then
        hotspot:Show()
    else
        hotspot:Hide()
    end

    if math.abs(alpha - targetAlpha) > .001 then
        showMap()
        local duration = db.fadeDuration
        local step = duration == 0 and 1 or dt / duration
        if alpha < targetAlpha then setAlpha(math.min(targetAlpha, alpha + step))
        else setAlpha(math.max(targetAlpha, alpha - step)) end
    end

    if db.mode == "hide" and targetAlpha == 0 and alpha <= .001 and not internallyHidden then
        internallyHidden = true
        cluster:Hide()
        hotspot:Show()
    end
end)

A:RegisterEvent("PLAYER_LOGIN")

A:SetScript("OnEvent", function()
    copyDefaults()
    cluster = MinimapCluster or Minimap

    if not cluster then print("Forever Minimap Fade: minimap frame not found") return end

    setAlpha(1)

    createHotspot()

    createButton()

    if ns.BuildOptions then ns.BuildOptions() end
end)