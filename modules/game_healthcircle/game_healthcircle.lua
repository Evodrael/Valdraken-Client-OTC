mapPanel = nil

healthCircle = nil
local healthCircleFront
local manaCircle
local manaCircleFront
local manaShieldCircle = nil
local manaShieldCircleFront = nil

local monkCircleBackground
local monkHealthCircle
local monkSereneCircle
local monkHarmonySlots = {}

local enabled = false
local healthEnabled = true
local manaEnabled = true
local monkMode = false
local harmonyLeft = true
local shieldModeActive = false
local distanceFromCenter = 15
local opacityCircle = 0.7
local styleIndex = 1
local imageSizeThin = 58
imageSizeBroad = 211
local verticalCenterOffset = 32
local monkHarmony = 0
local monkSerene = false

local styles = {
  [0] = { name = 'small', width = 35, height = 126 },
  [1] = { name = 'default', width = 58, height = 211 },
  [2] = { name = 'large', width = 79, height = 292 }
}

local function clamp(value, minValue, maxValue)
  value = tonumber(value) or minValue
  if value < minValue then return minValue end
  if value > maxValue then return maxValue end
  return value
end

local function normalizeStyleIndex(value)
  return clamp(value, 0, 2)
end

local function readOption(name, fallback)
  if GameOptions and GameOptions.getOption then
    local ok, value = pcall(function() return GameOptions:getOption(name) end)
    if ok and value ~= nil then
      return value
    end
  end
  return fallback
end

local function arcPath(side, state)
  local style = styles[styleIndex] or styles[1]
  return string.format('/images/arcs/%s-%s_%s', style.name, side, state)
end

local function arcPathCustom(suffix)
  local style = styles[styleIndex] or styles[1]
  return string.format('/images/arcs/%s-%s', style.name, suffix)
end

local function monkPath(side, asset)
  local style = styles[styleIndex] or styles[1]
  return string.format('/images/arcs/monk/%s/%s/%s-%s-monk', style.name, side, style.name, asset)
end

local function setWidgetBaseSize(widget)
  if widget then
    widget:setWidth(imageSizeThin)
    widget:setHeight(imageSizeBroad)
  end
end

local function setOpacity(widget, value)
  if widget then
    widget:setOpacity(value)
  end
end

local function setWidgetsVisible(value)
  local monkAtHealth = monkMode and harmonyLeft
  local monkAtMana = monkMode and not harmonyLeft
  if healthCircle then healthCircle:setVisible(value and healthEnabled and not monkAtHealth) end
  if healthCircleFront then healthCircleFront:setVisible(value and healthEnabled and not monkAtHealth) end
  if manaCircle then manaCircle:setVisible(value and manaEnabled and not monkAtMana and not shieldModeActive) end
  if manaCircleFront then manaCircleFront:setVisible(value and manaEnabled and not monkAtMana) end
  if monkCircleBackground then monkCircleBackground:setVisible(value and healthEnabled and monkMode) end
  if monkHealthCircle then monkHealthCircle:setVisible(value and healthEnabled and monkMode) end
  if monkSereneCircle then monkSereneCircle:setVisible(value and healthEnabled and monkMode) end
  for i = 1, 5 do
    if monkHarmonySlots[i] then
      monkHarmonySlots[i]:setVisible(value and healthEnabled and monkMode)
    end
  end
end

local function refreshMonkVisuals()
  if monkSereneCircle then
    monkSereneCircle:setImageColor('#9933FF')
    monkSereneCircle:setOpacity(monkSerene and opacityCircle or 0)
  end

  for i = 1, 5 do
    local slot = monkHarmonySlots[i]
    if slot then
      if i <= monkHarmony then
        slot:setImageColor('#C9852A')
        slot:setOpacity(opacityCircle)
      else
        slot:setImageColor('#8C6A2E')
        slot:setOpacity(opacityCircle * 0.35)
      end
    end
  end
end

