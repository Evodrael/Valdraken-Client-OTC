-- LuaFormatter off
local DEBUG_MODE = false
-- Diagnostic for the "same notification on every login" investigation.
-- Set to false once the culprit event is identified. Logs go to otclient.log.
local NOTIF_DIAG = false

local function debugPrint(...)
    if DEBUG_MODE then
        print("InfoBanner Debug:", ...)
    end
end

local OPEN_FRAMES = {
    "/modules/game_notifications/assets/images/infobanner/backdrop-infobanner-anim0",
    "/modules/game_notifications/assets/images/infobanner/backdrop-infobanner-anim1",
    "/modules/game_notifications/assets/images/infobanner/backdrop-infobanner-anim2",
    "/modules/game_notifications/assets/images/infobanner/backdrop-infobanner-anim3",
    "/modules/game_notifications/assets/images/infobanner/backdrop-infobanner-anim4",
    "/modules/game_notifications/assets/images/infobanner/backdrop-infobanner-anim5",
    "/modules/game_notifications/assets/images/infobanner/backdrop-infobanner-anim6",
    "/modules/game_notifications/assets/images/infobanner/backdrop-infobanner-anim7"
}

local MAX_WIDTH = 289
local BANNER_HEIGHT = 88
local FRAME_MS = 45
local DEFAULT_HOLD_MS = 3000
local FADE_IN_MS = 400
local FADE_OUT_MS = 300
local FADE_INTERVAL_MS = 20
local ICON_SHOW_PROGRESS = 0.25
local ICON_HIDE_PROGRESS = 0.25
local BANNER_MARGIN_OFFSET = 20
local ANIM_OFFSET = 10
local TOTAL_FRAMES = #OPEN_FRAMES

local eventCategory = {
    CLIENT_EVENT_TYPE_SIMPLE = 1,
    CLIENT_EVENT_TYPE_ACHIEVEMENT = 2,
    CLIENT_EVENT_TYPE_TITLE = 3,
    CLIENT_EVENT_TYPE_LEVEL = 4,
    CLIENT_EVENT_TYPE_SKILL = 5,
    CLIENT_EVENT_TYPE_BESTIARY = 6,
    CLIENT_EVENT_TYPE_BOSSTIARY = 7,
    CLIENT_EVENT_TYPE_QUEST = 8,
    CLIENT_EVENT_TYPE_COSMETIC = 9,
    CLIENT_EVENT_TYPE_PROFICIENCY = 10,
    CLIENT_EVENT_TYPE_LAST = 11
}

local eventType = {
    CLIENT_EVENT_NONE = 0,
    CLIENT_EVENT_BOSSDEFEATED = 1,
    CLIENT_EVENT_DEATHPVE = 2,
    CLIENT_EVENT_DEATHPVP = 3,
    CLIENT_EVENT_PLAYERKILLASSIST = 4,
    CLIENT_EVENT_PLAYERKILL = 5,
    CLIENT_EVENT_PLAYERATTACKING = 6,
    CLIENT_EVENT_TREASUREFOUND = 7,
    CLIENT_EVENT_GIFTOFLIFE = 8,
    CLIENT_EVENT_ATTACKSTOPPED = 9,
    CLIENT_EVENT_CAPACITYLIMIT = 10,
    CLIENT_EVENT_OUTOFAMMO = 11,
    CLIENT_EVENT_TARGETTOOCLOSE = 12,
    CLIENT_EVENT_OUTOFSOULPOINTS = 13,
    CLIENT_EVENT_TUTORIALCOMPLETE = 14,
    CLIENT_EVENT_LAST = 15
}

local skinType = {
    outfit = 0,
    addon1 = 1,
    addon2 = 2,
    mount = 3
}

local SkillId = {
    Magic = 1,
    Sword = 2,
    Club = 3,
    Axe = 4,
    Fist = 5,
    Distance = 6,
    Shielding = 7,
    Fishing = 8
}

local skillNames = {
    [SkillId.Magic]     = { name = "Magic Level",        icon = "magic" },
    [SkillId.Sword]     = { name = "Sword Fighting",     icon = "sword" },
    [SkillId.Club]      = { name = "Club Fighting",      icon = "club" },
    [SkillId.Axe]       = { name = "Axe Fighting",       icon = "axe" },
    [SkillId.Fist]      = { name = "Fist Fighting",      icon = "fist" },
    [SkillId.Distance]  = { name = "Distance Fighting",  icon = "distance" },
    [SkillId.Shielding] = { name = "Shielding",          icon = "shielding" },
    [SkillId.Fishing]   = { name = "Fishing",            icon = "fishing" }
}

