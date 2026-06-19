buttonsWindow = nil
battleButton = nil
skillsbutton = nil
vipButton = nil
rewardWall = nil
highscore = nil
isHiddenMenuActive = false
currentOpenWidget = nil

local bPassSlot = nil

-- Hotfix when a new button is introduced
-- VOIP DESATIVADO: "button_voip" removido daqui p/ nao forcar a criacao do side button de voip.
-- Reverter: re-adicionar "button_voip" na lista abaixo.
local forceButtons = { "weaponProficiency", "button_taskhunting" }

local legacyButtonIds = {
  analytics = "analyticsSelectorWidget",
  battleButton = "battleListWidget",
  bestiary = "bestiaryTrackerWidget",
  bossSlots = "bossslotsDialog",
  bosstiaryTracker = "bosstiaryTrackerWidget",
  compendium = "compendiumDialog",
  cyclopedia = "cyclopediaDialog",
  exaltationForge = "exaltationForgeDialog",
  highscore = "highscoresDialog",
  imbueTracker = "imbuementTrackerWidget",
  partyList = "partyWidget",
  preyWindow = "preyWidget",
  questLog = "questDialog",
  questTracker = "questTrackerWidget",
  rewardWall = "rewardWallDialog",
  skillsButton = "skillsWidget",
  spellList = "spellListWidget",
  unjustPoints = "unjustifiedPoinsWidget",
  vipButton = "vipWidget",
  wheel = "skillWheelDialog"
}

local toggleButtons = {
  "skillsWidget", "battleListWidget", "vipWidget", "questTrackerWidget", "unjustifiedPoinsWidget", "imbuementTrackerWidget",
  "partyWidget", "bosstiaryTrackerWidget", "bestiaryTrackerWidget", "preyWidget", "analyticsSelectorWidget", "spellListWidget", "playerGuide", "lenshelpFunction",
  "button_taskhunting"
}

local horizontalSpriteButtons = {
  -- button_taskhunting uses the standard vertical 20x40 sprite (idle on top,
  -- pressed below). Flagging it as horizontal told getSideButtonOnClip to
  -- clip at x=20 which falls outside the image → blank button when pressed.
}

local staticButtonIds = {
  button_minibot = true
}

local function getSideButtonOnClip(buttonId)
  return horizontalSpriteButtons[buttonId] and "20 0 20 20" or "0 20 20 20"
end

local function useHorizontalSideButtonSprite(button)
  if button and button.mergeStyle then
    button:mergeStyle({
      ['$pressed'] = {
        ['image-clip'] = '20 0 20 20'
      },
      ['$checked'] = {
        ['image-clip'] = '20 0 20 20'
      }
    })
  end
end

function getControlButtonTooltip(button)
  local buttonTooltip = ControlButtonTooltips[button]
  if not buttonTooltip then
    return ("%s Unkown")
  end
  return buttonTooltip
end

local function normalizeButtonList(buttons)
  local normalized = {}
  local seen = {}

  for _, buttonId in pairs(buttons or {}) do
    local normalizedId = legacyButtonIds[buttonId] or buttonId
    if ControlButtonNames[normalizedId] and not seen[normalizedId] then
      table.insert(normalized, normalizedId)
      seen[normalizedId] = true
    end
  end

  return normalized
end

local function ensureKnownButton(activeWidgets, inactiveWidgets, buttonId)
  if table.find(activeWidgets, buttonId) or table.find(inactiveWidgets, buttonId) then
    return
  end
  table.insert(activeWidgets, buttonId)
end

local function forceActiveButton(activeWidgets, inactiveWidgets, buttonId)
  local inactiveIndex = table.find(inactiveWidgets, buttonId)
  if inactiveIndex then
    table.remove(inactiveWidgets, inactiveIndex)
  end

  if not table.find(activeWidgets, buttonId) then
    table.insert(activeWidgets, buttonId)
  end
end

local function getMainButtonsHeight(buttonPanel)
  local totalLines = math.max(2, math.ceil(buttonPanel:getChildCount() / 5))
  return 77 + ((totalLines - 1) * 22)
end

