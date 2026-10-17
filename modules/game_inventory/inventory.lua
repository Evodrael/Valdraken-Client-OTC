InventorySlotStyles = {
  [InventorySlotHead] = "HeadSlot",
  [InventorySlotNeck] = "NeckSlot",
  [InventorySlotBack] = "BackSlot",
  [InventorySlotBody] = "BodySlot",
  [InventorySlotRight] = "RightSlot",
  [InventorySlotLeft] = "LeftSlot",
  [InventorySlotLeg] = "LegSlot",
  [InventorySlotFeet] = "FeetSlot",
  [InventorySlotFinger] = "FingerSlot",
  [InventorySlotAmmo] = "AmmoSlot"
}

inventoryWindow = nil
inventoryPanel = nil
inventoryButton = nil
assistantButton = nil
purseButton = nil

combatControlsWindow = nil
fightOffensiveBox = nil
fightBalancedBox = nil
fightDefensiveBox = nil
chaseModeButton = nil
safeFightButton = nil
fightModeRadioGroup = nil
chaseModeRadioGroup = nil
chaseModeStandBox = nil
chaseModeChaseBox = nil
buttonPvp = nil
pvpModesPanel = nil
soulLabel = nil
capLabel = nil
conditionPanel = nil
slotValue = {}

pvpModeCheckBox = nil

doveModeWidget = nil
whiteModeWidget = nil
yellowModeWidget = nil
redModeWidget = nil

-- A Twist of Fate nao e' uma bless de protecao: o servidor so a consome em morte
-- PvP e o sendBlessStatus a ignora de proposito ao contar. Fica marcada com
-- pvpOnly para nao contaminar nem o glow do inventario nem o tooltip -- era isso
-- que fazia o jogador com so a ToF acesa ler "You are protected by".
local inventoryBlessingTooltipNames = {
  { mask = bit.lshift(1, 1), name = "Twist of Fate", pvpOnly = true },
  { mask = bit.lshift(1, 2), name = "The Wisdom of Solitude" },
  { mask = bit.lshift(1, 3), name = "The Spark of the Phoenix" },
  { mask = bit.lshift(1, 4), name = "The Fire of the Suns" },
  { mask = bit.lshift(1, 5), name = "The Spiritual Shielding" },
  { mask = bit.lshift(1, 6), name = "The Embrace of Tibia" },
  { mask = bit.lshift(1, 7), name = "Heart of the Mountain" },
  { mask = bit.lshift(1, 8), name = "Blood of the Mountain" }
}

-- Quantas bless de protecao levam a chance de perda a zero, e quantas existem.
-- Derivado da tabela acima para nao ficar um "7" solto que mente se ela mudar.
local PROTECTION_FULL_COUNT = 5
local PROTECTION_TOTAL_COUNT = 0
for _, blessing in ipairs(inventoryBlessingTooltipNames) do
  if not blessing.pvpOnly then
    PROTECTION_TOTAL_COUNT = PROTECTION_TOTAL_COUNT + 1
  end
end

-- Chance de a mochila cair, por numero de bless de protecao. Espelha o
-- Blessings.LossPercent do servidor (data/libs/systems/blessing.lua); cada peca
-- equipada vale um decimo disso, como o DropLoot aplica.
local CONTAINER_LOSS_PERCENT = { [0] = 100, [1] = 70, [2] = 45, [3] = 25, [4] = 10, [5] = 0 }

local function formatLossWarning(protectionCount)
  local container = CONTAINER_LOSS_PERCENT[math.min(protectionCount, PROTECTION_FULL_COUNT)] or 0
  return string.format('Se morrer agora: a mochila cai com %d%% de chance e cada item equipado com %.1f%%.', container, container / 10)
end

