-- =============================================================================
-- game_hints (OTZudo) — agora funciona como o antigo game_tutorial.
-- Telas informativas (controls / tutorial 3 paginas / voc_change / arrival) +
-- o SELETOR INTERATIVO de vocacao (portado do game_tutorial), tudo disparado
-- pelo MESMO sinal do servidor: g_game.onTutorialHint(id) (opcode 0xDC).
--
-- Mapa de ids (igual ao game_tutorial do OTZudo; o servidor envia via
-- player:sendTutorial(id)):
--   1 = Alternative Controls   -> janela 'controls'
--   2 = Vocation select        -> SELETOR interativo (escolhe voc -> sendChangeVocation)
--   3 = Vocation/hunting hint   -> 'voc_change' com a imagem da vocacao do jogador
--   4 = Arrival in Thais        -> 'arrival' com a imagem da vocacao do jogador
-- =============================================================================

hintWindow = nil
local maxPages = 3
local currentPage = 1
local openedHints = {}

-- ---------------------------------------------------------------------------
-- Telas informativas (OTZudo original)
-- ---------------------------------------------------------------------------
function showHint(hintType)
  local hintPath = 'styles/' .. hintType

  if openedHints[hintType] then
    return openedHints[hintType]
  end

  if hintType == 'tutorialhint' then
    currentPage = 1
  end

  local win = g_ui.loadUI(hintPath, g_ui.getRootWidget())
  win:show(true)
  win:raise()
  win:focus()
  openedHints[hintType] = win
  return win
end

function destroyHint(hintType)
  local win = openedHints[hintType]
  if win then
    win:destroy()
    openedHints[hintType] = nil
  end
end

function tutorialHint(action)
  showHint('tutorialhint')
  local win = openedHints['tutorialhint']
  if not win then return end
  if action == 'next' then
    if currentPage < maxPages then currentPage = currentPage + 1 end
  elseif action == 'back' then
    if currentPage > 1 then currentPage = currentPage - 1 end
  end

  win.contentPanel:getChildById('firstScreen'):setVisible(currentPage == 1)
  win.contentPanel:getChildById('secondScreen'):setVisible(currentPage == 2)
  win.contentPanel:getChildById('thirdScreen'):setVisible(currentPage == 3)

  if currentPage == 3 then
    win.contentPanel:getChildById('ok'):setVisible(true)
    win.contentPanel:getChildById('next'):setVisible(false)
  else
    win.contentPanel:getChildById('ok'):setVisible(false)
    win.contentPanel:getChildById('next'):setVisible(true)
  end

  win.contentPanel:getChildById('back'):setEnabled(currentPage > 1)
end

-- imagem por vocacao (1=knight,2=paladin,3=sorcerer,4=druid,5=monk; 11-15 = promovidas)
local vocChangeImages = {
  [1] = '/images/game/tutorial/hint_03_vocationknight',
  [2] = '/images/game/tutorial/hint_04_vocationpaladin',
  [3] = '/images/game/tutorial/hint_05_vocationsorcerer',
  [4] = '/images/game/tutorial/hint_06_vocationdruid',
  [5] = '/images/game/tutorial/hint_11_vocationmonk',
}
local arrivalVocImages = {
  [1] = '/images/game/tutorial/hint_07_arrivalmainknight',
  [2] = '/images/game/tutorial/hint_08_arrivalmainpaladin',
  [3] = '/images/game/tutorial/hint_09_arrivalmainsorcerer',
  [4] = '/images/game/tutorial/hint_10_arrivalmaindruid',
}

local function baseVocation(vocationId)
  if vocationId and vocationId > 10 then return vocationId - 10 end
  return vocationId
end

function vocationHint(vocationId)
  local win = showHint('voc_change')
  if not win then return end
  local imageSource = vocChangeImages[baseVocation(vocationId)]
  if imageSource then
    win.contentPanel:getChildById('vocation'):setImageSource(imageSource)
  end
end

function arrivalHint(vocationId)
  local win = showHint('arrival')
  if not win then return end
  local imageSource = arrivalVocImages[baseVocation(vocationId)] or '/images/game/tutorial/hint_07_arrivalmain'
  win.contentPanel:getChildById('arrivalMain'):setImageSource(imageSource)
end

