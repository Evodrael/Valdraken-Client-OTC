if not WeaponProficiency then
	WeaponProficiency = {}
	WeaponProficiency.__index = WeaponProficiency

	WeaponProficiency.window = nil
	WeaponProficiency.warningWindow = nil
	WeaponProficiency.displayItemPanel = nil
	WeaponProficiency.perkPanel = nil
	WeaponProficiency.bonusDetailPanel = nil
	WeaponProficiency.starProgressPanel = nil
	WeaponProficiency.optionFilter = nil
	WeaponProficiency.itemListScroll = nil
	WeaponProficiency.vocationWarning = nil

	WeaponProficiency.itemList = {}
	WeaponProficiency.cacheList = {} -- [itemId] = {experience, perks}

	WeaponProficiency.allProficiencyRequested = false
	WeaponProficiency.firstItemRequested = nil

	WeaponProficiency.saveWeaponMissing = false

	WeaponProficiency.ItemCategory = {
		Axes = 17, Clubs = 18, DistanceWeapons = 19,
		Swords = 20, WandsRods = 21, FistWeapons = 27,
	}
	WeaponProficiency.perkPanelsName = {
		"oneBonusIconPanel", "twoBonusIconPanel",
		"threeBonusIconPanel"
	}
	WeaponProficiency.filters = {
		["levelButton"] = false,
		["vocButton"] = false,
		["oneButton"] = false,
		["twoButton"] = false,
	}

	-- Scrollable settings
	WeaponProficiency.listWidgetHeight = 34 -- 34x34
	WeaponProficiency.listCapacity = 0
	WeaponProficiency.listMinWidgets = 0
	WeaponProficiency.listMaxWidgets = 0
	WeaponProficiency.offset = 0
	WeaponProficiency.listPool = {}
	WeaponProficiency.listData = {}
end

function init()
	WeaponProficiency.window = g_ui.displayUI('weapon_proficiency')
	WeaponProficiency.displayItemPanel = WeaponProficiency.window:recursiveGetChildById("itemPanel")
	WeaponProficiency.perkPanel = WeaponProficiency.window:recursiveGetChildById("bonusProgressBackground")
	WeaponProficiency.bonusDetailPanel = WeaponProficiency.window:recursiveGetChildById("bonusDetailBackground")
	WeaponProficiency.optionFilter = WeaponProficiency.window:recursiveGetChildById("classFilter")
	WeaponProficiency.starProgressPanel = WeaponProficiency.window:recursiveGetChildById("starsPanelBackground")
	WeaponProficiency.itemListScroll = WeaponProficiency.window:recursiveGetChildById("itemListScroll")
	WeaponProficiency.vocationWarning = WeaponProficiency.window:recursiveGetChildById("vocationWarning")
	WeaponProficiency.window:hide()

	connect(g_game, {
		onInspection = onInspection,
		onGameStart = onGameStart,
		onGameEnd = onGameEnd,
		onWeaponProficiency = onWeaponProficiency,
		onProficiencyNotification = onProficiencyNotification
	})
	connect(g_things, { onLoadDat = loadProficiencyJson })

	if g_things.isDatLoaded and g_things.isDatLoaded() then
		loadProficiencyJson()
	end
end

function terminate()
	disconnect(g_game, {
		onInspection = onInspection,
		onGameStart = onGameStart,
		onGameEnd = onGameEnd,
		onWeaponProficiency = onWeaponProficiency,
		onProficiencyNotification = onProficiencyNotification
	})
	disconnect(g_things, { onLoadDat = loadProficiencyJson })
end

function onGameStart()
	WeaponProficiency.allProficiencyRequested = false
	WeaponProficiency.saveWeaponMissing = false
	WeaponProficiency.firstItemRequested = nil
end

function onGameEnd()
	WeaponProficiency.window:hide()
	WeaponProficiency:reset()

	if WeaponProficiency.warningWindow then
		WeaponProficiency:destroy()
		WeaponProficiency.warningWindow = nil
	end
	g_client.setInputLockWidget(nil)
end

function loadProficiencyJson()
	ProficiencyData:loadProficiencyJson()
end

function show()
	WeaponProficiency.window:show(true)
	WeaponProficiency.window:raise()
	WeaponProficiency.window:focus()
end

function hide()
	WeaponProficiency.window:hide()
end

function getUnknownMarketCategory(itemType)
	return UnknownCategories[itemType:getWeaponType()]
end

local function getWeaponMarketCategory(thing)
	if not thing then
		return nil
	end

	local category = getUnknownMarketCategory(thing)
	if category then
		return category
	end

	if thing.getId then
		local thingType = g_things.getThingType(thing:getId(), ThingCategoryItem)
		if thingType then
			local marketData = thingType:getMarketData() or {}
			return marketData.category or getUnknownMarketCategory(thingType)
		end
	end

	return nil
end

local function normalizeMarketData(itemType)
	local marketData = table.copy(itemType:getMarketData() or {})
	if table.empty(marketData) then
		marketData = {}
	end

	marketData.category = marketData.category or getUnknownMarketCategory(itemType)
	if not marketData.category then
		return nil
	end

	if not marketData.showAs or marketData.showAs <= 0 then
		marketData.showAs = itemType:getId()
	end

	if string.empty(marketData.name or "") then
		marketData.name = g_things.getCyclopediaItemName(itemType:getId())
	end

	if string.empty(marketData.name or "") and itemType.getName then
		marketData.name = itemType:getName()
	end

	if string.empty(marketData.name or "") then
		marketData.name = string.format("Item %d", itemType:getId())
	end

	local restrictVocation = marketData.restrictVocation
	if type(restrictVocation) == "number" then
		local vocations = {}
		for vocationId = 1, 16 do
			local vocationBitMask = Bit.bit(vocationId - 1)
			if Bit.hasBit(restrictVocation, vocationBitMask) then
				table.insert(vocations, vocationId)
			end
		end
		marketData.restrictVocation = vocations
	elseif type(restrictVocation) ~= "table" then
		marketData.restrictVocation = {}
	end

	marketData.requiredLevel = tonumber(marketData.requiredLevel) or 0
	return marketData
