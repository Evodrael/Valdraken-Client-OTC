MiniBotMiniWindow           = nil
MiniBotMiniWindowDialog     = nil
MiniBotEditPresetMiniWindow = nil
MiniBotImportPresetMiniWindow = nil
MiniBotGameWindowPanel      = nil
MiniBotToggleButton         = nil

local miniBotversionStr = "1.2.2 Beta"
-- How to set value:
--  000: First three numbers pack is major version
--  000: Second three numbers pack is minor version
--  000: Third three numbers pack is lesser version, used for hotfix
local miniBotVersion = 1002002

local _miniBotSettingsCache = nil
local function _loadMiniBotSettings()
  if _miniBotSettingsCache == nil then
    local node = g_settings.getNode('Minibot_Settings')
    if node == nil then
      node = {}
    end
    _miniBotSettingsCache = node
  end
  return _miniBotSettingsCache
end

local function _saveMiniBotSettings()
  if _miniBotSettingsCache ~= nil then
    g_settings.setNode('Minibot_Settings', _miniBotSettingsCache)
    g_settings.save()
  end
end

-- Auto Follow / Auto Fishing ticks (Support > General). Declared here so that
-- terminate(), which is defined above the rest of the runtime, can stop them.
local autoFollowEvent = nil
local autoFishingEvent = nil
local autoFishingWarning = nil

-- Estado do Auto Follow. O follow do servidor (g_game.follow) nao serve para
-- acompanhar troca de andar: ele e cancelado assim que o alvo sai da tela ou
-- muda de piso. Entao o rastro do alvo e a caminhada sao feitos aqui.
local followLastPos = nil     -- ultimo SQM conhecido do alvo
local followPrevPos = nil     -- SQM anterior (de onde ele saiu)
local followWalkDest = nil    -- ultimo destino enviado ao autoWalk
local followWalkRetry = 0     -- freio para nao refazer a mesma rota falha em loop
local followRecoverPos = nil  -- SQM que estamos tentando pisar para reencontrar o alvo
local followRecoverStage = 0
local followRecoverNext = 0   -- so avanca de estagio depois deste instante
local followRecoverDeadline = 0
local followFloorHint = false -- vimos o alvo trocar de andar?
local followWarning = nil
local followTargetName = nil  -- nome do alvo em minusculas; nil = follow desligado

local function resetAutoFollowState()
  followTargetName = nil
  followLastPos = nil
  followPrevPos = nil
  followWalkDest = nil
  followWalkRetry = 0
  followRecoverPos = nil
  followRecoverStage = 0
  followRecoverNext = 0
  followRecoverDeadline = 0
  followFloorHint = false
  followWarning = nil
end

local function stopAutoFollow()
  if autoFollowEvent ~= nil then
    removeEvent(autoFollowEvent)
    autoFollowEvent = nil
  end
  resetAutoFollowState()
end

local function stopAutoFishing()
  if autoFishingEvent ~= nil then
    removeEvent(autoFishingEvent)
    autoFishingEvent = nil
  end
  autoFishingWarning = nil
end

local function updateGoldBalanceText(bankBalance, inventoryBalance)
  if MiniBotMiniWindow == nil or MiniBotMiniWindow.balance == nil or MiniBotMiniWindow.balance.text == nil then
    return
  end

  MiniBotMiniWindow.cacheBalanceBank = tonumber(bankBalance) or 0
  MiniBotMiniWindow.cacheBalanceInventory = tonumber(inventoryBalance) or 0
  MiniBotMiniWindow.balance.text:setText(comma_value(MiniBotMiniWindow.cacheBalanceBank + MiniBotMiniWindow.cacheBalanceInventory))
end

local function refreshGoldBalance()
  if not g_game.isOnline() then
    updateGoldBalanceText(0, 0)
    return
  end

  local player = g_game.getLocalPlayer()
  if player ~= nil then
    updateGoldBalanceText(player:getResourceBalance(0), player:getResourceBalance(1))
  end

  g_game.requestResource(0)
  g_game.requestResource(1)
end

function getVersionStr()
  return miniBotversionStr
end

local pages = {
  {
      name = 'Settings',
      identifier = 'settings',
      icon = '143 0 13 13',
      iconSize = '13 13',
      ui = 'main_settings',
      childs = {}
  },
  {
      name = 'Combat',
      identifier = 'combat',
      icon = '156 0 11 13',
      iconSize = '11 13',
      childs = {
        {
          name = 'Attack',
          identifier = 'combat_attack',
          icon = '0 0 11 10',
          iconSize = '11 10',
          ui = 'combat_attack',
          childs = {}
        },
        {
          name = 'Timers',
          identifier = 'combat_timers',
          icon = '169 0 8 13',
          iconSize = '8 13',
          ui = 'combat_timers',
          childs = {}
        },
        {
          name = 'Shooter',
          identifier = 'combat_shooter',
          icon = '130 0 11 12',
          iconSize = '11 12',
          ui = 'combat_shooter',
          childs = {}
        },
        {
          name = 'PvP',
          identifier = 'combat_pvp',
          icon = '403 0 13 13',
          iconSize = '13 13',
          ui = 'combat_pvp',
          childs = {}
        },
      }
  },
  {
      name = 'Equipment',
      identifier = 'equipment',
      icon = '312 0 11 10',
      iconSize = '11 10',
      childs = {
        {
          name = 'Amulets',
          identifier = 'equipment_amulets',
          icon = '325 0 13 13',
          iconSize = '13 13',
          ui = 'equipment_amulets',
          childs = {}
        },
        {
          name = 'Rings',
          identifier = 'equipment_rings',
          icon = '338 0 12 12',
          iconSize = '12 12',
          ui = 'equipment_rings',
          childs = {}
        },
      }
  },
  {
      name = 'Cave Bot',
      identifier = 'cavebot',
      icon = '195 0 10 10',
      iconSize = '10 10',
      childs = {
        {
          name = 'Recorder',
          icon = '429 0 13 13',
          identifier = 'hunting_recorder',
          iconSize = '13 13',
          ui = 'hunting_recorder',
          childs = {}
        },
        {
          name = 'Explorer',
          icon = '221 0 9 13',
          identifier = 'hunting_explorer',
          iconSize = '9 13',
          ui = 'hunting_explorer',
          childs = {}
        },
        --{
        --  name = 'Group Follow',
        --  icon = '221 0 9 13',
        --  iconSize = '9 13',
        --  ui = 'hunting_groupFollow',
        --  childs = {}
        --},
      }
  },
  {
      name = 'Healing',
      identifier = 'healing',
      icon = '13 0 12 12',
      iconSize = '12 12',
      childs = {
        {
            name = 'Health',
            identifier = 'healing_health',
            icon = '78 0 9 12',
            iconSize = '9 12',
            ui = 'healing_health'
        },
        {
            name = 'Mana',
            identifier = 'healing_mana',
            icon = '91 0 9 12',
            iconSize = '9 12',
            ui = 'healing_mana'
        },
        --{
        --    name = 'Conditions',
        --    icon = '299 0 12 9',
        --    iconSize = '12 9',
        --    ui = 'healing_conditions'
        --},
        {
            name = 'Group',
            identifier = 'healing_group',
            icon = '26 0 12 12',
            iconSize = '12 12',
            ui = 'healing_group'
        },
      }
  },
  --{
  --    name = 'Group Healing',
  --    icon = '26 0 12 12',
  --    iconSize = '12 12',
  --    ui = 'main_grouphealing',
  --    childs = {}
  --},
  --{
  --    name = 'Defense Fortify',
  --    icon = '39 0 8 12',
  --    iconSize = '8 12',
  --    ui = 'main_defense',
  --    childs = {}
  --},
  --{
  --    name = 'Strength',
  --    icon = '52 0 13 12',
  --    iconSize = '13 12',
  --    ui = 'main_fortify',
  --    childs = {}
  --},
  {
      name = 'Support',
      identifier = 'support',
      icon = '377 0 13 13',
      iconSize = '13 13',
      childs = {
        {
          name = 'General',
          identifier = 'support_general',
          icon = '65 0 10 10',
          iconSize = '10 10',
          ui = 'support_general',
          childs = {}
        },
        {
          name = 'Mana Shield',
          identifier = 'support_manashield',
          icon = '365 0 11 12',
          iconSize = '11 12',
          ui = 'support_manashield',
          childs = {}
        },
      }
  },
}

function getPageModule()
  if MiniBotMiniWindow.selectedPage == nil or MiniBotMiniWindow.selectedPage == '' then
      return nil
  end

  return modules.game_minibot[MiniBotMiniWindow.selectedPage .. 'Module']
