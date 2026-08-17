---------------------------
-- Lua code author: R1ck --
-- Company: VICTOR HUGO PERENHA - JOGOS ON LINE --
---------------------------

BosstiarySlot = {}
BosstiarySlot.__index = BosstiarySlot

slotPanel = nil
bossPointsText = nil

local bossBalance = 0
local requiredPoints = 0
local lootBonus = 0
local nextLootBonus = 0

local filterText = {}
local slotData = {}
local availableBosses = {}

local receivedData = false
local requestTimeoutEvent = nil
local defaultSlotTwoPoints = 1500

local function normalizeSlotData(data)
	data = data or {}
	return {
		state = data.state or data[1] or 0,
		raceID = data.raceID or data.raceId or data.bossId or data[2] or 0,
		category = data.category or data.bossRace or data[3] or 0,
		kills = data.kills or data.killCount or data[4] or 0,
		bonusLoot = data.bonusLoot or data.lootBonus or data[5] or 0,
		bonusKill = data.bonusKill or data.killBonus or data[6] or 0,
		removeGold = data.removeGold or data.removePrice or data[7] or 0,
		isBoosted = data.isBoosted or data.inactive or data[8] or 0
	}
end

local function normalizeUnlockedCreatures(data)
	local normalized = {}
	for key, value in pairs(data or {}) do
		if type(value) == "table" then
			local bossId = value.bossId or value[1]
			if bossId then
				normalized[bossId] = value.bossRace or value[2] or 0
			end
		else
			normalized[key] = value
		end
	end
	return normalized
end

local function isSlotPanelValid(panel)
	panel = panel or slotPanel
	if not panel or panel:isDestroyed() then
		return false
	end
	return panel.informationProgress ~= nil and panel.slot1 ~= nil and panel.slot2 ~= nil
end

-- Every branch that renders a slot must set its title: the .otui default reads
-- "Slot X: Locked", so bailing out early would claim the slot is locked when it isn't.
local function setSlotMessage(slotWidget, title, message)
	slotWidget:setText(title)
	slotWidget.selectedBossPanel:setVisible(false)
	slotWidget.selectBoss:setVisible(false)
	if message then
		slotWidget.slot1Text:setText(message)
	end
	slotWidget.slot1Text:setVisible(true)
end

-- When a slot is locked the server reuses the boss id field to send the requirement,
-- so slot 2 can show the real number instead of a hardcoded one.
local function setSlotLocked(slotWidget, index, unlockRequirement)
	local message
	if index == 2 then
		local points = unlockRequirement > 0 and unlockRequirement or defaultSlotTwoPoints
		message = tr("Unlocks at %s Boss Points", comma_value(points))
	else
		message = tr("  Unlocks if you reach the\nProwess level for any boss")
	end

	setSlotMessage(slotWidget, tr("Slot %s: Locked", index), message)
end

local function setSlotUnavailable(slotWidget, index, raceId)
	setSlotMessage(slotWidget, tr("Slot %s: Unknown Boss", index),
		tr("The boss in this slot (id %s) is not\nrecognized by this client.", raceId))
end

local function onRequestTimeout()
	requestTimeoutEvent = nil
	if receivedData or not isSlotPanelValid() then
		return
	end

	local message = tr("Could not load your boss slots.\nPlease reopen this window.")
	setSlotMessage(slotPanel.slot1, tr("Slot %s: Unavailable", 1), message)
	setSlotMessage(slotPanel.slot2, tr("Slot %s: Unavailable", 2), message)
	slotPanel.slot3:setText(tr("Boosted Boss: Unavailable"))
end

function BosstiarySlot.onSideButtonRedirect()
	Cyclopedia.open()
	onOptionChange(cyclopediaOptionsPanel:recursiveGetChildById('8'))
end

function BosstiarySlot.requestData()
	filterText[1] = ''
	filterText[2] = ''

	slotPanel = VisibleCyclopediaPanel
	receivedData = false
	if requestTimeoutEvent then
		removeEvent(requestTimeoutEvent)
	end
	requestTimeoutEvent = scheduleEvent(onRequestTimeout, 3000)

    g_game.requestResource(ResourceBank)
    g_game.requestResource(ResourceInventary)
	g_game.openBosstiarySlots()
end

