---------------------------
-- Lua code author: R1ck --
-- Company: VICTOR HUGO PERENHA - JOGOS ON LINE --
---------------------------

BossTracker = {}
BossTracker.__index = BossTracker

BossTrackerList = {}

local sortOptions = {}
local firstSection = {}
local secondSection = {}

local sortFirst = nil
local sortSecond = nil

local sortTypes = {
	NAME = 1,
	COMPLETATION = 2,
	REMAINING_KILLS = 3,
	ASCENDING = 4,
	DESCENDING = 5
}

local function getBossEntry(monsterList, data)
	if type(data) ~= "table" then
		return nil
	end

	return monsterList and monsterList[data[1]] or nil
end

local function getBossName(monsterList, data)
	local creature = getBossEntry(monsterList, data)
	return creature and creature[1] or tostring(data and data[1] or "")
end

local function getPercent(current, total)
	current = tonumber(current) or 0
	total = tonumber(total) or 0
	if total <= 0 then
		return 0
	end
	return (current / total) * 100
end

function BossTracker.initSortFields()
	sortOptions[sortTypes.NAME] = true
	sortOptions[sortTypes.COMPLETATION] = false
	sortOptions[sortTypes.REMAINING_KILLS] = false
	sortOptions[sortTypes.ASCENDING] = true
	sortOptions[sortTypes.DESCENDING] = false

	sortFirst = sortTypes.NAME
	sortSecond = sortTypes.ASCENDING
end

function BossTracker.resetWindow()
	if not bossTrackerWindow or not bossTrackerWindow.contentsPanel then
		return
	end

	bossTrackerWindow.contentsPanel:destroyChildren()
end

function BossTracker.showTrackerData()
	if not bossTrackerWindow or not bossTrackerWindow.contentsPanel then
		return
	end

	bossTrackerWindow.contentsPanel:destroyChildren()

	if not BossTrackerList or #BossTrackerList == 0 then
		return
	end

	local monsterList = g_things.getMonsterList() or {}
	table.sort(BossTrackerList, function(a, b)
		local nameA = getBossName(monsterList, a)
		local nameB = getBossName(monsterList, b)
		local completionA = ((tonumber(a[5]) or 0) - (tonumber(a[2]) or 0))
		local completionB = ((tonumber(b[5]) or 0) - (tonumber(b[2]) or 0))
        local percentA = getPercent(a[2], a[5])
        local percentB = getPercent(b[2], b[5])

		if sortFirst == sortTypes.NAME then
			if sortSecond == sortTypes.ASCENDING then
				return nameA < nameB
			else
				return nameA > nameB
			end
		end

		if sortFirst == sortTypes.COMPLETATION then
			if sortSecond == sortTypes.ASCENDING then
				return percentA < percentB
			else
				return percentA > percentB
			end
		end

		if sortFirst == sortTypes.REMAINING_KILLS then
			if sortSecond == sortTypes.ASCENDING then
				return completionA < completionB
			else
				return completionA > completionB
			end
		end
	end)
	local layout = bossTrackerWindow.contentsPanel:getLayout()
	if layout then
		layout:disableUpdates()
	end
	for _, data in ipairs(BossTrackerList) do
		local creature = monsterList[data[1]]
		if not creature then
			goto continue
		end

		local widget = g_ui.createWidget('BossPanel', bossTrackerWindow.contentsPanel)
		widget.creature:setOutfit({type = creature[2], auxType = creature[3], head = creature[4], body = creature[5], legs = creature[6], feet = creature[7], addons = creature[8]})
		widget:setId(creature[1])

		local bossName = string.capitalize(creature[1])
		widget.bossName:setText(short_text(bossName, 16))
		widget.redirect:setId(bossName)
		if #bossName >= 16 then
			widget.bossName:setTooltip(bossName)
		end

		local currentKills = tonumber(data[2]) or 0
		local firstUnlock = tonumber(data[3]) or 0
		local secondUnlock = tonumber(data[4]) or firstUnlock
		local thirdUnlock = tonumber(data[5]) or secondUnlock

		local bossName, bossCooldown = modules.game_analyser.BossCooldown:hasCooldown(data[1])
		if not string.empty(bossName) and bossCooldown ~= -1 then
			BossTracker.checkTrackerCooldown(bossName, bossCooldown)
			widget.bossName:setText(short_text(bossName, 14))
			if #bossName >= 14 then
				widget.bossName:setTooltip(bossName)
			end
		end

		widget.trackerContainer.killsBar:setTooltip(tr("%s / %s", comma_value(currentKills), comma_value(firstUnlock)))
		widget.trackerContainer1.killsBar1:setTooltip(tr("%s / %s", comma_value(currentKills), comma_value(secondUnlock)))
		widget.trackerContainer2.killsBar2:setTooltip(tr("%s / %s", comma_value(currentKills), comma_value(thirdUnlock)))

		local firstPercent = math.min(getPercent(currentKills, firstUnlock), 100)
		widget.trackerContainer.killsBar:setPercent(firstPercent)

		if currentKills > firstUnlock and secondUnlock > firstUnlock then
			local secondPercent = math.min(getPercent(currentKills - firstUnlock, secondUnlock - firstUnlock), 100)
			widget.trackerContainer1.killsBar1:setPercent(secondPercent)
		end

		if currentKills > secondUnlock and thirdUnlock > secondUnlock then
			local thirdPercent = math.min(getPercent(currentKills - secondUnlock, thirdUnlock - secondUnlock), 100)
			widget.trackerContainer2.killsBar2:setPercent(thirdPercent)
		end

		if currentKills >= thirdUnlock then
			widget.trackerContainer.killsBar:setImageSource('/mods/game_cyclopedia/images/ui/monster-bar-green')
			widget.trackerContainer1.killsBar1:setImageSource('/mods/game_cyclopedia/images/ui/monster-bar-green')
			widget.trackerContainer2.killsBar2:setImageSource('/mods/game_cyclopedia/images/ui/monster-bar-green')
			widget.trackerContainer.killsBar:setTooltip(widget.trackerContainer.killsBar:getTooltip() .. " (fully unlocked)")
			widget.trackerContainer1.killsBar1:setTooltip(widget.trackerContainer1.killsBar1:getTooltip() .. " (fully unlocked)")
			widget.trackerContainer2.killsBar2:setTooltip(widget.trackerContainer2.killsBar2:getTooltip() .. " (fully unlocked)")
		end

		widget.trackerContainer1.countLabel:setText(data[2])

    	widget.onMouseRelease = function(widget, mousePos, mouseButton)
      		if widget:containsPoint(mousePos) and mouseButton == MouseRightButton then
        		local menu = g_ui.createWidget('PopupMenu')
        		menu:setGameMenu(true)
        		local buttonText = tr("Stop tracking \"%s\"", bossName)
        		menu:addOption(tr(buttonText), function() modules.game_cyclopedia.Bosstiary.checkBosstiaryTrack(nil, false, data[1]) end)
        		menu:display(mousePos)
      		end
    	end

		widget.cooldown:insertLuaCall("onDestroy")
		widget.cooldown.onDestroy = function(self)
			if self.eventCooldown then
				removeEvent(self.eventCooldown)
				self.eventCooldown = nil
			end
		end

		:: continue ::
	end

	if layout then
		layout:enableUpdates()
	end
