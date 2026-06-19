MagicalArchive = {
    dofile("magical_const"),
    summaryButtons = nil,
    combatMenu = nil,
    additionalMenu = nil,
    runeMenu = nil,

    spellList = {},
    learnedSpells = {},
    temporaryFilter = {},

    autoAimStorageData = AutoAimDefaultSpells,
    previewEvents = {}
}

MagicalArchive.__index = MagicalArchive

local panelStyles = {
    ["combatMenu"] = "spellDataPanel",
    ["additionalMenu"] = "additionalStats",
    ["runeMenu"] = "runeStats"
}

function MagicalArchive.stopPreview()
    if MagicalArchive.previewEvents then
        for _, event in ipairs(MagicalArchive.previewEvents) do
            removeEvent(event)
        end
    end
    MagicalArchive.previewEvents = {}
    
    if VisibleCyclopediaPanel then
        local animationPanel = VisibleCyclopediaPanel:recursiveGetChildById("animationPanel")
        if animationPanel then
            animationPanel:destroyChildren()
        end
    end
end

function MagicalArchive.playPreview(spellData)
    MagicalArchive.stopPreview()

    local animationPanel = VisibleCyclopediaPanel:recursiveGetChildById("animationPanel")
    if not animationPanel then
        return
    end

    animationPanel:destroyChildren()
    -- Ativa o clipping para o piso n�o vazar do box
    animationPanel:setClipping(true)

    local minX = 0
    local maxX = 0 
    local minY = 0
    local maxY = 0

    local function updateBounds(x, y)
        if x < minX then 
            minX = x 
        end
        if x > maxX then 
            maxX = x 
        end
        if y < minY then 
            minY = y 
        end
        if y > maxY then 
            maxY = y 
        end
    end

    if spellData.timestamps then
        for _, frame in ipairs(spellData.timestamps) do
            if frame.actions then
                for _, action in ipairs(frame.actions) do
                    if action.x then 
                        updateBounds(action.x, action.y or 0) 
                    end
                end
            end
        end
    end

    local dummyRelX = 5
    local dummyRelY = 0 
    local hasTarget = false

    if spellData.initActions then
        for _, action in ipairs(spellData.initActions) do
            if action.action == "target" then
                hasTarget = true
                dummyRelX = action.x or 5
                dummyRelY = action.y or 0
                updateBounds(dummyRelX, dummyRelY)
            end
        end
    end

    local rawPanelW = animationPanel:getWidth()
    local rawPanelH = animationPanel:getHeight()
    
    if rawPanelW == 0 then 
        rawPanelW = 469 
    end
    
    if rawPanelH == 0 then 
        rawPanelH = 199 
    end

    local padding = 4
    local panelW = rawPanelW - (padding * 2)
    local panelH = rawPanelH - (padding * 2)

    local tileSize = 32
    local creatureSize = 64
    local unitOffset = 16

    local centerRelX = (minX + maxX) / 2
    local centerRelY = (minY + maxY) / 2
    
    local contentCenterX = panelW / 2
    local contentCenterY = panelH / 2
    
    local function getMarginForRel(relX, relY)
        local diffX = relX - centerRelX
        local diffY = relY - centerRelY
        local ml = padding + contentCenterX + (diffX * tileSize) - (tileSize / 2)
        local mt = padding + contentCenterY + (diffY * tileSize) - (tileSize / 2)
        return ml, mt
    end

    local cols = math.ceil(panelW / tileSize) + 2
    local rows = math.ceil(panelH / tileSize) + 2
    
    local originML, originMT = getMarginForRel(0, 0)
    
    local shiftX = originML % tileSize
    local shiftY = originMT % tileSize
    
    if shiftX > 0 then 
        shiftX = shiftX - tileSize 
    end
    
    if shiftY > 0 then 
        shiftY = shiftY - tileSize 
    end

    for r = 0, rows do
        for c = 0, cols do
             local tile = g_ui.createWidget("UIWidget", animationPanel)
             tile:setSize({width = tileSize, height = tileSize})
             tile:addAnchor(AnchorTop, 'parent', AnchorTop)
             tile:addAnchor(AnchorLeft, 'parent', AnchorLeft)
             tile:setImageSource("/images/game/floor") 
             tile:setBorderWidth(0)
             
             local ml = shiftX + (c * tileSize) - tileSize
             local mt = shiftY + (r * tileSize) - tileSize
             tile:setMarginLeft(ml)
             tile:setMarginTop(mt)
        end
    end

    local function createAnchoredCreature(relX, relY, outfit, direction)
        local ml, mt = getMarginForRel(relX, relY)
        local creature = g_ui.createWidget("UICreature", animationPanel)
        
        if not creature then
            return nil
        end
        
        creature:setSize({width = creatureSize, height = creatureSize})
        creature:setClipping(false)
        
        if creature.setFixedCreatureSize then 
            creature:setFixedCreatureSize(true) 
        end
        
        creature:addAnchor(AnchorTop, 'parent', AnchorTop)
        creature:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        creature:setMarginLeft(ml - unitOffset)
        creature:setMarginTop(mt - unitOffset)
        creature:setOutfit(outfit)
        creature:setDirection(direction)

        return creature
    end    

    local firstMissile = nil
    local firstFieldEffect = nil
    
    if spellData.timestamps then
        for _, frame in ipairs(spellData.timestamps) do
            if frame.actions then
                for _, action in ipairs(frame.actions) do
                    if action.action == "missile" and not firstMissile then
                        firstMissile = action
                    elseif action.action == "fieldEffect" and not firstFieldEffect then
                        if (action.x or 0) ~= 0 or (action.y or 0) ~= 0 then
                            firstFieldEffect = action
                        end
                    end
                end
            end
            if firstMissile then 
                break 
            end
        end
    end

    local playerDir = 2
    
    if hasTarget then
        playerDir = 1
    elseif firstMissile then
        local tx = firstMissile.x or 0
        local ty = firstMissile.y or 0
        
        if tx > 0 then 
            playerDir = 1
        elseif tx < 0 then 
            playerDir = 3
        elseif ty < 0 then 
            playerDir = 0
        elseif ty > 0 then 
            playerDir = 2
        end
    elseif firstFieldEffect then
        local tx = firstFieldEffect.x or 0
        local ty = firstFieldEffect.y or 0
        
        if tx > 0 then 
            playerDir = 1
        elseif tx < 0 then 
            playerDir = 3
        elseif ty < 0 then 
            playerDir = 0
        elseif ty > 0 then 
            playerDir = 2
        end
    end

    local player = g_game.getLocalPlayer()
    local playerOutfit = player and player:getOutfit() or nil
    
    if not playerOutfit or (playerOutfit.type or 0) == 0 then
        playerOutfit = {type = 128, head = 78, body = 69, legs = 58, feet = 76, addons = 0}
    end
    
    local playerCreature = createAnchoredCreature(0, 0, playerOutfit, playerDir)

    local dummyCreature = nil
    if hasTarget then
        local dummyOutfit = {type = playerOutfit.type or 128, head = 0, body = 0, legs = 0, feet = 0, addons = 0}
        dummyCreature = createAnchoredCreature(dummyRelX, dummyRelY, dummyOutfit, 3)
    end

    local function runAnimation()
        if not animationPanel:isVisible() then 
            return 
        end
        
        -- Texto laranja removido daqui

        local timestamps = spellData.timestamps or {}
        if #timestamps == 0 then 
            return 
        end

        for _, frame in ipairs(timestamps) do
            local delay = frame.timestamp or 0
            local event = scheduleEvent(function()
                if not animationPanel:recursiveGetChildById(playerCreature:getId()) then 
                    return 
                end 

                for _, action in ipairs(frame.actions or {}) do
                    if action.action == "missile" then
                        local missile = g_ui.createWidget("UIMissile", animationPanel)
                        missile:setId("previewMissile")
                        missile:setMissileId(action.missileID or 1) 
                        missile:setSize({width = tileSize, height = tileSize}) 
                        
                        local sML, sMT = getMarginForRel(0, 0)
                        missile:addAnchor(AnchorTop, 'parent', AnchorTop)
                        missile:addAnchor(AnchorLeft, 'parent', AnchorLeft)
                        missile:setMarginLeft(sML)
                        missile:setMarginTop(sMT)
                        
                        local targetX = action.x or dummyRelX
                        local targetY = action.y or dummyRelY
                        local eML, eMT = getMarginForRel(targetX, targetY)

                        local dir = 1
                        if targetX < 0 then 
                            dir = 3 
                        end
                        if targetY < 0 then 
                            dir = 0 
                        end
                        if targetY > 0 then 
                            dir = 2 
                        end
                        
                        missile:setDirection(dir)

                        local flightTime = 400
                        local steps = 10
                        local stepDelay = flightTime / steps
                        local dML = (eML - sML) / steps
                        local dMT = (eMT - sMT) / steps
                        
                        for i = 1, steps do
                            scheduleEvent(function()
                                local curML = missile:getMarginLeft()
                                local curMT = missile:getMarginTop()
                                missile:setMarginLeft(curML + dML)
                                missile:setMarginTop(curMT + dMT)
                                if i == steps then 
                                    missile:destroy() 
                                end
                            end, i * stepDelay)
                        end

                    elseif action.action == "fieldEffect" then
                        local effect = g_ui.createWidget("UIEffect", animationPanel)
                        effect:setId("previewEffect")
                        effect:setEffectId(action.effectID or 1)
                        effect:setSize({width = tileSize, height = tileSize})
                        effect:setClipping(false)
                        
                        local ml, mt = getMarginForRel(action.x or 0, action.y or 0)
                        effect:addAnchor(AnchorTop, 'parent', AnchorTop)
                        effect:addAnchor(AnchorLeft, 'parent', AnchorLeft)
                        effect:setMarginLeft(ml)
                        effect:setMarginTop(mt)
                        
                        scheduleEvent(function()
                            if effect and (not effect.isDestroyed or not effect:isDestroyed()) then 
                                effect:destroy() 
                            end
                        end, 1000)

                    elseif action.action == "objecttype" then
                        local item = g_ui.createWidget("UIItem", animationPanel)
                        item:setId("previewItem")
                        item:setItemId(action.objecttypeID or 2135)
                        item:setSize({width = tileSize, height = tileSize})
                        item:setClipping(false)
                        
                        local ml, mt = getMarginForRel(action.x or 0, action.y or 0)
                        item:addAnchor(AnchorTop, 'parent', AnchorTop)
                        item:addAnchor(AnchorLeft, 'parent', AnchorLeft)
                        item:setMarginLeft(ml)
                        item:setMarginTop(mt)
                    end
                end
            end, delay)
            table.insert(MagicalArchive.previewEvents, event)
        end
    end

    runAnimation()

    local loopEvent = scheduleEvent(function()
        if VisibleCyclopediaPanel and VisibleCyclopediaPanel:isVisible() then
            local pnl = VisibleCyclopediaPanel:recursiveGetChildById("animationPanel")
            if pnl and pnl:isVisible() then
                MagicalArchive.playPreview(spellData)
            end
        end
    end, 3000)
    
    table.insert(MagicalArchive.previewEvents, loopEvent)