function init()
  connect(LocalPlayer, {
    onInventoryChange = onInventoryChange,
    onBlessingsChange = onBlessingsChange
  })

  inventoryWindow = g_ui.loadUI('inventory', m_interface.getRightPanel())
  inventoryWindow:disableResize()
  inventoryPanel = inventoryWindow:getChildById('contentsPanel')
  -- Altura ajustada ao conteudo real (stopButton termina ~167px) para nao deixar
  -- espaco vazio entre o inventario/Stop e o painel de Opcoes/Store logo abaixo.
  inventoryWindow:setHeight(170)
  assistantButton = inventoryWindow:recursiveGetChildById('button_minibot')

  purseButton = inventoryWindow:recursiveGetChildById('purseButton')
  purseButton.onClick = function()
    local player = g_game.getLocalPlayer()
    if not player then return end
    local purse = player:getInventoryItem(InventorySlotPurse)
    if purse then
      g_game.use(purse)
    end
  end

  -- controls
  fightOffensiveBox = inventoryWindow:recursiveGetChildById('fightOffensiveBox')
  fightBalancedBox = inventoryWindow:recursiveGetChildById('fightBalancedBox')
  fightDefensiveBox = inventoryWindow:recursiveGetChildById('fightDefensiveBox')

  chaseModeStandBox = inventoryWindow:recursiveGetChildById('chaseModeBoxStand')
  chaseModeChaseBox = inventoryWindow:recursiveGetChildById('chaseModeBoxChase')

  chaseModeButton = inventoryWindow:recursiveGetChildById('chaseModeBox')
  safeFightButton = inventoryWindow:recursiveGetChildById('safeFightBox')
  buttonPvp = inventoryWindow:recursiveGetChildById('openPvpButton')
  pvpModesPanel = inventoryWindow:recursiveGetChildById('pvpModesPanel')

  doveModeWidget = inventoryWindow:recursiveGetChildById('doveMode')
  doveModeWidget.pvpMode = PVPWhiteDove
  whiteModeWidget = inventoryWindow:recursiveGetChildById('whiteMode')
  whiteModeWidget.pvpMode = PVPWhiteHand
  yellowModeWidget = inventoryWindow:recursiveGetChildById('yellowMode')
  yellowModeWidget.pvpMode = PVPYellowHand
  redModeWidget = inventoryWindow:recursiveGetChildById('redMode')
  redModeWidget.pvpMode = PVPRedFist

  pvpModeCheckBox = UIRadioGroup.create()
  pvpModeCheckBox:addWidget(doveModeWidget)
  pvpModeCheckBox:addWidget(whiteModeWidget)
  pvpModeCheckBox:addWidget(yellowModeWidget)
  pvpModeCheckBox:addWidget(redModeWidget)

  pvpModeCheckBox.onSelectionChange = onSelectionChangePvp
  pvpModeCheckBox:selectWidget(doveModeWidget)

  whiteDoveBox = inventoryWindow:recursiveGetChildById('doveMode')
  whiteHandBox = inventoryWindow:recursiveGetChildById('whiteMode')
  yellowHandBox = inventoryWindow:recursiveGetChildById('yellowMode')
  redFistBox = inventoryWindow:recursiveGetChildById('redMode')

  fightModeRadioGroup = UIRadioGroup.create()
  fightModeRadioGroup:addWidget(fightOffensiveBox)
  fightModeRadioGroup:addWidget(fightBalancedBox)
  fightModeRadioGroup:addWidget(fightDefensiveBox)

  chaseModeRadioGroup = UIRadioGroup.create()
  chaseModeRadioGroup:addWidget(chaseModeStandBox)
  chaseModeRadioGroup:addWidget(chaseModeChaseBox)

  connect(fightModeRadioGroup, { onSelectionChange = onSetFightMode })
  connect(chaseModeRadioGroup, { onSelectionChange = onSetChaseMode })
  connect(safeFightButton, { onCheckChange = onSetSafeFight })
  if buttonPvp then
    connect(buttonPvp, { onClick = onOpenPvpButtonClick })
  end
  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
    onFightModeChange = update,
    onChaseModeChange = update,
    onSafeFightChange = update,
    onPVPModeChange   = update,
    onWalk = check,
    onAutoWalk = check,
    onBlessingsChange = onGameBlessingsChange,
    onUpdateBlessDialog = onUpdateBlessDialog,
  })

  if g_game.isOnline() then
    online()
  end
  -- controls end

  -- status
  soulLabel = inventoryWindow:recursiveGetChildById('soulLabel')
  capLabel = inventoryWindow:recursiveGetChildById('capLabel')
  conditionPanel = inventoryWindow:recursiveGetChildById('conditionPanel')
  m_settings.ConditionsHUD:startInventoryPanel(conditionPanel)


  connect(LocalPlayer, {
                         onSoulChange = onSoulChange,
                        onTotalCapacityChange = onTotalCapacityChange,
                        onBaseCapacityChange = onBaseCapacityChange,
                         onFreeCapacityChange = onFreeCapacityChange
                        })
  -- status end

  refresh()
  inventoryWindow:setup()
  inventoryWindow:open()