local function refreshMonkState()
  local player = g_game.getLocalPlayer()
  monkHarmony = player and clamp(player:getHarmony(), 0, 5) or 0
  monkSerene = player and player:isSerene() or false
  monkMode = player and (player:isMonk() or monkHarmony > 0 or monkSerene)
  refreshMonkVisuals()
  setWidgetsVisible(enabled and g_game.isOnline())
end

local setVerticalProgress

local function updateManaShieldDisplay()
  if not manaShieldCircle or not manaShieldCircleFront then return end

  local player = g_game.isOnline() and g_game.getLocalPlayer() or nil
  local shieldActive = player and enabled and
    (player:useMagicShield() or player:hasState(PlayerStates.NewMagicShield))

  if not shieldActive then
    if shieldModeActive then
      shieldModeActive = false
      if manaCircleFront then
        manaCircleFront:setImageSource(arcPath('right', 'full'))
      end
      local monkAtMana = monkMode and not harmonyLeft
      if manaCircle then manaCircle:setVisible(enabled and manaEnabled and not monkAtMana) end
      whenManaChange()
    end
    manaShieldCircle:setVisible(false)
    manaShieldCircleFront:setVisible(false)
    return
  end

  if not shieldModeActive then
    shieldModeActive = true
    if manaCircle then manaCircle:setVisible(false) end
    if manaCircleFront then
      manaCircleFront:setImageSource(arcPathCustom('maximal_white'))
    end
    manaShieldCircle:setVisible(true)
    manaShieldCircle:setWidth(imageSizeThin)
    manaShieldCircle:setHeight(imageSizeBroad)
    manaShieldCircle:setImageClip({ x = 0, y = 0, width = imageSizeThin, height = imageSizeBroad })
    whenManaChange()
  end

  local maxShield = player:getMaxManaShield()
  local currentShield = player:getManaShield()
  if maxShield <= 0 then maxShield = math.max(currentShield, 1) end
  local percent = clamp(currentShield / maxShield * 100, 0, 100)

  if percent <= 0 then
    manaShieldCircleFront:setVisible(false)
  else
    manaShieldCircleFront:setVisible(true)
    local emptyPixels = math.floor(imageSizeBroad * (1 - percent / 100))
    local filledPixels = imageSizeBroad - emptyPixels
    manaShieldCircleFront:setY(manaShieldCircle:getY() + emptyPixels)
    manaShieldCircleFront:setHeight(filledPixels)
    manaShieldCircleFront:setImageClip({ x = 0, y = emptyPixels, width = imageSizeThin, height = filledPixels })
  end
end

local function whenManaShieldChange()
  updateManaShieldDisplay()
end

local function onShieldStateChange(player, states, oldStates)
  local wasShield = player:hasState(PlayerStates.NewMagicShield, oldStates)
  local isShield = player:hasState(PlayerStates.NewMagicShield, states)
  if wasShield ~= isShield then
    updateManaShieldDisplay()
  end
end

local function applyArcStyle()
  styleIndex = clamp(styleIndex, 0, 2)
  local style = styles[styleIndex] or styles[1]
  imageSizeThin = style.width
  imageSizeBroad = style.height

  if healthCircle then healthCircle:setImageSource(arcPath('left', 'empty')) end
  if healthCircleFront then healthCircleFront:setImageSource(arcPath('left', 'full')) end
  if manaCircle then manaCircle:setImageSource(arcPath('right', 'empty')) end
  if manaCircleFront then manaCircleFront:setImageSource(arcPath('right', 'full')) end
  if manaShieldCircle then manaShieldCircle:setImageSource(arcPathCustom('bg-full')) end
  if manaShieldCircleFront then manaShieldCircleFront:setImageSource(arcPathCustom('minimal_white')) end

  local monkSide = harmonyLeft and 'left' or 'right'
  if monkCircleBackground then monkCircleBackground:setImageSource(monkPath(monkSide, 'bg-full')) end
  if monkHealthCircle then monkHealthCircle:setImageSource(monkPath(monkSide, 'maximal')) end
  if monkSereneCircle then monkSereneCircle:setImageSource(monkPath(monkSide, 'circle-purple')) end
  for i = 1, 5 do
    if monkHarmonySlots[i] then
      monkHarmonySlots[i]:setImageSource(monkPath(monkSide, 'slot-' .. i))
    end
  end

  setWidgetBaseSize(healthCircle)
  setWidgetBaseSize(healthCircleFront)
  setWidgetBaseSize(manaCircle)
  setWidgetBaseSize(manaCircleFront)
  setWidgetBaseSize(manaShieldCircle)
  setWidgetBaseSize(manaShieldCircleFront)
  setWidgetBaseSize(monkCircleBackground)
  setWidgetBaseSize(monkHealthCircle)
  setWidgetBaseSize(monkSereneCircle)
  for i = 1, 5 do
    setWidgetBaseSize(monkHarmonySlots[i])
  end
  refreshMonkVisuals()
  shieldModeActive = false
  updateManaShieldDisplay()
