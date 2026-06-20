combat_pvpModule = {}

local combatPvpWindow = nil

local spellsAppend = {
    { id = 6, words = "utani hur", name = "Haste" },
    { id = 39, words = "utani gran hur", name = "Strong Haste" },
    { id = 134, words = "utamo tempo san", name = "Swift Foot" },
    { id = 131, words = "utani tempo hur", name = "Charge" },
    { id = 1, words = "exura", name = "Light Healing" },
    { id = 2, words = "exura gran", name = "Intense Healing" },
    { id = 3, words = "exura vita", name = "Ultimate Healing" },
    { id = 36, words = "exura gran san", name = "Salvation" },
    { id = 82, words = "exura gran mas res", name = "Mass Healing" },
    { id = 123, words = "exura ico", name = "Wound Cleansing" },
    { id = 125, words = "exura san", name = "Divine Healing" },
    { id = 158, words = "exura gran ico", name = "Intense Wound Cleansing" },
    { id = 170, words = "exura infir ico", name = "Bruise Bane" },
    { id = 174, words = "exura infir", name = "Magic Patch" },
    { id = 239, words = "exura med ico", name = "Fair Wound Cleansing" },
    { id = 241, words = "exura max vita", name = "Restoration" },
    { id = 296, words = "exura mas nia", name = "Mass Spirit Mend" },
    { id = 273, words = "exura gran tio", name = "Spirit Mend" },
}

function combat_pvpModule.init(widget)
    combatPvpWindow = widget

    combat_pvpModule.loadSettings()

end

function combat_pvpModule.terminate()
    combatPvpWindow = nil
end

function combat_pvpModule.saveSettings()
    local settings = modules.game_minibot.getPressetSettings()
    local sList = settings['combat_pvp'] or {}
    if settings['shortcuts'] == nil then
        settings['shortcuts'] = {}
    end

    -- Tank Mode
    settings['shortcuts']['tankMode_enabled'] = combatPvpWindow.panel.tankMode.check:isChecked()

    -- Auto-remove paralyze
    local apList = {}
    apList['spells'] = {}
    apList['enabled'] = combatPvpWindow.panel.antiParalyze.check:isChecked()
    for i, c in ipairs(combatPvpWindow.panel.antiParalyze.listPanel.list:getChildren())  do
        if c.spellInfoId ~= nil then
            table.insert(apList['spells'], { id = c.spellInfoId, priority = i })
        end
    end
    sList['antiparalyze_settings'] = apList

    settings['combat_pvp'] = sList
    modules.game_minibot.setPressetSettings(settings)
    combat_pvpModule.reloadInternalModule()
end

function combat_pvpModule.closeCatcher()
    local windowCatcher = modules.game_minibot.getDropDownCatcher()
    if windowCatcher ~= nil then
        windowCatcher:hide()
        windowCatcher.onLeftClick = nil
    end

    combatPvpWindow.dropDownCatcher:hide()
    combatPvpWindow.dropDownMenuScrollBar:hide()
    combatPvpWindow.dropDownMenu:hide()
end

function combat_pvpModule.reloadLanguage(language)
    if language == 'ptbr' then
        combatPvpWindow.panel.tankMode.check:setText('Modo Tanque (SSA e Might Ring)')
        combatPvpWindow.panel.tankMode.help:setTooltip('Ao ativar o Modo Tanque, o Assistente equipara automaticamente o Stone Skin Amlet e o Might Ring, se possivel.')
        combatPvpWindow.panel.antiParalyze.check:setText('Auto-remover Paralyze')
        combatPvpWindow.panel.antiParalyze.help:setTooltip('A remocao automatica de Paralyze usara uma das spells selecionados assim que voce for paralisado. A prioridade respeita a ordem da esquerda para a direita.')

    elseif language == 'enus' then
        combatPvpWindow.panel.tankMode.check:setText('Tank mode (SSA and Might Ring)')
        combatPvpWindow.panel.tankMode.help:setTooltip('Enabling Tank Mode the Assistant will automatically equip Stone Skin Amulet and Might Ring if possible.')
        combatPvpWindow.panel.antiParalyze.check:setText('Auto-remove paralyze')
        combatPvpWindow.panel.antiParalyze.help:setTooltip('Auto-remove Paralyze will cast one of the selected spells as soon as you are paralyzed. The priority respect the order from Left to Right.')

    end
