local selectedContainerId = nil
local selectedContainerIdObtain = false
local mouseGrabberWidget = nil
local chooseCursorActive = false

quickLootWindow = nil
confirmWindow = nil
quickLootContainersPanel = nil
itemList = nil
quickLootCheckBox = nil
clearLootButton = nil
addToButton = nil
scrollBar = nil

quickLootFilter = nil
skippedLoot = nil
acceptedLoot = nil

allContainers = {}
obtainContainers = {}
lootData = {}

local cache = {
  listMin = 0,
  listMax = 0,
  listFit = 0,
  widgetSize = 16,
  listPool = 14,
  listData = {},
  offset = 0,
  scrollDelay = 0
}

function saveData()
  if not LoadedPlayer:isLoaded() then return end
  normalizeLootFilterData()

  local file = "/characterdata/" .. LoadedPlayer:getId() .. "/lootBlackWhitelist.json"
  local status, result = pcall(function() return json.encode(lootData, 2) end)
  if not status then
      return g_logger.error("Error while saving profile lootData. Data won't be saved. Details: " .. result)
  end

  if result:len() > 100 * 1024 * 1024 then
      return g_logger.error("Something went wrong, file is above 100MB, won't be saved")
  end
  g_resources.writeFileContents(file, result)
end

function loadData()
  if not LoadedPlayer:isLoaded() then return end

  local file = "/characterdata/" .. LoadedPlayer:getId() .. "/lootBlackWhitelist.json"
  if g_resources.fileExists(file) then
    local status, result = pcall(function()
        return json.decode(g_resources.readFileContents(file))
    end)
    if not status then
        return g_logger.error("Error while reading profiles file. To fix this problem you can delete storage.json. Details: " .. result)
    end
    lootData = result
  else
    -- base
    lootData["blacklistTypes"] = {}
    lootData["listType"] = "blacklist"
    lootData["whitelistTypes"] = {}
  end

  if not lootData["blacklistTypes"] then
    lootData["blacklistTypes"] = {}
  end
  if not lootData["listType"] then
    lootData["listType"] = "blacklist"
  end
  if not lootData["whitelistTypes"] then
    lootData["whitelistTypes"] = {}
  end
  normalizeLootFilterData()
end

local function normalizeLootContainers(containers)
  local normalizedContainers = {}
  local normalizedObtainContainers = {}

  for _, entry in pairs(containers or {}) do
    if type(entry) == "table" then
      local category = entry.category or entry[1]
      if category then
        normalizedContainers[category] = entry.lootContainerId or entry.containerId or entry[2] or 0
        normalizedObtainContainers[category] = entry.obtainContainerId or entry.obtainerContainerId or entry[3] or 0
      end
    end
  end

  return normalizedContainers, normalizedObtainContainers
end

local refreshList

local function finishChooseItem()
  selectedContainerId = nil
  selectedContainerIdObtain = false

  if mouseGrabberWidget then
    mouseGrabberWidget:ungrabMouse()
    if chooseCursorActive then
      g_mouse.updateGrabber(mouseGrabberWidget, 'target')
    end
  end

  if chooseCursorActive then
    g_mouse.popCursor('target')
    chooseCursorActive = false
  end
end

function normalizeLootFilterData()
  lootData["blacklistTypes"] = lootData["blacklistTypes"] or {}
  lootData["whitelistTypes"] = lootData["whitelistTypes"] or {}
  for _, key in ipairs({"blacklistTypes", "whitelistTypes"}) do
    local normalized = {}
    for _, itemId in pairs(lootData[key] or {}) do
      itemId = tonumber(itemId)
      if itemId and not table.contains(normalized, itemId) then
        table.insert(normalized, itemId)
      end
    end
    lootData[key] = normalized
  end
end

local function sendManagedContainerAction(action, category, item)
  -- [debug log desativado] g_logger.info(string.format("[QuickLoot] managed action=%d category=%d item=%d", action, category or 0, item and item:getId() or 0))
  if item then
    g_game.openContainerQuickLoot(action, category, item:getPosition(), item:getId(), item:getStackPos(), false)
  elseif action == 1 then
    g_game.clearLootContainer(category)
  elseif action == 2 then
    g_game.openLootContainer(category)
  elseif action == 5 then
    g_game.clearObtainContainer(category)
  elseif action == 6 then
    g_game.openObtainContainer(category)
  elseif action == 3 then
    g_game.setQuickLootFallback(false)
  end
end

