Bestiary = {}
Bestiary.__index = Bestiary

local BestiaryGroups = {}
local MonsterList = {}
local overviewPage = 1
local monsterListPage = 1
local BESTIARY_MONSTER_ID = 0
local monsterTracked = {}
local MasteryCount = 0
local selectedCharm = 0
local BestiaryMonster
local MonsterId = 0
local CurrentLevel = 0

function Bestiary.reset()
  overviewPage = 1
  monsterListPage = 1
  BestiaryGroups = {}
  MonsterList = {}
  BESTIARY_MONSTER_ID = 0
  selectedCharm = 0
  BestiaryMonster = {}
  MonsterId = 0
  CurrentLevel = 0
end

function Bestiary.getTrackedList()
  return monsterTracked
end

local function normalizeBestiaryGroup(data)
  if type(data) ~= "table" then
    return nil
  end

  local name = data.name or data.bestClass or data.race or data[1]
  if type(name) ~= "string" or #name == 0 then
    return nil
  end

  return {
    name = name,
    amount = data.amount or data.count or data[2] or 0,
    know = data.know or data.unlockedCount or data[3] or 0
  }
end

local function normalizeBestiaryOverviewMonster(data)
  if type(data) ~= "table" then
    return nil
  end

  local monsterId = data[1] or data.id or data.raceId or data.monsterId
  if not monsterId or monsterId == 0 then
    return nil
  end

  return {
    monsterId,
    data[2] or data.currentLevel or 0,
    data[3] or data.creatureAnimusMasteryBonus or data.extraExperience or 0
  }
end

local function normalizeBestiaryMonsterDetails(data)
  if type(data) ~= "table" then
    data = {}
  end

  data.loot = data.loot or {}
  for _, loot in pairs(data.loot) do
    loot.item = loot.item or loot.itemId or 0
    loot.difficulty = loot.difficulty or loot.diffculty or 0
    loot.stackable = loot.stackable
    if loot.stackable == nil then
      loot.stackable = (loot.amount or 0) > 0
    end
    loot.name = loot.name or ""
  end

  data.difficultyCharm = data.difficultyCharm or data.charmValue or 0
  data.health = data.health or data.maxHealth or 0
  data.experience = data.experience or 0
  data.speed = data.speed or 0
  data.armor = data.armor or 0
  data.mitigation = data.mitigation or 0
  data.attackMode = data.attackMode or 0
  data.location = data.location or ""
  data.elements = data.elements or {}

  if type(data.combat) == "table" and #data.elements == 0 then
    for elementIndex, percent in pairs(data.combat) do
      local elementId = tonumber(elementIndex)
      if elementId then
        data.elements[#data.elements + 1] = {
          element = elementId - 1,
          percent = percent
        }
      end
    end
  end

  return data
end

function Bestiary.monsterInTracker(monsterId)
  if not monsterId or monsterId == 0 then
    return false
  end

  for i, tracked in pairs(monsterTracked) do
    if tracked[1] == monsterId then
      return true
    end
  end

  return false
end

function Bestiary.bestiaryTracker(trackerType, monsterVector)
  if trackerType ~= 0 then
    return
  end
  monsterTracked = monsterVector
end

function Bestiary.monsterSelectCharm(type, charm, monsterId)
  if not charm or not charm.id then return true end
  if type:lower() == 'select' then
    g_game.charmSelect(charm.id, monsterId)
  elseif type:lower() == 'remove' then
    g_game.charmRemove(charm.id)
  end
end

function Bestiary.onOptionChangeBestiaryMonster(list, value, force)
  if not VisibleCyclopediaPanel then
    return true
  end

  local data = list:getCurrentOption()
  local button = VisibleCyclopediaPanel:recursiveGetChildById('selectButton')
  if button then
    button:setEnabled(true)
    button.onClick = function()
      Bestiary.monsterSelectCharm(button:getText(), data.data, BESTIARY_MONSTER_ID)
      g_game.bestiaryMonsterData(BESTIARY_MONSTER_ID)
    end
  end
end