local infoPopUp = {
    [eventCategory.CLIENT_EVENT_TYPE_COSMETIC] = {
        {
            title = "Outfit Unlocked",
            description = "You have unlocked '%s'",
            creatureId = '%d',
            img = "/modules/game_notifications/assets/images/nodo/icon-infobanner-unlock"
        }
    },
    [eventCategory.CLIENT_EVENT_TYPE_BOSSTIARY] = {
        {
            title = "Bosstiary Progress",
            description = "You have progressed '%s'",
            raceId = '%d',
            img = "/modules/game_notifications/assets/images/nodo/icon-infobanner-unlock"
        }
    },
    [eventCategory.CLIENT_EVENT_TYPE_BESTIARY] = {
        {
            title = "Bestiary Progress",
            description = "You have progressed '%s'",
            raceId = '%d',
            img = "/modules/game_notifications/assets/images/nodo/icon-infobanner-unlock"
        }
    },
    [eventCategory.CLIENT_EVENT_TYPE_ACHIEVEMENT] = {
        {
            title = "New Achievement",
            description = "You have earned '%s'",
            img = "/modules/game_notifications/assets/images/nodo/icon-infobanner-achievements"
        }
    },
    [eventCategory.CLIENT_EVENT_TYPE_TITLE] = {
        {
            title = "Title Gained",
            description = "You have earned '%s'",
            img = "/modules/game_notifications/assets/images/nodo/icon-infobanner-title"
        }
    },
    [eventCategory.CLIENT_EVENT_TYPE_PROFICIENCY] = {
        {
            title = "Weapon Proficiency",
            description = "you have improved '%s'",
            itemId = '%d',
            img = "/modules/game_notifications/assets/images/nodo/icon-infobanner-unlock"
        }
    },
    [eventCategory.CLIENT_EVENT_TYPE_QUEST] = {
        [true] = {
            title = "Quest Completed",
            description = "You have finished '%s'",
            img = "/modules/game_notifications/assets/images/nodo/icon-infobanner-quests"
        },
        [false] = {
            title = "Quest Started",
            description = "You have begun '%s'",
            img = "/modules/game_notifications/assets/images/nodo/icon-infobanner-quests"
        }
    },
    [eventCategory.CLIENT_EVENT_TYPE_LEVEL] = {
        {
            title = "Level %d!",
            description = "You gained hit points, mana, and capacity.",
            img = "/modules/game_notifications/assets/images/nodo/icon-infobanner-levelup"
        }
    },
    [eventCategory.CLIENT_EVENT_TYPE_SKILL] = {
        {
            title = "%s",
            description = "your skill has advanced to level %d",
            img = "/modules/game_notifications/assets/images/nodo/icon-infobanner-skill-%s"
        }
    },
    [eventCategory.CLIENT_EVENT_TYPE_SIMPLE] = {
        [eventType.CLIENT_EVENT_ATTACKSTOPPED] = {
            title = "Attack Stopped",
            description = "You are no longer attacking.",
            img = "/modules/game_notifications/assets/images/nodo/icon-infobanner-hint"
        },
        [eventType.CLIENT_EVENT_CAPACITYLIMIT] = {
            title = "Capacity Limit",
            description = "Remove items before adding new ones.",
            img = "/modules/game_notifications/assets/images/nodo/icon-infobanner-quests"
        },
        [eventType.CLIENT_EVENT_OUTOFAMMO] = {
            title = "Out of Ammunition",
            description = "You have no arrow or bolt equipped.",
            img = "/modules/game_notifications/assets/images/nodo/icon-infobanner-hint"
        },
        [eventType.CLIENT_EVENT_TARGETTOOCLOSE] = {
            title = "Target Too Close",
            description = "You are using a ranged auto-attack at melee distance.",
            img = "/modules/game_notifications/assets/images/nodo/icon-infobanner-hint"
        },
        [eventType.CLIENT_EVENT_OUTOFSOULPOINTS] = {
            title = "Out of Soul Points",
            description = "You don't have enough soul points to cast this spell.",
            img = "/modules/game_notifications/assets/images/nodo/icon-infobanner-hint"
        },
        [eventType.CLIENT_EVENT_TUTORIALCOMPLETE] = {
            title = "Off to New Shores",
            description = "Leave the village and set sail to start your real adventure.",
            img = "/modules/game_notifications/assets/images/nodo/icon-infobanner-offtonewshores"
        }
    }
}
-- LuaFormatter on

