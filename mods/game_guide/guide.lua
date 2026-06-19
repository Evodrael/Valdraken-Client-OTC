local guideWindow
local lastLevel
local isOnline = false

local COMPENDIUM_FILE = "/data/json/compendium.json"
local GUIDE_ICON = "/images/game/compendium/icon-news-player-guide"
local SPELL_ICON = "/images/game/skills/skill_magic"

local function ensureWindow()
  if guideWindow then
    return true
  end

  guideWindow = g_ui.loadUI("guide", m_interface.getRightPanel())
  if not guideWindow then
    return false
  end

  guideWindow:setup()
  guideWindow:close()
  return true
end

local function getChild(id)
  if not ensureWindow() then
    return nil
  end

  return guideWindow:recursiveGetChildById(id)
end

local function clearList()
  for _, id in ipairs({ "spellRow1", "spellRow2" }) do
    local row = getChild(id)
    if row then
      row:setVisible(false)
      row.onClick = nil
    end
  end
end

local function shortLabel(text, limit)
  text = text or ""
  limit = limit or 18

  if short_text then
    return short_text(text, limit)
  end

  if #text <= limit then
    return text
  end

  return text:sub(1, math.max(1, limit - 3)) .. "..."
end

local function openCompendiumArticle(title)
  if modules.game_compendium and modules.game_compendium.openArticleByTitle then
    modules.game_compendium.openArticleByTitle(title)
    return
  end

  if modules.game_compendium and modules.game_compendium.show then
    modules.game_compendium.show()
  end
end

local function setupGuideButton(buttonId, text, targetTitle)
  local button = getChild(buttonId)
  if not button then
    return
  end

  button:setVisible(true)
  button:setTooltip(text)
  if button.text then
    button.text:setText(shortLabel(text, 19))
  else
    button:setText(shortLabel(text, 19))
  end

  button.onClick = function()
    openCompendiumArticle(targetTitle or text)
  end
end

local function hideButton(buttonId)
  local button = getChild(buttonId)
  if button then
    button:setVisible(false)
    button.onClick = nil
  end
end

local function setupSpellRow(rowId, spell)
  local row = getChild(rowId)
  if not row then
    return
  end

  if not spell then
    row:setVisible(false)
    row.onClick = nil
    return
  end

  row:setVisible(true)
  if row.spellName then
    row.spellName:setText(shortLabel(spell.name, 18))
    row.spellName:setTooltip(spell.name)
  end

  if row.spellIcon then
    local spellId = Spells and Spells.getClientId and Spells.getClientId(spell.name)
    if spellId and Spells.getImageClipNormal then
      row.spellIcon:setImageClip(Spells.getImageClipNormal(spellId, "Default"))
    end
  end

  row.onClick = function()
    openCompendiumArticle(spell.name)
  end
end

local function readCompendium()
  if not g_resources.fileExists(COMPENDIUM_FILE) then
    return {}
  end

  local ok, result = pcall(function()
    return json.decode(g_resources.readFileContents(COMPENDIUM_FILE))
  end)

  if not ok or type(result) ~= "table" or type(result.gamenews) ~= "table" then
    return {}
  end

  return result.gamenews
end

local function getUnlocksForLevel(level)
  local unlocks = {}

  for _, entry in pairs(readCompendium()) do
    if type(entry) == "table" and tonumber(entry.unlocklevel) == level then
      table.insert(unlocks, entry)
    end
  end

  table.sort(unlocks, function(a, b)
    return tostring(a.headline or "") < tostring(b.headline or "")
  end)

  return unlocks
end

local function getSpellsForLevel(level)
  local player = g_game.getLocalPlayer()
  local vocation = player and translateVocation(player:getVocation()) or 0
  local spells = {}

  if not Spells or not Spells.getSpellList then
    return spells
  end

  for _, spell in pairs(Spells.getSpellList()) do
    if spell.level == level and (not spell.vocations or table.contains(spell.vocations, vocation)) then
      table.insert(spells, spell)
    end
  end

  table.sort(spells, function(a, b)
    return tostring(a.name or "") < tostring(b.name or "")
  end)

  return spells