end

function MagicalArchive.loadSpellsFromJson()
    local spellsFile = "/mods/game_cyclopedia/classes/magical_archive/spells.json"
    local spellsData = {}
    if g_resources.fileExists(spellsFile) then
        local status, result = pcall(function()
            return json.decode(g_resources.readFileContents(spellsFile))
        end)
        if status then
            spellsData = result
        else
            g_logger.error("Error loading spells.json: " .. result)
            return
        end
    else
        g_logger.error("spells.json not found: " .. spellsFile)
        return
    end

    local previewFile = "/mods/game_cyclopedia/classes/magical_archive/spells-preview.json"
    local previewData = {}
    if g_resources.fileExists(previewFile) then
        local status, result = pcall(function()
            return json.decode(g_resources.readFileContents(previewFile))
        end)
        if status then
            previewData = result
        else
            g_logger.error("Error loading spells-preview.json: " .. result)
            return
        end
    else
        g_logger.error("spells-preview.json not found: " .. previewFile)
        return
    end

    local iconIndexToClientId = {}
    for iconName, ids in pairs(SpellIcons) do
        local clientId, tfsId = ids[1], ids[2]
        iconIndexToClientId[tfsId] = clientId
    end

    local combinedSpells = {}
    for _, spell in ipairs(spellsData) do
        local spellId = tostring(spell.spellid or 0)
        local preview = previewData[spellId] or {}
        local allowedVocations = spell.allowedVocations
        if not allowedVocations or type(allowedVocations) ~= "table" then
            allowedVocations = {}
        end

        local combinedSpell = {
            id = spell.spellid or 0,
            name = spell.name or "Unknown",
            words = spell.formulaWithoutParams or "",
            icon = spell.iconIndex or "unknown",
            group = { [spell.spellGroupPrimary or "SPELLGROUP_NONE"] = true },
            vocations = allowedVocations,
            level = spell.minimumCasterLevel or 0,
            premium = spell.premium or false,
            aggressive = spell.aggressive or false,
            castCostMana = spell.castCostMana or 0,
            castCostSoulPoints = spell.castCostSoulPoints or 0,
            cooldownSelf = spell.cooldownSelf or 0,
            cooldownPrimaryGroup = spell.cooldownPrimaryGroup or 0,
            cooldownSecondaryGroup = spell.cooldownSecondaryGroup or 0,
            description = spell.description or "No description available.",
            cities = spell.cities or {},
            goldPrice = spell.goldPrice or 0,
            source = spell.source or "Unknown",
            scaling = spell.scaling or {},
            runeParams = spell.runeParams or {},
            mean = spell.mean or 0,
            damagetype = spell.damagetype or "Unknown",
            range = preview.range or 0,
            timestamps = preview.timestamps or {},
            initActions = preview.initActions or {},
            type = spell.isRune and "Conjure" or "Spell",
            directional = spell.aggressive
        }

        table.insert(combinedSpells, combinedSpell)
    end

    return combinedSpells
