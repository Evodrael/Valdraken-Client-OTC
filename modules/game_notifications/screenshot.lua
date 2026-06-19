-- LuaFormatter off
local ScreenshotType = {
    NONE = 0,
    ACHIEVEMENT = 1,
    BESTIARY_ENTRY_COMPLETED = 2,
    BESTIARY_ENTRY_UNLOCKED = 3,
    BOSS_DEFEATED = 4,
    DEATH_PVE = 5,
    DEATH_PVP = 6,
    LEVEL_UP = 7,
    PLAYER_KILL_ASSIST = 8,
    PLAYER_KILL = 9,
    PLAYER_ATTACKING = 10,
    TREASURE_FOUND = 11,
    SKILL_UP = 12,
    HIGHEST_DAMAGE_DEALT = 13,
    HIGHEST_HEALING_DONE = 14,
    LOW_HEALTH = 15,
    GIFT_OF_LIFE_TRIGGERED = 16
}

local AutoScreenshotEvents = {
    {id = ScreenshotType.LEVEL_UP, label = "Level Up", enableDefault = true},
    {id = ScreenshotType.SKILL_UP, label = "Skill Up", enableDefault = true},
    {id = ScreenshotType.ACHIEVEMENT, label = "Achievement", enableDefault = true},
    {id = ScreenshotType.BESTIARY_ENTRY_UNLOCKED, label = "Bestiary Entry Unlocked", enableDefault = false},
    {id = ScreenshotType.BESTIARY_ENTRY_COMPLETED, label = "Bestiary Entry Completed", enableDefault = false},
    {id = ScreenshotType.TREASURE_FOUND, label = "Treasure Found", enableDefault = false},
    {id = -99, label = "Valuable Loot", enableDefault = false},
    {id = ScreenshotType.BOSS_DEFEATED, label = "Boss Defeated", enableDefault = false},
    {id = ScreenshotType.DEATH_PVE, label = "Death PvE", enableDefault = true},
    {id = ScreenshotType.DEATH_PVP, label = "Death PvP", enableDefault = false},
    {id = ScreenshotType.PLAYER_KILL, label = "Player Kill", enableDefault = false},
    {id = ScreenshotType.PLAYER_KILL_ASSIST, label = "Player Kill Assist", enableDefault = false},
    {id = ScreenshotType.PLAYER_ATTACKING, label = "Player Attacking", enableDefault = false},
    {id = ScreenshotType.HIGHEST_DAMAGE_DEALT, label = "Highest Damage Dealt", enableDefault = false},
    {id = ScreenshotType.HIGHEST_HEALING_DONE, label = "Highest Healing Done", enableDefault = false},
    {id = ScreenshotType.LOW_HEALTH, label = "Low Health", enableDefault = false},
    {id = ScreenshotType.GIFT_OF_LIFE_TRIGGERED, label = "Gift of Life Triggered", enableDefault = true}
}
-- LuaFormatter on

local autoScreenshotDirName = "auto_screenshots"
local autoScreenshotDir = nil

local optionPanel = nil
local screenshotListener = nil
local scheduledScreenshotEvent = nil

local function clientOptionsHasPanelApi()
    return modules
        and modules.client_options
        and type(modules.client_options.addButton) == 'function'
        and type(modules.client_options.removeButton) == 'function'
        and type(modules.client_options.getPanel) == 'function'
end

local function getSettingBool(key, default)
    if g_settings and g_settings.getBoolean then
        local v = g_settings.getBoolean(key)
        if v == nil then return default end
        return v
    end
    return default
end

function destroyOptionsModule()
    if clientOptionsHasPanelApi() then
        pcall(modules.client_options.removeButton, "Misc.", "Screenshot")
    end
    if optionPanel and not optionPanel:isDestroyed() then
        optionPanel:destroy()
    end
    optionPanel = nil
end

