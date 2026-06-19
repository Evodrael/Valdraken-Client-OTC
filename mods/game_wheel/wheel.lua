wheelWindow = nil
wheelOfDestinyWindow = nil
gemAtelierWindow = nil
fragmentWindow = nil
newPresetWindow = nil
renamePresetWindow = nil
exportCodeWindow = nil
deletePresetWindow = nil
checkSavePresetWindow = nil
selectedNewPresetRadio = nil
local summaryVisible = false

wheelPanel = nil
centerReferencePoint = nil

local function clearWheelMouseHandlers()
  if g_ui.clearMouseState then
    g_ui.clearMouseState()
  end
  if g_mouse.clearGrabber then
    g_mouse.clearGrabber()
  end
  if g_mouse.popCursor then
    for i = 1, 10 do
      pcall(function() g_mouse.popCursor('pointer') end)
    end
  end
  if g_window and g_window.setSystemCursor then
    g_window.setSystemCursor('default')
  end

  if wheelPanel then
    wheelPanel.onMouseMove = nil
    wheelPanel.onMouseRelease = nil
    local focus = wheelPanel:recursiveGetChildById('focusSelectedWheel')
    if focus then
      focus:setVisible(false)
    end
  end
  if WheelOfDestiny then
    WheelOfDestiny.mouseIndex = 0
  end
end

local function clearFragmentInputState()
  if not fragmentWindow then
    return
  end

  local searchText = fragmentWindow:recursiveGetChildById('searchText')
  if searchText and searchText:isFocused() and wheelWindow then
    wheelWindow:focus()
  end

  local fragmentContent = fragmentWindow:recursiveGetChildById('fragmentContent')
  if fragmentContent then
    fragmentContent:focusChild(nil)
  end

  if wheelWindow and wheelWindow:isVisible() then
    g_client.setInputLockWidget(wheelWindow)
  end
end

if not SkillwheelStringsLibrary then
  SkillwheelStringsLibrary = {}
end

function init()
  wheelWindow = g_ui.displayUI('wheel')
  if wheelWindow.setDraggable then
    wheelWindow:setDraggable(false)
  end
  mainPanel = wheelWindow:getChildById('mainPanel')

  -- Wheel Menu
  wheelOfDestinyWindow = g_ui.loadUI('styles/wheelMenu', mainPanel)
  wheelOfDestinyWindow:hide()

  -- Gem Menu
  gemAtelierWindow = g_ui.loadUI('styles/gemMenu', mainPanel)
  gemAtelierWindow:hide()

  -- Fragment Menu
  fragmentWindow = g_ui.loadUI('styles/fragmentMenu', mainPanel)
  fragmentWindow:hide()

  -- New Preset Menu
  newPresetWindow = g_ui.displayUI('styles/newPreset')
  newPresetWindow:hide()

  -- Rename Preset Window
  renamePresetWindow = g_ui.displayUI('styles/renamePreset')
  renamePresetWindow:hide()

  loadConfigJson()

  selectedNewPresetRadio = UIRadioGroup.create()
  selectedNewPresetRadio:addWidget(newPresetWindow.contentPanel.useEmpty)
  selectedNewPresetRadio:addWidget(newPresetWindow.contentPanel.copyPreset)
  selectedNewPresetRadio:addWidget(newPresetWindow.contentPanel.import)
  selectedNewPresetRadio:selectWidget(newPresetWindow.contentPanel.import)
  selectedNewPresetRadio.onSelectionChange = WheelOfDestiny.onNewPresetSelectionChange

  local addOneButton = wheelOfDestinyWindow:recursiveGetChildById('addOne')
  local rmvOneButton = wheelOfDestinyWindow:recursiveGetChildById('rmvOne')

  g_mouse.bindAutoPress(addOneButton, function()
    onAddOne()
  end, 500, nil)

  g_mouse.bindAutoPress(rmvOneButton, function()
    onRmvOne()
  end, 500, nil)

  loadMenu('wheelMenu')
  toggleTabBarButtons('informationButton')
  hide()
  connect(g_game, {
    onGameEnd = onGameEnd,
    onGameStart = WheelOfDestiny.loadWheelPresets,
    onDestinyWheel = WheelOfDestiny.onDestinyWheel,
    onUnlockGem = GemAtelier.onUnlockGem,
    onResourceBalance = onResourceBalance,
  })
end

