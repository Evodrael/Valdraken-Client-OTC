skillsWindow = nil
storeXPButton = nil

local storeBoostTimerEvent = nil
local storeBoostTime = 0

local healthUpdateEvent = nil
local manaUpdateEvent = nil
local lastHealthValue = nil
local lastManaValue = nil

skillWidgetsOptions = {}

local skillNames = {
  [0] = "Fist",
  [1] = "Club",
  [2] = "Sword",
  [3] = "Axe",
  [4] = "Distance",
  [5] = "Shielding",
  [6] = "Fishing",
  [13] = "Magic Level"
}

local combatNames = {
  [0] = "Physical",
  [1] = "Fire",
  [2] = "Earth",
  [3] = "Energy",
  [4] = "Ice",
  [5] = "Holy",
  [6] = "Death",
  [7] = "Healing",
  [8] = "Drowning",
  [9] = "Life Drain",
  [10] = "Mana Drain",
  [11] = "Agony"
}

local function roundPercent(value)
  value = tonumber(value) or 0
  if math.abs(value) < 0.005 then
    return 0
  end
  return math.floor(value * 100 + 0.5) / 100
end

local function percentLabel(value)
  local rounded = roundPercent(value)
  if rounded == math.floor(rounded) then
    return tostring(rounded)
  end

  return string.format("%.2f", rounded):gsub("0+$", ""):gsub("%.$", "")
end

-- Otc::LastSkill in const.h equals 17 — anything >= that reads past the
-- bounded m_skills array on the C++ side and returns junk. Guard before
-- calling getSkillLevel so we never display memory garbage as a percent.
local LEGACY_SKILL_MAX = 16

local function getLegacySpecialSkill(player, skill)
  if not player or not skill or tonumber(skill) == nil then
    return 0
  end

  local skillId = tonumber(skill)
  if skillId < 0 or skillId > LEGACY_SKILL_MAX then
    return 0
  end

  if player.getSpecialSkill then
    local ok, value = pcall(function() return player:getSpecialSkill(skillId) end)
    if ok then
      return tonumber(value) or 0
    end
  end

  if player.getSkillLevel then
    local ok, value = pcall(function() return player:getSkillLevel(skillId) end)
    if ok then
      return tonumber(value) or 0
    end
  end

  return 0
end

local function getCharacterStatPercent(player, getter, fallbackSkill)
  if player and g_game.getFeature(GameCharacterSkillStats) and player[getter] then
    local ok, value = pcall(function() return player[getter](player) end)
    if ok then
      local native = tonumber(value) or 0
      if native ~= 0 then
        return native
      end
      -- Native returned 0; some servers still push these via the forge skill
      -- block (Otc::Fatal..Otc::Transcendence) instead of the imbuements /
      -- defense / forge-bonus doubles. Fall back to getSkillLevel so the
      -- panel reflects the value the server actually delivered.
      local legacy = getLegacySpecialSkill(player, fallbackSkill)
      if legacy ~= 0 then
        return legacy
      end
      return native
    end
  end

  return getLegacySpecialSkill(player, fallbackSkill)
end

local function normalizeCombatAbsorbValues(values)
  local result = {}
  if not values then
    return result
  end

  for element, value in pairs(values) do
    local index = tonumber(element)
    if index then
      result[index + 1] = roundPercent(value * 100)
    end
  end

  return result
end

local temporaryBonusDescription = {
  [1] = "Your potions and healing spells will heal 20% more\nwhen used on yourself.",
  [2] = "All your damage and defenses against monsters will\nincrease by 15%.",
  [3] = "You will receive a general bonus of 20% on acquired\nexperience.",
  [4] = "Gain a additional 8% of mana leech.",
  [5] = "The Exaltation Overload effect will be applied\nto you."
}

function init()
  connect(LocalPlayer, {
    onExperienceChange = onExperienceChange,
    onLevelChange = onLevelChange,
    onHealthChange = onHealthChange,
    onManaChange = onManaChange,
    onSoulChange = onSoulChange,
    onFreeCapacityChange = onFreeCapacityChange,
    onTotalCapacityChange = onTotalCapacityChange,
    onBaseCapacityChange = onBaseCapacityChange,
    onStaminaChange = onStaminaChange,
    onOfflineTrainingChange = onOfflineTrainingChange,
    onRegenerationChange = onRegenerationChange,
    onSpeedChange = onSpeedChange,
    onBaseSpeedChange = onBaseSpeedChange,
    onMagicLevelChange = onMagicLevelChange,
    onBaseMagicLevelChange = onBaseMagicLevelChange,
    onSkillChange = onSkillChange,
    onBaseSkillChange = onBaseSkillChange,
	  onUpdateGainRate = onUpdateGainRate,
	  onExpBoostChange = onExpBoostChange,
	  onUpdateOffenceStats = onUpdateOffenceStats,
    onUpdateDefenceStats = onUpdateDefenceStats,
    onUpdateMiscStats = onUpdateMiscStats,
    onFlatDamageHealingChange = onCharacterSkillStatsChange,
    onAttackInfoChange = onCharacterSkillStatsChange,
    onConvertedDamageChange = onCharacterSkillStatsChange,
    onImbuementsChange = onCharacterSkillStatsChange,
    onDefenseInfoChange = onCharacterSkillStatsChange,
    onCombatAbsorbValuesChange = onCombatAbsorbValuesChange,
    onForgeBonusesChange = onCharacterSkillStatsChange,
    onTemporaryBonusChange = onTemporaryBonusChange,
    onBattlePassBonusChange = onBattlePassBonusChange,
    onMagicBoostChange = onMagicBoostChange,
  })
  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = offline
  })

  skillsWindow = g_ui.loadUI('skills')
  storeXPButton = skillsWindow:recursiveGetChildById('boostButton')
  skillsWindow:hide()

  -- this disables scrollbar auto hiding
  local scrollbar = skillsWindow:getChildById('miniwindowScrollBar')
  scrollbar:mergeStyle({ ['$!on'] = { }})

  skillsWindow.onMouseRelease = function(widget, mousePos, mouseButton)
    if mouseButton == MouseRightButton then
      showSkillsPopUp(mousePos)
    end
  end

  refresh()
  skillsWindow:setup()
end

