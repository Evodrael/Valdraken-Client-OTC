combat_attackModule = {}

local combatAttackWindow = nil

local fortifySpells = {
    133, -- Blood Rage
    135, -- Sharpshooter
    126, -- Train Party
    129, -- Enchant Party
}

function combat_attackModule.init(widget)
    combatAttackWindow = widget

    combat_attackModule.loadSettings()

    combatAttackWindow.settings.ammoRefill.frameBackground.onLeftClick = function()
        combatAttackWindow.dropDownMenu:setMarginLeft(48)
        combatAttackWindow.dropDownMenu:setMarginTop(170)
        combat_attackModule.openItemCatcher(combatAttackWindow.settings.ammoRefill)
    end
end

function combat_attackModule.terminate()
    combat_attackModule.closeCatcher()

    combatAttackWindow = nil
end

function combat_attackModule.reloadLanguage(language)
    if language == 'ptbr' then
        combatAttackWindow.settings.title:setText('Opcoes de Ataque')
        combatAttackWindow.settings.attackPanel.meleeAttack:setText('Atacar apenas corpo a corpo.')
        combatAttackWindow.settings.attackPanel.meleeAttackHelp:setTooltip('Ao ativar esta caixa, o sistema so atacara quando uma criatura estiver no alcance corpo a corpo. Caso contrario, ele atacara qualquer um que esteja no seu campo de visao.')
        combatAttackWindow.settings.attackPanel.autoAttack:setText('Ataque automatico em criaturas proximas')
        combatAttackWindow.settings.attackPanel.autoAttackHelp:setTooltip('Ao ativar esta caixa, o sistema detectara automaticamente o melhor alvo com base na opcao selecionada abaixo.')
        combatAttackWindow.settings.attackPanel.attackClosestHelp:setTooltip('Encontrara o melhor alvo pela posicao mais proxima. Se houver duas ou mais criaturas na mesma distancia, ele identificara a melhor criatura pela vida mais baixa.')
        combatAttackWindow.settings.attackPanel.attackLowestHelp:setTooltip('Encontrara o melhor alvo pela menor porcentagem de vida.')
        combatAttackWindow.settings.attackPanel.attackHighestHelp:setTooltip('Encontrara o melhor alvo pela maior porcentagem de vida.')
        combatAttackWindow.settings.attackPanel.attackSmartArrowHelp:setTooltip('Encontrara o melhor alvo pela melhor area de impacto da flecha Diamond Arrow possivel, priorizando a menor porcentagem de vida possivel.')
        combatAttackWindow.settings.attackPanel.closest:setText('Priorizar a posicao mais proxima')
        combatAttackWindow.settings.attackPanel.health:setText('Priorize a vida mais baixa')
        combatAttackWindow.settings.attackPanel.highHealth:setText('Priorize a vida mais alta')
        combatAttackWindow.settings.attackPanel.smartArrow:setText('Diamond arrow inteligente')

        combatAttackWindow.settings.ammoRefill.check:setText('Recarga de municao')
        combatAttackWindow.settings.ammoRefill.tooltipLabel:setTooltip('Se uma municao selecionada for encontrada em seu inventario, o sistema tentara move-la periodicamente de forma automatica.')

    elseif language == 'enus' then
        combatAttackWindow.settings.title:setText('Attack options')
        combatAttackWindow.settings.attackPanel.meleeAttack:setText('Atacar only melee.')
        combatAttackWindow.settings.attackPanel.meleeAttackHelp:setTooltip('Activating this box, the system will only attack when a creature is on melee range. Otherwise, it will attack anyone in you field of vision.')
        combatAttackWindow.settings.attackPanel.autoAttack:setText('Auto Attack nearby creatures')
        combatAttackWindow.settings.attackPanel.autoAttackHelp:setTooltip('Activating this box, the system will auto detect the best target based on your selected option below.')
        combatAttackWindow.settings.attackPanel.attackClosestHelp:setTooltip('Will find the best target by the closest position. If there are two or more creatures on the same distance, it will identify the best creature by the lowest health.')
        combatAttackWindow.settings.attackPanel.attackLowestHelp:setTooltip('Will find the best target by the lowest health percentage.')
        combatAttackWindow.settings.attackPanel.attackHighestHelp:setTooltip('Will find the best target by the highest health percentage.')
        combatAttackWindow.settings.attackPanel.attackSmartArrowHelp:setTooltip('Will find the best target by the best Diamond arrow area impact possible, prioritizing lowest health percentage if possible.')
        combatAttackWindow.settings.attackPanel.closest:setText('Prioritize closest position')
        combatAttackWindow.settings.attackPanel.health:setText('Prioritize lowest health')
        combatAttackWindow.settings.attackPanel.highHealth:setText('Prioritize highest health')
        combatAttackWindow.settings.attackPanel.smartArrow:setText('Smart diamond arrow')

        combatAttackWindow.settings.ammoRefill.check:setText('Ammo refill')
        combatAttackWindow.settings.ammoRefill.tooltipLabel:setTooltip('If a selected ammo is found on your inventory, the system automatically try to move periodically.')

    end