end

local function lerp(a, b, t)
  return math.floor(a + (b - a) * t + 0.5)
end

local function interpolateColor(c1, c2, t)
  return {
    r = lerp(c1.r, c2.r, t),
    g = lerp(c1.g, c2.g, t),
    b = lerp(c1.b, c2.b, t)
  }
end

local function setPresetNameOnPanel()
  local prefix = 'Current preset:'
  local language = modules.game_minibot.getSettingsValue(false, 'language', 'ptbr')
  if language == 'ptbr' then
    prefix = "Preset selecionado:"
  elseif language == 'enus' then
    prefix = 'Current preset:'
  end

  for _, c in ipairs(MiniBotMiniWindow.presets.list:getChildren()) do
    if c.selectedPreset then
      MiniBotMiniWindow.presetName:setText(prefix .. ' \'' .. c:getText() .. '\'')
      break
    end
  end

  onGameWindowPresetnamgeChange(MiniBotMiniWindow.presets.buttons.gamewindow, true)
end

function internalAnimateWidgetExtension(widget, settings)
  local t = settings.currentStep / settings.steps
  local color = interpolateColor(settings.fromColor, settings.toColor, t)
  local rgbColor = rgbToHex(color)
  if rgbColor ~= nil and widget.extended ~= nil then
    widget.extended:setColor(rgbToHex(color))
  end

  settings.currentStep = settings.currentStep + settings.direction

  if settings.currentStep >= settings.steps then
    settings.direction = -1
    settings.currentStep = settings.steps
  elseif settings.currentStep <= 0 then
    settings.direction = 1
    settings.currentStep = 0
  end

  widget.colorChangeEvent = scheduleEvent(function()
    internalAnimateWidgetExtension(widget, settings)
  end, settings.duration / settings.steps)
end

function minibotAnimateExtension(widget)
  local settings = {
    fromColor = { r = 0xc3, g = 0x65, b = 0x80 },
    toColor   = { r = 0x18, g = 0x72, b = 0xC3 },
    duration = 1000,
    steps = 30,
    direction = 1,
    currentStep = 0
  }

  internalAnimateWidgetExtension(widget, settings)
end

function selectMinibotPanel(primary, secondary)
  local widget = MiniBotMiniWindow.tabs:getChildById('TabButton_' .. primary)
  if widget == nil then
      return
  end

  widget:setChecked(true)
  if secondary == nil then
      return
  end

  local panel = MiniBotMiniWindow.tabs:getChildById('ChildPanel_' .. primary)
  if panel == nil then
      return
  end

  local child = panel:getChildById('ChildButton_' .. secondary)
  if child == nil then
      return
  end

  child:setChecked(true)
end

function init()
  MiniBotMiniWindow = g_ui.displayUI('minibot')
  MiniBotMiniWindow:hide()

  MiniBotMiniWindow:constructEnviorementVariables()

  setupOptionsMainButton()

  loadPresetList()

  if g_game.isOnline() then
    onPlayerInfo()
    toggle()
  end

  for _, page in ipairs(pages) do
    local widget = g_ui.createWidget('MiniBotInfoTab', MiniBotMiniWindow.tabs)
    widget:constructEnviorementVariables()

    widget:setId('TabButton_' .. page.identifier)
    widget:setText(page.name)
    widget:setIconClip(torect(page.icon))
    widget:setIconSize(page.iconSize)
    if g_resources.isEncrypted() and page.disabled then
      widget:setEnabled(false)
      widget.extended:setText('Soon!')
      minibotAnimateExtension(widget)
    end

    if page.childs ~= nil and #(page.childs) > 0 then
      widget.downArrow:show()

      local panel = g_ui.createWidget('MiniBotPanelTab', MiniBotMiniWindow.tabs)
      panel:setId('ChildPanel_' .. page.identifier)
      local totalHeight = 0
      for _, child in ipairs(page.childs) do
        local innerChild = g_ui.createWidget('MiniBotChildInfoTab', panel)
        innerChild:constructEnviorementVariables()

        if g_resources.isEncrypted() and child.disabled then
          innerChild:setEnabled(false)
          innerChild.extended:setText('Soon!')
          minibotAnimateExtension(innerChild)
        end

        innerChild:setId('ChildButton_' .. child.identifier)
        innerChild:setText(child.name)
        innerChild:setIconClip(torect(child.icon))
        innerChild:setIconSize(child.iconSize)

        totalHeight = totalHeight + 20
        innerChild.onCheckChange = function()
          if innerChild.ignoreCallback then
              innerChild.rightArrow:setVisible(innerChild:isChecked())
              return
          end

          if not(innerChild:isChecked()) then
              innerChild.ignoreCallback = true
              innerChild:setChecked(true)
              innerChild.ignoreCallback = nil
              return
          end

          for _, c in ipairs(panel:getChildren()) do
              if c ~= innerChild then
                  c.ignoreCallback = true
                  c:setChecked(false)
                  c.ignoreCallback = nil
              end
          end

          innerChild.rightArrow:setVisible(innerChild:isChecked())

          if innerChild:isChecked() then
              loadMainPanel(child.ui)
          end
        end
      end

      panel:setHeight(totalHeight)
      panel:hide()

      widget.childPanel = panel
      widget.reloadMajorChilds = function()
        if widget:isChecked() then
          panel:show()
          local firstChild = panel:getChildByIndex(1)
          if firstChild ~= nil then
            firstChild:setChecked(true)
          end
          widget:setMarginBottom(0)
        else
          panel:hide()
          for _, c in ipairs(panel:getChildren()) do
            if c ~= innerChild then
              c.ignoreCallback = true
              c:setChecked(false)
              c.ignoreCallback = nil
            end
          end
          widget:setMarginBottom(3)
        end
      end
    else
      widget:setMarginBottom(3)
    end

    widget.onCheckChange = function()
      if widget.ignoreMajorCheck then
          return
      end

      if not(widget:isChecked()) then
          widget.ignoreMajorCheck = true
          widget:setChecked(true)
          widget.ignoreMajorCheck = nil
          return
      end

      if widget:isChecked() then
        for _, c in ipairs(MiniBotMiniWindow.tabs:getChildren()) do
          if c ~= widget then
            if c.childPanel ~= nil then
              c.reloadMajorChilds()
              c.downArrow:setVisible(true)
            else
              c.ignoreMajorCheck = true
              c:setChecked(false)
              if c.rightArrow ~= nil then
                c.rightArrow:setVisible(false)
              end
              c.ignoreMajorCheck = nil
            end
          end
        end
      end

      if page.childs ~= nil and #(page.childs) > 0 then
        widget.downArrow:setVisible(not(widget:isChecked()))
        if widget:isChecked() then
          widget.ignoreMajorCheck = true
          widget.reloadMajorChilds()
          widget:setChecked(false)
          widget.ignoreMajorCheck = nil
        else
          widget.reloadMajorChilds()
        end
      else
        widget.rightArrow:setVisible(widget:isChecked())
        if widget:isChecked() then
          loadMainPanel(page.ui)
        end
      end
    end
  end

  local firstChild = MiniBotMiniWindow.tabs:getChildByIndex(1)
  if firstChild ~= nil then
    firstChild:setChecked(true)
  end

  reloadLanguage()

  connect(g_minibot, {
    onWalkToNextNode = setupMinimapTexts,
  })

  -- g_game never emits onPlayerInfo (parsePlayerInfo has no callGlobalField), and
  -- this module loads at startup while still offline, so init() above never runs
  -- onPlayerInfo either. Without onGameStart no preset is ever selected on login
  -- and getPressetSettings() stays empty, leaving every feature inert.
  connect(g_game, {
    onGameStart = onPlayerInfo,
    onGameEnd = onGameEnd,
    onMissileTo = onMissileTo,
    onResourceBalance = onResourceBalance,
    onDeath = onPlayerDeath
  })

  connect(LocalPlayer, {
    onPartyMembersName = onPartyMembersName,
    onCaveBotTimestamp = onCaveBotTimestamp
  })

  -- Rastro do Auto Follow. Em Creature, nao em LocalPlayer: quem interessa e o
  -- jogador seguido, e o handler sai cedo enquanto nao ha alvo definido.
  connect(Creature, {
    onPositionChange = onFollowCreatureMove
  })
end

