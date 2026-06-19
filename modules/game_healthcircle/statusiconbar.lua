StatusIconBar = {}

local statusIconPanel = nil
local activeIcons = {}
local refreshPending = false

local cfg = {
  iconSize = 20,
  topBotSize = 10,
  marginRight = 10,
  fadeTime = 220,
  fadeInterval = 30,
  backgroundOpacity = 0.9,
}

local function getSettingOption(name, fallback)
  if not m_settings or not m_settings.getOption then
    return fallback
  end

  local ok, value = pcall(function() return m_settings.getOption(name) end)
  if not ok or value == nil then
    return fallback
  end

  return toboolean(value)
end

local function safeCall(obj, method)
  if not obj then
    return nil
  end

  local ok, value = pcall(function() return obj[method](obj) end)
  if ok then
    return value
  end

  return nil
end

local function hasStateBit(states, state)
  if not states or not state or state <= 0 then
    return false
  end

  if Bit and Bit.hasBit then
    return Bit.hasBit(states, state)
  end

  if bit32 and bit32.band then
    return bit32.band(states, state) ~= 0
  end

  if bit and bit.band then
    return bit.band(states, state) ~= 0
  end

  return false
end

local function getConditionsHUD()
  if m_settings and m_settings.ConditionsHUD then
    return m_settings.ConditionsHUD
  end

  return ConditionsHUD
end

local function shouldShowCondition(cond)
  if not cond then
    return false
  end

  local showInHud = getSettingOption('showInHudCheckBox', true)
  local showInBar = getSettingOption('showInBarCheckBox', true)

  if showInHud and cond.isVisibleHud and cond:isVisibleHud() then
    return true
  end

  return showInBar and cond.isVisibleBar and cond:isVisibleBar()
end

local function getActiveConditions()
  local conditionsHud = getConditionsHUD()
  if not conditionsHud or not conditionsHud.specialConditionsOrder then
    return {}
  end

  local result = {}
  local added = {}

  local function addCondition(cond)
    if not cond then
      return
    end

    local id = cond:getId()
    if Icons and PlayerStates and id == Icons[PlayerStates.Swords].id and conditionsHud.actives then
      local pz = conditionsHud:getSpecialConditionById(Icons[PlayerStates.Pz].id)
      local pzBlock = conditionsHud:getSpecialConditionById(Icons[PlayerStates.PzBlock].id)
      if (pz and conditionsHud.actives[pz:getId()]) or (pzBlock and conditionsHud.actives[pzBlock:getId()]) then
        return
      end
    end

    if not id or added[id] or not shouldShowCondition(cond) then
      return
    end

    added[id] = true
    table.insert(result, cond)
  end

  if conditionsHud.actives then
    for _, cond in ipairs(conditionsHud.specialConditionsOrder) do
      if conditionsHud.actives[cond:getId()] then
        addCondition(cond)
      end
    end
  end

  local localPlayer = g_game.getLocalPlayer()
  if localPlayer and Icons then
    local states = safeCall(localPlayer, 'getStates') or 0
    if states and states ~= 0 then
      for state, icon in pairs(Icons) do
        if type(state) == 'number' and hasStateBit(states, state) and icon then
          addCondition(conditionsHud:getSpecialConditionById(icon.id))
        end
      end
    end
  end

  local statesList = safeCall(localPlayer, 'getStatesList')
  if statesList and Icons then
    for _, state in pairs(statesList) do
      local icon = Icons[state]
      if icon then
        addCondition(conditionsHud:getSpecialConditionById(icon.id))
      end
    end
  end

  return result
end

function StatusIconBar.updatePosition()
  if not statusIconPanel or not healthCircle then return end
  local ph = statusIconPanel:getHeight()
  local pw = statusIconPanel:getWidth()
  local hx = healthCircle:getX()
  local hy = healthCircle:getY()
  local arcH = imageSizeBroad or 211
  statusIconPanel:setX(hx - pw - cfg.marginRight)
  statusIconPanel:setY(hy + math.floor((arcH - ph) / 2))