end

function BossTracker.onRedirect(widget)
	if not widget then
		return
	end
	modules.game_cyclopedia.Bosstiary.onSideButtonRedirect(widget:getId())
end

function BossTracker.showSortOptions()
	firstSection = {}
	secondSection = {}
	local sortMenu = g_ui.createWidget('PopupMenu')
    sortMenu:setGameMenu(true)
	local sort1 = sortMenu:addCheckBoxOption(tr('Sort by name'), function() BossTracker.selectFirstSection(sortTypes.NAME) end, "", sortOptions[sortTypes.NAME])
    local sort2 = sortMenu:addCheckBoxOption(tr('Sort by completion percentage'), function() BossTracker.selectFirstSection(sortTypes.COMPLETATION) end, "", sortOptions[sortTypes.COMPLETATION])
    local sort3 = sortMenu:addCheckBoxOption(tr('Sort by remaining kills'), function() BossTracker.selectFirstSection(sortTypes.REMAINING_KILLS) end, "", sortOptions[sortTypes.REMAINING_KILLS])
	sortMenu:addSeparator()
	local sort4 = sortMenu:addCheckBoxOption(tr('Sort ascending'), function() BossTracker.selectSecondSection(sortTypes.ASCENDING) end, "", sortOptions[sortTypes.ASCENDING])
    local sort5 = sortMenu:addCheckBoxOption(tr('Sort descending'), function() BossTracker.selectSecondSection(sortTypes.DESCENDING) end, "", sortOptions[sortTypes.DESCENDING])
    sortMenu:display(g_window.getMousePosition())

	table.insert(firstSection, {type = sortTypes.NAME, widget = sort1})
	table.insert(firstSection, {type = sortTypes.COMPLETATION, widget = sort2})
	table.insert(firstSection, {type = sortTypes.REMAINING_KILLS, widget = sort3})
	table.insert(secondSection, {type = sortTypes.ASCENDING, widget = sort4})
	table.insert(secondSection, {type = sortTypes.DESCENDING, widget = sort5})
end

function BossTracker.selectFirstSection(type)
	if type == sortTypes.NAME and sortOptions[sortTypes.NAME] == true then
		return
	end

	for k, data in pairs(firstSection) do
		if data.type == type then
			sortOptions[data.type] = true
			sortFirst = type
		else
			sortOptions[data.type] = false
		end
	end
	BossTracker.showTrackerData()
end

