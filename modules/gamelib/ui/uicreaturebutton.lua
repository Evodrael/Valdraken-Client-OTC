-- @docclass
UICreatureButton = extends(UIWidget, "UICreatureButton")
UICreatureButtonList = extends(UIVerticalList, "UICreatureButtonList")

local CreatureButtonColors = {
  onIdle = {notHovered = '#afafaf', hovered = '#f7f7f7' },
  onTargeted = {notHovered = '#df3f3f', hovered = '#f7a3a3' },
  onFollowed = {notHovered = '#3fdf3f', hovered = '#b3f7b3' }
}

local LifeBarColors = {} -- Must be sorted by percentAbove
table.insert(LifeBarColors, {percentAbove = 94, color = '#00C000' } )
table.insert(LifeBarColors, {percentAbove = 59, color = '#60c060' } )
table.insert(LifeBarColors, {percentAbove = 29, color = '#c0c000' } )
table.insert(LifeBarColors, {percentAbove = 9, color = '#c03030' } )
table.insert(LifeBarColors, {percentAbove = 3, color = '#c00000' } )
table.insert(LifeBarColors, {percentAbove = -1, color = '#600000' } )

local function getCreatureIconInfo(icon)
  if type(icon) ~= 'table' then
    return nil, nil
  end

  local iconId = icon.id or icon[1]
  local category = icon.category or icon[2]
  if not iconId then
    return nil, nil
  end

  return iconId, category or CreatureIconCategoryQuest
end

function UICreatureButton.create()
  local button = UICreatureButton.internalCreate()
  button:setFocusable(false)
  button.creature = nil
  button.isHovered = false
  return button
end

function UICreatureButton:setCreature(creature)
    self.creature = creature
end

function UICreatureButton:getCreature()
  return self.creature
end

function UICreatureButton:getCreatureId()
    return self.creature:getId()
end

function UICreatureButton:setup(id)
  self.lifeBarWidget = self:getChildById('lifeBar')
  self.manaBarWidget = self:getChildById('manaBar')
  self.creatureWidget = self:getChildById('creature')
  self.labelWidget = self:getChildById('label')
  self.skullWidget = self:getChildById('skull')
  self.emblemWidget = self:getChildById('emblem')
  self.monster1Widget = self:getChildById('monster1')
  self.monster2Widget = self:getChildById('monster2')
  self.monster3Widget = self:getChildById('monster3')
  self.monster4Widget = self:getChildById('monster4')
  self.monster5Widget = self:getChildById('monster5')
  self.creatureIcons = {}
end

function UICreatureButton:update()
  local color = CreatureButtonColors.onIdle
  local show = false
  if self.creature == g_game.getAttackingCreature() then
    color = CreatureButtonColors.onTargeted
  elseif self.creature == g_game.getFollowingCreature() then
    color = CreatureButtonColors.onFollowed
  end
  color = self.isHovered and color.hovered or color.notHovered

  if self.color == color then
    return
  end
  self.color = color

  if color ~= CreatureButtonColors.onIdle.notHovered then
    self.creatureWidget:setBorderWidth(1)
    self.creatureWidget:setBorderColor(color)
    self.labelWidget:setColor(color)
  else
    self.creatureWidget:setBorderWidth(0)
    self.labelWidget:setColor(color)
  end
end

function UICreatureButton:creatureSetup(creature)
  if self.creature ~= creature then
    self.creature = creature

    local name = creature:getName()
    if #name > 14 then
      self.labelWidget:setText(name:sub(1, 14) .. '...')
      self.labelWidget:setTooltip(name)
    else
      self.labelWidget:setText(name)
      self.labelWidget:removeTooltip()
    end
  end

  self.creatureWidget:setOutfit(creature:getOutfit())
  self.creatureWidget:setDirection(South)

  self:updateLifeBarPercent()
  self:updateManaBarPercent()
  self:updateSkull()
  self:updateEmblem()
  self:updateIcons()

  self:update()
end

function UICreatureButton:updateSkull()
  if not self.creature then
    return
  end
  local skullId = self.creature:getSkull()
  if skullId == self.skullId then
    return
  end
  self.skullId = skullId

  if skullId ~= SkullNone then
    local imagePath = getSkullImagePath(skullId)
    self.skullWidget:setImageSource(imagePath)
    self.skullWidget:setHeight(11)
    self.skullWidget:setWidth(11)
  else
    self.skullWidget:setWidth(0)
  end
end

function UICreatureButton:updateEmblem()
  if not self.creature then
    return
  end
  local emblemId = self.creature:getEmblem()
  if self.emblemId == emblemId then
    return
  end
  self.emblemId = emblemId

  if emblemId ~= EmblemNone then
    local imagePath = getEmblemImagePath(emblemId)
    self.emblemWidget:setImageSource(imagePath)
  else
    self.emblemWidget:setWidth(0)
    self.emblemWidget:setMarginLeft(0)
  end
end