end

local function normalizeCategorySelection(selected)
	if selected == "Weapons: Wands/Rods" then
		return "Weapons: Wands"
	end
	return selected
end

local function isProficiencyCategory(category)
	return table.contains({
		MarketCategory.Axes,
		MarketCategory.Clubs,
		MarketCategory.DistanceWeapons,
		MarketCategory.Swords,
		MarketCategory.WandsRods,
		MarketCategory.FistWeapons
	}, category)
end

function sortWeaponProficiency(marketCategory)
	local itemList = WeaponProficiency.itemList[marketCategory]
	if not itemList then return end

	table.sort(itemList, function(a, b)
		local idA, idB = a.itemId, b.itemId

		local expA = WeaponProficiency.cacheList[idA] and WeaponProficiency.cacheList[idA].exp or 0
		local expB = WeaponProficiency.cacheList[idB] and WeaponProficiency.cacheList[idB].exp or 0

		if expA == expB then
			return a.marketData.name:lower() < b.marketData.name:lower()
		end
		return expA > expB
	end)
end

function requestOpenWindow(redirectItem)
	if not next(WeaponProficiency.itemList) and g_things.isDatLoaded and g_things.isDatLoaded() then
		loadProficiencyJson()
	end

	if g_things.isDatLoaded and g_things.isDatLoaded() then
		local allWeapons = WeaponProficiency.itemList[MarketCategory.WeaponsAll] or {}
		if #allWeapons == 0 then
			if table.empty(ProficiencyData.content or {}) then
				loadProficiencyJson()
			else
				WeaponProficiency:createItemCache()
			end
		end
	end

	show()
	g_client.setInputLockWidget(WeaponProficiency.window)

	local category = "Weapons: All"
	local targetItemId = nil
	local leftSlotItem = modules.game_inventory.getLeftSlotItem()

	if leftSlotItem then
		category = WeaponCategoryToString[getWeaponMarketCategory(leftSlotItem)] or category
		targetItemId = leftSlotItem:getId()
	end

	if redirectItem then
		category = WeaponCategoryToString[getWeaponMarketCategory(redirectItem)] or category
		targetItemId = redirectItem:getId()
	end

	if WeaponProficiency.firstItemRequested then
		category = WeaponCategoryToString[getWeaponMarketCategory(WeaponProficiency.firstItemRequested)] or category
		targetItemId = WeaponProficiency.firstItemRequested:getId()
		WeaponProficiency.firstItemRequested = nil
	end

	if not WeaponProficiency.allProficiencyRequested then
		g_game.sendWeaponProficiencyAction(1) -- request all weapons
		WeaponProficiency.firstItemRequested = redirectItem
	end

	local focusFirstChild = false
	local focusVocation = (category ~= "Weapons: All")
	local categoryId = WeaponStringToCategory[normalizeCategorySelection(category)]
	if not categoryId or not WeaponProficiency.itemList[categoryId] or #WeaponProficiency.itemList[categoryId] == 0 then
		category = "Weapons: All"
		focusFirstChild = true
		focusVocation = false
	end
	if not focusVocation then
		focusFirstChild = true
		sortWeaponProficiency(MarketCategory.WeaponsAll)
	end

	WeaponProficiency.filters["vocButton"] = focusVocation 
	WeaponProficiency.window:recursiveGetChildById("vocButton"):setChecked(focusVocation, true)

	WeaponProficiency:onClearSearch(true)
	WeaponProficiency:onWeaponCategoryChange(category, nil, targetItemId, focusFirstChild)

	if WeaponProficiency.allProficiencyRequested then
		g_client.setInputLockWidget(WeaponProficiency.window)
	end
end

function onInspection(inspectType, itemName, item, descriptions)
	if inspectType ~= 2 then
		return
	end

	local infoWidget = WeaponProficiency.window:recursiveGetChildById("infoWidget")
	local text = itemName
	for _, data in pairs(descriptions) do
		text = text .. string.format("\n%s: %s", data.detail, wrapTextByWords(data.description, 52))
	end

	if not WeaponProficiency.allProficiencyRequested then
		WeaponProficiency.allProficiencyRequested = true
		requestOpenWindow()
	end

	infoWidget:setTooltip(text)
end

local isMasteryAchieved

local function updateListWidgetStars(widget)
	if not widget or not widget.cache then
		return
	end

	local entry = widget.cache
	local itemForProgress = entry.actualItem or entry.displayItem
	local starPanel = widget:getChildById("starsBackground")
	if not itemForProgress or not starPanel then
		return
	end

	local cacheEntry = WeaponProficiency.cacheList[entry.itemId] or nil
	local weaponLevel = ProficiencyData:getCurrentLevelByExp(itemForProgress, (cacheEntry and cacheEntry.exp or 0))
	local mastery = isMasteryAchieved(itemForProgress)

	starPanel:destroyChildren()
	for i = 1, 7 do
		local star = g_ui.createWidget("MiniStar", starPanel)
		if i <= weaponLevel and mastery then
			star:setImageSource("/images/game/proficiency/icon-star-tiny-gold")
			star:setOpacity(1)
		elseif i <= weaponLevel then
			star:setImageSource("/images/game/proficiency/icon-star-tiny-silver")
			star:setOpacity(1)
		else
			star:setImageSource("/images/game/proficiency/icon-star-tiny-silver")
			star:setOpacity(0.25)
		end
	end
end

local function refreshVisibleListStars()
	for _, widget in pairs(WeaponProficiency.listPool or {}) do
		updateListWidgetStars(widget)
	end
end

function onWeaponProficiency(itemId, experience, perks, marketCategory)
	WeaponProficiency.cacheList[itemId] = { exp = experience, perks = perks}
	if (not marketCategory or marketCategory == 0) then
		local thingType = g_things.getThingType(itemId, ThingCategoryItem)
		marketCategory = thingType and getWeaponMarketCategory(thingType) or marketCategory
	end
	sortWeaponProficiency(marketCategory)
	refreshVisibleListStars()
	WeaponProficiency:onUpdateSelectedProficiency(itemId)