end

function terminate()
  disconnect(LocalPlayer, {
    onInventoryChange = onInventoryChange,
    onBlessingsChange = onBlessingsChange
  })

  -- controls
  if g_game.isOnline() then
    offline()
  end

  fightModeRadioGroup:destroy()

  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
    onFightModeChange = update,
    onChaseModeChange = update,
    onSafeFightChange = update,
    onPVPModeChange   = update,
    onWalk = check,
    onAutoWalk = check,
    onBlessingsChange = onGameBlessingsChange,
    onUpdateBlessDialog = onUpdateBlessDialog,
  })

  -- controls end
  -- status
  disconnect(LocalPlayer, {
                         onSoulChange = onSoulChange,
                        onTotalCapacityChange = onTotalCapacityChange,
                        onBaseCapacityChange = onBaseCapacityChange,
                         onFreeCapacityChange = onFreeCapacityChange })
  -- status end

  inventoryWindow:destroy()
  if inventoryButton then
    inventoryButton:destroy()
  end
end

function getAssistantButton()
  if not inventoryWindow then
    return nil
  end

  return inventoryWindow:recursiveGetChildById('button_minibot')
end

function toggleAssistant()
  if modules.game_minibot and modules.game_minibot.toggle then
    modules.game_minibot.toggle()
  end
end

function getInventoryPanel()
  return inventoryPanel
end

function toggleAdventurerStyle(hasBlessing)
  for slot = InventorySlotFirst, InventorySlotLast do
    local itemWidget = inventoryPanel:getChildById('slot' .. slot)
    if itemWidget then
      itemWidget:setOn(hasBlessing)
    end
  end
end

-- Conta so as bless que protegem itens. O conjunto legado { 2, 4, 8, 16, 32 }
-- que estava aqui incluia o bit 1, que no esquema do bless dialog e' a Twist of
-- Fate: com 4 bless de protecao mais a ToF o inventario acendia como se nao
-- houvesse perda nenhuma, e ainda havia 10% na mochila e 1% por peca.
local function countProtectionBlessings(blessings)
  blessings = blessings or 0

  local count = 0
  for _, blessing in ipairs(inventoryBlessingTooltipNames) do
    if not blessing.pvpOnly and Bit.hasBit(blessings, blessing.mask) then
      count = count + 1
    end
  end

  return count
end

local function hasAllMainBlessings(blessings)
  return countProtectionBlessings(blessings) >= PROTECTION_FULL_COUNT
end

function refresh()
  local player = g_game.getLocalPlayer()
  for i = InventorySlotFirst, InventorySlotPurse do
    if g_game.isOnline() then
      onInventoryChange(player, i, player:getInventoryItem(i))
    else
      onInventoryChange(player, i, nil)
    end
    toggleAdventurerStyle(player and hasAllMainBlessings(player:getBlessings()) or false)
  end
  if player then
    onSoulChange(player, player:getSoul())
    onFreeCapacityChange(player, player:getFreeCapacity())
    onBaseCapacityChange(player, player:getFreeCapacity())
    onTotalCapacityChange(player, player:getFreeCapacity())
    onBlessingsChange(player, player:getBlessings(), 0)
  end

  purseButton:setVisible(true)
end

function toggle()
  if not inventoryButton then
    return
  end
  if inventoryButton:isOn() then
    inventoryWindow:close()
    inventoryButton:setOn(false)
  else
    inventoryWindow:open()
    inventoryButton:setOn(true)
  end
end

function onMiniWindowClose()
  if not inventoryButton then
    return
  end
  inventoryButton:setOn(false)
end

function getLeftSlotItem()
  local itemWidget = inventoryPanel:getChildById('slot6')
  if not itemWidget then
    return nil
  end
  return itemWidget:getItem()
end

