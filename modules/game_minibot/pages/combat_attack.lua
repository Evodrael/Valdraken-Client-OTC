combat_attackModule = {}

local combatAttackWindow = nil

-- Os quatro modos de alvo, na ordem em que aparecem na interface. O id do widget
-- e igual ao valor salvo, entao a interface e o motor nunca saem de sincronia.
local ATTACK_MODES = { 'closest', 'lowest', 'highest', 'ranged' }
local DEFAULT_MODE = 'closest'

local function isValidMode(mode)
    for _, name in ipairs(ATTACK_MODES) do
        if name == mode then
            return true
        end
    end
    return false
end

-- Antes cada modo era um booleano separado ('autoAttack_health', '..._closest',
-- '..._highhealth', '..._smartArrow'), o que permitia estados impossiveis (dois
-- modos ligados, ou nenhum) e obrigava o motor a adivinhar por ordem de if. Agora
-- e um unico campo de texto; presets antigos sao convertidos na primeira leitura.
local function readMode(mSettings)
    local mode = mSettings['autoAttack_mode']
    if isValidMode(mode) then
        return mode
    end

    if mSettings['autoAttack_smartArrow'] then
        return 'ranged'
    elseif mSettings['autoAttack_health'] then
        return 'lowest'
    elseif mSettings['autoAttack_highhealth'] then
        return 'highest'
    end

    return DEFAULT_MODE
end

-- Limites dos dois campos numericos. maxDistance 10 cobre a tela inteira (a aware
-- range do client e menor), entao 10 equivale a "sem limite"; minAoeTargets 1
-- desliga a checagem de aglomerado. Os defaults sao os valores neutros, para um
-- preset antigo (sem essas chaves) continuar se comportando como antes.
local TUNING = {
    maxDistance   = { min = 1, max = 10, default = 10 },
    minAoeTargets = { min = 1, max = 9,  default = 1 },
}

local function readTuning(mSettings, key)
    local spec = TUNING[key]
    local value = tonumber(mSettings['autoAttack_' .. key])
    if value == nil then
        return spec.default
    end
    return math.max(spec.min, math.min(spec.max, math.floor(value)))
end

function combat_attackModule.init(widget)
    combatAttackWindow = widget

    combat_attackModule.loadSettings()

    combatAttackWindow.settings.ammoRefill.frameBackground.onLeftClick = function()
        combatAttackWindow.dropDownMenu:setMarginLeft(48)
        -- Acompanha a altura do attackPanel: encolheu 24px ao sair a opcao de
        -- corpo a corpo, entao o bloco de municao (e este menu) subiu o mesmo tanto.
        combatAttackWindow.dropDownMenu:setMarginTop(146)
        combat_attackModule.openItemCatcher(combatAttackWindow.settings.ammoRefill)
    end
end

function combat_attackModule.terminate()
    combat_attackModule.closeCatcher()

    combatAttackWindow = nil
end