function BossTracker.selectSecondSection(type)
	if type == sortTypes.ASCENDING and sortOptions[sortTypes.ASCENDING] == true then
		return
	end

	for k, data in pairs(secondSection) do
		if data.type == type then
			sortOptions[data.type] = true
			sortSecond = type
		else
			sortOptions[data.type] = false
		end
	end
	BossTracker.showTrackerData()
end


function BossTracker.onLogout()
	if not bossTrackerWindow then
		return
	end

	local option = {
		contentHeight = bossTrackerWindow:getHeight(),
		contentMaximized = not bossTrackerWindow.minimizeButton:isOn(),
		sortKey = "completion",
		sortOrder = "ascending"
	}

	if sortOptions[sortTypes.NAME] then
		option.sortKey = "name"
	elseif sortOptions[sortTypes.COMPLETATION] then
		option.sortKey = "completion"
	elseif sortOptions[sortTypes.REMAINING_KILLS] then
		option.sortKey = "remaining"
	end

	if sortOptions[sortTypes.ASCENDING] then
		option.sortOrder = "ascending"
	else
		option.sortOrder = "descending"
	end

	modules.game_sidebars.setBosstiaryTrackerOptions(option)
end

function BossTracker.onLogin(bossTrackerWidgetOptions)
	sortOptions[sortTypes.ASCENDING] = false
	sortOptions[sortTypes.DESCENDING] = false
	if not bossTrackerWidgetOptions.sortOrder then
		bossTrackerWidgetOptions.sortOrder = "ascending"
	end

	if not bossTrackerWidgetOptions.sortKey then
		bossTrackerWidgetOptions.sortKey = "name"
	end

	if bossTrackerWidgetOptions.sortOrder == "ascending" then
		sortOptions[sortTypes.ASCENDING] = true
		sortSecond = sortTypes.ASCENDING
		BossTracker.selectSecondSection(sortTypes.ASCENDING)
	else
		sortOptions[sortTypes.DESCENDING] = true
		sortSecond = sortTypes.DESCENDING
		BossTracker.selectSecondSection(sortTypes.DESCENDING)
	end

	sortOptions[sortTypes.NAME] = false
	sortOptions[sortTypes.COMPLETATION] = false
	sortOptions[sortTypes.REMAINING_KILLS] = false

	if bossTrackerWidgetOptions.sortKey == "name" then
		sortOptions[sortTypes.NAME] = true
		sortFirst = sortTypes.NAME
		BossTracker.selectFirstSection(sortTypes.NAME)
	elseif bossTrackerWidgetOptions.sortKey == "completion" then
		sortOptions[sortTypes.COMPLETATION] = true
		sortFirst = sortTypes.COMPLETATION
		BossTracker.selectFirstSection(sortTypes.COMPLETATION)
	else
		sortFirst = sortTypes.REMAINING_KILLS
		sortOptions[sortTypes.REMAINING_KILLS] = true
		BossTracker.selectFirstSection(sortTypes.REMAINING_KILLS)
	end
end

function BossTracker.checkTrackerCooldown(name, cooldown)
	if not bossTrackerWindow or not bossTrackerWindow.contentsPanel then
		return true
	end

	local widget = bossTrackerWindow.contentsPanel:recursiveGetChildById(name)
	if not widget then
		return true
	end

	widget.cooldown:setVisible(true)

	widget.bossName:setText(short_text(name, 14))
	if #name >= 14 then
		widget.bossName:setTooltip(name)
	end

	local remainingTime = math.max(0, cooldown - os.time()) 

	if remainingTime == 0 then
		widget.cooldown:setImageSource("/images/icons/icon-cooldown-finished")
		widget.cooldown:setTooltip("No cooldown")
		return true
	end

	if widget.cooldown.eventCooldown then
		removeEvent(widget.cooldown.eventCooldown)
	end

	widget.cooldown:setImageSource("/images/icons/icon-cooldown-running")
	widget.cooldown.eventCooldown = cycleEvent(function() timerCooldown(widget.cooldown, cooldown) end, 1000)
end

function timerCooldown(widget, endTime)
	local remainingText = ""
	local remainingTime = math.max(0, endTime - os.time()) 
	if remainingTime == 0 then
		removeEvent(widget.eventCooldown)
		widget.eventCooldown = nil
		widget:setImageSource("/images/icons/icon-cooldown-finished")
		widget:setTooltip("No cooldown")
		return
	end

	local duration = math.max(1, remainingTime)
	local days = math.floor(duration / 86400)
	local hours = math.floor((duration % 86400) / 3600)
	local minutes = math.floor((duration % 3600) / 60)
	local seconds = math.floor(duration % 60)  -- Calcula os segundos restantes

	if days > 0 then
		remainingText = string.format("%dd %2dh %2dmin", days, hours, minutes)
	elseif hours > 0 then
		remainingText = string.format("%2dh %2dmin", hours, minutes)
	elseif minutes > 0 then
		remainingText = string.format("%2dmin %2ds", minutes, seconds)
	else
		remainingText = string.format("%2ds", seconds)
	end

	widget:setTooltip(remainingText)
end