notificationsController = notificationsController or {}
notificationsController.event = nil
notificationsController.state = "idle"
notificationsController.queue = {}
notificationsController.widgets = {}
notificationsController.simpleEventCooldowns = {}

local function showInfoBannerEnabled()
    local v
    if Options and Options.getOption then
        v = Options.getOption('showInfoBanner')
    end
    if v == nil then
        v = true
    end
    return v
end

local function getTopBarHeight()
    local ok, topBar = pcall(function()
        if modules and modules.game_topbar and modules.game_topbar.getTopBar then
            return modules.game_topbar.getTopBar()
        end
        return nil
    end)
    if ok and topBar and not topBar:isDestroyed() then
        return topBar:getHeight() or 0
    end
    return 0
end

-- Banner-skill-id (server-side numbering used by 0x75) → LocalPlayer Skill enum.
--   1=Magic (no LocalPlayer enum; use getMagicLevel)
--   2=Sword  → Skill.Sword  (2)
--   3=Club   → Skill.Club   (1)
--   4=Axe    → Skill.Axe    (3)
--   5=Fist   → Skill.Fist   (0)
--   6=Distance → Skill.Distance (4)
--   7=Shielding → Skill.Shielding (5)
--   8=Fishing → Skill.Fishing (6)
local BANNER_SKILL_TO_PLAYER_SKILL = {
    [2] = 2, -- Sword
    [3] = 1, -- Club
    [4] = 3, -- Axe
    [5] = 0, -- Fist
    [6] = 4, -- Distance
    [7] = 5, -- Shielding
    [8] = 6, -- Fishing
}

-- Per-character high-water marks so we drop replays/duplicates. Server
-- sometimes re-sends "Magic Level 83" on login or pushes events with stale
-- values; the player only ever cares about *new* progress on the *local*
-- character. We persist these to g_settings so a relog doesn't bring the same
-- banner back.
local lastBannerLevel = 0
local lastBannerMagic = 0
local lastBannerSkill = {}
local seenSimpleKeys  = {}   -- string set: quest names, achievements, etc.
local currentCharKey  = nil

local function persistenceKey(charName)
    return 'notificationBanner_' .. tostring(charName or 'unknown')
end

local function safeJsonEncode(t)
    if not json or not json.encode then return nil end
    local ok, encoded = pcall(json.encode, t)
    return ok and encoded or nil
end

local function safeJsonDecode(str)
    if not json or not json.decode then return nil end
    local ok, decoded = pcall(json.decode, str)
    return ok and decoded or nil
end

local function loadPersistedSeen(charName)
    if not g_settings or not g_settings.exists then return end
    local key = persistenceKey(charName)
    if not g_settings.exists(key) then return end
    local raw = g_settings.getString(key)
    local data = raw and safeJsonDecode(raw)
    if type(data) ~= 'table' then return end
    lastBannerLevel = tonumber(data.level) or 0
    lastBannerMagic = tonumber(data.magic) or 0
    lastBannerSkill = {}
    if type(data.skills) == 'table' then
        for k, v in pairs(data.skills) do
            local id = tonumber(k)
            if id then lastBannerSkill[id] = tonumber(v) or 0 end
        end
    end
    seenSimpleKeys = {}
    if type(data.seen) == 'table' then
        for _, key in ipairs(data.seen) do
            seenSimpleKeys[tostring(key)] = true
        end
    end
end

