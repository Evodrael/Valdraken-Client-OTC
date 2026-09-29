if not ImpactAnalyser then
	ImpactAnalyser = {
		launchTime = 0,
		session = 0,

		damageTotal = 0,
		dps = 0,
		maxDPS = 0,
		damageTicks = {},
		healingTicks = {},
		damageEffect = {},
		allTimeHightDps = 0,
		allTimeHightHps = 0,
		targetDPS = 1,
		gaugeDPSVisible = true,
		graphDPSVisible = true,
		gaugeHPSVisible = true,
		graphHPSVisible = true,
		damageTypeVisible = true,
		targetHPS = 1,

		healingTotal = 0,
		maxHPS = 0,

		-- private
		window = nil,
	}
	ImpactAnalyser.__index = ImpactAnalyser
end
local targetMaxMargin = 142

local imageDir = '/images/game/cyclopedia/icons/monster-icon-%s-resist'

local effectsFiles = {
	[0] = 'physical',
	[1] = 'fire',
	[2] = 'earth',
	[3] = 'energy',
	[4] = 'ice',
	[5] = 'holy',
	[6] = 'death',
	[7] = 'healing',
	[8] = 'drowning',
	[9] = 'lifedrain',
	[10] = 'manadrain',
	[11] = 'agony',
	[12] = 'agony',
}

-- Abrevia todos os valores do painel. Por extenso ("306,581,576 (49.0%)") a linha
-- estoura a largura do painel: nos Damage Types a percentagem fica cortada, e nos
-- totais o numero cobre o titulo da linha. Ate 2 casas decimais, sem zeros a
-- direita: 100K, 1M, 1.85M, 1.2B. Trunca em vez de arredondar, para 999.999 nunca
-- ser exibido como "1000K". Os tooltips das barras continuam com o valor exacto.
local abbreviationRanges = {
	{ 1000000000000000000, "Qi" },
	{ 1000000000000000, "Q" },
	{ 1000000000000, "T" },
	{ 1000000000, "B" },
	{ 1000000, "M" },
	{ 1000, "K" },
}

local function abbreviateNumber(value)
	value = tonumber(value) or 0
	local abs = math.abs(value)
	local sign = value < 0 and "-" or ""
	for _, range in ipairs(abbreviationRanges) do
		local divisor, suffix = range[1], range[2]
		if abs >= divisor then
			local scaled = math.floor(abs / (divisor / 100)) / 100
			local text = string.format("%.2f", scaled):gsub("%.?0+$", "")
			return sign .. text .. suffix
		end
	end
	return formatMoney(value, ",")
end

local DPS_WINDOW = 10000 -- janela deslizante, em ms
local DPS_MIN_ELAPSED = 1000 -- divisor minimo, em ms