function terminate()
  stopAutoFollow()
  stopAutoFishing()

  if unbindMinibotHotkeys then
    unbindMinibotHotkeys()
  end

  disconnect(g_minibot, {
    onWalkToNextNode = setupMinimapTexts,
  })

  disconnect(g_game, {
    onGameStart = onPlayerInfo,
    onGameEnd = onGameEnd,
    onMissileTo = onMissileTo,
    onResourceBalance = onResourceBalance,
    onDeath = onPlayerDeath
  })

  disconnect(LocalPlayer, {
    onPartyMembersName = onPartyMembersName,
    onCaveBotTimestamp = onCaveBotTimestamp
  })

  disconnect(Creature, {
    onPositionChange = onFollowCreatureMove
  })

  for _, c in ipairs(MiniBotMiniWindow.tabs:getChildren()) do
    if c.colorChangeEvent ~= nil then
      removeEvent(c.colorChangeEvent)
      c.colorChangeEvent = nil
    end
  end

  if MiniBotMiniWindow.disableCaveBotEvent ~= nil then
    removeEvent(MiniBotMiniWindow.disableCaveBotEvent)
    MiniBotMiniWindow.disableCaveBotEvent = nil
  end

  if MiniBotMiniWindowDialog ~= nil then
    MiniBotMiniWindowDialog:destroy()
    MiniBotMiniWindowDialog = nil
  end

  if MiniBotEditPresetMiniWindow ~= nil then
    MiniBotEditPresetMiniWindow:destroy()
    MiniBotEditPresetMiniWindow = nil
  end

  if MiniBotImportPresetMiniWindow ~= nil then
    MiniBotImportPresetMiniWindow:destroy()
    MiniBotImportPresetMiniWindow = nil
  end

  if MiniBotGameWindowPanel ~= nil then
    MiniBotGameWindowPanel:destroy()
    MiniBotGameWindowPanel = nil
  end

  if MiniBotMiniWindow.refreshScheduled ~= nil then
    for _, event in ipairs(MiniBotMiniWindow.refreshScheduled) do
      removeEvent(event)
    end
    MiniBotMiniWindow.refreshScheduled = nil
  end

  if MiniBotMiniWindow.eventTicks ~= nil then
    removeEvent(MiniBotMiniWindow.eventTicks)
    MiniBotMiniWindow.eventTicks = nil
  end

  local pageModule = getPageModule()
  if pageModule ~= nil then
    pageModule.terminate()
  end

  MiniBotMiniWindow:destroy()

  MiniBotMiniWindow = nil
  MiniBotToggleButton = nil
end

function internalToggle(toggle)
  MiniBotMiniWindow:setVisible(toggle)
end

function onMissileTo(...)
  if support_generalModule ~= nil then
    support_generalModule.onMissileTo(...)
  end
end

function onPartyMembersName(_, list)
  if healing_groupModule.getSelectedListType() == 'party' then
    healing_groupModule.reloadInternalModule()
  end
end

function getDropDownCatcher()
  return MiniBotMiniWindow.dropDownCatcher
end

function onClose()
  if MiniBotMiniWindow == nil then
    return
  end

  if MiniBotEditPresetMiniWindow ~= nil then
    MiniBotEditPresetMiniWindow:destroy()
    MiniBotEditPresetMiniWindow = nil
  end

  if MiniBotImportPresetMiniWindow ~= nil then
    MiniBotImportPresetMiniWindow:destroy()
    MiniBotImportPresetMiniWindow = nil
  end

  setSideButtonChecked(false)
  MiniBotMiniWindow:hide()
end

function hide()
  onClose()
end

function setSideButtonChecked(state)
  if state then
    return
  end

  if modules.game_sidebuttons == nil or modules.game_sidebuttons.getButtonById == nil then
    return
  end

  local sideButton = modules.game_sidebuttons.getButtonById("button_minibot")
  if sideButton and sideButton.button then
    sideButton.button:setChecked(state)
  end
end

function toggle()
  if MiniBotMiniWindow:isVisible() then
    MiniBotMiniWindow:hide()
  else
    show()
  end
end

function show()
  if not(MiniBotMiniWindow:isVisible()) then
    MiniBotMiniWindow.dropDownCatcher:hide()
    MiniBotMiniWindow:show()
    MiniBotMiniWindow:focus()
    setSideButtonChecked(true)
    refreshGoldBalance()

    local pageModule = getPageModule()
    if pageModule ~= nil then
      pageModule.terminate()
      pageModule.init(MiniBotMiniWindow.main:getChildByIndex(1))
    end
  end
end

function setupOptionsMainButton()
  if MiniBotToggleButton then
      return
  end

  if modules.game_sidebuttons ~= nil and modules.game_sidebuttons.getButtonById ~= nil then
    MiniBotToggleButton = modules.game_sidebuttons.getButtonById("button_minibot")
  end
end

function createBrandnewPreset(uid)
  local lastPreset = uid
  if uid == nil then
    lastPreset = getSettingsValue(false, 'last_preset', 0) + 1
  end

  local entry = {
    name = ('New Preset #' .. lastPreset),
    uid = lastPreset,
    creation = os.time()
  }

  if uid == nil then
    setSettingsValue(false, 'last_preset', lastPreset)
  end

  return entry
end

function getPressetSettings()
  local settings = _loadMiniBotSettings()

  local currentPreset = nil
  for _, c in ipairs(MiniBotMiniWindow.presets.list:getChildren()) do
    if c.selectedPreset then
      currentPreset = c.presetUid
      break
    end
  end

  if currentPreset == nil then
    return {}
  end

  if settings['presets'] == nil then
    settings['presets'] = {}
  end

  return settings['presets'][tostring(currentPreset)] or {}
end

function setPressetSettings(value)
  local settings = _loadMiniBotSettings()

  local currentPreset = nil
  for _, c in ipairs(MiniBotMiniWindow.presets.list:getChildren()) do
    if c.selectedPreset then
      currentPreset = c.presetUid
      break
    end
  end

  if currentPreset == nil then
    return
  end

  if settings['presets'] == nil then
    settings['presets'] = {}
  end

  if settings['presets'][tostring(currentPreset)] == nil then
    settings['presets'][tostring(currentPreset)] = {}
  end

  for k, v in pairs(value) do
    settings['presets'][tostring(currentPreset)][k] = v
  end

  _saveMiniBotSettings()
end

function getSettingsValue(ownPlayer, key, default)
  local settings = _loadMiniBotSettings()

  if not(ownPlayer) then
    return settings[key] or default
  end

  local cSettings = settings[g_game.getCharacterName()]
  if cSettings == nil then
    return default
  end

  return cSettings[key] or default
end

function setSettingsValue(ownPlayer, key, value)
  local settings = _loadMiniBotSettings()

  if not(ownPlayer) then
    settings[key] = value
    _saveMiniBotSettings()
    return
  end

  if settings[g_game.getCharacterName()] == nil then
    settings[g_game.getCharacterName()] = {}
  end

  settings[g_game.getCharacterName()][key] = value
  _saveMiniBotSettings()
end

function onClickPresetEntry(widget, ignoreSave)
  for _, c in ipairs(widget:getParent():getChildren()) do
    if c ~= widget then
      c.mask:hide()
      c.selectedPreset = false
    end
  end

  widget.mask:show()
  widget.selectedPreset = true
  setPresetNameOnPanel()

  if not(ignoreSave) then
    setSettingsValue(true, 'selected_preset', widget.presetUid)
  end

  if MiniBotMiniWindow:isVisible() then
    local pageModule = getPageModule()
    if pageModule ~= nil then
      pageModule.terminate()
      pageModule.init(MiniBotMiniWindow.main:getChildByIndex(1))
    end
  end

  onGameWindowPresetnamgeChange(MiniBotMiniWindow.presets.buttons.gamewindow, true)
  reloadInternalModules()
  g_minibot.cycle()
end

function createPresetWidget(entry)
  local widget = g_ui.createWidget('MiniBotPresetEntry', MiniBotMiniWindow.presets.list)
  widget:constructEnviorementVariables()

  widget:setText(entry.name)
  widget:setTooltip(entry.name)
  widget.onMousePress = openPresetGameMenu

  widget.presetUid = entry.uid

  if (MiniBotMiniWindow.presets.list:getChildCount() % 2) == 0 then
    widget:setBackgroundColor('#484848')
  end

  widget.onLeftClick = function()
    onClickPresetEntry(widget)
  end
end

function loadPresetList()
  local presets = {}
  local sPresets = getSettingsValue(false, 'presets', {})
  for _, entry in pairs(sPresets) do
    table.insert(presets, entry)
  end
  table.sort(presets, function(a, b)
    return a.creation < b.creation
  end)

  if #presets == 0 then
    local newEntry = createBrandnewPreset()
    sPresets[tostring(newEntry.uid)] = newEntry
    table.insert(presets, newEntry)
    setSettingsValue(false, 'presets', sPresets)
  end

  MiniBotMiniWindow.presets.list:destroyChildren()
  for _, entry in ipairs(presets) do
    createPresetWidget(entry)
  end