function BosstiarySlot.onBosstiarySlotsData(pointsBalance, pointsNext, bonusLoot, bonusNext, slots, unlockedCreatures)
	receivedData = true
	if requestTimeoutEvent then
		removeEvent(requestTimeoutEvent)
		requestTimeoutEvent = nil
	end

	bossBalance = pointsBalance
	requiredPoints = pointsNext
	lootBonus = bonusLoot
	nextLootBonus = bonusNext

	slotData = {
		normalizeSlotData(slots and slots[1]),
		normalizeSlotData(slots and slots[2]),
		normalizeSlotData(slots and slots[3])
	}
	availableBosses = normalizeUnlockedCreatures(unlockedCreatures)

	-- Don't adopt whatever panel is visible now: the player may have switched tabs
	-- while the reply was in flight. Reopening the tab re-requests the data anyway.
	if not isSlotPanelValid(VisibleCyclopediaPanel) then
		return
	end
	slotPanel = VisibleCyclopediaPanel

	BosstiarySlot.configureWindow()
end

function BosstiarySlot.configureWindow()
	if not isSlotPanelValid() then
		return
	end

    slotPanel.informationProgress.bossPointsProgress.bossPointsText:setText(tr('%s/%s', bossBalance, requiredPoints))
    slotPanel.informationProgress.bossPointsProgress:setPercent(requiredPoints > 0 and bossBalance * 100 / requiredPoints or 0)
    slotPanel.informationProgress.inforText:setText("Equipment Loot Bonus: " .. lootBonus .. "% Next: " .. nextLootBonus .. "%")

    if lootBonus > 100 and nextLootBonus > 100 then
        slotPanel.informationProgress.bossPointsBg:setWidth(262)
        slotPanel.informationProgress.bossPointsProgress:setWidth(260)
    else
        slotPanel.informationProgress.bossPointsBg:setWidth(278)
        slotPanel.informationProgress.bossPointsProgress:setWidth(276)
    end

    BosstiarySlot.showFirstSlot(slotData[1], filterText[1])
    BosstiarySlot.showSecondSlot(slotData[2], filterText[2])
    BosstiarySlot.showBoostedSlot(slotData[3])
end

