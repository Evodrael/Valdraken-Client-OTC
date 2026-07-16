support_generalModule = {}

local supportGeneralWindow = nil

local hasteSpells = {
    { id = 6, words = "utani hur", name = "Haste" },
    { id = 39, words = "utani gran hur", name = "Strong Haste" },
    { id = 134, words = "utamo tempo san", name = "Swift Foot" },
    { id = 131, words = "utani tempo hur", name = "Charge" },
}

local foodAppend = {
    
}

-- Armas de treino e dummies do Valdraken.
--
-- Fonte (nao inventar ids): o servidor so aceita como exercise weapon os ids de
-- exerciseWeaponsTable em data/scripts/actions/items/exercise_training_weapons.lua,
-- e so trata como dummy os itens marcados com type="dummy" em data/items/items.xml
-- (os mesmos que a loja vende em data/modules/scripts/gamestore/gamestore.lua).
-- As listas antigas vinham do Tibia global (Daily/Epic/Legend/Mystic/Special/Weak,
-- Deus/Super/Future Mage Dummy) e NAO existem neste servidor: getThingType nao
-- achava o id, devolvia o thing nulo (id 0) e a opcao escolhida virava item = 0,
-- entao o treino nunca comecava.
local trainingWeapons = {
    28541, -- training axe
    28553, -- exercise axe
    35280, -- durable exercise axe
    35286, -- lasting exercise axe

    28543, -- training bow
    28555, -- exercise bow
    35282, -- durable exercise bow
    35288, -- lasting exercise bow

    28542, -- training club
    28554, -- exercise club
    35281, -- durable exercise club
    35287, -- lasting exercise club

    28544, -- training rod
    28556, -- exercise rod
    35283, -- durable exercise rod
    35289, -- lasting exercise rod

    44064, -- training shield
    44065, -- exercise shield
    44066, -- durable exercise shield
    44067, -- lasting exercise shield

    28540, -- training sword
    28552, -- exercise sword
    35279, -- durable exercise sword
    35285, -- lasting exercise sword

    28545, -- training wand
    28557, -- exercise wand
    35284, -- durable exercise wand
    35290, -- lasting exercise wand

    50292, -- training wraps
    50293, -- exercise wraps
    50294, -- durable exercise wraps
    50295, -- lasting exercise wraps
    64341, -- training wrap (custom Valdraken)
    64342, -- exercise wrap (custom Valdraken)
    64343, -- durable exercise wrap (custom Valdraken)
    64344, -- lasting exercise wrap (custom Valdraken)
}

-- Armas que exigem estar coladas no dummy. Rod/bow/wand tem allowFarUse no
-- servidor; o resto (axe/club/shield/sword/wraps) so funciona corpo a corpo.
local meleeWeapons = {
    28541, -- training axe
    28553, -- exercise axe
    35280, -- durable exercise axe
    35286, -- lasting exercise axe

    28542, -- training club
    28554, -- exercise club
    35281, -- durable exercise club
    35287, -- lasting exercise club

    44064, -- training shield
    44065, -- exercise shield
    44066, -- durable exercise shield
    44067, -- lasting exercise shield

    28540, -- training sword
    28552, -- exercise sword
    35279, -- durable exercise sword
    35285, -- lasting exercise sword

    50292, -- training wraps
    50293, -- exercise wraps
    50294, -- durable exercise wraps
    50295, -- lasting exercise wraps
    64341, -- training wrap (custom Valdraken)
    64342, -- exercise wrap (custom Valdraken)
    64343, -- durable exercise wrap (custom Valdraken)
    64344, -- lasting exercise wrap (custom Valdraken)
}

-- Um id por TIPO de dummy (o que aparece no dropdown).
local trainingDummies = {
    28558, -- exercise dummy
    28561, -- demon exercise dummy
    28559, -- ferumbras exercise dummy
    28563, -- monk exercise dummy
    60086, -- chaotic training dummy
    60643, -- lich king training dummy
    61348, -- burn skull training dummy
}

-- Todos os ids que contam como aquele dummy no chao: cada dummy tem uma variacao
-- por rotateto (items.xml), e o "ferumbras"/"exercise" tem copias extras com o
-- mesmo nome. O MiniBot procura qualquer um destes ids no tile.
local dummiesPositions = {
    [28558] = { 28558, 28565 }, -- exercise dummy
    [28561] = { 28561, 28562 }, -- demon exercise dummy
    [28559] = { 28559, 28560, 60259, 60641, 60645 }, -- ferumbras exercise dummy
    [28563] = { 28563, 28564 }, -- monk exercise dummy
    [60086] = { 60086, 60087 }, -- chaotic training dummy
    [60643] = { 60643, 60644 }, -- lich king training dummy
    [61348] = { 61348, 61349 }, -- burn skull training dummy
}