local function shouldMirrorHandItem(item)
  if not item then
    return false
  end

  local dualWielding = item:isDualWielding()
  if dualWielding == true or dualWielding == 1 then
    return true
  end

  return item.getWeaponType and item:getWeaponType() == WEAPON_FIST
end

local function formatCapacityShort(value)
  value = math.floor(tonumber(value) or 0)
  -- The user wants the full integer (1, 2, ... 99999) for "small" caps and
  -- only the abbreviated `k` / `M` formats once the value crosses 100000.
  -- The previous threshold (>=1000) shortened "1500" into "1k", which is
  -- exactly what the report asks us to stop doing.
  if value >= 1000000 then
    local rounded = math.floor(value / 100000) / 10
    if rounded == math.floor(rounded) then
      rounded = math.floor(rounded)
    end
    return rounded .. "M"
  elseif value >= 100000 then
    return math.floor(value / 1000) .. "k"
  end
  return value
end

function configureMirror()
  local itemWidget = inventoryPanel:getChildById('slot6')
  local item = itemWidget:getItem()

  local itemWidgetMirror = inventoryPanel:getChildById('slot5')
  itemWidgetMirror:setFlipDirection(Flip.None)
  itemWidgetMirror.slot5Dual:setVisible(false)
  itemWidgetMirror:setPhantom(false)
  itemWidgetMirror:setOpacity(1.0)

  if not item and itemWidgetMirror.clone then
    itemWidgetMirror:setStyle(InventorySlotStyles[5])
    itemWidgetMirror:setItem(nil)
    itemWidgetMirror.clone = false
    return
  elseif not item then
    return
  end

  if not itemWidgetMirror.clone and itemWidgetMirror:getItem() then
    return
  end

  if not shouldMirrorHandItem(item) then
    itemWidgetMirror:setStyle(InventorySlotStyles[5])
    itemWidgetMirror:setItem(nil)
    itemWidgetMirror.clone = false
    return
  end

  itemWidgetMirror:setItemId(item:getId())
  itemWidgetMirror:setStyle('NoneInventoryItem')
  itemWidgetMirror:setFlipDirection(Flip.Horizontal)
  itemWidgetMirror.slot5Dual:setVisible(true)
  itemWidgetMirror:setPhantom(true)
  itemWidgetMirror:setOpacity(0.55)
  itemWidgetMirror.clone = true
end

function copyLeftHandToMirror()
  local itemWidget = inventoryPanel:getChildById('slot6')
  local item = itemWidget:getItem()
  if not item then
    return
  end
  local itemWidgetMirror = inventoryPanel:getChildById('slot5')
  if itemWidgetMirror.clone then
    return
  end

  addEvent(function() configureMirror() end, 100)
end

-- hooked events
function onInventoryChange(player, slot, item, oldItem)
  if slot > InventorySlotPurse then return end

  if slot == InventorySlotPurse then
    return
  end

  local itemWidget = inventoryPanel:getChildById('slot' .. slot)
  itemWidget:setItemShader('')
  itemWidget._skipRarityFrame = true
  if item then
    itemWidget:setStyle('InventoryItem')
    itemWidget:setItem(item)
    if ItemsDatabase and ItemsDatabase.setRarityItem then
      ItemsDatabase.setRarityItem(itemWidget, item)
    end
    if slot == 6 then
      addEvent(function()  configureMirror() end, 100)
    elseif slot == 5 then
      itemWidget.clone = false
    end
    updateFlags(item, itemWidget)
  else
    if slot == 6 then
      addEvent(function() configureMirror() end, 100)
    elseif slot == 5 then
      copyLeftHandToMirror()
    end
    itemWidget:setStyle(InventorySlotStyles[slot])
    itemWidget.quicklootflags:setVisible(false)
    itemWidget:setItem(nil)
    if ItemsDatabase and ItemsDatabase.setRarityItem then
      ItemsDatabase.setRarityItem(itemWidget, nil)
    end
  end
  slotValue[slot] = item
end

function SlotValue()
  return slotValue
end

local function normalizeBlessingChangeArgs(player, blessings, oldBlessings)
  if type(player) == 'number' then
    return g_game.getLocalPlayer(), player, blessings or 0
  end

  player = player or g_game.getLocalPlayer()
  if not blessings and player and player.getBlessings then
    blessings = player:getBlessings()
  end

  return player, blessings or 0, oldBlessings or 0