function BosstiarySlot.showFirstSlot(data, sortText)
	data = normalizeSlotData(data)
	slotPanel.slot1.selectedBossPanel:setVisible(false)
	slotPanel.slot1.selectBoss:setVisible(false)
	slotPanel.slot1.slot1Text:setVisible(false)

	local state = data.state
	local monsterList = g_things.getMonsterList()
	local firstPanel = slotPanel.slot1.selectedBossPanel.panel1.bossSlotMonsterPanel

	if state == 1 then
		if data.raceID == 0 then
			slotPanel.slot1:setText("Slot 1: Select Boss")
			slotPanel.slot1.selectedBossPanel:setVisible(true)
			slotPanel.slot1.selectedBossPanel:recursiveGetChildById("selectBossButton").onClick = function() BosstiarySlot.onSelectBoss(firstPanel) end
			firstPanel:destroyChildren()

			for k, v in pairs(availableBosses) do
				local monster = monsterList[k]
				if not monster then
					goto continue
				end
				local name = string.capitalize(monster[1])
				if sortText and #sortText > 0 then
					if not matchText(sortText, name) then
						goto continue
					end
				end

				local category = v + 1
				local widget = g_ui.createWidget('BossBox', firstPanel)
				widget.bossName:setText(short_text(name, 8))
				widget.bossOutfit:setOutfit({type = monster[2], auxType = monster[3], head = monster[4], body = monster[5], legs = monster[6], feet = monster[7], addons = monster[8]})
				widget.bossOutfit:setRaceID(k)
				widget.bossOutfit:setActionId(1)
				widget.bossIcon:setImageSource('/mods/game_cyclopedia/images/icons/icon-bosstiary-' .. category)
				widget.bossIcon:setTooltip(tr(toolMessages[category], BosstiaryReward[category].prowess, BosstiaryReward[category].expertise, BosstiaryReward[category].mastery))

				slotPanel.slot1.selectedBossPanel.searchText:setActionId(1)
				:: continue ::
			end
		else
			slotPanel.slot1.selectBoss:setVisible(true)

			local monster = monsterList[data.raceID]
			if not monster then
				setSlotUnavailable(slotPanel.slot1, 1, data.raceID)
				return
			end
			local name = string.capitalize(monster[1])
			local baseKill = baseKillData[data.category + 1]
			local baseReward = baseRewardData[data.category + 1]
			if not baseKill or not baseReward then
				setSlotUnavailable(slotPanel.slot1, 1, data.raceID)
				return
			end

			slotPanel.slot1:setText(tr("Slot 1: %s", short_text(name, 20)))
			slotPanel.slot1.selectBoss.selectedBoss.outfit:setOutfit({type = monster[2], auxType = monster[3], head = monster[4], body = monster[5], legs = monster[6], feet = monster[7], addons = monster[8]})
			slotPanel.slot1.selectBoss.progressSecond.second.counter:setText(data.kills)

			slotPanel.slot1.selectBoss.progressFirst.first:setTooltip(tr("%s / %s", data.kills, baseKill.firstUnlock))
			slotPanel.slot1.selectBoss.progressSecond.second:setTooltip(tr("%s / %s", data.kills, baseKill.secondUnlock))
			slotPanel.slot1.selectBoss.progressThird.third:setTooltip(tr("%s / %s", data.kills, baseKill.thirdUnlock))

			-- Reset percent bar
			slotPanel.slot1.selectBoss.progressFirst.first:setImageSource("/mods/game_cyclopedia/images/ui/mosnter-bar")
			slotPanel.slot1.selectBoss.progressSecond.second:setImageSource("/mods/game_cyclopedia/images/ui/mosnter-bar")
			slotPanel.slot1.selectBoss.progressThird.third:setImageSource("/mods/game_cyclopedia/images/ui/mosnter-bar")
			slotPanel.slot1.selectBoss.progressFirst.first:setPercent(0)
			slotPanel.slot1.selectBoss.progressSecond.second:setPercent(0)
			slotPanel.slot1.selectBoss.progressThird.third:setPercent(0)
			slotPanel.slot1.selectBoss.starFisrt:setImageSource("/mods/game_cyclopedia/images/icons/star/inative1")
			slotPanel.slot1.selectBoss.starSecond:setImageSource("/mods/game_cyclopedia/images/icons/star/inative2")
			slotPanel.slot1.selectBoss.starThird:setImageSource("/mods/game_cyclopedia/images/icons/star/inative3")

			local firstPercent = data.kills * 100 / baseKill.firstUnlock
			slotPanel.slot1.selectBoss.progressFirst.first:setPercent(firstPercent)

			if firstPercent >= 100 then
				slotPanel.slot1.selectBoss.starFisrt:setImageSource("/mods/game_cyclopedia/images/icons/star/enable1")

				local secondPercent = data.kills * 100 / baseKill.secondUnlock
				slotPanel.slot1.selectBoss.progressSecond.second:setPercent(secondPercent)

				if secondPercent >= 100 then
					slotPanel.slot1.selectBoss.starSecond:setImageSource("/mods/game_cyclopedia/images/icons/star/enable2")

					local thirdPercent = data.kills * 100 / baseKill.thirdUnlock
					slotPanel.slot1.selectBoss.progressThird.third:setPercent(thirdPercent)
					if thirdPercent >= 100 then
						slotPanel.slot1.selectBoss.progressFirst.first:setImageSource('/mods/game_cyclopedia/images/ui/monster-bar-green')
						slotPanel.slot1.selectBoss.progressSecond.second:setImageSource('/mods/game_cyclopedia/images/ui/monster-bar-green')
						slotPanel.slot1.selectBoss.progressThird.third:setImageSource('/mods/game_cyclopedia/images/ui/monster-bar-green')
						slotPanel.slot1.selectBoss.starThird:setImageSource("/mods/game_cyclopedia/images/icons/star/enable3")
					end
				end
			end

			local removeGold = data.removeGold
			if data.isBoosted == 1 then
				removeGold = 0
			end

			local category = data.category + 1
			local bonusText = slotPanel.slot1.selectBoss.selectedBonusText
			bonusText:setText("Equipment loot bonus: " .. tostring(data.bonusLoot) .. "%")
			slotPanel.slot1.selectBoss.gold.text:setText(comma_value(removeGold))
			slotPanel.slot1.selectBoss.iconBosstiary:setImageSource('/mods/game_cyclopedia/images/icons/icon-bosstiary-' .. category)
			slotPanel.slot1.selectBoss.iconBosstiary:setTooltip(tr(toolMessages[category], BosstiaryReward[category].prowess, BosstiaryReward[category].expertise, BosstiaryReward[category].mastery))
			slotPanel.slot1.selectBoss.removeButton:setTooltip(tr("It will cost you %s gold to remove the currently selected boss from this slot.", comma_value(removeGold)))
			slotPanel.slot1.selectBoss.removeButton:setActionId(1)

			local player = g_game.getLocalPlayer()
			local bankMoney = player:getResourceValue(ResourceBank)
			local characterMoney = player:getResourceValue(ResourceInventary)

			if bankMoney + characterMoney < removeGold then
				slotPanel.slot1.selectBoss.removeButton:disable()
				slotPanel.slot1.selectBoss.gold.text:setColor("#d33c3c")
			else
				slotPanel.slot1.selectBoss.removeButton:enable()
				slotPanel.slot1.selectBoss.gold.text:setColor("#c0c0c0")
			end
		end
	else
		setSlotLocked(slotPanel.slot1, 1, data.raceID)
	end