end

function reloadInternalModules()
  if MiniBotMiniWindow.refreshScheduled ~= nil then
    for _, event in ipairs(MiniBotMiniWindow.refreshScheduled) do
      removeEvent(event)
    end
    MiniBotMiniWindow.refreshScheduled = nil
  end

  MiniBotMiniWindow.refreshScheduled = {}
  for curIndex, entry in ipairs(pages) do
    table.insert(MiniBotMiniWindow.refreshScheduled, scheduleEvent(function()
      if entry.ui ~= nil then
        ((modules.game_minibot[entry.ui .. 'Module'])['reloadInternalModule'])()
      elseif entry.childs ~= nil then
        for _, child in ipairs(entry.childs) do
          if child.ui ~= nil then
            ((modules.game_minibot[child.ui .. 'Module'])['reloadInternalModule'])()
          end
        end
      end
    end, 25 * curIndex))
  end
end

function selectNextPreset()
  if MiniBotMiniWindow.presets.list:getChildCount() == 0 then
    return
  end

  local next = nil
  for i = 1, MiniBotMiniWindow.presets.list:getChildCount() do
    local c = MiniBotMiniWindow.presets.list:getChildByIndex(i)
    if c ~= nil and c.selectedPreset then
      next = MiniBotMiniWindow.presets.list:getChildByIndex(i + 1)
      break
    end
  end

  if next == nil then
    next = MiniBotMiniWindow.presets.list:getChildByIndex(1)
  end

  if next == nil or next.selectedPreset then
    return
  end

  next:focus()
  next:onLeftClick()
  modules.game_textmessage.displayStatusMessage('Assistant preset selected: ' .. next:getText(), true)
end

function selectPreviousPreset()
  if MiniBotMiniWindow.presets.list:getChildCount() == 0 then
    return
  end

  local previous = nil
  for i = MiniBotMiniWindow.presets.list:getChildCount(), 1, -1 do
    local c = MiniBotMiniWindow.presets.list:getChildByIndex(i)
    if c ~= nil and c.selectedPreset and i > 1 then
      previous = MiniBotMiniWindow.presets.list:getChildByIndex(i - 1)
      break
    end
  end

  if previous == nil then
    previous = MiniBotMiniWindow.presets.list:getChildByIndex(MiniBotMiniWindow.presets.list:getChildCount())
  end

  if previous == nil or previous.selectedPreset then
    return
  end

  previous:focus()
  previous:onLeftClick()
  modules.game_textmessage.displayStatusMessage('Assistant preset selected: ' .. previous:getText(), true)
end

function onPlayerInfo()
  -- No g_stats.startEvent/endEvent here: this build's g_stats only binds
  -- types/get/clear/getSlow/getSleepTime (see framework/luafunctions.cpp). Those
  -- calls are leftovers from another fork and throw the moment this runs.
  g_minibot.reset()

  local ignoreReload = false
  local selectedPreset = getSettingsValue(true, 'selected_preset', nil)
  for index, c in ipairs(MiniBotMiniWindow.presets.list:getChildren()) do
    if selectedPreset == nil or c.presetUid == selectedPreset or index == MiniBotMiniWindow.presets.list:getChildCount() then
      onClickPresetEntry(c, true)
      ignoreReload = true
      break
    end
  end

  if not(ignoreReload) then
    reloadInternalModules()
  end

  g_minibot.cycle()

  -- Pede ao servidor o estado autoritativo do cave bot (tempo/saldo/preco).
  g_game.requestCaveBot()

  -- (Re)bind the assistant hotkeys now that the player + settings are loaded.
  if bindMinibotHotkeys then
    bindMinibotHotkeys()
  end

  MiniBotMiniWindow.presets.buttons.gamewindow:setChecked(getSettingsValue(true, 'show_preset_name', false))

  -- Runs after the preset is selected above, so the Auto Bless setting is readable.
  -- The Auto Follow tick is (re)started by support_general's reloadInternalModule.
  sendPendingBless()
end

-- Support > General: Auto Bless and Auto Follow have no engine (C++) module, so
-- the death/login hooks and the follow tick live here, where they keep running
-- while the Assistant window is closed.
local function getSupportGeneralSettings()
  if MiniBotMiniWindow == nil then
    return {}
  end

  return getPressetSettings()['support_main'] or {}
end

local function findPlayerByName(name)
  local player = g_game.getLocalPlayer()
  if player == nil then
    return nil
  end

  name = name:lower()
  -- multiFloor = true: e assim que o follow enxerga o alvo no degrau de cima/baixo
  -- logo depois de ele subir ou descer. Com o modo de um andar so, a troca de piso
  -- seria indistinguivel de "saiu da tela" e o rastro nunca marcaria o degrau.
  for _, creature in ipairs(g_map.getSpectators(player:getPosition(), true)) do
    if creature:isPlayer() and not(creature:isLocalPlayer()) and creature:getName():lower() == name then
      return creature
    end
  end

  return nil
end

-- Ritmo do follow. 250ms e o suficiente: o destino so muda quando o alvo troca
-- de SQM, e e a troca de destino (nao o tick) que dispara um autoWalk novo.
local AUTO_FOLLOW_TICK = 250
-- Depois de um passo manual (setas/WASD) o follow para de agir por um instante,
-- senao o Assistente e o jogador brigam pelo controle do personagem.
local AUTO_FOLLOW_MANUAL_PAUSE = 1200
-- Tempo entre as tentativas de recuperacao, e teto para chegar ao SQM alvo.
local AUTO_FOLLOW_RECOVER_STEP = 1200
local AUTO_FOLLOW_RECOVER_TIMEOUT = 15000
local AUTO_FOLLOW_RETRY = 1000
local AUTO_FOLLOW_ROPE_ID = 3003 -- rope (data/items/items.xml do servidor)

local function samePos(a, b)
  return a ~= nil and b ~= nil and a.x == b.x and a.y == b.y and a.z == b.z
end

local function posDistance(a, b)
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

local function isFollowWalkable(pos)
  if pos.x < 0 or pos.y < 0 then
    return false
  end

  local tile = g_map.getTile(pos)
  -- isWalkable(false) considera criaturas: nao adianta mirar num SQM ocupado.
  return tile ~= nil and tile:isWalkable(false) and tile:isPathable()
end

-- O SQM vizinho ao alvo que fica mais perto de nos. Mirar no SQM do proprio alvo
-- faria o findPath terminar em cima da criatura e o ultimo passo ser recusado.
local function bestFollowTile(playerPos, targetPos)
  local best, bestCost = nil, nil
  for dx = -1, 1 do
    for dy = -1, 1 do
      if dx ~= 0 or dy ~= 0 then
        local pos = { x = targetPos.x + dx, y = targetPos.y + dy, z = targetPos.z }
        if isFollowWalkable(pos) then
          -- Chebyshev e o custo real de passos; manhattan so desempata, para
          -- preferir a aproximacao reta a diagonal.
          local cost = posDistance(playerPos, pos) * 10
                     + math.abs(playerPos.x - pos.x) + math.abs(playerPos.y - pos.y)
          if bestCost == nil or cost < bestCost then
            best, bestCost = pos, cost
          end
        end
      end
    end
  end

  return best
end

-- O rastro precisa de TODOS os SQMs do alvo, nao dos que o tick por acaso viu. Um
-- passo com haste sai em ~150ms, abaixo do tick de 250ms: o SQM da escada e
-- justamente o que se perde, e ai o `use` da recuperacao cairia no tile errado.
-- Por isso quem alimenta o rastro e o onPositionChange de Creature.
local function updateFollowTrail(pos)
  if pos == nil or samePos(pos, followLastPos) then
    return
  end

  followPrevPos = followLastPos
  followLastPos = pos

  if followPrevPos ~= nil and followPrevPos.z ~= pos.z then
    followFloorHint = true
  end
end

-- Global e conectado em Creature (nao em LocalPlayer): dispara para toda criatura
-- que anda, entao sai cedo no caso comum.
function onFollowCreatureMove(creature, newPos, _)
  if followTargetName == nil or creature == nil or newPos == nil then
    return
  end

  if not(creature:isPlayer()) or creature:isLocalPlayer() then
    return
  end

  if creature:getName():lower() ~= followTargetName then
    return
  end

  updateFollowTrail(newPos)
end

