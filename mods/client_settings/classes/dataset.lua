local function callVoip(method, ...)
    if g_voip and g_voip[method] then
        local ok, result = pcall(g_voip[method], ...)
        if ok then
            return result
        end
    end
    return nil
end

local function updateVoipLabel(id, text)
    local voipWindow = GameOptions:getLoadedWindow("voip")
    if not voipWindow then
        return
    end

    local widget = voipWindow:recursiveGetChildById(id)
    if widget then
        widget:setText(text)
    end
end

local function clampVolume(value)
    value = tonumber(value) or 0
    return math.max(0, math.min(100, value))
end

local function numericSoundType(name, fallback)
    if ENumericSoundType and ENumericSoundType[name] then
        return ENumericSoundType[name]
    end
    return fallback
end

local function setSoundLabel(windowId, labelId, text)
    local window = GameOptions:getLoadedWindow(windowId)
    if not window then
        return
    end

    local widget = window:recursiveGetChildById(labelId)
    if widget then
        widget:setText(text)
    end
end

local function setSoundWarningVisible(windowId, visible)
    local window = GameOptions:getLoadedWindow(windowId)
    if not window then
        return
    end

    local warning = window:recursiveGetChildById("warningVolumeLabel")
    if warning then
        warning:setVisible(visible)
    end
end

local function updateSoundWarnings(value)
    local visible = clampVolume(value) <= 0
    setSoundWarningVisible("battleSounds", visible)
    setSoundWarningVisible("uiSounds", visible)
end

local function setSoundChannelGain(channel, value)
    if g_sounds ~= nil and channel ~= nil then
        g_sounds.getChannel(channel):setGain(clampVolume(value) / 100.0)
    end
end

local function setSoundChannelsGain(channels, value)
    for _, channel in ipairs(channels) do
        setSoundChannelGain(channel, value)
    end
end

local function setSoundChannelEnabled(channel, value)
    if g_sounds ~= nil and channel ~= nil then
        g_sounds.getChannel(channel):setEnabled(value)
    end
end

local function setSoundChannelsEnabled(channels, value)
    for _, channel in ipairs(channels) do
        setSoundChannelEnabled(channel, value)
    end
end

local function applyEffectAlpha(value, ownOnly)
    local alpha = math.max(0, math.min(100, tonumber(value) or 100)) / 100.0
    g_client.setOwnSpellEffectAlpha(alpha)
    g_client.setOtherPlayerSpellEffectAlpha(ownOnly and 0 or alpha)
    g_client.setCreatureSpellEffectAlpha(ownOnly and 0 or alpha)
    g_client.setBossAreaCreatureEffectAlpha(ownOnly and 0 or alpha)
end

local function applyAntialiasingMode(value)
    local gameMapPanel = m_interface and m_interface.getMapPanel and m_interface.getMapPanel()
    local effectiveValue = value or 1

    g_app.setSmooth(value == 2)

    if gameMapPanel then
        gameMapPanel:setAntiAliasingMode(math.max(0, effectiveValue - 1))
    end

    return true
end