end

setVerticalProgress = function(emptyWidget, fullWidget, percent)
  if not emptyWidget or not fullWidget then
    return
  end

  percent = clamp(percent, 0, 100)
  local emptyPixels = math.floor(imageSizeBroad * (1 - percent / 100))
  local filledPixels = imageSizeBroad - emptyPixels

  emptyWidget:setHeight(emptyPixels)
  emptyWidget:setImageClip({ x = 0, y = 0, width = imageSizeThin, height = emptyPixels })

  fullWidget:setY(emptyWidget:getY() + emptyPixels)
  fullWidget:setHeight(filledPixels)
  fullWidget:setImageClip({ x = 0, y = emptyPixels, width = imageSizeThin, height = filledPixels })
end

local function setVerticalFill(fullWidget, percent)
  if not fullWidget then
    return
  end

  percent = clamp(percent, 0, 100)
  local emptyPixels = math.floor(imageSizeBroad * (1 - percent / 100))
  local filledPixels = imageSizeBroad - emptyPixels

  fullWidget:setY((monkCircleBackground and monkCircleBackground:getY() or fullWidget:getY()) + emptyPixels)
  fullWidget:setHeight(filledPixels)
  fullWidget:setImageClip({ x = 0, y = emptyPixels, width = imageSizeThin, height = filledPixels })
end

local function healthColor(percent)
  if percent > 92 then return '#00BC00' end
  if percent > 60 then return '#50A150' end
  if percent > 30 then return '#A1A100' end
  if percent > 8 then return '#BF0A0A' end
  return '#910F0F'
end

function whenHealthChange()
  if not g_game.isOnline() then
    return
  end

  local player = g_game.getLocalPlayer()
  if not player then
    return
  end

  local maxHealth = player:getMaxHealth()
  local percent = maxHealth > 0 and math.floor(player:getHealth() / maxHealth * 100) or 100

  if monkMode then
    if monkCircleBackground then
      monkCircleBackground:setHeight(imageSizeBroad)
      monkCircleBackground:setImageClip({ x = 0, y = 0, width = imageSizeThin, height = imageSizeBroad })
    end
    setVerticalFill(monkHealthCircle, percent)
    if monkHealthCircle then monkHealthCircle:setImageColor(healthColor(percent)) end
  end

  if not monkMode or not harmonyLeft then
    setVerticalProgress(healthCircle, healthCircleFront, percent)
    if healthCircleFront then healthCircleFront:setImageColor(healthColor(percent)) end
  end
end

function whenManaChange()
  if not g_game.isOnline() then
    return
  end

  local player = g_game.getLocalPlayer()
  if not player then
    return
  end

  local maxMana = player:getMaxMana()
  if maxMana <= 0 then
    if manaCircle then manaCircle:setVisible(false) end
    if manaCircleFront then manaCircleFront:setVisible(false) end
    return
  end

  setWidgetsVisible(enabled and g_game.isOnline())
  local percent = math.floor(player:getMana() / maxMana * 100)
  setVerticalProgress(manaCircle, manaCircleFront, percent)
end

function whenMonkHarmonyChange(localPlayer, harmony)
  monkHarmony = clamp(harmony, 0, 5)
  refreshMonkVisuals()
  setWidgetsVisible(enabled and g_game.isOnline())