local function warnAutoFollow(reason, name)
  if followWarning == reason then
    return
  end
  followWarning = reason

  local ptbr = getSettingsValue(false, 'language', 'ptbr') == 'ptbr'
  local text
  if reason == 'lost' then
    if ptbr then
      text = 'Follow automatico: perdi ' .. name .. ' de vista e nao achei por onde ele passou.'
    else
      text = 'Auto follow: lost sight of ' .. name .. ' and could not find where they went.'
    end
  else
    if ptbr then
      text = 'Follow automatico: ' .. name .. ' nao esta na sua tela.'
    else
      text = 'Auto follow: ' .. name .. ' is not on your screen.'
    end
  end

  if modules.game_textmessage ~= nil then
    modules.game_textmessage.displayFailureMessage(text)
  end
end

local function followWalkTo(player, dest)
  if dest == nil or samePos(player:getPosition(), dest) then
    return
  end

  -- autoWalk manda a rota inteira num pacote e refaz o findPath: reemitir a cada
  -- tick viraria flood de walk. So reemite quando o destino muda ou quando a
  -- caminhada anterior ja terminou/falhou sem chegar la.
  if samePos(followWalkDest, dest) then
    if player:isAutoWalking() then
      return
    end

    -- Destino repetido e caminhada parada = rota falhou (SQM bloqueado). Sem este
    -- freio seriam 4 findPath por segundo tentando o mesmo caminho impossivel.
    if g_clock.millis() < followWalkRetry then
      return
    end
  end

  followWalkDest = dest
  followWalkRetry = g_clock.millis() + AUTO_FOLLOW_RETRY
  player:autoWalk(dest)
end

local function clearFollowRecover()
  followRecoverPos = nil
  followRecoverStage = 0
  followRecoverNext = 0
  followRecoverDeadline = 0
  followFloorHint = false
end

-- Recuperacao: o alvo sumiu (saiu da tela, subiu/desceu ou entrou num teleport).
-- A ideia e ir pisar no SQM de onde ele saiu. Escada, buraco e teleport resolvem
-- sozinhos so de pisar; escada de mao, bueiro e corda precisam de uma acao, que
-- e tentada em escala depois que chegamos e nada aconteceu.
--
-- Nao ha classificacao de tile por id de proposito: a flag hasFloorChange do .dat
-- nunca e preenchida no caminho protobuf/appearances que este client usa (so em
-- protocolo < 7.80), e listas de id fixas seriam ids do Tibia global, que nao
-- valem nos assets customizados do Valdraken.
local function autoFollowRecover(player, name)
  local ppos = player:getPosition()

  if followRecoverPos == nil then
    -- O ultimo SQM conhecido que esteja no NOSSO andar. Se o alvo trocou de piso,
    -- followLastPos ja esta no andar novo e quem serve e o anterior: o SQM da
    -- escada/buraco.
    if followLastPos ~= nil and followLastPos.z == ppos.z then
      followRecoverPos = followLastPos
    elseif followPrevPos ~= nil and followPrevPos.z == ppos.z then
      followRecoverPos = followPrevPos
    else
      warnAutoFollow('lost', name)
      return
    end

    followRecoverStage = 0
    followRecoverNext = 0
    followRecoverDeadline = g_clock.millis() + AUTO_FOLLOW_RECOVER_TIMEOUT
  end

  if not(samePos(ppos, followRecoverPos)) then
    if g_clock.millis() > followRecoverDeadline then
      clearFollowRecover()
      warnAutoFollow('lost', name)
      return
    end

    followWalkTo(player, followRecoverPos)
    return
  end

  -- Chegamos e o alvo continua sumido. Cada estagio precisa de um intervalo: o
  -- servidor leva um tempo para responder, e sem isso os quatro seriam disparados
  -- no mesmo segundo.
  local now = g_clock.millis()
  if now < followRecoverNext then
    return
  end
  followRecoverNext = now + AUTO_FOLLOW_RECOVER_STEP

  if followRecoverStage == 0 then
    -- Pisamos e nada: talvez o alvo tenha entrado num SQM adiante que nao chegamos
    -- a ver (teleport). Segue mais um passo na direcao em que ele andava.
    followRecoverStage = 1
    if followPrevPos ~= nil and followLastPos ~= nil and followPrevPos.z == followLastPos.z then
      local ahead = {
        x = followLastPos.x + (followLastPos.x - followPrevPos.x),
        y = followLastPos.y + (followLastPos.y - followPrevPos.y),
        z = followLastPos.z
      }
      if not(samePos(ahead, followLastPos)) and isFollowWalkable(ahead) then
        followRecoverPos = ahead
        followRecoverDeadline = now + AUTO_FOLLOW_RECOVER_TIMEOUT
        return
      end
    end
  end

  -- Escada de mao, bueiro e corda so entram quando sabemos que o alvo trocou de
  -- andar. Se ele apenas correu para fora da tela no mesmo piso, dar use no SQM
  -- onde ele estava mexeria em alavanca, porta ou o que mais estivesse ali.
  if followFloorHint then
    local tile = g_map.getTile(ppos)
    local thing = tile ~= nil and tile:getTopUseThing() or nil

    if thing ~= nil and followRecoverStage <= 1 then
      followRecoverStage = 2
      g_game.use(thing) -- escada de mao / bueiro
      return
    end

    if thing ~= nil and followRecoverStage == 2 then
      followRecoverStage = 3
      local rope = g_game.findPlayerItem(AUTO_FOLLOW_ROPE_ID, -1)
      if rope ~= nil then
        g_game.useWith(rope, thing)
        return
      end
    end
  end

  clearFollowRecover()
  warnAutoFollow('lost', name)
end

local function autoFollowTick()
  autoFollowEvent = nil

  if not(g_game.isOnline()) then
    return
  end

  local sAutoFollow = getSupportGeneralSettings()['auto_follow']
  if sAutoFollow == nil or not(sAutoFollow['enabled']) then
    resetAutoFollowState()
    return
  end

  autoFollowEvent = scheduleEvent(autoFollowTick, AUTO_FOLLOW_TICK)

  local name = sAutoFollow['name'] or ''
  if name == '' then
    return
  end

  local player = g_game.getLocalPlayer()
  if player == nil or player:isDead() then
    return
  end

  -- game_walking marca cada passo manual em lastManualWalk. Usar esse valor evita
  -- registrar teclas por conta propria (e brigar com os binds do modulo de andar).
  local walking = modules.game_walking
  if walking ~= nil and walking.lastManualWalk ~= nil
     and g_clock.millis() - walking.lastManualWalk < AUTO_FOLLOW_MANUAL_PAUSE then
    followWalkDest = nil
    return
  end

  if player:isWalkLocked() then
    return
  end

  local ppos = player:getPosition()
  local target = findPlayerByName(name)
  local tpos = target ~= nil and target:getPosition() or nil

  -- Rede de seguranca: o rastro normal vem do onFollowCreatureMove, mas quem
  -- aparece na tela ja parado nao dispara evento nenhum.
  updateFollowTrail(tpos)

  if tpos ~= nil and tpos.z ~= ppos.z then
    followFloorHint = true
  end

  -- Alvo visivel e no mesmo andar: caminhada normal.
  if tpos ~= nil and tpos.z == ppos.z then
    clearFollowRecover()
    followWarning = nil

    -- Sobra do follow do servidor: ele andaria junto e brigaria com o autoWalk.
    local following = g_game.getFollowingCreature()
    if following ~= nil and following:getId() == target:getId() then
      g_game.follow(nil)
    end

    if posDistance(ppos, tpos) <= 1 then
      followWalkDest = nil
      return
    end

    followWalkTo(player, bestFollowTile(ppos, tpos) or tpos)
    return
  end

  -- Alvo fora da tela ou em outro andar: tenta reencontrar pelo rastro.
  if followLastPos == nil then
    warnAutoFollow('offscreen', name)
    return
  end

  autoFollowRecover(player, name)
end

-- Auto Fishing: usa a Mechanical Fishing Rod na Bath Tub a cada 2 segundos.
-- Os dois ids sao fixos (nao ha selecao de item na tela), entao ficam aqui.
local AUTO_FISHING_ROD_ID = 9306    -- Mechanical Fishing Rod (na backpack)
local AUTO_FISHING_SPOT_ID = 26077  -- Bath Tub (na tela)
local AUTO_FISHING_RIVER_ID = 4601  -- Rio (na tela) - opcao extra quando nao ha Bath Tub
local AUTO_FISHING_DELAY = 2000
local AUTO_FISHING_RIVER_DELAY = 1000