local function getStaticButtonById(buttonId)
  if buttonId == "button_minibot" and modules.game_inventory and modules.game_inventory.getAssistantButton then
    return modules.game_inventory.getAssistantButton()
  end

  if buttonsWindow then
    return buttonsWindow:recursiveGetChildById(buttonId)
  end

  return nil
end

local function removeButtonFromList(buttons, buttonId)
  local index = table.find(buttons, buttonId)
  while index do
    table.remove(buttons, index)
    index = table.find(buttons, buttonId)
  end
end

local function configureStaticButtons()
  local minibotButton = getStaticButtonById("button_minibot")
  if minibotButton and minibotButton.button then
    minibotButton.button.onClick = function() handleButtonClick(minibotButton.button) end
    minibotButton.button:setTooltip(tr(getControlButtonTooltip("button_minibot"), "Open"))
  end
end

local function removeInactiveDuplicates(activeWidgets, inactiveWidgets)
  local active = {}
  local filteredInactive = {}

  for _, buttonId in pairs(activeWidgets) do
    active[buttonId] = true
  end

  for _, buttonId in pairs(inactiveWidgets) do
    if not active[buttonId] then
      table.insert(filteredInactive, buttonId)
    end
  end

  return filteredInactive
end

local function getControlButtonOptions()
  local controlButtonsOptions = Options.array["controlButtonsOptions"]
  if type(controlButtonsOptions) ~= "table" or type(controlButtonsOptions.enabledButtons) ~= "table" or type(controlButtonsOptions.disabledButtons) ~= "table" then
    Options.array["controlButtonsOptions"] = Options.getDefaultSideButtons() or {
      enabledButtons = {},
      disabledButtons = {}
    }
  end

  local activeWidgets = normalizeButtonList(Options.getActiveWidgets())
  local inactiveWidgets = normalizeButtonList(Options.getInactiveWidgets())
  inactiveWidgets = removeInactiveDuplicates(activeWidgets, inactiveWidgets)

  ensureKnownButton(activeWidgets, inactiveWidgets, "compendiumDialog")
  ensureKnownButton(activeWidgets, inactiveWidgets, "playerGuide")

  for _, buttonId in pairs(forceButtons) do
    forceActiveButton(activeWidgets, inactiveWidgets, buttonId)
  end

  removeButtonFromList(activeWidgets, "button_minibot")
  removeButtonFromList(inactiveWidgets, "button_minibot")

  -- VOIP DESATIVADO: garante que o side button de voip nunca seja recriado, mesmo
  -- que esteja salvo nas opcoes do jogador (enabled/disabledButtons). Reverter:
  -- remover estas duas linhas.
  removeButtonFromList(activeWidgets, "button_voip")
  removeButtonFromList(inactiveWidgets, "button_voip")

  Options.updateControlButtons("enabledButtons", activeWidgets)
  Options.updateControlButtons("disabledButtons", inactiveWidgets)

  return activeWidgets, inactiveWidgets
end

