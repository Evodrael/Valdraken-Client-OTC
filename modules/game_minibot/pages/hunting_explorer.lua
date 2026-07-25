hunting_explorerModule = {}

local huntingExplorer = nil

function hunting_explorerModule.init(widget)
    huntingExplorer = widget

    hunting_explorerModule.loadSettings()
end

function hunting_explorerModule.terminate()
    huntingExplorer = nil

end

function hunting_explorerModule.reloadInternalModule()
    local settings = modules.game_minibot.getPressetSettings()
    local sList = settings['explorer'] or {}

    local sShortcut = settings['shortcuts'] or {}
    local enabled = sShortcut['huntingExplorer_enabled'] or false

    -- O Explorer opera apenas em "Correr e parar" (o modo Lure foi removido).
    -- Com "stop" desligado, findCreatures = 0 e o personagem apenas vagueia pela area.
    local findCreatures = 0
    local resumeCreatures = 0

    if sList['stop'] then
        findCreatures = tonumber(sList['stop_until'] or '') or 0
        resumeCreatures = tonumber(sList['stop_resume'] or '') or 0
    end

    -- The C++ explorer reads its configuration from the module entry:
    --   hits = stop-when-X-creatures, max = resume-when-X-creatures, use = lure mode.
    --   O modo Lure nao e mais oferecido, entao use permanece sempre false.
    g_minibot.resetModule(21) -- Hunting Explorer Module type
    g_minibot.addModule(21, {
        enabled = true,
        use = false,
        hits = findCreatures,
        max = resumeCreatures,
        min = 0,
        item = 0,
        spell = "",
        spellGroup = {},
        spellId = {},
        area = "",
        target = "",
        health = 0,
        mana = 0,
        harmony = 0,
        itemGroup = {},
    })
    g_minibot.setModuleToggle(21, enabled)
    g_minibot.setExplorerWalker(enabled) -- bool (was a table before, which marshalled to true)
end

function hunting_explorerModule.reloadLanguage(language)
    if language == 'ptbr' then
        huntingExplorer.panel.title:setText('Explorador Automatico')
        huntingExplorer.panel.stopFightTab.stop:setText('Correr e parar')
        huntingExplorer.panel.stopFightTab.stopHelp:setTooltip('Ativando a opcao de Correr e parar, o personagem continuara andando na velocidade normal ate encontrar a quantidade de monstros configurada abaixo. Nao configurar valores abaixo fara com que o personagem ande sem rumo e objetivo pela area.')
        huntingExplorer.panel.stopFightTab.untilLabel:setText('Parar se encontrar X monstros:')
        huntingExplorer.panel.stopFightTab.untilHelp:setTooltip('Configurar quantidade de monstros minimo para o Assistente parar o movimento e atacar os monstros. Valor 0 desativa parada, fazendo o personagem correr pela area sem objetivo.')
        huntingExplorer.panel.stopFightTab.resumeLabel:setText('Apos parada, andar se X monstros:')
        huntingExplorer.panel.stopFightTab.resumeHelp:setTooltip('Apos ter parado pela configuracao de parada, pode configurar quantidade de monstros maxima para o Assistente continuar atacando os monstros. Valor 0 faz com que ele respeite o valor acima de parada.')

    elseif language == 'enus' then
        huntingExplorer.panel.title:setText('Auto Explorer')
        huntingExplorer.panel.stopFightTab.stop:setText('Run and stop')
        huntingExplorer.panel.stopFightTab.stopHelp:setTooltip('By enabling the Run and Stop option, the character will continue walking at normal speed until encountering the number of monsters set below. Not setting the values below will cause the character to wander aimlessly through the area.')
        huntingExplorer.panel.stopFightTab.untilLabel:setText('Stop if find X monsters:')
        huntingExplorer.panel.stopFightTab.untilHelp:setTooltip('Set the minimum number of monsters for the Assistant to stop movement and attack the monsters. A value of 0 disables stopping, causing the character to run aimlessly through the area.')
        huntingExplorer.panel.stopFightTab.resumeLabel:setText('After stop, walk if X monsters:')
        huntingExplorer.panel.stopFightTab.resumeHelp:setTooltip('After stopping using the stop setting, you can set the maximum number of monsters for the Assistant to continue attacking. A value of 0 causes it to respect the above stop value.')

    end
end

function hunting_explorerModule.onWalkFailed(code)
    if huntingExplorer ~= nil then
        huntingExplorer.panel.enabled:setChecked(false)
    else
        modules.game_minibot.onMiniBotGameWindowChangeFromPanel('huntingExplorer_gamewindow', false)
    end
end