end

local function setLevelHeader(level, visible)
  local levelPanel = getChild("levelPanel")
  local levelLabel = getChild("levelLabel")
  local recentlyLabel = getChild("recentlyLabel")
  local basicsButton = getChild("basicsButton")

  if levelPanel then
    levelPanel:setVisible(visible)
  end

  if levelLabel then
    levelLabel:setText(tostring(level or ""))
  end

  if recentlyLabel then
    recentlyLabel:setVisible(not visible)
  end

  if basicsButton then
    basicsButton:setVisible(not visible)
  end
end

local function populate(level, fromLevelUp)
  clearList()
  setLevelHeader(level, fromLevelUp)

  if not fromLevelUp then
    setupGuideButton("basicsButton", tr("Basics"), "Basics")
  end

  local bottomLabel = getChild("bottomLabel")

  if fromLevelUp then
    local spells = getSpellsForLevel(level)
    if #spells > 0 then
      if bottomLabel then
        bottomLabel:setText(tr("New spells available:"))
      end
      setupSpellRow("spellRow1", spells[1])
      setupSpellRow("spellRow2", spells[2])
      hideButton("unlockButton1")
      hideButton("unlockButton2")
    else
      if bottomLabel then
        bottomLabel:setText(tr("Other unlocks:"))
      end
      setupSpellRow("spellRow1", nil)
      setupSpellRow("spellRow2", nil)
      setupGuideButton("unlockButton1", tr("Combat and Hunting"), "Combat and Hunting")
      setupGuideButton("unlockButton2", tr("NPC Interaction"), "NPC Interaction")
    end
  else
    if bottomLabel then
      bottomLabel:setText(tr("Other unlocks:"))
    end
    setupSpellRow("spellRow1", nil)
    setupSpellRow("spellRow2", nil)
    setupGuideButton("unlockButton1", tr("Combat and Hunting"), "Combat and Hunting")
    setupGuideButton("unlockButton2", tr("NPC Interaction"), "NPC Interaction")
  end
end

local function openForLevel(level, fromLevelUp)
  if not ensureWindow() then
    return
  end

  populate(level, fromLevelUp)
  guideWindow:open()
  if m_interface.addToPanels(guideWindow) then
    guideWindow:getParent():moveChildToIndex(guideWindow, #guideWindow:getParent():getChildren())
    modules.game_sidebuttons.setButtonVisible("playerGuide", true)
  else
    modules.game_sidebuttons.setButtonVisible("playerGuide", false)
  end
end

function init()
  ensureWindow()

  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline
  })

  connect(LocalPlayer, {
    onLevelChange = onLevelChange
  })
end

function terminate()
  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline
  })

  disconnect(LocalPlayer, {
    onLevelChange = onLevelChange
  })

  if guideWindow then
    guideWindow:destroy()
    guideWindow = nil
  end
end

function online()
  local player = g_game.getLocalPlayer()
  isOnline = true
  lastLevel = player and player:getLevel() or nil
end

function offline()
  isOnline = false
  lastLevel = nil
  hide()
end

function show()
  local player = g_game.getLocalPlayer()
  local level = player and player:getLevel() or lastLevel or 1
  openForLevel(level, false)
end

function hide()
  if guideWindow then
    guideWindow:close()
  end
  modules.game_sidebuttons.setButtonVisible("playerGuide", false)
end

function toggle()
  if guideWindow and guideWindow:isVisible() then
    hide()
  else
    show()
  end
end

function onLevelChange(localPlayer, level, levelPercent, oldLevel, oldLevelPercent)
  if not isOnline then
    lastLevel = level
    return
  end

  oldLevel = oldLevel or lastLevel
  lastLevel = level

  if oldLevel and oldLevel > 0 and level and level > oldLevel then
    scheduleEvent(function()
      openForLevel(level, true)
    end, 100)
  end
end

function openCompendium(title)
  openCompendiumArticle(title)
end