function terminate()
  if healthUpdateEvent then
    removeEvent(healthUpdateEvent)
    healthUpdateEvent = nil
  end

  if manaUpdateEvent then
    removeEvent(manaUpdateEvent)
    manaUpdateEvent = nil
  end

  disconnect(LocalPlayer, {
    onExperienceChange = onExperienceChange,
    onLevelChange = onLevelChange,
    onHealthChange = onHealthChange,
    onManaChange = onManaChange,
    onSoulChange = onSoulChange,
    onFreeCapacityChange = onFreeCapacityChange,
    onTotalCapacityChange = onTotalCapacityChange,
    onBaseCapacityChange = onBaseCapacityChange,
    onStaminaChange = onStaminaChange,
    onOfflineTrainingChange = onOfflineTrainingChange,
    onRegenerationChange = onRegenerationChange,
    onSpeedChange = onSpeedChange,
    onBaseSpeedChange = onBaseSpeedChange,
    onMagicLevelChange = onMagicLevelChange,
    onBaseMagicLevelChange = onBaseMagicLevelChange,
    onSkillChange = onSkillChange,
    onBaseSkillChange = onBaseSkillChange,
	  onUpdateGainRate = onUpdateGainRate,
	  onExpBoostChange = onExpBoostChange,
	  onUpdateOffenceStats = onUpdateOffenceStats,
    onUpdateDefenceStats = onUpdateDefenceStats,
    onUpdateMiscStats = onUpdateMiscStats,
    onFlatDamageHealingChange = onCharacterSkillStatsChange,
    onAttackInfoChange = onCharacterSkillStatsChange,
    onConvertedDamageChange = onCharacterSkillStatsChange,
    onImbuementsChange = onCharacterSkillStatsChange,
    onDefenseInfoChange = onCharacterSkillStatsChange,
    onCombatAbsorbValuesChange = onCombatAbsorbValuesChange,
    onForgeBonusesChange = onCharacterSkillStatsChange,
    onTemporaryBonusChange = onTemporaryBonusChange,
    onBattlePassBonusChange = onBattlePassBonusChange,
    onMagicBoostChange = onMagicBoostChange,
  })
  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = offline
  })

  skillsWindow:destroy()
end

function expForLevel(level)
  return math.floor((50*level*level*level)/3 - 100*level*level + (850*level)/3 - 200)
end

function expToAdvance(currentLevel, currentExp)
  return expForLevel(currentLevel+1) - currentExp
end

function resetSkillColor(id)
  local skill = skillsWindow:recursiveGetChildById(id)
  if not skill then
	return
  end
  local widget = skill:getChildById('value')
  widget:setColor('#bbbbbb')
end

function toggleSkill(id, state)
  local skill = skillsWindow:recursiveGetChildById(id)
  if not skill then
	return
  end
  skill:setVisible(state)
  scheduleEvent(function()
    skillsWindow:setContentMaximumHeight(math.max(125, getContentPanelHeight() + 6))
  end, 100)
end

function showOrHidePercentBar(skillId)
  if skillId then
    local skill = skillsWindow:recursiveGetChildById(skillId)
    local percentBar = skill:getChildById('percent')
    local skillIcon = skill:getChildById('skillIcon')
    local toggleVisible = not percentBar:isVisible()
    percentBar:setVisible(toggleVisible)
    if toggleVisible then
      skill:setHeight(21)
      for k, v in pairs(skillWidgetsOptions["invisibleProgressBars"]) do
        if v == skillId then
          table.remove(skillWidgetsOptions["invisibleProgressBars"], k)
          break
        end
      end
    else
      skill:setHeight(21 - 7)
      table.insert(skillWidgetsOptions["invisibleProgressBars"], skillId)
    end

    if skillIcon then
      skillIcon:setVisible(toggleVisible)
    end

    scheduleEvent(function()
      skillsWindow:setContentMaximumHeight(math.max(125, getContentPanelHeight() + 6))
    end, 100)
    return
  end

  -- Hide/Show all
  local options = {"level", "stamina", "offlineTraining", "magiclevel"}
  for i = Skill.Fist, Skill.Fishing do
    table.insert(options, "skillId"..i)
  end

  local isVisible = #skillWidgetsOptions["invisibleProgressBars"] == 0
  for _, skillId in pairs(options) do
    local skill = skillsWindow:recursiveGetChildById(skillId)
    local percentBar = skill:getChildById('percent')
    local skillIcon = skill:getChildById('skillIcon')
    if skillIcon then
      skillIcon:setVisible(not isVisible)
    end

    if isVisible then
      percentBar:setVisible(false)
      skill:setHeight(21 - 7)
      table.insert(skillWidgetsOptions["invisibleProgressBars"], skillId)
    else
      percentBar:setVisible(true)
      skill:setHeight(21)
      for k, v in pairs(skillWidgetsOptions["invisibleProgressBars"]) do
        if v == skillId then
          table.remove(skillWidgetsOptions["invisibleProgressBars"], k)
          break
        end
      end
    end
  end

  scheduleEvent(function()
    skillsWindow:setContentMaximumHeight(math.max(125, getContentPanelHeight() + 6))
  end, 100)
end

function updateVisblePercentBar()
  for i = Skill.Fist, Skill.Fishing do
    local skillId = "skillId"..i
    local skill = skillsWindow:recursiveGetChildById(skillId)
    local percentBar = skill:getChildById('percent')
    local skillIcon = skill:getChildById('skillIcon')
    if table.find(skillWidgetsOptions["invisibleProgressBars"], skillId) == nil then
      percentBar:setVisible(true)
      skill:setHeight(21)
      if skillIcon then
        skillIcon:setVisible(true)
      end
    else
      percentBar:setVisible(false)
      skill:setHeight(21 - 7)
      if skillIcon then
        skillIcon:setVisible(false)
      end
    end
  end
end

function resetPercentVisibility()
  local options = {"level", "stamina", "offlineTraining", "magiclevel"}
  for i = Skill.Fist, Skill.Fishing do
    table.insert(options, "skillId"..i)
  end

  for _, skillId in pairs(options) do
    local skill = skillsWindow:recursiveGetChildById(skillId)
    local percentBar = skill:getChildById('percent')
    percentBar:setVisible(true)
    skill:setHeight(21)
  end
end

function getContentPanelHeight()
  local calculatedHeight = 0
  local contentPanel = skillsWindow:recursiveGetChildById("contentsPanel")
  if not contentPanel then
    return 0
  end

  for _, widget in pairs(contentPanel:getChildren()) do
    if widget:isVisible() then
      calculatedHeight = calculatedHeight + widget:getHeight()

      if widget:getMarginTop() > 0 then
        calculatedHeight = calculatedHeight + widget:getMarginTop()
      end

      if widget:getId() == 'miscPanel' and widget:getMarginBottom() > 0 then
        calculatedHeight = calculatedHeight + widget:getMarginBottom() + 8
      end
    end
  end
  return calculatedHeight
end

