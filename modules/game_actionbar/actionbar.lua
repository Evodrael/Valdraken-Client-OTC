local actionBars = {}
local activeActionBars = {}

local window = nil
-- Separate reference for the Multi-Action assignment window. It must NOT share
-- the `window` global because the sub-pickers (assignSpell/assignText/object)
-- reuse `window` and nil it when they close.
local multiActionWindow = nil

-- Safe destroy helper for the shared `window` global. The assignSpell /
-- assignMultiAction / popup-menu flows wire several handlers (Esc, Cancel,
-- Apply, OK, close button, etc.) that all call safeDestroyWindow(). When more
-- than one of them fires (e.g. Esc + Cancel click, or rapid double-click on
-- a multi-action slot), the same widget is destroyed twice and the engine
-- prints "WARNING: attempt to destroy widget '...' two times".
-- safeDestroyWindow() guards the destroy and clears the global reference.
local function safeDestroyWindow()
    if window and not window:isDestroyed() then
        window:destroy()
    end
    window = nil
end

local mouseGrabberWidget = nil
local gameRootPanel = nil
local player = nil
local lastHighlightWidget = nil
local isLoaded = false

-- Multi-Action ported from Luminaris (surgical integration)
-- Storage: [buttonId "barID.buttonID"] -> { actions = {[1..3]={type=..,data=..,..}}, index = 1, lastUsage = millis }
MultiActionStorage = MultiActionStorage or {}
local isAssigningObject = false

-- new
local hotkeyItemList = {}
local passiveData = { cooldown = 0, max = 0}
local spellModification = {}
local spellListData = {}

local spellCooldownCache = {}
local spellGroupPressed = {}

local cachedItemWidget = {}
local dragButton = nil
local dragItem = nil

-- Multi-Action debug logger (toggle with g_settings.set('multiAction_debug', true|false))
local MULTIACTION_DEBUG = false
local function multiActionLog(...)
	if MULTIACTION_DEBUG then
		print('[MultiAction]', ...)
	end
end

-- Convert all `actions = {[1]=..,[2]=..,[3]=..}` tables in the storage to dense
-- string-keyed maps before JSON encoding. The OTCV8 json encoder treats any
-- table with `rawget(t,1) ~= nil` as an array and refuses to encode it if it's
-- sparse (e.g., slot 2 cleared between two assigned slots) — the whole save
-- would otherwise silently fail and on-disk state would diverge from in-memory.
local function serializeMultiActionStorage()
	local out = {}
	for buttonKey, entry in pairs(MultiActionStorage) do
		if type(entry) == 'table' then
			local actionsOut = {}
			if type(entry.actions) == 'table' then
				for i = 1, 3 do
					local a = entry.actions[i]
					if a ~= nil then
						actionsOut[tostring(i)] = a
					end
				end
			end
			out[buttonKey] = {
				actions = actionsOut,
				index = entry.index or 1,
				lastUsage = entry.lastUsage
			}
		end
	end
	return out
end

-- Inverse of serializeMultiActionStorage: turn the on-disk string-keyed actions
-- back into integer-keyed Lua tables so `actions[1]`, `actions[2]`, etc. work.
local function deserializeMultiActionStorage(raw)
	if type(raw) ~= 'table' then return {} end
	local out = {}
	for buttonKey, entry in pairs(raw) do
		if type(entry) == 'table' then
			local actions = {}
			if type(entry.actions) == 'table' then
				for k, v in pairs(entry.actions) do
					local idx = tonumber(k)
					if idx and idx >= 1 and idx <= 3 then
						actions[idx] = v
					end
				end
			end
			out[buttonKey] = {
				actions = actions,
				index = tonumber(entry.index) or 1,
				lastUsage = tonumber(entry.lastUsage)
			}
		end
	end
	return out
end

-- Multi-Action persistence (uses g_settings + json)
function saveMultiActions()
	if not g_game.isOnline() then return end
	local charName = g_game.getCharacterName()
	if not charName then return end
	local key = 'MultiActions_' .. charName
	if json and json.encode then
		local payload = serializeMultiActionStorage()
		local ok, encoded = pcall(json.encode, payload)
		if ok then
			g_settings.set(key, encoded)
			if g_settings.save then g_settings.save() end
			multiActionLog('save ok char=', charName, 'entries=', table.size(MultiActionStorage))
		else
			-- Surface encoder failures instead of swallowing them — this used to
			-- silently lose Multi-Action assignments whenever the actions table
			-- went sparse (e.g., user cleared slot 2 while keeping 1 and 3).
			g_logger.error('[MultiAction] saveMultiActions failed: ' .. tostring(encoded))
		end
	end
end

function loadMultiActions()
	if not g_game.isOnline() then return end
	local charName = g_game.getCharacterName()
	if not charName then return end
	-- Always start from a clean slate so a previous character's Multi-Actions
	-- (and their "3 dots" indicators) never bleed into this character. Storage
	-- is keyed per character; an empty/missing key means "no Multi-Actions".
	MultiActionStorage = {}
	local key = 'MultiActions_' .. charName
	if g_settings.exists and g_settings.exists(key) then
		local data = g_settings.getString(key)
		if data and data ~= "" and json and json.decode then
			local ok, result = pcall(json.decode, data)
			if ok and type(result) == 'table' then
				MultiActionStorage = deserializeMultiActionStorage(result)
				multiActionLog('load ok char=', charName, 'entries=', table.size(MultiActionStorage))
			else
				g_logger.error('[MultiAction] loadMultiActions decode failed: ' .. tostring(result))
			end
		end
	end
end

function multiAction_getStorageForButton(button)
	if not button then return nil end
	local key = button:getId()
	return MultiActionStorage[key], key
end

function multiAction_hasActions(button)
	local data = multiAction_getStorageForButton(button)
	return data and data.actions and not table.empty(data.actions)
end

-- Stub: Wheel of Destiny passives not present in OTCV8; some Luminaris paths may call this.
function refreshPassiveAbilities()
	-- intentionally empty; OTCV8 uses static PassiveAbilities
end

function getGrabberWidget()
	return mouseGrabberWidget
end

function getRootPanel()
	return gameRootPanel
end

function getButtonCache(button)
	if not button then
		return {
			cooldownEvent = nil,
			cooldownTime = 0,
			isSpell = false,
			isRuneSpell = false,
			isPassive = false,
			spellID = 0,
			spellData = nil,
			param = "",
			sendAutomatic = false,
			actionType = 0,
			upgradeTier = 0,
			smartMode = nil,
			hotkey = nil,
			lastClick = 0,
			nextDownKey = 0,
			isDragging = false,
			buttonIndex = 0,
			buttonParent = nil,
			itemId = 0,
			equipmentPreset = {},
			equipmentPresetIcon = ""
		}
	end

	if not button.cache then
		button.cache = {
			cooldownEvent = nil,
			cooldownTime = 0,
			isSpell = false,
			isRuneSpell = false,
			isPassive = false,
			spellID = 0,
			spellData = nil,
			param = "",
			sendAutomatic = false,
			actionType = 0,
			upgradeTier = 0,
			smartMode = nil,
			hotkey = nil,
			lastClick = 0,
			nextDownKey = 0,
			isDragging = false,
			buttonIndex = 0,
			buttonParent = nil,
			itemId = 0,
			equipmentPreset = {},
			equipmentPresetIcon = ""
		}
	end

	return button.cache
end

function getSmartCast(itemId)
	if smartList[itemId] then return smartList[itemId] end

	for inactiveId, activeId in pairs(smartList) do
		if itemId == activeId then
			return inactiveId
		end
	end
end

function getInactiveSmartCast(activeItemId)
	for inactiveId, activeId in pairs(smartList) do
		if activeItemId == activeId then
			return inactiveId
		end
	end
end

function getActiveSmartCast(inactiveItemId)
	return smartList[inactiveItemId]
end

local UseTypes = {
	["UseOnYourself"] = 1,
	["UseOnTarget"] = 2,
	["SmartCast"] = 3,
	["SelectUseTarget"] = 4,
	["Equip"] = 5,
	["Use"] = 6,

	-- Custom
	["chatText"] = 7,
	["passiveAbility"] = 8,
	["equipmentPreset"] = 9
}

local UseTypesTip = {
	[1] = "Use %s on Yourself",
	[2] = "Use %s on Attack Target",
	[3] = "Smart press %s",
	[4] = "Use %s with Crosshair",
	[5] = "%s %s",
	[6] = "Use %s",
}

function init()
	connect(LocalPlayer, {
		onManaChange 		= onUpdateActionBarStatus,
		onSoulChange 		= onUpdateActionBarStatus,
		onLevelChange 		= onUpdateLevel,
		onSpellsChange 		= onSpellsChange,
		onMonkPassiveChange = onUpdateActionBarStatus,
	})

	connect(g_game, {
		onGameEnd 				  = offline,
		onItemInfo                = onHotkeyItems,
		onGameStart 		      = online,
		onPassiveData             = onPassiveData,
		onSpellCooldown 		  = onSpellCooldown,
		onMultiUseCooldown        = onMultiUseCooldown,
		onSpellModification       = onSpellModification,
		onReleaseActionKeys       = onReleaseActionKeys,
		onSpellGroupCooldown 	  = onSpellGroupCooldown,
		updateInventoryItems      = updateInventoryItems,
		onEquipmentPresetCooldown = onEquipmentPresetCooldown
	})

	if g_game.isOnline() then
		online()
	end

	onCreateActionBars()

	gameRootPanel = m_interface.getRootPanel()
	mouseGrabberWidget = g_ui.createWidget('UIWidget')
	mouseGrabberWidget:setVisible(true)
	mouseGrabberWidget:setFocusable(false)
	mouseGrabberWidget.onMouseRelease = onDropActionButton
end

function terminate()
	disconnect(LocalPlayer, {
		onManaChange 		= onUpdateActionBarStatus,
		onSoulChange 		= onUpdateActionBarStatus,
		onLevelChange 		= onUpdateLevel,
		onSpellsChange 		= onSpellsChange,
		onMonkPassiveChange = onUpdateActionBarStatus,
	})

	disconnect(g_game, {
		onGameEnd 				  = offline,
		onItemInfo                = onHotkeyItems,
		onGameStart 		      = online,
		onPassiveData             = onPassiveData,
		onSpellCooldown 		  = onSpellCooldown,
		onMultiUseCooldown        = onMultiUseCooldown,
		onSpellModification       = onSpellModification,
		onReleaseActionKeys       = onReleaseActionKeys,
		onSpellGroupCooldown 	  = onSpellGroupCooldown,
		updateInventoryItems      = updateInventoryItems,
		onEquipmentPresetCooldown = onEquipmentPresetCooldown
	})

	actionBars = {}
end