end

function MagicalArchive.init()
    if not VisibleCyclopediaPanel then
        return
    end

    local jsonSpells = MagicalArchive.loadSpellsFromJson() or {}
    local spellsLuaSpells = Spells.getSpellList() or {}
    
    MagicalArchive.spellList = {}
    for _, jsonSpell in ipairs(jsonSpells) do
        local matchingSpell = nil
        for _, spell in ipairs(spellsLuaSpells) do
            if spell.id == jsonSpell.id then
                matchingSpell = spell
                break
            end
        end

        local combinedSpell = {
            id = jsonSpell.id,
            name = jsonSpell.name,
            words = jsonSpell.words,
            icon = matchingSpell and matchingSpell.icon or jsonSpell.icon,
            group = jsonSpell.group,
            vocations = jsonSpell.vocations,
            level = jsonSpell.level,
            premium = jsonSpell.premium,
            aggressive = jsonSpell.aggressive,
            castCostMana = jsonSpell.castCostMana,
            castCostSoulPoints = jsonSpell.castCostSoulPoints,
            cooldownSelf = jsonSpell.cooldownSelf,
            cooldownPrimaryGroup = jsonSpell.cooldownPrimaryGroup,
            cooldownSecondaryGroup = jsonSpell.cooldownSecondaryGroup,
            description = jsonSpell.description,
            cities = jsonSpell.cities,
            goldPrice = jsonSpell.goldPrice,
            source = jsonSpell.source,
            scaling = jsonSpell.scaling,
            runeParams = jsonSpell.runeParams,
            mean = jsonSpell.mean,
            damagetype = jsonSpell.damagetype,
            range = jsonSpell.range,
            timestamps = jsonSpell.timestamps,
            initActions = jsonSpell.initActions,
            type = jsonSpell.type,
            directional = jsonSpell.directional,
            autoaim = matchingSpell and matchingSpell.directional or false,
        }

        table.insert(MagicalArchive.spellList, combinedSpell)
    end

    MagicalArchive.learnedSpells = modules.game_spells.getSpellListData()

    MagicalArchive.combatMenu = VisibleCyclopediaPanel:recursiveGetChildById("combatMenu")
    MagicalArchive.additionalMenu = VisibleCyclopediaPanel:recursiveGetChildById("additionalMenu")
    MagicalArchive.runeMenu = VisibleCyclopediaPanel:recursiveGetChildById("runeMenu")
    
    if cyclopediaWindow and cyclopediaWindow.assignSpellButton then
        cyclopediaWindow.assignSpellButton.onClick = MagicalArchive.assignSpellToActionBar
    end

    MagicalArchive.summaryButtons = UIRadioGroup.create()
    if MagicalArchive.combatMenu then
        MagicalArchive.summaryButtons:addWidget(MagicalArchive.combatMenu)
    end
    if MagicalArchive.additionalMenu then
        MagicalArchive.summaryButtons:addWidget(MagicalArchive.additionalMenu)
    end
    if MagicalArchive.runeMenu then
        MagicalArchive.summaryButtons:addWidget(MagicalArchive.runeMenu)
    end
    MagicalArchive.summaryButtons.onSelectionChange = MagicalArchive.onSummaryChange

    MagicalArchive.temporaryFilter = getDefaultFilter()
    local searchText = VisibleCyclopediaPanel:recursiveGetChildById("searchText")
    if searchText then
        searchText:clearText(true)
    end