return {
    layout = {
        value = DEFAULT_LAYOUT,
    },

	graphicalCooldown = {
		value = true,
		apply = function(value)
            modules.game_actionbar.toggleCooldownOption()
            return true
        end,
	},

	showSecondTimestampsInConsole = {
		value = true,
		apply = function(value)
            modules.game_console.updateCurrentTab()
            return true
        end,
	},

	displayText = {
		value = true,
		apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawTexts(value)
            return true
        end,
	},

	allActionBar46 = {
		value = false,
		apply = function(value)
            local huds = {"actionBarShowLeft1", "actionBarShowLeft2", "actionBarShowLeft3"}
            for _, actionBar in pairs(huds) do
                local hud = GameOptions:getLoadedWindow("actionsBars"):recursiveGetChildById(actionBar)
                modules.game_actionbar.configureActionBar(actionBar, (value and hud:isChecked()))
            end
            return true
        end,
        tempApply = function(value)
            local huds = {"actionBarShowLeft1", "actionBarShowLeft2", "actionBarShowLeft3"}
            for _, hud in pairs(huds) do
              local actionBar = GameOptions:getLoadedWindow("actionsBars"):recursiveGetChildById(hud)
              if actionBar then
                actionBar:setColor(value and '$var-text-cip-color' or '$var-cip-inactive-color')
              end
            end
            return true
        end,
	},

	timeInventory = {
		value = true,
		apply = function(value) g_game.enableTimerInvetory(value) return true end,
	},

	showOwnHealth = {
		value = true,
		apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawOwnHealth(value)
            return true
        end,
	},

	storeAskBeforeBuyingProducts = {
		value = true,
	},

	openPrivateMessageInNewTab = {
		value = true,
	},

	showOthersMarks = {
		value = false,
	},

	showNPC = {
		value = true,
		apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawNpcIcon(value)
            return true
        end,
	},

	actionBarShowBottom1 = {
		value = true,
        apply = function(value)
            local parent = "allActionBar13"
            local allBox
            if TempOptions:getOption(parent) ~= nil then
              allBox = TempOptions:getOption(parent)
            elseif GameOptions:getOption(parent) ~= nil then
              allBox = GameOptions:getOption(parent)
            else
              allBox = false
            end

            modules.game_actionbar.configureActionBar('actionBarShowBottom1', allBox and value)
            return true
        end,
        tempApply = function(value)
            handleTmpActionBarShow('actionBarShowBottom1', value, "allActionBar13")
            return true
        end
	},

	actionBarShowBottom2 = {
		value = false,
        apply = function(value)
            local parent = "allActionBar13"
            local allBox
            if TempOptions:getOption(parent) ~= nil then
              allBox = TempOptions:getOption(parent)
            elseif GameOptions:getOption(parent) ~= nil then
              allBox = GameOptions:getOption(parent)
            else
              allBox = false
            end

            modules.game_actionbar.configureActionBar('actionBarShowBottom2', allBox and value)
            return true
        end,
        tempApply = function(value)
            handleTmpActionBarShow('actionBarShowBottom2', value, "allActionBar13")
            return true
        end
	},

	actionBarShowBottom3 = {
		value = false,
        apply = function(value)
            local parent = "allActionBar13"
            local allBox
            if TempOptions:getOption(parent) ~= nil then
              allBox = TempOptions:getOption(parent)
            elseif GameOptions:getOption(parent) ~= nil then
              allBox = GameOptions:getOption(parent)
            else
              allBox = false
            end

            modules.game_actionbar.configureActionBar('actionBarShowBottom3', allBox and value)
            return true
        end,
        tempApply = function(value)
            handleTmpActionBarShow('actionBarShowBottom3', value, "allActionBar13")
            return true
        end
	},

  actionBarShowLeft1 = {
		value = false,
        apply = function(value)
            local parent = "allActionBar46"
            local allBox
            if TempOptions:getOption(parent) ~= nil then
              allBox = TempOptions:getOption(parent)
            elseif GameOptions:getOption(parent) ~= nil then
              allBox = GameOptions:getOption(parent)
            else
              allBox = false
            end

            modules.game_actionbar.configureActionBar('actionBarShowLeft1', allBox and value)
            return true
        end,
        tempApply = function(value)
            handleTmpActionBarShow('actionBarShowLeft1', value, "allActionBar46")
            return true
        end
	},

  actionBarShowLeft2 = {
		value = false,
        apply = function(value)
            local parent = "allActionBar46"
            local allBox
            if TempOptions:getOption(parent) ~= nil then
              allBox = TempOptions:getOption(parent)
            elseif GameOptions:getOption(parent) ~= nil then
              allBox = GameOptions:getOption(parent)
            else
              allBox = false
            end

            modules.game_actionbar.configureActionBar('actionBarShowLeft2', allBox and value)
            return true
        end,
        tempApply = function(value)
            handleTmpActionBarShow('actionBarShowLeft2', value, "allActionBar46")
            return true
        end
	},

  actionBarShowLeft3 = {
		value = false,
        apply = function(value)
            local parent = "allActionBar46"
            local allBox
            if TempOptions:getOption(parent) ~= nil then
              allBox = TempOptions:getOption(parent)
            elseif GameOptions:getOption(parent) ~= nil then
              allBox = GameOptions:getOption(parent)
            else
              allBox = false
            end

            modules.game_actionbar.configureActionBar('actionBarShowLeft3', allBox and value)
            return true
        end,
        tempApply = function(value)
            handleTmpActionBarShow('actionBarShowLeft3', value, "allActionBar46")
            return true
        end
	},

  actionBarShowRight1 = {
		value = false,
        apply = function(value)
            local parent = "allActionBar79"
            local allBox
            if TempOptions:getOption(parent) ~= nil then
              allBox = TempOptions:getOption(parent)
            elseif GameOptions:getOption(parent) ~= nil then
              allBox = GameOptions:getOption(parent)
            else
              allBox = false
            end

            modules.game_actionbar.configureActionBar('actionBarShowRight1', allBox and value)
            return true
        end,
        tempApply = function(value)
            handleTmpActionBarShow('actionBarShowRight1', value, "allActionBar79")
            return true
        end
	},

	actionBarShowRight2 = {
		value = false,
        apply = function(value)
            local parent = "allActionBar79"
            local allBox
            if TempOptions:getOption(parent) ~= nil then
              allBox = TempOptions:getOption(parent)
            elseif GameOptions:getOption(parent) ~= nil then
              allBox = GameOptions:getOption(parent)
            else
              allBox = false
            end

            modules.game_actionbar.configureActionBar('actionBarShowRight2', allBox and value)
            return true
        end,
        tempApply = function(value)
            handleTmpActionBarShow('actionBarShowRight2', value, "allActionBar79")
            return true
        end
	},

	actionBarShowRight3 = {
		value = false,
        apply = function(value)
            local parent = "allActionBar79"
            local allBox
            if TempOptions:getOption(parent) ~= nil then
              allBox = TempOptions:getOption(parent)
            elseif GameOptions:getOption(parent) ~= nil then
              allBox = GameOptions:getOption(parent)
            else
              allBox = false
            end

            modules.game_actionbar.configureActionBar('actionBarShowRight3', allBox and value)
            return true
        end,
        tempApply = function(value)
            handleTmpActionBarShow('actionBarShowRight3', value, "allActionBar79")
            return true
        end
	},

	profile = {
		value = "1",
	},

	ambientLight = {
		value = 100,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setMinimumAmbientLight(value/100)
            gameMapPanel:setDrawLights(GameOptions:getOption('enableLights') and value < 100)
            return true
        end,
        tempApply = function(value)
            local graphics = GameOptions:getLoadedWindow('effects')
            local wid = graphics:recursiveGetChildById('enableLights')
            if wid and not wid:isChecked() then
              return true
            end

            local wid = graphics:recursiveGetChildById('ambientLabel')
            if wid then
              wid:setText(tr('Ambient Light: %d %%', value))
            end
            return true
        end,
	},

	hidePlayerBars = {
		value = false,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawPlayerBars(value)
            return true
        end,
	},

	storeNotification = {
		value = true,
	},

	containerPanel = {
		value = 8,
	},

	containerMoveToManagedContainerRecursive = {
		value = false,
	},

	showStatusOthersMessagesInConsole = {
		value = true,
	},

	walkTeleportDelay = {
		value = 200,
	},

	optimizationLevel = {
		value = 1,
        apply = function(value)
            g_adaptiveRenderer.setLevel(value - 2)
            return true
        end,
	},

	musicSoundVolume = {
		value = 100,
        apply = function(value)
            if g_sounds ~= nil then
                g_sounds.getChannel(SoundChannels.Music):setGain(value/100)
            end
            return true
        end,
	},

	hotkeyDelay = {
		value = 120,
        apply = function(value)
            local delayLabel =  GameOptions:getLoadedWindow('controls'):recursiveGetChildById('delayLabel')
            if delayLabel then
              delayLabel:setText(tr('Keyboard Delay: %d ms', value))
              if value < 50 then
                delayLabel:setColor("$var-text-cip-store-red")
              elseif value < 250 then
                delayLabel:setColor("$var-text-cip-color-orange")
              else
                delayLabel:setColor("$var-text-cip-color")
              end

              if not m_settings.getOption('hotkeyDelayNative') then
                rootWidget:getChildById("gameRootPanel"):setAutoRepeatDelay(math.max(0, tonumber(value)))
              end
            end

            if m_settings.getOption('hotkeyDelayNative') then
              delayLabel:setColor("$var-cip-inactive-color")
            end
            return true
        end,
        tempApply = function(value)
            local delayLabel =  GameOptions:getLoadedWindow('controls'):recursiveGetChildById('delayLabel')
            if delayLabel then
              delayLabel:setText(tr('Keyboard Delay: %d ms', value))
              if value < 50 then
                delayLabel:setColor("$var-text-cip-store-red")
              elseif value < 250 then
                delayLabel:setColor("$var-text-cip-color-orange")
              else
                delayLabel:setColor("$var-text-cip-color")
              end

              if not m_settings.getOption('hotkeyDelayNative') then
                rootWidget:getChildById("gameRootPanel"):setAutoRepeatDelay(math.max(0, tonumber(value)))
              end
            end
            return true
        end,
	},

	walkTurnDelay = {
		value = 100,
	},

	showLevelsInConsole = {
		value = true,
        apply = function(value)
            modules.game_console.updateCurrentTab()
            return true
        end,
	},

	allActionBar13 = {
		value = false,
        apply = function(value)
            local huds = {"actionBarShowBottom1", "actionBarShowBottom2", "actionBarShowBottom3"}
            for _, actionBar in pairs(huds) do
                local hud = GameOptions:getLoadedWindow("actionsBars"):recursiveGetChildById(actionBar)
                modules.game_actionbar.configureActionBar(actionBar, (value and hud:isChecked()))
            end
            return true
        end,
        tempApply = function(value)
            local huds = {"actionBarShowBottom1", "actionBarShowBottom2", "actionBarShowBottom3"}
            for _, hud in pairs(huds) do
              local actionBar = GameOptions:getLoadedWindow("actionsBars"):recursiveGetChildById(hud)
              if actionBar then
                actionBar:setColor(value and '$var-text-cip-color' or '$var-cip-inactive-color')
              end
            end
            return true
        end,
	},

	cacheMap = {
		value = false,
        apply = function(value)
            m_interface.refreshViewMode()
            return true
        end,
	},

	showRightHorizontalPanel = {
		value = false,
        apply = function(value)
            m_interface.showRightHorizontalPanel(value)
            return true
        end,
	},

	nativeMouseCursor = {
		value = false,
        apply = function(value)
            g_window.setUseNativeCursor(value)
            return true
        end,
	},

	autoChaseOverride = {
		value = true,
	},

	stayLoggedInforSession = {
		value = false,
	},

	chatModeOn = {
		value = true,
	},

	ctrlDragCheckBox = {
		value = false,
	},

	alwaysTurnTowardsMoveDirection = {
		value = true,
	},

	actionbarLock = {
		value = false,
	},

	classicView = {
		value = true,
        apply = function(value)
            m_interface.refreshViewMode()
            return true
        end,
	},

	cooldownSecond = {
		value = true,
        apply = function(value)
            modules.game_actionbar.toggleCooldownOption()
            return true
        end,
	},

	hotkeyDelayNative = {
		value = true,
        apply = function(value)
            local controls = GameOptions:getLoadedWindow('controls')
            local delayLabel = controls:recursiveGetChildById('hotkeyDelay')
            if delayLabel then
              delayLabel:setEnabled(not value)
              delayLabel:setColor(not value and '$var-text-cip-color' or '$var-cip-inactive-color')
            end
            local delayLabel = controls:recursiveGetChildById('delayLabel')
            if delayLabel then
              delayLabel:setText(tr('Keyboard Delay: %d ms', getOption('hotkeyDelay')))
              delayLabel:setColor(not value and '$var-text-cip-color' or '$var-cip-inactive-color')
              if not value then
                if getOption('hotkeyDelay') < 50 then
                  delayLabel:setColor("$var-text-cip-store-red")
                elseif getOption('hotkeyDelay') < 250 then
                  delayLabel:setColor("$var-text-cip-color-orange")
                else
                  delayLabel:setColor("$var-text-cip-color")
                end
              end
              rootWidget:getChildById("gameRootPanel"):setAutoRepeatDelay(value and 250 or math.max(0, tonumber(getOption('hotkeyDelay'))))
            end
            return true
        end,
        tempApply = function(value)
            local controls = GameOptions:getLoadedWindow('controls')
            if not controls then return true end
            local delayLabel = controls:recursiveGetChildById('hotkeyDelay')
            if delayLabel then
                delayLabel:setEnabled(not value)
                delayLabel:setColor(not value and '$var-text-cip-color' or '$var-cip-inactive-color')
            end
            local delayLabel = controls:recursiveGetChildById('delayLabel')
            if delayLabel then
                local controls = GameOptions:getLoadedWindow('controls')
                local delay = controls:recursiveGetChildById('hotkeyDelay')
                delayLabel:setText(tr('Keyboard Delay: %d ms', delay:getValue()))
                delayLabel:setColor(not value and '$var-text-cip-color' or '$var-cip-inactive-color')
                if not value then
                    local hotkeyDelayValue = GameOptions:getOption('hotkeyDelay')
                    if hotkeyDelayValue < 50 then
                        delayLabel:setColor("$var-text-cip-store-red")
                    elseif hotkeyDelayValue < 250 then
                        delayLabel:setColor("$var-text-cip-color-orange")
                    else
                        delayLabel:setColor("$var-text-cip-color")
                    end
                end
            end
            return true
        end
	},

	showBoostedMessagesInConsole = {
		value = true,
	},

	opacityArc = {
		value = 70,
        apply = function(value)
            g_map.setArcOpacity(value / 100)
            local wid = GameOptions:getLoadedWindow('hud'):recursiveGetChildById('opacityLabel')
            if wid then
              wid:setText(tr('Opacity: %d%%', value))
            end
            return true
        end,
        tempApply = function(value)
            g_map.setArcOpacity(value / 100)
            local wid = GameOptions:getLoadedWindow('hud'):recursiveGetChildById('opacityLabel')
            if wid then
              wid:setText(tr('Opacity: %d%%', value))
            end
            return true
        end
	},

	displayNames = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawNames(value)
            return true
        end,
	},

	topHealtManaBar = {
		value = true,
        apply = function(value)
            if not g_app.isMobile() then return true end

            modules.game_healthinfo.topHealthBar:setVisible(value)
            modules.game_healthinfo.topManaBar:setVisible(value)
            return true
        end,
	},

	showTimestampsInConsole = {
		value = true,
        apply = function(value)
            modules.game_console.updateCurrentTab()
            return true
        end,
	},

	leftPanels = {
		value = 0,
        apply = function(value)
            m_interface.refreshViewMode()
            return true
        end,
	},

	altCheckBox = {
		value = false,
        apply = function(value)
            local chatEnabled = Options.isChatOnEnabled
            KeyBinds:setupAndReset(Options.currentHotkeySetName, chatEnabled and "chatOn" or "chatOff")
            modules.game_walking.configureRotateKeys('altCheckBox', value)
            return true
        end,
	},

	showPing = {
		value = true,
        apply = function(value)
            modules.client_topmenu.setPingVisible(value)
            if modules.game_stats and modules.game_stats.ui.ping then
              modules.game_stats.ui.ping:setVisible(value)
            end
            return true
        end,
	},

	textualEffect = {
		value = true,
        apply = function(value)
            g_map.setTextureTextEnabled(value)
            return true
        end,
	},

	containerMoveToManagedContainerRecursiveWarning = {
		value = false,
	},

	containerSortRecursive = {
		value = false,
	},

	timeUnnused = {
		value = true,
        apply = function(value) g_game.enableTimerUnnused(value) return true end,
	},

	showPrivateMessagesInConsole = {
		value = true,
	},

	quickLogin = {
		value = false,
	},

	dontStretchShrink = {
		value = false,
        apply = function(value)
            addEvent(function()
                m_interface.updateStretchShrink()
            end)
            return true
        end,
	},

	showInfoMessagesInConsole = {
		value = true,
	},

	rightPanels = {
		value = 1,
        apply = function(value)
            m_interface.refreshViewMode()
            return true
        end,
	},

	showFps = {
		value = true,
        apply = function(value)
            modules.client_topmenu.setFpsVisible(value)
            if modules.game_stats and modules.game_stats.ui.fps then
              modules.game_stats.ui.fps:setVisible(value)
            end
            return true
        end,
	},

	stackEffects = {
		value = true,
        apply = function(value)
            g_map.enableStackEffects(value)
            return true
        end,
	},

	containerSortBackpacksFirst = {
		value = false,
	},

	lootControl = {
		value = 1,
	},

	showHealthManaCircle = {
    value = false,
    apply = function(value)
        local gameMapPanel = m_interface.getMapPanel()
        gameMapPanel:setShowArcs(value)
        return true
    end,
    tempApply = function(value)
        local window = GameOptions:getLoadedWindow("hud")
        if window then
            window:recursiveGetChildById("sizeBox"):setEnabled(value)
            window:recursiveGetChildById("distanceLabel"):setEnabled(value)
            window:recursiveGetChildById("distanceArc"):setEnabled(value)
            window:recursiveGetChildById("opacityLabel"):setEnabled(value)
            window:recursiveGetChildById("opacityArc"):setEnabled(value)

            local healthCheck = window:recursiveGetChildById("harmonyHealth")
            local manaCheck = window:recursiveGetChildById("harmonyMana")
            if healthCheck and manaCheck then
                healthCheck:setEnabled(value)
                manaCheck:setEnabled(value)
                if value then
                    local arcSide = getTmpOption("harmonyArcSide") or getOption("harmonyArcSide")
                    healthCheck:setChecked(arcSide)
                    manaCheck:setChecked(not arcSide)
                    local gameMapPanel = m_interface.getMapPanel()
                    gameMapPanel:setHarmonyLeftDraw(arcSide)
                end
            end
        end
        local gameMapPanel = m_interface.getMapPanel()
        gameMapPanel:setShowArcs(value)
        return true
    end
  },

  sizeBox = {
		value = 2,
        apply = function(value)
            g_map.setArcStyle(value - 1)
            return true
        end,
	},

	trainingProgress = {
		value = true,
	},

	topBar = {
		value = false,
	},

	classicControl = {
		value = 2,
        apply = function(value)
            local window = GameOptions:getLoadedWindow("controls")
            if window then
              window:recursiveGetChildById("lootControl"):setVisible(value == 1)
            end
            return true
        end,
        TempApply = function(value)
            local window = GameOptions:getLoadedWindow("controls")
            if window then
              window:recursiveGetChildById("lootControl"):setVisible(value == 1)
            end
            return true
        end,
	},

	backgroundFrameRate = {
		value = 500,
        apply = function(value)
            if GameOptions:getOption('noFrameCheckBox') then
                g_app.setMaxFps(0)
            else
                local text, v = value, value
                if value <= 0 or value >= 501 then text = 'max' v = 0 end
                g_app.setMaxFps(v)
            end
            return true
        end,
        tempApply = function(value)
            local graphics = GameOptions:getLoadedWindow('graphics')
            local wid = graphics:recursiveGetChildById('noFrameCheckBox')
            if wid and wid:isChecked() then
              return false
            end

            local wid = graphics:recursiveGetChildById('frameRateLabel')
            if wid then
              wid:setText(tr('Frame Rate Limit: %d', value))
            end
            return true
        end,
	},

	showStatusMessagesInConsole = {
		value = true,
	},

	potionSoundEffect = {
		value = true,
	},

	showLootMessagesInConsole = {
		value = true,
        apply = function(value)
            local gameWindow = GameOptions:getLoadedWindow('gameWindow')
            local wid = gameWindow:recursiveGetChildById('showLootMessagesInConsole')
            if wid then
              local v = GameOptions:getOption('showMessages')
              wid:setEnabled(v)
              wid:setColor(v and '$var-text-cip-color' or '$var-cip-inactive-color')
            end
            return true
        end,
        tempApply = function(value)
            local gameWindow = GameOptions:getLoadedWindow('gameWindow')
            local wid = gameWindow:recursiveGetChildById('showLootMessagesInConsole')
            if wid then
              local v = GameOptions:getOption('showMessages')
              wid:setEnabled(v)
              wid:setColor(v and '$var-text-cip-color' or '$var-cip-inactive-color')
            end
            return true
        end,
	},

	displayHealthOnTop = {
		value = false,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawHealthBarsOnTop(value)
            return true
        end,
	},

	floorFading = {
		value = 0,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setFloorFading(value)
            return true
        end,
	},

	showOwnName = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawOwnName(value)
            return true
        end,
	},

	optimiseConnectionStability = {
		value = false,
	},

	displayHealth = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawHealthBars(value)
            return true
        end,
	},

  engine = {
		value = -1,
        apply = function(value)
            if getOption("engine") ~= -1 and value ~= getOption("engine") then
              displayInfoBox("Info", "You have selected a different graphics engine. Restart RTC for this change to take effect.")
            end
            return true
        end,
	},


	antialiasing = {
		value = 3,
        apply = applyAntialiasingMode,
        tempApply = applyAntialiasingMode,
	},

	showSpells = {
		value = true,
        apply = function(value)
            local gameWindow = GameOptions:getLoadedWindow('gameWindow')
            local wid = gameWindow:recursiveGetChildById('showSpells')
            if wid then
              local v = getOption('showMessages')
              wid:setEnabled(v)
              wid:setColor(v and '$var-text-cip-color' or '$var-cip-inactive-color')
            end
            return true
        end,
        tempApply = function(value)
            local gameWindow = GameOptions:getLoadedWindow('gameWindow')
            local wid = gameWindow:recursiveGetChildById('showSpells')
            if wid then
              local v = getOption('showMessages')
              wid:setEnabled(v)
              wid:setColor(v and '$var-text-cip-color' or '$var-cip-inactive-color')
            end
            return true
        end,
	},

	containerMoveToManagedContainerRecursiveShowWarningAgain = {
		value = false,
	},

	timeContainers = {
		value = true,
        apply = function(value)
            g_game.enableTimerContainer(value)
            GameOptions:getLoadedWindow("interface"):recursiveGetChildById("timeUnnused"):setEnabled(true)
            return true
        end,
        tempApply = function(value)
            local interface = GameOptions:getLoadedWindow("interface")
            local unnusedWidget = interface:recursiveGetChildById("timeUnnused")
            unnusedWidget:setEnabled(true)
            unnusedWidget:setColor('$var-text-cip-color')
            if not value and not interface:recursiveGetChildById("timeInventory"):isChecked() then
              unnusedWidget:setEnabled(false)
              unnusedWidget:setColor('$var-cip-inactive-color')
            end
            return true
        end,
	},

	displayMana = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawManaBar(value)
            return true
        end,
	},

	ctrlCheckBox = {
		value = true,
        apply = function(value)
            local chatEnabled = Options.isChatOnEnabled
            KeyBinds:setupAndReset(Options.currentHotkeySetName, chatEnabled and "chatOn" or "chatOff")
            modules.game_walking.configureRotateKeys('ctrlCheckBox', value)
            return true
        end,
	},

	highlightThingsUnderCursor = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setCrosshairVisible(value)
            gameMapPanel:setDrawHighlightTarget(value)
            return true
        end,
	},

	vsync = {
		value = true,
        apply = function(value)
            local graphics = GameOptions:getLoadedWindow('graphics')
            local color = value and '$var-cip-inactive-color' or '$var-text-cip-color'
            graphics:recursiveGetChildById("noFrameCheckBox"):setEnabled(not value)
            graphics:recursiveGetChildById("backgroundFrameRate"):setEnabled(not value)
            graphics:recursiveGetChildById("frameRateLabel"):setColor(color)
            graphics:recursiveGetChildById("noFrameCheckBox"):setColor(color)
            g_window.setVerticalSync(value)
            if value then
              g_app.setMaxFps(200) -- allow 240hz monitors
            else
              local maxFps = graphics:recursiveGetChildById("backgroundFrameRate"):getValue() or 200
              local noFrameLimit = graphics:recursiveGetChildById("noFrameCheckBox")
              if noFrameLimit and noFrameLimit:isChecked() then
                maxFps = 0
              end
              g_app.setMaxFps(maxFps)
            end
            return true
        end,
        tempApply = function(value)
            local graphics = GameOptions:getLoadedWindow('graphics')
            local color = value and '$var-cip-inactive-color' or '$var-text-cip-color'
            graphics:recursiveGetChildById("noFrameCheckBox"):setEnabled(not value)
            graphics:recursiveGetChildById("backgroundFrameRate"):setEnabled(not value)
            graphics:recursiveGetChildById("frameRateLabel"):setColor(color)
            graphics:recursiveGetChildById("noFrameCheckBox"):setColor(color)
            return true
        end,
	},

	enableMusicSound = {
		value = false,
        apply = function(value)
            if g_sounds ~= nil then
                g_sounds.getChannel(SoundChannels.Music):setEnabled(value)
              end
            return true
        end,
	},

	opacityMissile = {
		value = 100,
        apply = function(value)
            g_client.setMissileAlpha(value/100)
            local effects = GameOptions:getLoadedWindow("effects")
            effects:recursiveGetChildById('opacityMissileLimitLabel'):setText(tr('Opacity Missiles: %s%%', value))
            return true
        end,
        tempApply = function(value)
            local effects = GameOptions:getLoadedWindow("effects")
            effects:recursiveGetChildById('opacityMissileLimitLabel'):setText(tr('Opacity Missiles: %s%%', value))
            return true
        end,
	},

	opacityEffects = {
		value = 100,
        apply = function(value)
            applyEffectAlpha(value, GameOptions:getOption("showOwnEffects"))
            local effects = GameOptions:getLoadedWindow("effects")
            effects:recursiveGetChildById('opacityEffectLimitLabel'):setText(tr('Opacity Effect: %s%%', value))
            return true
        end,
        tempApply = function(value)
            local effects = GameOptions:getLoadedWindow("effects")
            effects:recursiveGetChildById('opacityEffectLimitLabel'):setText(tr('Opacity Effect: %s%%', value))
            return true
        end,
	},

  showOwnEffects = {
    value = false,
    apply = function(value)
        applyEffectAlpha(GameOptions:getOption("opacityEffects"), value)
        return true
    end,
    tempApply = function(value)
        local effects = GameOptions:getLoadedWindow("effects")
        if effects then
            local opacity = effects:recursiveGetChildById('opacityEffects')
            if opacity then
                opacity:setEnabled(not value)
            end
        end
        return true
    end,
  },

  ignoreSpecialEffects = {
    value = false,
    apply = function(value)
        g_client.setIgnoreSpecialEffects(value)
        return true
    end,
  },

	showMessages = {
		value = true,
        apply = function(value)
            g_map.setShowMessageEnabled(value)
            local window = GameOptions:getLoadedWindow("gameWindow")
            local widgets = {"showPrivateMessagesOnScreen", "potionSoundEffect", "showSpells", "spellsOthers", "showHotkeyMessagesInConsole", "showLootMessagesInConsole", "showBoostedMessagesInConsole", "trainingProgress", "storeNotification"}
            for _, wid in pairs(widgets) do
              local w = window:recursiveGetChildById(wid)
              if w then
                w:setEnabled(value)
                w:setColor(value and '$var-text-cip-color' or '$var-cip-inactive-color')
              end
            end
            return true
        end,
        tempApply = function(value)
            local window = GameOptions:getLoadedWindow("gameWindow")
            local widgets = {"showPrivateMessagesOnScreen", "potionSoundEffect", "showSpells", "spellsOthers", "showHotkeyMessagesInConsole", "showLootMessagesInConsole", "showBoostedMessagesInConsole", "trainingProgress", "storeNotification"}
            for _, wid in pairs(widgets) do
              local w = window:recursiveGetChildById(wid)
              if w then
                w:setEnabled(value)
                w:setColor(value and '$var-text-cip-color' or '$var-cip-inactive-color')
              end
            end
            return true
        end,
	},

	showOwnMana = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawOwnManaBar(value)
            gameMapPanel:setDrawOwnManaShieldBar(value)
            return true
        end,
	},

  showHarmony = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawHarmonyBar(value)
            return true
        end,
	},

	markTargetVisually = {
		value = 1,
        apply = function(value)
            g_game.setHighlightingTarget(value == 1 or value == 3)
            g_game.setFramingTarget(value == 1 or value == 2)
            -- if g_game.isOnline() then
            --   modules.game_battle.updateSquare(value)
            -- end

            return true
        end,
	},

	smartWalk = {
		value = false,
	},

	walkCtrlTurnDelay = {
		value = 150,
	},

	fullscreen = {
		value = false,
        apply = function(value)
            g_window.setFullscreen(value)
            return true
        end,
	},

    -- HD Mode (xBRZ, soyfabi): um unico checkbox. Ligado = upscale 2x; desligado = 1x (normal).
    -- setScaleFactor infla getSpriteSize() (base*fator) e recarrega as texturas (unloadTextures).
    hdModeBox = {
        value = false,
        apply = function(value)
            if g_sprites and g_sprites.setScaleFactor then
                g_sprites.setScaleFactor(value and 2 or 1)
            end
            return true
        end,
    },

	stowContainer = {
		value = true,
	},

	dash = {
		value = false,
        apply = function(value)
            if value then
                g_game.setMaxPreWalkingSteps(2)
            else
                g_game.setMaxPreWalkingSteps(1)
            end
            return true
        end,
	},

	ownHUDCharacter = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawOwnHUD(value)
            return true
        end,
        tempApply = function(value)
            local huds = {"showOwnBars", "showOwnName", "showOwnHealth", "showOwnMana"}
            for _, hud in pairs(huds) do
              local showHud = selectedWindow:recursiveGetChildById(hud)
              if showHud then
                showHud:setEnabled(value)
              end
            end
            return true
        end,
	},

	combatFrames = {
		value = true,
	},

	showMarks = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawMarks(value)
            return true
        end,
	},

	showLeftHorizontalPanel = {
		value = false,
        apply = function(value)
            m_interface.showLeftHorizontalPanel(value)
            return true
        end,
	},

	distanceArc = {
		value = 15,
        apply = function(value)
            g_map.setArcDistance(value / 100)
            local wid = GameOptions:getLoadedWindow('hud'):recursiveGetChildById('distanceLabel')
            if wid then
              wid:setText(tr('Distance: %d%%', value))
            end
            return true
        end,
        tempApply = function(value)
            g_map.setArcDistance(value / 100)
            local wid = GameOptions:getLoadedWindow('hud'):recursiveGetChildById('distanceLabel')
            if wid then
              wid:setText(tr('Distance: %d%%', value))
            end
            return true
        end,
	},

  harmonyArcSide = {
    value = true,
    apply = function(value)
        local gameMapPanel = m_interface.getMapPanel()
        gameMapPanel:setHarmonyLeftDraw(value)
        return true
    end,
    tempApply = function(value)
        local gameMapPanel = m_interface.getMapPanel()
        gameMapPanel:setHarmonyLeftDraw(value)
        return true
    end,
  },

	showHotkeyMessagesInConsole = {
		value = true,
        tempApply = function(value)
            local gameWindow = GameOptions:getLoadedWindow('gameWindow')
            local wid = gameWindow:recursiveGetChildById('showHotkeyMessagesInConsole')
            if wid then
              local v = getOption('showMessages')
              wid:setEnabled(v)
              wid:setColor(v and '$var-text-cip-color' or '$var-cip-inactive-color')
            end
            return true
        end,
	},

	maxEffects = {
		value = false,
        apply = function(value)
            local effects = GameOptions:getLoadedWindow('effects')
            local wid = effects:recursiveGetChildById('effectLimitLabel')
            if wid and not value then
              wid:setColor("$var-text-cip-color")
              wid:setText(tr('Effects Limits: %d', getOption('limitEffects')))
            elseif wid then
              wid:setText(tr('Effects Limits: %d', getOption('limitEffects')))
              wid:setColor("$var-cip-inactive-color")
            end

            g_map.setUnlimitEffects(value)
            return true
        end,
        tempApply = function(value)
            local effects = GameOptions:getLoadedWindow('effects')
            local wid = effects:recursiveGetChildById('effectLimitLabel')
            local limitEffects = effects:recursiveGetChildById('limitEffects')
            if wid and not value then
              wid:setColor("$var-text-cip-color")
              limitEffects:enable()
            elseif wid then
              wid:setColor("$var-cip-inactive-color")
              limitEffects:disable()
            end
            return true
        end,
	},

	containerSortRecursiveShowWarningAgain = {
		value = false,
	},

	limitEffects = {
		value = 400,
        apply = function(value)
            local effects = GameOptions:getLoadedWindow('effects')
            local value = math.max(10, math.min(value, 1000))
            g_map.setLimitEffects(value)
            local wid = effects:recursiveGetChildById('effectLimitLabel')
            if wid then
              wid:setText(tr('Effects Limits: %d', value))
            end
            return true
        end,
        tempApply = function(value)
            local effects = GameOptions:getLoadedWindow('effects')
            local wid = effects:recursiveGetChildById('maxEffects')
            if wid and wid:isChecked() then
              return false
            end

            local wid = effects:recursiveGetChildById('effectLimitLabel')
            if wid then
              wid:setText(tr('Effects Limits: %d', value))
            end
            return true
        end,
	},

	lootHighlight = {
		value = true,
	},

	spellsOthers = {
		value = false,
        tempApply = function(value)
            local gameWindow = GameOptions:getLoadedWindow('gameWindow')
            local wid = gameWindow:recursiveGetChildById('spellsOthers')
            if wid then
              local v = GameOptions:getOption('showMessages')
              wid:setEnabled(v)
              wid:setColor(v and '$var-text-cip-color' or '$var-cip-inactive-color')
            end
            return true
        end,
	},

	colouriseLootColor = {
		value = 2,
        apply = function(value)
            g_game.setLootValueState(value - 1)
            return true
        end,
	},

	showOwnBars = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawOwnBars(value)
            return true
        end,
	},

	showEventMessagesInConsole = {
		value = true,
	},

	allActionBar79 = {
		value = false,
        apply = function(value)
            local huds = {"actionBarShowRight1", "actionBarShowRight2", "actionBarShowRight3"}
            for _, actionBar in pairs(huds) do
                local hud = GameOptions:getLoadedWindow("actionsBars"):recursiveGetChildById(actionBar)
                modules.game_actionbar.configureActionBar(actionBar, (value and hud:isChecked()))
            end
            return true
        end,
        tempApply = function(value)
            local huds = {"actionBarShowRight1", "actionBarShowRight2", "actionBarShowRight3"}
            for _, hud in pairs(huds) do
              local actionBar = GameOptions:getLoadedWindow("actionsBars"):recursiveGetChildById(hud)
              if actionBar then
                actionBar:setColor(value and '$var-text-cip-color' or '$var-cip-inactive-color')
              end
            end
            return true
        end,
	},

	noFrameCheckBox = {
		value = false,
        apply = function(value)
            local graphics = GameOptions:getLoadedWindow('graphics')
            local wid = graphics:recursiveGetChildById('frameRateLabel')
            if wid and not value then
              wid:setColor("$var-text-cip-color")
            elseif wid then
              wid:setColor("$var-cip-inactive-color")
            end

            if value then
              g_app.setMaxFps(0)
            else
              local vsync = graphics:recursiveGetChildById("vsync")
              if vsync and vsync:isChecked() then
                  g_window.setVerticalSync(true)
                  g_app.setMaxFps(300)
              else
                local currentFps = TempOptions:getOption('backgroundFrameRate') ~= nil and TempOptions:getOption('backgroundFrameRate') or nil
                if not currentFps then
                  currentFps = GameOptions:getOption('backgroundFrameRate') ~= nil and GameOptions:getOption('backgroundFrameRate') or nil
                end
                g_app.setMaxFps(currentFps and currentFps or 200)
              end
            end

            local wid = graphics:recursiveGetChildById('backgroundFrameRate')
            if wid and not value then
              wid:setEnabled(true)
            elseif wid then
              wid:setEnabled(false)
            end

            return true
        end,
        tempApply = function(value)
            local graphics = GameOptions:getLoadedWindow('graphics')
            local wid = graphics:recursiveGetChildById('frameRateLabel')
            if wid and not value then
              wid:setColor("$var-text-cip-color")
            elseif wid then
              wid:setColor("$var-cip-inactive-color")
            end

            local wid = graphics:recursiveGetChildById('backgroundFrameRate')
            if wid and not value then
              wid:setEnabled(true)
            elseif wid then
              wid:setEnabled(false)
            end
            return true
        end
	},

	actionTooltip = {
		value = true,
        apply = function(value)
            modules.game_actionbar.updateVisibleOptions('tooltip', value)
            return true
        end,
	},

	showSpellParameters = {
		value = true,
        apply = function(value)
            modules.game_actionbar.updateVisibleOptions('parameter', value)
            return true
        end,
	},

	showPrivateMessagesOnScreen = {
		value = true,
        tempApply = function(value)
            local gameWindow = GameOptions:getLoadedWindow('gameWindow')
            local wid = gameWindow:recursiveGetChildById('showPrivateMessagesOnScreen')
            if wid then
              local v = getOption('showMessages')
              wid:setEnabled(v)
              wid:setColor(v and '$var-text-cip-color' or '$var-cip-inactive-color')
            end
            return true
        end,
	},

	showHKObjectsBars = {
		value = true,
        apply = function(value)
            modules.game_actionbar.updateVisibleOptions('amount', value)
            return true
        end,
	},

	enableAudio = {
		value = true,
        apply = function(value)
            if g_sounds ~= nil then
                g_sounds.setAudioEnabled(value)
            end
            return true
        end,
	},

	turnDelay = {
		value = 30,
	},

	otherHUDCreatures = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawOtherHUD(value)
            return true
        end,
        tempApply = function(value)
            local huds = {"displayNames", "displayHealth", "showOthersMarks", "showNPC"}
            for _, hud in pairs(huds) do
              local showHud = GameOptions:getLoadedWindow('hud'):recursiveGetChildById(hud)
              if showHud then
                showHud:setEnabled(value)
              end
            end
            return true
        end,
	},

	autoSwitchHotkey = {
		value = false,
        apply = function(value)
            Options.array["hotkeyOptions"]["autoSwitchHotkeyPreset"] = value
            return true
        end,
	},

	pvpFrames = {
		value = true,
	},

	prestigeEmblem = {
		value = true,
        apply = function(value)
            g_game.enableShowPrestigeTexture(value)
            return true
        end,
	},

	walkStairsDelay = {
		value = 50,
	},

	walkFirstStepDelay = {
		value = 200,
	},

	wsadWalking = {
		value = false,
	},

	showAssignedHKButton = {
		value = true,
        apply = function(value)
            modules.game_actionbar.updateVisibleOptions('hotkey', value)
            return true
        end,
	},

	showCooldown = {
		value = true,
        apply = function(value)
            modules.game_cooldown.toggleVisible(value)
            return true
        end,
	},

	shiftCheckBox = {
		value = false,
        apply = function(value)
            local chatEnabled = Options.isChatOnEnabled
            KeyBinds:setupAndReset(Options.currentHotkeySetName, chatEnabled and "chatOn" or "chatOff")
            modules.game_walking.configureRotateKeys('shiftCheckBox', value)
            return true
        end,
	},

	customisableBars = {
		value = true,
        apply = function(value)
            modules.game_topbar.toggle(value)
            return true
        end,
	},

	statusBars = {
		value = true,
        apply = function(value)
            if not g_game.isOnline() then return true end
            if value then
                modules.game_healthinfo.getHealthInfoWindow():show()
              else
                modules.game_healthinfo.getHealthInfoWindow():hide()
              end
            return true
        end,
	},

	linkCopyWarning = {
		value = true,
	},

	enableLights = {
		value = false,
        apply = function(value)
            local effects = GameOptions:getLoadedWindow('effects')
            local wid = effects:recursiveGetChildById('ambientLabel')
            if wid and value then
              wid:setColor("$var-text-cip-color")
            elseif wid then
              wid:setColor("$var-cip-inactive-color")
            end

            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawLights(value and GameOptions:getOption('ambientLight') < 100)
            return true
        end,
        tempApply = function(value)
            local effects = GameOptions:getLoadedWindow('effects')
            local wid = effects:recursiveGetChildById('ambientLabel')
            local ambientSlider = effects:recursiveGetChildById('ambientLight')
            if wid and value then
              wid:setColor("$var-text-cip-color")
              ambientSlider:enable()
            elseif wid then
              wid:setColor("$var-cip-inactive-color")
              ambientSlider:disable()
            end
            return true
        end,
	},

  enableShaders = {
    value = true,
    apply = function(value)
      modules.game_shaders.clearMapShader()
      if value and g_game.isOnline() then
        modules.game_shaders.onPositionChange(_, g_game.getLocalPlayer():getPosition(), _)
      end
      return true
    end,
  },

  autoScreenshot = {
    value = true,
    apply = function(value)
        local screenshotPanel = GameOptions:getLoadedWindow("screenshot")
        if screenshotPanel then
            local checkboxes = screenshotPanel:getChildById("autoScreenshot")
            if checkboxes then
                checkboxes:setEnabled(value)
            end
        end
        return true
    end,
    tempApply = function(value)
        local screenshotPanel = GameOptions:getLoadedWindow("screenshot")
        if screenshotPanel then
            local checkboxes = screenshotPanel:getChildById("autoScreenshot")
            if checkboxes then
                checkboxes:setEnabled(value)
            end
        end
        return true
    end,
  },

  gameWindowScreen = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotLevelUp = {
      value = true,
      apply = function(value)
          return true
      end,
  },

  screenshotSkillUp = {
      value = true,
      apply = function(value)
          return true
      end,
  },

  screenshotAchievement = {
      value = true,
      apply = function(value)
          return true
      end,
  },

  screenshotBestiaryUnlocked = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotBestiaryComplete = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotTreasure = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotValuableLoot = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotBossDefeated = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotDeathPve = {
      value = true,
      apply = function(value)
          return true
      end,
  },

  screenshotDeathPvp = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotPlayerKill = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotPlayerKillAssist = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotPlayerAttacking = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotHighestDamage = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotHighestHealing = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotLowHealth = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotGiftOfLife = {
      value = true,
      apply = function(value)
          return true
      end,
  },

  -- Sound
  masterVolumeScrollBar = {
      value = 100,
      apply = function(value)
        value = clampVolume(value)
        if g_sounds ~= nil and g_sounds.setMasterGain then
            g_sounds.setMasterGain(value / 100.0)
        end
        setSoundLabel("sound", "masterVolumeLabel", value <= 0 and tr('Master Volume: %d%% (off)', value) or tr('Master Volume: %d%%', value))
        updateSoundWarnings(value)
        return true
      end,
      tempApply = function(value)
        value = clampVolume(value)
        setSoundLabel("sound", "masterVolumeLabel", value <= 0 and tr('Master Volume: %d%% (off)', value) or tr('Master Volume: %d%%', value))
        updateSoundWarnings(value)
        return true
      end,
  },

  musicVolumeScrollBar = {
      value = 100,
      apply = function(value)
        value = clampVolume(value)
        setSoundChannelGain(SoundChannels.Music, value)
        setSoundLabel("sound", "musicVolumeLabel", tr('Music Volume: %d%%', value))
        return true
      end,
      tempApply = function(value)
        setSoundLabel("sound", "musicVolumeLabel", tr('Music Volume: %d%%', clampVolume(value)))
        return true
      end,
  },

  anthemMusic = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(SoundChannels.Music, value)
        return true
      end,
  },

  ambienceVolumeScrollBar = {
      value = 100,
      apply = function(value)
        value = clampVolume(value)
        setSoundChannelsGain({ SoundChannels.Ambient, numericSoundType("AMBIENCE_STREAM", 8) }, value)
        setSoundLabel("sound", "ambienceVolumeLabel", tr('Ambience Volume: %d%%', value))
        return true
      end,
      tempApply = function(value)
        setSoundLabel("sound", "ambienceVolumeLabel", tr('Ambience Volume: %d%%', clampVolume(value)))
        return true
      end,
  },

  itemVolumeScrollBar = {
      value = 100,
      apply = function(value)
        value = clampVolume(value)
        setSoundChannelsGain({ numericSoundType("FOOD_AND_DRINK", 9), numericSoundType("ITEM_MOVEMENT", 10) }, value)
        setSoundLabel("sound", "itemVolumeLabel", tr('Item Volume: %d%%', value))
        return true
      end,
      tempApply = function(value)
        setSoundLabel("sound", "itemVolumeLabel", tr('Item Volume: %d%%', clampVolume(value)))
        return true
      end,
  },

  foodBeverages = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("FOOD_AND_DRINK", 9), value)
        return true
      end,
  },

  moveItemMusic = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("ITEM_MOVEMENT", 10), value)
        return true
      end,
  },

  eventVolumeScrollBar = {
      value = 100,
      apply = function(value)
        value = clampVolume(value)
        setSoundChannelGain(numericSoundType("EVENT", 11), value)
        setSoundLabel("sound", "eventVolumeLabel", tr('Event Volume: %d%%', value))
        return true
      end,
      tempApply = function(value)
        setSoundLabel("sound", "eventVolumeLabel", tr('Event Volume: %d%%', clampVolume(value)))
        return true
      end,
  },

  ownBattleVolumeScrollBar = {
      value = 100,
      apply = function(value)
        value = clampVolume(value)
        setSoundChannelsGain({
            numericSoundType("SPELL_HEALING", 2),
            numericSoundType("SPELL_SUPPORT", 3),
            numericSoundType("WEAPON_ATTACK", 4),
            numericSoundType("SPELL_GENERIC", 19)
        }, value)
        setSoundLabel("battleSounds", "ownBattleVolumeLabel", tr('Own Battle Sounds: %d%%', value))
        return true
      end,
      tempApply = function(value)
        setSoundLabel("battleSounds", "ownBattleVolumeLabel", tr('Own Battle Sounds: %d%%', clampVolume(value)))
        return true
      end,
  },

  otherBattleVolumeScrollBar = {
      value = 100,
      apply = function(value)
        value = clampVolume(value)
        setSoundChannelGain(numericSoundType("SPELL_ATTACK", 1), value)
        setSoundLabel("battleSounds", "otherBattleVolumeLabel", tr('Other Players: %d%%', value))
        return true
      end,
      tempApply = function(value)
        setSoundLabel("battleSounds", "otherBattleVolumeLabel", tr('Other Players: %d%%', clampVolume(value)))
        return true
      end,
  },

  creatureBattleVolumeScrollBar = {
      value = 100,
      apply = function(value)
        value = clampVolume(value)
        setSoundChannelsGain({
            numericSoundType("CREATURE_NOISE", 5),
            numericSoundType("CREATURE_DEATH", 6),
            numericSoundType("CREATURE_ATTACK", 7)
        }, value)
        setSoundLabel("battleSounds", "creatureBattleVolumeLabel", tr('Creatures: %d%%', value))
        return true
      end,
      tempApply = function(value)
        setSoundLabel("battleSounds", "creatureBattleVolumeLabel", tr('Creatures: %d%%', clampVolume(value)))
        return true
      end,
  },

  ownSpellSound = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("SPELL_GENERIC", 19), value)
        return true
      end,
  },

  ownAttackSound = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("SPELL_ATTACK", 1), value)
        return true
      end,
  },

  ownHealingSound = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("SPELL_HEALING", 2), value)
        return true
      end,
  },

  ownSupportSound = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("SPELL_SUPPORT", 3), value)
        return true
      end,
  },

  ownWeaponsSound = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("WEAPON_ATTACK", 4), value)
        return true
      end,
  },

  otherSpellSound = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("SPELL_ATTACK", 1), value)
        return true
      end,
  },

  otherAttackSound = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("WEAPON_ATTACK", 4), value)
        return true
      end,
  },

  otherHealingSound = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("SPELL_HEALING", 2), value)
        return true
      end,
  },

  otherSupportSound = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("SPELL_SUPPORT", 3), value)
        return true
      end,
  },

  otherWeaponsSound = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("WEAPON_ATTACK", 4), value)
        return true
      end,
  },

  creatureNoiseSound = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("CREATURE_NOISE", 5), value)
        return true
      end,
  },

  creatureDeathSound = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("CREATURE_DEATH", 6), value)
        return true
      end,
  },

  creatureSpellSound = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("CREATURE_ATTACK", 7), value)
        return true
      end,
  },

  -- UI Sounds
  uiSounds = {
      value = true,
      apply = function(value)
        if g_sounds ~= nil then
            g_sounds.getChannel(ENumericSoundType.UI):setEnabled(value)
        end
        return true
      end,
  },

  uiVolumeScrollBar = {
      value = 100,
      apply = function(value)
        value = clampVolume(value)
        if g_sounds ~= nil then
            g_sounds.getChannel(ENumericSoundType.UI):setGain(value/100.0)
        end

        local soundUI = GameOptions:getLoadedWindow("uiSounds")
        if soundUI then
            local wid = soundUI:recursiveGetChildById("uiVolumeLabel")
            if wid then
                wid:setText(tr('UI Volume: %d%%', value))
            end
        end
        return true
      end,
      tempApply = function(value)
        value = clampVolume(value)
        local soundUI = GameOptions:getLoadedWindow("uiSounds")
        if soundUI then
            local wid = soundUI:recursiveGetChildById("uiVolumeLabel")
            if wid then
                wid:setText(tr('UI Volume: %d%%', value))
            end
        end
        return true
      end,
  },

  partySounds = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("PARTY", 15), value)
        return true
      end,
  },

  vipSounds = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("VIP_LIST", 16), value)
        return true
      end,
  },

  consoleMessageSounds = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("CHAT_MESSAGE", 14), value)
        return true
      end,
  },

  partyMessageSounds = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("PARTY", 15), value)
        return true
      end,
  },

  guildMessageSounds = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("CHAT_MESSAGE", 14), value)
        return true
      end,
  },

  privateLocalMessageSounds = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("WHISPER_WITHOUT_OPEN_CHAT", 13), value)
        return true
      end,
  },

  privateMessageSounds = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("WHISPER_WITHOUT_OPEN_CHAT", 13), value)
        return true
      end,
  },

  npcMessageSounds = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("CHAT_MESSAGE", 14), value)
        return true
      end,
  },

  globalMessageSounds = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("CHAT_MESSAGE", 14), value)
        return true
      end,
  },

  finderMessageSounds = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("CHAT_MESSAGE", 14), value)
        return true
      end,
  },

  raidMessageSounds = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("RAID_ANNOUNCEMENT", 17), value)
        return true
      end,
  },

  systemMessageSounds = {
      value = true,
      apply = function(value)
        setSoundChannelEnabled(numericSoundType("SERVER_MESSAGE", 18), value)
        return true
      end,
  },

  quickAllCorpses = {
    value = false,
  },

  showInHudCheckBox = {
    value = true,
    apply = function(value)
        local gameMapPanel = m_interface.getMapPanel()
        gameMapPanel:setDrawHUDStatus(value)

        ConditionsHUD:setShowInHudEnabled(value)
        return true
    end,
    tempApply = function(value)
        ConditionsHUD:setShowInHudEnabled(value)
        return true
    end,
  },

  showInBarCheckBox = {
    value = true,
    apply = function(value)
        ConditionsHUD:setShowInBarEnabled(value)
        return true
    end,
    tempApply = function(value)
        ConditionsHUD:setShowInBarEnabled(value)
        return true
    end,
  },

  showSpellChat = {
    value = true,
    apply = function(value)
        local console = modules.game_console
        if value then
          console.openSpellChannel()
        else
          console.closeSpellChannel()
        end
        return true
    end,
    tempApply = function(value)
        return true
    end,
  },

  enterMutedVoip = {
    value = false,
  },

  showOverlayVoip = {
    value = true,
    apply = function(value)
        return true
    end,
  },

  microphoneVoip = {
    value = 1,
    apply = function(value)
        callVoip('setInputDevice', math.max(0, (tonumber(value) or 1) - 1))
        return true
    end,
  },

  speakerVoip = {
    value = 1,
    apply = function(value)
        callVoip('setOutputDevice', math.max(0, (tonumber(value) or 1) - 1))
        return true
    end,
  },

  micSensitivityVoip = {
    value = 100,
    apply = function(value)
        value = tonumber(value) or 50
        callVoip('setSensitivity', value)
        updateVoipLabel('micSensitivityVoipLabel', tr('Sensibilidade do microfone: %d%%', value))
        return true
    end,
    tempApply = function(value)
        value = tonumber(value) or 50
        updateVoipLabel('micSensitivityVoipLabel', tr('Sensibilidade do microfone: %d%%', value))
        return true
    end,
  },

  micGainVoip = {
    value = 200,
    apply = function(value)
        value = tonumber(value) or 100
        callVoip('setMicGain', value)
        updateVoipLabel('micGainVoipLabel', tr('Volume do seu microfone: %d%%', value))
        return true
    end,
    tempApply = function(value)
        value = tonumber(value) or 100
        updateVoipLabel('micGainVoipLabel', tr('Volume do seu microfone: %d%%', value))
        return true
    end,
  },

  speakerVolumeVoip = {
    value = 100,
    apply = function(value)
        value = tonumber(value) or 100
        callVoip('setSpeakerVolume', value)
        updateVoipLabel('speakerVolumeVoipLabel', tr('Volume da chamada: %d%%', value))
        return true
    end,
    tempApply = function(value)
        value = tonumber(value) or 100
        updateVoipLabel('speakerVolumeVoipLabel', tr('Volume da chamada: %d%%', value))
        return true
    end,
  },

  inputProfileVoip = {
    value = 1,
    apply = function(value)
        callVoip('setInputProfile', tonumber(value) == 2 and 'isolation' or 'studio')
        return true
    end,
  },

  micModeVoip = {
    value = 2,
    apply = function(value)
        value = tonumber(value) or 1
        callVoip('setPttMode', value ~= 2)
        return true
    end,
  },
}