function UICreatureButton:updateLifeBarPercent()
  if not self.creature then
    return
  end
  local percent = self.creature:getHealthPercent()
  self.percent = percent
  self.lifeBarWidget:setPercent(percent)

  local color
  for i, v in pairs(LifeBarColors) do
    if percent > v.percentAbove then
      color = v.color
      break
    end
  end

  self.lifeBarWidget:setBackgroundColor(color)
end

function UICreatureButton:updateManaBarPercent()
  if not self.creature then
    return
  end
  local percent = self.creature:getManaPercent()
  if self.percent == percent then
    return
  end

  self.percent = percent
  self.manaBarWidget:setPercent(percent)
end

function UICreatureButton:updateIcons()
  if not self.creature then
    return
  end

  if self.monster1Widget:getWidth() ~= 0 then
    self.monster1Widget:setWidth(0)
    self.monster1Widget:setMarginLeft(0)
  end

  if self.monster2Widget:getWidth() ~= 0 then
    self.monster2Widget:setWidth(0)
    self.monster2Widget:setMarginLeft(0)
  end

  if self.monster3Widget:getWidth() ~= 0 then
    self.monster3Widget:setWidth(0)
    self.monster3Widget:setMarginLeft(0)
  end

  if self.monster4Widget:getWidth() ~= 0 then
    self.monster4Widget:setWidth(0)
    self.monster4Widget:setMarginLeft(0)
  end

  if table.compare(self.creature:getIcons(), self.creatureIcons) then
    return
  end

  self.creatureIcons = self.creature:getIcons()
  if #self.creature:getIcons() == 0 then
    return
  end

  if not self.creature:isMonster() then
    return
  end

  local count = 0
  for i, icon in pairs(self.creature:getIcons()) do
    local iconId, category = getCreatureIconInfo(icon)
    if iconId then
      local imagePath = "/images/game/icons/" .. (category == CreatureIconCategoryModification and "modifications" or "quests") .. "/" .. iconId
      count = count + 1
      if count == 1 then
        self.monster1Widget:setImageSource(imagePath)
      elseif count == 2 then
        self.monster2Widget:setImageSource(imagePath)
      elseif count == 3 then
        self.monster3Widget:setImageSource(imagePath)
      elseif count == 4 then
        self.monster4Widget:setImageSource(imagePath)
      end

      if count > 4 then
        break
      end
    end
  end

end

local PartyShields = {
  [ShieldWhiteYellow] = true,
  [ShieldWhiteBlue] = true,
  [ShieldBlue] = true,
  [ShieldYellow] = true,
  [ShieldBlueSharedExp] = true,
  [ShieldYellowSharedExp] = true,
  [ShieldBlueNoSharedExpBlink] = true,
  [ShieldYellowNoSharedExpBlink] = true,
  [ShieldBlueNoSharedExp] = true,
  [ShieldYellowNoSharedExp] = true
}

local function isPartyCreature(creature)
  return creature and creature:isPlayer() and PartyShields[creature:getShield()] == true
end

local DefaultCreatureFilters = {
  'showPlayers',
  'showKnights',
  'showPaladins',
  'showDruids',
  'showSorcerers',
  'showMonks',
  'showSummons',
  'showNPCs',
  'showMonsters',
  'showNonSkulled',
  'showParty',
  'showOwnGuilds'
}

function UICreatureButtonList:setupCreatureFilters()
  if self.creatureFilterDefaultsInitialized then
    return
  end

  for _, filter in ipairs(DefaultCreatureFilters) do
    self:setFilter(filter, true)
  end

  self.creatureFilterDefaultsInitialized = true
end

local function getSpectatorsForCreatureList(player)
  local mapPanel = modules.game_interface and modules.game_interface.getMapPanel and modules.game_interface.getMapPanel()
  if mapPanel then
    local spectators = mapPanel:getSpectators(false) or {}
    if #spectators > 0 then
      return spectators
    end
  end

  return g_map.getSpectators(player:getPosition(), false) or {}
end

local function isShownByFilter(panel, creature)
  if not creature or creature:isLocalPlayer() then
    return false
  end

  if creature:isDead() then
    return false
  end

  if panel:isParty() and not isPartyCreature(creature) then
    return false
  end

  if creature:isPlayer() then
    if panel:getFilter('hidePlayers') or panel:getFilter('showPlayers') == false then
      return false
    end

    if panel:getFilter('hideParty') and isPartyCreature(creature) then
      return false
    end

    if panel:getFilter('showParty') == false and isPartyCreature(creature) then
      return false
    end

    if (panel:getFilter('hideNonSkulled') or panel:getFilter('showNonSkulled') == false) and creature:getSkull() == SkullNone then
      return false
    end

    if creature:isKnight() and (panel:getFilter('hideKnights') or panel:getFilter('showKnights') == false) then
      return false
    elseif creature:isPaladin() and (panel:getFilter('hidePaladins') or panel:getFilter('showPaladins') == false) then
      return false
    elseif creature:isDruid() and (panel:getFilter('hideDruids') or panel:getFilter('showDruids') == false) then
      return false
    elseif creature:isSorcerer() and (panel:getFilter('hideSorcerers') or panel:getFilter('showSorcerers') == false) then
      return false
    elseif creature:isMonk() and (panel:getFilter('hideMonks') or panel:getFilter('showMonks') == false) then
      return false
    end
  elseif creature:isNpc() then
    if panel:isParty() or panel:getFilter('hideNPCs') or panel:getFilter('showNPCs') == false then
      return false
    end
  elseif creature:isMonster() then
    if creature:isSummon() or creature:getType() == CreatureTypeSummonOwn or creature:getType() == CreatureTypeSummonOther then
      if panel:getFilter('hideSummons') or panel:getFilter('showSummons') == false then
        return false
      end
    elseif panel:isParty() or panel:getFilter('hideMonsters') or panel:getFilter('showMonsters') == false then
      return false
    end
  end

  return true