end

function combat_pvpModule.onMousePressPvpItemSpell(widget, button, mousePos)
    local hasExtra = false
    for _, c in ipairs(combatPvpWindow.panel.antiParalyze.listPanel.list:getChildren()) do
        if c.leftArrow ~= nil then
            c:setBorderWidth(0)
            c.leftArrow:setWidth(1)
            c.leftArrow:hide()
            c.rightArrow:setWidth(1)
            c.rightArrow:hide()
            c:setWidth(34)
        else
            hasExtra = true
        end
    end

    local extra = 0
    widget:setBorderWidth(1)
    if widget:getParent():getChildIndex(widget) > 1 then
        widget.leftArrow:setWidth(10)
        widget.leftArrow:show()
        extra = extra + 10

        widget.leftArrow.onLeftClick = function()
            widget:getParent():moveChildToIndex(widget, widget:getParent():getChildIndex(widget) - 1)
            combat_pvpModule.onMousePressPvpItemSpell(widget, button, mousePos)
            combat_pvpModule.saveSettings()
        end
    else
        widget.leftArrow.onLeftClick = nil
    end

    if widget:getParent():getChildIndex(widget) < (hasExtra and (combatPvpWindow.panel.antiParalyze.listPanel.list:getChildCount() - 1) or 5) then
        widget.rightArrow:setWidth(10)
        widget.rightArrow:show()
        extra = extra + 10

        widget.rightArrow.onLeftClick = function()
            widget:getParent():moveChildToIndex(widget, widget:getParent():getChildIndex(widget) + 1)
            combat_pvpModule.onMousePressPvpItemSpell(widget, button, mousePos)
            combat_pvpModule.saveSettings()
        end
    else
        widget.rightArrow.onLeftClick = nil
    end

    widget:setWidth(34 + extra)

    if button == MouseRightButton then
        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)

        menu:addOption('Remove', function()
            local addNewButton = 0
            for _, c in ipairs(widget:getParent():getChildren()) do
                if c.spellInfoId ~= nil then
                    addNewButton = addNewButton + 1
                end
            end

            widget:destroy()
            if addNewButton == 5 then
                local newWidget = g_ui.createWidget('MiniBotCombatPvpitemIgnoreDropDownEntry', combatPvpWindow.panel.antiParalyze.listPanel.list)
                newWidget:setId('antiParalyzeNewSpell')
                newWidget.onLeftClick = function()
                    combat_pvpModule.openCatcher()
                end
            end
            combat_pvpModule.saveSettings()
        end)

        menu:display(mousePos)
    end

    return true
end