end

local function getBlessingBitsFromDialog(data)
  if type(data) ~= 'table' then
    return 0
  end

  local blessings = 0
  local blessList = data.blesses or data
  for _, info in ipairs(blessList) do
    if type(info) == 'table' then
      local blessBitwise = tonumber(info.blessBitwise or info[1]) or 0
      local playerBlessCount = tonumber(info.playerBlessCount or info[2]) or 0
      if blessBitwise > 0 and playerBlessCount > 0 then
        blessings = blessings + blessBitwise
      end
    end
  end

  return blessings
end

function onGameBlessingsChange(playerOrBlessings, blessingsOrVisualState, oldBlessings)
  if type(playerOrBlessings) == 'number' then
    local player = g_game.getLocalPlayer()
    if player then
      onBlessingsChange(player, playerOrBlessings, 0)
    end
    return
  end

  onBlessingsChange(playerOrBlessings, blessingsOrVisualState, oldBlessings)
end

function onUpdateBlessDialog(data)
  local player = g_game.getLocalPlayer()
  if not player then
    return
  end

  local blessings = getBlessingBitsFromDialog(data)
  if blessings > 0 then
    onBlessingsChange(player, blessings, 0)
  end
end

function onBlessingsChange(player, blessings, oldBlessings)
  player, blessings, oldBlessings = normalizeBlessingChangeArgs(player, blessings, oldBlessings)
  if not player then
    return
  end

  local adventurerMask = Blessings and Blessings.Adventurer or 1
  local hasAdventurerBlessing = Bit.hasBit(blessings, adventurerMask)
  -- O status vem do servidor, que ja conta sem a Twist of Fate: e' a fonte
  -- autoritativa enquanto o bless dialog nao chegou (1 = nenhuma protecao,
  -- 2 = cinco ou mais, 3 = sete).
  local status = player:getBlessingStatus()
  local protectionCount = countProtectionBlessings(blessings)
  -- O bit Adventurer e' posto pelo parseBlessings quando o proprio servidor manda
  -- o flag de glow, o que cobre a adventurer's blessing abaixo do level 50.
  toggleAdventurerStyle(hasAdventurerBlessing or status > 1 or protectionCount >= PROTECTION_FULL_COUNT)

  local protectionNames, pvpNames = {}, {}
  for _, blessing in ipairs(inventoryBlessingTooltipNames) do
    if Bit.hasBit(blessings, blessing.mask) then
      table.insert(blessing.pvpOnly and pvpNames or protectionNames, blessing.name)
    end
  end

  local tooltip
  if protectionCount > 0 then
    tooltip = string.format('Blessings de protecao: %d de %d.', protectionCount, PROTECTION_TOTAL_COUNT)
    for _, name in ipairs(protectionNames) do
      tooltip = tooltip .. '\n - ' .. name
    end
    if protectionCount >= PROTECTION_FULL_COUNT then
      tooltip = tooltip .. '\nMorrendo para um monstro voce nao perde itens.'
    else
      tooltip = tooltip .. '\n' .. formatLossWarning(protectionCount)
    end
  elseif hasAdventurerBlessing or status > 1 then
    -- Protecao ligada pelo servidor sem o bless dialog ter chegado. Aqui o client
    -- nao sabe quais sao, e inventar a lista e' o que produzia a mentira.
    tooltip = 'Protecao ativa.\nAbra a janela de blessings para ver a lista.'
  else
    tooltip = 'Voce NAO esta protegido.\n' .. formatLossWarning(0) .. '\nDigite !bless para comprar as blessings de protecao.'
  end

  if #pvpNames > 0 then
    tooltip = tooltip .. '\n\nSomente PvP, nao protege itens contra monstros:'
    for _, name in ipairs(pvpNames) do
      tooltip = tooltip .. '\n - ' .. name
    end
  end

  blessedButton = inventoryWindow:recursiveGetChildById('blessedButton')
  if not blessedButton then
    return
  end
  blessedButton:setTooltip(tooltip)
  if status == 1 then
    blessedButton:setImageSource('/images/game/blessings/button-blessings-grey-idle')
  elseif status == 2 then
    blessedButton:setImageSource('/images/game/blessings/button-blessings-gold-idle')
  elseif status == 3 then
    blessedButton:setImageSource('/images/game/blessings/button-blessings-green-idle')
  end