end

-- A lista learnedSpells (modules.game_spells.getSpellListData) e indexada por CLIENT id, enquanto
-- a spell da Magical Archive usa o SERVER id (spellid do JSON). Por isso a checagem por id falhava
-- sempre e TODAS as spells ficavam opacas. Casamos por 'words' (chave estavel entre as duas fontes).
function MagicalArchive.isSpellLearned(spell)
    local learned = MagicalArchive.learnedSpells
    if not learned then
        return false
    end

    local words = spell.words and string.trim(string.lower(spell.words)) or nil
    local name = spell.name and string.lower(spell.name) or nil
    for _, known in pairs(learned) do
        if words and known.words and string.trim(string.lower(known.words)) == words then
            return true
        end
        if name and known.name and string.lower(known.name) == name then
            return true
        end
    end
    return false
end

function MagicalArchive.spellIsLocked(spell, level)
    if level < spell.level then
        return true
    end

    if spell.maglevel and level < spell.maglevel then
        return true
    end

    -- spell.vocations (JSON allowedVocations) sao NOMES ("Knight"/"Paladin"/...). translateVocation
    -- devolve NUMERO e nunca casava -> magias de outras classes ficavam "ativas". Usa o NOME.
    if spell.vocations and #spell.vocations > 0
        and not table.contains(spell.vocations, translateVocationName(g_game.getLocalPlayer():getVocation())) then
        return true
    end

    if not MagicalArchive.isSpellLearned(spell) then
        return true
    end
    return false