function combat_attackModule.reloadLanguage(language)
    local panel = combatAttackWindow.settings.attackPanel

    if language == 'ptbr' then
        combatAttackWindow.settings.title:setText('Opcoes de Ataque')
        panel.autoAttackLabel:setText('Auto Attack')
        panel.autoAttackHelp:setTooltip('Liga e desliga a selecao automatica de alvo. Com o botao em ON, o sistema escolhe o alvo pela opcao marcada abaixo e troca sozinho sempre que aparecer um alvo melhor.')
        panel.closest:setText('Criatura mais proxima')
        panel.attackClosestHelp:setTooltip('Ataca a criatura mais perto do personagem. Diagonal conta como 1 SQM, igual ao alcance do jogo.')
        panel.lowest:setText('Criatura com HP mais baixa')
        panel.attackLowestHelp:setTooltip('Ataca a criatura da tela com a menor porcentagem de vida. Criatura atras de parede ou invisivel e ignorada.')
        panel.highest:setText('Criatura com HP mais alta')
        panel.attackHighestHelp:setTooltip('Ataca a criatura da tela com a maior porcentagem de vida. Criatura atras de parede ou invisivel e ignorada.')
        panel.ranged:setText('Ataque a distancia')
        panel.attackRangedHelp:setTooltip('Para paladinos: escolhe o alvo em que a flecha de area (burst, diamond ou grenade arrow) acerta o maior numero de criaturas de uma vez. Em caso de empate, prioriza a vida mais baixa. Sem flecha de area equipada, funciona como "criatura mais proxima".')
        panel.preferAttacker:setText('Priorizar quem esta me atacando')
        panel.preferAttackerHelp:setTooltip('Vale por cima do modo escolhido, sem substituir ele. O protocolo do Tibia nao informa ao client quem tem voce como alvo, entao isto e uma estimativa: criaturas adjacentes, mais quem disparou um missil que caiu em voce nos ultimos 3 segundos.')
        panel.maxDistanceLabel:setText('Distancia maxima (SQM):')
        panel.maxDistanceHelp:setTooltip('Criatura mais longe que isso nunca e escolhida como alvo, para o personagem nao atravessar a tela atras de algo. De 1 a 10; 10 cobre a tela inteira (sem limite na pratica).')
        panel.minAoeLabel:setText('Min. de alvos para area:')
        panel.minAoeHelp:setTooltip('Usado apenas pelo "Ataque a distancia": se o melhor ponto de mira acertaria menos criaturas que isso, o sistema volta para o alvo com a vida mais baixa em vez de mirar um aglomerado distante. 1 desliga a checagem.')

        combatAttackWindow.settings.ammoRefill.check:setText('Recarga de municao')
        combatAttackWindow.settings.ammoRefill.tooltipLabel:setTooltip('Se uma municao selecionada for encontrada em seu inventario, o sistema tentara move-la periodicamente de forma automatica.')

    elseif language == 'enus' then
        combatAttackWindow.settings.title:setText('Attack options')
        panel.autoAttackLabel:setText('Auto Attack')
        panel.autoAttackHelp:setTooltip('Turns automatic target selection on and off. While the button is ON, the system picks the target using the option checked below and switches on its own whenever a better target shows up.')
        panel.closest:setText('Closest creature')
        panel.attackClosestHelp:setTooltip('Attacks the creature nearest to your character. Diagonals count as 1 SQM, matching the game reach.')
        panel.lowest:setText('Lowest HP creature')
        panel.attackLowestHelp:setTooltip('Attacks the creature on screen with the lowest health percentage. Creatures behind walls or invisible are ignored.')
        panel.highest:setText('Highest HP creature')
        panel.attackHighestHelp:setTooltip('Attacks the creature on screen with the highest health percentage. Creatures behind walls or invisible are ignored.')
        panel.ranged:setText('Ranged attack')
        panel.attackRangedHelp:setTooltip('For paladins: picks the target where the area arrow (burst, diamond or grenade arrow) hits the most creatures at once. On a tie, prefers the lowest health. Without area ammo equipped it behaves as "closest creature".')
        panel.preferAttacker:setText('Prioritize whoever is attacking me')
        panel.preferAttackerHelp:setTooltip('Applies on top of the selected mode, it does not replace it. The Tibia protocol does not tell the client who is targeting you, so this is a heuristic: adjacent creatures, plus whoever fired a missile that landed on you in the last 3 seconds.')
        panel.maxDistanceLabel:setText('Max distance (SQM):')
        panel.maxDistanceHelp:setTooltip('Creatures farther than this are never targeted, so the character does not walk across the screen chasing something. 1 to 10; 10 covers the whole screen (no practical limit).')
        panel.minAoeLabel:setText('Min. targets for area:')
        panel.minAoeHelp:setTooltip('Only used by "Ranged attack": if the best aim point would hit fewer creatures than this, the system falls back to the lowest HP target instead of aiming at a distant cluster. 1 disables the check.')

        combatAttackWindow.settings.ammoRefill.check:setText('Ammo refill')
        combatAttackWindow.settings.ammoRefill.tooltipLabel:setTooltip('If a selected ammo is found on your inventory, the system automatically try to move periodically.')

    end
end