-- So conta o que esta na tela: a area visivel e 15x11 SQMs centrada no jogador,
-- e no mesmo andar (usar a vara num alvo de outro floor nao funciona).
-- includeGround: o rio (4601) costuma ser o ground do tile, entao precisa ser
-- checado com getGround; a Bath Tub e um item empilhado (getItems).
local function findFishingThingOnScreen(id, includeGround)
  local player = g_game.getLocalPlayer()
  if player == nil then
    return nil
  end

  local pos = player:getPosition()
  if pos == nil then
    return nil
  end

  for dx = -7, 7 do
    for dy = -5, 5 do
      -- x/y sao uint16 do lado do C++: coordenada negativa na borda do mapa
      -- daria wrap em vez de "tile inexistente".
      local x, y = pos.x + dx, pos.y + dy
      local tile = nil
      if x >= 0 and y >= 0 then
        tile = g_map.getTile({ x = x, y = y, z = pos.z })
      end
      if tile ~= nil then
        if includeGround then
          local ground = tile:getGround()
          if ground ~= nil and ground:getId() == id then
            return ground
          end
        end
        for _, item in ipairs(tile:getItems()) do
          if item:getId() == id then
            return item
          end
        end
      end
    end
  end

  return nil
end

local function findAutoFishingSpot()
  return findFishingThingOnScreen(AUTO_FISHING_SPOT_ID, false)
end

local function findAutoFishingRiver()
  return findFishingThingOnScreen(AUTO_FISHING_RIVER_ID, true)
end

-- O aviso so aparece quando o motivo muda: sem isso o tick de 2s viraria spam
-- na tela enquanto o jogador anda ate a Bath Tub.
-- reason: 'rod' (falta a vara) ou 'spot' (falta o alvo). riverEnabled ajusta o
-- texto de 'spot' para mencionar o rio, ja que nesse modo qualquer um dos dois serve.
local function warnAutoFishing(reason, riverEnabled)
  if autoFishingWarning == reason then
    return
  end
  autoFishingWarning = reason

  local ptbr = getSettingsValue(false, 'language', 'ptbr') == 'ptbr'
  local text
  if reason == 'rod' then
    if ptbr then
      text = 'Pesca automatica: voce precisa de uma Mechanical Fishing Rod numa mochila aberta.'
    else
      text = 'Auto fishing: you need a Mechanical Fishing Rod inside an open backpack.'
    end
  elseif riverEnabled then
    if ptbr then
      text = 'Pesca automatica: nao ha nenhuma Bath Tub nem rio na sua tela.'
    else
      text = 'Auto fishing: there is no Bath Tub or river on your screen.'
    end
  else
    if ptbr then
      text = 'Pesca automatica: nao ha nenhuma Bath Tub na sua tela.'
    else
      text = 'Auto fishing: there is no Bath Tub on your screen.'
    end
  end

  if modules.game_textmessage ~= nil then
    modules.game_textmessage.displayFailureMessage(text)
  end
end

local function autoFishingTick()
  autoFishingEvent = nil

  if not(g_game.isOnline()) then
    return
  end

  local sAutoFishing = getSupportGeneralSettings()['auto_fishing']
  if sAutoFishing == nil or not(sAutoFishing['enabled']) then
    return
  end

  -- findPlayerItem varre os slots do inventario e depois os containers ABERTOS:
  -- com a mochila fechada a vara nao e encontrada, dai o texto do aviso.
  local rod = g_game.findPlayerItem(AUTO_FISHING_ROD_ID, -1)
  local spot = findAutoFishingSpot()
  local riverEnabled = sAutoFishing['river_enabled'] and true or false
  local nextDelay = AUTO_FISHING_DELAY

  if rod == nil then
    warnAutoFishing('rod')
  elseif spot ~= nil then
    -- Prioridade: Bath Tub (delay padrao de 2s).
    autoFishingWarning = nil
    g_game.useWith(rod, spot)
  elseif riverEnabled then
    -- Sem Bath Tub: tenta um rio na tela (delay de 1s).
    local river = findAutoFishingRiver()
    if river ~= nil then
      autoFishingWarning = nil
      g_game.useWith(rod, river)
      nextDelay = AUTO_FISHING_RIVER_DELAY
    else
      warnAutoFishing('spot', true)
    end
  else
    warnAutoFishing('spot', false)
  end

  autoFishingEvent = scheduleEvent(autoFishingTick, nextDelay)
end

function reloadSupportRuntime()
  local sList = getSupportGeneralSettings()

  -- Auto Reconnect: client_entergame already owns the reconnect (scheduleAutoReconnect
  -- -> executeAutoReconnect -> CharacterList.doLogin); we only flip its switch, which
  -- until now no screen ever wrote. Both stores need it: executeAutoReconnect reads the
  -- per-character flag, and characterlist's onLogout overwrites that flag from the
  -- global setting, so writing only one of them gets silently undone.
  local sAutoReconnect = sList['auto_reconnect']
  local reconnectEnabled = sAutoReconnect ~= nil and sAutoReconnect['enabled'] or false
  g_settings.set('autoReconnect', reconnectEnabled)
  if g_game.isOnline() and modules.client_entergame ~= nil and modules.client_entergame.saveAutoReconnect ~= nil then
    modules.client_entergame.saveAutoReconnect(g_game.getCharacterName(), reconnectEnabled)
  end

  stopAutoFollow()
  stopAutoFishing()

  if not(g_game.isOnline()) then
    return
  end

  local sAutoFishing = sList['auto_fishing']
  if sAutoFishing ~= nil and sAutoFishing['enabled'] then
    -- Primeiro tick imediato: e ele que avisa na hora se falta a vara ou a Bath Tub.
    autoFishingEvent = scheduleEvent(autoFishingTick, 1)
  end

  local sAutoFollow = sList['auto_follow']
  if sAutoFollow == nil or not(sAutoFollow['enabled']) then
    return
  end

  local name = sAutoFollow['name'] or ''
  if name == '' then
    return
  end

  -- Liga o rastro (onFollowCreatureMove sai cedo enquanto isto for nil).
  followTargetName = name:lower()
  autoFollowEvent = scheduleEvent(autoFollowTick, 1)
end

function onPlayerDeath()
  local sAutoBless = getSupportGeneralSettings()['auto_bless']
  if sAutoBless == nil or not(sAutoBless['enabled']) then
    return
  end

  -- Persisted per character: the command can only be sent on the next login.
  setSettingsValue(true, 'pending_bless', true)
end

function sendPendingBless()
  if not(getSettingsValue(true, 'pending_bless', false)) then
    return
  end

  local sAutoBless = getSupportGeneralSettings()['auto_bless']
  if sAutoBless == nil or not(sAutoBless['enabled']) then
    -- Turned off between the death and this login.
    setSettingsValue(true, 'pending_bless', false)
    return
  end

  scheduleEvent(function()
    if not(g_game.isOnline()) then
      return
    end

    g_game.talk('!bless')
    -- Only cleared once actually sent, so a disconnect right after login still
    -- blesses on the next one.
    setSettingsValue(true, 'pending_bless', false)
  end, 2000)
end

function onGameEnd()
  stopAutoFollow()
  stopAutoFishing()

  if MiniBotEditPresetMiniWindow ~= nil then
    MiniBotEditPresetMiniWindow:destroy()
    MiniBotEditPresetMiniWindow = nil
  end

  if MiniBotImportPresetMiniWindow ~= nil then
    MiniBotImportPresetMiniWindow:destroy()
    MiniBotImportPresetMiniWindow = nil
  end

  if MiniBotMiniWindow.disableCaveBotEvent ~= nil then
    removeEvent(MiniBotMiniWindow.disableCaveBotEvent)
    MiniBotMiniWindow.disableCaveBotEvent = nil
  end

  if MiniBotMiniWindow.eventTicks ~= nil then
    removeEvent(MiniBotMiniWindow.eventTicks)
    MiniBotMiniWindow.eventTicks = nil
  end

  MiniBotMiniWindow:hide()
end

function onClickNewPreset()
  local sPresets = getSettingsValue(false, 'presets', {})
  local entry = createBrandnewPreset()
  createPresetWidget(entry)
  sPresets[tostring(entry.uid)] = entry
  setSettingsValue(false, 'presets', sPresets)
end

function onClickRemovePreset(widget)
  if MiniBotMiniWindow.presets.list:getChildCount() <= 1 then
    return
  end

  local presets = {}
  local sPresets = getSettingsValue(false, 'presets', {})
  for _, entry in pairs(sPresets) do
    if entry.uid ~= widget.presetUid then
      presets[tostring(entry.uid)] = entry
    end
  end

  setSettingsValue(false, 'presets', presets)
  loadPresetList()

  local firstChild = MiniBotMiniWindow.presets.list:getChildByIndex(1)
  if firstChild ~= nil then
    firstChild:onLeftClick()
  end