end

function MagicalArchive.showSpellList()
    if not VisibleCyclopediaPanel or VisibleCyclopediaPanel:getId() ~= "MagicalArchiveDataPanel" then
        return true
    end

    MagicalArchive.init()
    table.sort(MagicalArchive.spellList, function(a, b)
        return a.name < b.name
    end)

    MagicalArchive.setupSpellList()
end

function MagicalArchive.setupSpellList(searchText)
    MagicalArchive.stopPreview()
    MagicalArchive.currentSpell = nil

    local player = g_game.getLocalPlayer()
    local playerLevel = player:getLevel()
    local playerVocation = translateVocation(player:getVocation())
    local list = VisibleCyclopediaPanel:recursiveGetChildById("listPanel")
    list:destroyChildren()

    for _, spell in pairs(MagicalArchive.spellList) do
        if searchText and #searchText > 0 then
            if not (matchText(searchText, spell.name) or matchText(searchText, spell.words)) then
                goto continue
            end
        end

        if not passesVocationFilter(spell.vocations, playerVocation) then
            goto continue
        end

        if not passesLevelFilter(spell.level, playerLevel) then
            goto continue
        end

        if not passesSpellGroupFilter(spell.group) then
            goto continue
        end

        local widget = g_ui.createWidget("SmallSpellList", list)
        local image = widget:recursiveGetChildById('spellIcon')
        local name = widget:recursiveGetChildById('name')
        local disabled = widget:recursiveGetChildById('gray')

        local spellId = SpellIcons[spell.icon] and SpellIcons[spell.icon][1] or 0
        local source = SpelllistSettings['Default'].verySmallIconFolder
        local clip = Spells.getImageClipVerySmall(spellId, 'Default')

        image:setImageSource(source)
        image:setImageClip(clip)

        name:setText(short_text(spell.name, 15))
        if #spell.name > 15 then
            name:setTooltip(spell.name)
        end

        disabled:setVisible(MagicalArchive.spellIsLocked(spell, playerLevel))
        widget.spellData = spell

        ::continue::
    end

    if cyclopediaWindow and cyclopediaWindow.aimTargetBox then
        cyclopediaWindow.aimTargetBox:setVisible(false)
    end
    
    list.onChildFocusChange = function(_, focused, oldFocused) 
        MagicalArchive.onSelectSpell(focused, oldFocused)
    end

    local firstWidget = list:getFirstChild()
    if not firstWidget then
        VisibleCyclopediaPanel:recursiveGetChildById("dataContent"):setVisible(false)
        return true
    end

    list:focusChild(firstWidget, KeyboardFocusReason, true)
end

function MagicalArchive.onSelectSpell(focused, oldFocused)
    if not VisibleCyclopediaPanel or VisibleCyclopediaPanel:getId() ~= "MagicalArchiveDataPanel" then
        return true
    end

    if oldFocused then
        local oldNameLabel = oldFocused:recursiveGetChildById("name")
        if oldNameLabel then
            oldNameLabel:setColor("#c0c0c0")
        end
    end

    if not focused then
        return true
    end

    local spellPanel = VisibleCyclopediaPanel:recursiveGetChildById("dataContent")
    if not spellPanel then
        return true
    end

    spellPanel:setVisible(true)

    local nameLabel = focused:recursiveGetChildById("name")
    if nameLabel then
        nameLabel:setColor("#f4f4f4")
    end

    local spellData = focused.spellData
    if not spellData then
        return true
    end
    MagicalArchive.currentSpell = spellData

    MagicalArchive.playPreview(spellData)

    local spellId = SpellIcons[spellData.icon] and SpellIcons[spellData.icon][1] or 0
    local source = SpelllistSettings['Default'].iconsFolder
    local clip = Spells.getImageClipNormal(spellId, 'Default')

    spellPanel:recursiveGetChildById("spellName"):setText(spellData.name or "")
    spellPanel:recursiveGetChildById("spellType"):setText(spellData.words or "")
    local iconWidget = spellPanel:recursiveGetChildById("spellIcon")
    if iconWidget then
        iconWidget:setImageSource(source)
        iconWidget:setImageClip(clip)
    end
    spellPanel:recursiveGetChildById("spellMagicLevel"):setText(getRestrictedLevel(spellData))

    local vocationList = spellPanel:recursiveGetChildById("vocationPanel")
    if vocationList then
        vocationList:destroyChildren()
        for _, vocation in ipairs(getVocationIconData(spellData.vocations or {})) do
            local widget = g_ui.createWidget("VocationIcon", vocationList)
            widget:setImageClip(string.format("%02d 0 9 9", vocation.index))
            widget:setTooltip(vocation.name)
        end
    end

    local isConjure = spellData.type == "Conjure"
    if MagicalArchive.runeMenu then
        MagicalArchive.runeMenu:setVisible(isConjure)
    end

    if MagicalArchive.summaryButtons and MagicalArchive.combatMenu then
        MagicalArchive.summaryButtons:selectWidget(MagicalArchive.combatMenu, false, true)
    end
    if cyclopediaWindow and cyclopediaWindow.aimTargetBox then
        cyclopediaWindow.aimTargetBox:setVisible(spellData.autoaim and true or false)
        cyclopediaWindow.aimTargetBox:setChecked(MagicalArchive.autoAimStorageData[tostring(spellData.id)], true)
    end