end

function whenMonkSereneChange(localPlayer, serene)
  monkSerene = not not serene
  refreshMonkVisuals()
  setWidgetsVisible(enabled and g_game.isOnline())
end

function whenVocationChange()
  refreshMonkState()
  whenMapResizeChange()
end

function whenMapResizeChange()
  if not mapPanel then
    return
  end

  local barDistance = 90
  local dynamicDistance = math.floor(mapPanel:getHeight() / 2 * 0.2)
  if dynamicDistance >= 100 then
    barDistance = dynamicDistance
  end

  local centerX = math.floor(mapPanel:getWidth() / 2)
  local centerY = math.floor(mapPanel:getHeight() / 2 - imageSizeBroad / 2 + verticalCenterOffset)
  local leftX = math.floor(centerX - barDistance - imageSizeThin) - distanceFromCenter
  local rightX = math.floor(centerX + barDistance) + distanceFromCenter
  local healthX = leftX
  local manaX = rightX
  local monkX = harmonyLeft and healthX or manaX

  if g_client.setHudArcPosition then
    local mapRect = mapPanel:getRect()
    g_client.setHudArcPosition(mapRect.x + healthX, mapRect.y + centerY, imageSizeBroad)
  end
  if healthCircle then healthCircle:setPosition({ x = healthX, y = centerY }) end
  if healthCircleFront then healthCircleFront:setPosition({ x = healthX, y = centerY }) end
  if manaCircle then manaCircle:setPosition({ x = manaX, y = centerY }) end
  if manaCircleFront then manaCircleFront:setPosition({ x = manaX, y = centerY }) end
  if manaShieldCircle then manaShieldCircle:setPosition({ x = manaX, y = centerY }) end
  if manaShieldCircleFront then manaShieldCircleFront:setPosition({ x = manaX, y = centerY }) end
  if monkCircleBackground then monkCircleBackground:setPosition({ x = monkX, y = centerY }) end
  if monkHealthCircle then monkHealthCircle:setPosition({ x = monkX, y = centerY }) end
  if monkSereneCircle then monkSereneCircle:setPosition({ x = monkX, y = centerY }) end
  for i = 1, 5 do
    if monkHarmonySlots[i] then
      monkHarmonySlots[i]:setPosition({ x = monkX, y = centerY })
    end
  end

  refreshMonkState()
  whenHealthChange()
  whenManaChange()
  updateManaShieldDisplay()

  if StatusIconBar then
    StatusIconBar.updatePosition()
  end
end

function setEnabled(value)
  enabled = toboolean(value)
  setWidgetsVisible(enabled and g_game.isOnline())
  updateManaShieldDisplay()
  whenMapResizeChange()
end

function setHealthCircle(value)
  healthEnabled = toboolean(value)
  setWidgetsVisible(enabled and g_game.isOnline())
  whenMapResizeChange()
end

function setManaCircle(value)
  manaEnabled = toboolean(value)
  setWidgetsVisible(enabled and g_game.isOnline())
  whenMapResizeChange()
end

function setArcStyle(value)
  styleIndex = normalizeStyleIndex(value)
  applyArcStyle()
  whenMapResizeChange()
end

function setDistanceFromCenter(value)
  distanceFromCenter = clamp(value, 0, 100)
  whenMapResizeChange()
end

function setCircleOpacity(value)
  opacityCircle = clamp(value, 0, 1)
  setOpacity(healthCircle, opacityCircle)
  setOpacity(healthCircleFront, opacityCircle)
  setOpacity(manaCircle, opacityCircle)
  setOpacity(manaCircleFront, opacityCircle)
  setOpacity(manaShieldCircle, opacityCircle)
  setOpacity(manaShieldCircleFront, opacityCircle)
  setOpacity(monkCircleBackground, opacityCircle)
  setOpacity(monkHealthCircle, opacityCircle)
  setOpacity(monkSereneCircle, opacityCircle)
  for i = 1, 5 do
    setOpacity(monkHarmonySlots[i], opacityCircle)
  end
  refreshMonkVisuals()