function online()
	local benchmark = g_clock.millis()
	dragItem = nil
	dragButton = nil
	cachedItemWidget = {}
	player = g_game.getLocalPlayer()
	hotkeyItemList = {}
	spellGroupPressed = {}

	-- Ensure the per-character hotkey/action-bar profile is active BEFORE we
	-- build any buttons. Without this, when two characters on the same account
	-- share a session (login → logout → login), the action bars get built from
	-- whichever profile was active last (the previous character), and the
	-- new character would see the wrong hotkeys/mappings. Options.online()
	-- normally does this on g_game.onGameStart, but the connection order
	-- between modules isn't guaranteed, so we re-apply here defensively.
	if player and Options and Options.applyCharacterHotkeyProfile then
		Options.applyCharacterHotkeyProfile(player)
	end

	modules.game_console.setChatState(Options.isChatOnEnabled)

	-- Multi-Action: load persisted storage for this character
	loadMultiActions()

	for i = 1, #actionBars do
		setupActionBar(i)
	end

	-- schedule update items
	scheduleEvent(function() updateActionBar() onUpdateActionBarStatus() updateActionPassive() updateVisibleWidgets() isLoaded = true end, 300)
	consoleln("ActionBars loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function offline()
	for _, actionbar in pairs(activeActionBars) do
		unbindActionBarEvent(actionbar)
	end

	hotkeyItemList = {}
	-- Reset Multi-Action runtime state (storage will be reloaded on next login)
	MultiActionStorage = {}

	if window then
		safeDestroyWindow()
		window = nil
	end

	offLineEvents()
end

function onCreateActionBars()
	local gameMapPanel = m_interface.gameMapPanel
	if not gameMapPanel then
		return true
	end

	if #actionBars == 0 then
		createActionBars()
	end
	local margins = {41, 80, 119}
	local totalMargin = 2

	for i = 1, #actionBars do
		local actionbar = actionBars[i]
		local enabled = Options.actionBar[i].isVisible

		actionbar:setOn(enabled)
		setupActionBar(i)
		if not enabled then
			goto continue
		end

		table.insert(activeActionBars, actionbar)
		local previousEnabled = true
		for j = 1, i - 1 do
			if not g_settings.getBoolean("actionbar" .. j, false) then
				previousEnabled = false
				break
			end
		end
		if previousEnabled then
			totalMargin = margins[i]
		end

		:: continue ::
	end

	resizeLockButtons()
	gameMapPanel:setMarginBottom(totalMargin)
end

function createActionBars()
	local bottomPanel = m_interface.getBottomActionPanel()
	local leftPanel = m_interface.getLeftActionPanel()
	local rightPanel = m_interface.getRightActionPanel()

	-- 1-3: bottom
	-- 4-6: left
	-- 7-9: right
	for i = 1, 9 do
		local parent, index, layout, isVertical
		if i <= 3 then
			parent = bottomPanel
			index = i
			layout = 'actionbar'
			isVertical = false
		elseif i <= 6 then
			parent = leftPanel
			index = i - 3
			layout = 'sideactionbar'
			isVertical = true
		else
			parent = rightPanel
			index = i - 6
			layout = 'sideactionbar'
			isVertical = true
		end

		actionBars[i] = g_ui.loadUI(layout, parent)
		actionBars[i]:setId("actionbar."..i)
		actionBars[i].n = i
		actionBars[i].isVertical = isVertical
		parent:moveChildToIndex(actionBars[i], index)
	end
end

function resizeLockButtons()
	local rightLockPanel = m_interface.getRightLockPanel()
	local rightCount = getActiveRightBars()
	rightLockPanel:setVisible(true)
	rightLockPanel:setIcon(Options.clientOptions["actionBarRightLocked"] and "/images/game/actionbar/locked" or "/images/game/actionbar/unlocked")
	if rightCount >= 1 and rightCount <= 3 then
		rightLockPanel:setWidth(35 + (rightCount - 1) * 36 - 1)
		rightLockPanel:getParent():setWidth(((36 + (rightCount - 1) * 36)) + 1)
	else
		rightLockPanel:setWidth(0)
		rightLockPanel:getParent():setWidth(0)
		rightLockPanel:setVisible(false)
	end

	local bottomLockPanel = m_interface.getBottomLockPanel()
	local bottomCount = getActiveBottomBars()
	bottomLockPanel:setVisible(true)
	bottomLockPanel:setIcon(Options.clientOptions["actionBarBottomLocked"] and "/images/game/actionbar/locked" or "/images/game/actionbar/unlocked")
	if bottomCount >= 1 and bottomCount <= 3 then
		bottomLockPanel:setHeight(34 + (bottomCount - 1) * 36)
	else
		bottomLockPanel:setHeight(0)
		bottomLockPanel:setVisible(false)
	end

	local leftLockPanel = m_interface.getLeftLockPanel()
	local leftCount = getActiveLeftBars()
	leftLockPanel:setVisible(true)
	leftLockPanel:setIcon(Options.clientOptions["actionBarLeftLocked"] and "/images/game/actionbar/locked" or "/images/game/actionbar/unlocked")
	if leftCount >= 1 and leftCount <= 3 then
		leftLockPanel:setWidth(35 + (leftCount - 1) * 36 - 1)
		leftLockPanel:getParent():setWidth(((36 + (leftCount - 1) * 36)) + 1)
	else
		leftLockPanel:setWidth(0)
		leftLockPanel:getParent():setWidth(0)
		leftLockPanel:setVisible(false)
	end
end

function setupActionBar(n)
	local actionbar = actionBars[n]
	local visible = actionbar:isVisible()
	local locked = Options.actionBar[n].isLocked
	actionbar.tabBar.onMouseWheel = nil

	actionbar.locked = locked

	local items = {}
	for i = 1, 50 do
		local layout = n < 4 and 'ActionButton' or 'SideActionButton'
		local widget = actionbar.tabBar:getChildById(n.."."..i)

		if not widget then
			widget = g_ui.createWidget(layout, actionbar.tabBar)
			widget:setId(n.."."..i)
		end

		resetButtonCache(widget)
		if g_game.isOnline() then
			updateButton(widget)
		end

		if widget.cooldown then
			widget.cooldown:stop()
		end

		if widget.item and widget.item:getItemId() > 100 then
			table.insert(items, widget.item:getItem())
		end
	end

	scheduleEvent(function() g_game.doThing(false) g_game.requestHotkeyItems(items) g_game.doThing(true) end, 100)
end

function resetButtonCache(button)
	if button.cache and button.cache.itemId > 0 then
		local cachedItem = cachedItemWidget[button.cache.itemId]
		if cachedItem then
			for index, widget in pairs(cachedItem) do
				if button == widget then
					table.remove(cachedItem, index)
				end
			end
		end
	end

	if button.item then
		button.item:setItemId(0)
		button.item:setOn(false)
		button.item:setChecked(false)
		button.item:setDraggable(false)
		if button.item.gray then
			button.item.gray:setVisible(false)
		end
		if button.item.text then
			button.item.text.gray:setVisible(false)
			button.item.text:setImageSource('')
			button.item.text:setText('')
			-- Destroy any leftover Multi-Action marker so it never lingers on a
			-- button reused by a character that has no Multi-Action on this slot.
			local multiOverlay = button.item.text:getChildById('multiOverlay')
			if multiOverlay then multiOverlay:destroy() end
		end
	end

	if button.hotkeyLabel then
		button.hotkeyLabel:setText('')
	end
	if button.parameterText then
		button.parameterText:setText('')
	end
	if button.cooldown then
		button.cooldown:setPercent(100)
		button.cooldown:setText("")
	end

	if button.cache then
		if button.cache.removeCooldownEvent then
			removeEvent(button.cache.removeCooldownEvent)
		end
	end

	button.cache = {
		cooldownEvent = nil,
		cooldownTime = 0,
		isSpell = false,
		isRuneSpell = false,
    	isPassive = false,
		spellID = 0,
		spellData = nil,
		primaryGroup = nil,
		param = "",
		sendAutomatic = false,
		actionType = 0,
		upgradeTier = 0,
		smartMode = nil,
		hotkey = nil,
		lastClick = 0,
		nextDownKey = 0,
		isDragging = false,
		buttonIndex = 0,
		buttonParent = nil,
		itemId = 0,
		equipmentPreset = {},
		equipmentPresetIcon = ""
	}
end

function onDropActionButton(self, mousePosition, mouseButton)
	if not g_ui.isMouseGrabbed() then return end
	g_mouse.updateGrabber(self, 'target')
	g_mouse.popCursor('target')
	self:ungrabMouse()

	if dragButton and dragItem then
		isLoaded = false
		dragButton.cache.isDragging = false
		onDragItemLeave(dragItem, mousePosition, dragButton)
		isLoaded = true
		dragButton = nil
		dragItem = nil
	end
end

function onMultiUseCooldown(time)
	updateActionBar(time)
end

function onSpellCooldown(spellId, delay)
	if not m_settings.getOption("graphicalCooldown") and not m_settings.getOption("cooldownSecond") then
		return true
	end

	local isRune = Spells.isRuneSpell(spellId)
  spellCooldownCache[spellId] = {exhaustion = delay, startTime = g_clock.millis()}

	for _, actionbar in pairs(activeActionBars) do
		for _, button in pairs(actionbar.tabBar:getChildren()) do
			local cache = getButtonCache(button)
			if not (cache.isSpell or cache.isRuneSpell) then
				goto continue
			end

			if cache.isRuneSpell and not isRune then
				goto continue
			end

			if not cache.isRuneSpell and cache.spellID ~= spellId then
				goto continue
			end

			if cache.cooldownEvent ~= nil and button.cooldown:getTimeElapsed() > delay then
				goto continue
			end

			updateCooldown(button, delay)
			if cache.removeCooldownEvent then
				removeEvent(button.cache.removeCooldownEvent)
			end
			button.cache.removeCooldownEvent = scheduleEvent(function() modules.game_actionbar.removeCooldown(button) end, delay)
			:: continue ::
		end
	end
end

function onSpellGroupCooldown(groupId, delay)
	if not m_settings.getOption("graphicalCooldown") and not m_settings.getOption("cooldownSecond") then
		return true
	end

	for _, actionbar in pairs(activeActionBars) do
		for _, button in pairs(actionbar.tabBar:getChildren()) do
			local cache = getButtonCache(button)
			if cache.isRuneSpell or not cache.spellData then
				goto continue
			end

			if Spells.getCooldownByGroup(cache.spellData, groupId) then
				local resttime = button.cooldown:getDuration() - button.cooldown:getTimeElapsed()
				if resttime < delay then
					updateCooldown(button, delay)
					removeEvent(button.cache.removeCooldownEvent)
					button.cache.removeCooldownEvent = scheduleEvent(function() modules.game_actionbar.removeCooldown(button) end, delay)
					spellCooldownCache[button.cache.spellData.id] = {exhaustion = delay, startTime = g_clock.millis()}
				end
			end

			if Spells.getCooldownBySecondaryGroup(cache.spellData, groupId) then
				local spellCache = spellCooldownCache[button.cache.spellData.id]
				if not spellCache then
					spellCache = {}
					spellCache.startTime = 0
				end

				local resttime = button.cooldown:getDuration() - button.cooldown:getTimeElapsed()
				if resttime < delay then
					updateCooldown(button, delay)
					removeEvent(button.cache.removeCooldownEvent)
					button.cache.removeCooldownEvent = scheduleEvent(function() modules.game_actionbar.removeCooldown(button) end, delay)
					spellCooldownCache[button.cache.spellData.id] = {exhaustion = delay, startTime = g_clock.millis()}
				end
			end
			:: continue ::
		end
	end
end

function onEquipmentPresetCooldown(delay)
	for _, actionbar in pairs(activeActionBars) do
		for _, button in pairs(actionbar.tabBar:getChildren()) do
			local cache = getButtonCache(button)
			if string.empty(cache.equipmentPresetIcon) then
				goto continue
			end

			updateCooldown(button, delay)
			removeEvent(button.cache.removeCooldownEvent)
			button.cache.removeCooldownEvent = scheduleEvent(function() modules.game_actionbar.removeCooldown(button) end, delay)

			:: continue ::
		end
	end
end

function onPassiveData(currentCooldown, maxCooldown, canDecay)
	passiveData = {cooldown = currentCooldown, max = maxCooldown}
	updateActionPassive()
end

function onSpellsChange(player, list)
	spellListData = {}
	for _, spellId in pairs(list) do
		local spell = Spells.getSpellByClientId(spellId)
		if spell then
			spellListData[tostring(spellId)] = spell
		end
	end
end

function canSpellCast(info)
	local localPlayer = g_game.getLocalPlayer()
	if localPlayer == nil or info == nil then
		return false
	end

	if not info.forceLearn and next(spellListData) ~= nil then
		local spellId = tostring(info.id or 0)
		local clientId = tostring(info.clientId or info.clientid or 0)
		-- The learned-spell list is authoritative when the spell is present. On a
		-- miss we fall through to the vocation check instead of blocking, so an
		-- id/clientId mismatch can't hide a spell the player can actually use.
		if spellListData[spellId] or spellListData[clientId] then
			return true
		end
	end

	if type(info.vocations) ~= "table" or #info.vocations == 0 then
		return true
	end

	-- SpellInfo stores CIP numeric vocation ids: 1/5 = Sorcerer, 2/6 = Druid,
	-- 3/7 = Paladin, 4/8 = Knight, 9/10 = Monk (base/promoted); 0 = no restriction.
	-- The previous code name-matched strings, so numeric ids never matched and
	-- every spell was wrongly reported as "wrong vocation".
	for _, vocation in ipairs(info.vocations) do
		local matched = false
		if type(vocation) == "number" then
			if vocation == 0 then
				matched = true
			elseif vocation == 1 or vocation == 5 then
				matched = localPlayer.isSorcerer and localPlayer:isSorcerer()
			elseif vocation == 2 or vocation == 6 then
				matched = localPlayer.isDruid and localPlayer:isDruid()
			elseif vocation == 3 or vocation == 7 then
				matched = localPlayer.isPaladin and localPlayer:isPaladin()
			elseif vocation == 4 or vocation == 8 then
				matched = localPlayer.isKnight and localPlayer:isKnight()
			elseif vocation == 9 or vocation == 10 then
				matched = localPlayer.isMonk and localPlayer:isMonk()
			end
		else
			local name = tostring(vocation):lower()
			matched = (name:find("knight") and localPlayer.isKnight and localPlayer:isKnight())
				or (name:find("paladin") and localPlayer.isPaladin and localPlayer:isPaladin())
				or (name:find("druid") and localPlayer.isDruid and localPlayer:isDruid())
				or (name:find("sorcerer") and localPlayer.isSorcerer and localPlayer:isSorcerer())
				or (name:find("monk") and localPlayer.isMonk and localPlayer:isMonk())
		end

		if matched then
			return true
		end
	end

	return false
end

function onSpellModification(spells)
	spellModification = {}
	for _, data in pairs(spells) do
		spellModification[tostring(data[1])] = {type = data[2], value = data[3]}
	end

	onUpdateActionBarStatus()
end

function getActiveBottomBars()
	if #actionBars == 0 then
		return 0
	end

	local count = 0
	for i = 1, 3 do
		local enabled = Options.actionBar[i].isVisible
		if enabled then
			count = count + 1
		end
	end
	return count
end

function getActiveRightBars()
	if #actionBars == 0 then
		return 0
	end

	local count = 0
	for i = 7, 9 do
		local enabled = Options.actionBar[i].isVisible
		if enabled then
			count = count + 1
		end
	end
	return count
end

function getActiveLeftBars()
	if #actionBars == 0 then
		return 0
	end

	local count = 0
	for i = 4, 6 do
		local enabled = Options.actionBar[i].isVisible
		if enabled then
			count = count + 1
		end
	end
	return count
end

function onHotkeyItems(itemList)
	for _, data in pairs(itemList) do
		table.insert(hotkeyItemList, data)
	end

	for _, actionbar in pairs(activeActionBars) do
		for _, button in pairs(actionbar.tabBar:getChildren()) do
			if button.item:getItemId() < 100 then
				goto continue
			end
			setupButtonTooltip(button, false)
			:: continue ::
		end
	end
end

function updateInventoryItems(_)
    for _, widgetList in pairs(cachedItemWidget) do
        for _, widget in pairs(widgetList) do
            updateButtonState(widget)
        end
    end
end

function setupButtonTooltip(button, isEmpty)
	if not g_game.isOnline() then
		return true
	end

	local cache = getButtonCache(button)
	if isEmpty then
	  local tooltip = "Action Button " .. button:getId()
		local hotkeyDesc = cache.hotkey and cache.hotkey or "None"
		tooltip = tooltip.."\n\nAction:  " .. "None"
		tooltip = tooltip.."\nHotkeys:  " .. hotkeyDesc
		if button.item then
			button.item:setTooltip(tooltip)
		end
		return true
	end

	local actionDesc = ""
	local spellData = cache.spellData

	local function getModifiedSpellCooldown(data)
		local modified = spellModification[tostring(data.id)]
		if not modified or modified.type ~= 1 then
			return data.exhaustion
		end

		return data.exhaustion + modified.value
	end

	local function getModifiedSpellMana(data)
		local modified = spellModification[tostring(data.id)]
		if not modified or modified.type ~= 0 then
			return data.mana
		end

		return data.mana + modified.value
	end

	if cache.actionType == 7 then
		if not cache.isSpell then
			actionDesc = 'Say: "' .. string.lineBreaks(cache.param, 44, 36) .. '"\n'
			actionDesc = actionDesc .. "Auto sent:  " .. (cache.sendAutomatic and "Yes" or "No")
		else
			actionDesc = "Cast " .. Spells.getSpellNameByWords(spellData.words) .."\n"
			actionDesc = actionDesc.. "   Formula:  ".. cache.param .. "\n"
			actionDesc = actionDesc.. " Cooldown:  " .. getModifiedSpellCooldown(spellData) / 1000 .. "s\n"
			actionDesc = actionDesc.. "         Mana:  ".. getModifiedSpellMana(spellData)
		end
	elseif cache.actionType == 8 then
		actionDesc = "Gift of Life"
	elseif cache.actionType == 9 then
		actionDesc = "Equip Preset"
	else
		actionDesc = UseTypesTip[cache.actionType]
		if actionDesc == nil then
			actionDesc = "Use %s"
		end

		if cache.actionType == UseTypes["Equip"] then
			local itemName = getItemNameById(button.item:getItem():getId()) .. ((cache.upgradeTier and cache.upgradeTier > 0) and " (Tier " .. cache.upgradeTier .. ")" or "")
			actionDesc = tr(actionDesc, (button.item:isChecked() and "Unequip" or "Equip"), itemName)
		elseif button.item:getItem() then
			actionDesc = tr(actionDesc, getItemNameById(button.item:getItem():getId()))
		end

		local smartId = getSmartCast(button.cache.itemId)
		local itemCount = player:getInventoryCount(button.cache.itemId, button.cache.upgradeTier) + player:getInventoryCount(smartId, button.cache.upgradeTier)
		actionDesc = actionDesc .. "\n    Amount:  " .. itemCount
	end

	local hotkeyDesc = cache.hotkey and cache.hotkey or "None"
	local tooltip = "Action Button ".. button:getId()

	if cache.actionType == 8 then
		tooltip = tooltip .. "\n\n Passive Ability:  " .. actionDesc
		tooltip = tooltip .. "\n            Hotkeys:  " .. hotkeyDesc
	else
		tooltip = tooltip .. "\n\n       Action:  " .. actionDesc
		tooltip = tooltip .. "\n   Hotkeys:  " .. hotkeyDesc
	end

	button.item:setTooltip(tooltip)
end

function updateButton(button)
	if not player then
		player = g_game.getLocalPlayer()
	end

	local buttonData = nil
	local barID, buttonID = string.match(button:getId(), "(%d+)%.(%d+)")

	if not button.item then
		local actionId, buttonId = button:getId():match("([^.]+)%.([^.]+)")
		button:destroy()
		local actionbar = actionBars[tonumber(actionId)]
		local layout = tonumber(actionId) < 4 and 'ActionButton' or 'SideActionButton'
		local widget = g_ui.createWidget(layout, actionbar.tabBar)
		actionbar.tabBar:moveChildToIndex(widget, tonumber(buttonId))
		widget:setId(actionId.."."..buttonId)
		updateButton(widget)
		return
	end

	for _, data in pairs(Options.actionBarMappings) do
		if data["actionBar"] == tonumber(barID) and data["actionButton"] == tonumber(buttonID) then
			buttonData = data
			break
		end
	end

	resetButtonCache(button)
	button.item.text:setTextOffset("0 0")

	button.cache = getButtonCache(button)
	if button.item.getItemId and not button.cache.actionType then
		button.item:setItemId(0, true)
		button.item:setOn(false)
	end

	setupHotkeyButton(button)
	if button.cache.hotkey then
		button.item.text:setTextOffset("0 8")
		button.hotkeyLabel:setText(translateDisplayHotkey(button.cache.hotkey))
	end

	-- Multi-Action: restore cache from persistent storage before checking
	-- emptiness. Always assign (even nil) so a button reused from a previous
	-- character without a Multi-Action here gets its stale indicator cleared.
	button.cache.multiAction = MultiActionStorage[button:getId()]
	local hasMultiAction = button.cache.multiAction and button.cache.multiAction.actions and not table.empty(button.cache.multiAction.actions)

	if (not buttonData or not buttonData["actionsetting"]) and not hasMultiAction then
		setupButtonTooltip(button, true)
		button.item:setDraggable(false)
		configureButtonMouseRelease(button)
		return true
	end

	-- buttonData may be nil here when only Multi-Action is configured. Guard accesses.
	local useAction, sendText, passiveAbility, equipPreset, equipPresetIcon
	if buttonData and buttonData["actionsetting"] then
		useAction = buttonData["actionsetting"]["useObject"]
		sendText = buttonData["actionsetting"]["chatText"]
		passiveAbility = buttonData["actionsetting"]["passiveAbility"]
		equipPreset = buttonData["actionsetting"]["equipmentPreset"]
		equipPresetIcon = buttonData["actionsetting"]["equipmentPresetIcon"] or ""
	end

	if useAction then
		button.item:setItemId(useAction, true)
		button.item:setOn(true)

		local cached = cachedItemWidget[useAction]
		if cached then
			table.insert(cached, button)
		else
			cachedItemWidget[useAction] = {}
			table.insert(cachedItemWidget[useAction], button)
		end

		-- check runes
		local spellData = Spells.getRuneSpellByItem(useAction)
		if spellData then
			button.cache.isRuneSpell = true
			button.cache.spellData = spellData
			if spellData.vocations and not table.contains(spellData.vocations, translateVocation(player:getVocation())) then
				button.item.gray:setVisible(true)
			end
		end

		button.cache.itemId = button.item:getItemId()
		button.cache.smartMode = buttonData["actionsetting"]["useEquipSmartMode"]
		button.cache.upgradeTier = buttonData["actionsetting"]["upgradeTier"]
		button.cache.actionType = UseTypes[buttonData["actionsetting"]["useType"]]
		updateButtonState(button)
	end

	if sendText then
		local spellData, param = Spells.getSpellDataByParamWords(sendText:lower())
		if spellData then
			local spellId = SpellIcons[spellData.icon][1]
			local source = SpelllistSettings['Default'].iconsFolder
			local clip = Spells.getImageClipNormal(spellId, 'Default')

			button.item.text:setImageSource(source)
			button.item.text:setImageClip(clip)
			button.cache.isSpell = true
			button.cache.spellID = spellData.id
			button.cache.spellData = spellData
			button.cache.primaryGroup = spellData.group and Spells.getGroupIds(spellData)[1] or nil

			if param then
				local formatedParam = param:gsub('"', '')
        		button.parameterText:setText(short_text('"' .. formatedParam, 4))
        		button.cache.castParam = formatedParam
			end

			if not playerCanUseSpell(spellData) then
				button.item.text.gray:setVisible(true)
			end

      		checkRemainSpellCooldown(button, spellData.id)
		else
			button.item.text:setText(short_text(sendText, 15))
		end

		button.item:setOn(true)
		button.cache.param = sendText
		button.cache.sendAutomatic = buttonData["actionsetting"]["sendAutomatically"]
		button.cache.actionType = UseTypes["chatText"]
	end

	if passiveAbility then
		local passive = PassiveAbilities[passiveAbility]
		button.item.text:setImageSource(passive.icon)
		button.item.text:setImageClip("0 0 32 32")
		button.cache.actionType = UseTypes["passiveAbility"]
		button.cache.isPassive = true
		updateActionPassive(button)
	end

	if equipPreset and not table.empty(equipPreset) then
		button.item:setOn(true)
		button.cache.equipmentPreset = equipPreset
		button.cache.equipmentPresetIcon = equipPresetIcon
		button.cache.actionType = UseTypes["equipmentPreset"]

		if not string.empty(equipPresetIcon) then
			button.item.text:setImageSource("/images/game/actionbar/equip-preset/" .. equipPresetIcon)
			button.item.text:setImageClip("0 0 30 30")
		end
	end

	-- Multi-Action rendering: paint the current rotation slot's icon + overlay marker
	do
		-- Always assign (even nil) so a button reused from a previous character
		-- without a Multi-Action here drops the stale data instead of keeping it.
		button.cache.multiAction = MultiActionStorage[button:getId()]
		local multiAction = button.cache.multiAction

		-- Always remove any existing marker overlay BEFORE deciding to re-add it.
		-- Without this, switching to a character that has no Multi-Action on this
		-- hotkey kept showing the previous character's marker ("3 dots").
		local oldOverlay = button.item.text:getChildById('multiOverlay')
		if oldOverlay then oldOverlay:destroy() end

		if multiAction and multiAction.actions and not table.empty(multiAction.actions) then
			local actions = multiAction.actions
			local index = multiAction.index or 1
			if not actions[index] then index = 1; multiAction.index = 1 end
			local currentAction = actions[index]

			button.item:setOn(true)

			if currentAction then
				if currentAction.type == "Spell" then
					local spellData = Spells.getSpellDataByParamWords(tostring(currentAction.data):lower())
					if spellData and SpellIcons and SpellIcons[spellData.icon] then
						local spellId = SpellIcons[spellData.icon][1]
						local source = SpelllistSettings['Default'].iconsFolder
						local clip = Spells.getImageClipNormal(spellId, 'Default')
						button.item.text:setImageSource(source)
						button.item.text:setImageClip(clip)
						button.cache.isSpell = true
						button.cache.spellID = spellData.id
						button.cache.spellData = spellData
						checkRemainSpellCooldown(button, spellData.id)
					else
						button.item.text:setText(short_text(tostring(currentAction.data), 6))
					end
				elseif currentAction.type == "Text" then
					button.item.text:setText(short_text(tostring(currentAction.data), 6))
				elseif currentAction.type == "Object" then
					local itemId = tonumber(currentAction.data) or 0
					if itemId > 0 then
						button.item:setItemId(itemId, true)
						if currentAction.tier and button.item.setItemTier then
							button.item:setItemTier(currentAction.tier)
						end
						button.cache.itemId = itemId
					end
				end
			end

			-- Overlay multi-action marker
			local multiOverlay = g_ui.createWidget('UIWidget', button.item.text)
			multiOverlay:setId('multiOverlay')
			multiOverlay:fill('parent')
			multiOverlay:setImageSource("/images/game/actionbar/multiicon")
			multiOverlay:setImageClip("0 0 32 32")
			multiOverlay:setPhantom(true)
		end
	end

  button.item:setDraggable(true)
  setupButtonTooltip(button, false)

  local parentButton = button:getParent()
  if parentButton then
	button.cache.buttonIndex = parentButton:getChildIndex(button)
	button.cache.buttonParent = parentButton
  end

  button.item.onDragEnter = function(self, mousePos)
    if Options.actionBar[tonumber(barID)].isLocked then
      return false
    end

	button.cooldown:setBorderWidth(1)
    button.cache.isDragging = true
	dragButton = button
	dragItem = self
    onDragItem(self, mousePos)
    return true
  end

  button.item.onDragMove = function(self, mousePos)
    if not button.cache.isDragging then
      return false
    end

    onDragItem(self, mousePos)
    return true
  end

  button.item.onDragLeave = function(self, widget, mousePos)
    if not button.cache.isDragging then
      return false
    end
    isLoaded = false
    button.cache.isDragging = false
    onDragItemLeave(self, mousePos, button)
    isLoaded = true
	dragButton = nil
	dragItem = nil
  end

  button.item.onClick = function() onExecuteAction(button) end
  button.item.text.onClick = function() onExecuteAction(button) end
  configureButtonMouseRelease(button)
  scheduleEvent(function() updateActionBar() end, 100)
end

function checkRemainSpellCooldown(button, spellId)
  if not m_settings.getOption("graphicalCooldown") and not m_settings.getOption("cooldownSecond") then
    return true
  end

  local cooldownData = spellCooldownCache[spellId]
  if not cooldownData then
    return
  end

  if (cooldownData.startTime + cooldownData.exhaustion) < g_clock.millis() then
    return
  end

  button.cache = getButtonCache(button)
  local remainTime = (cooldownData.startTime + cooldownData.exhaustion) - g_clock.millis()

  updateCooldown(button, remainTime)
  removeEvent(button.cache.removeCooldownEvent)
  button.cache.removeCooldownEvent = scheduleEvent(function() modules.game_actionbar.removeCooldown(button) end, remainTime)
end

function configureButtonMouseRelease(button)
  button.onMouseRelease = function(button, mousePos, mouseButton)
	button.cache = getButtonCache(button)
	if mouseButton == MouseRightButton then
		local menu = g_ui.createWidget('PopupMenu')
		menu:setGameMenu(true)
		menu:addOption(button.cache.isSpell and tr('Edit Spell') or tr('Assign Spell'), function() assignSpell(button) end)
		if button.item and button.item:getItemId() > 100 then
			menu:addOption(tr('Edit Object'), function() assignItem(button, button.item:getItemId()) end)
		else
			menu:addOption(tr('Assign Object'), function() assignItemEvent(button) end)
		end

		local buttonText = ""
		if button.item then
			buttonText = button.item.text:getText()
		end

		local hasEquipmentPreset = button.cache.equipmentPreset and not table.empty(button.cache.equipmentPreset)
		menu:addOption(buttonText:len() > 0 and tr('Edit Text') or tr('Assign Text'), function() assignText(button) end)
		menu:addOption(button.cache.isPassive and tr('Edit Passive Ability') or tr('Assign Passive Ability'), function() assignPassive(button) end)
		menu:addOption(button.cache.hotkey and tr('Edit Hotkey') or tr('Assign Hotkey'), function() assignHotkey(button) end)
		-- Equipment Preset removido do actionbar (opcao 'Assign/Edit Equipments' desabilitada)
		-- Multi-Action entry (ported from Luminaris)
		local hasMultiAction = multiAction_hasActions(button)
		menu:addOption(hasMultiAction and tr('Edit Multi-Action') or tr('Assign Multi-Action'), function() assignMultiAction(button) end)
		if button.cache.actionType > 0 or hasMultiAction then
			menu:addSeparator()
			menu:addOption(tr('Clear Action'), function()
				-- Clear Multi-Action persistence too
				local key = button:getId()
				if MultiActionStorage[key] then
					MultiActionStorage[key] = nil
					saveMultiActions()
				end
				button.cache.multiAction = nil
				local overlay = button.item and button.item.text and button.item.text:getChildById('multiOverlay')
				if overlay then overlay:destroy() end
				clearButton(button, true)
			end)
		end
		menu:display(mousePos)
		return true
	end
	return false
  end
end

local function getActionButtonFromWidget(widget)
  while widget do
    local id = widget:getId()
    if id and string.match(id, "^%d+%.%d+$") then
      return getButtonById(id)
    end
    widget = widget:getParent()
  end
end

function onDragItem(self, mousePos)
  self:setPhantom(true)
  self:setParent(gameRootPanel)
  self:setX(mousePos.x)
  self:setY(mousePos.y)

  self:setBorderColor('white')

  if lastHighlightWidget then
    lastHighlightWidget:setBorderWidth(0)
    lastHighlightWidget:setBorderColor('alpha')
  end

  local clickedWidget = gameRootPanel:recursiveGetChildByPos(mousePos, false)
  if not clickedWidget or not clickedWidget:backwardsGetWidgetById("tabBar") then
	return true
  end

  lastHighlightWidget = getActionButtonFromWidget(clickedWidget) or clickedWidget
  lastHighlightWidget:setBorderWidth(1)
  lastHighlightWidget:setBorderColor('white')
end

function onDragItemLeave(self, mousePos, button)
  if lastHighlightWidget then
    lastHighlightWidget:setBorderWidth(0)
    lastHighlightWidget:setBorderColor('alpha')
    lastHighlightWidget = nil
  end

  local clickedWidget = gameRootPanel:recursiveGetChildByPos(mousePos, false)
  if not clickedWidget or not clickedWidget:backwardsGetWidgetById("tabBar") then
    	resetDragWidget(self, button)
		return true
	end

  local destButton = getActionButtonFromWidget(clickedWidget)
  if not destButton then
    resetDragWidget(self, button)
    return true
  end

  if destButton == button then
    resetDragWidget(self, button)
    return true
  end

  local destButtonCache = table.recursivecopy(getButtonCache(destButton))

  button.cache = getButtonCache(button)
  local itemId = button.cache.itemId
  local destBarID, destButtonID = string.match(destButton:getId(), "(.*)%.(.*)")
  local draggedBarID, draggedButtonID = string.match(button:getId(), "(.*)%.(.*)")

  local cachedItem = cachedItemWidget[itemId]
  if cachedItem then
    for index, widget in pairs(cachedItem) do
      if button == widget then
        table.remove(cachedItem, index)
      end
	end
  end

  local cachedItem = cachedItemWidget[destButtonCache.itemId ]
  if cachedItem then
    for index, widget in pairs(cachedItem) do
      if button == widget then
        table.remove(cachedItem, index)
      end
	end
  end

  local isButtonEmpty = buttonIsEmpty(destButton)

  if button.cache.actionType == UseTypes["chatText"] then
    Options.createOrUpdateText(tonumber(destBarID), tonumber(destButtonID), button.cache.param, button.cache.sendAutomatic)
  elseif itemId ~= 0 then
    Options.createOrUpdateAction(tonumber(destBarID), tonumber(destButtonID), getActionName(button.cache.actionType), itemId, button.cache.upgradeTier, button.cache.smartMode)
  elseif button.cache.isPassive then
    Options.createOrUpdatePassive(tonumber(destBarID), tonumber(destButtonID), 1)
  elseif not table.empty(button.cache.equipmentPreset) then
    Options.createOrUpdatePreset(tonumber(destBarID), tonumber(destButtonID), button.cache.equipmentPreset, button.cache.equipmentPresetIcon)
  end

  updateButton(destButton)

  if isButtonEmpty then
    Options.removeAction(tonumber(draggedBarID), tonumber(draggedButtonID))
	removeCooldown(destButton)
    resetDragWidget(self, button)
  else
    if destButtonCache.actionType == UseTypes["chatText"] then
      Options.createOrUpdateText(tonumber(draggedBarID), tonumber(draggedButtonID), destButtonCache.param, destButtonCache.sendAutomatic)
    elseif destButtonCache.itemId ~= 0 then
      Options.createOrUpdateAction(tonumber(draggedBarID), tonumber(draggedButtonID), getActionName(destButtonCache.actionType), destButtonCache.itemId, destButtonCache.upgradeTier, destButtonCache.smartMode)
    elseif destButtonCache.isPassive then
      Options.createOrUpdatePassive(tonumber(draggedBarID), tonumber(draggedButtonID), 1)
	elseif not table.empty(destButtonCache.equipmentPreset) then
		Options.createOrUpdatePreset(tonumber(draggedBarID), tonumber(draggedButtonID), destButtonCache.equipmentPreset, destButtonCache.equipmentPresetIcon)
    end

	removeCooldown(destButton)
    resetDragWidget(self, button)
  end

  if self and not self:isDestroyed() then
    self:setBorderColor('alpha')
  end
end

function resetDragWidget(self, button)
  button.cache = getButtonCache(button)
  local cachedItem = cachedItemWidget[button.cache.itemId]
  if cachedItem then
    for index, widget in pairs(cachedItem) do
      if button == widget then
        table.remove(cachedItem, index)
      end
    end
  end

  self:destroy()
  local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")
  local style = tonumber(barID) > 3 and "SideActionButton" or "ActionButton"

  button:destroy()

  local destBar = actionBars[tonumber(barID)].tabBar
  local widget = g_ui.createWidget(style, destBar)

  if destBar then
	destBar:moveChildToIndex(widget, buttonID)
  end
  widget:setId(barID.."."..buttonID)
  updateButton(widget)
end

function buttonIsEmpty(button)
  return button.item:getItemId() == 0 and string.empty(button.item.text:getText()) and string.empty(button.item.text:getImageSource())
end

function getActionName(actionType)
  for k, v in pairs(UseTypes) do
    if v == actionType then
      return k
    end
  end
end

function removeCooldown(button)
	if not button or not button.cache then
		return true
	end

	button.cache.removeCooldownEvent = nil
	if button.cooldown then
		button.cooldown:stop()
		button.cooldown:setPercent(100)
		button.cooldown:setText("")
	end
end

function updateCooldown(button, timeMs)
	button.cooldown:showTime(m_settings.getOption("cooldownSecond"))
	button.cooldown:showProgress(m_settings.getOption("graphicalCooldown"))
	button.cooldown:setDuration(timeMs)
	button.cooldown:start()
end

function updateActionPassive(button)
	if not m_settings.getOption("graphicalCooldown") and not m_settings.getOption("cooldownSecond") then
		return true
	end

	if not button then
		for _, actionbar in pairs(activeActionBars) do
			for _, button in pairs(actionbar.tabBar:getChildren()) do
				if button.cache.isPassive then
					button.item.text.gray:setVisible(passiveData.max == 0)
				end

				if not button.cache.isPassive or button.cache.cooldownEvent ~= nil then
					goto continue
				end

				updateCooldown(button, passiveData.cooldown * 1000)
				button.cache.removeCooldownEvent = scheduleEvent(function() modules.game_actionbar.removeCooldown(button) end, passiveData.cooldown * 1000)
				:: continue ::
			end
		end
		return true
	else
		if button.cache.isPassive then
			button.item.text.gray:setVisible(passiveData.max == 0)
		end
	end

	if passiveData.max > 0 then
		removeEvent(button.cache.removeCooldownEvent)
		updateCooldown(button, passiveData.cooldown * 1000)
		button.cache.removeCooldownEvent = scheduleEvent(function() modules.game_actionbar.removeCooldown(button) end, passiveData.cooldown * 1000)
	end
end

function onUpdateLevel(localPlayer, level, levelPercent, oldLevel, oldLevelPercent)
	if level ~= oldLevel then
		onUpdateActionBarStatus()
	end
end

function onUpdateActionBarStatus()
	if #activeActionBars == 0 then
		return true
	end

	for _, actionbar in pairs(activeActionBars) do
		for _, button in pairs(actionbar.tabBar:getChildren()) do
            updateButtonState(button)
		end
	end
end

function updateActionBar(multiUseCooldown)
	for _, actionbar in pairs(activeActionBars) do
		for _, button in pairs(actionbar.tabBar:getChildren()) do
			updateButtonState(button)
			if multiUseCooldown and button.item and button.cache.itemId then
				local item = button.item:getItem()
				if item and item:isMultiUse() then
					local marketArray = {10, 12, 14}
					if table.contains(marketArray, item:getMarketData().category) then
						updateCooldown(button, multiUseCooldown)
					end
				end
			end
		end
	end
end

function onExecuteAction(button, isPress)
	local cache = getButtonCache(button)
	if cache.lastClick > g_clock.millis() then
		return true
	end

	if m_interface.gameRightPanels:isFocusable() or m_interface.gameLeftPanels:isFocusable() then
		return true
	end

	-- Multi-Action interception: cycle through assigned actions in sequence I -> II -> III -> I
	do
		local buttonIdKey = button:getId()
		local stored = MultiActionStorage[buttonIdKey]
		if stored then
			button.cache.multiAction = stored
		end
		local multiAction = button.cache.multiAction
		if multiAction and multiAction.actions and not table.empty(multiAction.actions) then
			-- Anti-hold throttle
			if button.cache.multiActionCooldown and button.cache.multiActionCooldown > g_clock.millis() then
				multiActionLog('blocked by multiActionCooldown', buttonIdKey, 'isPress=', isPress)
				return true
			end
			-- Skip key-press repeats (only execute on initial press)
			if isPress then
				button.cache.lastClick = g_clock.millis() + 150
				return true
			end

			local actions = multiAction.actions

			-- Count assigned actions for diagnostics
			local assignedCount = 0
			for i = 1, 3 do if actions[i] then assignedCount = assignedCount + 1 end end

			-- Idle reset (2s): rewind to first slot
			if multiAction.lastUsage and (g_clock.millis() - multiAction.lastUsage) > 2000 then
				multiActionLog('idle reset', buttonIdKey, 'oldIndex=', multiAction.index)
				multiAction.index = 1
			end
			multiAction.lastUsage = g_clock.millis()

			if not multiAction.index then multiAction.index = 1 end
			local currentIndex = multiAction.index
			if not actions[currentIndex] then
				multiActionLog('actions[index] nil, reset', buttonIdKey, 'index=', currentIndex, 'assigned=', assignedCount)
				currentIndex = 1; multiAction.index = 1
			end
			multiActionLog('execute', buttonIdKey, 'index=', currentIndex, 'assigned=', assignedCount)

			local action = actions[currentIndex]
			if action then
				if action.type == "Spell" then
					g_game.talk(tostring(action.data))
				elseif action.type == "Text" then
					if action.autoSend then
						g_game.talk(tostring(action.data))
					elseif modules.game_console and modules.game_console.getConsole then
						modules.game_console.getConsole():setText(tostring(action.data))
						modules.game_console.getConsole():setCursorPos(#tostring(action.data))
					end
				elseif action.type == "Object" then
					local itemId = tonumber(action.data) or 0
					if itemId > 0 then
						local subType = action.actionType
						if subType == UseTypes["UseOnYourself"] or subType == "UseOnYourself" then
							g_game.useInventoryItemWith(itemId, player)
						elseif subType == UseTypes["UseOnTarget"] or subType == "UseOnTarget" then
							local target = g_game.getAttackingCreature()
							if target then
								g_game.useInventoryItemWith(itemId, target)
							else
								m_interface.startUseWith(Item.create(itemId), -1)
							end
						elseif subType == UseTypes["Equip"] or subType == "Equip" then
							g_game.equipItemId(itemId, action.tier or 0)
						else
							g_game.useInventoryItem(itemId)
						end
					end
				end
			end

			-- Advance to the next non-empty slot (wraps around)
			currentIndex = currentIndex + 1
			if currentIndex > 3 then currentIndex = 1 end
			for _ = 1, 3 do
				if actions[currentIndex] then break end
				currentIndex = currentIndex + 1
				if currentIndex > 3 then currentIndex = 1 end
			end
			multiAction.index = currentIndex
			MultiActionStorage[buttonIdKey].index = currentIndex
			MultiActionStorage[buttonIdKey].lastUsage = multiAction.lastUsage
			multiActionLog('advance', buttonIdKey, 'nextIndex=', currentIndex)
			saveMultiActions()

			button.cache.multiActionCooldown = g_clock.millis() + 300
			button.cache.lastClick = g_clock.millis() + 150

			-- Re-render so the next action's icon shows
			updateButton(button)

			-- Schedule idle reset visual refresh
			if button.cache.idleResetEvent then
				removeEvent(button.cache.idleResetEvent)
			end
			button.cache.idleResetEvent = scheduleEvent(function()
				if multiAction.lastUsage and (g_clock.millis() - multiAction.lastUsage) >= 2000 then
					multiAction.index = 1
					if MultiActionStorage[buttonIdKey] then
						MultiActionStorage[buttonIdKey].index = 1
						saveMultiActions()
					end
					updateButton(button)
				end
			end, 2100)

			return true
		end
	end

	if not isPress then
		button.cache.nextDownKey = g_clock.millis() + 500
	end

	if isPress and button.cache.nextDownKey > g_clock.millis() then
		return true
	end

	local cooldown = isPress and 600 or 150
	button.cache.lastClick = g_clock.millis() + cooldown
	local action = button.cache.actionType
	if action == 0 then
		return true
	end

	if action == UseTypes["Equip"] and button.item then
		local smartId = getSmartCast(button.cache.itemId)

		if not smartId or not button.cache.smartMode then
			if smartId then
				if player:getInventoryCount(button.cache.itemId, button.cache.upgradeTier) == 0 then
					return
				end
			end

			g_game.equipItemId(button.cache.itemId, button.cache.upgradeTier)
		else
			local activeId = getActiveSmartCast(button.cache.itemId) or button.cache.itemId

			g_game.equipItemId(activeId, button.cache.upgradeTier)
		end
	end

	if action == UseTypes["equipmentPreset"] and button.item then
		local preset = {}
		for i, data in pairs(button.cache.equipmentPreset) do
			local slotId = tonumber(string.match(i, "%d+"))
			table.insert(preset, {slot = slotId, itemId = data.itemId, tier = data.tier, identifier = data.identifier, smartMode = data.smartMode})
		end

		g_game.sendEquipmentPreset(preset)
	end

	if action == UseTypes["Use"] and button.item then
		if (button.item:getItem():isContainer()) then
			g_game.closeContainerByItemId(button.item:getItemId())
		else
			g_game.useInventoryItem(button.item:getItemId())
		end
	end

	if action == UseTypes["UseOnYourself"] and button.item then
		g_game.useInventoryItemWith(button.item:getItemId(), player, button.item:getItemSubType() or -1)
	end

	if action == UseTypes["SmartCast"] and button.item then
		local pos = g_window.getMousePosition()
		local clickedWidget = gameRootPanel:recursiveGetChildByPos(pos, false)
		if not clickedWidget or clickedWidget:getClassName() ~= 'UIGameMap' then
			modules.game_textmessage.displayFailureMessage(tr('You can only perfom this action in game window.'))
			return
		end
		local tile = clickedWidget:getTile(pos)
		if not tile then
			modules.game_textmessage.displayFailureMessage(tr('You can only perfom this action in game window.'))
			return
		end

		local gameMapPanel = m_interface.gameMapPanel
		gameMapPanel:scheduleBlockMouseRelease(300)
		g_game.useWith(button.item:getItem(), tile:getTopUseThing(), button.item:getItemSubType() or -1)
	end

	if button.item and not g_ui.getCustomInputWidget() then
		if action == UseTypes["SelectUseTarget"] then
			m_interface.startUseWith(button.item:getItem(), button.item:getItemSubType() or - 1)
		end

		if action == UseTypes["UseOnTarget"] then
			local attackingCreature = g_game.getAttackingCreature()
			if not attackingCreature then
				m_interface.startUseWith(button.item:getItem(), button.item:getItemSubType() or - 1)
			else
				g_game.useWith(button.item:getItem(), attackingCreature, button.item:getItemSubType() or -1)
			end
		end
	end

	if action == UseTypes["chatText"] and button.cache.sendAutomatic then
    if button.cache.isSpell then
      spellGroupPressed[tostring(button.cache.primaryGroup)] = true
      g_game.talk(button.cache.param)
    else
      modules.game_console.sendMessage(button.cache.param)
    end

    modules.game_console.getConsole():setText('')
  elseif action == UseTypes["chatText"] then
  	modules.game_console.getConsole():setText(button.cache.param)
  	modules.game_console.getConsole():setCursorPos(#button.cache.param)
  end
end

function onCheckKeyUp(button)
	local cache = getButtonCache(button)
	if cache.isSpell then
		spellGroupPressed[tostring(button.cache.primaryGroup)] = nil
	end
end

function assignItemEvent(button)
	g_mouse.updateGrabber(mouseGrabberWidget, 'target')
	mouseGrabberWidget:grabMouse()
	g_mouse.pushCursor('target')
	mouseGrabberWidget.onMouseRelease = function(self, mousePosition, mouseButton) onAssignItem(self, mousePosition, mouseButton, button) end
end

function onAssignItem(self, mousePosition, mouseButton, button)
	g_mouse.updateGrabber(mouseGrabberWidget, 'target')
	mouseGrabberWidget:ungrabMouse()
	g_mouse.popCursor('target')
	mouseGrabberWidget.onMouseRelease = onDropActionButton

	local clickedWidget = gameRootPanel:recursiveGetChildByPos(mousePosition, false)
    if not clickedWidget then
		return true
	end

	local itemId = 0
	local itemTier = 0
	if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() and clickedWidget:getItem() then
		itemId = clickedWidget:getItem():getId()
		itemTier = clickedWidget:getItem():getTier()
	elseif clickedWidget:getClassName() == 'UIGameMap' then
		local tile = clickedWidget:getTile(mousePosition)
		if tile then
			itemId = tile:getTopUseThing():getId()
		end
	end

	local itemType = g_things.getThingType(itemId)
	if not itemType or not itemType:isPickupable() then
		modules.game_textmessage.displayFailureMessage(tr('Invalid object!'))
		return true
	end
	assignItem(button, itemId, itemTier)
end

-- assignSpell signature was extended with an optional `customSave`. When set,
-- the OK/Apply path calls `customSave(spellWords)` with the full spell
-- invocation string (e.g. `"exura"` or `"utevo res ina \"frog\""`) instead of
-- writing to Options.createOrUpdateText. Used by Multi-Action to store a
-- spell into MultiActionStorage[btn].actions[slot] without touching the
-- legacy single-action storage. `customSave` may also return data to merge
-- into the returned slot entry (for richer storage).
function assignSpell(button, customSave)
	local radio = UIRadioGroup.create()
	window = g_ui.loadUI('spell', g_ui.getRootWidget())
	window:show()
	g_client.setInputLockWidget(window)
	window:raise()
	scheduleEvent(function()
		window:focus()
	end, 50)
	
	window:setText("Assign Spell to Action Button ".. button:getId())

	local spells = modules.gamelib.SpellInfo['Default']
	for spellName, spellData in pairs(spells) do
		if not table.contains(spellData.vocations, translateVocation(player:getVocation())) then
			goto continue
		end

		local widget = g_ui.createWidget('SpellPreview', window.contentPanel.spellList)
		local spellId = SpellIcons[spellData.icon][1]
		local source = SpelllistSettings['Default'].iconsFolder
		local clip = Spells.getImageClipNormal(spellId, 'Default')

		-- radio
		radio:addWidget(widget)
		widget:setId(spellData.id)
		widget:setText(spellName.."\n"..spellData.words)
		widget.voc = spellData.vocations
		widget.param = spellData.parameter
		widget.source = source
		widget.clip = clip
		widget.image:setImageSource(widget.source)
		widget.image:setImageClip(widget.clip)
		if spellData.level then
			widget.levelLabel:setVisible(true)
			widget.levelLabel:setText(string.format("Level: %d", spellData.level))
			if player:getLevel() < spellData.level then
				widget.image.gray:setVisible(true)
			end
		end

		local primaryGroup = Spells.getPrimaryGroup(spellData)
		if primaryGroup ~= -1 then
			local offSet = 1
			if primaryGroup == 2 then
				offSet = (23 * (primaryGroup - 1))
			elseif primaryGroup == 3 then
				offSet = (23 * (primaryGroup - 1)) - 1
			end

			widget.imageGroup:setImageClip(offSet .. " 25 20 20")
			widget.imageGroup:setVisible(true)
		end

		:: continue ::
	end

	-- sort alphabetically
	local widgets = window.contentPanel.spellList:getChildren()
	table.sort(widgets, function(a, b) return a:getText() < b:getText() end)
	for i, widget in ipairs(widgets) do
		window.contentPanel.spellList:moveChildToIndex(widget, i)
	end

  -- edit spell
  if button.cache.spellData and not button.cache.isRuneSpell then
    local name = Spells.getSpellNameByWords(button.cache.spellData.words)
	local spellId = SpellIcons[button.cache.spellData.icon][1]
	local source = SpelllistSettings['Default'].iconsFolder
	local clip = Spells.getImageClipNormal(spellId, 'Default')

    window.contentPanel.preview:setText(name.."\n"..button.cache.spellData.words)
    window.contentPanel.preview.image:setImageSource(source)
    window.contentPanel.preview.image:setImageClip(clip)

    window.contentPanel.paramLabel:setOn(button.cache.spellData.parameter)
    window.contentPanel.paramText:setEnabled(button.cache.spellData.parameter)
    if button.cache.spellData.parameter then
      window.contentPanel.paramText:setText(button.cache.castParam)
	  if button.cache.castParam then
	  	window.contentPanel.paramText:setCursorPos(#button.cache.castParam)
	  end
    end

    for i, k in pairs(window.contentPanel.spellList:getChildren()) do
      if k:getId() == tostring(button.cache.spellData.id) then
        radio:selectWidget(window.contentPanel.spellList:getChildren()[i])
        window.contentPanel.spellList:ensureChildVisible(window.contentPanel.spellList:getChildren()[i])
        break
      end
    end
  end

	-- callback
	radio.onSelectionChange = function(widget, selected)
		if selected and window.contentPanel then
			window.contentPanel.preview:setText(selected:getText())
			window.contentPanel.preview.image:setImageSource(selected.source)
			window.contentPanel.preview.image:setImageClip(selected.clip)
			window.contentPanel.paramLabel:setOn(selected.param)
			window.contentPanel.paramText:setEnabled(selected.param)
			window.contentPanel.paramText:clearText()
			if selected:getText():lower():find("levitate") then
				window.contentPanel.paramText:setText("up|down")
			end
			window.contentPanel.spellList:ensureChildVisible(widget)
		end
	end

	if window.contentPanel.spellList:getChildren() and not button.cache.spellData then
		radio:selectWidget(window.contentPanel.spellList:getChildren()[1])
	end

  local cancelFunc = function()
		g_client.setInputLockWidget(nil)
		safeDestroyWindow()
	end

	local okFunc = function(destroy)
		local selected = radio:getSelectedWidget()
		if not selected then cancelFunc() return end

	  	local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")
		local param = string.match(selected:getText(), "\n(.*)")
		local paramText = window.contentPanel.paramText:getText()

		local check = (param .. " " .. paramText)
		if string.find(check, "utevo res ina") then
			param = "utevo res ina"
			paramText = string.gsub(paramText, "ina ", "")
		end

		if paramText:lower():find("up|down") then
			window.contentPanel.paramText:setText("")
		end
		if not string.empty(paramText) then
			param = param .. ' "' .. paramText:gsub('"', '') .. '"'
		end

		if customSave then
			-- Multi-Action path: hand the chosen invocation string off to the
			-- caller's storage instead of poking the legacy single-action slot.
			customSave(param)
		else
			Options.createOrUpdateText(tonumber(barID), tonumber(buttonID), param, true)
			updateButton(button)
		end

		if destroy then
			g_client.setInputLockWidget(nil)
			safeDestroyWindow()
		end
	end

	window.contentPanel.buttonOk.onClick = function() okFunc(true) end
	window.contentPanel.buttonApply.onClick = function() okFunc(false) end
	window.contentPanel.buttonClose.onClick = cancelFunc
	window.onEnter = function() okFunc(true) end
	window.onEscape = cancelFunc

	local actionbar = button:getParent():getParent()
	if actionbar.locked then
		cancelFunc()
	end
end

-- Same hook as assignSpell: if `customSave` is provided, the assign window
-- doesn't write to the legacy single-action slot; it just hands the chosen
-- text and the auto-say flag to the caller (Multi-Action uses this).
function assignText(button, customSave)
	window = g_ui.loadUI('text', g_ui.getRootWidget())
	window:show()
	g_client.setInputLockWidget(window)
	window:raise()
	scheduleEvent(function()
		window:focus()
	end, 50)

	window:setText("Assign Text to Action Button ".. button:getId())
	window.contentPanel.text.onTextChange = function(self, text)
		window.contentPanel.buttonOk:setEnabled(text:len() > 0)
		window.contentPanel.buttonApply:setEnabled(text:len() > 0)
	end

	window.contentPanel.checkPanel.tick:setChecked(true)
	-- When invoked for a Multi-Action slot, the button's legacy cache.param is
	-- usually empty/irrelevant; default to empty text so the field starts blank.
	local initialText = (customSave and '') or (button.cache and button.cache.param) or ''
	window.contentPanel.text:setText(initialText)
	window.contentPanel.text:setCursorPos(#initialText)
	if #window.contentPanel.text:getText() > 0 then
		window.contentPanel.checkPanel.tick:setChecked(button.cache.sendAutomatic)
	end

	local okFunc = function(destroy)
		local autoSay = window.contentPanel.checkPanel.tick:isChecked()
		local text = window.contentPanel.text:getText()
		local fomartedText = Spells.getSpellFormatedName(text)
		if customSave then
			customSave(fomartedText, autoSay)
		else
			local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")
			Options.createOrUpdateText(tonumber(barID), tonumber(buttonID), fomartedText, autoSay)
			updateButton(button)
		end

		if destroy then
			g_client.setInputLockWidget(nil)
			safeDestroyWindow()
		end
	end

	local cancelFunc = function()
		g_client.setInputLockWidget(nil)
		safeDestroyWindow()
	end

	window.contentPanel.buttonOk.onClick = function() okFunc(true) end
	window.contentPanel.buttonApply.onClick = function() okFunc(false) end
	window.contentPanel.buttonClose.onClick = cancelFunc
	window.onEscape = cancelFunc
	window.onEnter = function() okFunc(true) end
	window:insertLuaCall('onEnter')
	window:insertLuaCall('onEscape')

	local actionbar = button:getParent():getParent()
	if actionbar.locked then
		cancelFunc()
	end
end

function assignItem(button, itemId, itemTier, dragEvent)
	if not isLoaded then
		return true
	end

	if not button.item then
		updateButton(button)
		return
	end

	local actionbar = button:getParent():getParent()
	if dragEvent and actionbar.locked or actionbar.locked then
		updateButton(button)
		return
	end

	local radio = UIRadioGroup.create()
	local item = button.item:getItem()
	local id = button.item:getItemId()

	if window then
		safeDestroyWindow()
	end

	window = g_ui.loadUI('object', g_ui.getRootWidget())
	window:show()
	g_client.setInputLockWidget(window)
	window:raise()
	scheduleEvent(function()
		window:focus()
	end, 50)

	window:setText("Assign Object to Action Button " .. button:getId())
	window:setId("assignItemWindow")

	window.contentPanel.select.onClick = function()
		safeDestroyWindow()
		assignItemEvent(button)
	end

	local fromSelect = false
	if button.item:getItemId() > 0 and button.item:getItemId() ~= itemId then
		fromSelect = true
	end

	window.contentPanel.item:setItemId(itemId)
	if not item then
		item = window.contentPanel.item:getItem()
	end

	if window.contentPanel.item:getItem() then
		window.contentPanel.item:getItem():setTier(itemTier)
	end

	-- ativar smart object (se tem cloth e se tem wearout)
	window.contentPanel.checks.smart:setVisible(false)
	if (item:getClothSlot() > 0 and (item:hasExpireStop() or getSmartCast(item:getId()))) then
		window.contentPanel.checks.smart:setVisible(true)
		if button.cache.smartMode and button.cache.smartMode == true then
			window.contentPanel.checks.smart:setChecked(true)
		end
	end

	for i, child in ipairs(window.contentPanel.checks:getChildren()) do
		if i == 6 then
			goto continue
		end

		radio:addWidget(child)
		child:setEnabled(false)

		if i <= 4 and item:isMultiUse() then
			child:setEnabled(true)
			if not radio:getSelectedWidget() and not (item:getClothSlot() > 0 or (item:getClothSlot() == 0 and item:getClassification() > 0)) then
				if fromSelect or button.cache.actionType == 0 or button.cache.actionType == i or (button.cache.actionType and button.cache.actionType == 6) then
					radio:selectWidget(child)
				end
			end
		end

		if (i == 5 and canEquipItem(item)) then
			child:setEnabled(true)
			if not radio:getSelectedWidget() then
				if fromSelect or button.cache.actionType == 0 or button.cache.actionType == i or (button.cache.actionType and button.cache.actionType == 6) then
					radio:selectWidget(child)
				end
			end
		end

		if i == 7 and item:isUsable() and not item:isMultiUse() then
			child:setEnabled(true)
			if not radio:getSelectedWidget() then
				if fromSelect or button.cache.actionType == 0 or button.cache.actionType == i - 1 or (button.cache.actionType and button.cache.actionType == 6) then
					radio:selectWidget(child)
				end
			end
		end

		child.onCheckChange = function(self)
			if self:getId() == "Equip" and not window.contentPanel.checks.smart:isEnabled() then
				window.contentPanel.checks.smart:setEnabled(true)
			elseif self:getId() ~= "Equip" and window.contentPanel.checks.smart:isEnabled() then
				window.contentPanel.checks.smart:setChecked(false)
				window.contentPanel.checks.smart:setEnabled(false)
			end
		end

		:: continue ::
	end

	window.contentPanel.buttonOk:setEnabled(item and item:getId() > 100)
	window.contentPanel.buttonApply:setEnabled(item and item:getId() > 100)

	itemTier = not itemTier and button.cache.upgradeTier or itemTier
	window.contentPanel.tier:setVisible(itemTier and itemTier > 0 or false)
	if itemTier and itemTier > 1 then
		window.contentPanel.tier:setImageClip(18 * (itemTier - 1) .. " 0 18 16")
	end

	if not radio:getSelectedWidget() then
		radio:selectWidget(window.contentPanel.checks:getFirstChild())
	end

	local okFunc = function(destroy)
		local selected = radio:getSelectedWidget():getId()
		local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")

		local cache = getButtonCache(button)
		local cachedItem = cachedItemWidget[cache.itemId]
		if cachedItem then
			for index, widget in pairs(cachedItem) do
				if button == widget then
					table.remove(cachedItem, index)
				end
			end
		end

		if item:getClassification() == 0 then
			itemTier = nil
		end

		local smartMode = nil
		if window.contentPanel.checks.smart:isVisible() then
			smartMode = window.contentPanel.checks.smart:isChecked()
		end

		Options.createOrUpdateAction(tonumber(barID), tonumber(buttonID), selected, itemId, itemTier, smartMode)
		updateButton(button)

		if destroy then
			g_client.setInputLockWidget(nil)
			safeDestroyWindow()
			radio:destroy()
		end
	end

	local cancelFunc = function()
		g_client.setInputLockWidget(nil)
		updateButton(button)
		safeDestroyWindow()
		radio:destroy()
	end

	window.contentPanel.buttonOk.onClick = function() okFunc(true) end
	window.onEnter = function() okFunc(true) end
	window.contentPanel.buttonApply.onClick = function() okFunc(false) end
	window.contentPanel.buttonClose.onClick = cancelFunc
	window.onEscape = cancelFunc
	window:insertLuaCall('onEnter')

	local actionbar = button:getParent():getParent()
	if actionbar.locked then
		g_client.setInputLockWidget(nil)
		cancelFunc()
	end
end

function assignHotkey(button)
	window = g_ui.loadUI('hotkey', g_ui.getRootWidget())
	window:show()
	g_client.setInputLockWidget(window)
	window:raise()
	window:focus()

	local barN = button:getParent():getParent().n
	local barDesc
	if barN < 4 then
		barDesc = "Bottom"
	elseif barN < 7 then
		barDesc = "Left"
	else
		barDesc = "Right"
	end

	barDesc = barDesc .. " Action Bar: Action Button " .. button:getId()
	window:setText('Edit Hotkey for "' .. barDesc)
	window.desc:setText(window.desc:getText() .. barDesc .. '"')
	window.display:setText(button.cache.hotkey or "")

	local chatOn = Options.isChatOnEnabled
	if chatOn then
		window.chatMode:setText("Mode: \"Chat On\"")
	else
		window.chatMode:setText("Mode: \"Chat Off\"")
	end

	window:grabKeyboard()
	window.onKeyDown = function(window, keyCode, keyboardModifiers, keyText) manageKeyPress(window, keyCode, keyboardModifiers, keyText) end

	local okFunc = function()
		local lastHotkey = button.cache.hotkey or ""
		if lastHotkey ~= "" then
			local usedButton = getUsedHotkeyButton(lastHotkey)
			if usedButton then
				Options.removeHotkey(usedButton:getId())
				g_keyboard.unbindKeyPress(lastHotkey, nil, gameRootPanel)
				g_keyboard.unbindKeyDown(lastHotkey, nil, gameRootPanel)
				updateButton(usedButton)
			end
		end

		local hotkey = window.display.combo
		if hotkey == nil or #hotkey == 0 then
			if button.cache.hotkey ~= "" then
				local hk = button.cache.hotkey
				Options.removeHotkey(button:getId())
				g_keyboard.unbindKeyPress(hk, nil, gameRootPanel)
				g_keyboard.unbindKeyDown(hk, nil, gameRootPanel)
				updateButton(button)
			end
			g_client.setInputLockWidget(nil)
			safeDestroyWindow()
			return true
		end

    Options.clearHotkey(hotkey)

		local usedButton = getUsedHotkeyButton(hotkey)
		if usedButton then
			Options.removeHotkey(usedButton:getId())
			g_keyboard.unbindKeyPress(hotkey, nil, gameRootPanel)
			g_keyboard.unbindKeyDown(hotkey, nil, gameRootPanel)
		    updateButton(usedButton)
		end

		if KeyBinds:hotkeyIsUsed(hotkey) and hotkey ~= '' then
			local key = KeyBind:getKeyBindByHotkey(hotkey)
			Options.removeActionHotkey(chatOn and "chatOn" or "chatOff", key.jsonName)
			if key then
				key:setFirstKey('')
				g_keyboard.unbindKeyDown(hotkey, nil, gameRootPanel)
				g_keyboard.unbindKeyPress(hotkey, nil, gameRootPanel)
			end
		end

		if m_settings.hotkeyIsUsed(hotkey) then
			m_settings.removeCustomHotkey(hotkey)
		end

		g_keyboard.bindKeyPress(hotkey, function() onExecuteAction(button, true) end, gameRootPanel)
		g_keyboard.bindKeyDown(hotkey, function() onExecuteAction(button, false) end, gameRootPanel)
		button.cache.hotkey = hotkey
		Options.updateActionBarHotkey("TriggerActionButton_".. button:getId(), hotkey)
		updateButton(button)
		g_client.setInputLockWidget(nil)
		safeDestroyWindow()
	end

	local clearFunc = function()
		local hotkey = window.display:getText()
		Options.removeHotkey(button:getId())
		if hotkey ~= '' then
			g_keyboard.unbindKeyPress(hotkey, nil, gameRootPanel)
			g_keyboard.unbindKeyDown(hotkey, nil, gameRootPanel)
		end
		g_client.setInputLockWidget(nil)
		updateButton(button)
		window.display:setText('')
		safeDestroyWindow()
	end

	local closeFunc = function()
		g_client.setInputLockWidget(nil)
		safeDestroyWindow()
	end

	window.buttonOk.onClick = okFunc
	window.buttonClear.onClick = clearFunc
	window.buttonClose.onClick = closeFunc

	local actionbar = button:getParent():getParent()
	if actionbar.locked then
		g_client.setInputLockWidget(nil)
		closeFunc()
	end
end

function assignPassive(button)
	local radio = UIRadioGroup.create()
	window = g_ui.loadUI('passive', g_ui.getRootWidget())
	window:show()
	g_client.setInputLockWidget(window)
	window:raise()
	scheduleEvent(function()
		window:focus()
	end, 50)

	window:setText("Assign Passive to Action Button ".. button:getId())

	for id, passiveData in pairs(PassiveAbilities) do
		local widget = g_ui.createWidget('PassivePreview', window.contentPanel.passiveList)
		radio:addWidget(widget)
		widget:setId(id)
		widget:setText(passiveData.name)
		widget.image:setImageSource(passiveData.icon)
		widget.source = passiveData.icon
		:: continue ::
	end

	radio.onSelectionChange = function(widget, selected)
		if selected then
			window.contentPanel.preview:setText(selected:getText())
			window.contentPanel.preview.image:setImageSource(selected.source)
			window.contentPanel.passiveList:ensureChildVisible(widget)
		end
	end

	if window.contentPanel.passiveList:getChildren() then
		radio:selectWidget(window.contentPanel.passiveList:getChildren()[1])
		window.contentPanel.preview:setColor("$var-text-cip-color")
	end

	local okFunc = function(destroy)
		local selected = radio:getSelectedWidget()
		if not selected then return end

	  local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")
		Options.createOrUpdatePassive(tonumber(barID), tonumber(buttonID), tonumber(selected:getId()))
		updateButton(button)

		if destroy then
			g_client.setInputLockWidget(nil)
			safeDestroyWindow()
		end
	end

	local cancelFunc = function()
		g_client.setInputLockWidget(nil)
		safeDestroyWindow()
	end

	window.contentPanel.buttonOk.onClick = function() okFunc(true) end
	window.contentPanel.buttonApply.onClick = function() okFunc(false) end
	window.contentPanel.buttonClose.onClick = cancelFunc
	window.onEnter = function() okFunc(true) end
	window.onEscape = cancelFunc
	window:insertLuaCall('onEnter')

	local actionbar = button:getParent():getParent()
	if actionbar.locked then
		g_client.setInputLockWidget(nil)
		cancelFunc()
	end
end

function manageKeyPress(window, keyCode, keyboardModifiers, keyText)
	local keyCombo = determineKeyComboDesc(keyCode, keyboardModifiers, keyText)
	local resetCombo = {"Shift", "Ctrl", "Alt"}
    if table.contains(resetCombo, keyCombo) then
		window.display:setText('')
		window.warning:setVisible(false)
		window.buttonOk:setEnabled(true)
      	return true
    end

	local shortCut = (keyCombo == "HalfQuote" and "'" or keyCombo)
	window.display:setText(shortCut)
	window.display.combo = keyCombo
	window.warning:setVisible(false)
	window.buttonOk:setEnabled(true)
	if isHotkeyUsed(keyCombo) then
		window.warning:setVisible(true)
		window.warning:setText("This hotkey is already in use and will be overwritten.")
	end

	if table.contains(blockedKeys, keyCombo) then
		window.warning:setVisible(true)
		window.warning:setText("This hotkey is already in use and cannot be overwritten.")
		window.buttonOk:setEnabled(false)
	end
	return true
end

function clearButton(button, removeAction)
	local hotkey = button.cache.hotkey

	if button.cache.cooldownEvent then
	  removeEvent(button.cache.cooldownEvent)
	end

  	removeCooldown(button)
	resetButtonCache(button)

	if hotkey then
		button.cache.hotkey = hotkey
		button.hotkeyLabel:setText(translateDisplayHotkey(button.cache.hotkey))
	end

	setupButtonTooltip(button, true)
	if removeAction then
		local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")
		Options.removeAction(tonumber(barID), tonumber(buttonID))
	end
end

-- ============================================================
-- Multi-Action assignment (ported from Luminaris)
-- Uses simple inline prompts (OTCV8 assignSpell/Text/Item do not take callbacks)
-- ============================================================

-- Mouse-grabber based item picker for multi-action slot
local function multiAction_pickItem(button, callback)
	isAssigningObject = true
	if g_mouse and g_mouse.updateGrabber then
		g_mouse.updateGrabber(mouseGrabberWidget, 'target')
	end
	mouseGrabberWidget:grabMouse()
	g_mouse.pushCursor('target')
	mouseGrabberWidget.onMouseRelease = function(self, mousePosition, mouseButton)
		isAssigningObject = false
		mouseGrabberWidget:ungrabMouse()
		g_mouse.popCursor('target')
		-- Restore original drop handler
		mouseGrabberWidget.onMouseRelease = onDropActionButton

		local clickedWidget = gameRootPanel:recursiveGetChildByPos(mousePosition, false)
		if not clickedWidget then return true end

		local itemId, itemTier = 0, 0
		if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() and clickedWidget:getItem() then
			itemId = clickedWidget:getItem():getId()
			if clickedWidget:getItem().getTier then
				itemTier = clickedWidget:getItem():getTier() or 0
			end
		elseif clickedWidget:getClassName() == 'UIGameMap' then
			local tile = clickedWidget:getTile(mousePosition)
			if tile and tile:getTopUseThing() then
				itemId = tile:getTopUseThing():getId()
			end
		end

		local itemType = g_things.getThingType(itemId)
		if not itemType or not itemType:isPickupable() then
			if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
				modules.game_textmessage.displayFailureMessage(tr('Invalid object!'))
			end
			return true
		end

		if callback then
			callback(itemId, itemTier)
		end
	end
end

-- Open a tiny modal to ask for a string (used by Spell/Text slot assignment)
local function multiAction_promptText(title, defaultText, onAccept)
	local w = g_ui.createWidget('MainWindow', g_ui.getRootWidget())
	w:setId('multiActionPrompt')
	if w.setText then w:setText(title) end
	w:setSize({width = 320, height = 130})

	local label = g_ui.createWidget('Label', w)
	label:setId('promptLabel')
	label:setText(tr('Enter the spell words or text to send'))
	label:addAnchor(AnchorTop, 'parent', AnchorTop)
	label:addAnchor(AnchorLeft, 'parent', AnchorLeft)
	label:setMarginTop(28)
	label:setMarginLeft(8)

	local edit = g_ui.createWidget('TextEdit', w)
	edit:setId('promptEdit')
	edit:setSize({width = 300, height = 22})
	edit:addAnchor(AnchorTop, 'promptLabel', AnchorBottom)
	edit:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
	edit:setMarginTop(6)
	edit:setText(defaultText or "")

	local check = g_ui.createWidget('CheckBox', w)
	check:setId('promptCheck')
	check:setText(tr('Send automatically'))
	check:setChecked(true)
	check:addAnchor(AnchorTop, 'promptEdit', AnchorBottom)
	check:addAnchor(AnchorLeft, 'parent', AnchorLeft)
	check:setMarginTop(6)
	check:setMarginLeft(8)
	check:setWidth(200)

	local okBtn = g_ui.createWidget('Button', w)
	okBtn:setId('promptOk')
	okBtn:setText(tr('OK'))
	okBtn:setWidth(60)
	okBtn:addAnchor(AnchorBottom, 'parent', AnchorBottom)
	okBtn:addAnchor(AnchorRight, 'parent', AnchorRight)
	okBtn:setMarginBottom(8)
	okBtn:setMarginRight(8)

	local cancelBtn = g_ui.createWidget('Button', w)
	cancelBtn:setId('promptCancel')
	cancelBtn:setText(tr('Cancel'))
	cancelBtn:setWidth(60)
	cancelBtn:addAnchor(AnchorBottom, 'parent', AnchorBottom)
	cancelBtn:addAnchor(AnchorRight, 'promptOk', AnchorLeft)
	cancelBtn:setMarginBottom(8)
	cancelBtn:setMarginRight(6)

	local close = function() if w and not w:isDestroyed() then w:destroy() end end
	cancelBtn.onClick = close
	okBtn.onClick = function()
		local text = edit:getText()
		local autoSend = check:isChecked()
		close()
		if text and #text > 0 and onAccept then
			onAccept(text, autoSend)
		end
	end
	w.onEscape = close
	scheduleEvent(function() if edit and not edit:isDestroyed() then edit:focus() end end, 50)
end

-- Build a small visual preview of a Multi-Action slot
local function multiAction_updateSlotVisual(slot, actionData)
	if not slot then return end
	if not actionData then
		slot:setTooltip("")
		if slot.setImageSource then
			slot:setImageSource('/images/game/actionbar/actionbarslot')
			slot:setImageClip("0 0 32 32")
		end
		if slot.setItemId then slot:setItemId(0) end
		return
	end

	if actionData.type == "Spell" then
		slot:setTooltip("Cast " .. tostring(actionData.data))
		local spellData = Spells.getSpellDataByParamWords(tostring(actionData.data):lower())
		if spellData and SpellIcons and SpellIcons[spellData.icon] then
			local spellId = SpellIcons[spellData.icon][1]
			local source = SpelllistSettings['Default'].iconsFolder
			local clip = Spells.getImageClipNormal(spellId, 'Default')
			if slot.setImageSource then
				slot:setImageSource(source)
				slot:setImageClip(clip)
			end
		else
			slot:setImageSource('/images/game/actionbar/actionbarslot')
		end
	elseif actionData.type == "Text" then
		slot:setTooltip('Say: "' .. tostring(actionData.data) .. '"')
		slot:setImageSource('/images/game/actionbar/actionbarslot')
	elseif actionData.type == "Object" then
		slot:setTooltip("Use Item ID: " .. tostring(actionData.data))
		if slot.setItemId then
			slot:setItemId(tonumber(actionData.data) or 0)
			if actionData.tier and slot.setItemTier then
				slot:setItemTier(actionData.tier)
			end
		end
	end
end

function assignMultiAction(button)
	if window then
		safeDestroyWindow()
		window = nil
	end

	-- Close any previously-open Multi-Action window (re-entrancy).
	if multiActionWindow and not multiActionWindow:isDestroyed() then
		multiActionWindow:destroy()
	end
	multiActionWindow = nil

	-- IMPORTANT: keep the Multi-Action window in a CLOSURE-LOCAL variable, not
	-- the shared module `window`. The sub-pickers (assignSpell/assignText/
	-- multiAction_pickItem) reuse the global `window` and nil it when they
	-- close — if the slot handlers referenced the global, right-clicking a
	-- second slot after assigning a spell would index a nil window and throw,
	-- which is exactly why "pick another action" stopped working.
	local maWin = g_ui.loadUI('multiaction', g_ui.getRootWidget())
	multiActionWindow = maWin
	maWin:show()
	maWin:raise()
	maWin:focus()

	-- Position above the button
	local buttonPos = button:getPosition()
	local targetPos = {x = buttonPos.x, y = buttonPos.y - maWin:getHeight()}
	maWin:setPosition(targetPos)
	scheduleEvent(function()
		if maWin and not maWin:isDestroyed() then
			maWin:setPosition(targetPos)
			if maWin.bindRectToParent then maWin:bindRectToParent() end
		end
	end, 50)

	maWin.onEscape = function()
		if maWin and not maWin:isDestroyed() then
			maWin:destroy()
		end
	end

	-- Keep window alive while a sub-popup (right-click menu, Assign Spell/Text
	-- input boxes) is open. The OTCV8 right-click flow pops a PopupMenu which
	-- can steal focus from `window`, so we DON'T auto-close on focus loss —
	-- the user dismisses via Esc, the close button, or by re-clicking the
	-- action bar button.
	maWin.lockFocus = false

	local buttonIdKey = button:getId()
	if not MultiActionStorage[buttonIdKey] then
		MultiActionStorage[buttonIdKey] = {actions = {}, index = 1}
	end
	if not MultiActionStorage[buttonIdKey].actions then
		MultiActionStorage[buttonIdKey].actions = {}
	end
	if not MultiActionStorage[buttonIdKey].index then
		MultiActionStorage[buttonIdKey].index = 1
	end

	button.cache.multiAction = MultiActionStorage[buttonIdKey]
	updateButton(button)

	for i = 1, 3 do
		local slot = maWin:recursiveGetChildById('slot' .. i)
		if slot then
			multiAction_updateSlotVisual(slot, MultiActionStorage[buttonIdKey].actions[i])

			slot.onMouseRelease = function(widget, mousePos, mouseButton)
				if mouseButton ~= MouseRightButton then return end
				maWin.lockFocus = true

				local menu = g_ui.createWidget('PopupMenu')
				menu:setGameMenu(true)
				menu.onDestroy = function()
					if maWin and not maWin:isDestroyed() then maWin.lockFocus = false end
				end

				menu:addOption(tr('Assign Spell'), function()
					-- Use the real OTCV8 spell.otui picker so the player sees the
					-- same list of spells they're used to, with icons and
					-- parameter input. The customSave hook stores the chosen
					-- invocation into our Multi-Action slot instead of the
					-- legacy single-action storage.
					maWin.lockFocus = true
					assignSpell(button, function(words)
						MultiActionStorage[buttonIdKey].actions[i] = {type = "Spell", data = words, autoSend = true}
						button.cache.multiAction = MultiActionStorage[buttonIdKey]
						saveMultiActions()
						multiAction_updateSlotVisual(slot, MultiActionStorage[buttonIdKey].actions[i])
						updateButton(button)
						if maWin and not maWin:isDestroyed() then maWin.lockFocus = false end
					end)
				end)

				menu:addOption(tr('Assign Text'), function()
					-- Same trick for plain text actions.
					maWin.lockFocus = true
					assignText(button, function(text, autoSend)
						MultiActionStorage[buttonIdKey].actions[i] = {type = "Text", data = text, autoSend = autoSend}
						button.cache.multiAction = MultiActionStorage[buttonIdKey]
						saveMultiActions()
						multiAction_updateSlotVisual(slot, MultiActionStorage[buttonIdKey].actions[i])
						updateButton(button)
						if maWin and not maWin:isDestroyed() then maWin.lockFocus = false end
					end)
				end)

				menu:addOption(tr('Assign Object'), function()
					multiAction_pickItem(button, function(itemId, itemTier)
						MultiActionStorage[buttonIdKey].actions[i] = {
							type = "Object", data = itemId, tier = itemTier, actionType = UseTypes["Use"]
						}
						button.cache.multiAction = MultiActionStorage[buttonIdKey]
						saveMultiActions()
						multiAction_updateSlotVisual(slot, MultiActionStorage[buttonIdKey].actions[i])
						updateButton(button)
					end)
				end)

				if MultiActionStorage[buttonIdKey].actions[i] then
					menu:addSeparator()
					menu:addOption(tr('Clear Slot'), function()
						MultiActionStorage[buttonIdKey].actions[i] = nil
						saveMultiActions()
						multiAction_updateSlotVisual(slot, nil)
						updateButton(button)
					end)
				end

				menu:display(mousePos)
			end
		end
	end
end

function playerCanUseSpell(spellData)
	if not g_game.isOnline() then
		return
	end

	if not spellData then
		return false
	end

	if spellData.special and not spellModification[tostring(spellData.id)] then
		return false
	end

	if spellData.needLearn and not spellListData[tostring(spellData.id)] then
		return false
	end

	if spellData.mana and (player:getMana() < spellData.mana) then
		return false
	end

	if spellData.level and (player:getLevel() < spellData.level) then
		return false
	end

	if spellData.soul and (player:getSoul() < spellData.soul) then
		return false
	end

	if spellData.vocations and (not table.contains(spellData.vocations, translateVocation(player:getVocation()))) then
		return false
	end

	return true
end

function getItemNameById(itemId)
	for _, k in pairs(hotkeyItemList) do
		local item = k[1]
		if item:getId() == itemId then
			return k[2]
		end
	end
	return "this object"
end

function setupHotkeyButton(button)
	if not Options.currentHotkeySet then
		return
	end

	local currentSet = Options.isChatOnEnabled and Options.currentHotkeySet["chatOn"] or Options.currentHotkeySet["chatOff"]
	for _, data in pairs(currentSet) do
		if data["actionsetting"] then
			if data["actionsetting"]["action"] == "TriggerActionButton_" .. button:getId() then
				local keySequence = data["keysequence"]
				if keySequence and not string.empty(keySequence) then
					if not data["secondary"] then
						button.cache.hotkey = keySequence
					end

					g_keyboard.unbindKeyPress(keySequence, nil, gameRootPanel)
					g_keyboard.unbindKeyDown(keySequence, nil, gameRootPanel)
					g_keyboard.unbindKeyUp(keySequence, nil, gameRootPanel)

					g_keyboard.bindKeyPress(keySequence, function() onExecuteAction(button, true) end, gameRootPanel)
					g_keyboard.bindKeyDown(keySequence, function() onExecuteAction(button, false) end, gameRootPanel)
					g_keyboard.bindKeyUp(keySequence, function() onCheckKeyUp(button) end, gameRootPanel)
				end
			end
		end
	end
end

function isHotkeyUsed(key, secondary)
	if not secondary then
		secondary = false
	end

	if not key or not Options.currentHotkeySet then
		return false
	end

	local currentSet = Options.isChatOnEnabled and Options.currentHotkeySet["chatOn"] or Options.currentHotkeySet["chatOff"]
	for _, data in pairs(currentSet) do
		if data["actionsetting"] and data["keysequence"] then
			if secondary and data["secondary"] and data["keysequence"]:lower() == key:lower() then
				return true
			end

			if not secondary and not data["secondary"] and data["keysequence"]:lower() == key:lower() then
				return true
			end
		end
	end
	return false
end

function isHotkeyUsedByChat(key, chatType)
	if not key or not Options.currentHotkeySet then
		return false
	end
	local currentSet = Options.currentHotkeySet[chatType]
	for _, data in pairs(currentSet) do
		if data["actionsetting"] and data["keysequence"] then
			if data["keysequence"]:lower() == key:lower() then
				return true
			end
		end
	end
	return false
end

function getUsedHotkeyButton(key)
	for _, actionbar in pairs(activeActionBars) do
		for _, button in pairs(actionbar.tabBar:getChildren()) do
			local hotkey = button.cache.hotkey
			if hotkey and hotkey:lower() == key:lower() then
				return button
			end
		end
	end
	return nil
end

function switchChatMode(enabled)
	Options.setChatMode(enabled)
	KeyBinds:setupAndReset(Options.currentHotkeySetName, enabled and "chatOn" or "chatOff")

	for _, actionbar in pairs(activeActionBars) do
		for _, button in pairs(actionbar.tabBar:getChildren()) do
			if button.cache.hotkey ~= "" then
				g_keyboard.unbindKeyPress(button.cache.hotkey, nil, gameRootPanel)
				g_keyboard.unbindKeyDown(button.cache.hotkey, nil, gameRootPanel)
				button.cache.hotkey = nil
				button.hotkeyLabel:setText("")
			end
		end
	end

	-- insert new ones
	for _, actionbar in pairs(activeActionBars) do
		for _, button in pairs(actionbar.tabBar:getChildren()) do
			setupHotkeyButton(button)
			if button.cache.hotkey then
				button.hotkeyLabel:setText(translateDisplayHotkey(button.cache.hotkey))
			end
		end
	end
	m_settings.CustomHotkeys.createList(true)
end

function updateVisibleWidgets()
	for _, actionBar in pairs(actionBars) do
		if actionBar:isVisible() then
			local tabBar = actionBar.tabBar
			local children = tabBar:getChildren()
			local dimension = actionBar.isVertical and tabBar:getHeight() or tabBar:getWidth()
			local visibleCount = math.max(1, math.floor(dimension / 36))
			local firstIndex = actionBar.firstVisibleIndex or 1

			for i, button in ipairs(children) do
				if i >= firstIndex and i < firstIndex + visibleCount then
					button:setVisible(true)
					actionBar.lastVisibleIndex = i
				else
					button:setVisible(false)
				end
			end

			-- Wire a geometry watcher once per bar so resizes (after the
			-- bottom splitter or side panel loads its saved position) re-run
			-- the visibility math instead of leaving the bar "cut in half".
			if not actionBar.geometryWatchInstalled then
				actionBar.geometryWatchInstalled = true
				local lastDim = dimension
				local recompute = function()
					if not actionBar or actionBar:isDestroyed() or not actionBar:isVisible() then return end
					local currentDim = actionBar.isVertical and actionBar.tabBar:getHeight() or actionBar.tabBar:getWidth()
					if currentDim ~= lastDim then
						lastDim = currentDim
						updateVisibleWidgets()
					end
				end
				connect(actionBar.tabBar, { onGeometryChange = recompute })
				connect(actionBar, { onGeometryChange = recompute })
			end
		end
	end
end

local function getFirstVisibleButton(actionBar)
	for _, button in ipairs(actionBar.tabBar:getChildren()) do
		if button:isVisible() then
			return button
		end
	end
	return nil
end

local function getNextInvisibleChild(actionBar, firstIndex)
	for i, button in ipairs(actionBar.tabBar:getChildren()) do
		if i >= firstIndex and not button:isVisible() then
			return button
		end
	end
	return nil
end

local function getPrevInvisibleButton(actionBar)
	local lastButton = nil
	for _, button in ipairs(actionBar.tabBar:getChildren()) do
		if button:isVisible() then
			return lastButton
		end
		lastButton = button
	end
	return nil
end

local function getLastVisibleButton(actionBar)
	for _, button in ipairs(actionBar.tabBar:getReverseChildren()) do
		if button:isVisible() then
			return button
		end
	end
	return nil
end

function moveActionButtons(widget)
	local dir = widget:getId()
	local actionBar = widget:getParent():getParent()
	local scroll = actionBar.actionScroll
	local tabBar = actionBar.tabBar
	local buttons = { actionBar.prevPanel.prev, actionBar.prevPanel.first, actionBar.nextPanel.next, actionBar.nextPanel.last }
	local children = tabBar:getChildren()
	local reverseChildren = tabBar.getReverseChildren and tabBar:getReverseChildren() or {}

	local dimension = actionBar.isVertical and tabBar:getHeight() or tabBar:getWidth()
	local visibleCount = math.max(1, math.floor(dimension / 36))

	if dir == "next" then
		local firstVisible = getFirstVisibleButton(actionBar)
		if not firstVisible then return end

		local firstIndex = tabBar:getChildIndex(firstVisible)
		local nextInvisible = getNextInvisibleChild(actionBar, firstIndex)

		if not nextInvisible then return end

		firstVisible:setVisible(false)
		nextInvisible:setVisible(true)
		scroll:increment(36)

		actionBar.firstVisibleIndex = tabBar:getChildIndex(firstVisible) + 1
		actionBar.lastVisibleIndex = tabBar:getChildIndex(nextInvisible)

	elseif dir == "prev" then
		local prevInvisible = getPrevInvisibleButton(actionBar)
		local lastVisible = getLastVisibleButton(actionBar)

		if not prevInvisible then return end

		prevInvisible:setVisible(true)
		lastVisible:setVisible(false)
		scroll:decrement(36)

		actionBar.firstVisibleIndex = tabBar:getChildIndex(prevInvisible)
		actionBar.lastVisibleIndex = tabBar:getChildIndex(lastVisible) - 1

	elseif dir == "first" then
		for i, button in ipairs(children) do
			button:setVisible(i <= visibleCount)
		end

		actionBar.firstVisibleIndex = 1
		actionBar.lastVisibleIndex = tabBar:getChildIndex(getLastVisibleButton(actionBar))
		scroll:setValue(scroll:getMinimum())

	elseif dir == "last" then
		for i, button in ipairs(reverseChildren) do
			button:setVisible(i <= visibleCount)
		end

		actionBar.firstVisibleIndex = tabBar:getChildIndex(getFirstVisibleButton(actionBar))
		actionBar.lastVisibleIndex = #children
		scroll:setValue(scroll:getMaximum())
	end

	local prevEnabled = actionBar.firstVisibleIndex ~= 1
	local nextEnabled = actionBar.lastVisibleIndex ~= #children

	buttons[1]:setOn(prevEnabled)
	buttons[2]:setOn(prevEnabled)
	buttons[3]:setOn(nextEnabled)
	buttons[4]:setOn(nextEnabled)
end

function changeLockStatus(button, barType)
	local barData = {
		["Bottom"] = {option = "actionBarBottomLocked", startPos = 1, endPos = 3},
		["Left"] = {option = "actionBarLeftLocked", startPos = 4, endPos = 6},
		["Right"] = {option = "actionBarRightLocked", startPos = 7, endPos = 9}
	}

	local data = barData[barType]
	if not data then
		return true
	end

	Options.clientOptions[data.option] = not Options.clientOptions[data.option]

	for i = data.startPos, data.endPos do
		actionBars[i].locked = not Options.actionBar[i].isLocked
		Options.actionBar[i].isLocked = not Options.actionBar[i].isLocked
	end

	if Options.clientOptions[data.option] then
		button:setIcon("/images/game/actionbar/locked")
	else
		button:setIcon("/images/game/actionbar/unlocked")
	end
end

function unbindActionBarEvent(actionbar)
	for _, button in pairs(actionbar.tabBar:getChildren()) do
		if button.cache and button.cache.hotkey then
			g_keyboard.unbindKeyPress(button.cache.hotkey, nil, gameRootPanel)
			g_keyboard.unbindKeyDown(button.cache.hotkey, nil, gameRootPanel)
		end

		if button.cache.cooldownEvent then
			removeEvent(button.cache.cooldownEvent)
		end

		resetButtonCache(button)
	end
end

function configureActionBar(barStr, visible)
	if not g_game.isOnline() then
		return
	end

	local bottom = string.find(barStr, "Bottom") ~= nil
	local left = string.find(barStr, "Left") ~= nil
	local right = string.find(barStr, "Right") ~= nil
	local actionNumber = tonumber(string.sub(barStr, -1))

	if bottom then
		local actionBar = actionBars[actionNumber]
		if not actionBar then
			return true
		end

		actionBar:setVisible(visible)
		actionBar:setOn(visible)
		Options.actionBar[actionNumber].isVisible = visible
		Options.clientOptions["actionBarShowBottom" .. actionNumber] = visible
		Options.actionBar[actionNumber].created = true
		resizeLockButtons()
		unbindActionBarEvent(actionBar)
		isLoaded = false
		setupActionBar(actionNumber)
		isLoaded = true

		if visible then
			table.insert(activeActionBars, actionBar)
		else
			for index, action in pairs(actionBars) do
				if action:getId() == actionBar:getId() then
					table.remove(activeActionBars, index)
				end
			end
		end
		scheduleEvent(function() modules.game_actionbar.updateVisibleWidgets() end, 10)
		return
	end

	if left then
		local actionBar = actionBars[actionNumber + 3]
		if not actionBar then
			return true
		end

		actionBar:setVisible(visible)
		actionBar:setOn(visible)
		Options.actionBar[actionNumber + 3].isVisible = visible
		Options.clientOptions["actionBarShowLeft" .. actionNumber] = visible
		resizeLockButtons()
		unbindActionBarEvent(actionBar)
		isLoaded = false
		setupActionBar(actionNumber + 3)
		isLoaded = true

		if visible then
			table.insert(activeActionBars, actionBar)
		else
			for index, action in pairs(actionBars) do
				if action:getId() == actionBar:getId() then
					table.remove(activeActionBars, index)
				end
			end
		end
		scheduleEvent(function() modules.game_actionbar.updateVisibleWidgets() end, 10)
		return
	end

	if right then
		local actionBar = actionBars[actionNumber + 6]
		if not actionBar then
			return true
		end

		actionBar:setVisible(visible)
		actionBar:setOn(visible)
		Options.actionBar[actionNumber + 6].isVisible = visible
		Options.clientOptions["actionBarShowRight" .. actionNumber] = visible
		resizeLockButtons()
		unbindActionBarEvent(actionBar)
		isLoaded = false
		setupActionBar(actionNumber + 6)
		isLoaded = true

		if visible then
			table.insert(activeActionBars, actionBar)
		else
			for index, action in pairs(actionBars) do
				if action:getId() == actionBar:getId() then
					table.remove(activeActionBars, index)
				end
			end
		end
		scheduleEvent(function() modules.game_actionbar.updateVisibleWidgets() end, 10)
		return
	end
end

function resetActionBar()
	if not player then
		player = g_game.getLocalPlayer()
	end

	if dragButton and dragItem then
		resetDragWidget(dragItem, dragButton)
		dragItem = nil
		dragButton = nil
	end

	isLoaded = false
	for _, actionbar in pairs(activeActionBars) do
		for _, button in pairs(actionbar.tabBar:getChildren()) do
			if button.cache.hotkey then
				g_keyboard.unbindKeyPress(button.cache.hotkey, nil, gameRootPanel)
				g_keyboard.unbindKeyDown(button.cache.hotkey, nil, gameRootPanel)
				button.cache.hotkey = nil
				button.hotkeyLabel:setText("")
			end

			clearButton(button, false)
			resetButtonCache(button)
			updateButton(button)
		end
	end
	isLoaded = true
end

function resetSlots(slot)
	for _, actionbar in pairs(activeActionBars) do
		if actionbar:getId() == "actionbar." .. slot then
			for _, button in pairs(actionbar.tabBar:getChildren()) do
				if button.cache.hotkey then
					g_keyboard.unbindKeyPress(button.cache.hotkey, nil, gameRootPanel)
					g_keyboard.unbindKeyDown(button.cache.hotkey, nil, gameRootPanel)
					button.cache.hotkey = nil
					button.hotkeyLabel:setText("")
					Options.removeHotkey(button:getId())
				end

				clearButton(button, false)
				resetButtonCache(button)
			end
			break
		end
	end
end

function getButtonById(id)
	for _, actionbar in pairs(actionBars) do
		for _, button in pairs(actionbar.tabBar:getChildren()) do
			if button:getId() == id then
				return button
			end
		end
	end
	return nil
end

function assignTextToFirstAvailableSlot(text, sendAutomatically)
	if type(text) ~= 'string' or text == '' or not Options or not Options.createOrUpdateText or not Options.actionBarMappings then
		return false
	end

	for barId = 1, 9 do
		for buttonId = 1, 50 do
			local hasActionSetting = false
			for _, data in pairs(Options.actionBarMappings) do
				if data["actionBar"] == barId and data["actionButton"] == buttonId and data["actionsetting"] and next(data["actionsetting"]) ~= nil then
					hasActionSetting = true
					break
				end
			end

			if not hasActionSetting then
				Options.createOrUpdateText(barId, buttonId, text, sendAutomatically and true or false)
				local button = getButtonById(string.format('%d.%d', barId, buttonId))
				if button then
					updateButton(button)
				end
				return true, barId, buttonId
			end
		end
	end

	return false
end

function onDragSpellLeave(mousePos, spellWords, actionButton)
	if not actionButton then
		return true
	end

	local destButton = getButtonById(actionButton:getParent():getId())
	if not destButton then
		return true
	end

	local actionbar = destButton:getParent():getParent()
	if actionbar.locked then
		return true
	end

	local destBarID, destButtonID = string.match(destButton:getId(), "(.*)%.(.*)")
	Options.createOrUpdateText(tonumber(destBarID), tonumber(destButtonID), spellWords, true)
	updateButton(destButton)
end

function updateVisibleOptions(option, state)
	for _, actionbar in pairs(activeActionBars) do
		local childs = actionbar.tabBar:getChildren()
		for _, button in pairs(childs) do
			if not button:isVisible() then
				goto continue
			end

			if option == "hotkey" then
				button.hotkeyLabel:setVisible(state)
			elseif option == "amount" then
				button.item:setShowCount(state)
			elseif option == "parameter" then
				button.parameterText:setVisible(state)
			end

			if option == "tooltip" then
				if not state then
					button.item:setTooltip("")
				else
					setupButtonTooltip(button, false)
				end
			end

			:: continue ::
		end
	end
end

function toggleCooldownOption()
	for _, actionbar in pairs(activeActionBars) do
		for _, button in pairs(actionbar.tabBar:getChildren()) do
			local cache = getButtonCache(button)
			if not (cache.isSpell or cache.isRuneSpell) then
				goto continue
			end

			button.cooldown:showTime(m_settings.getOption("cooldownSecond"))
			button.cooldown:showProgress(m_settings.getOption("graphicalCooldown"))
			:: continue ::
		end
	end
end

function onReleaseActionKeys()
	spellGroupPressed = {}
end

function isHotkeyGroupPressed(group)
	return spellGroupPressed[tostring(group)] ~= nil
end

function canEquipItem(item)
	if item:getClothSlot() == 0 and (item:getClassification() > 0 or item:isAmmo() or getSmartCast(item:getId())) then
		return true
	end

	if item:getClothSlot() > 0 or (item:getClothSlot() == 0 and item:hasWearout()) then
		return true
	end
	return false
end

function onSearchTextChange(text)
	local spellList = window:recursiveGetChildById('spellList')
	for _, child in pairs(spellList:getChildren()) do
		local name = child:getText():lower()
		if name:find(text:lower()) or text == '' or #text < 3 then
			child:setVisible(true)
		else
			child:setVisible(false)
		end
	end
  end

function onClearSearchText()
	local search = window:recursiveGetChildById('searchText')
  search:setText('')
end

function removeHotkey(name)
  local button = getUsedHotkeyButton(name)

  if not button then return end

  Options.removeHotkey(button:getId())
  g_keyboard.unbindKeyPress(name, nil, m_interface.getRootPanel())
  updateButton(button)
end

function updateButtonState(button)
	if not button then return end

	if not player then
		player = g_game.getLocalPlayer()
	end

	if not player then return end
	if not button.item then return end

	button:recursiveGetChildById('activeSpell'):setVisible(false)
	if button.cache.isSpell then
		setupButtonTooltip(button, false)
		button.item.text.gray:setVisible(not playerCanUseSpell(button.cache.spellData))

		local passiveSpell = player:getMonkPassive()
		local spellId = 0
		if passiveSpell == 1 then
			spellId = 274
		elseif passiveSpell == 2 then
			spellId = 275
		elseif passiveSpell == 3 then
			spellId = 276
		end

		button:recursiveGetChildById('activeSpell'):setVisible(button.cache.spellData.id == spellId)
	elseif button.cache.itemId ~= 0 then
		local smartId = getSmartCast(button.cache.itemId)
		local isItemEquiped = player:hasEquippedItemId(button.cache.itemId, button.cache.upgradeTier)
		local isSmartEquiped = smartId and player:hasEquippedItemId(smartId, button.cache.upgradeTier)
		local itemCount = player:getInventoryCount(button.cache.itemId, button.cache.upgradeTier)
			+ player:getInventoryCount(smartId, button.cache.upgradeTier)

		-- update checked (pressed)
		if button.cache.actionType == UseTypes["Equip"] and (not smartId or button.cache.smartMode) then
			button.item:setChecked(itemCount ~= 0 and (isItemEquiped or isSmartEquiped))
		end

		-- update shadow (disabled)
		button.item.gray:setVisible(itemCount == 0)

		-- update item count
		button.item:setItemCount(itemCount);

		-- update tooltip
		setupButtonTooltip(button, false)

		-- update item
		if button.cache.smartMode then
			local activeId = getActiveSmartCast(button.cache.itemId) or button.cache.itemId
			local inactiveId = getInactiveSmartCast(button.cache.itemId) or button.cache.itemId

			if player:hasEquippedItemId(activeId, button.cache.upgradeTier) then
				button.item:setItemId(activeId, true)
				button.cache.itemId = activeId
			else
				button.item:setItemId(inactiveId, true)
				button.cache.itemId = inactiveId

			end
		end
	end
end