end

function loadMainPanel(ui)
  local pageModule = getPageModule()
  if pageModule ~= nil then
      pageModule.terminate()
  end

  MiniBotMiniWindow.selectedPage = ui
  MiniBotMiniWindow.main:destroyChildren()
  g_ui.loadUI('/modules/game_minibot/pages/' .. ui, MiniBotMiniWindow.main)

  pageModule = getPageModule()
  if pageModule ~= nil then
      pageModule.init(MiniBotMiniWindow.main:getChildByIndex(1))

      if pageModule.reloadLanguage ~= nil then
        pageModule.reloadLanguage(modules.game_minibot.getSettingsValue(false, 'language', 'ptbr'))
      end
  end
end

function callMethod(method, ...)
  local pageModule = getPageModule()
  if pageModule ~= nil then
      if pageModule[method] == nil then
          print('Invalid MiniBot Info method:', method)
          return
      end

      (pageModule[method])(...)
  end
end

function openEditPresetNameWindow(name, onOkEditPreset, onCloseEditPreset)
  local forceClose = false
  if onCloseEditPreset == nil then
    forceClose = true
    onCloseEditPreset = function()
      if MiniBotEditPresetMiniWindow ~= nil then
        MiniBotEditPresetMiniWindow:destroy()
        MiniBotEditPresetMiniWindow = nil
      end

      MiniBotMiniWindow:show()
    end
  end

  if MiniBotEditPresetMiniWindow ~= nil then
    MiniBotEditPresetMiniWindow:destroy()
    MiniBotEditPresetMiniWindow = nil
  end

  if MiniBotImportPresetMiniWindow ~= nil then
    MiniBotImportPresetMiniWindow:destroy()
    MiniBotImportPresetMiniWindow = nil
  end

  MiniBotMiniWindow:hide()

  MiniBotEditPresetMiniWindow = g_ui.displayUI('minibot_editpreset')
  MiniBotEditPresetMiniWindow:show()

  MiniBotEditPresetMiniWindow:constructEnviorementVariables()

  MiniBotEditPresetMiniWindow.name:setText(name)

  MiniBotEditPresetMiniWindow.onEscape = function()
    onCloseEditPreset()
  end

  MiniBotEditPresetMiniWindow.cancel.onLeftClick = function()
    onCloseEditPreset()
  end

  MiniBotEditPresetMiniWindow.name.onTextChange = function()
    if MiniBotEditPresetMiniWindow.name:getText() == '' then
      MiniBotEditPresetMiniWindow.ok:setEnabled(false)
      MiniBotEditPresetMiniWindow.warn:setPhantom(false)
      return
    end

    MiniBotEditPresetMiniWindow.ok:setEnabled(MiniBotEditPresetMiniWindow.name:getText() ~= name)
    MiniBotEditPresetMiniWindow.warn:setPhantom(MiniBotEditPresetMiniWindow.ok:isEnabled())
  end

  MiniBotEditPresetMiniWindow.ok.onLeftClick = function()
    onOkEditPreset(MiniBotEditPresetMiniWindow.name:getText())
    if forceClose then
      onCloseEditPreset()
    end
  end

  MiniBotEditPresetMiniWindow.onEnter = function()
    onOkEditPreset(MiniBotEditPresetMiniWindow.name:getText())
    if forceClose then
      onCloseEditPreset()
    end
  end
end

function openPresetGameMenu(widget, mousePos, mouseButton)
  if mouseButton ~= MouseRightButton then
      return
  end

  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)

  menu:addOption("Edit '" .. widget:getText() .. "' name", function()
    local function onCloseEditPreset()
      if MiniBotEditPresetMiniWindow ~= nil then
        MiniBotEditPresetMiniWindow:destroy()
        MiniBotEditPresetMiniWindow = nil
      end

      MiniBotMiniWindow:show()
    end

    local function onOkEditPreset(input)
      if not(MiniBotEditPresetMiniWindow.ok:isEnabled()) then
        return
      end

      widget:setText(input)
      setPresetNameOnPanel()

      local presets = {}
      local sPresets = getSettingsValue(false, 'presets', {})
      for _, entry in pairs(sPresets) do
        if entry.uid ~= widget.presetUid then
          presets[tostring(entry.uid)] = entry
        else
          entry.name = input
          presets[tostring(entry.uid)] = entry
        end
      end

      setSettingsValue(false, 'presets', presets)
      onCloseEditPreset()
    end

    openEditPresetNameWindow(widget:getText(), onOkEditPreset, onCloseEditPreset)
  end)

  menu:addOption("Remove '" .. widget:getText() .. "'", function()
    modules.game_minibot.onClickRemovePreset(widget)
  end)

  menu:display(mousePos)
  return true
end

function importNewPreset(recorder)
  if MiniBotEditPresetMiniWindow ~= nil then
    MiniBotEditPresetMiniWindow:destroy()
    MiniBotEditPresetMiniWindow = nil
  end

  if MiniBotImportPresetMiniWindow ~= nil then
    MiniBotImportPresetMiniWindow:destroy()
    MiniBotImportPresetMiniWindow = nil
  end

  MiniBotMiniWindow:hide()

  MiniBotImportPresetMiniWindow = g_ui.displayUI('minibot_importpreset')
  MiniBotImportPresetMiniWindow:show()

  MiniBotImportPresetMiniWindow:constructEnviorementVariables()

  local function onCloseImportPreset()
    if MiniBotImportPresetMiniWindow ~= nil then
      MiniBotImportPresetMiniWindow:destroy()
      MiniBotImportPresetMiniWindow = nil
    end

    MiniBotMiniWindow:show()
  end

  local function onOkImportPreset()
    if not(MiniBotImportPresetMiniWindow.ok:isEnabled()) then
      return
    end

    local newPreset = table.unobscure(MiniBotImportPresetMiniWindow.name:getText())
    if recorder then
      modules.game_minibot.callMethod('onImportCode', newPreset)
    else
      local sPresets = getSettingsValue(false, 'presets', {})

      local newUID = getSettingsValue(false, 'last_preset', 0) + 1
      newPreset['uid'] = newUID
      newPreset['creation'] = os.time()
      newPreset['DeusOT_Assistant_Preset_Export'] = nil
      newPreset['version'] = nil
      sPresets[tostring(newUID)] = newPreset
      setSettingsValue(false, 'last_preset', newUID)
      setSettingsValue(false, 'presets', sPresets)

      createPresetWidget(newPreset)
    end
    onCloseImportPreset()
  end

  MiniBotImportPresetMiniWindow.onEscape = function()
    onCloseImportPreset()
  end

  MiniBotImportPresetMiniWindow.cancel.onLeftClick = function()
    onCloseImportPreset()
  end

  MiniBotImportPresetMiniWindow.name.onTextChange = function()
    MiniBotImportPresetMiniWindow.versionWarn:hide()
    if MiniBotImportPresetMiniWindow.name:getText() == '' then
      MiniBotImportPresetMiniWindow.ok:setEnabled(false)
      MiniBotImportPresetMiniWindow.warn:setPhantom(false)
      return
    end

    local obscuredCode = table.unobscure(MiniBotImportPresetMiniWindow.name:getText())
    if obscuredCode == nil or type(obscuredCode) ~= 'table' then
      MiniBotImportPresetMiniWindow.ok:setEnabled(false)
      MiniBotImportPresetMiniWindow.warn:setPhantom(false)
      return
    end

    if recorder then
      if not(obscuredCode['version']) or type(obscuredCode['version']) ~= 'number' or obscuredCode['version'] <= 0 then
        MiniBotImportPresetMiniWindow.ok:setEnabled(false)
        MiniBotImportPresetMiniWindow.warn:setPhantom(false)
        return
      end

      if obscuredCode['version'] ~= hunting_recorderModule.getExportCodeVersion() then
        MiniBotImportPresetMiniWindow.ok:setEnabled(false)
        MiniBotImportPresetMiniWindow.versionWarn:show()
        return
      end
    else
      if not(obscuredCode['DeusOT_Assistant_Preset_Export']) or not(obscuredCode['version']) or type(obscuredCode['version']) ~= 'number' or obscuredCode['version'] <= 0 then
        MiniBotImportPresetMiniWindow.ok:setEnabled(false)
        MiniBotImportPresetMiniWindow.warn:setPhantom(false)
        return
      end

      if obscuredCode['version'] ~= miniBotVersion then
        MiniBotImportPresetMiniWindow.versionWarn:show()
      end
    end

    MiniBotImportPresetMiniWindow.warn:setPhantom(true)
    MiniBotImportPresetMiniWindow.ok:setEnabled(true)
  end

  MiniBotImportPresetMiniWindow.ok.onLeftClick = function()
    onOkImportPreset()
  end

  MiniBotImportPresetMiniWindow.onEnter = function()
    onOkImportPreset()
  end