-- ---------------------------------------------------------------------------
-- SELETOR DE VOCACAO (portado do game_tutorial)
-- ---------------------------------------------------------------------------
local vocationWindow = nil
local INFO_HEIGHT  = 227
local ANIM_DURATION = 600
local selectedVocation = nil
local animTokens = {}

local vocations = {
  { id = "knight",   vocationId = 1, name = "Knight",   spells = { 21, 19 }, gear = {34155, 3344, 39157, 3419, 28715, 44621} },
  { id = "sorcerer", vocationId = 3, name = "Sorcerer", spells = {157, 102}, gear = {3071, 39162, 20090, 31582, 8039, 3155} },
  { id = "druid",    vocationId = 4, name = "Druid",    spells = {49, 46},   gear = {8084, 34091, 39154, 36671, 31578, 3165} },
  { id = "paladin",  vocationId = 2, name = "Paladin",  spells = {155, 39},  gear = {47371, 8023, 36666, 39149, 32628, 35901} },
  { id = "monk",     vocationId = 5, name = "Monk",     spells = {177, 169}, gear = {50161, 50170, 50239, 50274, 50260, 50184} },
}

local function animateInfo(info, toMargin)
  local id = info:getId()
  local token = {}
  animTokens[id] = token
  local fromMargin = info:getMarginTop()
  if fromMargin == toMargin then return end
  local startTime = g_clock.millis()
  local function step()
    if animTokens[id] ~= token then return end
    local elapsed = g_clock.millis() - startTime
    local t = math.min(elapsed / ANIM_DURATION, 1)
    local e = 1 - math.pow(1 - t, 3)
    info:setMarginTop(math.floor(fromMargin + (toMargin - fromMargin) * e))
    if t < 1 then scheduleEvent(step, 16) end
  end
  step()
end

local function positionAbovePanelBottom(widget, panel, marginBottom)
  local pos  = panel:getPosition()
  local size = panel:getSize()
  local wSize = widget:getSize()
  widget:setPosition({
    x = pos.x + math.floor((size.width - wSize.width) / 2),
    y = pos.y + size.height - wSize.height - marginBottom
  })
end

local function hideAllConfirm()
  if not vocationWindow then return end
  for _, v in ipairs(vocations) do
    local cp = vocationWindow:recursiveGetChildById(v.id .. "ConfirmPanel")
    if cp then cp:hide() end
  end
end

local function showAllStartButtons()
  if not vocationWindow then return end
  for _, v in ipairs(vocations) do
    local sb  = vocationWindow:recursiveGetChildById(v.id .. "StartButton")
    local sel = vocationWindow:recursiveGetChildById(v.id .. "SelectBtn")
    if sb then
      sb:show()
      sb:setImageSource("/images/game/tutorial/button_startplaying_idle")
    end
    if sel then sel:setChecked(false) end
  end
end

local function setVocationActionBar(v)
  if not Options or not Options.changeHotkeyProfile then return end
  Options.changeHotkeyProfile(v.name)
  local actionbar = modules.game_actionbar
  if not actionbar then return end
  scheduleEvent(function()
    if actionbar.resetActionBar then actionbar.resetActionBar() end
  end, 500)
end