function support_generalModule.init(widget)
    supportGeneralWindow = widget

    support_generalModule.loadSettings()

    supportGeneralWindow.panel.autoHaste.frameBackground.onLeftClick = function()
        supportGeneralWindow.dropDownMenu:setMarginLeft(48)
        supportGeneralWindow.dropDownMenu:setMarginTop(65)
        support_generalModule.openSpellCatcher(supportGeneralWindow.panel.autoHaste)
    end

    supportGeneralWindow.panel.autoEat.frameBackground.onLeftClick = function()
        supportGeneralWindow.dropDownMenu:setMarginLeft(48)
        supportGeneralWindow.dropDownMenu:setMarginTop(175)
        support_generalModule.openItemCatcher(supportGeneralWindow.panel.autoEat)
    end

    supportGeneralWindow.panel.autoTraining.frameBackground1.onLeftClick = function()
        supportGeneralWindow.dropDownMenu:setMarginLeft(48)
        supportGeneralWindow.dropDownMenu:setMarginTop(265)
        support_generalModule.openItemTrainingCatcher(supportGeneralWindow.panel.autoTraining, 1)
    end

    supportGeneralWindow.panel.autoTraining.frameBackground2.onLeftClick = function()
        supportGeneralWindow.dropDownMenu:setMarginLeft(0)
        supportGeneralWindow.dropDownMenu:setMarginTop(265)
        support_generalModule.openItemTrainingCatcher(supportGeneralWindow.panel.autoTraining, 2)
    end
end

function support_generalModule.terminate()
    support_generalModule.closeCatcher()

    supportGeneralWindow = nil
end

function support_generalModule.reloadLanguage(language)
    if language == 'ptbr' then
        supportGeneralWindow.panel.title:setText('Geral')
        supportGeneralWindow.panel.autoHaste.noVocation:setTooltip('Sua vocacao nao pode usar esta spell.')
        supportGeneralWindow.panel.autoHaste.help:setTooltip('O AutoHaste detectara automaticamente quando seu bonus de velocidade acabar e usara a spell selecionada.')
        supportGeneralWindow.panel.autoHaste.ignoreProtection:setText('Ignorar em PZ')
        supportGeneralWindow.panel.autoHaste.ignoreProtection:setTextOffset('0 0')
        supportGeneralWindow.panel.autoHaste.ignoreProteconMask:setMarginLeft(0)
        supportGeneralWindow.panel.changeGold.check:setText('Troca de coin automatico')
        supportGeneralWindow.panel.changeGold.help:setTooltip('Todas as suas moedas de gold/platinum serao automaticamente transformadas em sua versao mais valiosa quando acumuladas em 100 unidades.')
        supportGeneralWindow.panel.autoMount.check:setText('Montaria automatica')
        supportGeneralWindow.panel.autoMount.help:setTooltip('Ao sair de uma Protection Zone, o Assistente ira tentar manter sempre a montaria ativa no seu personagem.')
        supportGeneralWindow.panel.autoEat.check:setText('Comer automaticamente')
        supportGeneralWindow.panel.autoEat.help:setTooltip('Voce pode selecionar uma Food especifica para que seu personagem coma periodicamente, para mante-lo satisfeito.')
        supportGeneralWindow.panel.autoTraining.check:setText('Treino automatico')
        supportGeneralWindow.panel.autoTraining.help:setTooltip('Voce pode selecionar uma Exercise Weapon especifica e um Dummy para que o Assistente inicie o treinamento automaticamente.')
        supportGeneralWindow.panel.autoBless.check:setText('Bless automatico')
        supportGeneralWindow.panel.autoBless.help:setTooltip('Ao morrer, o Assistente enviara automaticamente o comando !bless no proximo login deste personagem.')
        supportGeneralWindow.panel.autoFollow.check:setText('Follow automatico')
        supportGeneralWindow.panel.autoFollow.name:setPlaceholder('Digite o nome do jogador')
        supportGeneralWindow.panel.autoFollow.help:setTooltip('O Assistente seguira o jogador com este nome sempre que ele estiver na sua tela.')
        supportGeneralWindow.panel.autoReconnect.check:setText('Reconexao automatica')
        supportGeneralWindow.panel.autoReconnect.help:setTooltip('Se a conexao com o servidor cair, o client refaz o login deste personagem automaticamente. So funciona com o client aberto, e nao age em logout manual.')


    elseif language == 'enus' then
        supportGeneralWindow.panel.title:setText('General')
        supportGeneralWindow.panel.autoHaste.noVocation:setTooltip('Your vocation cannot use this spell.')
        supportGeneralWindow.panel.autoHaste.help:setTooltip('Auto Haste will automatically detect when your haste buff is gone and cast the selected spell.')
        supportGeneralWindow.panel.autoHaste.ignoreProtection:setText('Ignore on PZ')
        supportGeneralWindow.panel.autoHaste.ignoreProtection:setTextOffset('0 0')
        supportGeneralWindow.panel.autoHaste.ignoreProteconMask:setMarginLeft(0)
        supportGeneralWindow.panel.changeGold.check:setText('Auto change gold')
        supportGeneralWindow.panel.changeGold.help:setTooltip('All your gold/platinum coins will be automatically transformed into their most valuable version when it stacks into 100 units.')
        supportGeneralWindow.panel.autoMount.check:setText('Auto change gold')
        supportGeneralWindow.panel.autoMount.help:setTooltip('When leaving a Protection Zone, the Assistant will try to always keep the mount active on your character.')
        supportGeneralWindow.panel.autoEat.check:setText('Auto eat')
        supportGeneralWindow.panel.autoEat.help:setTooltip('You can select a specific food so that your character will periodically eat it, to maintain you satisfied.')
        supportGeneralWindow.panel.autoTraining.check:setText('Auto training')
        supportGeneralWindow.panel.autoTraining.help:setTooltip('You can select a specific exercise weapon and a dummy type, so that the Assistant will automatically start training.')
        supportGeneralWindow.panel.autoBless.check:setText('Auto bless')
        supportGeneralWindow.panel.autoBless.help:setTooltip('When you die, the Assistant will automatically send the !bless command on your next login with this character.')
        supportGeneralWindow.panel.autoFollow.check:setText('Auto follow')
        supportGeneralWindow.panel.autoFollow.name:setPlaceholder('Type player name')
        supportGeneralWindow.panel.autoFollow.help:setTooltip('The Assistant will keep following the player with this name whenever they are on your screen.')
        supportGeneralWindow.panel.autoReconnect.check:setText('Auto reconnect')
        supportGeneralWindow.panel.autoReconnect.help:setTooltip('If the connection to the game server drops, the client logs this character back in automatically. Only works while the client stays open, and it does not act on a manual logout.')

    end