local valueInSeconds = function(t)
    local d = 0
    local time = 0
    local now = g_clock.millis()
    if #t > 0 then
		local itemsToBeRemoved = 0
        for i, v in ipairs(t) do
            if now - v.tick <= DPS_WINDOW then
                if time == 0 then
                    time = v.tick
                end
                d = d + v.amount
            else
				itemsToBeRemoved = itemsToBeRemoved + 1
            end
        end

		-- items are added in order, so we can safely
		-- remove only the first items
		for i = 1, itemsToBeRemoved do
			table.remove(t, 1)
		end
    end

	if d == 0 then
		return 0
	end

	-- O divisor era simplesmente (now - tick do golpe mais antigo da janela). Com UM
	-- unico golpe recente -- tipicamente um charm, que bate sozinho e alto -- isso da'
	-- zero, e d/0 em Lua e' +inf: o DPS aparecia absurdo e ficava gravado para sempre em
	-- Max-DPS/All-Time High (por isso o saveConfigJson ja' tinha de filtrar infinitos).
	-- Um piso de 1s da' o significado esperado: "dano no ultimo segundo".
	local elapsed = math.min(DPS_WINDOW, math.max(DPS_MIN_ELAPSED, now - time))
	return math.ceil(d / (elapsed / 1000))
end

function ImpactAnalyser:create()
	ImpactAnalyser.launchTime = 0
	ImpactAnalyser.session = 0

	ImpactAnalyser.damageTotal = 0
	ImpactAnalyser.dps = 0
	ImpactAnalyser.maxDPS = 0
	ImpactAnalyser.damageTicks = {}
	ImpactAnalyser.healingTicks = {}
	ImpactAnalyser.damageEffect = {}
	ImpactAnalyser.allTimeHightDps = 0
	ImpactAnalyser.allTimeHightHps = 0
	ImpactAnalyser.targetDPS = 1
	ImpactAnalyser.gaugeDPSVisible = true
	ImpactAnalyser.graphDPSVisible = true
	ImpactAnalyser.gaugeHPSVisible = true
	ImpactAnalyser.graphHPSVisible = true
	ImpactAnalyser.damageTypeVisible = true
	ImpactAnalyser.targetHPS = 1

	ImpactAnalyser.healingTotal = 0
	ImpactAnalyser.maxHPS = 0

	-- private
	ImpactAnalyser.window = openedWindows['impactButton']
end

function ImpactAnalyser:reset(allTimeDps, allTimeHps)
	ImpactAnalyser.launchTime = g_clock.millis()
	ImpactAnalyser.session = 0

	ImpactAnalyser.damageTotal = 0
	ImpactAnalyser.dps = 0
	ImpactAnalyser.maxDPS = 0
	ImpactAnalyser.maxHPS = 0
	if allTimeDps then
		ImpactAnalyser.allTimeHightDps = 0
	end
	if allTimeHps then
		ImpactAnalyser.allTimeHightHps = 0
	end
	ImpactAnalyser.targetDPS = 1
	ImpactAnalyser.targetHPS = 1
	ImpactAnalyser.damageTicks = {}
	ImpactAnalyser.healingTicks = {}
	ImpactAnalyser.damageEffect = {}

	ImpactAnalyser.healingTotal = 0

	ImpactAnalyser.window.contentsPanel.graphDpsPanel:clear()
	ImpactAnalyser.window.contentsPanel.graphDpsPanel:addValue(1, 0)

	ImpactAnalyser.window.contentsPanel.graphHealPanel:clear()
	ImpactAnalyser.window.contentsPanel.graphHealPanel:addValue(1, 0)

	ImpactAnalyser:updateWindow()
end

-- Recalcula DPS/HPS da janela deslizante, poda os ticks vencidos e actualiza os
-- recordes. Corre SEMPRE, mesmo com a janela fechada: Max-DPS e All-Time High nao
-- podem depender de o jogador ter o painel aberto, e a poda e' o que impede as
-- tabelas de ticks de crescerem sem limite durante uma cacada com o painel escondido.
function ImpactAnalyser:refreshRates()
	local curDPS = valueInSeconds(ImpactAnalyser.damageTicks) or 0
	local curHPS = valueInSeconds(ImpactAnalyser.healingTicks) or 0

	if curDPS > ImpactAnalyser.maxDPS then
		ImpactAnalyser.maxDPS = curDPS
	end
	-- "All-Time High" e' a mesma grandeza do Max-DPS, so' que persistida entre sessoes.
	-- Antes era alimentado em addDealDamage com o valor de UM golpe: um charm que tira
	-- 5% do HP de um boss enchia o campo com um numero que nao era DPS nenhum e nunca
	-- mais descia.
	if curDPS > ImpactAnalyser.allTimeHightDps then
		ImpactAnalyser.allTimeHightDps = curDPS
	end

	if curHPS > ImpactAnalyser.maxHPS then
		ImpactAnalyser.maxHPS = curHPS
	end
	if curHPS > ImpactAnalyser.allTimeHightHps then
		ImpactAnalyser.allTimeHightHps = curHPS
	end

	return curDPS, curHPS
end

function ImpactAnalyser:updateWindow(ignoreVisible)
	local curDPS, curHealPS = ImpactAnalyser:refreshRates()

	if not ImpactAnalyser.window:isVisible() and not ignoreVisible then
		return
	end
	ImpactAnalyser:checkAnchos()
	local contentsPanel = ImpactAnalyser.window.contentsPanel

	contentsPanel.dmg:setText(abbreviateNumber(ImpactAnalyser.damageTotal))
	contentsPanel.allTimeHigh:setText(abbreviateNumber(ImpactAnalyser.allTimeHightDps))

	contentsPanel.maxDps:setText(abbreviateNumber(ImpactAnalyser.maxDPS))
	contentsPanel.dps:setText(abbreviateNumber(curDPS))

	contentsPanel.targetDps:setText(abbreviateNumber(ImpactAnalyser.targetDPS))
	-- movido pro check de 15s
	contentsPanel.graphDpsPanel:addValue(1, curDPS)

	if ImpactAnalyser.targetDPS == 1 and curDPS == 0 then
		ImpactAnalyser.window.contentsPanel.dpsBG.dpsArrow:setMarginLeft(targetMaxMargin / 2)
	else
		local target = math.max(1, ImpactAnalyser.targetDPS)
		local percent = (curDPS * 71) / target
		ImpactAnalyser.window.contentsPanel.dpsBG.dpsArrow:setMarginLeft(math.min(targetMaxMargin, math.ceil(percent)))
	end

	ImpactAnalyser.window.contentsPanel.dpsBG:setTooltip(string.format("Current: %d\nTarget: %d", curDPS, ImpactAnalyser.targetDPS))

	----------------------- DAMAGE TYPE -----------------------------
	for _, child in pairs(contentsPanel.dmgTypes:getChildren()) do
		child.toBeRemoved = true
	end

	if table.empty(ImpactAnalyser.damageEffect) then
		if contentsPanel.dmgTypes:getChildCount() > 0 then
			contentsPanel.dmgTypes:destroyChildren()
		end

		g_ui.createWidget('NoDataLabel', contentsPanel.dmgTypes)
	else
		for effect, damage in pairs(ImpactAnalyser.damageEffect) do
			local widget = contentsPanel.dmgTypes:getChildById("DamageEffect_" .. effect)
			if not widget then
				widget = g_ui.createWidget('DamagePanel', contentsPanel.dmgTypes)
				widget:setId("DamageEffect_" .. effect)
				widget.icon:setImageSource(string.format(imageDir, effectsFiles[effect]))
				widget.icon:setTooltip(getCombatName(effect))
			end

			local percent = (damage * 100) / ImpactAnalyser.damageTotal
			widget.desc:setText(abbreviateNumber(damage) .. " (" .. string.format("%.1f", percent) .. "%)")
			widget.toBeRemoved = false
		end
	end

	for _, child in pairs(contentsPanel.dmgTypes:getChildren()) do
		if child.toBeRemoved then
			child:destroy()
		end
	end

	---------------------------- Healing -------------------------------

	contentsPanel.hpsTotal:setText(abbreviateNumber(ImpactAnalyser.healingTotal))

	contentsPanel.allTimeHighHealing:setText(abbreviateNumber(ImpactAnalyser.allTimeHightHps))

	contentsPanel.maxHps:setText(abbreviateNumber(ImpactAnalyser.maxHPS))
	contentsPanel.hps:setText(abbreviateNumber(curHealPS))

	contentsPanel.targetHps:setText(abbreviateNumber(ImpactAnalyser.targetHPS))
	-- movido pro check de 15s
	contentsPanel.graphHealPanel:addValue(1, curHealPS)

	if ImpactAnalyser.targetHPS == 1 and curHealPS == 0 then
		ImpactAnalyser.window.contentsPanel.hpsBG.hpsArrow:setMarginLeft(targetMaxMargin / 2)
	else
		local target = math.max(1, ImpactAnalyser.targetHPS)
		local percent = (curHealPS * 71) / target
		ImpactAnalyser.window.contentsPanel.hpsBG.hpsArrow:setMarginLeft(math.min(targetMaxMargin, math.ceil(percent)))
	end

	ImpactAnalyser.window.contentsPanel.hpsBG:setTooltip(string.format("Current: %d\nTarget: %d", curHealPS, ImpactAnalyser.targetHPS))
end

function ImpactAnalyser:updateGraphics()
	-- desativado
	if true then
		return
	end
	local curHPS = valueInSeconds(ImpactAnalyser.damageTicks)
	if not curHPS then curHPS = 0 end
	ImpactAnalyser.maxDPS = ImpactAnalyser.maxDPS > curHPS and ImpactAnalyser.maxDPS or curHPS
	ImpactAnalyser.window.contentsPanel.graphDpsPanel:addValue(1, curHPS)


	local curHPS = valueInSeconds(ImpactAnalyser.healingTicks)
	if not curHPS then curHPS = 0 end
	ImpactAnalyser.maxHPS = ImpactAnalyser.maxHPS > curHPS and ImpactAnalyser.maxHPS or curHPS
	ImpactAnalyser.window.contentsPanel.graphHealPanel:addValue(1, curHPS)
end

function ImpactAnalyser:addDealDamage(amount, effect)
	ImpactAnalyser.damageTotal = ImpactAnalyser.damageTotal + amount
	ImpactAnalyser.damageTicks[#ImpactAnalyser.damageTicks + 1] = {amount = amount, tick = g_clock.millis()}
	if not ImpactAnalyser.damageEffect[effect] then
		ImpactAnalyser.damageEffect[effect] = 0
	end

	ImpactAnalyser.damageEffect[effect] = ImpactAnalyser.damageEffect[effect] + amount
end

function ImpactAnalyser:addHealing(amount)
	ImpactAnalyser.healingTotal = ImpactAnalyser.healingTotal + amount
	ImpactAnalyser.healingTicks[#ImpactAnalyser.healingTicks + 1] = {amount = amount, tick = g_clock.millis()}
end


function onImpactExtra(mousePosition)
  if cancelNextRelease then
    cancelNextRelease = false
    return false
  end

	local menu = g_ui.createWidget('PopupMenu')
	menu:setGameMenu(true)
	menu:addOption(tr('Reset Data'), function() ImpactAnalyser:reset(false) return end)
	menu:addOption(tr('Reset All-Time High'), function() ImpactAnalyser:setAllTimeHightDps(0);ImpactAnalyser:setAllTimeHightHps(0) end)
	menu:addOption(tr('Show Session Values'), function() end)
	menu:addSeparator()
	menu:addOption(tr('Set DPS target'), function() ImpactAnalyser:openTargetConfig(true) end)
	menu:addCheckBoxOption(tr('DPS gauge'), function()
		ImpactAnalyser:setDPSGauge(not ImpactAnalyser.window.contentsPanel.targetDpsLabel:isVisible(), true)
	end, "", ImpactAnalyser.window.contentsPanel.targetDpsLabel:isVisible())
	menu:addCheckBoxOption(tr('DPS graph'), function()
		ImpactAnalyser:setDPSGraph(not ImpactAnalyser.window.contentsPanel.dpsGraphBG:isVisible(), true)
	end, "", ImpactAnalyser.window.contentsPanel.dpsGraphBG:isVisible())
	menu:addSeparator()
	menu:addCheckBoxOption(tr('Damage Types'), function()
		ImpactAnalyser:setDamageType(not ImpactAnalyser.window.contentsPanel.damageTypeLabel:isVisible(), true)
	end, "", ImpactAnalyser.window.contentsPanel.damageTypeLabel:isVisible())
	menu:addSeparator()
	menu:addOption(tr('Set HPS target'), function() ImpactAnalyser:openTargetConfig(false) end)
	menu:addCheckBoxOption(tr('HPS gauge'), function()
		ImpactAnalyser:setHPSGauge(not ImpactAnalyser.window.contentsPanel.targetHpsLabel:isVisible(), true)
	end, "", ImpactAnalyser.window.contentsPanel.targetHpsLabel:isVisible())
	menu:addCheckBoxOption(tr('HPS graph'), function()
		ImpactAnalyser:setHPSGraph(not ImpactAnalyser.window.contentsPanel.hpsGraphBG:isVisible(), true)
	end, "", ImpactAnalyser.window.contentsPanel.hpsGraphBG:isVisible())
	menu:display(mousePosition)
  return true
end

function ImpactAnalyser:openTargetConfig(isDps)
	local window = configPopupWindow["impactButton"]
	window:show()
	window:setText('Set '.. (isDps and 'DPS' or 'HPS') ..' Target')
	window.contentPanel.dps.target:setText(ImpactAnalyser.targetDPS)
	window.contentPanel.hps.target:setText(ImpactAnalyser.targetHPS)
	window.contentPanel.dps:setVisible(isDps)
	window.contentPanel.hps:setVisible(not isDps)

	window.onEnter = function()
		if isDps then
			local value = window.contentPanel.dps.target:getText()
			ImpactAnalyser.targetDPS = tonumber(value)
		else
			local value = window.contentPanel.hps.target:getText()
			ImpactAnalyser.targetHPS = tonumber(value)
		end
		window:hide()
	end

	window.contentPanel.ok.onClick = function()
		if isDps then
			local value = window.contentPanel.dps.target:getText()
			ImpactAnalyser.targetDPS = tonumber(value)
		else
			local value = window.contentPanel.hps.target:getText()
			ImpactAnalyser.targetHPS = tonumber(value)
		end
		window:hide()
	end
	window.contentPanel.cancel.onClick = function()
		window:hide()
	end
end

function ImpactAnalyser:setDPSGauge(value, check)
	ImpactAnalyser.window.contentsPanel.targetDpsLabel:setVisible(value)
	ImpactAnalyser.window.contentsPanel.targetDps:setVisible(value)
	ImpactAnalyser.window.contentsPanel.dpsBG:setVisible(value)
	ImpactAnalyser.window.contentsPanel.dpsLabel:setVisible(value)
	ImpactAnalyser.window.contentsPanel.dps:setVisible(value)
	ImpactAnalyser.window.contentsPanel.separatorDps:setVisible(value)

	ImpactAnalyser.gaugeDPSVisible = value

	if check then
		ImpactAnalyser:checkAnchos()
	end
end

function ImpactAnalyser:setDPSGraph(value, check)
	ImpactAnalyser.window.contentsPanel.dpsGraphBG:setVisible(value)
	ImpactAnalyser.window.contentsPanel.graphDpsPanel:setVisible(value)
	ImpactAnalyser.window.contentsPanel.graphHorizontal:setVisible(value)
	ImpactAnalyser.window.contentsPanel.separatorGraphHorizontalDps:setVisible(value)


	ImpactAnalyser.graphDPSVisible = value

	if check then
		ImpactAnalyser:checkAnchos()
	end
end

function ImpactAnalyser:setDamageType(value, check)
	ImpactAnalyser.window.contentsPanel.damageTypeLabel:setVisible(value)
	ImpactAnalyser.window.contentsPanel.dmgTypes:setVisible(value)
	ImpactAnalyser.window.contentsPanel.separatorDmgType:setVisible(value)


	ImpactAnalyser.damageTypeVisible = value

	if check then
		ImpactAnalyser:checkAnchos()
	end
end

function ImpactAnalyser:setHPSGauge(value, check)
	ImpactAnalyser.window.contentsPanel.targetHpsLabel:setVisible(value)
	ImpactAnalyser.window.contentsPanel.targetHps:setVisible(value)
	ImpactAnalyser.window.contentsPanel.hpsBG:setVisible(value)
	ImpactAnalyser.window.contentsPanel.hpsLabelGauge:setVisible(value)
	ImpactAnalyser.window.contentsPanel.hps:setVisible(value)
	ImpactAnalyser.window.contentsPanel.separatorHps:setVisible(value)

	ImpactAnalyser.gaugeHPSVisible = value

	if check then
		ImpactAnalyser:checkAnchos()
	end
end

function ImpactAnalyser:setHPSGraph(value, check)
	ImpactAnalyser.window.contentsPanel.hpsGraphBG:setVisible(value)
	ImpactAnalyser.window.contentsPanel.graphHealPanel:setVisible(value)
	ImpactAnalyser.window.contentsPanel.graphHPSHorizontal:setVisible(value)

	ImpactAnalyser.graphHPSVisible = value

	if check then
		ImpactAnalyser:checkAnchos()
	end
end

function ImpactAnalyser:checkAnchos()
	-- TODO: this is most likely why sometimes when logging in this bugs anchors
	-- should be done in the otui file, and in case they depend on other widgets
	-- update them when the other widgets visibility are updated - also, this is
	-- also weird once the anchors don't seem to be breaking anytime...
	if ImpactAnalyser.window.contentsPanel.targetDpsLabel:isVisible() then
		ImpactAnalyser.window.contentsPanel.dpsGraphBG:addAnchor(AnchorTop, 'separatorDps', AnchorBottom)
	else
		ImpactAnalyser.window.contentsPanel.dpsGraphBG:addAnchor(AnchorTop, 'separatorAllTimeHigh', AnchorBottom)
	end

	-- dps graph
	if ImpactAnalyser.window.contentsPanel.dpsGraphBG:isVisible() then
		ImpactAnalyser.window.contentsPanel.damageTypeLabel:addAnchor(AnchorTop, 'separatorGraphHorizontalDps', AnchorBottom)
	elseif ImpactAnalyser.window.contentsPanel.targetDpsLabel:isVisible() then
		ImpactAnalyser.window.contentsPanel.damageTypeLabel:addAnchor(AnchorTop, 'separatorDps', AnchorBottom)
	else
		ImpactAnalyser.window.contentsPanel.damageTypeLabel:addAnchor(AnchorTop, 'separatorAllTimeHigh', AnchorBottom)
	end

	-- damage type
	if ImpactAnalyser.window.contentsPanel.damageTypeLabel:isVisible() then
		ImpactAnalyser.window.contentsPanel.healingLabel:addAnchor(AnchorTop, 'separatorDmgType', AnchorBottom)
	elseif ImpactAnalyser.window.contentsPanel.dpsGraphBG:isVisible() then
		ImpactAnalyser.window.contentsPanel.healingLabel:addAnchor(AnchorTop, 'separatorGraphHorizontalDps', AnchorBottom)
	elseif ImpactAnalyser.window.contentsPanel.targetDpsLabel:isVisible() then
		ImpactAnalyser.window.contentsPanel.healingLabel:addAnchor(AnchorTop, 'separatorDps', AnchorBottom)
	else
		ImpactAnalyser.window.contentsPanel.healingLabel:addAnchor(AnchorTop, 'separatorAllTimeHigh', AnchorBottom)
	end

	-- heal gauge
	if ImpactAnalyser.window.contentsPanel.targetHpsLabel:isVisible() then
		ImpactAnalyser.window.contentsPanel.hpsGraphBG:addAnchor(AnchorTop, 'separatorHps', AnchorBottom)
	else
		ImpactAnalyser.window.contentsPanel.hpsGraphBG:addAnchor(AnchorTop, 'separatorAllTimeHighHealing', AnchorBottom)
	end
end

-- getters
function ImpactAnalyser:getAllTimeHightDps() return ImpactAnalyser.allTimeHightDps end
function ImpactAnalyser:gaugeDPSIsVisible() return ImpactAnalyser.gaugeDPSVisible end
function ImpactAnalyser:graphDPSIsVisible() return ImpactAnalyser.graphDPSVisible end
function ImpactAnalyser:gaugeHPSIsVisible() return ImpactAnalyser.gaugeHPSVisible end
function ImpactAnalyser:graphHPSIsVisible() return ImpactAnalyser.graphHPSVisible end
function ImpactAnalyser:damageTypeIsVisible() return ImpactAnalyser.damageTypeVisible end

-- setters
function ImpactAnalyser:setAllTimeHightDps(value) ImpactAnalyser.allTimeHightDps = value end
function ImpactAnalyser:setAllTimeHightHps(value) ImpactAnalyser.allTimeHightHps = value end

function ImpactAnalyser:loadConfigJson()
	local config = {
		desiredDamageTypesVisible = true,
		desiredDpsGaugeVisible = true,
		desiredDpsGraphVisible = true,
		desiredHpsGaugeVisible = true,
		desiredHpsGraphVisible = true,
		dpsGaugeTargetValue = 1,
		hpsGaugeTargetValue = 1,
		maxDamageImpact = 0,
		maxHealingImpact = 0,
		showSessionValues = true,
	}

	local player = g_game.getLocalPlayer()
	local file = "/characterdata/" .. player:getId() .. "/impactanalyser.json"
	if g_resources.fileExists(file) then
		local status, result = pcall(function()
			return json.decode(g_resources.readFileContents(file))
		end)

		if not status then
			return g_logger.error("Error while reading characterdata file. Details: " .. result)
		end

		config = result
	end

	ImpactAnalyser:setDPSGauge(config.desiredDpsGaugeVisible, false)
	ImpactAnalyser:setDPSGraph(config.desiredDpsGraphVisible, false)
	ImpactAnalyser:setDamageType(config.desiredDamageTypesVisible, false)
	ImpactAnalyser:setHPSGauge(config.desiredHpsGaugeVisible, false)
	ImpactAnalyser:setHPSGraph(config.desiredHpsGraphVisible, false)
	-- Ficheiros gravados antes da correcao do DPS podem trazer infinito ou o valor de um
	-- golpe isolado; sanear aqui evita comparar contra nil/inf em todo o updateWindow.
	local function finiteOr(value, fallback)
		if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
			return fallback
		end
		return value
	end

	ImpactAnalyser.allTimeHightDps = finiteOr(config.maxDamageImpact, 0)
	ImpactAnalyser.allTimeHightHps = finiteOr(config.maxHealingImpact, 0)
	ImpactAnalyser.targetDPS = finiteOr(config.dpsGaugeTargetValue, 1)
	ImpactAnalyser.targetHPS = finiteOr(config.hpsGaugeTargetValue, 1)

	ImpactAnalyser:checkAnchos()
end

function ImpactAnalyser:saveConfigJson()
	local function checkFinite(value)
		if value == math.huge or value == -math.huge or type(value) ~= "number" then
			return 0
		end
		return value
	end

	local config = {
		desiredDamageTypesVisible = ImpactAnalyser:damageTypeIsVisible(),
		desiredDpsGaugeVisible = ImpactAnalyser:gaugeDPSIsVisible(),
		desiredDpsGraphVisible = ImpactAnalyser:graphDPSIsVisible(),
		desiredHpsGaugeVisible = ImpactAnalyser:gaugeHPSIsVisible(),
		desiredHpsGraphVisible = ImpactAnalyser:graphHPSIsVisible(),
		dpsGaugeTargetValue = checkFinite(ImpactAnalyser.targetDPS),
		hpsGaugeTargetValue = checkFinite(ImpactAnalyser.targetHPS),
		maxDamageImpact = checkFinite(ImpactAnalyser.allTimeHightDps),
		maxHealingImpact = checkFinite(ImpactAnalyser.allTimeHightHps),
		showSessionValues = true,
	}

	if not LoadedPlayer:isLoaded() then return end

	local file = "/characterdata/" .. LoadedPlayer:getId() .. "/impactanalyser.json"
	local status, result = pcall(function() return json.encode(config, 2) end)
	if not status then
		return g_logger.error("Error while saving profile ImpactAnalyzer data. Data won't be saved. Details: " .. result)
	end

	if result:len() > 100 * 1024 * 1024 then
		return g_logger.error("Something went wrong, file is above 100MB, won't be saved")
	end
	
	g_resources.writeFileContents(file, result)
end