local function setupVocation(v)
  local panel        = vocationWindow:recursiveGetChildById(v.id .. "Panel")
  local info         = vocationWindow:recursiveGetChildById(v.id .. "Info")
  local startButton  = vocationWindow:recursiveGetChildById(v.id .. "StartButton")
  local selectBtn    = vocationWindow:recursiveGetChildById(v.id .. "SelectBtn")
  local confirmPanel = vocationWindow:recursiveGetChildById(v.id .. "ConfirmPanel")
  local confirmBtn   = vocationWindow:recursiveGetChildById(v.id .. "ConfirmBtn")
  local highlight    = vocationWindow:recursiveGetChildById(v.id .. "Highlight")

  if not panel or not info or not startButton or not selectBtn or not confirmPanel or not confirmBtn then
    g_logger.error("[game_hints] widget faltando para " .. v.id)
    return
  end

  local debounceToken = nil
  local function isAreaHovered()
    return panel:isHovered() or panel:isChildHovered()
      or startButton:isHovered() or startButton:isChildHovered()
      or confirmPanel:isHovered() or confirmPanel:isChildHovered()
  end
  local function scheduleCheck()
    local token = {}
    debounceToken = token
    scheduleEvent(function()
      if debounceToken ~= token then return end
      if isAreaHovered() then
        animateInfo(info, 0)
        if highlight then highlight:show() end
      else
        animateInfo(info, INFO_HEIGHT)
        if highlight then highlight:hide() end
      end
    end, 30)
  end

  panel.onHoverChange        = function() scheduleCheck() end
  startButton.onHoverChange  = function() scheduleCheck() end
  selectBtn.onHoverChange    = function() scheduleCheck() end
  confirmPanel.onHoverChange = function() scheduleCheck() end
  confirmBtn.onHoverChange   = function() scheduleCheck() end

  selectBtn.onClick = function()
    if selectedVocation and selectedVocation.id ~= v.id then
      local osb  = vocationWindow:recursiveGetChildById(selectedVocation.id .. "StartButton")
      local osel = vocationWindow:recursiveGetChildById(selectedVocation.id .. "SelectBtn")
      if osb  then osb:setImageSource("/images/game/tutorial/button_startplaying_idle") end
      if osel then osel:setChecked(false) end
    end
    selectedVocation = v
    startButton:setImageSource("")
    selectBtn:setChecked(true)
    hideAllConfirm()
    positionAbovePanelBottom(confirmPanel, panel, 8)
    confirmPanel:show()
    confirmPanel:raise()
  end

  confirmBtn.onClick = function()
    if selectedVocation then
      g_game.sendChangeVocation(selectedVocation.vocationId)
      setVocationActionBar(selectedVocation)
      scheduleEvent(function()
        local hc = modules.game_healthcircle
        if hc and hc.checkVocation then hc.checkVocation() end
      end, 500)
    end
    hideVocationSelect()
  end
end

local function setupSpellIcons()
  local profile = SpelllistSettings and SpelllistSettings['Default']
  if not profile then return end
  local iconSource = profile.iconFile or profile.iconsFolder
  if not iconSource then return end
  for _, v in ipairs(vocations) do
    for i, clientId in ipairs(v.spells) do
      local icon = vocationWindow:recursiveGetChildById(v.id .. "Slot" .. i .. "Icon")
      if icon then
        icon:setImageSource(iconSource)
        icon:setImageClip(Spells.getImageClipNormal(clientId, 'Default'))
      end
    end
  end
end

local function setupGearItems()
  for _, v in ipairs(vocations) do
    for i, itemId in ipairs(v.gear) do
      local slot = vocationWindow:recursiveGetChildById(v.id .. "Gear" .. i)
      if slot then slot:setItemId(itemId) end
    end
  end
end

function showVocationSelect()
  if not vocationWindow then return end
  showAllStartButtons()
  hideAllConfirm()
  selectedVocation = nil
  vocationWindow:show()
  vocationWindow:raise()
  vocationWindow:focus()
end

function hideVocationSelect()
  if vocationWindow then vocationWindow:hide() end
end

-- ---------------------------------------------------------------------------
-- Sinal do servidor + ciclo de vida do modulo
-- ---------------------------------------------------------------------------
function onTutorialHint(id)
  if id == 1 then
    showHint('controls')
  elseif id == 2 then
    showVocationSelect()
  elseif id == 3 then
    local player = g_game.getLocalPlayer()
    vocationHint(player and player:getVocation() or 1)
  elseif id == 4 then
    local player = g_game.getLocalPlayer()
    arrivalHint(player and player:getVocation() or 1)
  end
end

local function closeAll()
  hideVocationSelect()
  for hintType, _ in pairs(openedHints) do
    destroyHint(hintType)
  end
end

function init()
  vocationWindow = g_ui.loadUI('styles/vocation_select', g_ui.getRootWidget())
  if vocationWindow then
    vocationWindow:hide()
    for _, v in ipairs(vocations) do setupVocation(v) end
    setupSpellIcons()
    setupGearItems()
  else
    g_logger.error("[game_hints] falha ao carregar styles/vocation_select")
  end

  connect(g_game, { onGameEnd = closeAll })
  g_game.onTutorialHint = onTutorialHint
end

function terminate()
  disconnect(g_game, { onGameEnd = closeAll })
  if g_game.onTutorialHint == onTutorialHint then
    g_game.onTutorialHint = nil
  end
  closeAll()
  if vocationWindow then
    vocationWindow:destroy()
    vocationWindow = nil
  end
end
