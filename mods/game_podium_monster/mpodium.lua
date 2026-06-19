podiumWindow = nil

local monsterList = nil
local previewGround = nil
local searchField = nil
local currentCreature = nil

local showoffOutfit = {}
local isBossPoduim = nil
local position = nil
local showCreature = nil
local podiumVisible = nil
local podiumDirection = nil
local thingID = nil

local podiumItem = nil
local currentOutfit = nil
local lastChecked = nil
local originalShowCreature = nil
local currentRaceID = 0

local bossList = {}
local creatureList = {}

function init()
  podiumWindow = g_ui.displayUI('mpodium.otui')
  podiumWindow:hide()

  previewGround = podiumWindow:recursiveGetChildById('PreviewGround')
  monsterList = podiumWindow:recursiveGetChildById('monsterList')
  searchField = podiumWindow:recursiveGetChildById('searchfiltercreatures')

  connect(g_game, {
	onParseMonsterPodium = onParseMonsterPodium
  })
end

function terminate()
  podiumWindow:hide()
  selectedOption = nil
  searchFilterCharmText = ''

  disconnect(g_game, {
  	onParseMonsterPodium = onParseMonsterPodium
  })
end

function hide()
	if not originalShowCreature and podiumItem then
		podiumItem:setOutfitVisible(false)
	end

	if podiumItem then
		podiumItem:setOutfit({})
	end
	searchField:clearText()
	currentOutfit = nil
	lastChecked = nil
	currentRaceID = 0
	if podiumWindow and podiumWindow:isVisible() then
		podiumWindow:hide()
	end
end

-- Valida se um lookType existe no appearances do cliente ANTES de chamar setOutfit
-- num UICreature. Sem esta guarda, um raceId do bestiario cujo lookType seja
-- 0/invalido ou ausente do staticdata leva o render C++ (Creature::internalDraw via
-- UICreature::drawSelf) a desenhar um ThingType placeholder -> access violation em
-- otclient_gl.exe. Pula a entrada graciosamente. (ThingCategoryCreature e global Lua.)
local function isValidLookType(lookType)
	if not lookType or lookType == 0 then
		return false
	end
	return g_things.isValidDatId(lookType, ThingCategoryCreature)
end

function requestMonsterData(thing)
	thingID = thing:getId()
	g_game.requestPodiumData(thing);
	monsterList:destroyChildren()
end

function onParseMonsterPodium(currentOutfit, currentID, podiumBoss, bosses, monsters, pos, thingID, showPodium, isShowingCreature, direction)
	if not podiumWindow:isVisible() then
		podiumWindow:show()
		podiumWindow:focus()
	end

	currentRaceID = currentID
	showoffOutfit = currentOutfit
    isBossPoduim = podiumBoss
	position = pos
	showCreature = isShowingCreature
	originalShowCreature = isShowingCreature
	podiumVisible = showPodium
	podiumDirection = direction

	bossList = bosses
	creatureList = monsters

	previewGround.item:setItemId(thingID)
	podiumItem = previewGround.item:getItem()

	local showFloor = podiumWindow:recursiveGetChildById('ShowFloor')
	showFloor.floor:setChecked(true)

	local creatureShow = podiumWindow:recursiveGetChildById('creatureShow')
	creatureShow:setChecked(showCreature)

	local podiumShow = podiumWindow:recursiveGetChildById('podium')
	podiumShow:setChecked(podiumVisible)

	-- Limpa a lista ANTES de repopular: onParseMonsterPodium pode ser chamada de novo ao reabrir o
	-- Customise Podium e antes ela so APPENDava -> a creature selecionada duplicava na lista.
	monsterList:destroyChildren()
	showMonsterPodium()
end