end

function support_generalModule.saveSettings()
    local settings = modules.game_minibot.getPressetSettings()
    local sList = settings['support_main'] or {}
    if settings['shortcuts'] == nil then
        settings['shortcuts'] = {}
    end

    -- Haste
    -- A spell escolhida fica guardada em spellInfoId. Antes ela era deduzida de
    -- volta pelo x do image-clip do icone, e o icone nasce com "image-clip: 0 0 32 32"
    -- no .otui: sem spell escolhida o x era 0, que getSpellRegularIdByImageClipX
    -- resolve para o primeiro icone da folha (id 3, Ultimate Healing). Ou seja, so
    -- marcar o check ja gravava "exura vita" como spell do Auto Haste.
    local hasteSettings = {}
    local spellId = supportGeneralWindow.panel.autoHaste.spellInfoId or 0
    local spell = g_spells.getSpellInfoById(spellId)
    if spell ~= nil then
        hasteSettings['spell'] = spell.id
        hasteSettings['reqmana'] = spell.mana
    else
        hasteSettings['spell'] = 0
        hasteSettings['reqmana'] = 0
    end
    hasteSettings['enabled'] = supportGeneralWindow.panel.autoHaste.check:isChecked()
    hasteSettings['ignorePz'] = supportGeneralWindow.panel.autoHaste.ignoreProtection:isChecked()
    sList['haste'] = hasteSettings

    -- Change gold
    local changeGoldSettings = {}
    changeGoldSettings['enabled'] = supportGeneralWindow.panel.changeGold.check:isChecked()
    sList['change_gold'] = changeGoldSettings

    -- Auto Eat
    local autoEatSettings = {}
    autoEatSettings['item'] = supportGeneralWindow.panel.autoEat.item:getItemId()
    autoEatSettings['enabled'] = supportGeneralWindow.panel.autoEat.check:isChecked()
    sList['auto_eat'] = autoEatSettings

    -- Auto Mount
    local autoMountSettings = {}
    autoMountSettings['enabled'] = supportGeneralWindow.panel.autoMount.check:isChecked()
    sList['auto_mount'] = autoMountSettings

    -- Auto Training
    local autoTrainingSettings = {}
    autoTrainingSettings['item1'] = supportGeneralWindow.panel.autoTraining.item1:getItemId()
    autoTrainingSettings['item2'] = supportGeneralWindow.panel.autoTraining.item2:getItemId()
    autoTrainingSettings['enabled'] = supportGeneralWindow.panel.autoTraining.check:isChecked()
    sList['auto_training'] = autoTrainingSettings

    -- Auto Bless
    local autoBlessSettings = {}
    autoBlessSettings['enabled'] = supportGeneralWindow.panel.autoBless.check:isChecked()
    sList['auto_bless'] = autoBlessSettings

    -- Auto Follow
    local autoFollowSettings = {}
    autoFollowSettings['enabled'] = supportGeneralWindow.panel.autoFollow.check:isChecked()
    autoFollowSettings['name'] = supportGeneralWindow.panel.autoFollow.name:getText()
    sList['auto_follow'] = autoFollowSettings

    -- Auto Reconnect
    local autoReconnectSettings = {}
    autoReconnectSettings['enabled'] = supportGeneralWindow.panel.autoReconnect.check:isChecked()
    sList['auto_reconnect'] = autoReconnectSettings

    settings['support_main'] = sList
    modules.game_minibot.setPressetSettings(settings)
    support_generalModule.reloadInternalModule()
end