function combat_attackModule.reloadInternalModule()
    local settings = modules.game_minibot.getPressetSettings()
    local mSettings = settings['combat_attack'] or {}
    local sSettings = settings['shortcuts'] or {}

    local player = g_game.getLocalPlayer()
    local enabled = player ~= nil and sSettings['autoAttack_enabled'] and true or false

    -- A selecao de alvo agora vive no Lua (modules.game_minibot.setAutoAttackMode).
    -- O caminho antigo no motor fica desligado nas duas pontas: processAutoAttack()
    -- exige m_autoAttack > 0 E o modulo 9 ligado, e deixar qualquer um dos dois
    -- ativo faria o C++ competir com o tick do Lua pelo mesmo alvo.
    g_minibot.setAutoAttack(0)
    g_minibot.setModuleToggle(9, false)

    modules.game_minibot.setAutoAttackMode(enabled and readMode(mSettings) or nil, {
        maxDistance = readTuning(mSettings, 'maxDistance'),
        minAoeTargets = readTuning(mSettings, 'minAoeTargets'),
        preferAttacker = mSettings['autoAttack_preferAttacker'] and true or false,
    })

    -- Ammo Refill (module type 23 — separate from Auto-attack=9 to avoid the toggle collision)
    g_minibot.resetModule(23) -- Ammo Refill Module type
    local sAmmoRefill = mSettings['ammo_refill']
    if sAmmoRefill ~= nil then
        local internal = {
            item = sAmmoRefill['item'],
            enabled = true,

            use = false,
            min = 0,
            max = 0,
            spell = "",
            spellGroup = {},
            spellId = {},
            area = "",
            target = "",
            health = 0,
            mana = 0,
            hits = 0,
            harmony = 0,
            itemGroup = {},
        }
        g_minibot.addModule(23, internal)
        g_minibot.setModuleToggle(23, sAmmoRefill['enabled'])
    else
        g_minibot.setModuleToggle(23, false)
    end
end

function combat_attackModule.closeCatcher()
    local windowCatcher = modules.game_minibot.getDropDownCatcher()
    if windowCatcher ~= nil then
        windowCatcher:hide()
        windowCatcher.onLeftClick = nil
    end

    if combatAttackWindow == nil then
        return
    end

    combatAttackWindow.dropDownCatcher:hide()
    combatAttackWindow.dropDownMenuScrollBar:hide()
    combatAttackWindow.dropDownMenu:hide()
end

function combat_attackModule.openItemCatcher(itemBlock)
    combatAttackWindow.dropDownCatcher:show()
    combatAttackWindow.dropDownCatcher.onLeftClick = combat_attackModule.closeCatcher

    local windowCatcher = modules.game_minibot.getDropDownCatcher()
    if windowCatcher ~= nil then
        windowCatcher:show()
        windowCatcher.onLeftClick = combat_attackModule.closeCatcher
    end

    combatAttackWindow.dropDownMenu:show()
    combatAttackWindow.dropDownMenuScrollBar:show()
    combatAttackWindow.dropDownMenu:destroyChildren()

    local thingTypes = g_things.findItemTypeByMarketCategory(MarketCategory.Ammunitions)
    for _, thingType in ipairs(thingTypes) do
        local spellWidget = g_ui.createWidget('MiniBotCombatAttackItemDropDownEntry', combatAttackWindow.dropDownMenu)
        spellWidget:constructEnviorementVariables()

        spellWidget.item:setItemId(thingType:getId())
        spellWidget:setTooltip(thingType:getName())

        spellWidget.onLeftClick = function()
            if itemBlock ~= nil then
                itemBlock.item:show()
                itemBlock.item:setItemId(thingType:getId())
                itemBlock.name:setText(thingType:getName())
                itemBlock.frameBackground:setTooltip(thingType:getName())
            end
            combat_attackModule.closeCatcher()
            combat_attackModule.saveSettings()
        end
    end
end

function combat_attackModule.onAmmoRefillChange(widget)
    if combatAttackWindow == nil then
        return
    end

    if widget:isChecked() then
        combatAttackWindow.settings.ammoRefill.block:hide()
        combatAttackWindow.settings.ammoRefill.item:setOpacity(1)
        combatAttackWindow.settings.ammoRefill.frameBackground:setPhantom(false)
        combatAttackWindow.settings.ammoRefill.name:setOpacity(1)
    else
        combatAttackWindow.settings.ammoRefill.block:show()
        combatAttackWindow.settings.ammoRefill.item:setOpacity(0.3)
        combatAttackWindow.settings.ammoRefill.frameBackground:setPhantom(true)
        combatAttackWindow.settings.ammoRefill.name:setOpacity(0.3)
    end

    if widget.ignoreCallback then
        return
    end

    combat_attackModule.saveSettings()
    combat_attackModule.reloadInternalModule()
end