end

function onProficiencyNotification(itemId, experience, hasUnnusedPerk, thingType)
	local itemCache = WeaponProficiency.cacheList[itemId]
	if not itemCache then
		WeaponProficiency.cacheList[itemId] = { exp = experience, perks = {} }
	else
		if experience > 0 then
			itemCache.exp = experience
		end
	end

	sortWeaponProficiency((thingType:getMarketData() or {}).category or getWeaponMarketCategory(thingType))
	modules.game_topbar.onUpdateProficiencyData(WeaponProficiency.cacheList[itemId], hasUnnusedPerk, thingType)
end

---------------------------
----- Local Functions -----
---------------------------
local function canChangeWeaponPerks()
	local player = g_game.getLocalPlayer()
	if not player or not g_game.isOnline() then
		return false
	end
	return player:isInProtectionZone()
end

isMasteryAchieved = function(targetItem)
	if not targetItem then
		return false
	end
	
	local maxExperience = ProficiencyData:getMaxExperience(ProficiencyData:getPerkLaneCount(targetItem:getProficiencyId()), targetItem)
	local weaponEntry = WeaponProficiency.cacheList[targetItem:getId()]
	local currentExperience = weaponEntry and weaponEntry.exp or 0

	return currentExperience >= maxExperience
end

local function enableBonusIcon(bonusIcon, iconGrey, hightLightWidget, borderWidget, bonusDescWidget, bonusTooltip, augmentIconDarker, perkData)
	if bonusIcon.blocked or bonusIcon.active or bonusIcon.locked then
		return true
	end

	local visible = not iconGrey:isVisible()

	iconGrey:setVisible(false)
	hightLightWidget:setVisible(true)
	borderWidget:setImageSource("/images/game/proficiency/border-weaponmasterytreeicons-active")

	bonusDescWidget:setImageSource("")
	bonusDescWidget:setText(bonusTooltip)
	if bonusDescWidget:getWrappedLinesCount() > 4 then
		bonusDescWidget:setText(short_text(bonusTooltip, 57))
		bonusDescWidget:setTooltip(bonusTooltip)
	end

	if perkData.Type == PERK_SPELL_AUGMENT then
		augmentIconDarker:setVisible(false)
	end

	bonusIcon.active = true
end

local function disableBonusIcon(iconGrey, hightLightWidget, borderWidget, bonusDescWidget, augmentIconDarker, perkData)
	iconGrey:setVisible(true)
	iconGrey:setOpacity(1)
	hightLightWidget:setVisible(false)
	borderWidget:setImageSource("/images/game/proficiency/border-weaponmasterytreeicons-inactive")

	bonusDescWidget:setImageSource("/images/game/proficiency/icon-lock-grey")
	bonusDescWidget:setText("")
	bonusDescWidget:removeTooltip()

	if perkData.Type == PERK_SPELL_AUGMENT then
		augmentIconDarker:setVisible(true)
		augmentIconDarker:setOpacity(1)
	end
end

local function disableOtherBonusIcons(currentPerkPanel, currentBonusIcon)
	for i = 0, 2 do
		local bonusIcon = currentPerkPanel:getChildById("bonusIcon" .. i)
		if bonusIcon and bonusIcon ~= currentBonusIcon and bonusIcon.active then
			bonusIcon.blocked = false
			bonusIcon.active = false
			local iconGrey = bonusIcon:getChildById("icon-grey")
			local hightLightWidget = bonusIcon:getChildById("highlight")
			local borderWidget = bonusIcon:getChildById("border")
			local augmentIconDarker = bonusIcon:getChildById("iconPerks-grey")
			local augmentIcon = bonusIcon:getChildById("iconPerks")

			iconGrey:setVisible(true)
			iconGrey:setOpacity(1)
			hightLightWidget:setVisible(false)
			borderWidget:setImageSource("/images/game/proficiency/border-weaponmasterytreeicons-inactive")
			if augmentIcon:isVisible() then
				augmentIconDarker:setVisible(true)
				augmentIconDarker:setOpacity(1)
			end
		end
	end
end

local function updatePercentWidgets(child, currentExperience, _index, itemType)
	if not child then
		return
	end

	local percentWidget = child:getChildById("bonusSelectProgress")
	local starWidget = WeaponProficiency.starProgressPanel:getChildById("starWidget" .. _index)
	local starProgress = starWidget:getChildById("starProgress")

	local percent = ProficiencyData:getLevelPercent(currentExperience, _index, itemType)
	local maxLevelExperience = ProficiencyData:getMaxExperienceByLevel(_index, itemType)

	percentWidget:setPercent(percent)
	starProgress:setPercent(percent)
	starProgress:setTooltip(string.format("%s / %s", comma_value(currentExperience), comma_value(maxLevelExperience)))

	if percent >= 100 then
		local iconTypo = isMasteryAchieved(itemType) and "gold" or "silver"
		starWidget:getChildById("star"):setImageSource(string.format("/images/store/icon-star-%s", iconTypo))
		for _, widget in pairs(child.currentPerkPanel:getChildren()) do
			widget.blocked = false
		end
	end
end

local function checkSortOptions(itemData)
	local player = g_game.getLocalPlayer()
	if not player then
		return false
	end

	local playerLevel = player:getLevel()
	local playerVocation = translateWheelVocation(player:getVocation())

	if WeaponProficiency.filters["levelButton"] then
		if itemData.marketData.requiredLevel > playerLevel then
			return false
		end
	end

	if WeaponProficiency.filters["vocButton"] then
		local itemVocation = itemData.marketData.restrictVocation
		if type(itemVocation) ~= "table" then
			itemVocation = {}
		end
		if #itemVocation > 0 and not table.contains(itemVocation, playerVocation) then
			return false
		end
	end

	if WeaponProficiency.filters["oneButton"] then
		if itemData.thingType:getClothSlot() ~= 6 then
			return false
		end
	end

	if WeaponProficiency.filters["twoButton"] then
		if itemData.thingType:getClothSlot() ~= 0 then
			return false
		end
	end
	return true