end

function setHarmonyLeftDraw(value)
  harmonyLeft = toboolean(value)
  applyArcStyle()
  whenMapResizeChange()
end

local function onGameStart()
  refreshMonkState()
  setWidgetsVisible(enabled)
  whenMapResizeChange()
  updateManaShieldDisplay()
end

local function onGameEnd()
  if shieldModeActive then
    shieldModeActive = false
    if manaCircleFront then
      manaCircleFront:setImageSource(arcPath('right', 'full'))
    end
  end
  setWidgetsVisible(false)
end

function init()
  g_ui.importStyle('game_healthcircle.otui')
  mapPanel = modules.game_interface.getMapPanel()

  healthCircle = g_ui.createWidget('HealthCircle', mapPanel)
  manaCircle = g_ui.createWidget('ManaCircle', mapPanel)
  healthCircleFront = g_ui.createWidget('HealthCircleFront', mapPanel)
  manaCircleFront = g_ui.createWidget('ManaCircleFront', mapPanel)
  manaShieldCircle = g_ui.createWidget('ManaShieldCircle', mapPanel)
  manaShieldCircleFront = g_ui.createWidget('ManaShieldCircleFront', mapPanel)
  manaShieldCircle:setVisible(false)
  manaShieldCircleFront:setVisible(false)
  monkCircleBackground = g_ui.createWidget('MonkCircleBackground', mapPanel)
  monkHealthCircle = g_ui.createWidget('MonkHealthCircle', mapPanel)
  monkSereneCircle = g_ui.createWidget('MonkSereneCircle', mapPanel)
  for i = 1, 5 do
    monkHarmonySlots[i] = g_ui.createWidget('MonkHarmonySlot', mapPanel)
  end

  enabled = toboolean(readOption('showHealthManaCircle', false))
  styleIndex = normalizeStyleIndex((tonumber(readOption('sizeBox', 2)) or 2) - 1)
  distanceFromCenter = clamp(readOption('distanceArc', 15), 0, 100)
  opacityCircle = clamp((tonumber(readOption('opacityArc', 70)) or 70) / 100, 0, 1)
  harmonyLeft = toboolean(readOption('harmonyArcSide', true))

  applyArcStyle()
  setCircleOpacity(opacityCircle)
  setWidgetsVisible(false)

  connect(LocalPlayer, {
    onHealthChange = whenHealthChange,
    onManaChange = whenManaChange,
    onManaShieldChange = whenManaShieldChange,
    onStatesChange = onShieldStateChange,
    onHarmonyChange = whenMonkHarmonyChange,
    onSereneChange = whenMonkSereneChange,
    onSerenityChange = whenMonkSereneChange,
    onVocationChange = whenVocationChange
  })
  connect(mapPanel, { onGeometryChange = whenMapResizeChange })
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })

  if StatusIconBar then
    StatusIconBar.init()
  end

  if g_game.isOnline() then
    onGameStart()
  end
end

function terminate()
  if StatusIconBar then
    StatusIconBar.terminate()
  end

  disconnect(LocalPlayer, {
    onHealthChange = whenHealthChange,
    onManaChange = whenManaChange,
    onManaShieldChange = whenManaShieldChange,
    onStatesChange = onShieldStateChange,
    onHarmonyChange = whenMonkHarmonyChange,
    onSereneChange = whenMonkSereneChange,
    onSerenityChange = whenMonkSereneChange,
    onVocationChange = whenVocationChange
  })
  if mapPanel then
    disconnect(mapPanel, { onGeometryChange = whenMapResizeChange })
  end
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })

  local widgets = {
    healthCircle,
    manaCircle,
    healthCircleFront,
    manaCircleFront,
    manaShieldCircle,
    manaShieldCircleFront,
    monkCircleBackground,
    monkHealthCircle,
    monkSereneCircle
  }
  for i = 1, 5 do
    table.insert(widgets, monkHarmonySlots[i])
  end
  for _, widget in ipairs(widgets) do
    if widget then
      widget:destroy()
    end
  end
end