function combat_attackModule.loadSettings()
    local settings = modules.game_minibot.getPressetSettings()
    local mSettings = settings['combat_attack'] or {}
    local sSettings = settings['shortcuts'] or {}

    local autoAttack = sSettings['autoAttack_enabled'] and true or false
    local mode = readMode(mSettings)

    local panel = combatAttackWindow.settings.attackPanel

    panel.autoAttack.ignoreCallback = true
    panel.autoAttack:setChecked(autoAttack)
    combat_attackModule.onAutoAttackCheckChange(panel.autoAttack)
    panel.autoAttack.ignoreCallback = nil

    for _, name in ipairs(ATTACK_MODES) do
        panel[name].ignoreCallback = true
        panel[name]:setChecked(name == mode)
        panel[name].ignoreCallback = nil
    end

    panel.preferAttacker.ignoreCallback = true
    panel.preferAttacker:setChecked(mSettings['autoAttack_preferAttacker'] and true or false)
    panel.preferAttacker.ignoreCallback = nil

    for key in pairs(TUNING) do
        panel[key].ignoreCallback = true
        panel[key]:setText(tostring(readTuning(mSettings, key)))
        panel[key].ignoreCallback = nil
    end

    -- Ammo refill
    local ammoRefillSettings = mSettings['ammo_refill'] or {}
    combatAttackWindow.settings.ammoRefill.check.ignoreCallback = true
    combatAttackWindow.settings.ammoRefill.check:setChecked(ammoRefillSettings['enabled'] or false)
    combat_attackModule.onAmmoRefillChange(combatAttackWindow.settings.ammoRefill.check)
    combatAttackWindow.settings.ammoRefill.check.ignoreCallback = nil
    local item = ammoRefillSettings['item'] or 0
    if item > 0 then
        combatAttackWindow.settings.ammoRefill.item:show()
        combatAttackWindow.settings.ammoRefill.item:setItemId(item)
        combatAttackWindow.settings.ammoRefill.name:setText(combatAttackWindow.settings.ammoRefill.item:getItem():getName())
    else
        combatAttackWindow.settings.ammoRefill.item:hide()
    end
end

function combat_attackModule.saveSettings()
    local settings = modules.game_minibot.getPressetSettings()
    if settings['combat_attack'] == nil then
        settings['combat_attack'] = {}
    end
    if settings['shortcuts'] == nil then
        settings['shortcuts'] = {}
    end

    local panel = combatAttackWindow.settings.attackPanel

    settings['shortcuts']['autoAttack_enabled'] = panel.autoAttack:isChecked()

    local mode = DEFAULT_MODE
    for _, name in ipairs(ATTACK_MODES) do
        if panel[name]:isChecked() then
            mode = name
            break
        end
    end
    settings['combat_attack']['autoAttack_mode'] = mode
    settings['combat_attack']['autoAttack_preferAttacker'] = panel.preferAttacker:isChecked()

    -- Campo vazio (o jogador apagou tudo) salva o default, nao nil: nil faria o
    -- readTuning cair no default de novo na proxima leitura, o que dá no mesmo,
    -- mas gravar o numero mantem o preset explicito e o export legivel.
    for key, spec in pairs(TUNING) do
        local value = tonumber(panel[key]:getText())
        if value == nil then
            value = spec.default
        end
        settings['combat_attack']['autoAttack_' .. key] = math.max(spec.min, math.min(spec.max, math.floor(value)))
    end

    -- Chaves do formato antigo: apagadas para readMode() nao voltar a converter um
    -- preset ja migrado e sobrescrever a escolha atual do jogador.
    settings['combat_attack']['autoAttack_health'] = nil
    settings['combat_attack']['autoAttack_highhealth'] = nil
    settings['combat_attack']['autoAttack_closest'] = nil
    settings['combat_attack']['autoAttack_smartArrow'] = nil
    settings['combat_attack']['attackMelee_enabled'] = nil

    -- Ammo Refill
    local ammoRefillSettings = {}
    ammoRefillSettings['item'] = combatAttackWindow.settings.ammoRefill.item:getItemId()
    ammoRefillSettings['enabled'] = combatAttackWindow.settings.ammoRefill.check:isChecked()
    settings['combat_attack']['ammo_refill'] = ammoRefillSettings

    modules.game_minibot.setPressetSettings(settings)
    combat_attackModule.reloadInternalModule()
end