function showSkillsPopUp(mousePosition)
  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)
  menu:addOption(tr('Reset Experience Counter'), function() g_game.getLocalPlayer().expSpeed = 0; end) -- aqui tem que trocar a tooltip tbm
  menu:addSeparator()
  menu:addCheckBoxOption(tr('Level'), function() showOrHidePercentBar("level") end, "", table.find(skillWidgetsOptions["invisibleProgressBars"], "level") == nil)
  menu:addCheckBoxOption(tr('Stamina'), function() showOrHidePercentBar("stamina") end, "", table.find(skillWidgetsOptions["invisibleProgressBars"], "stamina") == nil)
  menu:addCheckBoxOption(tr('Offline Training'), function() showOrHidePercentBar("offlineTraining") end, "", table.find(skillWidgetsOptions["invisibleProgressBars"], "offlineTraining") == nil)
  menu:addCheckBoxOption(tr('Magic'), function() showOrHidePercentBar("magiclevel") end, "", table.find(skillWidgetsOptions["invisibleProgressBars"], "magiclevel") == nil)
  for i = Skill.Fist, Skill.Fishing do
    local skillName = skillNames[i]
    menu:addCheckBoxOption(tr(skillName), function() showOrHidePercentBar("skillId"..i) end, "", table.find(skillWidgetsOptions["invisibleProgressBars"], "skillId"..i) == nil)
  end

  menu:addSeparator()
  menu:addCheckBoxOption(tr('Offence Stats'), function()
    local currentState = skillWidgetsOptions["offenceStatsVisible"]
    manageOffenceStats(not currentState)
    skillWidgetsOptions["offenceStatsVisible"] = not currentState
  end, "", skillWidgetsOptions["offenceStatsVisible"])

  menu:addCheckBoxOption(tr('Defence Stats'), function()
    local currentState = skillWidgetsOptions["defenceStatsVisible"]
    manageDefenceStats(not currentState)
    skillWidgetsOptions["defenceStatsVisible"] = not currentState
  end, "", skillWidgetsOptions["defenceStatsVisible"])

  menu:addCheckBoxOption(tr('Misc. Stats'), function()
    local currentState = skillWidgetsOptions["miscStatsVisible"]
    manageMiscStats(not currentState)
    skillWidgetsOptions["miscStatsVisible"] = not currentState
  end, "", skillWidgetsOptions["miscStatsVisible"])

  menu:addSeparator()
  menu:addCheckBoxOption(tr('Show all Skill Bars'), function() showOrHidePercentBar(nil) end, "", #skillWidgetsOptions["invisibleProgressBars"] == 0)

  menu:display(mousePosition)
end

function setSkillBase(id, value, baseValue, loyalty)
  if loyalty == nil then
    loyalty = 0
  end

  local skill = skillsWindow:recursiveGetChildById(id)
  if not skill then
    return
  end

  local converId = id:gsub("%D", "")
  local skillNumber = tonumber(converId)
  if skillNumber and skillNumber >= 7 then
    return
  end

  local widget = skill:getChildById('value')
  local percentWidget = skill:getChildById('percent')

  skill:removeTooltip()
  widget:setColor('#bbbbbb')

  local additionalTooltip = ''
  if id == 'magiclevel' then
    local magicBoost = g_game.getLocalPlayer():getMagicBoosts()
    if table.size(magicBoost) > 0 then
      additionalTooltip = tr('\n\nAdditional magic level modifiers:')
      for i, count in pairs(magicBoost) do
        additionalTooltip = additionalTooltip .. string.format("\n%s magic level +%d", combatNames[i], count)
      end
    end
  end

  -- OTZudo loyalty flat bonus: the authoritative number comes from the
  -- server via opcode 202 → action "loyalty_info" (see mods/game_store/store.lua).
  -- Read from _G because game_store and game_skills live in separate sandboxed
  -- _ENV tables — a plain `LoyaltyInfo` reference here would resolve to nil.
  local loyaltyFlatBonus = 0
  local loyaltyInfo = _G.LoyaltyInfo
  if loyaltyInfo and loyaltyInfo.skills and loyaltyInfo.skills[id] then
    loyaltyFlatBonus = tonumber(loyaltyInfo.skills[id]) or 0
  end

  if baseValue < 0 or value < 0 or (baseValue == value and loyaltyFlatBonus == 0) then
    if percentWidget then
      local tooltip = ''
      if loyalty > 0 then
        tooltip = tr("%s+%s Loyalty\n", baseValue, loyalty)
      end
      local percent = tr('%sYou have %s percent to go%s', tooltip, convertSkillPercent(10000 - (percentWidget:getPercent() * 100), false), additionalTooltip)
      percentWidget:setTooltip(percent)
      skill:setTooltip(percent)
    end
    return
  end

  local realBase = baseValue + loyalty
  local realValue = value + loyalty

  if value > baseValue or (realBase > baseValue) or loyaltyFlatBonus > 0 then
	  -- Tooltip layout: "<realValue> = <base> +<items> (+N Loyalty Points)".
	  -- Item bonuses are computed by subtracting the OTZudo loyalty flat
	  -- bonus and the legacy training-loyalty delta from (value - baseValue)
	  -- so loyalty is only counted under "(+N Loyalty Points)" — matching the
	  -- OTZudo spec which advertises a flat "+N skill" perk per title.
	  local itemBonus = (value - baseValue) - loyaltyFlatBonus - (loyalty or 0)
	  if itemBonus < 0 then itemBonus = 0 end

	  local tooltip = tr("%s = %s", realValue, baseValue)
	  if itemBonus > 0 then
	    tooltip = tr("%s +%s", tooltip, itemBonus)
	  end
	  if loyaltyFlatBonus > 0 then
	    tooltip = tr("%s (+%s Loyalty)", tooltip, loyaltyFlatBonus)
	  elseif (loyalty or 0) > 0 then
	    tooltip = tr("%s (+%s Loyalty)", tooltip, loyalty)
	  end
	  widget:setColor('#44ad25') -- green

    local percentWidget = skill:getChildById('percent')
    if percentWidget then
      local percent = tr('You have %s percent to go', convertSkillPercent(10000 - (percentWidget:getPercent() * 100), false))
      tooltip = tooltip .. '\n' .. percent
      percentWidget:setTooltip(tooltip .. additionalTooltip)
    end

    tooltip = tooltip .. additionalTooltip
    skill:setTooltip(tooltip)
  elseif value < baseValue then
    widget:setColor('#c00000') -- red
    skill:setTooltip(baseValue .. ' ' .. (value - baseValue))
  else
    widget:setColor('#bbbbbb') -- default
    skill:removeTooltip()
  end
end

local function formatCapacityValue(value)
  value = math.floor(tonumber(value) or 0)
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

function setSkillValue(id, value)
  local skill = skillsWindow:recursiveGetChildById(id)
  if not skill then
	  return
  end

  local widget = skill:getChildById('value')
  if value == 0 then
	  widget:setColor('#bbbbbb') -- reset
  end

  if id == 'capacity' then
    local player = g_game.getLocalPlayer()
    if value == 0 then
      widget:setColor('$var-text-cip-store-red')
    elseif player and player:getTotalCapacity() ~= player:getBaseCapacity() then
      widget:setColor('#44ad25') -- green
    else
      widget:setColor('#bbbbbb') -- reset
    end
    local fullValue = math.floor(value)
    value = formatCapacityValue(fullValue)
    skill:setTooltip(tr("Capacity: %s", comma_value(fullValue)))
  end

  if id == 'regenerationTime' then
    local tooltip = "You are hungry.\nEat something to regenerate your and mana over time"
    local hours, minutes, seconds = string.match(value, "(%d%d):(%d%d):(%d%d)")
    if value ~= "00:00:00" then
      if tonumber(hours) > 0 then
        tooltip = tr("You are regenerating hit points and mana for %s hours and %s minutes", hours, minutes)
      else
        tooltip = tr("You are regenerating hit points and mana for %s minutes and %s seconds", minutes, seconds)
      end
    end

    value = hours .. ":" .. minutes
    skill:setTooltip(tooltip)
  end

  widget:setText(value)

  local expLabel = skillsWindow:recursiveGetChildById('expLabel')
  if id == "experience" then
    if widget:getWidth() > 75 then
        expLabel:setText("XP")
    else
        expLabel:setText("Experience")
    end
  end

end

function setSkillColor(id, value)
  local skill = skillsWindow:recursiveGetChildById(id)
  local widget = skill:getChildById('value')
  widget:setColor(value)
end

function setSkillTooltip(id, value)
  local skill = skillsWindow:recursiveGetChildById(id)
  local widget = skill:getChildById('value')
  widget:setTooltip(value)
end

function setSkillPercent(id, percent, tooltip, color)
  local skill = skillsWindow:recursiveGetChildById(id)
  if not skill then
	  return
  end

  local widget = skill:getChildById('percent')
  if widget then
    widget:setPercent(percent)
    if table.contains({'offlineTraining', 'stamina'}, id) then
      widget:setPercent(math.floor(percent))
    end

	if id == 'offlineTraining' then
		widget:setBackgroundColor('#c00000') -- red
	end

    if color then
    	widget:setBackgroundColor(color)
    end

    if not table.empty(skillWidgetsOptions) and table.contains(skillWidgetsOptions["invisibleProgressBars"], id) then
      widget:setVisible(false)
    end
  end
end

function update()
  local offlineTraining = skillsWindow:recursiveGetChildById('offlineTraining')
  if not g_game.getFeature(GameOfflineTrainingTime) then
    offlineTraining:hide()
  else
    offlineTraining:show()
  end

  local regenerationTime = skillsWindow:recursiveGetChildById('regenerationTime')
  if not g_game.getFeature(GamePlayerRegenerationTime) then
    regenerationTime:hide()
  else
    regenerationTime:show()
  end
end

function onGameStart()
  local benchmark = g_clock.millis()
  refresh()
  consoleln("Skills loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function refresh()
  local player = g_game.getLocalPlayer()
  if not player then return end

  skillWidgetsOptions = modules.game_sidebars.getSkillsWidgetConfig()
  if table.empty(skillWidgetsOptions) then
    skillWidgetsOptions = {
      ["contentHeight"] = 0,
      ["contentMaximized"] = true,
      ["invisibleProgressBars"] = {},
      ["defenceStatsVisible"] = true,
      ["miscStatsVisible"] = true,
      ["offenceStatsVisible"] = true
    }
  end

  local missingOptions = {"defenceStatsVisible", "miscStatsVisible", "offenceStatsVisible"}
  for _, option in pairs(missingOptions) do
    if skillWidgetsOptions[option] == nil then
      skillWidgetsOptions[option] = true
    end
  end

  for i = Skill.Fist, Skill.Fishing do
    updateVisblePercentBar()
  end

  manageOffenceStats(skillWidgetsOptions["offenceStatsVisible"])
  manageDefenceStats(skillWidgetsOptions["defenceStatsVisible"])
  manageMiscStats(skillWidgetsOptions["miscStatsVisible"])

  if expSpeedEvent then removeEvent(expSpeedEvent) end
  expSpeedEvent = cycleEvent(checkExpSpeed, 30*1000)

  onExperienceChange(player, player:getExperience())
  onLevelChange(player, player:getLevel(), player:getLevelPercent())
  onHealthChange(player, player:getHealth(), player:getMaxHealth())
  onManaChange(player, player:getMana(), player:getMaxMana())
  onSoulChange(player, player:getSoul())
  onFreeCapacityChange(player, player:getFreeCapacity())
  onTotalCapacityChange(player, player:getFreeCapacity())
  onBaseCapacityChange(player, player:getFreeCapacity())
  onStaminaChange(player, player:getStamina())
  onMagicLevelChange(player, player:getMagicLevel(), player:getMagicLevelPercent())
  onOfflineTrainingChange(player, player:getOfflineTrainingTime())
  onRegenerationChange(player, player:getRegenerationTime())
  onSpeedChange(player, player:getSpeed())
  onMagicBoostChange(player, player:getMagicBoosts())
  onExpBoostChange(player, player:getStoreExpBoostTime(), player:canBuyExpBoost())

  local hasAdditionalSkills = g_game.getFeature(GameAdditionalSkills)
  for i = Skill.Fist, Skill.Fishing do
    onSkillChange(player, i, player:getSkillLevel(i), player:getSkillLevelPercent(i))
    onBaseSkillChange(player, i, player:getSkillBaseLevel(i))
  end

  update()

  if g_game.getFeature(GameCharacterSkillStats) then
    updateCharacterSkillStats(player)
  end

  skillsWindow:setContentMinimumHeight(44)
  if hasAdditionalSkills then
    skillsWindow:setContentMaximumHeight(680)
  else
    skillsWindow:setContentMaximumHeight(390)
  end
end

function updateOffenceStatsFromPlayer(player)
  if not player or not g_game.getFeature(GameCharacterSkillStats) then
    return
  end

  onUpdateOffenceStats(
    player,
    player:getFlatDamageHealing(),
    player:getAttackValue(),
    player:getAttackElement(),
    player:getConvertedDamagePercent(),
    player:getConvertedElement()
  )
end

function updateDefenceStatsFromPlayer(player, absorbValues)
  if not player or not g_game.getFeature(GameCharacterSkillStats) then
    return
  end

  onUpdateDefenceStats(
    player,
    normalizeCombatAbsorbValues(absorbValues or player:getCombatAbsorbValues()),
    player:getDefenseValue(),
    player:getArmorValue(),
    0,
    player:getMitigationPercent(),
    player:getDamageReflection()
  )
end

function updateMiscStatsFromPlayer(player)
  if not player or not g_game.getFeature(GameCharacterSkillStats) then
    return
  end

  onUpdateMiscStats(player)
end

function updateCharacterSkillStats(player)
  updateOffenceStatsFromPlayer(player)
  updateDefenceStatsFromPlayer(player)
  updateMiscStatsFromPlayer(player)
end

function onCharacterSkillStatsChange(localPlayer)
  updateCharacterSkillStats(localPlayer)
end

function onCombatAbsorbValuesChange(localPlayer, absorbValues)
  updateDefenceStatsFromPlayer(localPlayer, absorbValues)
end

function offline()
  if healthUpdateEvent then
    removeEvent(healthUpdateEvent)
    healthUpdateEvent = nil
  end

  if manaUpdateEvent then
    removeEvent(manaUpdateEvent)
    manaUpdateEvent = nil
  end

  if expSpeedEvent then expSpeedEvent:cancel() expSpeedEvent = nil end

  rateHighlightEvent = nil
  resetPercentVisibility()
  skillsWindow:close()
  skillsWindow:setParent(nil)
end

function toggle()
  if modules.game_sidebuttons.isButtonVisible("skillsWidget") then
    skillsWindow:close()
    modules.game_sidebuttons.setButtonVisible("skillsWidget", false)
  else
    skillsWindow:open()
    if m_interface.addToPanels(skillsWindow) then
      skillsWindow:getParent():moveChildToIndex(skillsWindow, #skillsWindow:getParent():getChildren())
      modules.game_sidebuttons.setButtonVisible("skillsWidget", true)

      scheduleEvent(function()
        skillsWindow:setContentMaximumHeight(math.max(125, getContentPanelHeight() + 6))
      end, 100)

    end
  end
end

function close()
  skillsWindow:close()
end

function open()
  skillsWindow:open()
  if m_interface.addToPanels(skillsWindow) then
    skillsWindow:getParent():moveChildToIndex(skillsWindow, #skillsWindow:getParent():getChildren())
    modules.game_sidebuttons.setButtonVisible("skillsWidget", true)
    scheduleEvent(function()
      skillsWindow:setContentMaximumHeight(math.max(125, getContentPanelHeight() + 6))
    end, 100)
  else
    modules.game_sidebuttons.setButtonVisible("skillsWidget", false)
  end
end

function checkExpSpeed()
  local player = g_game.getLocalPlayer()
  if not player then return end

  local currentExp = player:getExperience()
  local currentTime = g_clock.seconds()
  if player.lastExps ~= nil then
    player.expSpeed = (currentExp - player.lastExps[1][1])/(currentTime - player.lastExps[1][2])
    onLevelChange(player, player:getLevel(), player:getLevelPercent())
  else
    player.lastExps = {}
  end
  table.insert(player.lastExps, {currentExp, currentTime})
  if #player.lastExps > 30 then
    table.remove(player.lastExps, 1)
  end
end

function onMiniWindowClose()
  modules.game_sidebuttons.setButtonVisible("skillsWidget", false)
end

function onExperienceChange(localPlayer, value, oldValue)
  if value >= 1*(1000000000000000) then
    setSkillValue('experience', "1kkkk+")
  else
    setSkillValue('experience', comma_value(value))
  end
end

function onLevelChange(localPlayer, value, percent)
  setSkillValue('level', comma_value(value))
  local levelLabel = skillsWindow:recursiveGetChildById('level')
  levelLabel:recursiveGetChildById('percent'):setTooltip(tr('You have %s percent to go', 100 - percent))

  local text = tr("%s XP for next level", comma_value(expToAdvance(localPlayer:getLevel(), localPlayer:getExperience())))
  if localPlayer.expSpeed ~= nil then
     local expPerHour = math.floor(localPlayer.expSpeed * 3600)
     if expPerHour > 0 then
        local nextLevelExp = expForLevel(localPlayer:getLevel()+1)
        local hoursLeft = (nextLevelExp - localPlayer:getExperience()) / expPerHour
        local minutesLeft = math.floor((hoursLeft - math.floor(hoursLeft))*60)
        hoursLeft = math.floor(hoursLeft)
        text = text .. '\n' .. tr('currently %s XP per hour, next level in %d hours and %d minutes', comma_value(expPerHour), hoursLeft, minutesLeft)
     end
  end

  local experienceLabel = skillsWindow:recursiveGetChildById('experience')
  experienceLabel:setTooltip(text)
  setSkillPercent('level', percent)
  modules.game_topbar.updateLevelTooltip(text)
end

function onHealthChange(localPlayer, health, maxHealth)
  lastHealthValue = health

  if healthUpdateEvent then
    removeEvent(healthUpdateEvent)
  end

  healthUpdateEvent = scheduleEvent(function()
    setSkillValue('health', lastHealthValue)
    healthUpdateEvent = nil
  end, 50) -- 50ms debounce delay
end

function onManaChange(localPlayer, mana, maxMana)
  lastManaValue = mana

  if manaUpdateEvent then
    removeEvent(manaUpdateEvent)
  end

  manaUpdateEvent = scheduleEvent(function()
    setSkillValue('mana', lastManaValue)
    manaUpdateEvent = nil
  end, 50) -- 50ms debounce delay
end

function onSoulChange(localPlayer, soul)
  setSkillValue('soul', soul)
end

function onFreeCapacityChange(localPlayer, freeCapacity)
  setSkillValue('capacity', freeCapacity)
end

function onTotalCapacityChange(localPlayer, totalCapacity)
  local player = g_game.getLocalPlayer()
  setSkillValue('capacity', player and player:getFreeCapacity() or 0)
end

function onBaseCapacityChange(localPlayer, totalCapacity)
  local player = g_game.getLocalPlayer()
  setSkillValue('capacity', player and player:getFreeCapacity() or 0)
end

function onStaminaChange(localPlayer, stamina)
	local hours = math.floor(stamina / 60)
	local minutes = stamina % 60
	if minutes < 10 then
		minutes = '0' .. minutes
	end
	local percent = math.floor(100 * stamina / (42 * 60)) -- max is 42 hours --TODO not in all client versions

	setSkillValue('stamina', hours .. ":" .. minutes)

    --TODO not all client versions have premium time
	local text = ""
	if stamina > (39*60) and g_game.getClientVersion() >= 1038 then
		text = tr("You have %s hours and %s minutes left and receive ", hours, minutes) .. "50% more\nexperience (Premium Only)"
		setSkillPercent('stamina', percent, text, 'green')
	elseif stamina > (39*60) and g_game.getClientVersion() < 1038 then
		text = tr("You have %s hours and %s minutes left", hours, minutes) .. '\n' ..
		tr("If you are premium player, you will gain 50%% more experience")
		setSkillPercent('stamina', percent, text, 'green')
	elseif stamina <= (39*60) and stamina > 840 then
		setSkillPercent('stamina', percent, tr("You have %s hours and %s minutes left", hours, minutes), 'orange')
	elseif stamina <= 840 and stamina > 0 then
		text = tr("You have %s hours and %s minutes left", hours, minutes) .. "\n" ..
		tr("You gain only 50%% experience and you don't may gain loot from monsters")
		setSkillPercent('stamina', percent, text, 'red')
	elseif stamina == 0 then
		text = tr("You have %s hours and %s minutes left", hours, minutes) .. "\n" ..
		tr("You don't may receive experience and loot from monsters")
		setSkillPercent('stamina', percent, text, 'black')
	end
end

function onOfflineTrainingChange(localPlayer, offlineTrainingTime)
  if not g_game.getFeature(GameOfflineTrainingTime) then
    return
  end
  local hours = math.floor(offlineTrainingTime / 60)
  local minutes = offlineTrainingTime % 60
  if minutes < 10 then
    minutes = '0' .. minutes
  end
  local percent = 100 * offlineTrainingTime / (12 * 60) -- max is 12 hours

  setSkillValue('offlineTraining', hours .. ":" .. minutes)
  setSkillPercent('offlineTraining', percent, tr('You have %s hours and %s minutes of offline training time left', hours, tostring(tonumber(minutes))))
end

function onRegenerationChange(localPlayer, regenerationTime)
  if not g_game.getFeature(GamePlayerRegenerationTime) or regenerationTime < 0 then
    return
  end

  local hours = math.floor(regenerationTime / 3600)
  local minutes = math.floor((regenerationTime % 3600) / 60)
  local seconds = regenerationTime % 60

  if hours < 10 then
    hours = '0' .. hours
  end
  if minutes < 10 then
    minutes = '0' .. minutes
  end
  if seconds < 10 then
    seconds = '0' .. seconds
  end

  modules.client_settings.onHungryChange(localPlayer, regenerationTime > 0)
  setSkillValue('regenerationTime', hours .. ":" .. minutes .. ":" .. seconds)
end


function onSpeedChange(localPlayer, speed)
  setSkillValue('speed', speed)
  onBaseSpeedChange(localPlayer, localPlayer:getBaseSpeed())
end

function onBaseSpeedChange(localPlayer, baseSpeed)
  setSkillBase('speed', localPlayer:getSpeed(), baseSpeed)
end

function onMagicLevelChange(localPlayer, magiclevel, percent)
  setSkillValue('magiclevel', magiclevel + localPlayer:getMagicLoyalty())
  setSkillPercent('magiclevel', (percent / 100))
  onBaseMagicLevelChange(localPlayer, localPlayer:getBaseMagicLevel())
end

function onBaseMagicLevelChange(localPlayer, baseMagicLevel)
  setSkillBase('magiclevel', localPlayer:getMagicLevel(), baseMagicLevel, localPlayer:getMagicLoyalty())
end

function onSkillChange(localPlayer, id, level, percent)
  setSkillValue('skillId' .. id, (level + localPlayer:getSkillLoyalty(id)))
  setSkillPercent('skillId' .. id, (percent / 100))
  onBaseSkillChange(localPlayer, id, localPlayer:getSkillBaseLevel(id))
end

function onBaseSkillChange(localPlayer, id, baseLevel)
  setSkillBase('skillId'..id, localPlayer:getSkillLevel(id), baseLevel, localPlayer:getSkillLoyalty(id))
end

function onExpBoostChange(localPlayer, time, canBuy)
  storeXPButton:setVisible(canBuy)
  storeBoostTime = time

  if storeBoostTimerEvent then
    removeEvent(storeBoostTimerEvent)
    storeBoostTimerEvent = nil
  end

  onUpdateGainRate(localPlayer, localPlayer:getBaseExpRate(), localPlayer:getLowLevelRate(), localPlayer:getExpBoostRate(), localPlayer:getStaminaRate())

  if time > 0 then
    storeBoostTimerEvent = cycleEvent(function()
      if storeBoostTime > 0 then
        storeBoostTime = storeBoostTime - 1
      end
      onUpdateGainRate(localPlayer, localPlayer:getBaseExpRate(), localPlayer:getLowLevelRate(), localPlayer:getExpBoostRate(), localPlayer:getStaminaRate())
      if storeBoostTime <= 0 and storeBoostTimerEvent then
        removeEvent(storeBoostTimerEvent)
        storeBoostTimerEvent = nil
      end
    end, 1000)
  else
    local storeBoostValue = skillsWindow:recursiveGetChildById('storeBoostValue')
    storeBoostValue:setText('00:00')
    storeBoostValue:setColor("$var-text-cip-store-red")
  end
end

function onTemporaryBonusChange(localPlayer, bonus, endTime)
  local temporaryBoostPanel = skillsWindow:recursiveGetChildById('temporaryBonus')
  if bonus == 0 then
    temporaryBoostPanel:setVisible(false)
    temporaryBoostPanel:removeTooltip()
    return
  end

  local timeLabel = temporaryBoostPanel:getChildById('temporaryBonusValue')
  temporaryBoostPanel:setVisible(true)
  timeLabel:setText('00:00')

  if endTime > 0 then
    local timeLeft = endTime - os.time()
    if timeLeft < 0 then
      temporaryBoostPanel:setVisible(false)
      timeLabel:setText('00:00')
      return
    end

    local hours = math.floor(timeLeft / 3600)
    local minutes = math.floor((timeLeft % 3600) / 60)
    timeLabel:setText(string.format("%d:%d", hours, minutes))
    temporaryBoostPanel:setTooltip(string.format("Current Temporary Bonus:\n- %s", temporaryBonusDescription[bonus] or ""))
  end
end

function onBoostClick()
	g_game.openStore()
	g_game.sendRequestStorePremiumBoost()
end

function onUpdateGainRate(localPlayer, baseRate, lowLevelBonus, expBoost, staminaMulti)
  if not g_game.isOnline() then
    return
  end

  local rate = skillsWindow:recursiveGetChildById('xpGainRate')
  if not rate then
	return
  end

  local totalGainRate = (baseRate + lowLevelBonus + expBoost) * staminaMulti / 100
  local tooltip = tr("Your current XP gain rate amounts to %s%s.", totalGainRate, "%") .. "\nYour XP gain rate is calculated as follows:\n" .. tr("- Base XP gain rate: %s%s", baseRate, "%")
  if lowLevelBonus ~= 0 then
    tooltip = tr("%s\n- Low level bonus: +%s%s ", tooltip, lowLevelBonus, "%") .. "(until level 50)"
  end

  local formattedTime = formatTimeBySeconds(storeBoostTime)

  local storeBoostValue = skillsWindow:recursiveGetChildById('storeBoostValue')
  if storeBoostTime > 0 then
    if expBoost ~= 0 then
      tooltip = tr("%s\n- XP boost: +%s%s ", tooltip, expBoost, "%") .. tr("(%s remaining)", formattedTime)
    end

    storeBoostValue:setText(formattedTime)

    if storeBoostTime <= 300 then
      storeBoostValue:setColor("$var-text-cip-store-red")
    else
      storeBoostValue:setColor("$var-text-cip-color-green")
    end
  elseif storeBoostValue then
    storeBoostValue:setText('00:00')
    storeBoostValue:setColor("$var-text-cip-store-red")
  end

  local storeBoostWidget = skillsWindow:recursiveGetChildById('storeBoost')
  storeBoostWidget:setTooltip(tr("XP boost remaining time: %s", formattedTime .. "\n- Click here to increase your experience gain"))
  storeBoostWidget.onClick = onBoostClick

  if staminaMulti > 100 then
    local staminaStr = tostring(staminaMulti)
    formattedStr = staminaStr:sub(1, 1) .. "." .. staminaStr:sub(2)
    finalStr = tostring(tonumber(formattedStr))
    tooltip = tr("%s\n- Stamina bonus: x%s ", tooltip, finalStr) .. tr("(%s h remaining)", formatTimeByMinutes(localPlayer:getStamina() - 2340))
  end

  local widget = rate:getChildById('value')
  widget:setText(totalGainRate .. "%")
  widget:setColor("$var-text-cip-color-green")
  rate:setTooltip(tooltip)

  if not rateHighlightEvent then
    local endTime = g_clock.millis() + 6000
	  rateHighlightEvent = cycleEvent(function()
      if not g_game.isOnline() or not doHighlight then
        rateHighlightEvent = nil
        return
      end
      doHighlight(endTime)
    end, 200)
  end
end

function instantlyBuyBoost()
  local xpBoostOfferId = 65583
  local xpBoostPrice = nil

  local yesCallback = function()
    if confirmBoostWindow then
      g_game.buyStoreOffer(xpBoostOfferId, 1, "")
      confirmBoostWindow:destroy()
    end
  end

  local noCallback = function()
    if confirmBoostWindow then
      confirmBoostWindow:destroy()
    end
  end

  local message = tr("Do you want to buy a XP boost for %s Rubini Coins?", xpBoostPrice)
  confirmBoostWindow = displayGeneralBox(tr('Warning'), tr(message), {
    { text=tr('Yes'), callback=yesCallback },
    { text=tr('No'), callback=noCallback },
  }, yesCallback, noCallback)

  onEnter = yesCallback
  onEscape = noCallback
end

function doHighlight(endTime)
  if not g_game.isOnline() or not skillsWindow then
    removeEvent(rateHighlightEvent)
    rateHighlightEvent = nil
    return
  end

  local widget = skillsWindow:recursiveGetChildById('gainLabel')
  if not widget then
    removeEvent(rateHighlightEvent)
    rateHighlightEvent = nil
    return
  end

  if widget:getActionId() == 0 then
    widget:setColor('#ebebeb')
    widget:setActionId(1)
  elseif widget:getActionId() == 1 then
    widget:setColor('#dfdfdf')
    widget:setActionId(2)
  elseif widget:getActionId() == 2 then
    widget:setColor('#d6d6d6')
    widget:setActionId(3)
  elseif widget:getActionId() == 3 then
    widget:setColor('#cecece')
    widget:setActionId(4)
  else
    widget:setColor('#c0c0c0')
    widget:setActionId(0)
  end

  if g_clock.millis() >= endTime then
    removeEvent(rateHighlightEvent)
    rateHighlightEvent = nil
    widget:setColor('#c0c0c0')
  end
end

function move(panel, height, index, minimized)
  skillsWindow:setParent(panel)
  skillsWindow:open()

  if minimized then
    skillsWindow:setHeight(height)
    skillsWindow:minimize()
  else
    skillsWindow:maximize()
    skillsWindow:setHeight(height)
  end

  return skillsWindow
end

function getCombatName(combatId)
  return combatNames[combatId] or "Unkown"
end

function manageOffenceStats(state)
  local panel = skillsWindow:recursiveGetChildById("attackPanel")
  local separator = skillsWindow:recursiveGetChildById("attackSeparator")
  panel:setVisible(state)
  separator:setVisible(state)

  scheduleEvent(function()
    skillsWindow:setContentMaximumHeight(math.max(125, getContentPanelHeight() + 6))
  end, 100)
end

function manageDefenceStats(state)
  local panel = skillsWindow:recursiveGetChildById("defencePanel")
  local separator = skillsWindow:recursiveGetChildById("defenceSeparator")
  panel:setVisible(state)
  separator:setVisible(state)

  scheduleEvent(function()
    skillsWindow:setContentMaximumHeight(math.max(125, getContentPanelHeight() + 6))
  end, 100)
end

function manageMiscStats(state)
  local panel = skillsWindow:recursiveGetChildById("miscPanel")
  local separator = skillsWindow:recursiveGetChildById("miscSeparator")
  panel:setVisible(state)
  separator:setVisible(state)

  scheduleEvent(function()
    skillsWindow:setContentMaximumHeight(math.max(125, getContentPanelHeight() + 6))
  end, 100)
end

function onUpdateOffenceStats(player, damageAndHealing, damageValue, damageElement, convertedValue, convertedElement)
  -- Damage and Healing
  local damageHealingWidget = skillsWindow:recursiveGetChildById('damageHealingLabel')
  damageHealingWidget:setText(damageAndHealing)

  -- Attack Value
  local attackWidget = skillsWindow:recursiveGetChildById('attackValue')
  attackWidget:recursiveGetChildById("value"):setText(damageValue)
  attackWidget:recursiveGetChildById("combatIcon"):setImageSource("/mods/game_cyclopedia/images/icons/stats/element_" .. damageElement)

  -- Converted Damage
  local convertedWidget = skillsWindow:recursiveGetChildById('convertedDamage')
  convertedWidget:recursiveGetChildById("value"):setText("+" .. percentLabel(convertedValue) .. "%")
  convertedWidget:recursiveGetChildById("combatIcon"):setImageSource("/mods/game_cyclopedia/images/icons/stats/element_" .. convertedElement)
  convertedWidget:setTooltip(tr(specialTooltips["convertedDamage"], percentLabel(convertedValue), getCombatName(convertedElement)))
  convertedWidget:setVisible(roundPercent(convertedValue) > 0)

  if convertedValue > 10.0 then
    convertedWidget:recursiveGetChildById("nameLabel"):setText("Convert...")
  end

  -- Life Leech
  local lifeWidget = skillsWindow:recursiveGetChildById('lifeLeech')
  local lifeLevel = getCharacterStatPercent(player, "getLifeLeechPercent", Skill.LifeLeechAmount)
  lifeWidget:recursiveGetChildById("value"):setText("+" .. percentLabel(lifeLevel) .. "%")
  lifeWidget:setTooltip(tr(specialTooltips["lifeLeech"], percentLabel(lifeLevel)))
  lifeWidget:setVisible(roundPercent(lifeLevel) > 0)

  -- Mana Leech
  local manaWidget = skillsWindow:recursiveGetChildById('manaLeech')
  local manaLevel = getCharacterStatPercent(player, "getManaLeechPercent", Skill.ManaLeechAmount)
  manaWidget:recursiveGetChildById("value"):setText("+" .. percentLabel(manaLevel) .. "%")
  manaWidget:setTooltip(tr(specialTooltips["manaLeech"], percentLabel(manaLevel)))
  manaWidget:setVisible(roundPercent(manaLevel) > 0)

  -- Critical
  local criticalWidget = skillsWindow:recursiveGetChildById('skillIdHitSeparator')
  local chanceWidget = skillsWindow:recursiveGetChildById('criticalChance')
  local extraDamageWidget = skillsWindow:recursiveGetChildById('criticalDamage')

  local chanceLevel = getCharacterStatPercent(player, "getCriticalChancePercent", Skill.CriticalChance)
  local damageLevel = getCharacterStatPercent(player, "getCriticalDamagePercent", Skill.CriticalDamage)

  chanceWidget:recursiveGetChildById("value"):setText("+" .. percentLabel(chanceLevel) .. "%")
  chanceWidget:setTooltip(tr(specialTooltips["criticalChance"], percentLabel(chanceLevel), percentLabel(damageLevel)))
  extraDamageWidget:recursiveGetChildById("value"):setText("+" .. percentLabel(damageLevel) .. "%")
  extraDamageWidget:setTooltip(tr(specialTooltips["criticalDamage"], percentLabel(chanceLevel), percentLabel(damageLevel)))

  criticalWidget:setVisible(roundPercent(chanceLevel) > 0 or roundPercent(damageLevel) > 0)
  chanceWidget:setVisible(roundPercent(chanceLevel) > 0)
  extraDamageWidget:setVisible(roundPercent(damageLevel) > 0)

  -- Onslaught
  local onslaughtWidget = skillsWindow:recursiveGetChildById('onslaught')
  local onslaughtLevel = getCharacterStatPercent(player, "getOnslaughtChancePercent", Skill.OnslaughtChance)
  onslaughtWidget:recursiveGetChildById('value'):setText("+" .. percentLabel(onslaughtLevel) .. "%")
  onslaughtWidget:setTooltip(tr(specialTooltips["onslaught"], percentLabel(onslaughtLevel)))
  onslaughtWidget:setVisible(roundPercent(onslaughtLevel) > 0)

  scheduleEvent(function()
    skillsWindow:setContentMaximumHeight(math.max(125, getContentPanelHeight() + 6))
  end, 100)
end

function onUpdateDefenceStats(player, elementalProtections, defense, armor, mantra, mitigation, damageReflection)
  -- Combat Defenses
  for i = 0, 11 do
    local value = elementalProtections and elementalProtections[i + 1] or 0
    local elementWidget = skillsWindow:recursiveGetChildById('elementalDefense_' .. i)
    if elementWidget then
      elementWidget:setVisible(value ~= 0)
      elementWidget:recursiveGetChildById("value"):setText(value < 0 and (percentLabel(value) .. "%") or ("+" .. percentLabel(value) .. "%"))
      elementWidget:recursiveGetChildById("value"):setColor(value < 0 and "#ff9854" or "#44ad25")

      local effectStr = value < 0 and "increased" or "reduced"
      local noteStr = specialTooltips["protection_note"]
      elementWidget:setTooltip(tr(specialTooltips["protection"], getCombatName(i), effectStr, percentLabel(value), noteStr))
    end
  end

  -- Defense
  local defenseWidget = skillsWindow:recursiveGetChildById('defenseValue')
  defenseWidget:recursiveGetChildById('value'):setText(defense)

  -- Armor
  local armorWidget = skillsWindow:recursiveGetChildById('armorValue')
  armorWidget:recursiveGetChildById('value'):setText(armor)

  -- Mantra
  local mantraWidget = skillsWindow:recursiveGetChildById('mantraValue')
  mantraWidget:recursiveGetChildById('value'):setText(mantra)

  -- Mitigation
  local mitigationWidget = skillsWindow:recursiveGetChildById('mitigationValue')
  mitigationWidget:recursiveGetChildById('value'):setText("+" .. percentLabel(mitigation) .. "%")

  -- Dodge
  local ruseWidget = skillsWindow:recursiveGetChildById('ruseValue')
  local ruseLevel = getCharacterStatPercent(player, "getDodgeChancePercent", Skill.RuseChance)
  ruseWidget:recursiveGetChildById('value'):setText("+" .. percentLabel(ruseLevel) .. "%")
  ruseWidget:setTooltip(tr(specialTooltips["ruseValue"], percentLabel(ruseLevel)))
  ruseWidget:setVisible(roundPercent(ruseLevel) > 0)

  -- Damage Reflection
  local reflectionWidget = skillsWindow:recursiveGetChildById('reflectionValue')
  reflectionWidget:recursiveGetChildById('value'):setText(damageReflection)
  reflectionWidget:setTooltip(tr(specialTooltips["reflectionValue"], damageReflection))
  reflectionWidget:setVisible(damageReflection > 0)

  scheduleEvent(function()
    skillsWindow:setContentMaximumHeight(math.max(125, getContentPanelHeight() + 6))
  end, 100)
end

function onUpdateMiscStats(player)
  -- Momentum
  local momentumWidget = skillsWindow:recursiveGetChildById('momentumValue')
  local momentumLevel = getCharacterStatPercent(player, "getMomentumChancePercent", Skill.MomentumChance)
  momentumWidget:recursiveGetChildById('value'):setText("+" .. percentLabel(momentumLevel) .. "%")
  momentumWidget:setTooltip(tr(specialTooltips["momentumValue"], percentLabel(momentumLevel)))
  momentumWidget:setVisible(roundPercent(momentumLevel) > 0)

  -- Transcendence
  local transcendenceWidget = skillsWindow:recursiveGetChildById('transcendenceValue')
  local transcendenceLevel = getCharacterStatPercent(player, "getTranscendenceChancePercent", Skill.TranscendenceChance)
  transcendenceWidget:recursiveGetChildById('value'):setText("+" .. percentLabel(transcendenceLevel) .. "%")
  transcendenceWidget:setTooltip(tr(specialTooltips["transcendenceValue"], percentLabel(transcendenceLevel)))
  transcendenceWidget:setVisible(roundPercent(transcendenceLevel) > 0)

  -- Amplification
  -- IMPORTANT: pass nil as fallbackSkill. Amplification has no legacy Skill
  -- enum entry on the C++ side (Otc::LastSkill = 17 is the end sentinel), so
  -- getSkillLevel(17) reads past the m_skills array and returns garbage —
  -- which is where the "39120%" report came from.
  local amplificationWidget = skillsWindow:recursiveGetChildById('amplificationValue')
  local amplificationLevel = getCharacterStatPercent(player, "getAmplificationChancePercent", nil)
  amplificationWidget:recursiveGetChildById('value'):setText("+" .. percentLabel(amplificationLevel) .. "%")
  amplificationWidget:setTooltip(tr(specialTooltips["amplificationValue"], percentLabel(amplificationLevel)))
  amplificationWidget:setVisible(roundPercent(amplificationLevel) > 0)

  scheduleEvent(function()
    skillsWindow:setContentMaximumHeight(math.max(125, getContentPanelHeight() + 6))
  end, 100)
end

local boostedBattlePassBonuses = {
  [1] = "Double Experience",
  [2] = "Double Skill",
  [3] = "Double Regeneration",
  [4] = "Exaltation Overload",
  [5] = "Extra Skill"
}

function onBattlePassBonusChange(localPlayer, bonuses)
  local battlePassBoostPanel = skillsWindow:recursiveGetChildById('battlePass')
  if #bonuses == 0 then
    battlePassBoostPanel:setVisible(false)
    battlePassBoostPanel:removeTooltip()
    return
  end

  battlePassBoostPanel:setVisible(true)
  local tooltip = "Current Battle Pass Bonuses:"
  for _, bonus in pairs(bonuses) do
    local stringFormat = "\n%s is active for another %s."
    local stringSkillFormat = "\n+%d extra skill %s fighting is active for another %s."
    local bonusName = boostedBattlePassBonuses[bonus[1]] or "Unknown Bonus"
    local timeLeft = bonus[2]
    local hours = math.floor(timeLeft / 3600)
    local minutes = math.floor((timeLeft % 3600) / 60)
    local timeString = string.format("%d hours and %02d minutes", hours, minutes)
    if hours == 0 then
      timeString = string.format("%02d minutes", minutes)
    end
    if bonus[1] == 5 then
      tooltip = tooltip .. stringSkillFormat:format(bonus[3], skillNames[bonus[4]]:lower(), timeString)
    else
      tooltip = tooltip .. stringFormat:format(bonusName, timeString)
    end

    if bonus[1] == 1 then
      local xpBoostValue = skillsWindow:recursiveGetChildById('battlePassBoostValue')

      xpBoostValue:setText(string.format("%02d:%02d", hours, minutes))
      xpBoostValue:setColor("$var-text-cip-color-green")
      xpBoostValue:setTooltip(tr("Double Experience Boost active for another %s", timeString))
    end

    battlePassBoostPanel:setTooltip(tooltip)
  end

end

function onPlayerUnload()
  if skillWidgetsOptions then
    modules.game_sidebars.registerSkillWidgetsConfig(skillWidgetsOptions)
  end
end

function onMagicBoostChange(localPlayer, magicBoosts)
  setSkillBase('magiclevel', localPlayer:getMagicLevel(), localPlayer:getBaseMagicLevel(), localPlayer:getMagicLoyalty())
end
