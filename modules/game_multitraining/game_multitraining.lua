multiTrainingWindow = nil

-- Maps skill name -> server skillType byte (matches parseStartOfflineTraining on server)
local SKILL_TYPE = {
  fist     = 0,
  club     = 1,
  sword    = 2,
  axe      = 3,
  distance = 4,
  magic    = 5,
}

-- Maps skill name -> widget id in the window
local SKILL_WIDGET = {
  magic    = 'skillMagic',
  fist     = 'skillFist',
  club     = 'skillClub',
  sword    = 'skillSword',
  axe      = 'skillAxe',
  distance = 'skillDistance',
}

function init()
  connect(g_game, {
    onMultiOfflineTrainingDialog = show,
    onSkillChange                = onSkillChange,
    onMagicLevelChange           = onMagicLevelChange,
    onGameEnd                    = hide,
  })
end

function terminate()
  disconnect(g_game, {
    onMultiOfflineTrainingDialog = show,
    onSkillChange                = onSkillChange,
    onMagicLevelChange           = onMagicLevelChange,
    onGameEnd                    = hide,
  })

  if multiTrainingWindow then
    multiTrainingWindow:destroy()
    multiTrainingWindow = nil
  end
end

function show()
  if not multiTrainingWindow then
    multiTrainingWindow = g_ui.displayUI('game_multitraining')
  end

  -- Populate current values when opening
  local player = g_game.getLocalPlayer()
  if player then
    updateSkill('skillMagic',    player:getMagicLevel(),   player:getMagicLevelPercent())
    updateSkill('skillFist',     player:getSkillLevel(Skill.Fist),     player:getSkillLevelPercent(Skill.Fist))
    updateSkill('skillClub',     player:getSkillLevel(Skill.Club),     player:getSkillLevelPercent(Skill.Club))
    updateSkill('skillSword',    player:getSkillLevel(Skill.Sword),    player:getSkillLevelPercent(Skill.Sword))
    updateSkill('skillAxe',      player:getSkillLevel(Skill.Axe),      player:getSkillLevelPercent(Skill.Axe))
    updateSkill('skillDistance', player:getSkillLevel(Skill.Distance), player:getSkillLevelPercent(Skill.Distance))
  end

  multiTrainingWindow:show()
  multiTrainingWindow:raise()
  multiTrainingWindow:focus()
end

function hide()
  if multiTrainingWindow then
    multiTrainingWindow:hide()
  end
end

function updateSkill(widgetId, level, percent)
  if not multiTrainingWindow then return end
  local widget = multiTrainingWindow:getChildById(widgetId)
  if not widget then return end

  local valueLabel = widget:getChildById('value')
  if valueLabel then
    valueLabel:setText(tostring(level))
  end

  local bar = widget:getChildById('percent')
  if bar then
    if bar.setPercent then
      bar:setPercent(math.floor(percent))
    elseif bar.setValue then
      bar:setValue(math.floor(percent), 0, 100)
    end
    bar:setTooltip(tr('You have %s percent to go', 100 - percent))
  end
end

function onMagicLevelChange(player, level, percent)
  updateSkill('skillMagic', level, percent)
end

function onSkillChange(player, skillId, level, percent)
  local map = {
    [Skill.Fist]     = 'skillFist',
    [Skill.Club]     = 'skillClub',
    [Skill.Sword]    = 'skillSword',
    [Skill.Axe]      = 'skillAxe',
    [Skill.Distance] = 'skillDistance',
  }
  local widgetId = map[skillId]
  if widgetId then
    updateSkill(widgetId, level, percent)
  end
end

function onTrainClick(skillName)
  local skillType = SKILL_TYPE[skillName]
  if skillType == nil then return end
  -- OTCV8 binds the same function as `sendStartOfflineTraining` (see
  -- src/client/luafunctions.cpp), so we call that. Falls back to the upstream
  -- name in case someone aliases it later.
  if g_game.sendStartOfflineTraining then
    g_game.sendStartOfflineTraining(skillType)
  elseif g_game.startOfflineTraining then
    g_game.startOfflineTraining(skillType)
  end
  hide()
end