function support_generalModule.loadSettings()
    local settings = modules.game_minibot.getPressetSettings()
    local sList = settings['support_main'] or {}
    local sShortcut = settings['shortcuts'] or {}

    -- Haste
    local hasteSettings = sList['haste'] or {}
    supportGeneralWindow.panel.autoHaste.check.ignoreCallback = true
    supportGeneralWindow.panel.autoHaste.check:setChecked(hasteSettings['enabled'] or false)
    supportGeneralWindow.panel.autoHaste.ignoreProtection.ignoreCallback = true
    supportGeneralWindow.panel.autoHaste.ignoreProtection:setChecked(hasteSettings['ignorePz'] or false)
    supportGeneralWindow.panel.autoHaste.ignoreProtection.ignoreCallback = nil
    support_generalModule.onHasteChange(supportGeneralWindow.panel.autoHaste.check)
    supportGeneralWindow.panel.autoHaste.check.ignoreCallback = nil
    local spell = g_spells.getSpellInfoById(hasteSettings['spell'] or 0)
    if spell ~= nil then
        supportGeneralWindow.panel.autoHaste.spellInfoId = spell.id
        supportGeneralWindow.panel.autoHaste.spell:show()
        supportGeneralWindow.panel.autoHaste.spell:setImageClip(g_spells.getSpellRegularImageClipById(spell.id))
        supportGeneralWindow.panel.autoHaste.name:setText(spell.name)
        supportGeneralWindow.panel.autoHaste.words:setText(spell.words)
        supportGeneralWindow.panel.autoHaste.frameBackground:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')
        if not(modules.game_actionbar.canSpellCast(spell)) then
            supportGeneralWindow.panel.autoHaste.noVocation:show()
        else
            supportGeneralWindow.panel.autoHaste.noVocation:hide()
        end
    else
        supportGeneralWindow.panel.autoHaste.spellInfoId = 0
        supportGeneralWindow.panel.autoHaste.spell:hide()
        supportGeneralWindow.panel.autoHaste.noVocation:hide()
    end

    -- Change gold
    supportGeneralWindow.panel.changeGold.check.ignoreCallback = true
    supportGeneralWindow.panel.changeGold.check:setChecked(sList['change_gold'] ~= nil and sList['change_gold']['enabled'] or false)
    supportGeneralWindow.panel.changeGold.check.ignoreCallback = nil

    -- Auto Eat
    local autoEatSettings = sList['auto_eat'] or {}
    supportGeneralWindow.panel.autoEat.check.ignoreCallback = true
    supportGeneralWindow.panel.autoEat.check:setChecked(autoEatSettings['enabled'] or false)
    support_generalModule.onAutoEatChange(supportGeneralWindow.panel.autoEat.check)
    supportGeneralWindow.panel.autoEat.check.ignoreCallback = nil
    local item = autoEatSettings['item'] or 0
    if item > 0 then
        supportGeneralWindow.panel.autoEat.item:show()
        supportGeneralWindow.panel.autoEat.item:setItemId(item)
        supportGeneralWindow.panel.autoEat.name:setText(supportGeneralWindow.panel.autoEat.item:getItem():getName())
    else
        supportGeneralWindow.panel.autoEat.item:hide()
    end

    -- Auto Mount
    local autoMountSettings = sList['auto_mount'] or {}
    supportGeneralWindow.panel.autoMount.check.ignoreCallback = true
    supportGeneralWindow.panel.autoMount.check:setChecked(autoMountSettings['enabled'] or false)
    support_generalModule.onAutoMountChange(supportGeneralWindow.panel.autoMount.check)
    supportGeneralWindow.panel.autoMount.check.ignoreCallback = nil

    -- Auto Training
    local autoTrainingSettings = sList['auto_training'] or {}
    supportGeneralWindow.panel.autoTraining.check.ignoreCallback = true
    supportGeneralWindow.panel.autoTraining.check:setChecked(autoTrainingSettings['enabled'] or false)
    support_generalModule.onAutoTrainingChange(supportGeneralWindow.panel.autoTraining.check)
    supportGeneralWindow.panel.autoTraining.check.ignoreCallback = nil
    -- Presets salvos antes da correcao das listas guardam ids do Tibia global que
    -- nao existem aqui. Limpa a selecao invalida em vez de mostrar um slot vazio
    -- que parece configurado mas nunca treina.
    local item1 = autoTrainingSettings['item1'] or 0
    if table.find(trainingWeapons, item1) then
        supportGeneralWindow.panel.autoTraining.item1:show()
        supportGeneralWindow.panel.autoTraining.item1:setItemId(item1)
    else
        supportGeneralWindow.panel.autoTraining.item1:setItemId(0)
        supportGeneralWindow.panel.autoTraining.item1:hide()
    end
    local item2 = autoTrainingSettings['item2'] or 0
    if dummiesPositions[item2] ~= nil then
        supportGeneralWindow.panel.autoTraining.item2:show()
        supportGeneralWindow.panel.autoTraining.item2:setItemId(item2)
    else
        supportGeneralWindow.panel.autoTraining.item2:setItemId(0)
        supportGeneralWindow.panel.autoTraining.item2:hide()
    end

    -- Auto Bless
    local autoBlessSettings = sList['auto_bless'] or {}
    supportGeneralWindow.panel.autoBless.check.ignoreCallback = true
    supportGeneralWindow.panel.autoBless.check:setChecked(autoBlessSettings['enabled'] or false)
    supportGeneralWindow.panel.autoBless.check.ignoreCallback = nil

    -- Auto Follow
    local autoFollowSettings = sList['auto_follow'] or {}
    supportGeneralWindow.panel.autoFollow.name.ignoreCallback = true
    supportGeneralWindow.panel.autoFollow.name:setText(autoFollowSettings['name'] or '')
    supportGeneralWindow.panel.autoFollow.name.ignoreCallback = nil
    supportGeneralWindow.panel.autoFollow.check.ignoreCallback = true
    supportGeneralWindow.panel.autoFollow.check:setChecked(autoFollowSettings['enabled'] or false)
    support_generalModule.onAutoFollowChange(supportGeneralWindow.panel.autoFollow.check)
    supportGeneralWindow.panel.autoFollow.check.ignoreCallback = nil

    -- Auto Reconnect
    local autoReconnectSettings = sList['auto_reconnect'] or {}
    supportGeneralWindow.panel.autoReconnect.check.ignoreCallback = true
    supportGeneralWindow.panel.autoReconnect.check:setChecked(autoReconnectSettings['enabled'] or false)
    supportGeneralWindow.panel.autoReconnect.check.ignoreCallback = nil