function combat_pvpModule.openCatcher()
    combatPvpWindow.dropDownCatcher:show()
    combatPvpWindow.dropDownCatcher.onLeftClick = combat_pvpModule.closeCatcher

    local windowCatcher = modules.game_minibot.getDropDownCatcher()
    if windowCatcher ~= nil then
        windowCatcher:show()
        windowCatcher.onLeftClick = combat_pvpModule.closeCatcher
    end

    combatPvpWindow.dropDownMenu:show()
    combatPvpWindow.dropDownMenuScrollBar:show()
    combatPvpWindow.dropDownMenu:destroyChildren()
    combatPvpWindow.dropDownMenu:setMarginTop(75)

    local function isOnList(id)
        for _, c in ipairs(combatPvpWindow.panel.antiParalyze.listPanel.list:getChildren()) do
            if c.spellInfoId ~= nil and c.spellInfoId == id then
                return true
            end
        end

        return false
    end

    for _, spell in ipairs(spellsAppend) do
        local foundSpell = g_spells.getSpellInfoById(spell.id)
        if spellsAppend ~= nil and not(isOnList(spell.id)) then
            local spellWidget = g_ui.createWidget('MiniBotCombatPvpSpellDropDownEntry', combatPvpWindow.dropDownMenu)
            spellWidget:constructEnviorementVariables()

            if not(modules.game_actionbar.canSpellCast(foundSpell)) then
                spellWidget.block:show()
                spellWidget.icon:setOpacity(0.3)
            end

            spellWidget.icon:setImageClip(g_spells.getSpellRegularImageClipById(foundSpell.id))
            spellWidget:setTooltip(foundSpell.name .. '\n\'' .. foundSpell.words .. '\'')

            spellWidget.onLeftClick = function()
                local addButton = combatPvpWindow.panel.antiParalyze.listPanel.list:getChildById('antiParalyzeNewSpell')
                combat_pvpModule.closeCatcher()

                local widget = g_ui.createWidget('MiniBotCombatPvpitemSpellDropDownEntry', combatPvpWindow.panel.antiParalyze.listPanel.list)
                widget:constructEnviorementVariables()
                widget.spell:setImageClip(g_spells.getSpellRegularImageClipById(foundSpell.id))
                widget.spellInfoId = foundSpell.id
                widget:setTooltip(foundSpell.name .. '\n\'' .. foundSpell.words .. '\'')
                widget.onMousePress = function(w, b, p)
                    return combat_pvpModule.onMousePressPvpItemSpell(w, p, b)
                end

                if addButton ~= nil then
                    if combatPvpWindow.panel.antiParalyze.listPanel.list:getChildCount() > 5 then
                        addButton:destroy()
                    else
                        addButton:getParent():moveChildToIndex(addButton, addButton:getParent():getChildCount())
                    end
                end

                combat_pvpModule.saveSettings()
            end
        end
    end
end

function combat_pvpModule.loadSettings()
    local settings = modules.game_minibot.getPressetSettings()
    local sList = settings['combat_pvp'] or {}
    local sShortcut = settings['shortcuts'] or {}

    -- Tank Mode
    combatPvpWindow.panel.tankMode.check.ignoreCallback = true
    combatPvpWindow.panel.tankMode.check:setChecked(sShortcut['tankMode_enabled'] or false)
    combatPvpWindow.panel.tankMode.check.ignoreCallback = nil

    -- Anti paralyze
    local apList = sList['antiparalyze_settings'] or {}
    local apSpells = apList['spells'] or {}
    combatPvpWindow.panel.antiParalyze.check.ignoreCallback = true
    combatPvpWindow.panel.antiParalyze.check:setChecked(apList['enabled'])
    combatPvpWindow.panel.antiParalyze.check.ignoreCallback = nil
    combatPvpWindow.panel.antiParalyze.listPanel.list:destroyChildren()

    if not(apList['enabled']) then
        combatPvpWindow.panel.antiParalyze.listPanel:setOpacity(0.5)
        combatPvpWindow.panel.antiParalyze.listPanel.block:setVisible(true)
    else
        combatPvpWindow.panel.antiParalyze.listPanel:setOpacity(1)
        combatPvpWindow.panel.antiParalyze.listPanel.block:setVisible(false)
    end

    local size = 0
    local tmpList = {}
    for _, block in pairs(apSpells) do
        tmpList[block.priority] = block.id
    end
    for _, spellId in ipairs(tmpList) do
        local spell = g_spells.getSpellInfoById(spellId)
        if spell ~= nil and size < 5 then
            size = size + 1
            local widget = g_ui.createWidget('MiniBotCombatPvpitemSpellDropDownEntry', combatPvpWindow.panel.antiParalyze.listPanel.list)
            widget:constructEnviorementVariables()
            widget.spell:setImageClip(g_spells.getSpellRegularImageClipById(spell.id))
            widget.spellInfoId = spell.id
            widget:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')
            widget.onMousePress = function(w, b, p)
                return combat_pvpModule.onMousePressPvpItemSpell(w, p, b)
            end
        end
    end

    if size < 5 then
        local widget = g_ui.createWidget('MiniBotCombatPvpitemIgnoreDropDownEntry', combatPvpWindow.panel.antiParalyze.listPanel.list)
        widget:setId('antiParalyzeNewSpell')
        widget.onLeftClick = function()
            combat_pvpModule.openCatcher()
        end
    end