end

local function setupPerkIconGrey(perkData, iconSource, iconClip, iconGrey, augmentIconNormal, augmentIconDarker)
	if perkData.Type == PERK_SPELL_AUGMENT then
		iconGrey:setImageSource(string.format("%s-off", iconSource))
		iconGrey:setImageClip(string.format("%s 64 64", iconClip))
		local augmentIconClip = ProficiencyData:getAugmentIconClip(perkData)
		augmentIconNormal:setVisible(true)
		augmentIconDarker:setVisible(true)
		augmentIconNormal:setImageClip(string.format("%s 32 32", augmentIconClip))
		local x = tonumber(augmentIconClip:match("^(%d+)")) or 0
		augmentIconDarker:setImageClip(string.format("%d 32 32 32", x))
	else
		local x = tonumber(iconClip:match("^(%d+)")) or 0
		iconGrey:setImageSource(iconSource)
		iconGrey:setImageClip(string.format("%d 64 64 64", x))
	end
end

local function createHoverHandler(bonusIcon, iconGrey, augmentIconDarker)
	return function(widget, hovered)
		if not bonusIcon.active and not bonusIcon.locked and not bonusIcon.blocked then
			local opacity = hovered and 0.5 or 1
			iconGrey:setOpacity(opacity)
			augmentIconDarker:setOpacity(opacity)
		end
		g_tooltip.onWidgetHoverChange(widget, hovered)
	end
end

local function createClickHandler(bonusIcon, currentPerkPanel, bonusDetail, hightLightWidget, borderWidget, iconGrey, augmentIconDarker, bonusTooltip, perkData, itemId)
	return function()
		if bonusIcon.blocked or bonusIcon.active or bonusIcon.locked then return end
		disableOtherBonusIcons(currentPerkPanel, bonusIcon)
		enableBonusIcon(bonusIcon, iconGrey, hightLightWidget, borderWidget, bonusDetail:recursiveGetChildById("bonusName"), bonusTooltip, augmentIconDarker, perkData)
		WeaponProficiency:checkPerksMatch(itemId)
	end
end

----------------------------
------ Core Functions ------
----------------------------
function WeaponProficiency:reset()
	self.cacheList = {}
	self.allProficiencyRequested = false
	self.currentItemId = nil
end

function WeaponProficiency:updateMainButtons(currentData)
	local enableReset = canChangeWeaponPerks() and table.size(currentData.perks) > 0
	local resetButton = self.window:getChildById("reset")
	local applyButton = self.window:getChildById("apply")
	local okButton = self.window:getChildById("ok")
	local closeButton = self.window:getChildById("close")

	resetButton:setOn(enableReset)
	applyButton:setOn(false)
	okButton:setOn(false)

	local resetTooltip = "Reset your perks"
	if not canChangeWeaponPerks() then
		resetTooltip = "You can only reset your perks in a protection zone."
	elseif table.empty(currentData.perks) then
		resetTooltip = "You don't have any perks to reset."
	end

	resetButton:setTooltip(resetTooltip)
	applyButton:setTooltip("No changes have been made to your perks.")
	closeButton:setText("Close")
end