function combat_attackModule.onAutoAttackCheckChange(widget)
    local enabled = widget:isChecked()

    -- Botao master ON/OFF: reflete o estado no proprio texto do botao.
    widget:setText(enabled and 'ON' or 'OFF')

    -- As opcoes de alvo so fazem sentido com o auto-attack ligado: ficam sempre
    -- visiveis, habilitadas apenas quando ON.
    local panel = combatAttackWindow.settings.attackPanel
    panel.closest:setEnabled(enabled)
    panel.attackClosestHelp:setEnabled(enabled)
    panel.lowest:setEnabled(enabled)
    panel.attackLowestHelp:setEnabled(enabled)
    panel.highest:setEnabled(enabled)
    panel.attackHighestHelp:setEnabled(enabled)
    panel.ranged:setEnabled(enabled)
    panel.attackRangedHelp:setEnabled(enabled)
    panel.preferAttacker:setEnabled(enabled)
    panel.preferAttackerHelp:setEnabled(enabled)
    panel.maxDistance:setEnabled(enabled)
    panel.maxDistanceLabel:setEnabled(enabled)
    panel.maxDistanceHelp:setEnabled(enabled)
    panel.minAoeTargets:setEnabled(enabled)
    panel.minAoeLabel:setEnabled(enabled)
    panel.minAoeHelp:setEnabled(enabled)

    if widget.ignoreCallback then
        modules.game_console.focusChat()
        return
    end

    combat_attackModule.saveSettings()

    local panelGame = modules.game_interface.getMiniBotPanel()
    if panelGame ~= nil then
        local child = panelGame:getChildById('combat_gamewindow')
        if child ~= nil then
            child.ignoreCallback = true
            child:setChecked(enabled)
            child.ignoreCallback = nil
        end
    end

    modules.game_console.focusChat()
end

function combat_attackModule.onAttackOptionChange(widget)
    if widget.ignoreCallback then
        return
    end

    -- Comportamento de radio: a opcao clicada fica marcada e as outras tres saem.
    -- Clicar na que ja estava marcada nao desliga (sempre existe um modo ativo).
    if not(widget:isChecked()) then
        widget.ignoreCallback = true
        widget:setChecked(true)
        widget.ignoreCallback = nil
        return
    end

    local panel = combatAttackWindow.settings.attackPanel
    local selected = widget:getId()
    for _, name in ipairs(ATTACK_MODES) do
        if name ~= selected then
            panel[name].ignoreCallback = true
            panel[name]:setChecked(false)
            panel[name].ignoreCallback = nil
        end
    end

    combat_attackModule.saveSettings()
end

-- Checkbox "priorizar quem me ataca" e os dois campos numericos. Diferente dos
-- modos, nao ha exclusividade: e so salvar e reaplicar.
function combat_attackModule.onAttackTuningChange(widget)
    if widget.ignoreCallback then
        return
    end

    combat_attackModule.saveSettings()
end

-- Clamp dos campos numericos enquanto o jogador digita. O texto vazio e deixado
-- em paz de proposito: apagar para redigitar nao pode escrever um numero de volta
-- em cima do cursor. O saveSettings resolve o vazio pelo default.
function combat_attackModule.validateAttackNumber(widget)
    local spec = TUNING[widget:getId()]
    if spec == nil or widget:getText() == '' then
        if widget.ignoreCallback == nil and widget:getText() == '' then
            combat_attackModule.saveSettings()
        end
        return
    end

    local value = tonumber(widget:getText())
    if value == nil then
        widget:clearText()
        return
    end

    value = math.floor(value)
    if value < spec.min or value > spec.max then
        local clamped = math.max(spec.min, math.min(spec.max, value))
        widget.ignoreCallback = true
        widget:setText(tostring(clamped))
        widget.ignoreCallback = nil
    end

    if widget.ignoreCallback then
        return
    end

    combat_attackModule.saveSettings()
end

function combat_attackModule.reloadEnabledShortcut(_, widget)
    if widget:getId() ~= 'combat_gamewindow' then
        return
    end

    if combatAttackWindow ~= nil then
        combatAttackWindow.settings.attackPanel.autoAttack:setChecked(widget:isChecked())
    else
        local settings = modules.game_minibot.getPressetSettings()
        if settings['shortcuts'] == nil then
            settings['shortcuts'] = {}
        end

        settings['shortcuts']['autoAttack_enabled'] = widget:isChecked()
        modules.game_minibot.setPressetSettings(settings)
        combat_attackModule.reloadInternalModule()
    end
end