end

function MagicalArchive.onSummaryChange(widget, selected, lastSelected)
    if not VisibleCyclopediaPanel or not MagicalArchive.summaryButtons then
        return true
    end

    if not selected then
        if MagicalArchive.combatMenu then
            MagicalArchive.summaryButtons:selectWidget(MagicalArchive.combatMenu)
        end
        return true
    end

    if lastSelected then
        local lastSelectedStyle = panelStyles[lastSelected:getId()]
        if lastSelectedStyle then
            local lastPanel = VisibleCyclopediaPanel:recursiveGetChildById(lastSelectedStyle)
            if lastPanel then
                lastPanel:setVisible(false)
            end
        end
    end

    local selectedStyle = panelStyles[selected:getId()]
    if not selectedStyle then
        return true
    end

    local styleWidget = VisibleCyclopediaPanel:recursiveGetChildById(selectedStyle)
    if styleWidget then
        styleWidget:setVisible(true)
    else
        return true
    end

    local spellListWidget = VisibleCyclopediaPanel:recursiveGetChildById("listPanel")
    if not spellListWidget then
        return true
    end

    local spellFocused = spellListWidget:getFocusedChild()
    if not spellFocused then
        return true
    end

    local selectedId = selected:getId()
    local spellData = spellFocused.spellData
    if selectedId == "combatMenu" then
        MagicalArchive.populateCombatMenu(styleWidget, spellData)
    elseif selectedId == "additionalMenu" then
        MagicalArchive.populateAdditionalMenu(styleWidget, spellData)
    elseif selectedId == "runeMenu" then
        if spellData.type == "Conjure" then
            MagicalArchive.populateRuneMenu(styleWidget, spellData)
        else
            MagicalArchive.runeMenu:setVisible(false)
            MagicalArchive.summaryButtons:selectWidget(MagicalArchive.combatMenu, false, true)
            MagicalArchive.populateCombatMenu(styleWidget, spellData)
        end
    end
end

function MagicalArchive.onFilterPanel(hideFilter)
    if not VisibleCyclopediaPanel then
        return true
    end

    local filterPanel = VisibleCyclopediaPanel:recursiveGetChildById("filterPanel")
    local spellListPanel = VisibleCyclopediaPanel:recursiveGetChildById("spellListPanel")
    if not filterPanel or not spellListPanel then
        return true
    end

    filterPanel:setVisible(not hideFilter)
    spellListPanel:setVisible(hideFilter)

    if not hideFilter then
        for k, v in pairs(MagicalArchive.temporaryFilter) do
            local widget = VisibleCyclopediaPanel:recursiveGetChildById(k)
            if widget then
                widget:setChecked(v, true)
            end
        end
    end
end

function MagicalArchive.onSearchTextChange(widget)
    local searchText = widget:getText()
    MagicalArchive.setupSpellList(searchText)
end