end

local function distanceFromLocalPlayer(creature)
  local player = g_game.getLocalPlayer()
  if not player or not creature then
    return 999
  end

  local cpos = creature:getPosition()
  local ppos = player:getPosition()
  if not cpos or not ppos or cpos.z ~= ppos.z then
    return 999
  end

  return math.max(math.abs(cpos.x - ppos.x), math.abs(cpos.y - ppos.y))
end

local function sortCreatures(panel, creatures)
  local sortType = panel:getSortType()
  table.sort(creatures, function(a, b)
    if sortType == 'byNameAscending' or sortType == 'name' then
      return a:getName():lower() < b:getName():lower()
    elseif sortType == 'byNameDescending' then
      return a:getName():lower() > b:getName():lower()
    elseif sortType == 'byDistanceAscending' or sortType == 'distance' then
      return distanceFromLocalPlayer(a) < distanceFromLocalPlayer(b)
    elseif sortType == 'byDistanceDescending' then
      return distanceFromLocalPlayer(a) > distanceFromLocalPlayer(b)
    elseif sortType == 'byHitpointsAscending' or sortType == 'health' then
      return a:getHealthPercent() < b:getHealthPercent()
    elseif sortType == 'byHitpointsDescending' then
      return a:getHealthPercent() > b:getHealthPercent()
    end

    return a:getId() < b:getId()
  end)
end

function UICreatureButtonList:getVisibleCreatures()
  local player = g_game.getLocalPlayer()
  if not player then
    return {}
  end

  local creatures = {}
  for _, creature in pairs(getSpectatorsForCreatureList(player)) do
    if isShownByFilter(self, creature) then
      table.insert(creatures, creature)
    end
  end

  sortCreatures(self, creatures)
  return creatures
end

function UICreatureButtonList:getAttackableCreatures()
  local creatures = {}
  for _, creature in ipairs(UICreatureButtonList.getVisibleCreatures(self)) do
    if not creature:isNpc() and not isPartyCreature(creature) then
      table.insert(creatures, creature)
    end
  end
  return creatures
end

function UICreatureButtonList:getPartyCreatures()
  local player = g_game.getLocalPlayer()
  if not player then
    return {}
  end

  local creatures = {}
  for _, creature in pairs(getSpectatorsForCreatureList(player)) do
    if isPartyCreature(creature) and not creature:isLocalPlayer() then
      table.insert(creatures, creature)
    end
  end

  sortCreatures(self, creatures)
  return creatures
end

function UICreatureButtonList:refreshCreatures()
  local creatures = UICreatureButtonList.getVisibleCreatures(self)
  self.creatureButtons = self.creatureButtons or {}
  self:setHeight(math.max(1, #creatures * (self:isParty() and 38 or 34)))

  local used = {}
  for index, creature in ipairs(creatures) do
    local id = creature:getId()
    local button = self.creatureButtons[id]
    if not button then
      button = g_ui.createWidget('BattleButton', self) or g_ui.createWidget('CreatureButton', self)
      if not button then
        return
      end
      UICreatureButton.setup(button)
      if modules.game_battle and modules.game_battle.onBattleButtonMouseRelease then
        button.onMouseRelease = modules.game_battle.onBattleButtonMouseRelease
      end
      if self:isParty() then
        if button.manaBarWidget then
          button.manaBarWidget:setVisible(true)
        end
        button:setHeight(36)
      end
      self.creatureButtons[id] = button
    end

    UICreatureButton.creatureSetup(button, creature)
    button:show()
    self:moveChildToIndex(button, index)
    used[id] = true
  end

  for id, button in pairs(self.creatureButtons) do
    if not used[id] then
      button:destroy()
      self.creatureButtons[id] = nil
    end
  end
end

function UICreatureButtonList:startCreatureRefresh()
  if self.creatureRefreshEvent then
    return
  end

  UICreatureButtonList.setupCreatureFilters(self)

  local function refresh()
    if self:isDestroyed() then
      return
    end

    if g_game.isOnline() then
      UICreatureButtonList.refreshCreatures(self)
    elseif self.creatureButtons then
      for id, button in pairs(self.creatureButtons) do
        button:destroy()
        self.creatureButtons[id] = nil
      end
    end

    self.creatureRefreshEvent = scheduleEvent(refresh, 250)
  end

  refresh()
end

function UICreatureButtonList:stopCreatureRefresh()
  removeEvent(self.creatureRefreshEvent)
  self.creatureRefreshEvent = nil
end