end

function onExportCurrentPreset()
  local settings = getPressetSettings()
  if settings['name'] == nil or settings['name'] == '' then
    for _, widget in ipairs(MiniBotMiniWindow.presets.list:getChildren()) do
      if widget.selectedPreset then
        settings['name'] = widget:getText()
        break
      end
    end
  end
  if settings['name'] == nil or settings['name'] == '' then
    settings['name'] = 'Default'
  end

  settings['DeusOT_Assistant_Preset_Export'] = true
  settings['version'] = miniBotVersion
  g_window.setClipboardText(table.obscure(settings))

  local message = ""
  local language = modules.game_minibot.getSettingsValue(false, 'language', 'ptbr')
  if language == 'ptbr' then
      message = "Seu preset '" .. settings['name'] .. "' foi exportada com sucesso para a sua area de transferencia. (CTRL + C)"
  elseif language == 'enus' then
      message = "Your preset '" .. settings['name'] .. "' has been succesfully exported into your clipboard. (CTRL + C)"
  end
  modules.game_minibot.openConfirmationWindow("DeusOT Assistant presets", message)
end

function reloadLanguage()
  local language = modules.game_minibot.getSettingsValue(false, 'language', 'ptbr')
  if language == 'ptbr' then
    MiniBotMiniWindow:setText('Assistente')
    MiniBotMiniWindow.clipboard:setTooltip('Exportar preset para a area de transferencia.')
    MiniBotMiniWindow.presets.buttons.new:setText('Novo')
    MiniBotMiniWindow.presets.buttons.import:setText('Importar')
    MiniBotMiniWindow.presets.buttons.gamewindow:setTooltip('Mostrar nome do preset selecionado na janela de jogo.')
  elseif language == 'enus' then
    MiniBotMiniWindow:setText('Assistant')
    MiniBotMiniWindow.clipboard:setTooltip('Export preset to clipboard.')
    MiniBotMiniWindow.presets.buttons.new:setText('New')
    MiniBotMiniWindow.presets.buttons.import:setText('Import')
    MiniBotMiniWindow.presets.buttons.gamewindow:setTooltip('Show selected preset name on Game Window.')
  end

  setPresetNameOnPanel()

  for _, c in ipairs(MiniBotMiniWindow.tabs:getChildren()) do
      if c.extended ~= nil and c.extended:getText() ~= '' then
        if language == 'ptbr' then
          c.extended:setText('Em breve!')
        elseif language == 'enus' then
          c.extended:setText('Soon!')
        end
      end
  end

  -- Reload modules
  local pageModule = getPageModule()
  if pageModule ~= nil then
      if pageModule.reloadLanguage == nil then
          return
      end

      (pageModule.reloadLanguage)(language)
  end
end

function onGameWindowPresetnamgeChange(widget, ignoreSave)
  if widget.ignoreCallback then
    return
  end

  -- Gravar a escolha nao depende de haver preset selecionado. Enquanto isto vinha
  -- depois da busca pelo preset (que retornava cedo quando nao havia nenhum),
  -- marcar a opcao sem preset selecionado era silenciosamente esquecido.
  if not(ignoreSave) then
    setSettingsValue(true, 'show_preset_name', widget:isChecked())
  end

  local panel = modules.game_interface.getMiniBotPresetPanel and modules.game_interface.getMiniBotPresetPanel()
  if panel == nil then
    return
  end

  local currentPresetName = nil
  for _, c in ipairs(MiniBotMiniWindow.presets.list:getChildren()) do
    if c.selectedPreset then
      currentPresetName = c:getText()
      break
    end
  end

  -- Esconder nao precisa de nome, so o mostrar. Sem preset selecionado o painel
  -- fica escondido; ao escolher um, onClickPresetEntry -> setPresetNameOnPanel
  -- chama isto de novo e o nome aparece.
  if widget:isChecked() and currentPresetName ~= nil then
    panel:show()
    panel:setMarginTop(7)
    panel:setText(currentPresetName)
  else
    panel:hide()
    panel:setMarginTop(0)
    panel:clearText()
  end
end

function setupMinimapTexts()
  local widgets = {}
  table.insert(widgets, modules.game_interface.getMapPanel())
  if modules.game_extendedmap ~= nil and modules.game_extendedmap.getExtendedMinimap ~= nil then
    table.insert(widgets, modules.game_extendedmap.getExtendedMinimap())
  end

  for _, widget in ipairs(widgets) do
    if g_settings.getBoolean('showMinimapMinibotText') and g_minibot.isModuleToggle(5) and g_minibot.getCurrentWalkIndex() > 0 then
      widget:setText("Node: #" .. g_minibot.getCurrentWalkIndex())
    else
      widget:clearText()
    end
  end
end

function openConfirmationWindow(title, message, yesFunc, noFunc)
  if MiniBotMiniWindowDialog ~= nil then
    MiniBotMiniWindowDialog:destroy()
    MiniBotMiniWindowDialog = nil
  end

  MiniBotMiniWindow:hide()

  if yesFunc == nil then
    MiniBotMiniWindowDialog = displayInfoBox(title, message)
    MiniBotMiniWindowDialog.ok = function()
      MiniBotMiniWindowDialog:destroy()
      MiniBotMiniWindowDialog = nil
      MiniBotMiniWindow:show()
      MiniBotMiniWindow:focus()
      return true
    end

    return
  end

  local yesCallback = function()
    if MiniBotMiniWindowDialog ~= nil then
      MiniBotMiniWindowDialog:hide()
      MiniBotMiniWindowDialog:destroy()
      MiniBotMiniWindowDialog = nil
    end

    MiniBotMiniWindow:show()
    MiniBotMiniWindow:focus()
    if yesFunc ~= nil then
      yesFunc()
    end
  end

  local noCallback = function()
    if MiniBotMiniWindowDialog ~= nil then
      MiniBotMiniWindowDialog:hide()
      MiniBotMiniWindowDialog:destroy()
      MiniBotMiniWindowDialog = nil
    end

    MiniBotMiniWindow:show()
    MiniBotMiniWindow:focus()
    if noFunc ~= nil then
      noFunc()
    end
  end

  MiniBotMiniWindowDialog = displayGeneralBox(title, message, {
    { text = 'No', callback = noCallback },
    { text = 'Yes', callback = yesCallback },
    anchor = AnchorHorizontalCenter
  }, yesCallback, noCallback)
end

function toggleDisableCavebot()
  if MiniBotMiniWindow.eventTicks ~= nil then
    removeEvent(MiniBotMiniWindow.eventTicks)
    MiniBotMiniWindow.eventTicks = nil
  end

  if not(g_minibot.isModuleToggle(5)) then
    return
  end

  --MiniBotMiniWindow.eventTicks = scheduleEvent(function()
  --  if g_minibot.isModuleToggle(5) then
  --    modules.game_minibot.onMiniBotGameWindowChangeFromPanel('huntingRecorder_gamewindow')
  --  end
  --end, math.random(20, 25) * 60 * 1000)
end

function onCaveBotTimestamp(localPlayer, timestamp)
  if timestamp >= os.time() then
    if g_minibot.isModuleToggle(5) then
      modules.game_minibot.onMiniBotGameWindowChangeFromPanel('huntingRecorder_gamewindow', false)
    end

    return
  end
end

function onResourceBalance(type, balance)
  if MiniBotMiniWindow.cacheBalanceBank == nil then
    MiniBotMiniWindow.cacheBalanceBank = 0
    MiniBotMiniWindow.cacheBalanceInventory = 0
  end

  if type == 0 then
    updateGoldBalanceText(balance, MiniBotMiniWindow.cacheBalanceInventory)
  elseif type == 1 then
    updateGoldBalanceText(MiniBotMiniWindow.cacheBalanceBank, balance)
  end
end

function getCacheResourceBalance()
  if MiniBotMiniWindow.cacheBalanceBank == nil then
    MiniBotMiniWindow.cacheBalanceBank = 0
    MiniBotMiniWindow.cacheBalanceInventory = 0
  end

  return MiniBotMiniWindow.cacheBalanceBank + MiniBotMiniWindow.cacheBalanceInventory
end