function MagicalArchive.onFilterChange(widget)
    local id = widget:getId()
    local isChecked = widget:isChecked()
    local filter = MagicalArchive.temporaryFilter

    filter[id] = isChecked

    local spellTypes = { "attackFilter", "healingFilter", "supportFilter" }
    if id == "allSpellsFilter" then
        for _, type in ipairs(spellTypes) do
            filter[type] = isChecked
        end
    elseif table.contains(spellTypes, id) then
        filter.allSpellsFilter = true
        for _, type in ipairs(spellTypes) do
            if not filter[type] then
                filter.allSpellsFilter = false
                break
            end
        end
    end

    local vocationTypes = { "sorcererFilter", "druidFilter", "paladinFilter", "knightFilter", "monkFilter" }
    if id == "allVocationsFilter" then
        for _, voc in ipairs(vocationTypes) do
            filter[voc] = isChecked
        end
    elseif table.contains(vocationTypes, id) then
        filter.allVocationsFilter = true
        for _, voc in ipairs(vocationTypes) do
            if not filter[voc] then
                filter.allVocationsFilter = false
                break
            end
        end
    end

    for key, value in pairs(filter) do
        local button = VisibleCyclopediaPanel:recursiveGetChildById(key)
        if button then
            button:setChecked(value, true)
        end
    end

    MagicalArchive.setupSpellList()
end

function MagicalArchive.populateCombatMenu(panel, spellData)
    local runeFields = { "spellGroupInfo", "cdInfo", "groupCdInfo" }
    local allFields = { "manaInfo", "spellGroupInfo", "basePowerInfo", "scalesWithInfo", "cdInfo", "groupCdInfo", "magicTypeInfo", "rangeInfo" }

    for _, widgetId in ipairs(allFields) do
        local infoWidget = panel:recursiveGetChildById(widgetId)
        if infoWidget then
            infoWidget:setText("-")
        end
    end

    if spellData.type == "Conjure" then
        for _, field in ipairs(CombatMenuFields) do
            if table.contains(runeFields, field.widget) then
                local infoWidget = panel:recursiveGetChildById(field.widget)
                if infoWidget and type(field.func) == "function" then
                    local text = field.func(spellData)
                    infoWidget:setText(text or "-")
                end
            end
        end
    else
        for _, field in ipairs(CombatMenuFields) do
            local infoWidget = panel:recursiveGetChildById(field.widget)
            if infoWidget and type(field.func) == "function" then
                local text = field.func(spellData)
                infoWidget:setText(text or "-")
                if field.widget == "scalesWithInfo" then
                    infoWidget:setTooltip(text or "-")
                end
            end
        end
    end
end

function MagicalArchive.populateAdditionalMenu(panel, spellData)
    local additionalFields = {
        { widget = "sourceInfo", func = getSpellSource },
        { widget = "learnInfo", func = getSpellLearnIn },
        { widget = "aboutInfo", func = getSpellDescription }
    }

    local widgetIds = { "sourceInfo", "learnInfo", "aboutInfo" }
    for _, widgetId in ipairs(widgetIds) do
        local infoWidget
        if widgetId == "aboutInfo" then
            local aboutInfoPanel = panel:recursiveGetChildById("aboutInfoPanel")
            infoWidget = aboutInfoPanel and aboutInfoPanel:getChildById("aboutInfo")
        else
            infoWidget = panel:recursiveGetChildById(widgetId)
        end
        if infoWidget then
            infoWidget:setText("-")
        end
    end

    for _, field in ipairs(additionalFields) do
        local infoWidget
        if field.widget == "aboutInfo" then
            local aboutInfoPanel = panel:recursiveGetChildById("aboutInfoPanel")
            infoWidget = aboutInfoPanel and aboutInfoPanel:getChildById("aboutInfo")
        else
            infoWidget = panel:recursiveGetChildById(field.widget)
        end
        if infoWidget then
            if type(field.func) == "function" then
                local text = field.func(spellData)
                infoWidget:setText(text or "-")
            end
        end
    end
end

function MagicalArchive.populateRuneMenu(panel, spellData)
    local runeFields = {
        { widget = "amountInfo", func = getSpellRuneParams },
        { widget = "manaInfo", func = getSpellManaAndSoul },
        { widget = "restrictionInfo", func = getSpellLevel },
        { widget = "spellGroupInfo", func = getSpellGroup },
        { widget = "cdInfo", func = getSpellCooldown },
        { widget = "groupCdInfo", func = getSpellGroupCooldown }
    }

    local widgetIds = { "amountInfo", "manaInfo", "restrictionInfo", "spellGroupInfo", "cdInfo", "groupCdInfo" }
    for _, widgetId in ipairs(widgetIds) do
        local infoWidget = panel:recursiveGetChildById(widgetId)
        if infoWidget then
            infoWidget:setText("-")
        end
    end

    for _, field in ipairs(runeFields) do
        local infoWidget = panel:recursiveGetChildById(field.widget)
        if infoWidget then
            if type(field.func) == "function" then
                local text = field.func(spellData)
                infoWidget:setText(text or "-")
            end
        end
    end

    local vocationList = panel:recursiveGetChildById("vocationsInfo")
    if vocationList then
        vocationList:destroyChildren()
        for _, vocation in ipairs(getVocationIconData(spellData.vocations or {})) do
            local widget = g_ui.createWidget("VocationIcon", vocationList)
            widget:setImageClip(string.format("%02d 0 9 9", vocation.index))
            widget:setTooltip(vocation.name)
        end
    end