end

local function cancelIconEvents(container)
  if not container then
    return
  end

  if container.fadeInEvent then
    removeEvent(container.fadeInEvent)
    container.fadeInEvent = nil
  end

  if container.fadeOutEvent then
    removeEvent(container.fadeOutEvent)
    container.fadeOutEvent = nil
  end
end

local function setContainerOpacity(container, opacity)
  if not container then
    return
  end

  container:setOpacity(1)
  local background = container:getChildById('background')
  if background then
    if not container.baseBackgroundOpacity then
      container.baseBackgroundOpacity = background.getOpacity and background:getOpacity() or cfg.backgroundOpacity
    end
    background:setOpacity(container.baseBackgroundOpacity * opacity)
  end

  local icon = container:getChildById('icon')
  if icon then
    icon:setOpacity(opacity)
  end
end

function StatusIconBar.updateWidgetHeight()
  if not statusIconPanel then
    return
  end

  local height = cfg.topBotSize * 2 + 1
  for _, container in pairs(activeIcons) do
    if container and statusIconPanel:hasChild(container) then
      height = height + container:getHeight() + 1
    end
  end

  statusIconPanel:setHeight(height)
  StatusIconBar.updatePosition()
end

local function destroyIconContainer(container)
  if not container then
    return
  end

  cancelIconEvents(container)
  if container.conditionId then
    activeIcons[container.conditionId] = nil
  end

  if statusIconPanel and statusIconPanel:hasChild(container) then
    container:destroy()
  end

  StatusIconBar.updateWidgetHeight()
end

function StatusIconBar.fadeIn(container, time)
  if not container or not statusIconPanel or not statusIconPanel:hasChild(container) then
    return
  end

  cancelIconEvents(container)
  container.realHeight = container.realHeight or cfg.iconSize

  local progress = math.min(1, math.max(0, time / cfg.fadeTime))
  container:setHeight(math.max(1, math.floor(container.realHeight * progress)))
  setContainerOpacity(container, progress)

  if progress >= 1 then
    container:setHeight(container.realHeight)
    setContainerOpacity(container, 1)
    StatusIconBar.updateWidgetHeight()
    return
  end

  container.fadeInEvent = scheduleEvent(function()
    StatusIconBar.fadeIn(container, time + cfg.fadeInterval)
  end, cfg.fadeInterval)

  StatusIconBar.updateWidgetHeight()
end

function StatusIconBar.fadeOut(container, time)
  if not container or not statusIconPanel or not statusIconPanel:hasChild(container) then
    return
  end

  cancelIconEvents(container)
  container.realHeight = container.realHeight or cfg.iconSize

  local progress = math.min(1, math.max(0, time / cfg.fadeTime))
  if progress <= 0 then
    destroyIconContainer(container)
    return
  end

  container:setHeight(math.max(1, math.floor(container.realHeight * progress)))
  setContainerOpacity(container, progress)

  container.fadeOutEvent = scheduleEvent(function()
    StatusIconBar.fadeOut(container, time - cfg.fadeInterval)
  end, cfg.fadeInterval)

  StatusIconBar.updateWidgetHeight()
end

local function clearAllIcons()
  for _, container in pairs(activeIcons) do
    destroyIconContainer(container)
  end
  activeIcons = {}

  if statusIconPanel then
    statusIconPanel:setHeight(cfg.topBotSize * 2 + 1)
    statusIconPanel:setVisible(false)
  end
end