function screenshot_onTerminate()
    destroyOptionsModule()

    if screenshotListener and LocalPlayer then
        disconnect(LocalPlayer, { onTakeScreenshot = screenshotListener })
        screenshotListener = nil
    end
    if scheduledScreenshotEvent then
        removeEvent(scheduledScreenshotEvent)
        scheduledScreenshotEvent = nil
    end
end

function screenshot_onGameStart()
    if g_game.getClientVersion() < 1180 then
        return
    end

    autoScreenshotDir = g_resources.getWriteDir() .. "/" .. autoScreenshotDirName

    -- Load saved per-event toggles into runtime currentBoolean
    for _, screenshotEvent in ipairs(AutoScreenshotEvents) do
        local settingKey = screenshotEvent.label:gsub("%s+", "")
        screenshotEvent.currentBoolean = getSettingBool(settingKey, screenshotEvent.enableDefault)
    end

    -- Only build the options panel if client_options exposes the panel/button API.
    if clientOptionsHasPanelApi() then
        local ok, panel = pcall(function()
            return g_ui.loadUI('/modules/game_notifications/screenshot', modules.client_options.getPanel())
        end)
        if ok and panel then
            optionPanel = panel
            for _, screenshotEvent in ipairs(AutoScreenshotEvents) do
                local label = g_ui.createWidget("ScreenshotType", optionPanel.allCheckBox)
                local settingKey = screenshotEvent.label:gsub("%s+", "")
                local enabled = getSettingBool(settingKey, screenshotEvent.enableDefault)
                label.text:setText(screenshotEvent.label)
                label.enabled:setChecked(enabled)
                label.enabled:setId(screenshotEvent.id)
                screenshotEvent.currentBoolean = enabled
            end

            local enableSs = optionPanel:recursiveGetChildById("enableScreenshots")
            if enableSs then enableSs:setChecked(getSettingBool("enableScreenshots", false)) end
            local onlyGame = optionPanel:recursiveGetChildById("onlyCaptureGameWindow")
            if onlyGame then onlyGame:setChecked(getSettingBool("onlyCaptureGameWindow", false)) end

            local keepBlk = optionPanel:recursiveGetChildById("keepBlacklog")
            if keepBlk then keepBlk:disable() end

            pcall(modules.client_options.addButton, "Misc.", "Screenshot", optionPanel)
        else
            g_logger.info("[game_notifications] Failed to load screenshot options panel; running headless.")
        end
    end

    if not g_resources.directoryExists(autoScreenshotDir) then
        g_resources.makeDir(autoScreenshotDirName)
    end

    -- Always register the listener (regardless of panel availability).
    if LocalPlayer then
        screenshotListener = function(...) onScreenShot(...) end
        connect(LocalPlayer, { onTakeScreenshot = screenshotListener })
    end
end

function screenshot_onGameEnd()
    if g_game.getClientVersion() < 1180 then
        return
    end

    if optionPanel and not optionPanel:isDestroyed() then
        local onlyGame = optionPanel:recursiveGetChildById("onlyCaptureGameWindow")
        if onlyGame then g_settings.set("onlyCaptureGameWindow", onlyGame:isChecked()) end
        local enableSs = optionPanel:recursiveGetChildById("enableScreenshots")
        if enableSs then g_settings.set("enableScreenshots", enableSs:isChecked()) end
        destroyOptionsModule()
    end

    for _, screenshotEvent in ipairs(AutoScreenshotEvents) do
        local key = screenshotEvent.label:gsub("%s+", "")
        if screenshotEvent.currentBoolean ~= nil then
            g_settings.set(key, screenshotEvent.currentBoolean)
        end
    end

    if screenshotListener and LocalPlayer then
        disconnect(LocalPlayer, { onTakeScreenshot = screenshotListener })
        screenshotListener = nil
    end
    if scheduledScreenshotEvent then
        removeEvent(scheduledScreenshotEvent)
        scheduledScreenshotEvent = nil
    end
end