local function savePersistedSeen()
    if not g_settings or not g_settings.set then return end
    if not currentCharKey then return end
    local seenList = {}
    for k in pairs(seenSimpleKeys) do
        seenList[#seenList + 1] = k
    end
    local payload = {
        level  = lastBannerLevel,
        magic  = lastBannerMagic,
        skills = lastBannerSkill,
        seen   = seenList,
    }
    local encoded = safeJsonEncode(payload)
    if encoded then
        g_settings.set(persistenceKey(currentCharKey), encoded)
        if g_settings.save then g_settings.save() end
    end
end

-- Sync helpers called by native LocalPlayer change handlers so the
-- persistent dedup marks track the *actual* player value. Necessary because
-- onGameStart fires before the server pushes player data — without these,
-- lastBannerLevel stays at 0 until the player levels up, and the very first
-- 0x75 "Magic Level 83" after login would slip through.
function infoBanner_syncLevel(level)
    level = tonumber(level) or 0
    if level > lastBannerLevel then
        lastBannerLevel = level
        savePersistedSeen()
    end
end

function infoBanner_syncMagic(level)
    level = tonumber(level) or 0
    if level > lastBannerMagic then
        lastBannerMagic = level
        savePersistedSeen()
    end
end

function infoBanner_syncSkill(bannerSkillId, level)
    bannerSkillId = tonumber(bannerSkillId) or 0
    level = tonumber(level) or 0
    if bannerSkillId <= 0 then return end
    if level > (lastBannerSkill[bannerSkillId] or 0) then
        lastBannerSkill[bannerSkillId] = level
        savePersistedSeen()
    end
end

-- Called from game_notifications.lua whenever the local player connects
-- (login, character swap). Seeds the dedup marks from disk (per-character
-- key) and falls back to the player's current values for any field we don't
-- have a record of yet — guarantees no replay on first login of a session,
-- and no replay on subsequent relogs either.
function infoBanner_resetForLocalPlayer(player)
    lastBannerLevel = 0
    lastBannerMagic = 0
    lastBannerSkill = {}
    seenSimpleKeys  = {}
    currentCharKey  = nil
    if not player then return end

    currentCharKey = player:getName() or 'unknown'
    loadPersistedSeen(currentCharKey)

    -- Fold in current LIVE values so the player's actual level/skills become
    -- the dedup baseline even if we had no previous record on disk.
    lastBannerLevel = math.max(lastBannerLevel, player:getLevel() or 0)
    lastBannerMagic = math.max(lastBannerMagic, player:getMagicLevel() or 0)
    for bannerId, playerSkillEnum in pairs(BANNER_SKILL_TO_PLAYER_SKILL) do
        local live = player:getSkillLevel(playerSkillEnum) or 0
        lastBannerSkill[bannerId] = math.max(lastBannerSkill[bannerId] or 0, live)
    end
    -- Persist the seeded values so even on a brand-new character entry the
    -- on-disk record starts at "current = no new banners deserved".
    savePersistedSeen()
end

-- Build a stable string key for non-numeric events (quest names, achievement
-- titles, etc.) so we can dedup them across relogs.
local function buildSimpleEventKey(eventCat, args)
    if eventCat == eventCategory.CLIENT_EVENT_TYPE_QUEST then
        local questName = tostring(args[1] or '')
        local isDone = (args[2] == 1 or args[2] == true) and 'done' or 'open'
        return 'quest:' .. isDone .. ':' .. questName
    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_ACHIEVEMENT then
        return 'achievement:' .. tostring(args[1] or '')
    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_TITLE then
        return 'title:' .. tostring(args[1] or '')
    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_COSMETIC then
        return string.format('cosmetic:%s:%s', tostring(args[1] or '0'), tostring(args[3] or '0'))
    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_BESTIARY then
        return string.format('bestiary:%s:%s', tostring(args[1] or '0'), tostring(args[2] or '0'))
    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_BOSSTIARY then
        return string.format('bosstiary:%s:%s', tostring(args[1] or '0'), tostring(args[2] or '0'))
    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_PROFICIENCY then
        return string.format('proficiency:%s:%s', tostring(args[1] or '0'), tostring(args[2] or ''))
    end
    return nil
end

-- Register a server-pushed event into the dedup tables without showing a
-- banner. Used during the login grace window so the server's replay of past
-- progress (Magic Level X, completed quests, achievements, ...) is recorded
-- as "already seen" instead of triggering banners on every relog.
function notificationsController:markSeenSilently(eventCat, ...)
    local args = { ... }
    if eventCat == eventCategory.CLIENT_EVENT_TYPE_LEVEL then
        local announced = tonumber(args[1]) or 0
        if announced > lastBannerLevel then
            lastBannerLevel = announced
            savePersistedSeen()
        end
    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_SKILL then
        local bannerSkillId = tonumber(args[1]) or 0
        local announced = tonumber(args[2]) or 0
        if bannerSkillId == 1 then
            if announced > lastBannerMagic then
                lastBannerMagic = announced
                savePersistedSeen()
            end
        elseif bannerSkillId > 0 then
            if announced > (lastBannerSkill[bannerSkillId] or 0) then
                lastBannerSkill[bannerSkillId] = announced
                savePersistedSeen()
            end
        end
    else
        local key = buildSimpleEventKey(eventCat, args)
        if key and not seenSimpleKeys[key] then
            seenSimpleKeys[key] = true
            savePersistedSeen()
        end
    end
end

function notificationsController:onClientEvent(eventCat, ...)
    if not showInfoBannerEnabled() then
        g_logger.debug("The server has sent infobaner, but the checkbox in client_options is disabled..")
        return
    end
    local args = { ... }
    local popupTemplate = nil

    -- Login grace: the native LocalPlayer handlers (onSkillChange/onLevelChange/
    -- onMagicLevelChange) call this directly, BYPASSING the grace router in
    -- game_notifications.lua. On login the server replays the player's full
    -- skill set as 0 -> realValue jumps, which looked like skill-ups and spammed
    -- a banner per skill on EVERY login. During the grace window we only record
    -- the value as already-seen (high-water mark) and never show a banner.
    if notification_isInGrace and notification_isInGrace() then
        self:markSeenSilently(eventCat, ...)
        return
    end

    if NOTIF_DIAG then
        local diagKey = buildSimpleEventKey(eventCat, args)
        g_logger.info(string.format(
            "[notif] onClientEvent cat=%s args=%s,%s,%s,%s grace=%s key=%s seen=%s char=%s",
            tostring(eventCat), tostring(args[1]), tostring(args[2]), tostring(args[3]),
            tostring(args[4]),
            tostring(notification_isInGrace and notification_isInGrace()),
            tostring(diagKey),
            tostring(diagKey ~= nil and seenSimpleKeys[diagKey] == true),
            tostring(currentCharKey)))
    end

    -- Drop replayed events: keep a persistent high-water mark per character.
    -- The comparison is ONLY against lastBannerLevel/Magic/Skill (loaded from
    -- disk + seeded with the player's value on login), NOT against the live
    -- player value — because by the time 0x75 arrives the server has already
    -- pushed the new level, so `localPlayer:getLevel()` already returns the
    -- announced number on real level-ups. Comparing against that would drop
    -- the legitimate banner.
    if eventCat == eventCategory.CLIENT_EVENT_TYPE_LEVEL then
        local announced = tonumber(args[1]) or 0
        if announced <= 0 or announced <= lastBannerLevel then
            return
        end
        lastBannerLevel = announced
        savePersistedSeen()
    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_SKILL then
        local bannerSkillId = tonumber(args[1]) or 0
        local announced = tonumber(args[2]) or 0
        if bannerSkillId == 1 then
            if announced <= 0 or announced <= lastBannerMagic then
                return
            end
            lastBannerMagic = announced
            savePersistedSeen()
        elseif bannerSkillId > 0 then
            if announced <= 0 or announced <= (lastBannerSkill[bannerSkillId] or 0) then
                return
            end
            lastBannerSkill[bannerSkillId] = announced
            savePersistedSeen()
        end
    else
        -- Non-numeric events: dedup by stable string key so quests /
        -- achievements / bestiary unlocks don't re-trigger after a relog.
        local key = buildSimpleEventKey(eventCat, args)
        if key then
            if seenSimpleKeys[key] then
                return
            end
            seenSimpleKeys[key] = true
            savePersistedSeen()
        end
    end

    if eventCat == eventCategory.CLIENT_EVENT_TYPE_SIMPLE then
        local evType = args[1]
        local now = g_clock.millis()
        local lastSent = self.simpleEventCooldowns[evType] or 0
        if now - lastSent < 5000 then
            return
        end
        self.simpleEventCooldowns[evType] = now
        popupTemplate = infoPopUp[eventCat] and infoPopUp[eventCat][evType]

    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_QUEST then
        local isCompleted = args[2] == 1 or args[2] == true
        popupTemplate = infoPopUp[eventCat] and infoPopUp[eventCat][isCompleted]

    elseif infoPopUp[eventCat] and infoPopUp[eventCat][1] then
        popupTemplate = infoPopUp[eventCat][1]
    end

    if not popupTemplate then
        debugPrint("No infoPopUp found for eventCat:", eventCat)
        return
    end

    local title = popupTemplate.title
    local description = popupTemplate.description
    local img = popupTemplate.img

    local extraData = {}

    if eventCat == eventCategory.CLIENT_EVENT_TYPE_QUEST then
        local questName = args[1]
        title = type(title) == 'string' and title:format(questName) or title
        description = type(description) == 'string' and description:format(questName) or description

    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_PROFICIENCY then
        local itemId = args[1]
        local message = args[2]
        description = type(description) == 'string' and description:format(message) or description
        if popupTemplate.itemId then
            extraData.itemId = itemId
        end

    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_LEVEL then
        local level = args[1]
        title = type(title) == 'string' and title:format(level) or title

    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_SKILL then
        local skillId = args[1]
        local level = args[2]
        local data = skillNames[skillId] or { name = "Skill", icon = "fist" }
        title = type(title) == 'string' and title:format(data.name) or title
        description = type(description) == 'string' and description:format(level) or description
        img = type(img) == 'string' and img:format(data.icon) or img

    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_COSMETIC then
        local lookType = args[1]
        local skinName = args[2]
        local sType = tonumber(args[3])
        if sType == 1 then
            skinName = skinName .. " (Addon 1)"
        elseif sType == 2 then
            skinName = skinName .. " (Addon 2)"
        end
        description = type(description) == 'string' and description:format(skinName) or description
        if popupTemplate.creatureId then
            extraData.creatureId = lookType
            extraData.skinType = sType
        end
    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_BESTIARY or eventCat == eventCategory.CLIENT_EVENT_TYPE_BOSSTIARY then
        local raceId = args[1]
        local progressLevel = args[2]
        description = type(description) == 'string' and description:format(progressLevel) or description
        if popupTemplate.raceId then
            extraData.raceId = raceId
        end

    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_ACHIEVEMENT then
        local name = args[1]
        description = type(description) == 'string' and description:format(name) or description

    elseif eventCat == eventCategory.CLIENT_EVENT_TYPE_TITLE then
        local name = args[1]
        description = type(description) == 'string' and description:format(name) or description
    end

    self:show(title, description, img, DEFAULT_HOLD_MS, extraData)
end

function infoBanner_onTerminate()
    if not notificationsController then return end
    notificationsController:hideImmediate()
    if notificationsController.ui then
        notificationsController:unloadUI()
    end
    notificationsController.simpleEventCooldowns = {}
end

function notificationsController:unloadUI()
    if self.ui and not self.ui:isDestroyed() then
        self.ui:destroy()
    end
    self.ui = nil
end

function notificationsController:ensure()
    if self.ui and not self.ui:isDestroyed() then
        return
    end

    local mapPanel = nil
    if modules and modules.game_interface and modules.game_interface.getMapPanel then
        mapPanel = modules.game_interface.getMapPanel()
    end

    if not mapPanel then
        debugPrint("No mapPanel available; cannot show banner.")
        return
    end

    self.ui = g_ui.createWidget('InfoBannerWindow', mapPanel)
    self.ui:hide()

    self._connectedPanels = {}

    local function onMapPanelResize()
        scheduleEvent(function()
            if notificationsController then
                notificationsController:updateBannerPosition()
            end
        end, 0)
    end
    self._onMapPanelResize = onMapPanelResize
    connect(mapPanel, { onGeometryChange = onMapPanelResize })
    table.insert(self._connectedPanels, mapPanel)

    self.widgets = {
        paper = self.ui:recursiveGetChildById('paper'),
        anim = self.ui:recursiveGetChildById('animation'),
        icon = self.ui:recursiveGetChildById('icon'),
        title = self.ui:recursiveGetChildById('title'),
        desc = self.ui:recursiveGetChildById('desc'),
        append = self.ui:recursiveGetChildById('append')
    }

    -- Build explicit fade lists (replaces querySelectorAll('.fade-*'))
    self.widgets.fadeTexts = {}
    if self.widgets.title then table.insert(self.widgets.fadeTexts, self.widgets.title) end
    if self.widgets.desc then table.insert(self.widgets.fadeTexts, self.widgets.desc) end
    if self.widgets.append then table.insert(self.widgets.fadeTexts, self.widgets.append) end

    self.widgets.fadeIcons = {}
    local icon = self.widgets.icon
    if icon then table.insert(self.widgets.fadeIcons, icon) end
    local icon2 = self.ui:recursiveGetChildById('icon2')
    if icon2 then table.insert(self.widgets.fadeIcons, icon2) end
    local icon3 = self.ui:recursiveGetChildById('icon3')
    if icon3 then table.insert(self.widgets.fadeIcons, icon3) end

    debugPrint("UI Widget Initialized/Ensured")
end

function notificationsController:updateBannerPosition()
    if not self.ui or self.ui:isDestroyed() then
        return
    end

    -- Horizontal centering is now handled by anchors.horizontalCenter on the
    -- InfoBannerWindow style, so we only need to push it down below the topbar.
    local statsBarHeight = getTopBarHeight()
    self.ui:setMarginTop(statsBarHeight + BANNER_MARGIN_OFFSET)

    debugPrint("Banner position updated: marginTop=", statsBarHeight + BANNER_MARGIN_OFFSET)
end

function notificationsController:cancelEvent()
    if self.event then
        removeEvent(self.event)
        self.event = nil
    end
end

function notificationsController:show(title, desc, img, holdMs, extraData)
    self:ensure()
    if not self.ui then
        return
    end
    debugPrint("Adding to queue ->", tostring(title))

    table.insert(self.queue, {
        title = title,
        desc = desc,
        img = img,
        holdMs = holdMs or DEFAULT_HOLD_MS,
        extraData = extraData or {}
    })
    if self.state == "idle" then
        self:processNext()
    end
end

function notificationsController:setWidgetsOpacity(widgets, opacity)
    for _, widget in ipairs(widgets) do
        if widget and not widget:isDestroyed() then
            widget:setOpacity(opacity)
        end
    end
end

function notificationsController:setContentOpacity(opacity)
    if self.widgets.fadeTexts then
        self:setWidgetsOpacity(self.widgets.fadeTexts, opacity)
    end
end

function notificationsController:setLeftIconsOpacity(opacity)
    if self.widgets.fadeIcons then
        self:setWidgetsOpacity(self.widgets.fadeIcons, opacity)
    end
end

function notificationsController:setPaperSize(width)
    local paper = self.widgets.paper
    if not paper or paper:isDestroyed() then return end
    paper:setWidth(width)
    paper:setImageRect({
        x = 0,
        y = 0,
        width = width,
        height = BANNER_HEIGHT
    })
end

function notificationsController:resetBanner()
    local w = self.ui
    w:setOpacity(1.0)
    w:show()
    self:setContentOpacity(0)
    self:setLeftIconsOpacity(0)
    self:setPaperSize(0)

    if self.widgets.append then
        self.widgets.append:destroyChildren()
    end

    local anim = self.widgets.anim
    if anim and not anim:isDestroyed() then
        anim:show()
        anim:setMarginLeft(0)
        anim:setImageSource(OPEN_FRAMES[1])
    end
end

function notificationsController:processNext()
    self:cancelEvent()
    if #self.queue == 0 then
        debugPrint("Queue empty. Unloading UI.")
        self.state = "idle"
        if self.ui then
            self:unloadUI()
            self.widgets = {}
        end
        return
    end
    self:updateBannerPosition()
    local data = table.remove(self.queue, 1)
    if not self.ui or self.ui:isDestroyed() then
        self.state = "idle"
        return
    end
    self:resetBanner()
    if data.img and self.widgets.icon then
        self.widgets.icon:setImageSource(data.img)
    end
    if self.widgets.title then self.widgets.title:setText(data.title or "") end
    if self.widgets.desc then self.widgets.desc:setText(data.desc or "") end

    if data.extraData and self.widgets.append then
        local appendW = self.widgets.append
        appendW:destroyChildren()

        if data.extraData.itemId then
            local itemId = data.extraData.itemId
            local w = g_ui.createWidget('UIItem', appendW)
            w:setSize({ width = 64, height = 64 })
            w:setItemId(itemId)
            w:setPhantom(true)
        elseif data.extraData.raceId then
            local raceId = data.extraData.raceId
            local raceData = nil
            if g_things and g_things.getRaceData then
                raceData = g_things.getRaceData(raceId)
            end
            if not raceData or (raceData.raceId == 0 and (not raceData.outfit or raceData.outfit.type == 0)) then
                g_logger.warning(string.format("Creature with race id %s was not found.", tostring(raceId)))
            else
                local creature = g_ui.createWidget('UICreature', appendW)
                creature:setSize({ width = 64, height = 64 })
                creature:setOutfit(raceData.outfit)
                creature:setPhantom(true)
            end
        elseif data.extraData.creatureId then
            local creatureId = data.extraData.creatureId
            local sType = data.extraData.skinType
            local creature = g_ui.createWidget('UICreature', appendW)
            creature:setSize({ width = 64, height = 64 })
            creature:setPhantom(true)
            if sType == skinType.outfit then
                creature:setOutfit({ type = creatureId })
            elseif sType == skinType.addon1 or sType == skinType.addon2 then
                creature:setOutfit({ type = creatureId, addons = sType })
            elseif sType == skinType.mount then
                creature:setOutfit({ type = creatureId })
            else
                creature:setOutfit({ type = creatureId })
            end
        end
    end

    self.state = "opening"
    debugPrint("Starting Banner ->", data.title)
    self:animateOpen(data.holdMs)
end

function notificationsController:animateOpen(holdMs)
    local frame = 1
    local iconsShown = false
    local anim = self.widgets.anim
    local function animate()
        if not self.ui or self.ui:isDestroyed() then
            return
        end
        frame = frame + 1
        if frame > TOTAL_FRAMES then
            self:finishOpening(holdMs)
            return
        end
        local progress = (frame - 1) / (TOTAL_FRAMES - 1)
        local currentWidth = MAX_WIDTH * progress
        self:setPaperSize(currentWidth)
        if anim and not anim:isDestroyed() then
            anim:setMarginLeft(currentWidth - ANIM_OFFSET)
            anim:setImageSource(OPEN_FRAMES[frame])
        end
        if not iconsShown and progress >= ICON_SHOW_PROGRESS then
            self:setLeftIconsOpacity(1)
            iconsShown = true
        end
        self.event = scheduleEvent(animate, FRAME_MS)
    end
    self.event = scheduleEvent(animate, FRAME_MS)
end

function notificationsController:finishOpening(holdMs)
    debugPrint("Opening finished. Holding.")
    self:setPaperSize(MAX_WIDTH)
    if self.widgets.anim and not self.widgets.anim:isDestroyed() then
        self.widgets.anim:hide()
    end
    self.state = "holding"
    self:fadeIn(holdMs)
end

function notificationsController:fadeIn(holdMs)
    local startTime = g_clock.millis()
    local function fadeInText()
        if not self.ui or self.ui:isDestroyed() then
            self:cancelEvent()
            self.state = "idle"
            return
        end
        local elapsed = g_clock.millis() - startTime
        local t = math.min(1, elapsed / FADE_IN_MS)
        self:setContentOpacity(t)
        if t < 1 then
            self.event = scheduleEvent(fadeInText, FADE_INTERVAL_MS)
        else
            self.event = scheduleEvent(function()
                if notificationsController then
                    notificationsController:close()
                end
            end, holdMs)
        end
    end
    self.event = scheduleEvent(fadeInText, FADE_INTERVAL_MS)
end

function notificationsController:close()
    if not self.ui or self.ui:isDestroyed() then
        return
    end
    self:cancelEvent()
    self.state = "closing"
    debugPrint("Closing phase.")
    self:fadeOut()
end

function notificationsController:fadeOut()
    local startTime = g_clock.millis()
    local function fadeOutText()
        if not self.ui or self.ui:isDestroyed() then
            self:cancelEvent()
            self.state = "idle"
            return
        end
        local elapsed = g_clock.millis() - startTime
        local t = math.min(1, elapsed / FADE_OUT_MS)
        self:setContentOpacity(1 - t)
        if t < 1 then
            self.event = scheduleEvent(fadeOutText, FADE_INTERVAL_MS)
        else
            self:animateClose()
        end
    end
    self.event = scheduleEvent(fadeOutText, FADE_INTERVAL_MS)
end

function notificationsController:animateClose()
    local frame = TOTAL_FRAMES
    local iconsHidden = false
    local anim = self.widgets.anim
    if anim and not anim:isDestroyed() then
        anim:show()
    end
    local function retract()
        if not self.ui or self.ui:isDestroyed() then
            self:cancelEvent()
            self.state = "idle"
            return
        end
        frame = frame - 1
        if frame < 1 then
            debugPrint("Retract finished. Running Exit.")
            self:setPaperSize(0)
            if anim and not anim:isDestroyed() then
                anim:setMarginLeft(0)
                anim:setImageSource(OPEN_FRAMES[1])
            end
            self:exit()
            return
        end
        local progress = (frame - 1) / (TOTAL_FRAMES - 1)
        local currentWidth = MAX_WIDTH * progress
        self:setPaperSize(currentWidth)
        if anim and not anim:isDestroyed() then
            anim:setMarginLeft(currentWidth - ANIM_OFFSET)
            anim:setImageSource(OPEN_FRAMES[frame])
        end
        if not iconsHidden and progress <= ICON_HIDE_PROGRESS then
            self:setLeftIconsOpacity(0)
            iconsHidden = true
        end
        self.event = scheduleEvent(retract, FRAME_MS)
    end
    self.event = scheduleEvent(retract, FRAME_MS)
end

function notificationsController:exit()
    if not self.ui or self.ui:isDestroyed() then
        return
    end
    self:cancelEvent()
    debugPrint("Exit finished.")
    self.ui:hide()
    self.ui:setOpacity(1)
    self.state = "idle"
    self:processNext()
end

function notificationsController:hideImmediate()
    self:cancelEvent()
    if self._onMapPanelResize and self._connectedPanels then
        for _, panel in ipairs(self._connectedPanels) do
            if panel and not panel:isDestroyed() then
                disconnect(panel, { onGeometryChange = self._onMapPanelResize })
            end
        end
    end
    self._onMapPanelResize = nil
    self._connectedPanels = {}
    if self.ui then
        self:unloadUI()
        self.widgets = {}
    end
    self.queue = {}
    self.state = "idle"
    debugPrint("Reset Immediate and Unloaded.")
end