function init()
  buttonsWindow = g_ui.loadUI('sidebuttons', m_interface.getRightPanel())
  local activeWidgets, inactiveWidgets = getControlButtonOptions()
  local buttonPanel = buttonsWindow:recursiveGetChildById("buttons")
  local battlePassBorder = buttonsWindow:recursiveGetChildById("border")
  local storeBorder = buttonsWindow:recursiveGetChildById("storeBorder")

  bPassSlot = buttonsWindow:recursiveGetChildById("bPassSlot")
  bPassSlot.onClick = function()
    local player = g_game.getLocalPlayer()
    if not player then return end
    -- True "independent" Battle Pass Inbox requires the server to ship item
    -- id 23397 (defined in items.xml) inside appearances.dat so the client
    -- can render it. Until that asset is delivered, registering it XML-only
    -- on the server crashes the login flow (the client disconnects when an
    -- inventory slot references an unknown item id). Fall back to the
    -- Purse / Store Inbox so the button still opens a usable container.
    local bpItem = player:getInventoryItem(InventorySlotBattlePass)
    if not bpItem then
      bpItem = player:getInventoryItem(InventorySlotPurse)
    end
    if bpItem then
      g_game.use(bpItem)
    else
      g_logger.warning("[BattlePassInbox] no item found in BattlePass(12) or Purse(11) slots")
    end
  end

  battlePassBorder:setImageShader("text_staff")
  storeBorder:setImageShader("text_staff")

  for k, v in pairs(forceButtons) do
    if not table.find(activeWidgets, v) and not table.find(inactiveWidgets, v) then
      table.insert(activeWidgets, v)
    end
  end

  configureStaticButtons()

  for _, v in pairs(activeWidgets) do
    if not staticButtonIds[v] then
      local widget = g_ui.createWidget("UISideButton", buttonPanel)
      widget.button:setImageSource(tr("/images/topbuttons/%s.png", v))
      if horizontalSpriteButtons[v] then
        useHorizontalSideButtonSprite(widget.button)
      end
      widget:setId(v)
      widget.button.onClick = function() handleButtonClick(widget.button) end
      widget.button:setTooltip(tr(getControlButtonTooltip(v), "Open"))
    end
  end

  buttonsWindow:setHeight(getMainButtonsHeight(buttonPanel))

  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
    onBestiaryHighlight = onBestiaryHighlight,
    onBosstiaryHighlight = onBosstiaryHighlight,
    onResourceBalance = onResourceBalance,
    onOpenRewardWall = onOpenRewardWall,
    onGameNews = onGameNews,
    onProficiencyHighlight = onProficiencyHighlight
  })
end

function setButtonVisible(buttonId, state)
  local buttonPanel = buttonsWindow:recursiveGetChildById("buttons")
  local button = staticButtonIds[buttonId] and getStaticButtonById(buttonId) or buttonPanel:recursiveGetChildById(buttonId)
  if button then
    if buttonId == "button_minibot" then
      button.button:setChecked(false)
      return
    end
    -- Mirror handleButtonClick's manual image-clip swap. Without it the
    -- $checked OTML rule sets the "on" sprite when checked, but when
    -- unchecked there's no $!checked rule to revert it, so the button stays
    -- visually pressed even after setChecked(false).
    if state then
      button.button:setImageClip(torect(getSideButtonOnClip(buttonId)))
      button.button:setTooltip(tr(getControlButtonTooltip(buttonId), "Close"))
    else
      button.button:setImageClip(torect("0 0 20 20"))
      button.button:setTooltip(tr(getControlButtonTooltip(buttonId), "Open"))
    end
    button.button:setChecked(state)
  end
end

function isButtonVisible(buttonId)
  local buttonPanel = buttonsWindow:recursiveGetChildById("buttons")
  local button = staticButtonIds[buttonId] and getStaticButtonById(buttonId) or buttonPanel:recursiveGetChildById(buttonId)
  if not button then
    return false
  end

  return button.button:isChecked()
end

function getButtonById(buttonId)
  local buttonPanel = buttonsWindow:recursiveGetChildById("buttons")
  local button = staticButtonIds[buttonId] and getStaticButtonById(buttonId) or buttonPanel:recursiveGetChildById(buttonId)
  if not button then
    return nil
  end
  return button
end

-- Afunda (on=true) ou solta (on=false) um side button por id, seguindo o ESTADO
-- REAL da janela do modulo (chamado pelo show/hide do modulo). Espelha o visual
-- que handleButtonClick aplica, para a janela fechada pela propria janela tambem
-- voltar o botao ao normal (antes so o clique no botao alternava o estado).
function setButtonChecked(buttonId, on)
  if not buttonsWindow then return end
  local container = getButtonById(buttonId)
  if not container then return end
  local button = (container.getChildById and container:getChildById('button')) or container
  if not button or not button.setChecked then return end
  button:setChecked(on and true or false)
  if button.setImageClip then
    button:setImageClip(torect(on and getSideButtonOnClip(buttonId) or "0 0 20 20"))
  end
end

function setCompendiumHighlight(highlighted)
  if not buttonsWindow then
    return
  end

  local compendiumButton = getButtonById("compendiumDialog")
  if not compendiumButton then
    return
  end

  compendiumButton.highlight:setVisible(highlighted)
  compendiumButton.brightButton:setVisible(highlighted)
end

local function refreshCompendiumHighlight()
  if modules.game_compendium and modules.game_compendium.hasUnseenContent then
    setCompendiumHighlight(modules.game_compendium.hasUnseenContent())
  end