function hunting_explorerModule.loadSettings()
    local settings = modules.game_minibot.getPressetSettings()
    local sList = settings['explorer'] or {}
    local sShortcut = settings['shortcuts'] or {}

    huntingExplorer.panel.enabled.ignoreCallback = true
    huntingExplorer.panel.enabled:setChecked(sShortcut['huntingExplorer_enabled'] or false)
    huntingExplorer.panel.enabled.ignoreCallback = nil

    huntingExplorer.panel.enabled.onCheckChange = function()
        if huntingExplorer.panel.enabled.ignoreCallback then
            return
        end

        if huntingExplorer.panel.enabled:isChecked() then
            modules.game_minibot.hunting_recorderModule.onWalkFailed(0)
        end

        local panel = modules.game_interface.getMiniBotPanel()
        if panel ~= nil then
            local child = panel:getChildById('huntingExplorer_gamewindow')
            if child ~= nil then
                child.ignoreCallback = true
                child:setChecked(huntingExplorer.panel.enabled:isChecked())
                child.ignoreCallback = nil
            end
        end

        local settings2 = modules.game_minibot.getPressetSettings()
        if settings2['shortcuts'] == nil then
            settings2['shortcuts'] = {}
        end

        settings2['shortcuts']['huntingExplorer_enabled'] = huntingExplorer.panel.enabled:isChecked()
        modules.game_minibot.setPressetSettings(settings2)
        g_minibot.setModuleToggle(21, huntingExplorer.panel.enabled:isChecked()) -- Hunting Explorer
    end

    huntingExplorer.panel.stopFightTab.stop.ignoreCallback = true
    huntingExplorer.panel.stopFightTab.untilBox.ignoreCallback = true
    huntingExplorer.panel.stopFightTab.resume.ignoreCallback = true

    huntingExplorer.panel.stopFightTab.stop:setChecked(sList['stop'] or false)
    huntingExplorer.panel.stopFightTab.untilBox:setText(sList['stop_until'] or '')
    huntingExplorer.panel.stopFightTab.resume:setText(sList['stop_resume'] or '')

    huntingExplorer.panel.stopFightTab.stop.ignoreCallback = nil
    huntingExplorer.panel.stopFightTab.untilBox.ignoreCallback = nil
    huntingExplorer.panel.stopFightTab.resume.ignoreCallback = nil

    -- "Correr e parar" ligado habilita os campos de parar/retomar; desligado o
    -- personagem apenas vagueia pela area sem parar para lutar.
    local stopEnabled = huntingExplorer.panel.stopFightTab.stop:isChecked()
    huntingExplorer.panel.stopFightTab.untilLabel:setEnabled(stopEnabled)
    huntingExplorer.panel.stopFightTab.untilBox:setEnabled(stopEnabled)
    huntingExplorer.panel.stopFightTab.resumeLabel:setEnabled(stopEnabled)
    huntingExplorer.panel.stopFightTab.resume:setEnabled(stopEnabled)
end

function hunting_explorerModule.saveSettings()
    local settings = modules.game_minibot.getPressetSettings()
    local sList = settings['explorer'] or {}
    if settings['shortcuts'] == nil then
        settings['shortcuts'] = {}
    end

    local values = {}

    settings['shortcuts']['huntingExplorer_enabled'] = huntingExplorer.panel.enabled:isChecked()

    values['stop'] = huntingExplorer.panel.stopFightTab.stop:isChecked()
    values['stop_until'] = tostring(huntingExplorer.panel.stopFightTab.untilBox:getText())
    values['stop_resume'] = tostring(huntingExplorer.panel.stopFightTab.resume:getText())

    settings['explorer'] = values
    modules.game_minibot.setPressetSettings(settings)
    hunting_explorerModule.reloadInternalModule()
end

function hunting_explorerModule.reloadEnabledShortcut(_, widget)
    if widget:getId() ~= 'huntingExplorer_gamewindow' then
        return
    end

    huntingExplorer.panel.enabled.ignoreCallback = true
    huntingExplorer.panel.enabled:setChecked(widget:isChecked())
    huntingExplorer.panel.enabled.ignoreCallback = nil
end

function hunting_explorerModule.onTextOptionChange(widget)
    if widget.ignoreCallback then
        return
    end

    hunting_explorerModule.saveSettings()
end

function hunting_explorerModule.onStopChange(widget)
    if widget.ignoreCallback then
        return
    end

    -- Unico modo do Explorer: "Correr e parar". Ligado habilita os campos de
    -- parar/retomar; desligado o personagem apenas vagueia pela area.
    local stopEnabled = widget:isChecked()
    huntingExplorer.panel.stopFightTab.untilLabel:setEnabled(stopEnabled)
    huntingExplorer.panel.stopFightTab.untilBox:setEnabled(stopEnabled)
    huntingExplorer.panel.stopFightTab.resumeLabel:setEnabled(stopEnabled)
    huntingExplorer.panel.stopFightTab.resume:setEnabled(stopEnabled)

    hunting_explorerModule.saveSettings()
end