function terminate()
  disconnect(g_game, {
    onGameEnd = onGameEnd,
    onGameStart = WheelOfDestiny.loadWheelPresets,
    onDestinyWheel = WheelOfDestiny.onDestinyWheel,
    onUnlockGem = GemAtelier.onUnlockGem,
    onResourceBalance = onResourceBalance
  })

  if wheelWindow then
    wheelWindow:destroy()
    wheelWindow = nil
  end
end

function toggle()
  if wheelWindow:isVisible() then
    hide()
  else
    wheelWindow:focus()
    loadMenu('wheelMenu')
    -- hide other windows
    if gemAtelierWindow:isVisible() then
      gemAtelierWindow:hide()
    end
    if fragmentWindow:isVisible() then
      fragmentWindow:hide()
    end

    g_game.sendOpenDestinyWheel(g_game.getLocalPlayer():getId())
    wheelWindow:recursiveGetChildById('tabContent'):setVisible(false)
    WheelOfDestiny.onRemoveClick()
  end
end

function hide()
  clearWheelMouseHandlers()
  clearFragmentInputState()
  g_client.setInputLockWidget(nil)
  wheelWindow:hide()
end

function onGameEnd()
  hide()
  WheelOfDestiny.saveWheelPresets()

  newPresetWindow:hide()
  renamePresetWindow:hide()

  if exportCodeWindow then
    exportCodeWindow:destroy()
    exportCodeWindow = nil
  end

  if exportCodeWindow then
    exportCodeWindow:destroy()
    exportCodeWindow = nil
  end

  if checkSavePresetWindow then
    checkSavePresetWindow:destroy()
    checkSavePresetWindow = nil
  end

  WheelOfDestiny.currentPreset = {}
  g_ui.setInputLockWidget(nil)
end

function show()
  g_game.requestResource(ResourceBank)
  g_game.requestResource(ResourceInventary)
  g_game.requestResource(ResourceWheelPoints)
  g_game.requestResource(ResourceLesserGem)
  g_game.requestResource(ResourceRegularGem)
  g_game.requestResource(ResourceGreaterGem)
  g_game.sendOpenDestinyWheel(g_game.getLocalPlayer():getId())
end

-- check click point
function onWheelClick(position)
  WheelOfDestiny.onWheelClick(position)
end

function loadMenu(menuId)
  clearWheelMouseHandlers()
  clearFragmentInputState()

  if wheelOfDestinyWindow:isVisible() then
    wheelOfDestinyWindow:hide()
  end
  if gemAtelierWindow:isVisible() then
    gemAtelierWindow:hide()
  end
  if newPresetWindow:isVisible() then
    newPresetWindow:hide()
  end
  if fragmentWindow:isVisible() then
    fragmentWindow:hide()
  end

  wheelMenuButton = wheelWindow.optionsTabBar:getChildById('wheelMenu')
  gemMenuButton = wheelWindow.optionsTabBar:getChildById('gemMenu')
  fragmentMenuButton = wheelWindow.optionsTabBar:getChildById('fragmentMenu')

  if menuId == 'wheelMenu' then
    gemAtelierWindow:hide()
    fragmentWindow:hide()
    wheelPanel = wheelOfDestinyWindow:getChildById('wheelPanel')

    wheelPanel.onMouseMove = WheelOfDestiny.onMouseMove

    centerReferencePoint = wheelOfDestinyWindow:recursiveGetChildById('centerReferencePoint')
    wheelMenuButton:setChecked(true)
    gemMenuButton:setChecked(false)
    fragmentMenuButton:setChecked(false)
    local informationButton = wheelWindow.mainPanel.wheelMenu.info.presetTabBar:getChildById('informationButton')
    local managePresetsButton = wheelWindow.mainPanel.wheelMenu.info.presetTabBar:getChildById('managePresetsButton')
    local summaryButton = wheelWindow.mainPanel.wheelMenu.dedicationPerks:getChildById('summaryButton')
    local summaryOpenedButton = wheelWindow.mainPanel.wheelMenu.summary:getChildById('summaryButton')
    informationButton.onClick = function() toggleTabBarButtons('informationButton') end
    managePresetsButton.onClick = function() toggleTabBarButtons('managePresetsButton') WheelOfDestiny.configurePresets() end
    summaryButton.onClick = function() toggleSummary() end
    summaryOpenedButton.onClick = function() toggleSummary() end
    toggleTabBarButtons('informationButton')

    if WheelOfDestiny.lastSelectedGemVessel and WheelOfDestiny.lastSelectedGemVessel:isVisible() then
      local currentDomain = WheelOfDestiny.lastSelectedGemVessel:getId():gsub("selectVessel", "")
      WheelOfDestiny.onGemVesselClick(tonumber(currentDomain))
    end
    Workshop.createFragments()
    wheelOfDestinyWindow:show(true)
  elseif menuId == 'gemMenu' then
    Workshop.createFragments()
    GemAtelier.resetFields()
    GemAtelier.showGems(true)
    gemAtelierWindow:show(true)
    wheelMenuButton:setChecked(false)
    fragmentMenuButton:setChecked(false)
    gemMenuButton:setChecked(true)
  elseif menuId == 'fragmentMenu' then
    Workshop.createFragments()
    Workshop.showFragmentList(true)
    fragmentWindow:show(true)
    wheelMenuButton:setChecked(false)
    gemMenuButton:setChecked(false)
    fragmentMenuButton:setChecked(true)
  end