function Bestiary.updateBestiaryGroup(bestiaries)
  BestiaryGroups = {}
  for _, bestiary in ipairs(bestiaries or {}) do
    local normalized = normalizeBestiaryGroup(bestiary)
    if normalized then
      BestiaryGroups[#BestiaryGroups + 1] = normalized
    end
  end
  Bestiary.showBestiaryGroups(1)
end

function Bestiary.showBestiaryGroups()
  if not VisibleCyclopediaPanel or not VisibleCyclopediaPanel.listOfMonsters then
    return true
  end

  local totalPages = math.ceil(#BestiaryGroups / 15)
  -- check if has page count
  if VisibleCyclopediaPanel.pageCount then
    VisibleCyclopediaPanel.pageCount:setText(tr('%s / %s', overviewPage, totalPages))
  end
  VisibleCyclopediaPanel.listOfMonsters.itemsPanel:destroyChildren()
  VisibleCyclopediaPanel.backListButton.onClick = function() Bestiary.changeOverviewPage(-1) end
  VisibleCyclopediaPanel.nextListButton.onClick = function() Bestiary.changeOverviewPage(1) end
  VisibleCyclopediaPanel:recursiveGetChildById("backButton"):setEnabled(false)

  if math.min(overviewPage, totalPages) == 1 then
    VisibleCyclopediaPanel.backListButton:setEnabled(false)
  else
    VisibleCyclopediaPanel.backListButton:setEnabled(true)
  end

  if math.min(overviewPage, totalPages) == math.max(1, totalPages) then
    VisibleCyclopediaPanel.nextListButton:setEnabled(false)
  else
    VisibleCyclopediaPanel.nextListButton:setEnabled(true)
  end

  local groupCount = 0
  local beginList = (overviewPage - 1) * 15 + 1

  for i = 1, #BestiaryGroups do
    if groupCount == 15 then
			break
		end

		if i < beginList then
			goto continue
		end

    if not BestiaryGroups[i] or not BestiaryGroups[i].name then goto continue end
    local widget = g_ui.createWidget('CyclopediaWindow', VisibleCyclopediaPanel.listOfMonsters.itemsPanel)
    widget:setId(BestiaryGroups[i].name)
    widget:setText(short_text(BestiaryGroups[i].name, 14))
    widget.monster:setIcon('/images/game/cyclopedia/bestiary/'..BestiaryGroups[i].name)

    widget.monster.onClick = function()
      monsterListPage = 1
      g_game.bestiaryOverview(0, BestiaryGroups[i].name)
    end

    widget.totalKill:setText(string.format("Total: %d", BestiaryGroups[i].amount))
    widget.knownMonster:setText(string.format("Known: %d", BestiaryGroups[i].know))
    groupCount = groupCount + 1

    :: continue ::
  end

  VisibleCyclopediaPanel:recursiveGetChildById("searchBestiary"):focus()
end

function Bestiary.updateBestiaryOverview(name, monsterList, masteryCount)
  if name == nil then
    onOptionChange(cyclopediaOptionsPanel:recursiveGetChildById('2'))
    return
  end

  MonsterList = {}
  for _, monster in ipairs(monsterList or {}) do
    local normalized = normalizeBestiaryOverviewMonster(monster)
    if normalized then
      MonsterList[#MonsterList + 1] = normalized
    end
  end
  MasteryCount = masteryCount
  Bestiary.bestiaryOverview()
end

function Bestiary.bestiaryOverview()
  RegisterBackButton(Bestiary.bestiaryOverview, Bestiary)
  if VisibleCyclopediaPanel and VisibleCyclopediaPanel:getId() ~= 'bestiaryOverviewPanel' or not VisibleCyclopediaPanel then
    if VisibleCyclopediaPanel then
      VisibleCyclopediaPanel:destroy()
    end

    VisibleCyclopediaPanel = g_ui.createWidget('BestiaryOverviewPanel', cyclopediaWindow.optionsPanel)
    VisibleCyclopediaPanel:setId('bestiaryOverviewPanel')
  end

  if #MonsterList == 0 then
    Bestiary.showBestiaryGroups()
    return
  end

  VisibleCyclopediaPanel.backButton:setEnabled(true)
  VisibleCyclopediaPanel.backButton.onClick = function() Bestiary.showBestiaryGroups() end
  VisibleCyclopediaPanel.backListButton.onClick = function() Bestiary.changeMonsterPage(-1) end
  VisibleCyclopediaPanel.nextListButton.onClick = function() Bestiary.changeMonsterPage(1) end

  local totalPages = math.ceil(#MonsterList / 15)
  VisibleCyclopediaPanel.pageCount:setText(tr('%s / %s', monsterListPage, totalPages))
  VisibleCyclopediaPanel.listOfMonsters.itemsPanel:destroyChildren()

  if math.min(monsterListPage, totalPages) == 1 then
    VisibleCyclopediaPanel.backListButton:setEnabled(false)
  else
    VisibleCyclopediaPanel.backListButton:setEnabled(true)
  end

  if math.min(monsterListPage, totalPages) == math.max(1, totalPages) then
    VisibleCyclopediaPanel.nextListButton:setEnabled(false)
  else
    VisibleCyclopediaPanel.nextListButton:setEnabled(true)
  end

  local monsterCount = 0
  local beginList = (monsterListPage - 1) * 15 + 1

  for i = 1, #MonsterList do
    if monsterCount == 15 then
			break
		end

		if i < beginList then
			goto continue
		end

    local widget = g_ui.createWidget('CyclopediaCreatureWindow', VisibleCyclopediaPanel.listOfMonsters.itemsPanel)
    local monsterId = MonsterList[i][1]
    local currentLevel = tonumber(MonsterList[i][2]) or 0
    local unlockedLevel = math.max(currentLevel - 1, 0)
    local discovered = currentLevel > 0
    local extraExperience = tonumber(MonsterList[i][3]) or 0
    local monster = g_things.getMonsterList()[monsterId]
    if not monster then
      g_logger.error("Bestiary Overview: failed to retrieve data from monster " .. monsterId)
      goto continue
		end

    local name = discovered and string.capitalize(monster[1]) or "?"
    widget:setTooltip(name)
    widget:setText(short_text(name, 14))
    local monsterWidget = widget:recursiveGetChildById("monster")
    monsterWidget:setOutfit({type = monster[2], auxType = monster[3], head = monster[4], body = monster[5], legs = monster[6], feet = monster[7], addons = monster[8], shaders = discovered and "" or "outfit_black"})
    monsterWidget:setStaticWalking(true)
    monsterWidget:setTooltip(name)
    local monsterButton = widget:recursiveGetChildById("monsterButton")
    if discovered then
      monsterWidget.onClick = function() backMonster = name; g_game.bestiaryMonsterData(monsterId) end
      monsterButton.onClick = function() backMonster = name; g_game.bestiaryMonsterData(monsterId) end
      monsterButton:setEnabled(true)
    else
      monsterWidget.onClick = nil
      monsterButton.onClick = nil
      monsterButton:setEnabled(false)
    end
    widget.totalKill:setText(unlockedLevel .." / 3")
    if extraExperience > 0 then
      widget.soulCoreIcon:setVisible(true)
      widget.soulCoreIcon:setTooltip(tr('The Animus Mastery for this creature is unlocked.\nIt yields 2%%, plus an additional 0.1%% for every 10 Animus Masteries unlocked, up to a maximum of 4%%.\nYou currently benefit from %.1f%% due to having unlocked %d Animus Masteries.', extraExperience, MasteryCount))
    end

    if unlockedLevel >= 3 then
      widget:recursiveGetChildById("checked"):setVisible(true)
      widget:recursiveGetChildById("totalKill"):setVisible(false)
    else
      widget:recursiveGetChildById("checked"):setVisible(false)
    end

    monsterCount = monsterCount + 1

    :: continue ::
  end

end

function Bestiary.updateBestiaryMonsterData(monsterId, bestiaryMonster, currentLevel, killCounter, first, second, third, difficulty, ocorrence, extraExperience, masteryCount)
  RegisterBackButton(Bestiary.updateBestiaryMonsterData, monsterId, bestiaryMonster, currentLevel, killCounter, first, second, third, difficulty, ocorrence, extraExperience, masteryCount)

  if not VisibleCyclopediaPanel or VisibleCyclopediaPanel:getId() == 'charmDataPanel' then return end

  BESTIARY_MONSTER_ID = monsterId
  Cyclopedia.bestiaryMonsterData(monsterId, bestiaryMonster, currentLevel, killCounter, first, second, third, difficulty, ocorrence, extraExperience, masteryCount)
end

function Cyclopedia.bestiaryMonsterData(monsterId, bestiaryMonster, currentLevel, killCounter, first, second, third, difficulty, ocorrence, extraExperience, masteryCount)
  bestiaryMonster = normalizeBestiaryMonsterDetails(bestiaryMonster)
  currentLevel = tonumber(currentLevel) or 0
  killCounter = tonumber(killCounter) or 0
  first = math.max(tonumber(first) or bestiaryMonster.thirdDifficulty or 1, 1)
  second = math.max(tonumber(second) or bestiaryMonster.secondUnlock or first, first)
  third = math.max(tonumber(third) or bestiaryMonster.lastProgressKillCount or second, second)
  difficulty = tonumber(difficulty) or bestiaryMonster.difficulty or 0
  ocorrence = tonumber(ocorrence) or bestiaryMonster.ocorrence or 0
  extraExperience = tonumber(extraExperience) or bestiaryMonster.AnimusMasteryBonus or 0
  masteryCount = tonumber(masteryCount) or bestiaryMonster.AnimusMasteryPoints or 0
  MasteryCount = masteryCount

  if VisibleCyclopediaPanel then
    VisibleCyclopediaPanel:destroy()
    VisibleCyclopediaPanel = g_ui.createWidget('BestiaryMonsterPanel', cyclopediaWindow.optionsPanel)
    VisibleCyclopediaPanel:setId('bestiaryMonsterPanel')
  end

  VisibleCyclopediaPanel.backButton.onClick = function() Bestiary.bestiaryOverview() end

  local monster = g_things.getMonsterList()[monsterId]
  local widget = VisibleCyclopediaPanel.listOfMonsters

  widget:setText(monster[1])
  widget.monster:setOutfit({type = monster[2], auxType = monster[3], head = monster[4], body = monster[5], legs = monster[6], feet = monster[7], addons = monster[8]})
  widget.monster:setStaticWalking(true)

  widget.trackerKills:setChecked(false, true)

  for i, tracked in pairs(monsterTracked) do
    if tracked[1] == monsterId then
      widget.trackerKills:setChecked(true, true)
    end
  end

  if extraExperience > 0 then
    VisibleCyclopediaPanel:recursiveGetChildById("soulCoreIcon"):setVisible(true)
    VisibleCyclopediaPanel:recursiveGetChildById("soulCoreIcon"):setTooltip(tr('The Animus Mastery for this creature is unlocked.\nIt yields 2%%, plus an additional 0.1%% for every 10 Animus Masteries unlocked, up to a maximum of 4%%.\nYou currently benefit from %.1f%% due to having unlocked %d Animus Masteries.', extraExperience, MasteryCount))
  end


  local fullyUnlocked = killCounter >= third
  VisibleCyclopediaPanel:recursiveGetChildById("first"):setPercent(0)
  VisibleCyclopediaPanel:recursiveGetChildById("first"):setValue(killCounter, 0, first)

  VisibleCyclopediaPanel:recursiveGetChildById("second"):setPercent(0)
  VisibleCyclopediaPanel:recursiveGetChildById("third"):setPercent(0)

  if killCounter >= second then
    VisibleCyclopediaPanel:recursiveGetChildById("second"):setValue(killCounter, 0, second)
    VisibleCyclopediaPanel:recursiveGetChildById("third"):setValue(killCounter, 0, third)
  elseif killCounter >= first then
    VisibleCyclopediaPanel:recursiveGetChildById("second"):setValue(killCounter, 0, second)
  end


  if fullyUnlocked then
    VisibleCyclopediaPanel:recursiveGetChildById("first"):setImageSource('/images/game/cyclopedia/bestiary/progress-green')
    VisibleCyclopediaPanel:recursiveGetChildById("second"):setImageSource('/images/game/cyclopedia/bestiary/progress-green')
    VisibleCyclopediaPanel:recursiveGetChildById("third"):setImageSource('/images/game/cyclopedia/bestiary/progress-green')
  end

  VisibleCyclopediaPanel:recursiveGetChildById("first"):setTooltip(tr("%s / %s %s", comma_value(killCounter), comma_value(first), (fullyUnlocked and "(fully unlocked)" or "")))
  VisibleCyclopediaPanel:recursiveGetChildById("second"):setTooltip(tr("%s / %s %s", comma_value(killCounter), comma_value(second), (fullyUnlocked and "(fully unlocked)" or "")))
  VisibleCyclopediaPanel:recursiveGetChildById("third"):setTooltip(tr("%s / %s %s", comma_value(killCounter), comma_value(third), (fullyUnlocked and "(fully unlocked)" or "")))

  VisibleCyclopediaPanel:recursiveGetChildById("second"):setText(comma_value(killCounter))

  -- difficulty
  local difficultyText = {
    [0] = "Harmless",
    [1] = "Trivial",
    [2] = "Easy",
    [3] = "Medium",
    [4] = "Hard",
    [5] = "Challenging"
  }

  local dif = VisibleCyclopediaPanel:recursiveGetChildById('difficulty')
  for i = 1, 5 do
    local widdif = g_ui.createWidget('UIWidget', dif)
    widdif:setId(i)
    widdif:setHeight(10)
    widdif:setWidth(9)
    widdif:setImageSource('/images/game/cyclopedia/icons/icon-star-' .. (i <= difficulty and 'active' or 'inactive'))
    widdif:setTooltip("Difficulty: " .. difficultyText[difficulty])
  end

  -- ocorrence
  ocorrence = ocorrence + 1
  local ocorrenceText = {
    [1] = "Common",
    [2] = "Uncommon",
    [3] = "Rare",
    [4] = "Very Rare",
  }

  local ocor = VisibleCyclopediaPanel:recursiveGetChildById('ocorrency')
  for i = 1, 4 do
    local widdif = g_ui.createWidget('UIWidget', ocor)
    widdif:setId(i)
    widdif:setHeight(10)
    widdif:setWidth(9)
    widdif:setImageSource('/images/game/cyclopedia/icons/monster-icon-diamond-' .. (i <= ocorrence and 'active' or 'inactive'))
    widdif:setTooltip("Ocorrency: " .. ocorrenceText[ocorrence])
  end

  -- looting
  local lootPanel = VisibleCyclopediaPanel:recursiveGetChildById('lootPanel')
  -- dividir o loot
  local common = {}
  local uncommon = {}
  local semirare = {}
  local rare = {}
  local veryrare = {}

  -- Gating de revelacao por nivel de bestiary. O servidor revela TODOS os loots
  -- assim que killCounter >= 1, mas no Tibia os loots aparecem progressivamente
  -- conforme o currentLevel (1..4). Mascaramos aqui (item -> 0 = "?") os loots
  -- cuja raridade exige um nivel maior que o ja desbloqueado, sem mexer no
  -- servidor (regra OTC<-servidor): so escondemos a apresentacao.
  --   difficulty 0 (common)            -> revela com level >= 1
  --   difficulty 1-2 (uncommon/semi)   -> revela com level >= 2
  --   difficulty 3 (rare)              -> revela com level >= 3
  --   difficulty 4 (very rare)         -> revela com level >= 4
  local function requiredLevelForDifficulty(d)
    if d <= 0 then return 1
    elseif d <= 2 then return 2
    elseif d == 3 then return 3
    else return 4 end
  end

  for i, info in pairs(bestiaryMonster.loot) do
    -- Esconde (mostra como "?") o que ainda nao foi desbloqueado.
    if currentLevel < requiredLevelForDifficulty(info.difficulty) then
      info = { item = 0, difficulty = info.difficulty, name = info.name, stackable = info.stackable }
    end
    if info.difficulty == 0 then
      table.insert(common, info)
    elseif info.difficulty == 1 then
      table.insert(uncommon, info)
    elseif info.difficulty == 2 then
      table.insert(semirare, info)
    elseif info.difficulty == 3 then
      table.insert(rare, info)
    elseif info.difficulty == 4 then
      table.insert(veryrare, info)
    end
  end

  if #common > 0 then
    local commonPanel = g_ui.createWidget('LootPanelWidget', lootPanel)
    local max = 15
    if #common > 15 then
      commonPanel:setHeight(74)
      max = 30
    end
    commonPanel.lootType:setText(tr("Common:"))

    for i = 1, max do
      local item = g_ui.createWidget('BestiaryLootItem', commonPanel.lootItem)
      local it = common[i]
      if it then
        if it.item > 0 then
          item.image:setImageClip("0 34 34 34")
          item.item:setItemId(it.item)
          item.item:setVirtualCount(it.stackable and "1+" or "1")
          item.item:setTooltip(it.name)
          item.item.onClick = function() modules.game_cyclopedia.cyclopediaWindow:hide() modules.game_cyclopedia.CyclopediaItems.onRedirect(it.item) end
          item.item.onMouseRelease = function(widget, mousePos, mouseButton)
            if mouseButton == MouseRightButton then
              local menu = g_ui.createWidget('PopupMenu')
              menu:setGameMenu(true)
              local buttonText = modules.game_quickloot.inWhiteList(it.item) and 'Remove from Loot List' or 'Add to Loot List'
              menu:addOption(tr(buttonText), function() Bestiary.itemToList(it.item) end)
              menu:display(mousePos)
            end
          end
        else
          item.image:setImageSource("/images/ui/unkown-button")
        end
      end
    end
  end

  if #uncommon > 0 then
    local uncommonPanel = g_ui.createWidget('LootPanelWidget', lootPanel)
    local max = 15
    if #uncommon > 15 then
      uncommonPanel:setHeight(74)
      max = 30
    end
    uncommonPanel.lootType:setText(tr("Uncommon:"))

    for i = 1, max do
      local item = g_ui.createWidget('BestiaryLootItem', uncommonPanel.lootItem)
      local it = uncommon[i]
      if it then
        if it.item > 0 then
          item.image:setImageClip("0 34 34 34")
          item.item:setItemId(it.item)
          item.item:setVirtualCount(it.stackable and "1+" or "1")
          item.item:setTooltip(it.name)
          item.item.onClick = function() modules.game_cyclopedia.cyclopediaWindow:hide() modules.game_cyclopedia.CyclopediaItems.onRedirect(it.item) end
          item.item.onMouseRelease = function(widget, mousePos, mouseButton)
            if widget:containsPoint(mousePos) and mouseButton == MouseRightButton then
              local menu = g_ui.createWidget('PopupMenu')
              menu:setGameMenu(true)
              local buttonText = modules.game_quickloot.inWhiteList(it.item) and 'Remove from Loot List' or 'Add to Loot List'
              menu:addOption(tr(buttonText), function() Bestiary.itemToList(it.item) end)
              menu:display(mousePos)
            end
          end
        else
          item.image:setImageSource("/images/ui/unkown-button")
        end
      end
    end
  end

  if #semirare > 0 then
    local semirarePanel = g_ui.createWidget('LootPanelWidget', lootPanel)
    local max = 15
    if #semirare > 15 then
      semirarePanel:setHeight(74)
      max = 30
    end
    semirarePanel.lootType:setText(tr("Semi-Rare:"))

    for i = 1, max do
      local item = g_ui.createWidget('BestiaryLootItem', semirarePanel.lootItem)
      local it = semirare[i]
      if it then
        if it.item > 0 then
          item.image:setImageClip("0 34 34 34")
          item.item:setItemId(it.item)
          item.item:setVirtualCount(it.stackable and "1+" or "1")
          item.item:setTooltip(it.name)
          item.item.onClick = function() modules.game_cyclopedia.cyclopediaWindow:hide() modules.game_cyclopedia.CyclopediaItems.onRedirect(it.item) end
          item.item.onMouseRelease = function(widget, mousePos, mouseButton)
            if widget:containsPoint(mousePos) and mouseButton == MouseRightButton then
              local menu = g_ui.createWidget('PopupMenu')
              menu:setGameMenu(true)
              local buttonText = modules.game_quickloot.inWhiteList(it.item) and 'Remove from Loot List' or 'Add to Loot List'
              menu:addOption(tr(buttonText), function() Bestiary.itemToList(it.item) end)
              menu:display(mousePos)
            end
          end
        else
          item.image:setImageSource("/images/ui/unkown-button")
        end
      end
    end
  end

  if #rare > 0 then
    local rarePanel = g_ui.createWidget('LootPanelWidget', lootPanel)
    local max = 15
    if #rare > 15 then
      rarePanel:setHeight(74)
      max = 30
    end
    rarePanel.lootType:setText(tr("Rare:"))

    for i = 1, max do
      local item = g_ui.createWidget('BestiaryLootItem', rarePanel.lootItem)
      local it = rare[i]
      if it then
        if it.item > 0 then
          item.image:setImageClip("0 34 34 34")
          item.item:setItemId(it.item)
          item.item:setVirtualCount(it.stackable and "1+" or "1")
          item.item:setTooltip(it.name)
          item.item.onClick = function() modules.game_cyclopedia.cyclopediaWindow:hide() modules.game_cyclopedia.CyclopediaItems.onRedirect(it.item) end
          item.item.onMouseRelease = function(widget, mousePos, mouseButton)
            if widget:containsPoint(mousePos) and mouseButton == MouseRightButton then
              local menu = g_ui.createWidget('PopupMenu')
              menu:setGameMenu(true)
              local buttonText = modules.game_quickloot.inWhiteList(it.item) and 'Remove from Loot List' or 'Add to Loot List'
              menu:addOption(tr(buttonText), function() Bestiary.itemToList(it.item) end)
              menu:display(mousePos)
            end
          end
        else
          item.image:setImageSource("/images/ui/unkown-button")
        end
      end
    end
  end

  if #veryrare > 0 then
    local veryrarePanel = g_ui.createWidget('LootPanelWidget', lootPanel)
    local max = 15
    if #veryrare > 15 then
      veryrarePanel:setHeight(74)
      max = 30
    end
    veryrarePanel.lootType:setText(tr("Very Rare:"))

    for i = 1, max do
      local item = g_ui.createWidget('BestiaryLootItem', veryrarePanel.lootItem)
      local it = veryrare[i]
      if it then
        if it.item > 0 then
          item.image:setImageClip("0 34 34 34")
          item.item:setItemId(it.item)
          item.item:setVirtualCount(it.stackable and "1+" or "1")
          item.item:setTooltip(it.name)
          item.item.onClick = function() modules.game_cyclopedia.cyclopediaWindow:hide() modules.game_cyclopedia.CyclopediaItems.onRedirect(it.item) end
          item.item.onMouseRelease = function(widget, mousePos, mouseButton)
            if widget:containsPoint(mousePos) and mouseButton == MouseRightButton then
              local menu = g_ui.createWidget('PopupMenu')
              menu:setGameMenu(true)
              local buttonText = modules.game_quickloot.inWhiteList(it.item) and 'Remove from Loot List' or 'Add to Loot List'
              menu:addOption(tr(buttonText), function() Bestiary.itemToList(it.item) end)
              menu:display(mousePos)
            end
          end
        else
          item.image:setImageSource("/images/ui/unkown-button")
        end
      end
    end
  end

  if currentLevel > 1 then
    local attackImages = {
      [0] = "/images/game/cyclopedia/icons/monster-icon-melee",
      [1] = "/images/game/cyclopedia/icons/monster-icon-ranged",
      [2] = "/images/game/cyclopedia/icons/monster-icon-noattack"
    }

    VisibleCyclopediaPanel:recursiveGetChildById('charmPoints'):setText(bestiaryMonster.difficultyCharm)
    VisibleCyclopediaPanel:recursiveGetChildById('attackRange'):setImageSource(attackImages[bestiaryMonster.attackMode])
    VisibleCyclopediaPanel:recursiveGetChildById('attackRange'):setText('')
    VisibleCyclopediaPanel:recursiveGetChildById('attackRange'):setHeight(9)
    VisibleCyclopediaPanel:recursiveGetChildById('attackRange'):setWidth(9)
    VisibleCyclopediaPanel:recursiveGetChildById('castSpell'):setVisible(true)
    VisibleCyclopediaPanel:recursiveGetChildById('health'):setText(comma_value(bestiaryMonster.health))
    VisibleCyclopediaPanel:recursiveGetChildById('experience'):setText(comma_value(bestiaryMonster.experience))
    VisibleCyclopediaPanel:recursiveGetChildById('speed'):setText(comma_value(bestiaryMonster.speed))
    VisibleCyclopediaPanel:recursiveGetChildById('armor'):setText(bestiaryMonster.armor)

    local mitigation = string.format("%.2f", bestiaryMonster.mitigation)
    VisibleCyclopediaPanel:recursiveGetChildById('mitigation'):setText(mitigation .. "%")
  end

  local elementNameByActionId = {
    [1] = {name = "physical", id = 0},
    [2] = {name = "earth", id = 2},
    [3] = {name = "fire", id = 1},
    [4] = {name = "death", id = 6},
    [5] = {name = "energy", id = 3},
    [6] = {name = "holy", id = 5},
    [7] = {name = "ice", id = 4},
    [8] = {name = "healing", id = 7}
  }

  local elementNameById = {}
  for _, elementInfo in ipairs(elementNameByActionId) do
    elementNameById[elementInfo.id] = elementInfo
  end

  local elementsWidgets = {}
  for k, v in ipairs(elementNameByActionId) do
      local widgetElement = g_ui.createWidget('ElementPanel', VisibleCyclopediaPanel:recursiveGetChildById("elements"))
      widgetElement.progress:setValue(0, 0, 150)
      widgetElement.progress:setBackgroundColor('white')
      widgetElement:setId(v.id)
      widgetElement:setActionId(k)
      widgetElement.icon:setImageSource('/images/game/cyclopedia/icons/monster-icon-'.. v.name ..'-resist')
      widgetElement.icon:setTooltip(string.capitalize(v.name))
  end

  for i, v in ipairs(bestiaryMonster.elements) do
    local list = VisibleCyclopediaPanel:recursiveGetChildById("elements")
    local widgetElement = list and list:getChildById(v.element)
    if widgetElement then
      widgetElement.index = i
      widgetElement.progress:setValue(0, 0, 150)
      widgetElement.progress:setBackgroundColor('white')
      elementsWidgets[#elementsWidgets + 1] = widgetElement
    end
  end

  if currentLevel > 2 then
    for i = 1, #elementsWidgets do
      local widgetElement = elementsWidgets[i]
      local element = bestiaryMonster.elements
      local index = widgetElement.index

      local elementEntry = element[index]
      if elementEntry then
        local id = tonumber(elementEntry.element) or -1
        local percent = tonumber(elementEntry.percent) or 0
        local actionId = tonumber(widgetElement:getActionId()) or -1
        local elementInfo = elementNameById[id] or elementNameByActionId[actionId]
        local elementLabel = elementInfo and elementInfo.name or "unknown"

        widgetElement.progress:setValue(percent, 0, 150)
        widgetElement.progress:setTooltip(tr('Sensitive to %s: %d%% (neutral)', elementLabel, percent))
        if percent < 50 then
          widgetElement.progress:setBackgroundColor('red')
          widgetElement.progress:setTooltip(tr('Sensitive to %s: %d%% (strong)', elementLabel, percent))
        elseif percent < 100 then
          widgetElement.progress:setBackgroundColor('#e4c00a')
          widgetElement.progress:setTooltip(tr('Sensitive to %s: %d%% (strong)', elementLabel, percent))
        elseif percent > 100 then
          widgetElement.progress:setBackgroundColor('#18ce18')
          widgetElement.progress:setTooltip(tr('Sensitive to %s: %d%% (weak)', elementLabel, percent))
        end
      end
    end


    function removeSpacesAfterNewLine(text)
      local result = text:gsub("\n%s+", "\n")
        result = result:gsub("\n%s", "\n")
        return result
    end

    -- location
    if bestiaryMonster.location ~= "" then
      VisibleCyclopediaPanel:recursiveGetChildById("locations"):setText(removeSpacesAfterNewLine(bestiaryMonster.location))
    end
  end

  local panelImage = VisibleCyclopediaPanel:recursiveGetChildById('charmImage')
  panelImage:setImageSource('')

  VisibleCyclopediaPanel:recursiveGetChildById('coinCost'):setText("?")
  BestiaryMonster = bestiaryMonster
  MonsterId = monsterId

  local panel = VisibleCyclopediaPanel:recursiveGetChildById('charm0')
  local major = Charm:getMajorCharm(MonsterId)
  if not major.id or major.id == -1 then
    panel:recursiveGetChildById("charmImage"):setImageSource('')
  else
    panel:recursiveGetChildById("charmImage"):setImageSource('/images/game/cyclopedia/monster-bonus-effects/monster-bonus-effects-'.. major.id)
  end

  local panel = VisibleCyclopediaPanel:recursiveGetChildById('charm1')
  local minor = Charm:getMinorCharm(MonsterId)
  if not minor.id or minor.id == -1 then
    panel:recursiveGetChildById("charmImage"):setImageSource('')
  else
    panel:recursiveGetChildById("charmImage"):setImageSource('/images/game/cyclopedia/monster-bonus-effects/monster-bonus-effects-'.. minor.id)
  end

  local selectAssignButton = VisibleCyclopediaPanel:recursiveGetChildById('selectAssignButton')
  selectAssignButton:setVisible(true)
  selectAssignButton:setEnabled(false)

  local selectClearButton = VisibleCyclopediaPanel:recursiveGetChildById('selectClearButton')
  selectClearButton:setVisible(false)
  selectClearButton:setEnabled(false)

  CurrentLevel = currentLevel
  if currentLevel > 3 then
    Bestiary.onCharm()
  end
end

------
function Bestiary.changeOverviewPage(index)
  overviewPage = index > 0 and overviewPage + 1 or overviewPage - 1
  Bestiary.showBestiaryGroups()
end

function Bestiary.changeMonsterPage(index)
  monsterListPage = index > 0 and monsterListPage + 1 or monsterListPage - 1
  Bestiary.bestiaryOverview()
end

function Bestiary.itemToList(itemId)
  if not modules.game_quickloot.inWhiteList(itemId) then
		modules.game_quickloot.addToQuickLoot(itemId)
	else
		modules.game_quickloot.removeItemInList(itemId)
	end
end

function Bestiary.onTrackMonster(isChecked, monsterId)
  if not monsterId then
    monsterId = BESTIARY_MONSTER_ID
  end

  g_game.sendMonsterTracker(monsterId, isChecked)
end

function Bestiary.onSearchChange(widget)
  if string.empty(widget:getText()) then
    VisibleCyclopediaPanel:getChildById('searchButton'):setEnabled(false)
  else
    VisibleCyclopediaPanel:getChildById('searchButton'):setEnabled(true)
  end
end

function Bestiary.onSearch()
  if not VisibleCyclopediaPanel then
    return
  end

  local widget = VisibleCyclopediaPanel:getChildById('searchBestiary')
  if not widget then
    return
  end

  local text = widget:getText():lower()

  local list = {}
  for raceId, monsterInfo in pairs(g_things.getMonsterList()) do
    local name = monsterInfo[1]:lower()
    if string.find(name, string.escape(text)) then
      list[#list + 1] = raceId
    end
  end

  widget:clearText()
  monsterListPage = 1
  g_game.bestiarySearch(list)
end

function Bestiary.setupBackTrackerButton()
  if VisibleCyclopediaPanel then
    VisibleCyclopediaPanel:recursiveGetChildById("backButton"):setEnabled(true)
    VisibleCyclopediaPanel:recursiveGetChildById("backButton").onClick = function() modules.game_cyclopedia.onOptionChange(modules.game_cyclopedia.cyclopediaOptionsPanel:recursiveGetChildById('2')) end
  end
end

function Bestiary.onApplyCharm(monster, charm, monsterId)
  if messageBoxCharm then
    return
  end

  local okFunc = function()
    g_game.charmSelect(charm.id, monsterId)
    g_game.bestiaryMonsterData(monsterId)
    messageBoxCharm:destroy()
    cyclopediaWindow:show(true)
    g_client.setInputLockWidget(nil)
    messageBoxCharm = nil
  end

  local cancelFunc = function()
    cyclopediaWindow:show(true)
    messageBoxCharm:destroy()
    g_client.setInputLockWidget(nil)
    messageBoxCharm = nil
  end

  cyclopediaWindow:hide()
  g_client.setInputLockWidget(nil)
	messageBoxCharm = displayGeneralBox("Confirm Selected Charm", tr("Do you want to use the Charm %s for this creature?", charm.name),
    { { text=tr('Yes'), callback=okFunc },
    { text=tr('No'), callback=cancelFunc }
  }, okFunc, cancelFunc)

  g_client.setInputLockWidget(messageBoxCharm)
  messageBoxCharm.onEscape = cancelFunc
end

function Bestiary.onRemoveCharm(monster, charm, mosnterId)
  if messageBoxCharm then
    return
  end

  local okFunc = function()
    g_game.charmRemove(charm.id)
    g_game.bestiaryMonsterData(mosnterId)
    messageBoxCharm:destroy()
    cyclopediaWindow:show(true)
    g_client.setInputLockWidget(nil)
    messageBoxCharm = nil
  end

  local cancelFunc = function()
    cyclopediaWindow:show(true)
    messageBoxCharm:destroy()
    g_client.setInputLockWidget(nil)
    messageBoxCharm = nil
  end

  cyclopediaWindow:hide()
  g_client.setInputLockWidget(nil)
  messageBoxCharm = displayGeneralBox("Confirm Charm Removal", tr("Do you want to remove the Charm %s from this creature? This will cost you %s gold pieces.", charm.name, comma_value(charm.removePrice)),
    { { text=tr('Yes'), callback=okFunc },
    { text=tr('No'), callback=cancelFunc }
  }, okFunc, cancelFunc)

  g_client.setInputLockWidget(messageBoxCharm)
  messageBoxCharm.onEscape = cancelFunc
end

function Bestiary.onFocusChangeBestiaryMonster(widget, focus)
  if widget:isFocused() then
    if widget:getId() == "charm0" then
      selectedCharm = 0
    else
      selectedCharm = 1
    end

    Bestiary.onCharm()
  end
end

function Bestiary.onCharm()
  if CurrentLevel <= 3 then
    return
  end

  local charmOptions = VisibleCyclopediaPanel:recursiveGetChildById('charmOptions')

  local currentCharm = {id = -1}
  if selectedCharm == 0 then
    charmList = Charm:getEmptyMajorSlots()
    currentCharm = Charm:getMajorCharm(MonsterId)
  else
    charmList = Charm:getEmptyMinorSlots()
    currentCharm = Charm:getMinorCharm(MonsterId)
  end

  local coinCostPanel = VisibleCyclopediaPanel:recursiveGetChildById('coinCostPanel')
  coinCostPanel:setVisible(false)

  if #charmList == 0 and currentCharm.id == -1 then
    charmOptions:removeOption('?')
    charmOptions:clear()
    charmOptions:addOption('None Unlocked')
    charmOptions:setCurrentIndex(1)
    charmOptions:setEnabled(false)
  elseif currentCharm.id == -1 then
    charmListUnlocked = {}
    charmOptions:removeOption('?')
    charmOptions:clear()
    for i, charm in pairs(charmList) do
      if charm.creatureId == 0 then
        table.insert(charmListUnlocked, charm)
        charmOptions:addOption(charm.name, charm)
      end
    end

    if #charmListUnlocked == 0 then
      charmOptions:clear()
      charmOptions:addOption('None Unlocked')
      charmOptions:setEnabled(false)
    else
      -- charmOptions:setCurrentIndex(1)
      charmOptions:setEnabled(true)

      local selectAssignButton = VisibleCyclopediaPanel:recursiveGetChildById('selectAssignButton')
      selectAssignButton:setVisible(true)
      selectAssignButton:setEnabled(true)

      local selectClearButton = VisibleCyclopediaPanel:recursiveGetChildById('selectClearButton')
      selectClearButton:setVisible(false)
      selectClearButton:setEnabled(false)

      local data = charmOptions:getCurrentOption()

      local monster = g_things.getMonsterList()[MonsterId]
      selectAssignButton.onClick = function()
        local data = charmOptions:getCurrentOption()
        Bestiary.onApplyCharm(monster[1], data.data, MonsterId)
      end
    end
  elseif currentCharm.id > -1 then
    charmListUnlocked = {}
    charmOptions:removeOption('?')
    for i, charm in pairs(charmList) do
      if charm.creatureId == MonsterId then
        table.insert(charmListUnlocked, charm)
        charmOptions:addOption(charm.name, charm)
      end
    end

    charmOptions:setCurrentIndex(1)
    charmOptions:setEnabled(false)
    local data = charmOptions:getCurrentOption()
    if data then
      local panel = VisibleCyclopediaPanel:recursiveGetChildById('charm0')
      if selectedCharm == 1 then
        panel = VisibleCyclopediaPanel:recursiveGetChildById('charm1')
      end
      panel:recursiveGetChildById("charmImage"):setImageSource('/images/game/cyclopedia/monster-bonus-effects/monster-bonus-effects-'.. currentCharm.id)
    end

    local selectAssignButton = VisibleCyclopediaPanel:recursiveGetChildById('selectAssignButton')
    selectAssignButton:setVisible(false)
    selectAssignButton:setEnabled(false)

    local selectClearButton = VisibleCyclopediaPanel:recursiveGetChildById('selectClearButton')
    selectClearButton:setVisible(true)
    selectClearButton:setEnabled(true)

    local coinCostPanel = VisibleCyclopediaPanel:recursiveGetChildById('coinCostPanel')
    coinCostPanel:setVisible(true)

    local monster = g_things.getMonsterList()[MonsterId]
    selectClearButton.onClick = function()
      Bestiary.onRemoveCharm(monster[1], currentCharm, MonsterId)
    end
    coinCostPanel:getChildById('coinCost'):setText(comma_value(Charm:getCharmCost(currentCharm.id)))
  end
end
