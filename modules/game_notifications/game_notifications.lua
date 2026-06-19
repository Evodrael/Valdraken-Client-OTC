-- Entry point for game_notifications (procedural port of LuminarisOT Controller).
-- Exposes the global `notificationsController` table that infobanner.lua and
-- screenshot.lua extend. No Controller class is used – OTCV8 doesn't have one.

notificationsController = notificationsController or {}

local connections = nil
local playerConnections = nil
local localPlayerRef = nil
-- Last seen values so we can detect level/skill *increases* (not just any
-- change) and avoid spamming the banner on initial login when values arrive.
local lastLevel = nil
local lastMagicLevel = nil
local lastSkills = {}

-- Wall-clock cutoff (millis) before which any server-sent client-event banner
-- (level up, skill up, bestiary, etc.) is registered in the dedup tables WITHOUT
-- being displayed. Set on onGameStart so the replay the server emits at login
-- doesn't spam the player with notifications about progress that happened in a
-- previous session. Bumped to 8000ms because some servers emit the replay batch
-- over several seconds.
local LOGIN_NOTIFICATION_GRACE_MS = 8000
local notificationGraceUntil = 0
function notification_isInGrace()
    return g_clock.millis() < notificationGraceUntil
end

-- Constants mirrored from infobanner.lua's eventCategory map; if the server
-- sends real onClientEvent packets these are the same shape.
local CLIENT_EVENT_TYPE_LEVEL = 4
local CLIENT_EVENT_TYPE_SKILL = 5
-- Skill IDs as the banner expects (see infobanner.lua skillNames):
--   1=Magic, 2=Sword, 3=Club, 4=Axe, 5=Fist, 6=Distance, 7=Shielding, 8=Fishing
local SKILL_ID_TO_BANNER = {
    [0] = 5, -- Skill.Fist
    [1] = 3, -- Skill.Club
    [2] = 2, -- Skill.Sword
    [3] = 4, -- Skill.Axe
    [4] = 6, -- Skill.Distance
    [5] = 7, -- Skill.Shielding
    [6] = 8, -- Skill.Fishing
}

local function fireBannerLevelUp(newLevel)
    if not notificationsController.onClientEvent then return end
    notificationsController:onClientEvent(CLIENT_EVENT_TYPE_LEVEL, newLevel)
end

local function fireBannerSkillUp(bannerSkillId, newLevel)
    if not notificationsController.onClientEvent then return end
    notificationsController:onClientEvent(CLIENT_EVENT_TYPE_SKILL, bannerSkillId, newLevel)
end

-- Native-event fallback: when the server doesn't push 0x75 (parseClientEvent),
-- we synthesize banners from LocalPlayer's onLevelChange/onSkillChange. This
-- keeps level-up and skill-up popups working on servers that haven't
-- implemented the 15.21+ ClientEvent system.
--
-- These handlers also keep the persistent dedup marks (lastBannerLevel etc.
-- in infobanner.lua) in sync with the actual player state — necessary because
-- onGameStart often fires before the server pushes player data, so the
-- initial seeding in infoBanner_resetForLocalPlayer sees getLevel()=0.
local nativeLevelHandler = function(player, level, percent)
    if lastLevel ~= nil and level > lastLevel then
        fireBannerLevelUp(level)
    end
    lastLevel = level
    if infoBanner_syncLevel then infoBanner_syncLevel(level) end
end

local nativeMagicHandler = function(player, level, percent)
    if lastMagicLevel ~= nil and level > lastMagicLevel then
        fireBannerSkillUp(1, level) -- banner expects 1 = Magic
    end
    lastMagicLevel = level
    if infoBanner_syncMagic then infoBanner_syncMagic(level) end
end

local nativeSkillHandler = function(player, skillId, level, percent)
    local previous = lastSkills[skillId]
    if previous ~= nil and level > previous then
        local bannerId = SKILL_ID_TO_BANNER[skillId]
        if bannerId then
            fireBannerSkillUp(bannerId, level)
        end
    end
    lastSkills[skillId] = level
    local bannerId = SKILL_ID_TO_BANNER[skillId]
    if bannerId and infoBanner_syncSkill then
        infoBanner_syncSkill(bannerId, level)
    end
end

local function connectLocalPlayer()
    local player = g_game.getLocalPlayer()
    if not player or player == localPlayerRef then return end
    if playerConnections and localPlayerRef then
        disconnect(localPlayerRef, playerConnections)
    end
    localPlayerRef = player
    playerConnections = {
        onLevelChange      = nativeLevelHandler,
        onMagicLevelChange = nativeMagicHandler,
        onSkillChange      = nativeSkillHandler,
    }
    connect(player, playerConnections)
    -- Seed last-seen so we don't fire a banner on the very first sample.
    lastLevel = player:getLevel()
    lastMagicLevel = player:getMagicLevel()
    lastSkills = {}
    for i = 0, 6 do lastSkills[i] = player:getSkillLevel(i) end
    -- Seed the server-event dedup marks too — without this the banner from
    -- 0x75 ("Magic Level 83") fires on every login since its dedup tracker
    -- has no record of what the local player already has.
    if infoBanner_resetForLocalPlayer then
        infoBanner_resetForLocalPlayer(player)
    end
end

local function disconnectLocalPlayer()
    if playerConnections and localPlayerRef then
        disconnect(localPlayerRef, playerConnections)
    end
    playerConnections = nil
    localPlayerRef = nil
    lastLevel = nil
    lastMagicLevel = nil
    lastSkills = {}
    if infoBanner_resetForLocalPlayer then
        infoBanner_resetForLocalPlayer(nil)
    end
end

function init()
    notificationsController.bannerQueue = {}
    notificationsController.bannerState = "idle"
    notificationsController.event = nil
    notificationsController.state = "idle"
    notificationsController.queue = {}
    notificationsController.widgets = {}
    notificationsController.simpleEventCooldowns = {}

    connections = {
        onClientEvent = function(...)
            -- During the initial login window, route the replayed server
            -- events through markSeenSilently so they register in the dedup
            -- tables (level/skill high-water marks, seenSimpleKeys) WITHOUT
            -- showing a banner. Past sessions' progress would otherwise spam
            -- the player on every login.
            if g_clock.millis() < notificationGraceUntil then
                if notificationsController and notificationsController.markSeenSilently then
                    notificationsController:markSeenSilently(...)
                end
                return
            end
            notificationsController:onClientEvent(...)
        end,
        onGameStart = function()
            notificationGraceUntil = g_clock.millis() + LOGIN_NOTIFICATION_GRACE_MS
            connectLocalPlayer()
            if screenshot_onGameStart then
                screenshot_onGameStart()
            end
        end,
        onGameEnd = function()
            disconnectLocalPlayer()
            if screenshot_onGameEnd then
                screenshot_onGameEnd()
            end
        end
    }

    connect(g_game, connections)

    if g_game.isOnline() then
        notificationGraceUntil = g_clock.millis() + LOGIN_NOTIFICATION_GRACE_MS
        connectLocalPlayer()
        if screenshot_onGameStart then screenshot_onGameStart() end
    end
end

function terminate()
    disconnectLocalPlayer()
    if connections then
        disconnect(g_game, connections)
        connections = nil
    end

    if screenshot_onTerminate then
        screenshot_onTerminate()
    end
    if infoBanner_onTerminate then
        infoBanner_onTerminate()
    end

    notificationsController = nil
end