end

function MagicalArchive.onAimTargetChange(checkBox)
    local spellListWidget = VisibleCyclopediaPanel:recursiveGetChildById("listPanel")
    if not spellListWidget then
        return true
    end

    local spellFocused = spellListWidget:getFocusedChild()
    if not spellFocused then
        return true
    end

    MagicalArchive.autoAimStorageData[tostring(spellFocused.spellData.id)] = checkBox:isChecked()
    g_game.sendUpdateAutoAimList(spellFocused.spellData.id, checkBox:isChecked())
end

function MagicalArchive.assignSpellToActionBar()
    local spellData = MagicalArchive.currentSpell
    if not spellData then
        local spellListWidget = VisibleCyclopediaPanel and VisibleCyclopediaPanel:recursiveGetChildById("listPanel")
        local spellFocused = spellListWidget and spellListWidget:getFocusedChild()
        spellData = spellFocused and spellFocused.spellData or nil
    end

    if not spellData then
        if modules.game_textmessage then
            modules.game_textmessage.displayStatusMessage(tr("Please select a spell first."))
        end
        return true
    end

    local spellWords = spellData.words
    if type(spellWords) ~= "string" or spellWords == "" then
        if modules.game_textmessage then
            modules.game_textmessage.displayStatusMessage(tr("This spell has no formula to assign."))
        end
        return true
    end

    local assignTextToSlot = modules.game_actionbar and modules.game_actionbar.assignTextToFirstAvailableSlot
    if not assignTextToSlot then
        if modules.game_textmessage then
            modules.game_textmessage.displayStatusMessage(tr("Action bar not available."))
        end
        return true
    end

    local status, assigned = pcall(assignTextToSlot, spellWords, true)
    if modules.game_textmessage then
        if status and assigned then
            modules.game_textmessage.displayStatusMessage(tr("Spell assigned to action bar."))
        else
            modules.game_textmessage.displayStatusMessage(tr("No free action bar slot available."))
        end
    end

    return true
end

function MagicalArchive.loadJson()
    if not LoadedPlayer:isLoaded() then 
        return 
    end

    local file = "/characterdata/" .. LoadedPlayer:getId() .. "/aimattargetconfigurationstorage.json"

    -- Sempre parte de uma COPIA dos defaults (nao referencia, p/ nao mutar AutoAimDefaultSpells)
    -- e sobrescreve com o que o jogador salvou. Assim os spells default (que vem marcados) sao
    -- mantidos mesmo que o JSON nao os contenha.
    local merged = {}
    for k, v in pairs(AutoAimDefaultSpells) do merged[k] = v end

    if g_resources.fileExists(file) then
        local status, result = pcall(function()
            return json.decode(g_resources.readFileContents(file))
        end)
        if not status then
            return g_logger.error("Error while reading auto aim file. Details: " .. result)
        end
        if type(result) == "table" then
            for k, v in pairs(result) do merged[k] = v end
        end
    end
    MagicalArchive.autoAimStorageData = merged

    -- Sincroniza com o SERVIDOR no login. ATENCAO: NAO existe g_game.sendAutoAimList (era nil ->
    -- o "if g_game.sendAutoAimList" nunca rodava -> NADA era enviado, por isso o aim default so
    -- passava a valer depois de marcar/desmarcar). Enviamos cada spell pelo metodo que EXISTE
    -- (g_game.sendUpdateAutoAimList -> opcode 0xC8), o mesmo usado no toggle.
    g_game.doThing(false)
    for spellId, enabled in pairs(merged) do
        local sid = tonumber(spellId)
        if sid then
            g_game.sendUpdateAutoAimList(sid, enabled and true or false)
        end
    end
    g_game.doThing(true)
end

function MagicalArchive.saveJson()
    local file = "/characterdata/" .. LoadedPlayer:getId() .. "/aimattargetconfigurationstorage.json"
    local status, result = pcall(function() 
        return json.encode(MagicalArchive.autoAimStorageData, 2) 
    end)
    
    if not status then
        return g_logger.error("Error while saving auto aim data. Data won't be saved. Details: " .. result)
    end
    
    if result:len() > 100 * 1024 * 1024 then
        return g_logger.error("Something went wrong, file is above 100MB, won't be saved")
    end
    
    g_resources.writeFileContents(file, result)
end