end

function updateSideButtons()
  local activeWidgets, inactiveWidgets = getControlButtonOptions()
  local buttonPanel = buttonsWindow:recursiveGetChildById("buttons")

  for k, v in pairs(forceButtons) do
    if not table.find(activeWidgets, v) and not table.find(inactiveWidgets, v) then
      table.insert(activeWidgets, v)
    end
  end

  buttonPanel:destroyChildren()
  for _, v in pairs(activeWidgets) do
    if not staticButtonIds[v] then
      local widget = g_ui.createWidget("UISideButton", buttonPanel)
      widget.button:setImageSource(tr("/images/topbuttons/%s.png", v))
      if horizontalSpriteButtons[v] then
        useHorizontalSideButtonSprite(widget.button)
      end
      widget:setId(v)
      widget.button.onClick = function() handleButtonClick(widget.button) end
      widget.button:setTooltip(tr(getControlButtonTooltip(v), "Open"))
    end
  end

  configureStaticButtons()
  buttonsWindow:setHeight(getMainButtonsHeight(buttonPanel))
  refreshCompendiumHighlight()
end

function terminate()
  buttonsWindow:destroy()
  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
    onBestiaryHighlight = onBestiaryHighlight,
    onBosstiaryHighlight = onBosstiaryHighlight,
    onResourceBalance = onResourceBalance,
    onOpenRewardWall = onOpenRewardWall,
    onGameNews = onGameNews,
    onProficiencyHighlight = onProficiencyHighlight
  })
end

function offline()
  currentOpenWidget = nil
end