end

function combat_attackModule.reloadInternalModule()
    local player = g_game.getLocalPlayer()
    if player == nil then
        g_minibot.setAutoAttack(0)
        return
    end

    local settings = modules.game_minibot.getPressetSettings()
    local mSettings = settings['combat_attack'] or {}
    local sSettings = settings['shortcuts'] or {}

    local attackMelee = mSettings['attackMelee_enabled']
    local autoAttack = sSettings['autoAttack_enabled']
    local health = mSettings['autoAttack_health']
    local highHealth = mSettings['autoAttack_highhealth']
    local closest = mSettings['autoAttack_closest']
    local smartArrow = mSettings['autoAttack_smartArrow']

    local type = 0 -- None
    if autoAttack then
        if smartArrow then
            type = 200
        elseif health then
            type = 2 -- Health
        elseif highHealth then
            type = 3 -- High Health
        else
            type = 1 -- Distance
        end

        if attackMelee then
            type = type + 100
        end
    end

    g_minibot.setAutoAttack(type)

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

    local attackMelee = mSettings['attackMelee_enabled']
    local autoAttack = sSettings['autoAttack_enabled']
    local health = mSettings['autoAttack_health']
    local highHealth = mSettings['autoAttack_highhealth']
    local closest = mSettings['autoAttack_closest']
    local smartArrow = mSettings['autoAttack_smartArrow']

    if not(health) and not(closest) and not(smartArrow) and not(highHealth) then
        closest = true
    end

    combatAttackWindow.settings.attackPanel.health.ignoreCallback = true
    combatAttackWindow.settings.attackPanel.highHealth.ignoreCallback = true
    combatAttackWindow.settings.attackPanel.closest.ignoreCallback = true
    combatAttackWindow.settings.attackPanel.smartArrow.ignoreCallback = true
    combatAttackWindow.settings.attackPanel.autoAttack.ignoreCallback = true
    combatAttackWindow.settings.attackPanel.meleeAttack.ignoreCallback = true
    combatAttackWindow.settings.attackPanel.health:setChecked(health)
    combatAttackWindow.settings.attackPanel.highHealth:setChecked(highHealth)
    combatAttackWindow.settings.attackPanel.closest:setChecked(closest)
    combatAttackWindow.settings.attackPanel.smartArrow:setChecked(smartArrow)
    combatAttackWindow.settings.attackPanel.autoAttack:setChecked(autoAttack)
    combatAttackWindow.settings.attackPanel.meleeAttack:setChecked(attackMelee)
    combat_attackModule.onAutoAttackCheckChange(combatAttackWindow.settings.attackPanel.autoAttack)
    combatAttackWindow.settings.attackPanel.health.ignoreCallback = nil
    combatAttackWindow.settings.attackPanel.highHealth.ignoreCallback = nil
    combatAttackWindow.settings.attackPanel.closest.ignoreCallback = nil
    combatAttackWindow.settings.attackPanel.smartArrow.ignoreCallback = nil
    combatAttackWindow.settings.attackPanel.autoAttack.ignoreCallback = nil
    combatAttackWindow.settings.attackPanel.meleeAttack.ignoreCallback = nil

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

    settings['shortcuts']['autoAttack_enabled'] = combatAttackWindow.settings.attackPanel.autoAttack:isChecked()
    settings['combat_attack']['attackMelee_enabled'] = combatAttackWindow.settings.attackPanel.meleeAttack:isChecked()
    settings['combat_attack']['autoAttack_health'] = combatAttackWindow.settings.attackPanel.health:isChecked()
    settings['combat_attack']['autoAttack_highhealth'] = combatAttackWindow.settings.attackPanel.highHealth:isChecked()
    settings['combat_attack']['autoAttack_closest'] = combatAttackWindow.settings.attackPanel.closest:isChecked()
    settings['combat_attack']['autoAttack_smartArrow'] = combatAttackWindow.settings.attackPanel.smartArrow:isChecked()

    -- Ammo Refill
    local ammoRefillSettings = {}
    ammoRefillSettings['item'] = combatAttackWindow.settings.ammoRefill.item:getItemId()
    ammoRefillSettings['enabled'] = combatAttackWindow.settings.ammoRefill.check:isChecked()
    settings['combat_attack']['ammo_refill'] = ammoRefillSettings

    modules.game_minibot.setPressetSettings(settings)
    combat_attackModule.reloadInternalModule()
end