end

function support_generalModule.onChangeGoldChange(widget)
    if widget.ignoreCallback then
        return
    end

    support_generalModule.saveSettings()
    support_generalModule.reloadInternalModule()
end

function support_generalModule.onAutoMountChange(widget)
    if widget.ignoreCallback then
        return
    end

    support_generalModule.saveSettings()
    support_generalModule.reloadInternalModule()
end

function support_generalModule.onAutoBlessChange(widget)
    if widget.ignoreCallback then
        return
    end

    support_generalModule.saveSettings()
    support_generalModule.reloadInternalModule()
end

function support_generalModule.onAutoFollowChange(widget)
    if widget:isChecked() then
        supportGeneralWindow.panel.autoFollow.name:setEnabled(true)
        supportGeneralWindow.panel.autoFollow.name:setOpacity(1)
    else
        supportGeneralWindow.panel.autoFollow.name:setEnabled(false)
        supportGeneralWindow.panel.autoFollow.name:setOpacity(0.3)
    end

    if widget.ignoreCallback then
        return
    end

    support_generalModule.saveSettings()
    support_generalModule.reloadInternalModule()
end

function support_generalModule.onAutoReconnectChange(widget)
    if widget.ignoreCallback then
        return
    end

    support_generalModule.saveSettings()
    support_generalModule.reloadInternalModule()
end

function support_generalModule.onAutoFollowNameChange(widget)
    if widget.ignoreCallback then
        return
    end

    support_generalModule.saveSettings()
    support_generalModule.reloadInternalModule()
end

function support_generalModule.onHasteChange(widget)
    if widget:isChecked() then
        supportGeneralWindow.panel.autoHaste.block:hide()
        supportGeneralWindow.panel.autoHaste.spell:setOpacity(1)
        supportGeneralWindow.panel.autoHaste.frameBackground:setPhantom(false)
        supportGeneralWindow.panel.autoHaste.noVocation:setOpacity(1)
        supportGeneralWindow.panel.autoHaste.noVocation:setPhantom(false)
        supportGeneralWindow.panel.autoHaste.name:setOpacity(1)
        supportGeneralWindow.panel.autoHaste.words:setOpacity(1)
        supportGeneralWindow.panel.autoHaste.ignoreProtection:setEnabled(true)
    else
        supportGeneralWindow.panel.autoHaste.block:show()
        supportGeneralWindow.panel.autoHaste.spell:setOpacity(0.3)
        supportGeneralWindow.panel.autoHaste.frameBackground:setPhantom(true)
        supportGeneralWindow.panel.autoHaste.noVocation:setOpacity(0.5)
        supportGeneralWindow.panel.autoHaste.noVocation:setPhantom(true)
        supportGeneralWindow.panel.autoHaste.name:setOpacity(0.3)
        supportGeneralWindow.panel.autoHaste.words:setOpacity(0.3)
        supportGeneralWindow.panel.autoHaste.ignoreProtection:setEnabled(false)
    end

    if widget.ignoreCallback then
        return
    end

    support_generalModule.saveSettings()
    support_generalModule.reloadInternalModule()
end

function support_generalModule.onIgnoreProtectionChange(widget)
    if widget.ignoreCallback then
        return
    end

    support_generalModule.saveSettings()
    support_generalModule.reloadInternalModule()
end

function support_generalModule.onAutoEatChange(widget)
    if widget:isChecked() then
        supportGeneralWindow.panel.autoEat.block:hide()
        supportGeneralWindow.panel.autoEat.item:setOpacity(1)
        supportGeneralWindow.panel.autoEat.frameBackground:setPhantom(false)
        supportGeneralWindow.panel.autoEat.name:setOpacity(1)
    else
        supportGeneralWindow.panel.autoEat.block:show()
        supportGeneralWindow.panel.autoEat.item:setOpacity(0.3)
        supportGeneralWindow.panel.autoEat.frameBackground:setPhantom(true)
        supportGeneralWindow.panel.autoEat.name:setOpacity(0.3)
    end

    if widget.ignoreCallback then
        return
    end

    support_generalModule.saveSettings()
    support_generalModule.reloadInternalModule()