function online()
  local benchmark = g_clock.millis()
  m_interface.addToPanels(buttonsWindow)
  configureStaticButtons()
  clearHighlight()
  refreshCompendiumHighlight()
  consoleln("Side Buttons loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function clearHighlight()
  local buttons = {"compendiumDialog", "cyclopediaDialog", "bosstiaryDialog", "skillWheelDialog", "exaltationForgeDialog"}
  for _, str in pairs(buttons) do
    local buttonWidget = getButtonById(str)
    if buttonWidget then
      buttonWidget.button:setActionId(0)
      buttonWidget.highlight:setVisible(false)
      buttonWidget.brightButton:setVisible(false)
    end
  end
end

function onBestiaryHighlight(raceId)
  local cyclopediaButton = getButtonById("cyclopediaDialog")
  if cyclopediaButton then
    cyclopediaButton.button:setActionId(raceId)
    cyclopediaButton.highlight:setVisible(true)
    cyclopediaButton.brightButton:setVisible(true)
  end
end

function onBosstiaryHighlight(raceId)
  local bosstiaryButton = getButtonById("bosstiaryDialog")
  if bosstiaryButton then
    bosstiaryButton.button:setActionId(raceId)
    bosstiaryButton.highlight:setVisible(true)
    bosstiaryButton.brightButton:setVisible(true)
  end
end

function onProficiencyHighlight(hasUnusedPerk)
  local proficiencyButton = getButtonById("weaponProficiency")
  if proficiencyButton then
    proficiencyButton.highlight:setVisible(hasUnusedPerk)
    proficiencyButton.brightButton:setVisible(hasUnusedPerk)
  end
end

-- game_taskhunting calls this whenever its cached task lists transition from
-- empty to "player has at least one active task" (and the other way around).
-- The Task Board side button gets the same bestiary-style highlight ring so
-- the player notices unredeemed progress without opening the panel.
function setTaskBoardHighlight(active)
  local taskButton = getButtonById("button_taskhunting")
  if taskButton then
    taskButton.highlight:setVisible(active and true or false)
    taskButton.brightButton:setVisible(active and true or false)
  end
end

function onOpenRewardWall(fromShrine, nextRewardTime, currentIndex, message, dailyState, jokerToken, serverSave, dayStreakLevell)
  local rewardButton = getButtonById("rewardWallDialog")
  if rewardButton then
    rewardButton.highlight:setVisible(dailyState ~= 0)
    rewardButton.brightButton:setVisible(dailyState ~= 0)
  end
end

function onResourceBalance(resourceType, amount)
  -- wheel
  if resourceType == ResourceWheelPoints then
    local wheelButton = getButtonById("skillWheelDialog")
    if wheelButton then
      wheelButton.highlight:setVisible(amount > 0)
      wheelButton.brightButton:setVisible(amount > 0)
    end
  end

  -- forge
  if resourceType == ResourceForgeDust then
    local forgeButton = getButtonById("exaltationForgeDialog")
    if forgeButton then
      forgeButton.highlight:setVisible(amount == modules.game_forge.ForgeSystem.maxPlayerDust)
      forgeButton.brightButton:setVisible(amount == modules.game_forge.ForgeSystem.maxPlayerDust)
    end
  end

end

function onGameNews(_, action)
  local highlighted = action == 1
  if modules.game_compendium and modules.game_compendium.hasUnseenContent then
    highlighted = modules.game_compendium.hasUnseenContent()
  end

  setCompendiumHighlight(highlighted)
end

function handleButtonClick(button)
  if isToggleButton(button:getParent():getId()) then
    if button:isChecked() then
      button:setImageClip(torect("0 0 20 20"))
      button:setChecked(false)
      button:setTooltip(tr(getControlButtonTooltip(button:getParent():getId()), "Open"))
    else
      button:setImageClip(torect(getSideButtonOnClip(button:getParent():getId())))
      button:setChecked(true)
      button:setTooltip(tr(getControlButtonTooltip(button:getParent():getId()), "Close"))
    end
  else
    button:setChecked(true)
    scheduleEvent(function()
      button:setChecked(false)
    end, 100)

    if currentOpenWidget then
      forceCloseButton(currentOpenWidget)
    end
    currentOpenWidget = button
  end

  -- [debug log desativado] g_logger.info(string.format("[sidebuttons] abrindo dialog='%s'", tostring(button:getParent() and button:getParent():getId() or '?')))
  executeButtonFunctionality(button)
end

function isToggleButton(buttonId)
  for _, toggleButtonId in pairs(toggleButtons) do
      if buttonId == toggleButtonId then
          return true
      end
  end
  return false
end

function executeButtonFunctionality(button)
  if button:getParent():getId() == "skillsWidget" then
    if button:isChecked(true) then
      modules.game_skills:open()
    else
      modules.game_skills:close()
      button:setChecked(false)
    end
  elseif button:getParent():getId() == "battleListWidget" then
    if button:isChecked(true) then
        modules.game_battle:open()
        button:setChecked(true)
      else
        modules.game_battle:close()
        button:setChecked(false)
    end
  elseif button:getParent():getId() == "partyWidget" then
      modules.game_party_list.toggle()
  elseif button:getParent():getId() == "vipWidget" then
    if button:isChecked(true) then
        modules.game_viplist.toggle()
      else
        modules.game_viplist:close()
        button:setChecked(false)
    end
  elseif button:getParent():getId() == "spellListWidget" then
    modules.game_spells.toggle()
  elseif button:getParent():getId() == "skillWheelDialog" then
    modules.game_wheel:toggle()
  elseif button:getParent():getId() == "questDialog" then
    g_game.requestQuestLog()
    modules.game_questlog:toggle()
  elseif button:getParent():getId() == "questTrackerWidget" then
    modules.game_questlog:toggleTracker()
  elseif button:getParent():getId() == "button_minibot" then
    modules.game_minibot.toggle()
  elseif button:getParent():getId() == "unjustifiedPoinsWidget" then
    modules.game_unjustifiedpoints:toggle()
  elseif button:getParent():getId() == "preyDialog" then
    modules.game_prey.show()
  elseif button:getParent():getId() == "preyWidget" then
    modules.game_prey:toggleTracker()
  elseif button:getParent():getId() == "rewardWallDialog" then
      g_game.openDailyReward()
  elseif button:getParent():getId() == "analyticsSelectorWidget" then
    modules.game_analyser:toggle()
  elseif button:getParent():getId() == "compendiumDialog" then
    modules.game_compendium:show(true)
    refreshCompendiumHighlight()
  elseif button:getParent():getId() == "playerGuide" then
    scheduleEvent(function()
      modules.game_guide:toggle()
    end, 1)
  elseif button:getParent():getId() == "cyclopediaDialog" then
    if button:getActionId() ~= 0 then
      modules.game_cyclopedia.toggleRedirect("Bestiary", button:getActionId())
      button:setActionId(0)
      button:getParent().highlight:setVisible(false)
      button:getParent().brightButton:setVisible(false)
    else
      modules.game_cyclopedia:toggle()
    end
  elseif button:getParent():getId() == "bosstiaryDialog" then
    if button:getActionId() ~= 0 then
      modules.game_cyclopedia.toggleRedirect("Bosstiary", button:getActionId())
      button:setActionId(0)
      button:getParent().highlight:setVisible(false)
      button:getParent().brightButton:setVisible(false)
    else
      modules.game_cyclopedia.Bosstiary.onSideButtonRedirect()
    end
  elseif button:getParent():getId() == "bossslotsDialog" then
    modules.game_cyclopedia.BosstiarySlot.onSideButtonRedirect()
  elseif button:getParent():getId() == "bosstiaryTrackerWidget" then
    modules.game_trackers.toggleBossTracker()
  elseif button:getParent():getId() == "bestiaryTrackerWidget" then
    modules.game_trackers.toggleBestiaryTracker()
  elseif button:getParent():getId() == "imbuementTrackerWidget" then
    modules.game_trackers.toggleImbuementTracker()
  elseif button:getParent():getId() == "exaltationForgeDialog" then
    modules.game_forge:toggle()
  elseif button:getParent():getId() == "lenshelpFunction" then
    if button:isChecked(true) then
      modules.game_minimap:toggle()
      button:setChecked(true)
      button:getParent().highlight:setVisible(false)
      button:getParent().brightButton:setVisible(true)
    else
      modules.game_minimap:toggle()
      button:setChecked(false)
      button:getParent().highlight:setVisible(true)
    end
  elseif button:getParent():getId() == "highscoresDialog" then
    modules.game_highscores:show(true)
  elseif button:getParent():getId() == "weaponProficiency" then
    modules.game_proficiency.requestOpenWindow()
  elseif button:getParent():getId() == "button_taskhunting" then
    if modules.game_taskhunting and modules.game_taskhunting.toggle then
      modules.game_taskhunting.toggle()
    end
  elseif button:getParent():getId() == "manageShortcuts" then
    m_settings.toggleShortcuts()
  end
end

-- Some modules (game_cyclopedia, etc) historically only exposed `close()` or
-- never had a `hide` symbol at all, which made the dot/colon mix below crash
-- with "attempt to call method 'hide' (a nil value)" whenever the user opened
-- a second side button while the first one was the current widget. Going
-- through this helper means we always probe for the actual method and pick
-- whichever close/hide/toggle the module exposes, instead of hard-coding one
-- shape per side button.
-- Descobre, da melhor forma possivel, se a janela do modulo esta ABERTA/visivel.
-- Retorna true/false quando consegue determinar; nil quando nao sabe.
local function moduleLooksOpen(mod)
  for _, q in ipairs({ 'isOpen', 'isVisible' }) do
    local fn = mod[q]
    if type(fn) == 'function' then
      local ok, v = pcall(fn, mod)
      if ok then return v and true or false end
    end
  end
  -- Convencao do projeto: a janela costuma estar num global *Window/*Widget do modulo.
  for k, v in pairs(mod) do
    if type(k) == 'string' and k:lower():find('window') and v ~= nil then
      local ok, vis = pcall(function() return v.isVisible and v:isVisible() end)
      if ok and vis ~= nil then return vis and true or false end
    end
  end
  return nil
end

local function safeClose(mod, methodNames)
  if not mod then return end
  for _, name in ipairs(methodNames) do
    local fn = mod[name]
    if type(fn) == 'function' then
      -- 'toggle' ABRE quando a janela esta fechada. Num "force close" isso reabria
      -- janelas ja fechadas (bug: Cyclopedia voltando atras do Forge). So acionamos
      -- o toggle se a janela NAO estiver comprovadamente fechada.
      if name == 'toggle' then
        local open = moduleLooksOpen(mod)
        if open == false then
          -- [debug log desativado] g_logger.info(string.format("[sidebuttons] safeClose: janela ja fechada, ignorando toggle (%s)", tostring(mod)))
          return
        end
      end
      -- [debug log desativado] g_logger.info(string.format("[sidebuttons] safeClose -> %s() em %s", tostring(name), tostring(mod)))
      local ok, err = pcall(fn, mod)
      if not ok then
        -- [debug log desativado] g_logger.warning(string.format("[sidebuttons] %s.%s failed: %s", tostring(mod), name, tostring(err)))
      end
      return
    end
  end
end

local sideButtonCloseDispatch = {
  spellListWidget       = function() safeClose(modules.game_spells, { 'hide', 'close', 'toggle' }) end,
  skillWheelDialog      = function() safeClose(modules.game_wheel, { 'hide', 'close', 'toggle' }) end,
  questDialog           = function() safeClose(modules.game_questlog, { 'hide', 'close', 'toggle' }) end,
  button_minibot        = function() safeClose(modules.game_minibot, { 'hide', 'close', 'toggle' }) end,
  preyDialog            = function() safeClose(modules.game_prey, { 'hide', 'close', 'toggle' }) end,
  rewardWallDialog      = function() safeClose(modules.game_dailyreward, { 'closeDaily', 'hide', 'close' }) end,
  compendiumDialog      = function() safeClose(modules.game_compendium, { 'hide', 'close', 'toggle' }) end,
  playerGuide           = function() safeClose(modules.game_guide, { 'hide', 'close', 'toggle' }) end,
  cyclopediaDialog      = function() safeClose(modules.game_cyclopedia, { 'hide', 'close', 'toggle' }) end,
  bosstiaryDialog       = function() safeClose(modules.game_cyclopedia, { 'hide', 'close', 'toggle' }) end,
  bossslotsDialog       = function() safeClose(modules.game_cyclopedia, { 'hide', 'close', 'toggle' }) end,
  exaltationForgeDialog = function() safeClose(modules.game_forge, { 'hide', 'close', 'toggle' }) end,
  lenshelpFunction      = function() safeClose(modules.game_minimap, { 'toggle', 'hide', 'close' }) end,
  highscoresDialog      = function() safeClose(modules.game_highscores, { 'hide', 'close', 'toggle' }) end,
  manageShortcuts       = function() safeClose(m_settings, { 'hide', 'close', 'toggle' }) end,
  button_taskhunting    = function() safeClose(modules.game_taskhunting, { 'hide', 'close', 'toggle' }) end,
}

function forceCloseButton(button)
  if not button:getParent() then
    return true
  end

  local id = button:getParent():getId()
  local handler = sideButtonCloseDispatch[id]
  if handler then
    -- [debug log desativado] g_logger.info(string.format("[sidebuttons] forceClose dialog anterior='%s'", tostring(id)))
    handler()
  end
end

function toggleMainButtons()
  isHiddenMenuActive = not isHiddenMenuActive

  if not buttonsWindow then return end

  buttonsWindow.minimized = isHiddenMenuActive
  local buttonsPanel = buttonsWindow:recursiveGetChildById('buttons')
  local optionsButton = buttonsWindow:recursiveGetChildById('options')
  local logoutButton = buttonsWindow:recursiveGetChildById('logout')
  local separator = buttonsWindow:recursiveGetChildById('sep')
  local hiddenMenuButton = buttonsWindow:recursiveGetChildById('hiddenMenu')

  buttonsPanel:setVisible(not isHiddenMenuActive)
  optionsButton:setVisible(not isHiddenMenuActive)
  logoutButton:setVisible(not isHiddenMenuActive)
  separator:setVisible(not isHiddenMenuActive)

  if isHiddenMenuActive then
    buttonsWindow:setHeight(27)
    hiddenMenuButton:setImageSource('/images/ui/hidden-menu-up')
  else
    updateSideButtons()
    hiddenMenuButton:setImageSource('/images/ui/hidden-menu-down')
  end
end

function move(panel, index, minimized)
  buttonsWindow:setParent(panel)
  buttonsWindow:open()
  if minimized then
    toggleMainButtons()
  end

  return buttonsWindow
end