end

function BosstiarySlot.showSecondSlot(data, sortText)
	data = normalizeSlotData(data)
	slotPanel.slot2.selectedBossPanel:setVisible(false)
	slotPanel.slot2.selectBoss:setVisible(false)
	slotPanel.slot2.slot1Text:setVisible(false)

	local state = data.state
	local monsterList = g_things.getMonsterList()
	local secondPanel = slotPanel.slot2.selectedBossPanel.panel1.bossSlotMonsterPanel

	if state == 1 then
		if data.raceID == 0 then
			slotPanel.slot2:setText("Slot 2: Select Boss")
			slotPanel.slot2.selectedBossPanel:setVisible(true)
			slotPanel.slot2.selectedBossPanel:recursiveGetChildById("selectBossButton").onClick = function() BosstiarySlot.onSelectBoss(secondPanel) end
			secondPanel:destroyChildren()

			for k, v in pairs(availableBosses) do
				local monster = monsterList[k]
				if not monster then
					goto continue
				end

				local name = string.capitalize(monster[1])
				if sortText and #sortText > 0 then
					if not matchText(sortText, name) then
						goto continue
					end
				end

				local category = v + 1
				local widget = g_ui.createWidget('BossBox', secondPanel)
				widget.bossName:setText(short_text(name, 8))
				widget.bossOutfit:setOutfit({type = monster[2], auxType = monster[3], head = monster[4], body = monster[5], legs = monster[6], feet = monster[7], addons = monster[8]})
				widget.bossOutfit:setRaceID(k)
				widget.bossOutfit:setActionId(2)
				widget.bossIcon:setImageSource('/mods/game_cyclopedia/images/icons/icon-bosstiary-' .. category)
				widget.bossIcon:setTooltip(tr(toolMessages[category], BosstiaryReward[category].prowess, BosstiaryReward[category].expertise, BosstiaryReward[category].mastery))
				slotPanel.slot2.selectedBossPanel.searchText:setActionId(2)

				:: continue ::
			end
		else
			slotPanel.slot2.selectBoss:setVisible(true)

			local monster = monsterList[data.raceID]
			if not monster then
				setSlotUnavailable(slotPanel.slot2, 2, data.raceID)
				return
			end
			local name = string.capitalize(monster[1])
			local baseKill = baseKillData[data.category + 1]
			local baseReward = baseRewardData[data.category + 1]
			if not baseKill or not baseReward then
				setSlotUnavailable(slotPanel.slot2, 2, data.raceID)
				return
			end

			slotPanel.slot2:setText(tr("Slot 2: %s", short_text(name, 20)))
			slotPanel.slot2.selectBoss.selectedBoss.outfit:setOutfit({type = monster[2], auxType = monster[3], head = monster[4], body = monster[5], legs = monster[6], feet = monster[7], addons = monster[8]})
			slotPanel.slot2.selectBoss.progressSecond.second.counter:setText(data.kills)

			slotPanel.slot2.selectBoss.progressFirst.first:setTooltip(tr("%s / %s", data.kills, baseKill.firstUnlock))
			slotPanel.slot2.selectBoss.progressSecond.second:setTooltip(tr("%s / %s", data.kills, baseKill.secondUnlock))
			slotPanel.slot2.selectBoss.progressThird.third:setTooltip(tr("%s / %s", data.kills, baseKill.thirdUnlock))

			-- Reset percent bar
			slotPanel.slot2.selectBoss.progressFirst.first:setImageSource("/mods/game_cyclopedia/images/ui/mosnter-bar")
			slotPanel.slot2.selectBoss.progressSecond.second:setImageSource("/mods/game_cyclopedia/images/ui/mosnter-bar")
			slotPanel.slot2.selectBoss.progressThird.third:setImageSource("/mods/game_cyclopedia/images/ui/mosnter-bar")
			slotPanel.slot2.selectBoss.progressFirst.first:setPercent(0)
			slotPanel.slot2.selectBoss.progressSecond.second:setPercent(0)
			slotPanel.slot2.selectBoss.progressThird.third:setPercent(0)
			slotPanel.slot2.selectBoss.starFisrt:setImageSource("/mods/game_cyclopedia/images/icons/star/inative1")
			slotPanel.slot2.selectBoss.starSecond:setImageSource("/mods/game_cyclopedia/images/icons/star/inative2")
			slotPanel.slot2.selectBoss.starThird:setImageSource("/mods/game_cyclopedia/images/icons/star/inative3")

			local firstPercent = data.kills * 100 / baseKill.firstUnlock
			slotPanel.slot2.selectBoss.progressFirst.first:setPercent(firstPercent)

			if firstPercent >= 100 then
				slotPanel.slot2.selectBoss.starFisrt:setImageSource("/mods/game_cyclopedia/images/icons/star/enable1")

				local secondPercent = data.kills * 100 / baseKill.secondUnlock
				slotPanel.slot2.selectBoss.progressSecond.second:setPercent(secondPercent)

				if secondPercent >= 100 then
					slotPanel.slot2.selectBoss.starSecond:setImageSource("/mods/game_cyclopedia/images/icons/star/enable2")

					local thirdPercent = data.kills * 100 / baseKill.thirdUnlock
					slotPanel.slot2.selectBoss.progressThird.third:setPercent(thirdPercent)
					if thirdPercent >= 100 then
						slotPanel.slot2.selectBoss.progressFirst.first:setImageSource('/mods/game_cyclopedia/images/ui/monster-bar-green')
						slotPanel.slot2.selectBoss.progressSecond.second:setImageSource('/mods/game_cyclopedia/images/ui/monster-bar-green')
						slotPanel.slot2.selectBoss.progressThird.third:setImageSource('/mods/game_cyclopedia/images/ui/monster-bar-green')
						slotPanel.slot2.selectBoss.starThird:setImageSource("/mods/game_cyclopedia/images/icons/star/enable3")
					end
				end
			end

			local removeGold = data.removeGold
			if data.isBoosted == 1 then
				removeGold = 0
			end

			local category = data.category + 1
			local bonusText = slotPanel.slot2.selectBoss.selectedBonusText
			bonusText:setText("Equipment loot bonus: " .. tostring(data.bonusLoot) .. "%")
			slotPanel.slot2.selectBoss.gold.text:setText(comma_value(removeGold))
			slotPanel.slot2.selectBoss.iconBosstiary:setImageSource('/mods/game_cyclopedia/images/icons/icon-bosstiary-' .. category)
			slotPanel.slot2.selectBoss.iconBosstiary:setTooltip(tr(toolMessages[category], BosstiaryReward[category].prowess, BosstiaryReward[category].expertise, BosstiaryReward[category].mastery))
			slotPanel.slot2.selectBoss.removeButton:setTooltip(tr("It will cost you %s gold to remove the currently selected boss from this slot.", comma_value(removeGold)))
			slotPanel.slot2.selectBoss.removeButton:setActionId(2)

			local player = g_game.getLocalPlayer()
			local bankMoney = player:getResourceValue(ResourceBank)
			local characterMoney = player:getResourceValue(ResourceInventary)

			if bankMoney + characterMoney < removeGold then
				slotPanel.slot2.selectBoss.removeButton:disable()
				slotPanel.slot2.selectBoss.gold.text:setColor("#d33c3c")
			else
				slotPanel.slot2.selectBoss.removeButton:enable()
				slotPanel.slot2.selectBoss.gold.text:setColor("#c0c0c0")
			end
		end
	else
		setSlotLocked(slotPanel.slot2, 2, data.raceID)
	end