function showMonsterPodium(filter)
	podiumItem = previewGround.item:getItem()
	if not podiumItem then
		return
	end

	if showoffOutfit.type ~= 128 then
		currentOutfit = showoffOutfit
	end

	if showCreature and currentOutfit then
		podiumItem:setOutfitVisible(true)
		podiumItem:setOutfit(currentOutfit)
	else
		podiumItem:setOutfitVisible(false)
	end

	podiumItem:setPodiumVisible(podiumVisible)
	podiumItem:setPodiumDirection(podiumDirection)

	local creatures = g_things.getMonsterList()
	if isBossPoduim then
		for k, v in pairs(bossList) do
			local name = string.capitalize(v)
			if not creatures[k] then
				goto continue
			end
			-- pula bosses sem lookType valido (evita crash no render do UICreature)
			if not isValidLookType(creatures[k][2]) then
				goto continue
			end
			if filter and not matchText(filter, name:lower()) then
				goto continue
			end

			local widget = g_ui.createWidget('PodiumCreatureBox', monsterList)
			widget.checkBox.name:setText(name)
			if widget.checkBox.name:isTextWraped() then
				widget.checkBox.name:setMarginTop(32)
			end

			widget.checkBox.creature:setRaceID(k)
			widget.checkBox.creature:setOutfit({type = creatures[k][2], auxType = creatures[k][3], head = creatures[k][4], body = creatures[k][5], legs = creatures[k][6], feet = creatures[k][7], addons = creatures[k][8]})

			:: continue ::
		end
	else
		for _, v in pairs(creatureList) do
			local currentRace = creatures[v]
			-- OTZudo: se a race nao existir no g_things (faltando no staticdata do
			-- cliente) nao deixa estourar a janela inteira; apenas pula a entrada.
			if not currentRace then
				goto continue
			end
			-- pula racas sem lookType valido no appearances (evita access violation
			-- no render do UICreature quando o ThingType nao existe/e placeholder)
			if not isValidLookType(currentRace[2]) then
				goto continue
			end
			if filter and not matchText(filter, currentRace[1]:lower()) then
				goto continue
			end

			local widget = g_ui.createWidget('PodiumCreatureBox', monsterList)
			widget.checkBox.name:setText(currentRace[1])
			if widget.checkBox.name:isTextWraped() then
				widget.checkBox.name:setMarginTop(32)
			end

			widget.checkBox.creature:setRaceID(v)
			widget.checkBox.creature:setOutfit({type = currentRace[2], auxType = currentRace[3], head = currentRace[4], body = currentRace[5], legs = currentRace[6], feet = currentRace[7], addons = currentRace[8]})

			:: continue ::
		end
	end
end

--- buttons
function showFloor(checked)
	if checked then
		previewGround:setImageSource('/images/game/outfit_ground')
	else
		previewGround:setImageSource('images/ui/panel-background')
	end
end

function showCreatureOutfit(checked)
	showCreature = checked
	if not podiumItem then
		return
	end

	if checked then
		podiumItem:setOutfitVisible(true)
		podiumItem:setOutfit(podiumItem:getOutfit())
	else
		podiumItem:setOutfitVisible(false)
	end
end

function showPodiumItem(checked)
	if podiumItem then
		podiumItem:setPodiumVisible(checked)
	end
end

function onCheckBox(widget, parentClick)
	local current = widget
	if parentClick then
		current = widget:recursiveGetChildById('creature')
		if lastChecked then
			lastChecked:setChecked(false)
		end
		lastChecked = widget
		widget:setChecked(true)
	else
		if lastChecked then
			lastChecked:setChecked(false)
		end
		lastChecked = widget:getParent()
		lastChecked:setChecked(true)
	end

	currentOutfit = current:getOutfit()
	currentRaceID = current:getRaceID()

	-- Selecionar uma criatura SEMPRE a exibe no preview. Antes dependia do callback do checkbox
	-- (showCreatureOutfit) atualizar 'showCreature' a tempo; se o check ja estivesse no estado
	-- alvo, setChecked nao disparava o callback e a creature NAO aparecia. Agora setamos direto.
	showCreature = true
	if podiumItem then
		podiumItem:setOutfit(current:getOutfit())
		podiumItem:setOutfitVisible(true)
	end

	-- Mantem o checkbox "Show Creature" em sincronia (marca sem depender do retorno do callback).
	local creatureShow = podiumWindow:recursiveGetChildById('creatureShow')
	if creatureShow and not creatureShow:isChecked() then
		creatureShow:setChecked(true)
	end
end

function onChangeDirection(isRight)
	if not podiumItem then
		return
	end
	local currentDirection = podiumItem:getPodiumDir()

	if isRight then
		if currentDirection == 0 then
			podiumItem:setPodiumDirection(3)
		else
			podiumItem:setPodiumDirection(currentDirection - 1)
		end
	else
		if currentDirection >= 3 then
			podiumItem:setPodiumDirection(0)
		else
			podiumItem:setPodiumDirection(currentDirection + 1)
		end
	end
end

function onSelectCreature()
	if not podiumItem then
		return
	end

	if not currentRaceID or currentRaceID == 0 then
		podiumItem:setOutfitVisible(false)
	end

	if not showCreature then
		currentRaceID = 0
	end

	g_game.sendMonsterPodiumOutfit(currentRaceID, position, thingID, podiumItem:getPodiumDir(), podiumItem:isPodiumVisible(), showCreature)
	hide()
end

-- Search function
function onSearchChange(self)
	monsterList:destroyChildren()
	if #self:getText() == 0 then
		showMonsterPodium()
		return
	end
	showMonsterPodium(self:getText())
end