end

-- controls
function update()
  local fightMode = g_game.getFightMode()
  if fightMode == FightOffensive then
    fightModeRadioGroup:selectWidget(fightOffensiveBox)
  elseif fightMode == FightBalanced then
    fightModeRadioGroup:selectWidget(fightBalancedBox)
  else
    fightModeRadioGroup:selectWidget(fightDefensiveBox)
  end

  local chaseMode = g_game.getChaseMode()
  if chaseMode == ChaseOpponent then
    chaseModeRadioGroup:selectWidget(chaseModeChaseBox)
  else
    chaseModeRadioGroup:selectWidget(chaseModeStandBox)
  end

  local safeFight = g_game.isSafeFight()
  safeFightButton:setChecked(not safeFight)
  if safeFightButton:isChecked() then
    safeFightButton:setTooltip(tr("Secure Mode Off: You are able to attack someone by targeting,\nregardless of your expert mode. You risk white, red and black\nskulls as well as a protection zone block."))
  else
    safeFightButton:setTooltip(tr("Secure Mode On: You are able to attack only those players\nyour expert mode allows. You risk skulls and protection zone\nblocks depending on your active expert mode."))
  end

  if buttonPvp then
    local isOpenPvPWorld = g_game.getCanChangePvpFrameOption()
    if not isOpenPvPWorld then
      pvpModesPanel:setVisible(false)
      buttonPvp:setChecked(false)
    end

    buttonPvp:setEnabled(isOpenPvPWorld)
  end

  if g_game.getFeature(GamePVPMode) then
    local pvpMode = g_game.getPVPMode()
    local pvpWidget = getPVPBoxByMode(pvpMode)
  end
end

function check()
  if m_settings.getOption('autoChaseOverride') then
    if g_game.isAttacking() and g_game.getChaseMode() == ChaseOpponent then
      g_game.doThing(false)
      g_game.setChaseMode(DontChase)
      g_game.doThing(true)
    end
  end
end