local function clearManagedContainer(category, obtainContainer)
  if obtainContainer then
    sendManagedContainerAction(5, category)
    obtainContainers[category] = 0
  else
    sendManagedContainerAction(1, category)
    allContainers[category] = 0
  end
  refreshList()
end

local function openManagedContainer(category, obtainContainer)
  local containerId = obtainContainer and (obtainContainers[category] or 0) or (allContainers[category] or 0)
  if containerId == 0 then
    return
  end

  if obtainContainer then
    sendManagedContainerAction(6, category)
  else
    sendManagedContainerAction(2, category)
  end
end

local function bindClick(widget, callback)
  if not widget then
    return
  end

  widget.onClick = callback
  widget.onMouseRelease = function(_, _, button)
    if button == MouseLeftButton then
      callback()
      return true
    end
    return false
  end
end

local function bindManagedContainerBox(widget, category)
  bindClick(widget:getChildById('buttonSelect'), function()
    startChooseItem(category, false)
  end)
  bindClick(widget:getChildById('buttonClear'), function()
    clearManagedContainer(category, false)
  end)
  bindClick(widget:getChildById('containerId'), function()
    openManagedContainer(category, false)
  end)

  bindClick(widget:getChildById('obtainButtonSelect'), function()
    startChooseItem(category, true)
  end)
  bindClick(widget:getChildById('obtainButtonClear'), function()
    clearManagedContainer(category, true)
  end)
  bindClick(widget:getChildById('obtainContainerId'), function()
    openManagedContainer(category, true)
  end)
end

function init()
  quickLootWindow = g_ui.displayUI('quickloot')
  quickLootWindow:hide()

  mouseGrabberWidget = g_ui.createWidget('UIWidget')
  mouseGrabberWidget:setVisible(true)
  mouseGrabberWidget:setFocusable(false)
  mouseGrabberWidget.onMouseRelease = onChooseItemMouseRelease

  skippedLoot    = quickLootWindow:getChildById('quickLootButtonsPanel'):getChildById('blacklist')
  acceptedLoot   = quickLootWindow:getChildById('quickLootButtonsPanel'):getChildById('whitelist')
  clearLootButton   = quickLootWindow:getChildById('quickLootButtonsPanel'):getChildById('clearLootButton')
  addToButton   = quickLootWindow:getChildById('quickLootButtonsPanel'):getChildById('addToButton')
  scrollBar = quickLootWindow:recursiveGetChildById('itemsScroll')

  quickLootFilter = UIRadioGroup.create()
  quickLootFilter:addWidget(skippedLoot)
  quickLootFilter:addWidget(acceptedLoot)

  quickLootContainersPanel = quickLootWindow:getChildById('quickLootContainers'):getChildById('quickLootContainersPanel')
  itemList = quickLootWindow:recursiveGetChildById('itemList')
  quickLootCheckBox = quickLootWindow:getChildById('quickLootFallback'):getChildById('quickLootFallbackToMainContainer')
  quickLootCheckBox.onCheckChange = function(self, checked)
    g_game.setQuickLootFallback(checked)
  end
  bindClick(quickLootWindow:getChildById('quickLootFallback'), function()
    quickLootCheckBox:setChecked(not quickLootCheckBox:isChecked())
  end)

  local count = 0
  for _, i in pairs(ObjectCategoryOrder) do
    if getObjectCategoryName(i) ~= '' then
      count = count + 1
      local widget = g_ui.createWidget('QuicklootContainerBox', quickLootContainersPanel)
      local color = (count % 2) == 0 and '#414141' or '#484848'

      widget:setId(i)
      widget:setBackgroundColor(color)
      widget:getChildById('containerType'):setText(getObjectCategoryName(i))
      bindManagedContainerBox(widget, i)

      local lootContainerId = allContainers[i] or 0
      local obtainContainerId = obtainContainers[i] or 0
      local containerSlot = widget:getChildById('containerId')
      local obtainSlot = widget:getChildById('obtainContainerId')
      -- Rarity frames make these category slots noisy: every backpack here
      -- looks "epic" / "legendary" just because of its price. Flag the slots
      -- before assigning the item so ItemsDatabase.setRarityItem skips the
      -- frame draw (gamelib/items.lua _skipRarityFrame branch).
      if containerSlot then containerSlot._skipRarityFrame = true end
      if obtainSlot then obtainSlot._skipRarityFrame = true end
      if containerSlot then containerSlot:setItem(lootContainerId > 0 and Item.create(lootContainerId, 1) or nil) end
      if obtainSlot then obtainSlot:setItem(obtainContainerId > 0 and Item.create(obtainContainerId, 1) or nil) end
    end
  end

  connect(g_game, { onGameEnd = finish })
  connect(g_game, { onGameStart = start })
  connect(g_game, { onQuickLootContainers = onQuickLootContainers })

  connect(quickLootFilter, { onSelectionChange = onSelectionChange })