end

function combat_pvpModule.onTankModeChange(widget)
    if widget.ignoreCallback then
        return
    end

    local panel = modules.game_interface.getMiniBotPanel()
    if panel ~= nil then
        local child = panel:getChildById('tankMode_gamewindow')
        if child ~= nil then
            child.ignoreCallback = true
            child:setChecked(widget:isChecked())
            child.ignoreCallback = nil
        end
    end

    combat_pvpModule.saveSettings()
    combat_pvpModule.reloadInternalModule()
end

function combat_pvpModule.onAntiParalyzeChange(widget)
    if widget.ignoreCallback then
        return
    end

    if not(widget:isChecked()) then
        combatPvpWindow.panel.antiParalyze.listPanel:setOpacity(0.5)
        combatPvpWindow.panel.antiParalyze.listPanel.block:setVisible(true)
    else
        combatPvpWindow.panel.antiParalyze.listPanel:setOpacity(1)
        combatPvpWindow.panel.antiParalyze.listPanel.block:setVisible(false)
    end

    combat_pvpModule.saveSettings()
    combat_pvpModule.reloadInternalModule()
end

function combat_pvpModule.reloadInternalModule()
    local settings = modules.game_minibot.getPressetSettings()

    local sList = settings['combat_pvp'] or {}
    local sShortcut = settings['shortcuts'] or {}

    -- Tank Mode: auto-equip Stone Skin Amulet (3081) + Might Ring (3048).
    g_minibot.resetModule(16) -- Tank Mode Module type
    if sShortcut['tankMode_enabled'] then
        local function tankItem(itemId)
            return {
                item = itemId,
                enabled = true,
                use = false,
                ignorePz = false,
                min = 0,
                max = 0,
                hits = 0,
                spell = "",
                spellGroup = {},
                spellId = {},
                area = "",
                target = "",
                health = 0,
                mana = 0,
                harmony = 0,
                itemGroup = {},
            }
        end

        g_minibot.addModule(16, tankItem(3081)) -- Stone Skin Amulet
        g_minibot.addModule(16, tankItem(3048)) -- Might Ring

        g_minibot.setModuleToggle(16, true) -- Tank Mode Module type
    else
        g_minibot.setModuleToggle(16, false) -- Tank Mode Module type
    end

    -- Anti Paralyze
    local apList = sList['antiparalyze_settings'] or {}
    local apSpells = apList['spells'] or {}
    g_minibot.resetModule(17) -- Anti Paralyze Module type
    g_minibot.setModuleToggle(17, apList['enabled'] or false) -- Anti Paralyze Module type
    local size = 0
    local tmpList = {}
    for _, block in pairs(apSpells) do
        tmpList[block.priority] = block.id
    end
    for _, spellId in ipairs(tmpList) do
        local spell = g_spells.getSpellInfoById(spellId)
        if spell ~= nil and size < 5 then
            size = size + 1

            local internal = {
                spell = spell.words,
                spellGroup = {},
                spellId = {},
                reqmana = spell.mana,

                item = 0,
                hits = 0,
                use = false,
                min = 0,
                max = 0,
                enabled = true,
                ignorePz = false,
                area = "",
                target = "",
                health = 0,
                mana = 0,
                harmony = 0,
                itemGroup = {},
            }

            table.insert(internal.spellId, spell.id)
            for _, group in ipairs(spell.groups) do
                table.insert(internal.spellGroup, group)
            end

            g_minibot.addModule(17, internal)
        end
    end
end

function combat_pvpModule.reloadEnabledShortcut(_, widget)
    if widget:getId() == 'tankMode_gamewindow' then
        -- Tank Mode
        combatPvpWindow.panel.tankMode.check.ignoreCallback = true
        combatPvpWindow.panel.tankMode.check:setChecked(widget:isChecked())
        combatPvpWindow.panel.tankMode.check.ignoreCallback = nil
    end
end