function combat_attackModule.onAutoAttackCheckChange(widget)
    if widget:isChecked() then
        combatAttackWindow.settings.attackPanel.closest:setEnabled(true)
        combatAttackWindow.settings.attackPanel.attackClosestHelp:setEnabled(true)
        combatAttackWindow.settings.attackPanel.health:setEnabled(true)
        combatAttackWindow.settings.attackPanel.attackLowestHelp:setEnabled(true)
        combatAttackWindow.settings.attackPanel.highHealth:setEnabled(true)
        combatAttackWindow.settings.attackPanel.attackHighestHelp:setEnabled(true)
        combatAttackWindow.settings.attackPanel.smartArrow:setEnabled(true)
        combatAttackWindow.settings.attackPanel.attackSmartArrowHelp:setEnabled(true)
    else
        combatAttackWindow.settings.attackPanel.closest:setEnabled(false)
        combatAttackWindow.settings.attackPanel.attackClosestHelp:setEnabled(false)
        combatAttackWindow.settings.attackPanel.health:setEnabled(false)
        combatAttackWindow.settings.attackPanel.attackLowestHelp:setEnabled(false)
        combatAttackWindow.settings.attackPanel.highHealth:setEnabled(false)
        combatAttackWindow.settings.attackPanel.attackHighestHelp:setEnabled(false)
        combatAttackWindow.settings.attackPanel.smartArrow:setEnabled(false)
        combatAttackWindow.settings.attackPanel.attackSmartArrowHelp:setEnabled(false)
    end

    if widget.ignoreCallback then
        modules.game_console.focusChat()
        return
    end

    combat_attackModule.saveSettings()

    local panel = modules.game_interface.getMiniBotPanel()
    if panel ~= nil then
        local child = panel:getChildById('combat_gamewindow')
        if child ~= nil then
            child.ignoreCallback = true
            child:setChecked(widget:isChecked())
            child.ignoreCallback = nil
        end
    end

    combat_attackModule.reloadInternalModule()
    modules.game_console.focusChat()
end

function combat_attackModule.onAttackOptionChange(widget)
    if widget.ignoreCallback then
        return
    end

    if widget:getId() ~= 'meleeAttack' then
        if not(widget:isChecked()) then
            widget.ignoreCallback = true
            widget:setChecked(true)
            widget.ignoreCallback = nil
            return
        end

        if widget:getId() == 'closest' then
            combatAttackWindow.settings.attackPanel.health.ignoreCallback = true
            combatAttackWindow.settings.attackPanel.health:setChecked(false)
            combatAttackWindow.settings.attackPanel.health.ignoreCallback = nil
            combatAttackWindow.settings.attackPanel.highHealth.ignoreCallback = true
            combatAttackWindow.settings.attackPanel.highHealth:setChecked(false)
            combatAttackWindow.settings.attackPanel.highHealth.ignoreCallback = nil
            combatAttackWindow.settings.attackPanel.smartArrow.ignoreCallback = true
            combatAttackWindow.settings.attackPanel.smartArrow:setChecked(false)
            combatAttackWindow.settings.attackPanel.smartArrow.ignoreCallback = nil
        elseif widget:getId() == 'health' then
            combatAttackWindow.settings.attackPanel.closest.ignoreCallback = true
            combatAttackWindow.settings.attackPanel.closest:setChecked(false)
            combatAttackWindow.settings.attackPanel.closest.ignoreCallback = nil
            combatAttackWindow.settings.attackPanel.highHealth.ignoreCallback = true
            combatAttackWindow.settings.attackPanel.highHealth:setChecked(false)
            combatAttackWindow.settings.attackPanel.highHealth.ignoreCallback = nil
            combatAttackWindow.settings.attackPanel.smartArrow.ignoreCallback = true
            combatAttackWindow.settings.attackPanel.smartArrow:setChecked(false)
            combatAttackWindow.settings.attackPanel.smartArrow.ignoreCallback = nil
        elseif widget:getId() == 'highHealth' then
            combatAttackWindow.settings.attackPanel.health.ignoreCallback = true
            combatAttackWindow.settings.attackPanel.health:setChecked(false)
            combatAttackWindow.settings.attackPanel.health.ignoreCallback = nil
            combatAttackWindow.settings.attackPanel.closest.ignoreCallback = true
            combatAttackWindow.settings.attackPanel.closest:setChecked(false)
            combatAttackWindow.settings.attackPanel.closest.ignoreCallback = nil
            combatAttackWindow.settings.attackPanel.smartArrow.ignoreCallback = true
            combatAttackWindow.settings.attackPanel.smartArrow:setChecked(false)
            combatAttackWindow.settings.attackPanel.smartArrow.ignoreCallback = nil
        elseif widget:getId() == 'smartArrow' then
            combatAttackWindow.settings.attackPanel.health.ignoreCallback = true
            combatAttackWindow.settings.attackPanel.health:setChecked(false)
            combatAttackWindow.settings.attackPanel.health.ignoreCallback = nil
            combatAttackWindow.settings.attackPanel.highHealth.ignoreCallback = true
            combatAttackWindow.settings.attackPanel.highHealth:setChecked(false)
            combatAttackWindow.settings.attackPanel.highHealth.ignoreCallback = nil
            combatAttackWindow.settings.attackPanel.closest.ignoreCallback = true
            combatAttackWindow.settings.attackPanel.closest:setChecked(false)
            combatAttackWindow.settings.attackPanel.closest.ignoreCallback = nil
        end

        if widget.ignoreCallback then
            return
        end
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