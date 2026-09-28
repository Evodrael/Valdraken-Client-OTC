local highscoresWindow
local gameworldbox
local vocationbox
local categorybox
local highscoreTable

local pvpTypesById = {
  ["openPvpCheck"] = 0,
  ["optionalPvpCheck"] = 1,
  ["hardcorePvpCheck"] = 2,
  ["retroOpenPvpCheck"] = 3,
  ["retroHardcorePvpCheck"] = 4,
}

-- O servidor identifica a categoria pelo id do enum HighscoreCategories_t (Experience=0,
-- Fist=1, ...) e a vocacao pelo client-id CIP (None=0/Knight=1/Paladin=2/Sorcerer=3/
-- Druid=4/Monk=5, 0xFFFFFFFF = todas). O callback legado 'onHighscores' entrega apenas
-- as LISTAS DE NOMES, e a versao anterior deste ficheiro mandava de volta o indice da
-- lista: pedir a pagina 2 de "Experience Points" virava categoria 1 (Fist Fighting) e a
-- vocacao ficava presa num id que nao existe. Guardamos aqui os ids verdadeiros, que
-- chegam no callback 'onProcessHighscores' disparado imediatamente antes.
local ALL_VOCATIONS = 0xFFFFFFFF
local categoryIdByName = {}
local vocationIdByName = {}

function init()
  highscoresWindow = g_ui.displayUI('highscores')
  highscoresWindow:hide()

  connect(g_game, {
    onGameEnd = offline,
    onProcessHighscores = onProcessHighscores,
    onHighscores = onHighscores,
  })

  initInterface()
end

function terminate()
  disconnect(g_game, {
    onGameEnd = offline,
    onProcessHighscores = onProcessHighscores,
    onHighscores = onHighscores,
  })

  if highscoresWindow then
    highscoresWindow:destroy()
    highscoresWindow = nil
  end
end

function hide()
  highscoresWindow:hide()
  g_client.setInputLockWidget(nil)
  modules.game_sidebuttons.setButtonVisible("highscoresDialog", false)
end

function show()
  highscoresWindow:show(true)
  highscoresWindow:focus()
  g_client.setInputLockWidget(highscoresWindow)
  modules.game_sidebuttons.setButtonVisible("highscoresDialog", true)
  g_game.highscore(0, 0, 0xFFFFFFFF, g_game.getWorldName(), 1, 20)
end

function offline()
  if modules.game_sidebuttons.isButtonVisible("highscoresDialog") then
    modules.game_sidebuttons.setButtonVisible("highscoresDialog", false)
  end
  hide()
end

function initInterface()
  highscoreTable = highscoresWindow.highscoreList
  gameworldbox = highscoresWindow.filters.gameworldbox
  vocationbox = highscoresWindow.filters.vocationbox
  categorybox = highscoresWindow.filters.categorybox
end

local function getHours(seconds)
  return math.floor((seconds/60)/60)
end

local function getMinutes(seconds)
  return math.floor(seconds/60)
end

local function getSeconds(seconds)
  return seconds%60
end

local function getTimeinWords(secs)
  local hours, minutes, seconds = getHours(secs), getMinutes(secs), getSeconds(secs)
  if (minutes > 59) then
    minutes = minutes-hours*60
  end

  local timeStr = ''

  if hours > 0 then
    timeStr = timeStr .. ' hours '
  end

  if minutes > 0 then
    timeStr = timeStr .. minutes .. ' minutes'
  elseif seconds > 0 then
    timeStr =  seconds .. ' seconds'
  end

  return timeStr
end

-- Callback "cru" do motor: vocations/categories chegam como { {id, nome}, ... }.
-- Dispara sempre logo antes de onHighscores (Game::processHighscore).
function onProcessHighscores(serverName, world, worldType, battlEye, vocations, categories)
  categoryIdByName = {}
  for _, entry in pairs(categories or {}) do
    if entry[2] then
      categoryIdByName[entry[2]] = entry[1]
    end
  end

  vocationIdByName = {}
  for _, entry in pairs(vocations or {}) do
    if entry[2] then
      vocationIdByName[entry[2]] = entry[1]
    end
  end
end

local function categoryIdOf(name)
  return categoryIdByName[name] or 0 -- 0 = Experience Points
end

local function vocationIdOf(name)
  -- "All Vocations" e' inserido pelo C++ e nao vem na lista do servidor.
  return vocationIdByName[name] or ALL_VOCATIONS
end