function StatusIconBar.refreshIcons()
  if not statusIconPanel then return end
  refreshPending = false

  if not g_game.isOnline() then
    clearAllIcons()
    return
  end

  local active = getActiveConditions()
  local activeById = {}

  for _, cond in ipairs(active) do
    local id = cond:getId()
    activeById[id] = cond

    local container = activeIcons[id]
    if not container then
      container = g_ui.createWidget('StatusIconContainer', statusIconPanel)
      container:setId('statusIcon_' .. id)
      container.conditionId = id
      container.realHeight = cfg.iconSize
      container:setHeight(1)
      setContainerOpacity(container, 0)
      activeIcons[id] = container
      StatusIconBar.fadeIn(container, 0)
    elseif container.fadeOutEvent then
      StatusIconBar.fadeIn(container, container:getHeight() / math.max(container.realHeight or cfg.iconSize, 1) * cfg.fadeTime)
    else
      container:setHeight(container.realHeight or cfg.iconSize)
      setContainerOpacity(container, 1)
    end

    local tooltip = cond:getTooltip() or ''
    if cond.getTooltipBar then
      local tooltipBar = cond:getTooltipBar()
      if tooltipBar and tooltipBar ~= '' then
        tooltip = tooltipBar
      end
    end
    container:setTooltip(tooltip)

    local icon = container:getChildById('icon')
    if icon then
      local iconPath = cond:getPath()
      if (not iconPath or iconPath == '') and cond.getIcon then
        iconPath = cond:getIcon()
      end
      if iconPath and iconPath ~= '' then
        icon:setImageSource(iconPath)
      end
    end
  end

  for id, container in pairs(activeIcons) do
    if not activeById[id] and not container.fadeOutEvent then
      StatusIconBar.fadeOut(container, cfg.fadeTime)
    end
  end

  for index, cond in ipairs(active) do
    local container = activeIcons[cond:getId()]
    if container then
      statusIconPanel:moveChildToIndex(container, index + 1)
    end
  end

  local bottom = statusIconPanel:getChildById('statusIconBottom')
  if bottom then
    statusIconPanel:moveChildToIndex(bottom, statusIconPanel:getChildCount())
  end

  if next(activeIcons) then
    statusIconPanel:setVisible(true)
    statusIconPanel:raise()
  else
    statusIconPanel:setVisible(false)
  end

  StatusIconBar.updateWidgetHeight()
end

function StatusIconBar.scheduleRefresh()
  if not refreshPending then
    refreshPending = true
    addEvent(StatusIconBar.refreshIcons)
  end
end

local function onGameStart()
  addEvent(StatusIconBar.refreshIcons)
  scheduleEvent(StatusIconBar.refreshIcons, 100)
  scheduleEvent(StatusIconBar.refreshIcons, 500)
  scheduleEvent(StatusIconBar.refreshIcons, 1000)
end

local function onGameEnd()
  clearAllIcons()
end

function StatusIconBar.init()
  g_ui.importStyle('statusiconbar')

  statusIconPanel = g_ui.createWidget('StatusIconPanel', mapPanel)
  local top = g_ui.createWidget('StatusIconTop', statusIconPanel)
  top:setId('statusIconTop')
  local bottom = g_ui.createWidget('StatusIconBottom', statusIconPanel)
  bottom:setId('statusIconBottom')
  statusIconPanel:setVisible(false)
  statusIconPanel:setHeight(cfg.topBotSize * 2 + 1)
  statusIconPanel:raise()

  connect(LocalPlayer, {
    onStatesChange = StatusIconBar.scheduleRefresh,
    onSkullChange = StatusIconBar.scheduleRefresh,
    onEmblemChange = StatusIconBar.scheduleRefresh,
    onRegenerationChange = StatusIconBar.scheduleRefresh,
    onTaintsChange = StatusIconBar.scheduleRefresh,
  })
  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd,
  })

  if g_game.isOnline() then
    addEvent(StatusIconBar.refreshIcons)
    scheduleEvent(StatusIconBar.refreshIcons, 500)
  end
end

function StatusIconBar.terminate()
  disconnect(LocalPlayer, {
    onStatesChange = StatusIconBar.scheduleRefresh,
    onSkullChange = StatusIconBar.scheduleRefresh,
    onEmblemChange = StatusIconBar.scheduleRefresh,
    onRegenerationChange = StatusIconBar.scheduleRefresh,
    onTaintsChange = StatusIconBar.scheduleRefresh,
  })
  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd,
  })

  if statusIconPanel then
    clearAllIcons()
    statusIconPanel:destroy()
    statusIconPanel = nil
  end
end