end

function toggleSummary()
  summaryVisible = not summaryVisible

  local summaryPanel = wheelWindow.mainPanel.wheelMenu:getChildById('summary')
  local dedicationPerksPanel = wheelWindow.mainPanel.wheelMenu:getChildById('dedicationPerks')
  local convictionPerksPanel = wheelWindow.mainPanel.wheelMenu:getChildById('convictionPerks')
  local vesselsPanel = wheelWindow.mainPanel.wheelMenu:getChildById('vessels')
  local revelationPerksPanel = wheelWindow.mainPanel.wheelMenu:getChildById('revelationPerks')

  summaryPanel:setVisible(summaryVisible)
  dedicationPerksPanel:setVisible(not summaryVisible)
  convictionPerksPanel:setVisible(not summaryVisible)
  vesselsPanel:setVisible(not summaryVisible)
  revelationPerksPanel:setVisible(not summaryVisible)
  WheelOfDestiny.configureSummary()
end

function toggleTabBarButtons(selectedButtonId)
  local informationButton = wheelWindow.mainPanel.wheelMenu.info.presetTabBar:getChildById('informationButton')
  local managePresetsButton = wheelWindow.mainPanel.wheelMenu.info.presetTabBar:getChildById('managePresetsButton')
  local tabContent = wheelWindow.mainPanel.wheelMenu.info.tabContent

  if selectedButtonId == 'informationButton' then
    informationButton:setSize(tosize("174 34"))
    informationButton:setImageSource('/images/game/destiny_wheel/informationSelection')
    informationButton:setImageClip(torect("0 0 174 34"))
    managePresetsButton:setSize(tosize("34 34"))
    managePresetsButton:setImageSource('/images/game/destiny_wheel/small_manage_button')
    managePresetsButton:setImageClip(torect("0 0 34 34"))
    tabContent.manage:setVisible(false)
    tabContent.information:setVisible(true)
  elseif selectedButtonId == 'managePresetsButton' then
    informationButton:setSize(tosize("34 34"))
    informationButton:setImageSource('/images/game/destiny_wheel/small_information_button')
    informationButton:setImageClip(torect("0 0 34 34"))
    managePresetsButton:setSize(tosize("174 34"))
    managePresetsButton:setImageSource('/images/game/destiny_wheel/manageSelect')
    managePresetsButton:setImageClip(torect("0 0 174 34"))
    tabContent.information:setVisible(false)
    tabContent.manage:setVisible(true)
  end
end

function onResourceBalance()
  if not wheelWindow:isVisible() then
    return true
  end
  local player = g_game.getLocalPlayer()
  
  local bankMoney = player:getResourceValue(ResourceBank)
  local characterMoney = player:getResourceValue(ResourceInventary)
  local lesserFragment = player:getResourceValue(ResourceLesserFragment)
  local greaterFragment = player:getResourceValue(ResourceGreaterFragment)

  local value = bankMoney + characterMoney

  wheelWindow.moneyPanel.gold:setText(formatMoney(value, ','))
  wheelWindow.lesserFragmentPanel.gold:setText(lesserFragment)
  wheelWindow.greaterFragmentPanel.gold:setText(greaterFragment)

end

function loadConfigJson()
	local file = "/json/SkillwheelStringsJsonLibrary.json"
	if g_resources.fileExists(file) then
		local status, result = pcall(function()
			return json.decode(g_resources.readFileContents(file))
		end)

		if not status then
			return g_logger.error("Error while reading characterdata file. Details: " .. result)
		end

		SkillwheelStringsLibrary = result
	end
end