function onHighscores(worlds, selectedWorld, vocations, selectedVocation, categories, selectedCategory, page, pages, characters, lastUpdate)
  gameworldbox:clearOptions()
  gameworldbox:addOption("All Game Worlds")
  for id, world in pairs(worlds) do
    gameworldbox:addOption(world)
  end

  gameworldbox:setCurrentOption(selectedWorld, false)

  vocationbox:clearOptions()
  for id, vocation in pairs(vocations) do
    vocationbox:addOption(vocation)
  end
  vocationbox:setCurrentOption(vocations[selectedVocation], false)

  categorybox:clearOptions()
  for id, vocation in pairs(categories) do
    categorybox:addOption(vocation)
  end
  categorybox:setCurrentOption(categories[selectedCategory], false)

  highscoreTable:destroyChildren()
  for id, character in pairs(characters) do
    local widget = g_ui.createWidget('ListHighscore', highscoreTable)
    widget.rank:setText(character[1])
    widget.rank:setColor("#c0c0c0")
    widget.name:setText(character[2])
    widget.name:setColor("#c0c0c0")
    widget.vocation:setText(g_game.getVocationName(character[3]))
    widget.vocation:setColor("#c0c0c0")
    widget.gameworld:setText(short_text(character[4], 8))
    widget.gameworld:setColor("#c0c0c0")
    widget.level:setText(character[5])
    widget.level:setColor("#c0c0c0")
    widget:setBackgroundColor((id % 2 == 0 and '#484848' or '#414141'))
    widget.points:setText(comma_value(character[7]))
    widget.points:setColor("#c0c0c0")
    if character[6] then
      widget.rank:setColor("#60f860")
      widget.name:setColor("#60f860")
      widget.vocation:setColor("#60f860")
      widget.gameworld:setColor("#60f860")
      widget.points:setColor("#60f860")
    end
  end

  local rest = 20 - #highscoreTable:getChildren()
  if rest > 0 then
    for i = 1, rest do
      local widget = g_ui.createWidget('ListHighscore', highscoreTable)
      widget:setBackgroundColor((i % 2 == 0 and '#484848' or '#414141'))
    end
  end

  highscoresWindow.page:setText(string.format("%d / %d", page, pages))
  highscoresWindow.page:setColor("#c0c0c0")
  highscoresWindow.lastUpdate:setText("Last Update: "..getTimeinWords(os.time() - lastUpdate) .. " ago")
  highscoresWindow.lastUpdate:setColor("#909090")

  -- buttons
  local m_seletecdWorld = selectedWorld
  if m_seletecdWorld == "All Game Worlds" then
    m_seletecdWorld = ""
  end

  local stringPvpTypes = ""
  for checkboxId, typeId in pairs(pvpTypesById) do
    local checkbox = highscoresWindow:recursiveGetChildById(checkboxId)
    if checkbox and checkbox:isChecked() then
      if stringPvpTypes ~= "" then
        stringPvpTypes = stringPvpTypes .. ","
      end
      stringPvpTypes = stringPvpTypes .. typeId
    end
  end

  -- Ids reais (nao os indices da lista) da selecao que o servidor acabou de confirmar.
  -- Sao estes que a paginacao tem de repetir, senao mudar de pagina muda tambem a
  -- categoria e a vocacao filtrada.
  local currentCategoryId = categoryIdOf(categories[selectedCategory])
  local currentVocationId = vocationIdOf(vocations[selectedVocation])

  local function selectedFilters()
    return categoryIdOf(categorybox:getCurrentOption().text), vocationIdOf(vocationbox:getCurrentOption().text)
  end

  highscoresWindow.showOwnRank.onClick = function()
    local categoryId, vocationId = selectedFilters()
    g_game.highscore(1, categoryId, vocationId, m_seletecdWorld, 1, 20, stringPvpTypes)
  end
  highscoresWindow.first.onClick = function()
    g_game.highscore(0, currentCategoryId, currentVocationId, m_seletecdWorld, 1, 20, stringPvpTypes)
  end
  highscoresWindow.prevButton.onClick = function()
    g_game.highscore(0, currentCategoryId, currentVocationId, m_seletecdWorld, math.max(1, page -1), 20, stringPvpTypes)
  end
  highscoresWindow.nextButton.onClick = function()
    g_game.highscore(0, currentCategoryId, currentVocationId, m_seletecdWorld, math.min(pages, page +1), 20, stringPvpTypes)
  end
  highscoresWindow.last.onClick = function()
    g_game.highscore(0, currentCategoryId, currentVocationId, m_seletecdWorld, pages, 20, stringPvpTypes)
  end


  highscoresWindow.filters.submit.onClick = function()
    local m_seletecdWorld = gameworldbox:getCurrentOption().text
    if m_seletecdWorld == "All Game Worlds" then
      m_seletecdWorld = ""
    end
    local categoryId, vocationId = selectedFilters()
    g_game.highscore(0, categoryId, vocationId, m_seletecdWorld, 1, 20, stringPvpTypes)
  end
end