end

function terminate()
  finishChooseItem()
  quickLootCheckBox = nil
  quickLootContainersPanel = nil
  clearLootButton = nil
  addToButton = nil
  lootData = {}

  if mouseGrabberWidget then
    mouseGrabberWidget:destroy()
    mouseGrabberWidget = nil
  end

  if quickLootWindow then
    quickLootWindow:destroy()
    quickLootWindow = nil
  end

  disconnect(g_game, { onGameEnd = finish })
  disconnect(g_game, { onGameStart = start })
  disconnect(g_game, { onQuickLootContainers = onQuickLootContainers })
  disconnect(quickLootFilter, { onSelectionChange = onSelectionChange })
end

refreshList = function()

  for i = ObjectCategory.OBJECTCATEGORY_LAST, ObjectCategory.OBJECTCATEGORY_FIRST, -1 do
    if getObjectCategoryName(i) ~= '' then
      local widget = quickLootContainersPanel:getChildById(i)
      if widget then
        local lootContainerId = allContainers[i] or 0
        local obtainContainerId = obtainContainers[i] or 0
        local containerSlot = widget:getChildById('containerId')
        local obtainSlot = widget:getChildById('obtainContainerId')
        if containerSlot then containerSlot._skipRarityFrame = true end
        if obtainSlot then obtainSlot._skipRarityFrame = true end
        if containerSlot then containerSlot:setItem(lootContainerId > 0 and Item.create(lootContainerId, 1) or nil) end
        if obtainSlot then obtainSlot:setItem(obtainContainerId > 0 and Item.create(obtainContainerId, 1) or nil) end
      end
    end
  end
end

function showQuickLoot()
  quickLootWindow.searchText:clearText()
  scrollBar:setValue(0)
  quickLootWindow:show(true)
  quickLootWindow:focus()
  g_client.setInputLockWidget(quickLootWindow)
end

function hideQuickLoot()
  finishChooseItem()
  g_client.setInputLockWidget(nil)
  quickLootWindow:hide()
end

function onChooseItemMouseRelease(self, mousePosition, mouseButton)
  local item = nil
  if mouseButton == MouseLeftButton then
    local clickedWidget = m_interface.getRootPanel():recursiveGetChildByPos(mousePosition, false)
    if clickedWidget then
      if clickedWidget:getClassName() == 'UIGameMap' then
        local tile = clickedWidget:getTile(mousePosition)
        if tile then
          local thing = tile:getTopMoveThing()
          if thing and thing:isItem() then
            item = thing
          end
        end
      elseif clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
        item = clickedWidget:getItem()
      end
    end
  end

  if item and item:getId() > 0 then
    sendManagedContainerAction((selectedContainerIdObtain and 4 or 0), selectedContainerId, item)
    if selectedContainerIdObtain then
      obtainContainers[selectedContainerId] = item:getId()
    else
      allContainers[selectedContainerId] = item:getId()
    end
    refreshList()
  else
    modules.game_textmessage.displayFailureMessage(tr('Sorry, not possible.'))
  end

  finishChooseItem()
  showQuickLoot()
  return true
end

function startChooseItem(id, obtain)
  finishChooseItem()
  hideQuickLoot()
  selectedContainerId = id
  selectedContainerIdObtain = obtain

  g_mouse.updateGrabber(mouseGrabberWidget, 'target')
  mouseGrabberWidget:grabMouse()
  g_mouse.pushCursor('target')
  chooseCursorActive = true
end