end

function support_generalModule.onAutoTrainingChange(widget)
    if widget:isChecked() then
        supportGeneralWindow.panel.autoTraining.block1:hide()
        supportGeneralWindow.panel.autoTraining.item1:setOpacity(1)
        supportGeneralWindow.panel.autoTraining.item2:setOpacity(1)
        supportGeneralWindow.panel.autoTraining.frameBackground1:setPhantom(false)
        supportGeneralWindow.panel.autoTraining.frameBackground2:setPhantom(false)
    else
        supportGeneralWindow.panel.autoTraining.block1:show()
        supportGeneralWindow.panel.autoTraining.item1:setOpacity(0.3)
        supportGeneralWindow.panel.autoTraining.item2:setOpacity(0.3)
        supportGeneralWindow.panel.autoTraining.frameBackground1:setPhantom(true)
        supportGeneralWindow.panel.autoTraining.frameBackground2:setPhantom(true)
    end

    if widget.ignoreCallback then
        return
    end

    support_generalModule.saveSettings()
    support_generalModule.reloadInternalModule()
end

function support_generalModule.reloadInternalModule()
    local settings = modules.game_minibot.getPressetSettings()

    local sList = settings['support_main'] or {}
    local sShortcut = settings['shortcuts'] or {}

    -- Haste
    g_minibot.resetModule(4) -- Healing Haste Module type
    local sHaste = sList['haste']
    if sHaste ~= nil then
        local internal = {
            item = 0,
            use = false,
            min = 0,
            max = 0,
            enabled = sHaste['enabled'],
            ignorePz = sHaste['ignorePz'],
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
        local spell = g_spells.getSpellInfoById(sHaste['spell'])
        if spell ~= nil then
            internal.spell = spell.words
            internal.reqmana = spell.mana
            table.insert(internal.spellId, spell.id)
            for _, group in ipairs(spell.groups) do
                table.insert(internal.spellGroup, group)
            end
        end
        g_minibot.addModule(4, internal)
        g_minibot.setModuleToggle(4, sHaste['enabled']) -- Haste needs its toggle or it never runs
    else
        g_minibot.setModuleToggle(4, false)
    end

    -- Change Gold
    g_minibot.resetModule(7) -- Change Gold Module type
    local changeGoldEnabled = false
    local sChangeGold = sList['change_gold']
    if sChangeGold ~= nil then
        changeGoldEnabled = sChangeGold['enabled']
        -- Register an entry so the C++ cycle actually runs the conversion.
        g_minibot.addModule(7, {
            enabled = true,
            item = 0,
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
        })
    end
    g_minibot.setModuleToggle(7, changeGoldEnabled) -- Change Gold Module type

    -- Auto Eat
    g_minibot.resetModule(8) -- Auto Eat Module type
    local sAutoEat = sList['auto_eat']
    if sAutoEat ~= nil then
        local internal = {
            item = sAutoEat['item'],
            use = true,
            enabled = true,

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
            itemGroup = { 255 }, -- Multiuse
        }
        g_minibot.addModule(8, internal)
        g_minibot.setModuleToggle(8, sAutoEat['enabled'])
    else
        g_minibot.setModuleToggle(8, false)
    end

    -- Auto Training
    g_minibot.resetModule(12) -- Auto Training Module type
    local sAutoTraining = sList['auto_training']
    if sAutoTraining ~= nil then
        local internal = {
            item = sAutoTraining['item1'] or 0,
            use = table.find(meleeWeapons, sAutoTraining['item1'] or 0),
            spellGroup = {},
            enabled = true,

            min = 0,
            max = 0,
            hits = 0,
            spell = "",
            spellId = {},
            area = "",
            target = "",
            health = 0,
            mana = 0,
            harmony = 0,
            itemGroup = { 255 }, -- Multiuse
        }

        local variations = dummiesPositions[sAutoTraining['item2'] or 0]
        if variations ~= nil then
            for _, id in ipairs(variations) do
                table.insert(internal.spellGroup, id)
            end
        end

        g_minibot.addModule(12, internal)
        g_minibot.setModuleToggle(12, sAutoTraining['enabled'])
    else
        g_minibot.setModuleToggle(12, false)
    end

    -- Auto Mount
    g_minibot.resetModule(22) -- Auto Mount Module type
    local sAutoMount = sList['auto_mount']
    if sAutoMount ~= nil then
        local internal = {
            enabled = true,

            item = 0,
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
        g_minibot.addModule(22, internal)
        g_minibot.setModuleToggle(22, sAutoMount['enabled'])
    else
        g_minibot.setModuleToggle(22, false)
    end

    -- Auto Bless and Auto Follow have no engine module: they are driven from
    -- minibot.lua, which owns the death/login hooks and the follow tick.
    modules.game_minibot.reloadSupportRuntime()
end

function support_generalModule.closeCatcher()
    local windowCatcher = modules.game_minibot.getDropDownCatcher()
    if windowCatcher ~= nil then
        windowCatcher:hide()
        windowCatcher.onLeftClick = nil
    end

    if supportGeneralWindow == nil then
        return
    end

    supportGeneralWindow.dropDownCatcher:hide()
    supportGeneralWindow.dropDownMenuScrollBar:hide()
    supportGeneralWindow.dropDownMenu:hide()
end

function support_generalModule.openSpellCatcher(spellBlock)
    supportGeneralWindow.dropDownCatcher:show()
    supportGeneralWindow.dropDownCatcher.onLeftClick = support_generalModule.closeCatcher

    local windowCatcher = modules.game_minibot.getDropDownCatcher()
    if windowCatcher ~= nil then
        windowCatcher:show()
        windowCatcher.onLeftClick = support_generalModule.closeCatcher
    end

    supportGeneralWindow.dropDownMenu:show()
    supportGeneralWindow.dropDownMenuScrollBar:show()
    supportGeneralWindow.dropDownMenu:destroyChildren()

    for _, spell in ipairs(hasteSpells) do
        local foundSpell = g_spells.getSpellInfoById(spell.id)
        if foundSpell ~= nil then
            local spellWidget = g_ui.createWidget('MiniBotSupportGeneralSpellDropDownEntry', supportGeneralWindow.dropDownMenu)
            spellWidget:constructEnviorementVariables()

            if not(modules.game_actionbar.canSpellCast(foundSpell)) then
                spellWidget.block:show()
                spellWidget.icon:setOpacity(0.3)
            else
                spellWidget.block:hide()
                spellWidget.icon:setOpacity(1)
            end

            spellWidget.icon:setImageClip(g_spells.getSpellRegularImageClipById(foundSpell.id))
            spellWidget:setTooltip(foundSpell.name .. '\n\'' .. foundSpell.words .. '\'')

            spellWidget.onLeftClick = function()
                if spellBlock ~= nil then
                    spellBlock.spellInfoId = foundSpell.id
                    spellBlock.spell:show()
                    spellBlock.spell:setImageClip(g_spells.getSpellRegularImageClipById(foundSpell.id))
                    spellBlock.name:setText(foundSpell.name)
                    spellBlock.words:setText(foundSpell.words)
                    spellBlock.frameBackground:setTooltip(foundSpell.name .. '\n\'' .. foundSpell.words .. '\'')
                    if not(modules.game_actionbar.canSpellCast(foundSpell)) then
                        spellBlock.noVocation:show()
                    else
                        spellBlock.noVocation:hide()
                    end
                end
                support_generalModule.closeCatcher()
                support_generalModule.saveSettings()
            end
        end
    end
end

function support_generalModule.openItemCatcher(itemBlock)
    supportGeneralWindow.dropDownCatcher:show()
    supportGeneralWindow.dropDownCatcher.onLeftClick = support_generalModule.closeCatcher

    local windowCatcher = modules.game_minibot.getDropDownCatcher()
    if windowCatcher ~= nil then
        windowCatcher:show()
        windowCatcher.onLeftClick = support_generalModule.closeCatcher
    end

    supportGeneralWindow.dropDownMenu:show()
    supportGeneralWindow.dropDownMenuScrollBar:show()
    supportGeneralWindow.dropDownMenu:destroyChildren()

    local thingTypes = g_things.findItemTypeByMarketCategory(MarketCategory.Food)
    for _, item in ipairs(foodAppend) do
        local thingType = g_things.getThingType(item)
        if thingType ~= nil then
            table.insert(thingTypes, thingType)
        end
    end

    for _, thingType in ipairs(thingTypes) do
        local itemWidget = g_ui.createWidget('MiniBotSupportGeneralItemDropDownEntry', supportGeneralWindow.dropDownMenu)
        itemWidget:constructEnviorementVariables()

        itemWidget.item:setItemId(thingType:getId())
        itemWidget:setTooltip(thingType:getName())

        itemWidget.onLeftClick = function()
            if itemBlock ~= nil then
                itemBlock.item:show()
                itemBlock.item:setItemId(thingType:getId())
                itemBlock.name:setText(thingType:getName())
                itemBlock.frameBackground:setTooltip(thingType:getName())
            end
            support_generalModule.closeCatcher()
            support_generalModule.saveSettings()
        end
    end
end

function support_generalModule.openItemTrainingCatcher(itemBlock, type)
    supportGeneralWindow.dropDownCatcher:show()
    supportGeneralWindow.dropDownCatcher.onLeftClick = support_generalModule.closeCatcher

    local windowCatcher = modules.game_minibot.getDropDownCatcher()
    if windowCatcher ~= nil then
        windowCatcher:show()
        windowCatcher.onLeftClick = support_generalModule.closeCatcher
    end

    supportGeneralWindow.dropDownMenu:show()
    supportGeneralWindow.dropDownMenuScrollBar:show()
    supportGeneralWindow.dropDownMenu:destroyChildren()

    -- getThingType() loga erro e devolve o thing nulo (id 0) para id que nao existe
    -- nos assets, o que colocaria uma entrada vazia no dropdown. Filtra antes.
    local ids = nil
    if type == 1 then
        ids = trainingWeapons
    elseif type == 2 then
        ids = trainingDummies
    end

    local thingTypes = {}
    for _, id in ipairs(ids or {}) do
        if g_things.isValidDatId(id, ThingCategoryItem) then
            table.insert(thingTypes, g_things.getThingType(id, ThingCategoryItem))
        end
    end

    for _, thingType in ipairs(thingTypes) do
        local itemWidget = g_ui.createWidget('MiniBotSupportGeneralItemDropDownEntry', supportGeneralWindow.dropDownMenu)
        itemWidget:constructEnviorementVariables()

        itemWidget.item:setItemId(thingType:getId())
        itemWidget:setTooltip(thingType:getName())

        itemWidget.onLeftClick = function()
            local item = itemBlock['item' .. type]
            local frameBackground = itemBlock['frameBackground' .. type]

            item:show()
            item:setItemId(thingType:getId())
            frameBackground:setTooltip(thingType:getName())

            support_generalModule.closeCatcher()
            support_generalModule.saveSettings()

            if supportGeneralWindow.panel.autoTraining.check:isChecked() then
                support_generalModule.reloadInternalModule()
            end
        end
    end
end

function support_generalModule.onMissileTo(missile, from, to)
    if not(g_minibot.isModuleToggle(12)) then
        return
    end

    -- PlayerStates.StatePz nao existe (o campo chama Pz), entao hasState() recebia
    -- nil e devolvia sempre false: a animacao do treino nunca aparecia.
    local player = g_game.getLocalPlayer()
    if player == nil or not(player:hasState(PlayerStates.Pz)) then
        return
    end

    if player:getPosition().x ~= from.x or player:getPosition().y ~= from.y or player:getPosition().z ~= from.z then
        return
    end

    g_minibot.setModuleTimeTick(12, g_clock.millis() + 2200)

    if supportGeneralWindow == nil then
        return
    end

    local widget = g_ui.createWidget("UICreature", supportGeneralWindow.panel.autoTraining.effects)
    widget:setPhantom(true)
    local outfit = {
        type = 0,
        auxType = missile,
        addons = 0,
        head = 0,
        body = 0,
        legs = 0,
        feet = 0,
        mount = 0,
        wings = 0,
        aura = 0,
        shader = '',
        healthBar = 0,
        manaBar = 0,
        category = ThingCategoryMissile
    }


    widget:setPhantom(true)
    widget:setMarginBottom(12)
    widget:setWidth(48)
    widget:setHeight(48)
    widget:setOutfit(outfit)
    widget:setDirection(5)
    widget:getCreature():setDirection(2)
    widget:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    widget:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)

    local speedMultiplier = 3.0
    local duration = (150 * math.floor(supportGeneralWindow.panel.autoTraining.effects:getWidth() / 32)) / speedMultiplier
    local initialMarginLeft = 0
    local finalMarginLeft = supportGeneralWindow.panel.autoTraining.effects:getWidth() - 48

    local animationStartTime = g_clock.millis()
    local totalDelta = finalMarginLeft - initialMarginLeft
    local frameInterval = 16

    local function animationCycle()
        if widget.missileMoveEvent ~= nil then
            removeEvent(widget.missileMoveEvent)
            widget.missileMoveEvent = nil
        end

        if supportGeneralWindow == nil then
            if not(widget:isDestroyed()) then
                widget:destroy()
            end

            widget = nil
            return
        end

        local now = g_clock.millis()
        local elapsed = now - animationStartTime

        if elapsed >= duration then
            if not(widget:isDestroyed()) then
                widget:setMarginLeft(finalMarginLeft)
                widget:destroy()
            end

            if supportGeneralWindow ~= nil then
                local effectWidget = g_ui.createWidget("UICreature", supportGeneralWindow.panel.autoTraining.effects)
                effectWidget:setPhantom(true)
                local outfit2 = {
                    type = 0,
                    auxType = 10,
                    addons = 0,
                    head = 0,
                    body = 0,
                    legs = 0,
                    feet = 0,
                    mount = 0,
                    wings = 0,
                    aura = 0,
                    shader = '',
                    healthBar = 0,
                    manaBar = 0,
                    category = ThingCategoryEffect
                }

                effectWidget:setPhantom(true)
                effectWidget:setAnimate(true)
                effectWidget:setMarginBottom(16)
                effectWidget:setWidth(64)
                effectWidget:setHeight(64)
                effectWidget:setOutfit(outfit2)
                effectWidget:addAnchor(AnchorLeft, 'parent', AnchorLeft)
                effectWidget:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
                effectWidget:setMarginLeft(finalMarginLeft - 18)

                scheduleEvent(function()
                    if not(effectWidget:isDestroyed()) then
                        effectWidget:destroy()
                    end
                end, 600)
            end

            return
        end

        local progress = elapsed / duration
        local currentMarginLeft = initialMarginLeft + totalDelta * progress

        widget:setMarginLeft(currentMarginLeft)

        widget.missileMoveEvent = scheduleEvent(animationCycle, frameInterval)
    end

    animationCycle()
end

function support_generalModule.reloadEnabledShortcut(_, widget)
    
end