function onUICheckBox(widget, checked)
    if not widget then
        return
    end
    local id = tonumber(widget:getId())
    for _, screenshotEvent in ipairs(AutoScreenshotEvents) do
        if screenshotEvent.id == id then
            screenshotEvent.currentBoolean = checked
            break
        end
    end
end

function resetValues()
    for _, screenshotEvent in ipairs(AutoScreenshotEvents) do
        local key = screenshotEvent.label:gsub("%s+", "")
        if screenshotEvent.currentBoolean ~= nil then
            g_settings.set(key, screenshotEvent.currentBoolean)
        end
    end
    if not optionPanel or optionPanel:isDestroyed() then
        return
    end
    for _, selectedCheckBox in pairs(optionPanel.allCheckBox:getChildren()) do
        for _, child in pairs(selectedCheckBox:getChildren()) do
            if child:getStyle().__class == 'UICheckBox' then
                local id = tonumber(child:getId())
                if id then
                    for _, screenshotEvent in ipairs(AutoScreenshotEvents) do
                        if screenshotEvent.id == id then
                            child:setChecked(screenshotEvent.enableDefault)
                            break
                        end
                    end
                end
            end
        end
    end
end

function onScreenShot(stype)
    local enabled
    if optionPanel and not optionPanel:isDestroyed() and optionPanel.Opciones3 and optionPanel.Opciones3.enableScreenshots then
        enabled = optionPanel.Opciones3.enableScreenshots:isChecked()
    else
        enabled = getSettingBool("enableScreenshots", false)
    end
    if not enabled then
        return
    end

    local localPlayer = g_game.getLocalPlayer()
    if not localPlayer then return end
    local name = localPlayer:getName() or "player"
    local level = localPlayer:getLevel() or 1

    for _, screenshotEvent in ipairs(AutoScreenshotEvents) do
        if screenshotEvent.id == stype and screenshotEvent.currentBoolean then
            local screenshotName = name .. level .. "_" ..
                                       screenshotEvent.label:gsub("%s+", "") .. "_" ..
                                       os.date("%Y%m%d%H%M%S") .. ".png"
            takeScreenshot("/" .. autoScreenshotDirName .. "/" .. screenshotName)
            return
        end
    end
end

function takeScreenshot(name)
    if not g_game.isOnline() then
        return
    end
    if not name:lower():match("%.png$") then
        name = name .. ".png"
    end

    if scheduledScreenshotEvent then
        removeEvent(scheduledScreenshotEvent)
        scheduledScreenshotEvent = nil
    end

    scheduledScreenshotEvent = scheduleEvent(function()
        local onlyMap = false
        if optionPanel and not optionPanel:isDestroyed() then
            local w = optionPanel:recursiveGetChildById("onlyCaptureGameWindow")
            if w then onlyMap = w:isChecked() end
        else
            onlyMap = getSettingBool("onlyCaptureGameWindow", false)
        end
        if onlyMap and g_app.doMapScreenshot then
            g_app.doMapScreenshot(name)
        elseif g_app.doScreenshot then
            g_app.doScreenshot(name)
        end
        scheduledScreenshotEvent = nil
    end, 50)

    local directory = g_resources.getWriteDir():gsub("[/\\]+", "\\") .. autoScreenshotDirName
    local message = string.format("Screenshot has been saved to '%s'.", directory)

    if modules and modules.game_console and modules.game_console.addText then
        local console = modules.game_console
        console.addText(message, console.SpeakTypesSettings, tr("Server Log"))
    end
    if modules and modules.game_textmessage and modules.game_textmessage.displayStatusMessage then
        modules.game_textmessage.displayStatusMessage(message)
    end
end

function OpenFolder()
    if not autoScreenshotDir then
        autoScreenshotDir = g_resources.getWriteDir() .. "/" .. autoScreenshotDirName
    end
    local directory = g_resources.getWriteDir():gsub("[/\\]+", "\\") .. autoScreenshotDirName
    if g_platform and g_platform.openDir then
        g_platform.openDir(directory)
    end
end