function start()
  local benchmark = g_clock.millis()
  loadData()
  normalizeLootFilterData()
  local lootType = lootData["listType"]
  if g_game.isOnline() then
    local lootTable = (lootType == "whitelist" and lootData["whitelistTypes"] or lootData["blacklistTypes"])
    normalizeLootFilterData()
    g_game.doThing(false)
    g_game.updateLootWhiteList(lootType == "whitelist", lootData[lootType == "whitelist" and "whitelistTypes" or "blacklistTypes"] or lootTable or {})
    g_game.doThing(true)
  end

  updateLootItems()
  if lootType == "whitelist" then
	  quickLootFilter:selectWidget(acceptedLoot)
    clearLootButton:setImageSource("/images/game/quickloot/clear-accepted-button")
    addToButton:setImageSource("/images/game/quickloot/add-accepted-button")
  else
	  quickLootFilter:selectWidget(skippedLoot)
    clearLootButton:setImageSource("/images/game/quickloot/clear-button")
    addToButton:setImageSource("/images/game/quickloot/add-button")
  end
  consoleln("Quick Loot loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function reloadLootWhiteList()
  normalizeLootFilterData()
  local lootType = lootData["listType"]
  local lootTable = (lootType == "whitelist" and lootData["whitelistTypes"] or lootData["blacklistTypes"])
  g_game.doThing(false)
  g_game.updateLootWhiteList(lootType == "whitelist", lootTable or {})
  g_game.doThing(true)
end

function finish()
  hideQuickLoot()
  saveData()
  if confirmWindow then
    confirmWindow:destroy()
    confirmWindow = nil
  end
end

function onQuickLootContainers(quickLootFallbackToMainContainer, containers)
  -- [debug log desativado] g_logger.info(string.format("[QuickLoot] containers fallback=%s entries=%d", tostring(quickLootFallbackToMainContainer), #(containers or {})))
  local checked = quickLootFallbackToMainContainer == 1 or quickLootFallbackToMainContainer == true
  quickLootCheckBox:setChecked(checked, true)

  allContainers, obtainContainers = normalizeLootContainers(containers)

  updateLootItems()
  refreshList()
end

function addToQuickLoot(clientId)
  if type(clientId) ~= "number" then
    return
  end

  local lootConfig = lootData["listType"]
  local lootTable = (lootConfig == "whitelist" and lootData["whitelistTypes"] or lootData["blacklistTypes"])
  local filter = lootConfig == "whitelist"
  if not lootTable then
    return
  end

  if table.contains(lootTable, clientId) then
    return
  end

  table.insert(lootTable, clientId)
  normalizeLootFilterData()
  updateLootItems()
  saveData()
  g_game.updateLootWhiteList(filter, lootData[lootConfig == "whitelist" and "whitelistTypes" or "blacklistTypes"] or {})
end

function updateLootItems(searchText)
  local lootConfig = lootData["listType"]
  local lootTable = (lootConfig == "whitelist" and lootData["whitelistTypes"] or lootData["blacklistTypes"])
  if not lootTable then
    lootTable = {}
  end

  if not scrollBar then
    return
  end

  itemList:destroyChildren()

  cache.listFit = math.floor(itemList:getHeight() / 38) + 2
	cache.listMin = 0
	cache.listPool = {}
	cache.listData = {}

  if not searchText or #searchText == 0 then
    cache.listData = lootTable
  else
    for i, itemId in pairs(lootTable) do
      local itemName = getItemServerName(itemId)
      if matchText(searchText, itemName) then
        table.insert(cache.listData, itemId)
      end
    end
  end

  local count = 0
  for i, itemId in pairs(cache.listData) do
    if #cache.listPool >= cache.listFit then
      break
    end

    count = count + 1
    local itemName = getItemServerName(itemId)
    local widget = g_ui.createWidget('QuicklootItemBox', itemList)
    local color = (count % 2) == 0 and '#414141' or '#484848'

    widget:setId(itemId)
    widget:setBackgroundColor(color)
    widget:getChildById('itemType'):setText(itemName)
    widget:getChildById('itemId'):setItemId(itemId)

    widget:getChildById('buttonItemClear').onClick = function()
      removeItemInList(itemId)
    end

    table.insert(cache.listPool, widget)
  end

  cache.listMax = #cache.listData
  scrollBar:setValue(0)
  scrollBar:setMinimum(#cache.listPool > 0 and 1 or 0)
	scrollBar:setMaximum(#cache.listPool < 9 and 0 or math.max(0, cache.listMax - #cache.listPool) + 2)
	scrollBar.onValueChange = function(self, value, delta) onItemListValueChange(self, value, delta) end

	itemList:setVirtualOffset({x = 0, y = 0})
end

function onItemListValueChange(scroll, value, delta)
	local startLabel = math.max(cache.listMin, value)
	local endLabel = startLabel + #cache.listPool - 1
  
	if endLabel > cache.listMax then
	  endLabel = cache.listMax
	  startLabel = endLabel - #cache.listPool + 1
	end

	cache.offset = cache.offset + ((value % 5) * 2)
	if cache.offset > 20 or value <= 1 then
		cache.offset = 0
	end

	if value >= #cache.listData - 8 then
		cache.offset = 43
	end

	itemList:setVirtualOffset({x = 0, y = cache.offset})

	for i, widget in ipairs(cache.listPool) do
	  local index = value > 0 and (startLabel + i - 1) or (startLabel + i)
	  local itemId = cache.listData[index]

	  if itemId then
      local color = (index % 2) == 0 and '#414141' or '#484848'
      local itemName = getItemServerName(itemId)
      widget:setId(itemId)
      widget:setBackgroundColor(color)
      widget:getChildById('itemType'):setText(itemName)
      widget:getChildById('itemId'):setItemId(itemId)

      widget:getChildById('buttonItemClear').onClick = function() removeItemInList(itemId) end
    end
	end
end

function onSelectionChange(widget, selectedWidget)
  lootData["listType"] = selectedWidget:getId()

  if selectedWidget:getId() == "whitelist" then
    clearLootButton:setImageSource("/images/game/quickloot/clear-accepted-button")
    addToButton:setImageSource("/images/game/quickloot/add-accepted-button")
  else
    clearLootButton:setImageSource("/images/game/quickloot/clear-button")
    addToButton:setImageSource("/images/game/quickloot/add-button")
  end

  updateLootItems()
  saveData()

  if g_game.isOnline() then
    local lootConfig = lootData["listType"]
    local lootTable = (lootConfig == "whitelist" and lootData["whitelistTypes"] or lootData["blacklistTypes"])
    local filter = lootConfig == "whitelist"
    normalizeLootFilterData()
    g_game.doThing(false)
    g_game.updateLootWhiteList(filter, lootData[lootConfig == "whitelist" and "whitelistTypes" or "blacklistTypes"] or {})
    g_game.doThing(true)
  end
end

function removeItemInList(clientId)
  if type(clientId) ~= "number" then
    return
  end

  local lootConfig = lootData["listType"]
  local lootTable = (lootConfig == "whitelist" and lootData["whitelistTypes"] or lootData["blacklistTypes"])
  if not table.contains(lootTable, clientId) then
    return
  end

  for k, v in pairs(lootTable) do
    if v == clientId then
      table.remove(lootTable, k)
      break
    end
  end

  updateLootItems()
  saveData()
  normalizeLootFilterData()
  g_game.updateLootWhiteList(lootConfig == "whitelist", lootData[lootConfig == "whitelist" and "whitelistTypes" or "blacklistTypes"] or {})
end

function inWhiteList(clientId)
  if not clientId then
    clientId = 0
  end

  local lootConfig = lootData["listType"] or "whitelist"
  local lootTable = (lootConfig == "whitelist" and lootData["whitelistTypes"] or lootData["blacklistTypes"])
  if not lootTable then
	return false
  end

  return table.contains(lootTable, clientId)
end

function GetLootContainers()
  local c = {}
  for _, id in pairs(allContainers) do
    table.insert(c, id)
  end

  return c
end

function clearCurrentList()
  if confirmWindow then
    return
  end

  local okFunc = function()
    local currentList = lootData["listType"]
    if currentList == "whitelist" then
    lootData["whitelistTypes"] = {}
    else
    lootData["blacklistTypes"] = {}
    end
    updateLootItems()
    reloadLootWhiteList()
    saveData()
    g_client.setInputLockWidget(nil)
    quickLootWindow:show(true)
    g_client.setInputLockWidget(quickLootWindow)
    confirmWindow:destroy()
    confirmWindow = nil
  end

  local cancelFunc = function()
    g_client.setInputLockWidget(nil)
    quickLootWindow:show(true)
    g_client.setInputLockWidget(quickLootWindow)
    confirmWindow:destroy()
    confirmWindow = nil
  end

  local currentList = lootData["listType"]
  local actionType = currentList == "whitelist" and "Accepted" or "Skipped"
  quickLootWindow:hide()
  g_client.setInputLockWidget(nil)
	confirmWindow = displayGeneralBox(tr("Confirm Clearing of %s Loot List", actionType), tr("You are about to delete all objects from your %s Loot List.\nIf you click on \"Ok\", you will loot all dropped items and gold when using the quick loot function.", actionType),
    { { text=tr('Yes'), callback=okFunc },
    { text=tr('No'), callback=cancelFunc }
  }, okFunc, cancelFunc)
  g_client.setInputLockWidget(confirmWindow)
end

function redirectCyclopedia()
  quickLootWindow:hide()
  g_client.setInputLockWidget(nil)
  if modules.game_cyclopedia and modules.game_cyclopedia.Cyclopedia then
    modules.game_cyclopedia.Cyclopedia:open()
  elseif modules.game_cyclopedia and modules.game_cyclopedia.toggle then
    modules.game_cyclopedia.toggle()
  end
end