end

local function updateMonsterName(monsterName)
	local maxCharacters = 14
	local finalName = "Boosted Boss: "

	if string.len(monsterName) > maxCharacters then
	  finalName = finalName .. string.sub(monsterName, 1, maxCharacters) .. "..."
	else
	  finalName = finalName .. monsterName
	end

	slotPanel.slot3:setText(string.capitalize(finalName))
end

function BosstiarySlot.showBoostedSlot(data)
	data = normalizeSlotData(data)
	local monster = g_things.getMonsterList()[data.raceID]
	if not monster then
		slotPanel.slot3:setText(tr("Boosted Boss: Unavailable"))
		return
	end
	local baseKill = baseKillData[data.category + 1]
	local baseReward = baseRewardData[data.category + 1]
	if not baseKill or not baseReward then
		slotPanel.slot3:setText(tr("Boosted Boss: Unavailable"))
		return
	end

	updateMonsterName(monster[1])
	slotPanel.slot3.monster.outfit:setOutfit({type = monster[2], auxType = monster[3], head = monster[4], body = monster[5], legs = monster[6], feet = monster[7], addons = monster[8]})
	if slotPanel.slot3.monster.outfit.setStaticWalking then
		slotPanel.slot3.monster.outfit:setStaticWalking(true)
	elseif slotPanel.slot3.monster.outfit.getCreature and slotPanel.slot3.monster.outfit:getCreature() then
		slotPanel.slot3.monster.outfit:getCreature():setStaticWalking(1000)
	end
	if slotPanel.slot3.monster.outfit.setAnimate then
		slotPanel.slot3.monster.outfit:setAnimate(true)
	end

	slotPanel.slot3.first:setTooltip(tr("%s / %s", comma_value(data.kills), comma_value(baseKill.firstUnlock)))
	slotPanel.slot3.second:setTooltip(tr("%s / %s", comma_value(data.kills), comma_value(baseKill.secondUnlock)))
	slotPanel.slot3.third:setTooltip(tr("%s / %s", comma_value(data.kills), comma_value(baseKill.thirdUnlock)))

	local percent = data.kills * 100 / baseKill.firstUnlock
	slotPanel.slot3.first:setPercent(percent)
	if percent >= 100 then
		slotPanel.slot3.starFisrt:setImageSource("/mods/game_cyclopedia/images/icons/star/enable1")
		percent = data.kills * 100 / baseKill.secondUnlock
		slotPanel.slot3.second:setPercent(percent)

		if percent >= 100 then
			slotPanel.slot3.starSecond:setImageSource("/mods/game_cyclopedia/images/icons/star/enable2")
			percent = data.kills * 100 / baseKill.thirdUnlock
			slotPanel.slot3.third:setPercent(percent)

			if percent >= 100 then
				slotPanel.slot3.first:setImageSource('/mods/game_cyclopedia/images/ui/monster-bar-green')
				slotPanel.slot3.second:setImageSource('/mods/game_cyclopedia/images/ui/monster-bar-green')
				slotPanel.slot3.third:setImageSource('/mods/game_cyclopedia/images/ui/monster-bar-green')
				slotPanel.slot3.starThird:setImageSource("/mods/game_cyclopedia/images/icons/star/enable3")
			end
		end
	end

	local category = data.category + 1
	slotPanel.slot3.second.counter:setText(data.kills)
	slotPanel.slot3.iconBosstiary:setImageSource('/mods/game_cyclopedia/images/icons/icon-bosstiary-' .. data.category + 1)
	slotPanel.slotCenterText:setText("Equipment loot bonus: " .. data.bonusLoot .. "%\n            Kill bonus: " .. data.bonusKill .. "x")
	slotPanel.slot3.iconBosstiary:setTooltip(tr(toolMessages[category], BosstiaryReward[category].prowess, BosstiaryReward[category].expertise, BosstiaryReward[category].mastery))
end

function BosstiarySlot.clearSearch(widget, button)
	local textBox = widget:backwardsGetWidgetById('searchText')
	if #textBox:getText() == 0 then
		return
	end

	textBox:clearText()
	BosstiarySlot.onSearchChange(textBox)
end

function BosstiarySlot.onSearchChange(widget)
	filterText[widget:getActionId()] = widget:getText()
	if widget:getActionId() == 1 then
		BosstiarySlot.showFirstSlot(slotData[1], filterText[widget:getActionId()])
	else
		BosstiarySlot.showSecondSlot(slotData[2], filterText[widget:getActionId()])
	end
end

function BosstiarySlot.onSelectBoss(list)
	if list:getChildCount() == 0 then
		return
	end

	local focused = list:getFocusedChild()
	if not focused then
		return
	end

	local creature = focused:recursiveGetChildById('bossOutfit')
	local textBox = focused:backwardsGetWidgetById('searchText')
	textBox:clearText()

	filterText[creature:getActionId()] = ''
	g_game.sendBosstiarySlotAction(creature:getActionId(), creature:getRaceID())
end

function BosstiarySlot.onRemoveCreature(widget)
   g_game.sendBosstiarySlotAction(widget:getActionId(), 0)
end