function WeaponProficiency:createItemCache()
	self.itemList = {}
	self.itemList[MarketCategory.WeaponsAll] = {}
	for _, v in pairs(self.ItemCategory) do
		self.itemList[v] = {}
	end

	local seenItems = {}
	local function appendItemType(itemType)
		if not itemType or seenItems[itemType:getId()] then
			return
		end

		local displayItem = Item.create(itemType:getId())
		local actualItem = Item.create(itemType:getId())
		local marketData = normalizeMarketData(itemType)

		if marketData and displayItem and actualItem then
			if not self.itemList[marketData.category] then
				marketData.category = getUnknownMarketCategory(itemType) or marketData.category
			end

			if not self.itemList[marketData.category] then
				goto continue
			end

			displayItem:setId(marketData.showAs)

			local marketItem = {
				itemId = itemType:getId(),
				displayItem = displayItem,
				actualItem = actualItem,
				thingType = itemType,
				marketData = marketData
			}
			table.insert(self.itemList[marketData.category], marketItem)
			table.insert(self.itemList[MarketCategory.WeaponsAll], marketItem)
			seenItems[itemType:getId()] = true
		end

		::continue::
	end

	local types = g_things.getProficiencyThings() or {}
	for _, itemType in pairs(types) do
		appendItemType(itemType)
	end

	if #self.itemList[MarketCategory.WeaponsAll] == 0 and g_things.findThingTypeByAttr then
		for _, itemType in pairs(g_things.findThingTypeByAttr(ThingAttrMarket, 0) or {}) do
			local marketData = normalizeMarketData(itemType)
			if marketData and (isProficiencyCategory(marketData.category) or (itemType.hasProficiency and itemType:hasProficiency())) then
				appendItemType(itemType)
			end
		end
	end

	local function sortByName(a, b)
		local nameA = a.marketData.name:lower()
		local nameB = b.marketData.name:lower()
		return nameA < nameB
	end

	for _, v in pairs(self.itemList) do
		table.sort(v, sortByName)
	end

	-- [debug log desativado] g_logger.info(string.format("[WeaponProficiency] cached %d weapon entries", #self.itemList[MarketCategory.WeaponsAll]))
end

function WeaponProficiency:onItemListValueChange(scroll, value, delta)
	self.oldScrollValue = value
	local itemListWidget = self.window:recursiveGetChildById("itemList")

	-- Special case with half visible lines
	if #self.listData > 30 and #self.listData <= 35 then
    	itemListWidget:setVirtualOffset({x = 0, y = (delta > 0 and 8 or 0)})
		return true
	end

    local itemsPerRow = 5
    local rowsVisible = 8
    local itemsVisible = itemsPerRow * rowsVisible
    local totalItems = #self.listData

    local startLabel = (value * itemsPerRow) + 1
    local endLabel = startLabel + itemsVisible - 1

    local currentWidgetIndex = startLabel

    self.offset = self.offset + ((value % 5) * 2)

    if self.offset > 64 or value == 0 then
        self.offset = 0
    end

    if endLabel >= totalItems then
        self.offset = 7
    end

    itemListWidget:setVirtualOffset({x = 0, y = self.offset})

	local _itemWidget = self.displayItemPanel and self.displayItemPanel:getChildById("item")
	local currentItem = _itemWidget and _itemWidget:getItem()

    for k, widget in pairs(itemListWidget:getChildren()) do
        if currentWidgetIndex > totalItems then
            widget:setVisible(false)
            goto continue
        end

        local entry = self.listData[currentWidgetIndex]
        if not entry then
            widget:setVisible(false)
            goto continue
        end

        local itemSlot = widget:getChildById("item")
        -- Weapon Proficiency lists every weapon side-by-side; the rarity
        -- price tint distracts from the per-weapon star progress that the
        -- panel actually communicates. Skip the rarity frame for these
        -- slots.
        if itemSlot then itemSlot._skipRarityFrame = true end
        itemSlot:setItem(entry.displayItem or entry.actualItem)
        widget:setTooltip(entry.marketData.name)
        widget.cache = entry

        widget:setVisible(true)

		if widget:isFocused() then
			itemListWidget:focusChild(nil, MouseFocusReason, false, true)
		end

		if self.currentItemId and self.currentItemId == entry.itemId then
			itemListWidget:focusChild(widget, MouseFocusReason, false, true)
		end

		updateListWidgetStars(widget)

        currentWidgetIndex = currentWidgetIndex + 1
        :: continue ::
    end
end

function WeaponProficiency:onWeaponCategoryChange(selected, searchText, targetItemId, focusFirstChild, fromOptionChange)
	selected = normalizeCategorySelection(selected)
	local weaponCategory = WeaponStringToCategory[selected]
	if not weaponCategory then
		return
	end

	local categoryEntries = self.itemList[weaponCategory] or {}
	if #categoryEntries == 0 and weaponCategory ~= MarketCategory.WeaponsAll then
		selected = "Weapons: All"
		weaponCategory = MarketCategory.WeaponsAll
		categoryEntries = self.itemList[weaponCategory] or {}
		focusFirstChild = true
	end

	sortWeaponProficiency(weaponCategory)

	-- Update current filter without propagation
	self.optionFilter:setCurrentOption(selected, true)
	
	local targetWidget = nil
	local itemListWidget = self.window:recursiveGetChildById("itemList")
	local _itemWidget = self.displayItemPanel and self.displayItemPanel:getChildById("item")
	local currentItem = _itemWidget and _itemWidget:getItem()

	itemListWidget.onChildFocusChange = nil
	itemListWidget:destroyChildren()

	self.listCapacity = ((math.floor(itemListWidget:getHeight() / self.listWidgetHeight)) + 2) * 5
    self.listMinWidgets = 0
	self.oldScrollValue = -1
    self.listPool = {}
    self.listData = {}

	-- Generate the filtred list
	for _, data in pairs(categoryEntries) do
		if not checkSortOptions(data) then
			goto continue
		end
	
		if searchText and not string.empty(searchText) and not matchText(searchText:lower(), data.marketData.name:lower()) then
			goto continue
		end

		table.insert(self.listData, data)
		:: continue ::
	end

	local currentIndex = 0
	for _, data in pairs(self.listData) do
		if #self.listPool >= self.listCapacity then
            break
        end

		local widget = g_ui.createWidget("ItemBox", itemListWidget)
		if widget then
			widget:setId("widget_" .. currentIndex)
		end
		if not widget or not checkSortOptions(data) then
			goto continue
		end
	
		if searchText and not string.empty(searchText) and not matchText(searchText:lower(), data.marketData.name:lower()) then
			goto continue
		end

		local itemSlot = widget:getChildById("item")
		if itemSlot then itemSlot._skipRarityFrame = true end
		itemSlot:setItem(data.displayItem or data.actualItem)
		widget:setVisible(true)
		widget:setTooltip(data.marketData.name)
		widget.cache = data

		if not targetWidget then
			if targetItemId and targetItemId == data.itemId then
				targetWidget = widget
			elseif fromOptionChange and not focusFirstChild and self.currentItemId and self.currentItemId == data.itemId then
				targetWidget = widget
			end
		end

		updateListWidgetStars(widget)

		currentIndex = currentIndex + 1
		table.insert(self.listPool, widget)
		:: continue ::
	end

	self.listMaxWidgets = math.ceil((#self.listData / 5) - 7)
	local specialListSize = false
	if #self.listData > 30 and #self.listData <= 35 then
		self.listMaxWidgets = 1
		specialListSize = true
	end

    self.itemListScroll:setValue(0)
    self.itemListScroll:setMinimum(self.listMinWidgets)
    self.itemListScroll:setMaximum(math.max(0, self.listMaxWidgets))
    self.itemListScroll.onValueChange = function(list, value, delta) self:onItemListValueChange(list, value, delta) end

	self.itemListScroll:setVisibleItems(specialListSize and 9 or math.min(#self.listData, 45))
    self.itemListScroll:setVirtualChilds(specialListSize and 10 or #self.listData)
	
	itemListWidget:setVirtualOffset({x = 0, y = 0})

	itemListWidget.onChildFocusChange = function(_, a)
		if a and a.cache then
			WeaponProficiency:onItemListFocusChange(a.cache)
		end
	end

	-- Sem alvo e sem focusFirstChild (ex: arma equipada que nao esta na lista) a janela
	-- abria "vazia". Em aberturas/trocas de categoria (sem busca textual) cai pro 1o item.
	if targetWidget or focusFirstChild or (self.listPool[1] and (not searchText or string.empty(searchText))) then
		local focusWidget = targetWidget or self.listPool[1]
		itemListWidget:focusChild(focusWidget, MouseFocusReason, true)
		-- O foco inicial nem sempre dispara onChildFocusChange (lista virtual), deixando o
		-- painel de detalhes vazio ate o primeiro clique. Forca a selecao do primeiro item.
		if focusWidget and focusWidget.cache and self.currentItemId ~= focusWidget.cache.itemId then
			self:onItemListFocusChange(focusWidget.cache)
		end
	else
		itemListWidget:focusChild(nil, MouseFocusReason, false, true)
	end

	if #self.listData > 0 and #self.listPool == 0 then
		g_logger.warning(string.format("[WeaponProficiency] render produced no widgets for %s with %d entries", selected, #self.listData))
	end

	-- Widget not found/visible lets force the selection
	if targetItemId and not targetWidget then
		for _, data in pairs(categoryEntries) do
			if targetItemId == data.itemId then
				self:onItemListFocusChange(data)
				break
			end
		end
	end
end

function WeaponProficiency:onItemListFocusChange(selectedCache)
	if not selectedCache or not g_game.isOnline() then return end

	local displayPanel = self.displayItemPanel and self.displayItemPanel:getChildById("item")
	if not displayPanel then return end
	local oldItem = displayPanel:getItem()

	-- Display a warning message to save changes
	if self.saveWeaponMissing and oldItem then
		self:onCloseMessage(false, oldItem, function() self:onItemListFocusChange(selectedCache) end)
		return
	end

	local displayItem = selectedCache.actualItem or Item.create(selectedCache.itemId)
	if not displayItem then
		return
	end
	local displayItemId = selectedCache.itemId
	self.currentItemId = displayItemId
	displayPanel._skipRarityFrame = true
	displayPanel:setItem(displayItem)
	self.displayItemPanel:getChildById("itemNameTitle"):setText(selectedCache.marketData.name)

	self.perkPanel:destroyChildren()
	self.bonusDetailPanel:destroyChildren()
	self.starProgressPanel:destroyChildren()

	-- Vocation warning label
	local player = g_game.getLocalPlayer()
	local itemVocation = selectedCache.marketData.restrictVocation
	local playerVocation = translateWheelVocation(player:getVocation())
	local showVocationWarning = (#itemVocation > 0 and not table.contains(itemVocation, playerVocation)) or player:getLevel() < selectedCache.marketData.requiredLevel
	self.vocationWarning:setVisible(showVocationWarning)

	local currentData = self.cacheList[displayItemId] or {exp = 0, perks = {}}
	self.cacheList[displayItemId] = currentData

	g_game.doThing(false)
	g_game.sendInspectionObject(4, displayItemId, 0)
	g_game.doThing(true)

	if self.allProficiencyRequested then
		g_game.doThing(false)
		g_game.sendWeaponProficiencyAction(0, displayItemId)
		g_game.doThing(true)
	end

	local proficiencyId = displayItem:getProficiencyId()
	local profEntry = ProficiencyData:getContentById(proficiencyId)
	if not profEntry then return end

	self:updateExperienceProgress(currentData.exp, #profEntry.Levels, displayItem)

	for i, levelData in ipairs(profEntry.Levels) do
		local widget = g_ui.createWidget("BonusSelectPanel", self.perkPanel)
		local bonusDetail = g_ui.createWidget("BonusDetailPanel", self.bonusDetailPanel, "bonusDetail_" .. i)
		local starDetail = g_ui.createWidget("StarWidget", self.starProgressPanel)
		starDetail:setId("starWidget" .. i)
		widget:getChildById("bonusSelectProgress"):setPercent(0)

		local currentPerkPanel = self.perkPanelsName[#levelData.Perks] and widget:getChildById(self.perkPanelsName[#levelData.Perks])
		if currentPerkPanel then
			currentPerkPanel:setVisible(true)
			widget.currentPerkPanel = currentPerkPanel
		end

		local widgetIsBlocked = not canChangeWeaponPerks() and currentData.perks[i - 1]
		for index, perkData in ipairs(levelData.Perks) do
			local bonusIcon = currentPerkPanel:getChildById(string.format("bonusIcon%s", index - 1))
			local icon = bonusIcon:getChildById("icon")
			local iconGrey = bonusIcon:getChildById("icon-grey")
			local borderWidget = bonusIcon:getChildById("border")
			local hightLightWidget = bonusIcon:getChildById("highlight")
			local augmentIconNormal = bonusIcon:getChildById("iconPerks")
			local augmentIconDarker = bonusIcon:getChildById("iconPerks-grey")

			local iconSource, iconClip = ProficiencyData:getImageSourceAndClip(perkData)
			local bonusName, bonusTooltip = ProficiencyData:getBonusNameAndTooltip(perkData)

			bonusIcon:setTooltip(string.format("%s\n\n%s", bonusName, bonusTooltip))
			bonusIcon.blocked, bonusIcon.locked, bonusIcon.active = true, false, false
			bonusIcon.perkData = perkData

			icon:setImageSource(iconSource)
			icon:setImageClip(string.format("%s 64 64", iconClip))

			-- Setup icon grey and augment
			setupPerkIconGrey(perkData, iconSource, iconClip, iconGrey, augmentIconNormal, augmentIconDarker)

			if currentData.perks[i - 1] == index - 1 then
				bonusIcon.blocked = false
				enableBonusIcon(bonusIcon, iconGrey, hightLightWidget, borderWidget, bonusDetail:recursiveGetChildById("bonusName"), bonusTooltip, augmentIconDarker, perkData)
			end

			if widgetIsBlocked then
				bonusIcon:getChildById("locked-perk"):setVisible(true)
				bonusIcon.locked = true
			end

			bonusIcon.onHoverChange = createHoverHandler(bonusIcon, iconGrey, augmentIconDarker)
			bonusIcon.onClick = createClickHandler(bonusIcon, currentPerkPanel, bonusDetail, hightLightWidget, borderWidget, iconGrey, augmentIconDarker, bonusTooltip, perkData, displayItemId)
		end

		updatePercentWidgets(widget, currentData.exp, i, displayItem)
	end
end

function WeaponProficiency:onUpdateSelectedProficiency(itemId)
	local _itemWidget = self.displayItemPanel and self.displayItemPanel:getChildById("item")
	local currentItem = _itemWidget and _itemWidget:getItem()
	if not currentItem or self.currentItemId ~= itemId then
		return
	end

	local currentData = self.cacheList[itemId] or {exp = 0, perks = {}}
	local experience = currentData.exp
	self:updateExperienceProgress(experience, #self.perkPanel:getChildren(), currentItem)

	-- Setup window buttons
	self:updateMainButtons(currentData)

	for i, child in ipairs(self.perkPanel:getChildren()) do
		updatePercentWidgets(child, experience, i, currentItem)

		if not child.currentPerkPanel then
			goto continue
		end

		local widgetIsBlocked = not canChangeWeaponPerks() and currentData.perks[i - 1]
		for index, widget in pairs(child.currentPerkPanel:getChildren()) do
			
			if widgetIsBlocked then
				widget:getChildById("locked-perk"):setVisible(true)
				widget.locked = true
			end

			if currentData.perks[i - 1] == index - 1 then
				widget.blocked = false
				widget.locked = false

				local iconGrey = widget:getChildById("icon-grey")
				local borderWidget = widget:getChildById("border")
				local hightLightWidget = widget:getChildById("highlight")
				local augmentIconDarker = widget:getChildById("iconPerks-grey")
				local bonusDetail = self.bonusDetailPanel:getChildById("bonusDetail_" .. i)
				local _, bonusTooltip = ProficiencyData:getBonusNameAndTooltip(widget.perkData)

				if not bonusDetail then
					goto continue
				end

				enableBonusIcon(widget, iconGrey, hightLightWidget, borderWidget, bonusDetail:recursiveGetChildById("bonusName"), bonusTooltip, augmentIconDarker, widget.perkData)
			end
		end
		::continue::
	end
end

function WeaponProficiency:updateExperienceProgress(currentExp, levelsCount, displayItem)
	local experienceWidget = self.window:recursiveGetChildById("progressDescription")
	local experienceLeftWidget = self.window:recursiveGetChildById("nextLevelDescription")
	local totalProgressWidget = self.window:recursiveGetChildById("proficiencyProgress")

	local currentCeilExperience = ProficiencyData:getCurrentCeilExperience(currentExp, displayItem)
	local maxExperience = ProficiencyData:getMaxExperience(levelsCount, displayItem)
	local masteryAchieved = currentExp >= maxExperience

	experienceWidget:setText(string.format("%s / %s", comma_value(currentExp), comma_value(currentCeilExperience)))
	
	self:updateItemAddons(currentExp, displayItem, masteryAchieved)

	if masteryAchieved then
		experienceLeftWidget:setText("Mastery achieved")
	else
		experienceLeftWidget:setText(string.format("%s XP for next level", comma_value(currentCeilExperience - currentExp)))
	end

	totalProgressWidget:setPercent(ProficiencyData:getTotalPercent(currentExp, levelsCount, displayItem))
	totalProgressWidget:setTooltip(string.format("%s / %s", comma_value(currentExp), comma_value(maxExperience)))
end

function WeaponProficiency:updateItemAddons(currentExp, displayItem, masteryAchieved)
	local weaponLevel = math.min(7, ProficiencyData:getCurrentLevelByExp(displayItem, currentExp))
	local iconLevelWidget = self.window:recursiveGetChildById("iconMasteryLevel")
	local weaponLevelWidget = self.window:recursiveGetChildById("itemMasteryLevel")

	iconLevelWidget:setImageSource("/images/game/proficiency/icon-masterylevel-" .. weaponLevel)
	weaponLevelWidget:setVisible(weaponLevel > 0)
	if weaponLevel > 0 then
		local color = masteryAchieved and "gold" or "silver"
		weaponLevelWidget:setImageSource(string.format("/images/game/proficiency/icon-masterylevel-%d-%s", weaponLevel, color))
	end
end

function WeaponProficiency:toggleFilterOption(filter)
	local filterId = filter:getId()
	local oneHandButton = self.window:recursiveGetChildById("oneButton")
	local twoHandButton = self.window:recursiveGetChildById("twoButton")

	if filterId == "oneButton" then
		if twoHandButton:isChecked() then
			twoHandButton:setChecked(false, true) -- (true) ignore lua call
			self.filters["twoButton"] = false
		end
	elseif filterId == "twoButton" then
		if oneHandButton:isChecked() then
			oneHandButton:setChecked(false, true)  -- (true) ignore lua call
			self.filters["oneButton"] = false
		end
	end

	self.filters[filterId] = not filter:isChecked()
	filter:setChecked(not filter:isChecked())

	self:onWeaponCategoryChange(self.optionFilter:getCurrentOption().text)
end

function WeaponProficiency:onSearchTextChange(text)
	local currentCategory = self.optionFilter:getCurrentOption().text
	self:onWeaponCategoryChange(currentCategory, text)
end

function WeaponProficiency:onClearSearch()
	local searchField = self.window:recursiveGetChildById("searchText")
	if not string.empty(searchField:getText()) then
		searchField:clearText()
	end
end

function WeaponProficiency:onApplyChanges(button, targetItem)
	if button and not button:isOn() then return end

	local _itemWidget = self.displayItemPanel and self.displayItemPanel:getChildById("item")
	local currentItem = _itemWidget and _itemWidget:getItem()
	if targetItem then
		currentItem = targetItem
	end

	if not currentItem then
		return
	end

	if not self.currentItemId then
		return
	end

	local toSend = {}
	for i, child in ipairs(self.perkPanel:getChildren()) do
		for k, v in pairs(child.currentPerkPanel:getChildren()) do
			if not v.blocked and v.active then 
				toSend[i - 1] = k - 1
			end
		end
	end

	if table.empty(toSend) then
		g_game.sendWeaponProficiencyAction(2, self.currentItemId)
		self.cacheList[self.currentItemId].perks = {}
	else
		g_game.sendWeaponProficiencyApply(self.currentItemId, toSend)
	end

	self.window:getChildById("apply"):setOn(false)
	self.window:getChildById("ok"):setOn(false)
	self.window:getChildById("close"):setText("Close")
	self.saveWeaponMissing = false
end

function WeaponProficiency:onResetWeapon(button)
	if not canChangeWeaponPerks() or not button:isOn() then
		return
	end

	local _itemWidget = self.displayItemPanel and self.displayItemPanel:getChildById("item")
	local currentItem = _itemWidget and _itemWidget:getItem()
	if not currentItem or not self.currentItemId then
		return
	end

	local applyButton = self.window:getChildById("apply")
	local okButton = self.window:getChildById("ok")
	local closeButton = self.window:getChildById("close")
	local weaponEntry = self.cacheList[self.currentItemId] or {}
	local perksSize = table.size(weaponEntry.perks)

	button:setOn(false)
	applyButton:setOn(perksSize > 0)
	okButton:setOn(perksSize > 0)

	button:setTooltip("You don't have any perks to reset.")

	if perksSize > 0 then
		local text = "Apply changes to your perks"
		applyButton:setTooltip(text)
		okButton:setTooltip(text)
		closeButton:setText("Cancel")
		self.saveWeaponMissing = true
	else
		local text = "No changes have been made to your perks."
		applyButton:setTooltip(text)
		okButton:setTooltip(text)
		closeButton:setText("Close")
	end

	-- Limpar as informaçoes
	for i, child in ipairs(self.perkPanel:getChildren()) do
		local bonusDetail = self.bonusDetailPanel:getChildById("bonusDetail_" .. i)
		if not bonusDetail or not child.currentPerkPanel then
			goto continue
		end

		for index, widget in pairs(child.currentPerkPanel:getChildren()) do
			widget:getChildById("locked-perk"):setVisible(false)

			if widget.active then
				widget.blocked = false
				widget.locked = false
				widget.active = false

				local iconGrey = widget:getChildById("icon-grey")
				local borderWidget = widget:getChildById("border")
				local hightLightWidget = widget:getChildById("highlight")
				local augmentIconDarker = widget:getChildById("iconPerks-grey")

				disableBonusIcon(iconGrey, hightLightWidget, borderWidget, bonusDetail:recursiveGetChildById("bonusName"), augmentIconDarker, widget.perkData)
			end
		end
		::continue::
	end
end

function WeaponProficiency:onCloseWindow(button)
	if button:getText() == "Close" then
		hide()
		g_client.setInputLockWidget(nil)
		return true
	end

	self:onCloseMessage(true)
end

function WeaponProficiency:onCloseMessage(userClosingWindow, targetItem, callbackFunction)
	if self.warningWindow then
		self.warningWindow:destroy()
	end

	self.window:hide()
	g_client.setInputLockWidget(nil)

	local noButton = function()
		if self.warningWindow then
			self.warningWindow:destroy()
			self.warningWindow = nil
		end
		self.saveWeaponMissing = false

		if not userClosingWindow then
			self.window:show()
			g_client.setInputLockWidget(self.window)
			if callbackFunction then
				callbackFunction()
			end
		else
			modules.game_console.getConsole():focus()
			m_interface.getRootPanel():focus()
		end
	end

  	local yesButton = function()
    	if self.warningWindow then
      		self.warningWindow:destroy()
			self.warningWindow = nil
    	end

		self:onApplyChanges(nil, targetItem)
		
		if not userClosingWindow then
			if callbackFunction then
				callbackFunction()
			end

			self.window:show()
			g_client.setInputLockWidget(self.window)
		else
			modules.game_console.getConsole():focus()
			m_interface.getRootPanel():focus()
		end
  	end

  	self.warningWindow = displayGeneralBox('Save?', "You did not save the changes you have made to your perks.\n\nWould you like to save your perks?",
		{{ text=tr('Yes'), callback = yesButton }, { text=tr('No'), callback = noButton }
	}, yesFunction, noFunction)
end

function WeaponProficiency:checkPerksMatch(itemId)
    local cacheEntry = self.cacheList[itemId]
    if not cacheEntry then
        return
    end

    local cachePerks = cacheEntry.perks
    local allPerksMatch = true

    -- Se o cache estiver vazio, não bate
    if table.empty(cachePerks) then
        allPerksMatch = false
    else
        -- Para cada linha de perks
        for levelIndex, perkRow in ipairs(self.perkPanel:getChildren()) do
            local expectedPerk = cachePerks[levelIndex - 1]
            local foundActive = nil

            for perkIndex, widget in pairs(perkRow.currentPerkPanel:getChildren()) do
                if widget.active then
                    foundActive = perkIndex - 1
                    break
                end
            end

            -- Se o cache possui perk esperado mas não há ativo, ou há ativo a mais que o cache
            if expectedPerk and foundActive ~= expectedPerk then
                allPerksMatch = false
                break
            elseif not expectedPerk and foundActive ~= nil then
                -- Ativo a mais, fora do que o cache esperava
                allPerksMatch = false
                break
            end
        end
    end

    -- Habilita ou desabilita os botões
    local applyButton = self.window:getChildById("apply")
    local okButton = self.window:getChildById("ok")
	local closeButton = self.window:getChildById("close")

	if canChangeWeaponPerks() and not allPerksMatch then
		local resetButton = self.window:getChildById("reset")
		resetButton:setOn(true)
		resetButton:setTooltip("Reset your perks")
	end

	local tooltip = not allPerksMatch and "No changes have been made to your perks." or "Apply changes to your perks"

    applyButton:setOn(not allPerksMatch)
    okButton:setOn(not allPerksMatch)
	applyButton:setTooltip(tooltip)
	okButton:setTooltip(tooltip)

	closeButton:setText(not allPerksMatch and "Cancel" or "Close")
	self.saveWeaponMissing = not allPerksMatch
end