function online()
  local benchmark = g_clock.millis()
  local player = g_game.getLocalPlayer()
  if player then
    local char = g_game.getCharacterName()

    local lastCombatControls = g_settings.getNode('LastCombatControls')

    -- Check if the world is OpenPVP and Enable buttonPvp
    if g_game.getCanChangePvpFrameOption() then
        buttonPvp:setOn(true)
      else
        buttonPvp:setOn(false)
    end

    if not table.empty(lastCombatControls) then
      if lastCombatControls[char] then
        local lasfightMode = lastCombatControls[char].fightMode
        local laschaseMode = lastCombatControls[char].chaseMode
        g_game.doThing(false)
        g_game.setFightMode(lasfightMode)
        g_game.doThing(true)
        g_game.doThing(false)
        g_game.setChaseMode(laschaseMode)
        g_game.doThing(true)
        g_game.doThing(false)
        g_game.setSafeFight(true)
        g_game.doThing(true)
        g_game.doThing(false)
        g_game.setPVPMode(0)
        g_game.doThing(true)
      end
    end
  end
  update()
  refresh()
  consoleln("Inventory controls refreshed in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function offline()
  local lastCombatControls = g_settings.getNode('LastCombatControls')
  if not lastCombatControls then
    lastCombatControls = {}
  end

  local player = g_game.getLocalPlayer()
  if player then
    local char = g_game.getCharacterName()
    lastCombatControls[char] = {
      fightMode = g_game.getFightMode(),
      chaseMode = g_game.getChaseMode(),
    }

    -- save last combat control settings
    g_settings.setNode('LastCombatControls', lastCombatControls)
  end
end

function onSetFightMode(self, selectedFightButton)
  if selectedFightButton == nil then return end
  local buttonId = selectedFightButton:getId()
  local fightMode
  if buttonId == 'fightOffensiveBox' then
    fightMode = FightOffensive
  elseif buttonId == 'fightBalancedBox' then
    fightMode = FightBalanced
  else
    fightMode = FightDefensive
  end
  g_game.doThing(false)
  g_game.setFightMode(fightMode)
  g_game.doThing(true)
end

function onSetChaseMode(self, selectedButton)
  if selectedButton == nil then return end
  local buttonId = selectedButton:getId()
  local chaseMode
  if buttonId == 'chaseModeBoxChase' then
    chaseMode = ChaseOpponent
  else
    chaseMode = DontChase
  end
  g_game.doThing(false)
  g_game.setChaseMode(chaseMode)
  g_game.doThing(true)
end

function onSetSafeFight(self, checked)
  g_game.doThing(false)
  g_game.setSafeFight(not checked)
  g_game.doThing(true)
end

function onSetPVPMode(self, selectedPVPButton)
  if selectedPVPButton == nil then
    return
  end

  local buttonId = selectedPVPButton:getId()
  local pvpMode = PVPWhiteDove
  if buttonId == 'whiteDoveBox' then
    pvpMode = PVPWhiteDove
  elseif buttonId == 'whiteHandBox' then
    pvpMode = PVPWhiteHand
  elseif buttonId == 'yellowHandBox' then
    pvpMode = PVPYellowHand
  elseif buttonId == 'redFistBox' then
    pvpMode = PVPRedFist
  end

  g_game.setPVPMode(pvpMode)
end

function getPVPBoxByMode(mode)
  local widget = nil
  if mode == PVPWhiteDove then
    widget = whiteDoveBox
  elseif mode == PVPWhiteHand then
    widget = whiteHandBox
  elseif mode == PVPYellowHand then
    widget = yellowHandBox
  elseif mode == PVPRedFist then
    widget = redFistBox
  end
  return widget
end

function onSoulChange(localPlayer, soul)
  if not soul then return end
  soulLabel:setText(tr'' .. soul)
end

function onFreeCapacityChange(player, freeCapacity)
  if not freeCapacity then return end
  freeCapacity = math.floor(freeCapacity)
  local formattedCapacity = tostring(formatCapacityShort(freeCapacity))
  -- Use the smaller font for any abbreviated value (k or M) and for long
  -- numbers (5+ digits) so the text never overflows the small cap label.
  local needsSmallFont = formattedCapacity:find("[kM]") ~= nil or #formattedCapacity >= 5
  capLabel.label:setFont(needsSmallFont and "verdana-9px-bold" or "verdana-cap-bold")
  capLabel.label:setTextAlign(AlignCenter)
  capLabel.label:setTextOffset("0 4")
  capLabel.label:setText(formattedCapacity)
  if freeCapacity == 0 then
    capLabel.label:setColor('$var-text-cip-store-red')
  elseif player and player:getTotalCapacity() ~= player:getBaseCapacity() then
    capLabel.label:setColor('#44ad25') -- green
  else
    capLabel.label:setColor('$var-text-cip-color')
  end
end

function onTotalCapacityChange(player, freeCapacity)
  onFreeCapacityChange(player, player:getFreeCapacity())
end

function onBaseCapacityChange(player, freeCapacity)
  onFreeCapacityChange(player, player:getFreeCapacity())
end

function onInventoryMinimize(value)
  minimizeButton = inventoryWindow:recursiveGetChildById('minButton')
  minimizeButton:setOn(value)

  capLabel = inventoryWindow:recursiveGetChildById('capLabel')
  conditionPanel = inventoryWindow:recursiveGetChildById('conditionPanel')
  stopButton = inventoryWindow:recursiveGetChildById('stopButton')
  blessedButton = inventoryWindow:recursiveGetChildById('blessedButton')
  openPvpButton = inventoryWindow:recursiveGetChildById('openPvpButton')
  pvpModesPanel = inventoryWindow:recursiveGetChildById('pvpModesPanel')


  for slots = 1, 10 do
    local slot = inventoryWindow:recursiveGetChildById('slot' .. slots)
    if value then slot:hide() else slot:show() end
  end

  inventoryWindow.minimized = value
  inventoryWindow:setHeight(value and 89 or 170)

  if value then
    capLabel:setMarginTop(-120)
    capLabel:setMarginLeft(-60)
    soulLabel:setMarginTop(-99)
    soulLabel:setMarginLeft(14)

    fightOffensiveBox:setMarginTop(-14)
    fightOffensiveBox:setMarginLeft(-57)
    fightBalancedBox:setMarginTop(-19)
    fightBalancedBox:setMarginLeft(20)
    fightDefensiveBox:setMarginTop(-19)
    fightDefensiveBox:setMarginLeft(20)

    chaseModeStandBox:setMarginTop(22)
    chaseModeStandBox:setMarginLeft(-19)
    chaseModeChaseBox:setMarginTop(-19)
    chaseModeChaseBox:setMarginLeft(20)

    safeFightButton:setSize(tosize("20 20"))
    safeFightButton:setImageSource("/images/game/combatmodes/safefight")
    safeFightButton:setImageClip("0 0 20 20")
    safeFightButton:setMarginTop(3)
    safeFightButton:setMarginLeft(0)

    conditionPanel:setMarginTop(-100)
    conditionPanel:setMarginLeft(14)
    conditionPanel:setMarginRight(-3)
    blessedButton:setMarginTop(44)
    blessedButton:setMarginLeft(-11)

    openPvpButton:setSize(tosize("12 12"))
    openPvpButton:setImageSource("/images/game/combatmodes/min-pvpmode")
    openPvpButton:setImageClip("0 0 12 12")
    openPvpButton:setMarginTop(-11)
    openPvpButton:setMarginLeft(-70)

    pvpModesPanel:setMarginTop(-42)
    pvpModesPanel:setMarginLeft(26)

    stopButton:setMarginTop(25)
    stopButton:setMarginLeft(26)
  else
    capLabel:setMarginTop(4)
    capLabel:setMarginLeft(0)
    soulLabel:setMarginTop(4)
    soulLabel:setMarginLeft(0)

    fightOffensiveBox:setMarginTop(-14)
    fightOffensiveBox:setMarginLeft(8)
    fightBalancedBox:setMarginTop(4)
    fightBalancedBox:setMarginLeft(0)
    fightDefensiveBox:setMarginTop(4)
    fightDefensiveBox:setMarginLeft(0)

    chaseModeStandBox:setMarginTop(0)
    chaseModeStandBox:setMarginLeft(3)
    chaseModeChaseBox:setMarginTop(4)
    chaseModeChaseBox:setMarginLeft(0)
    safeFightButton:setSize(tosize("42 20"))
    safeFightButton:setImageSource("/images/game/combatmodes/pvp")
    safeFightButton:setImageClip("0 0 42 20")
    safeFightButton:setMarginTop(6)
    safeFightButton:setMarginLeft(0)

    conditionPanel:setMarginTop(3)
    conditionPanel:setMarginLeft(0)
    conditionPanel:setMarginRight(0)
    blessedButton:setMarginTop(0)
    blessedButton:setMarginLeft(3)

    openPvpButton:setSize(tosize("20 20"))
    openPvpButton:setImageSource("/images/game/combatmodes/pvpmode")
    openPvpButton:setImageClip("0 0 20 20")
    openPvpButton:setMarginTop(4)
    openPvpButton:setMarginLeft(0)

    pvpModesPanel:setMarginTop(7)
    pvpModesPanel:setMarginLeft(0)

    stopButton:setMarginTop(82)
    stopButton:setMarginLeft(0)
  end
end

function openBlessedWindow()
  g_game.requestBlessings()
end

function move(panel, index, minimized)
  addEvent(function()
    inventoryWindow:setParent(panel)
    inventoryWindow:open()
    if minimized then
      onInventoryMinimize(minimized)
    end
  end)

  return inventoryWindow
end

function onOpenPvpButtonClick(widget)
  pvpModesPanel:setVisible(not pvpModesPanel:isVisible())
  if pvpModesPanel:isVisible() then
    buttonPvp:setChecked(true)
  else
    buttonPvp:setChecked(false)
  end
end

function onSelectionChangePvp(widget, selectedWidget)
  g_game.setPVPMode(selectedWidget.pvpMode)
end

function getConditionPanel()
  return conditionPanel
end

function onLeftSlotChange(itemId)
  if not g_game.isOnline() then
    return
  end
  modules.game_topbar.onUpdateProficiencyWidget(itemId == 0)
end
