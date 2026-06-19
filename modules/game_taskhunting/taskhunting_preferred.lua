-- ─────────────────────────────────────────────────────────────────────────────
-- game_taskhunting / taskhunting_preferred.lua
-- Preferred List window — creature selection, assign, unlock additional slots
-- ─────────────────────────────────────────────────────────────────────────────

local preferredListWindow = nil
local selectedPreferredItem = nil
local selectedRaceId = nil
-- raceId is stored as phantom label text on each list item (widget userdata keys are unreliable in sandboxed modules)

local SLOT_UNLOCK_COSTS = { [1]=300, [2]=600, [3]=900, [4]=1200 }
local CLEAR_COST = 10

local OPT_PREFERRED_UNLOCK  = 12
local OPT_PREFERRED_CLEAR   = 13
local OPT_UNWANTED_CLEAR    = 14
local OPT_PREFERRED_ASSIGN  = 15
local OPT_UNWANTED_ASSIGN   = 16

-- Forward declarations (module-local)
local setCreatureInPanel
local getPanelForSlot

-- ─────────────────────────────────────────────────────────────────────────────
-- Creature panel helpers
-- ─────────────────────────────────────────────────────────────────────────────

setCreatureInPanel = function(panel, raceId)
    panel:destroyChildren()
    if not raceId or raceId == 0 then return end
    local c = g_ui.createWidget('UICreature', panel)
    c:fill('parent')
    c:setCreatureSize(56)
    if g_things and g_things.getRaceData then
        local raceData = g_things.getRaceData(raceId)
        if raceData and raceData.outfit then
            c:setOutfit(raceData.outfit)
            c:setDirection(2)
            c:getCreature():setStaticWalking(1000)
        end
    end
end

getPanelForSlot = function(slotIndex, isUnwanted)
    if not preferredListWindow then return nil end
    if slotIndex == 0 then
        local id = isUnwanted and 'unwantedCreaturePanel' or 'preferredCreaturePanel'
        return preferredListWindow:recursiveGetChildById(id)
    end
    -- additional slots 1-4: widgets are in rightPanel (slot's parent) with suffixed ids
    local slot = preferredListWindow:recursiveGetChildById('additionalSlot' .. slotIndex)
    if not slot then return nil end
    local rightPanel = slot:getParent()
    if rightPanel then
        local id = isUnwanted and ('unwPanel_' .. slotIndex) or ('prefPanel_' .. slotIndex)
        local panel = rightPanel:getChildById(id)
        if panel then return panel end
    end
    -- fallback: old layout where panels were inside the slot container
    local id = isUnwanted and 'unwPanel' or 'prefPanel'
    return slot:getChildById(id)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Selection
-- ─────────────────────────────────────────────────────────────────────────────

local function getRaceIdFromItem(item)
    local label = item:getChildById('raceIdData')
    if not label then return nil end
    local v = tonumber(label:getText())
    return v
end

function selectPreferredItem(item)
    local raceId = getRaceIdFromItem(item)
    if selectedPreferredItem and selectedPreferredItem ~= item then
        local isOdd = (selectedPreferredItem:getId() == 'odd')
        selectedPreferredItem:setBackgroundColor(isOdd and '#414141' or '#484848')
    end
    selectedPreferredItem = item
    selectedRaceId = raceId
    item:setBackgroundColor('#585858')
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Assign / Clear
-- ─────────────────────────────────────────────────────────────────────────────

function assignPreferred(slotIndex)
    if not selectedPreferredItem or not selectedRaceId then return end
    local panel = getPanelForSlot(slotIndex, false)
    if panel then setCreatureInPanel(panel, selectedRaceId) end
    taskSendAction(OPT_PREFERRED_ASSIGN, slotIndex, selectedRaceId)
end

function assignUnwanted(slotIndex)
    if not selectedPreferredItem or not selectedRaceId then return end
    local panel = getPanelForSlot(slotIndex, true)
    if panel then setCreatureInPanel(panel, selectedRaceId) end
    taskSendAction(OPT_UNWANTED_ASSIGN, slotIndex, selectedRaceId)
end

local function canAffordClear()
    return g_game.getResource(ResourceBountyPoints) >= CLEAR_COST
end

-- Sets a slot button to "Clear" (hasCreature=true) or "Assign" (hasCreature=false).
-- btn: the Button widget; infoPanel: the cost panel next to it.
-- isPreferred: true=preferred side, false=unwanted side; slotIndex: 0=base, 1-4=additional.
-- creaturePanelId: id of the creature panel widget to anchor against (default prefPanel/unwPanel).
local function applySlotButtonState(btn, infoPanel, hasCreature, isPreferred, slotIndex, creaturePanelId)
    if not btn then return end
    local isUnwanted = not isPreferred
    -- default anchor targets match buildUnlockedSlot ids; base row uses different ids
    if not creaturePanelId then
        creaturePanelId = isPreferred and 'prefPanel' or 'unwPanel'
    end
    if hasCreature then
        btn:setText(tr('Clear'))
        btn:setEnabled(canAffordClear())
        btn:removeAnchor(AnchorVerticalCenter)
        btn:addAnchor(AnchorTop, creaturePanelId, AnchorTop)
        btn:setMarginTop(5)
        btn.onClick = function()
            local panel = getPanelForSlot(slotIndex, isUnwanted)
            if panel then setCreatureInPanel(panel, 0) end
            taskSendAction(isPreferred and OPT_PREFERRED_CLEAR or OPT_UNWANTED_CLEAR, slotIndex)
            applySlotButtonState(btn, infoPanel, false, isPreferred, slotIndex)
        end
        if infoPanel then infoPanel:setVisible(true) end
    else
        btn:setText(tr('Assign'))
        btn:setEnabled(true)
        btn:removeAnchor(AnchorTop)
        btn:addAnchor(AnchorVerticalCenter, creaturePanelId, AnchorVerticalCenter)
        btn:setMarginTop(0)
        btn.onClick = function()
            if not selectedPreferredItem or not selectedRaceId then return end
            local panel = getPanelForSlot(slotIndex, isUnwanted)
            if panel then setCreatureInPanel(panel, selectedRaceId) end
            taskSendAction(isPreferred and OPT_PREFERRED_ASSIGN or OPT_UNWANTED_ASSIGN, slotIndex, selectedRaceId)
            applySlotButtonState(btn, infoPanel, true, isPreferred, slotIndex)
        end
        if infoPanel then infoPanel:setVisible(false) end
    end
end

function clearPreferred(slotIndex)
    local panel = getPanelForSlot(slotIndex, false)
    if panel then setCreatureInPanel(panel, 0) end
    taskSendAction(OPT_PREFERRED_CLEAR, slotIndex)
end

function clearUnwanted(slotIndex)
    local panel = getPanelForSlot(slotIndex, true)
    if panel then setCreatureInPanel(panel, 0) end
    taskSendAction(OPT_UNWANTED_CLEAR, slotIndex)
end

function updateClearButtons()
    if not preferredListWindow then return end
    local canClear = canAffordClear()

    -- Only update enabled state on buttons that are currently in "Clear" mode
    local function refreshBtn(btn)
        if btn and btn:getText() == tr('Clear') then
            btn:setEnabled(canClear)
        end
    end

    refreshBtn(preferredListWindow:recursiveGetChildById('preferredClearBtn'))
    refreshBtn(preferredListWindow:recursiveGetChildById('unwantedClearBtn'))

    for i = 1, 4 do
        local slot = preferredListWindow:recursiveGetChildById('additionalSlot' .. i)
        if slot then
            local rightPanel = slot:getParent()
            if rightPanel then
                refreshBtn(rightPanel:getChildById('prefClearBtn_' .. i))
                refreshBtn(rightPanel:getChildById('unwClearBtn_' .. i))
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Unlock additional slot
-- ─────────────────────────────────────────────────────────────────────────────

function unlockPreferredSlot(slotIndex)
    taskSendAction(OPT_PREFERRED_UNLOCK, slotIndex)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Build unlocked slot UI (replaces locked content with assign panels)
-- ─────────────────────────────────────────────────────────────────────────────

local function createSlotInfoPanel(parent, anchorTopId)
    local panel = g_ui.createWidget('Panel', parent)
    panel:setSize({width=43, height=20})
    panel:setImageSource('/images/ui/infoPanel')
    panel:setImageBorder(3)
    panel:addAnchor(AnchorTop, anchorTopId, AnchorBottom)
    panel:addAnchor(AnchorLeft, anchorTopId, AnchorLeft)
    panel:setMarginTop(5)

    local icon = g_ui.createWidget('UIWidget', panel)
    icon:setId('infoIcon')
    icon:setImageSource('/images/task_bounty/info_icon1')
    icon:addAnchor(AnchorRight, 'parent', AnchorRight)
    icon:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    icon:setMarginRight(3)

    local lbl = g_ui.createWidget('Label', panel)
    lbl:setId('valueLabel')
    lbl:setFont('Verdana Bold-11px')
    lbl:setColor('#c0c0c0')
    lbl:setTextAutoResize(true)
    lbl:addAnchor(AnchorRight, 'infoIcon', AnchorLeft)
    lbl:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    lbl:setMarginRight(2)

    return panel
end

-- Returns the id of the widget to anchor "top" of a new unlocked slot row.
-- slotIndex 1 anchors below unwantedCreaturePanel (base row).
-- slotIndex N>1 anchors below prefPanel of slot N-1.
local function getAnchorAboveId(slotIndex)
    if slotIndex == 1 then
        return 'unwantedCreaturePanel'
    end
    return 'prefPanel_' .. (slotIndex - 1)
end

local function buildUnlockedSlot(slot, slotIndex)
    local rightPanel = slot:getParent()
    if not rightPanel then return end

    -- Guard: already built (prefPanel_N exists in rightPanel)
    if rightPanel:getChildById('prefPanel_' .. slotIndex) then return end

    -- Hide the locked slot container
    slot:setVisible(false)

    local anchorAbove = getAnchorAboveId(slotIndex)
    local prefPanelId  = 'prefPanel_'   .. slotIndex
    local prefBtnId    = 'prefClearBtn_'.. slotIndex
    local prefInfoId   = 'prefInfoPanel_'.. slotIndex
    local unwPanelId   = 'unwPanel_'    .. slotIndex
    local unwBtnId     = 'unwClearBtn_' .. slotIndex
    local unwInfoId    = 'unwInfoPanel_'.. slotIndex

    local prefPanel = g_ui.createWidget('UIWidget', rightPanel)
    prefPanel:setId(prefPanelId)
    prefPanel:setSize({width=64, height=64})
    prefPanel:setImageSource('/images/ui/1pixel-down-frame')
    prefPanel:setImageBorder(3)
    prefPanel:addAnchor(AnchorTop, anchorAbove, AnchorBottom)
    prefPanel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    prefPanel:setMarginTop(15)
    prefPanel:setMarginLeft(11)

    local prefBtn = g_ui.createWidget('Button', rightPanel)
    prefBtn:setId(prefBtnId)
    prefBtn:setWidth(43)
    prefBtn:setHeight(20)
    prefBtn:addAnchor(AnchorVerticalCenter, prefPanelId, AnchorVerticalCenter)
    prefBtn:addAnchor(AnchorLeft, prefPanelId, AnchorRight)
    prefBtn:setMarginLeft(10)

    local prefInfoPanel = createSlotInfoPanel(rightPanel, prefBtnId)
    prefInfoPanel:setId(prefInfoId)
    local prefInfoLbl = prefInfoPanel:getChildById('valueLabel')
    if prefInfoLbl then prefInfoLbl:setText(tostring(CLEAR_COST)) end

    local unwPanel = g_ui.createWidget('UIWidget', rightPanel)
    unwPanel:setId(unwPanelId)
    unwPanel:setSize({width=64, height=64})
    unwPanel:setImageSource('/images/ui/1pixel-down-frame')
    unwPanel:setImageBorder(3)
    unwPanel:addAnchor(AnchorTop, prefPanelId, AnchorTop)
    unwPanel:addAnchor(AnchorLeft, prefBtnId, AnchorRight)
    unwPanel:setMarginLeft(20)

    local unwBtn = g_ui.createWidget('Button', rightPanel)
    unwBtn:setId(unwBtnId)
    unwBtn:setWidth(43)
    unwBtn:setHeight(20)
    unwBtn:addAnchor(AnchorVerticalCenter, unwPanelId, AnchorVerticalCenter)
    unwBtn:addAnchor(AnchorLeft, unwPanelId, AnchorRight)
    unwBtn:setMarginLeft(10)

    local unwInfoPanel = createSlotInfoPanel(rightPanel, unwBtnId)
    unwInfoPanel:setId(unwInfoId)
    local unwInfoLbl = unwInfoPanel:getChildById('valueLabel')
    if unwInfoLbl then unwInfoLbl:setText(tostring(CLEAR_COST)) end

    applySlotButtonState(prefBtn, prefInfoPanel, false, true,  slotIndex, prefPanelId)
    applySlotButtonState(unwBtn,  unwInfoPanel,  false, false, slotIndex, unwPanelId)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Update additional slots (called after server data arrives)
-- ─────────────────────────────────────────────────────────────────────────────

function updateAdditionalSlots()
    if not preferredListWindow then return end
    if not cachedPreferredLists then return end

    -- Slot 0 = base row (always unlocked)
    local baseSlot = cachedPreferredLists[1]
    if baseSlot then
        local prefPanel = preferredListWindow:recursiveGetChildById('preferredCreaturePanel')
        local unwPanel  = preferredListWindow:recursiveGetChildById('unwantedCreaturePanel')
        if prefPanel then setCreatureInPanel(prefPanel, baseSlot.preferredRaceId) end
        if unwPanel  then setCreatureInPanel(unwPanel,  baseSlot.unwantedRaceId)  end

        local prefBtn  = preferredListWindow:recursiveGetChildById('preferredClearBtn')
        local prefInfo = preferredListWindow:recursiveGetChildById('preferredInfoPanel')
        if prefInfo then
            local lbl = prefInfo:getChildById('valueLabel')
            if lbl then lbl:setText(tostring(CLEAR_COST)) end
        end
        applySlotButtonState(prefBtn, prefInfo, baseSlot.preferredRaceId ~= 0, true, 0, 'preferredCreaturePanel')

        local unwBtn  = preferredListWindow:recursiveGetChildById('unwantedClearBtn')
        local unwInfo = preferredListWindow:recursiveGetChildById('unwantedInfoPanel')
        if unwInfo then
            local lbl = unwInfo:getChildById('valueLabel')
            if lbl then lbl:setText(tostring(CLEAR_COST)) end
        end
        applySlotButtonState(unwBtn, unwInfo, baseSlot.unwantedRaceId ~= 0, false, 0, 'unwantedCreaturePanel')
    end

    -- Additional slots 1-4
    for i = 1, 4 do
        local slot = preferredListWindow:recursiveGetChildById('additionalSlot' .. i)
        if not slot then goto continue end

        local slotData = cachedPreferredLists[i + 1]
        local isUnlocked = slotData and (slotData.activedList == 1)

        if isUnlocked then
            buildUnlockedSlot(slot, i)
            -- Widgets are in rightPanel (slot's parent), not inside slot
            local rightPanel = slot:getParent()
            -- Restore creatures
            local prefPanel = rightPanel and rightPanel:getChildById('prefPanel_' .. i)
            local unwPanel  = rightPanel and rightPanel:getChildById('unwPanel_' .. i)
            if prefPanel and slotData.preferredRaceId ~= 0 then
                setCreatureInPanel(prefPanel, slotData.preferredRaceId)
            end
            if unwPanel and slotData.unwantedRaceId ~= 0 then
                setCreatureInPanel(unwPanel, slotData.unwantedRaceId)
            end
            -- Set button state based on whether creature is assigned
            local prefBtn  = rightPanel and rightPanel:getChildById('prefClearBtn_' .. i)
            local prefInfo = rightPanel and rightPanel:getChildById('prefInfoPanel_' .. i)
            if prefInfo then
                local lbl = prefInfo:getChildById('valueLabel')
                if lbl then lbl:setText(tostring(CLEAR_COST)) end
            end
            applySlotButtonState(prefBtn, prefInfo, slotData.preferredRaceId ~= 0, true, i, 'prefPanel_' .. i)

            local unwBtn  = rightPanel and rightPanel:getChildById('unwClearBtn_' .. i)
            local unwInfo = rightPanel and rightPanel:getChildById('unwInfoPanel_' .. i)
            if unwInfo then
                local lbl = unwInfo:getChildById('valueLabel')
                if lbl then lbl:setText(tostring(CLEAR_COST)) end
            end
            applySlotButtonState(unwBtn, unwInfo, slotData.unwantedRaceId ~= 0, false, i, 'unwPanel_' .. i)
        else
            -- Locked: show cost + unlock button
            local cost = SLOT_UNLOCK_COSTS[i] or 0
            local canUnlock = g_game.getResource(ResourceBountyPoints) >= cost
            local unlockBtn = slot:getChildById('unlockBtn')
            if unlockBtn then
                unlockBtn:setEnabled(canUnlock)
                local idx = i  -- capture for closure
                unlockBtn.onClick = function()
                    taskSendAction(OPT_PREFERRED_UNLOCK, idx)
                end
            end
            -- Update cost label in infoPanel
            local infoPanel = slot:getChildById('infoPanel')
            if infoPanel then
                local costLabel = infoPanel:getChildById('costLabel')
                if not costLabel then
                    costLabel = g_ui.createWidget('UILabel', infoPanel)
                    costLabel:setId('costLabel')
                    costLabel:setFont('Verdana Bold-11px')
                    costLabel:setColor('#dfdfdf')
                    costLabel:setTextAutoResize(true)
                    costLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
                    costLabel:addAnchor(AnchorRight, 'slotIcon', AnchorLeft)
                    costLabel:setMarginRight(3)
                end
                costLabel:setText(tostring(cost))
            end
        end

        ::continue::
    end

    updateClearButtons()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Populate creature list
-- ─────────────────────────────────────────────────────────────────────────────

function populatePreferredList()
    if not preferredListWindow then return end
    local list = preferredListWindow:recursiveGetChildById('creaturesList')
    if not list then return end
    -- Only rebuild if the list is empty (first open or after window destroy)
    if #list:getChildren() > 0 then return end
    list:destroyChildren()

    local races = {}
    if g_things and g_things.getRacesByName then
        races = g_things.getRacesByName('')
    end

    -- Filter bosses, sort alphabetically
    local filtered = {}
    for _, race in ipairs(races) do
        if not race.boss then
            filtered[#filtered + 1] = race
        end
    end
    table.sort(filtered, function(a, b)
        return (a.name or '') < (b.name or '')
    end)

    for idx, race in ipairs(filtered) do
        local item = g_ui.createWidget('PreferredListItem', list)
        local isOdd = (idx % 2 == 1)
        item:setId(isOdd and 'odd' or 'even')
        item:setBackgroundColor(isOdd and '#414141' or '#484848')

        -- Store raceId as hidden label text (widget userdata keys are unreliable in sandboxed modules)
        local dataLabel = g_ui.createWidget('UILabel', item)
        dataLabel:setId('raceIdData')
        dataLabel:setText(tostring(race.raceId or 0))
        dataLabel:setVisible(false)
        dataLabel:setPhantom(true)

        local creatureSlot = item:getChildById('creatureSlot')
        if creatureSlot then
            local c = g_ui.createWidget('UICreature', creatureSlot)
            c:fill('parent')
            c:setCreatureSize(36)
            c:setPhantom(true)
            if race.outfit then
                c:setOutfit(race.outfit)
                c:setDirection(2)
                c:getCreature():setStaticWalking(1000)
            end
        end

        local nameLabel = item:getChildById('creatureName')
        if nameLabel then
            nameLabel:setText(race.name or '')
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Filter list by text
-- ─────────────────────────────────────────────────────────────────────────────

function filterPreferredList(text)
    if not preferredListWindow then return end
    local list = preferredListWindow:recursiveGetChildById('creaturesList')
    if not list then return end

    local filter = text:lower()
    local visibleIndex = 0
    for _, item in ipairs(list:getChildren()) do
        local nameLabel = item:getChildById('creatureName')
        local name = nameLabel and nameLabel:getText():lower() or ''
        local visible = (filter == '' or name:find(filter, 1, true) ~= nil)
        item:setVisible(visible)
        if visible then
            visibleIndex = visibleIndex + 1
            local isOdd = (visibleIndex % 2 == 1)
            item:setId(isOdd and 'odd' or 'even')
            item:setBackgroundColor(isOdd and '#414141' or '#484848')
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Wire base row assign buttons
-- ─────────────────────────────────────────────────────────────────────────────

local function wirePreferredListButtons()
    if not preferredListWindow then return end
    local prefBtn  = preferredListWindow:recursiveGetChildById('preferredClearBtn')
    local prefInfo = preferredListWindow:recursiveGetChildById('preferredInfoPanel')
    if prefInfo then
        local lbl = prefInfo:getChildById('valueLabel')
        if lbl then lbl:setText(tostring(CLEAR_COST)) end
    end
    applySlotButtonState(prefBtn, prefInfo, false, true, 0, 'preferredCreaturePanel')

    local unwBtn  = preferredListWindow:recursiveGetChildById('unwantedClearBtn')
    local unwInfo = preferredListWindow:recursiveGetChildById('unwantedInfoPanel')
    if unwInfo then
        local lbl = unwInfo:getChildById('valueLabel')
        if lbl then lbl:setText(tostring(CLEAR_COST)) end
    end
    applySlotButtonState(unwBtn, unwInfo, false, false, 0, 'unwantedCreaturePanel')
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Open / close
-- ─────────────────────────────────────────────────────────────────────────────

function openPreferredList()
    if preferredListWindow then
        preferredListWindow:show()
        preferredListWindow:raise()
        preferredListWindow:focus()
        populatePreferredList()
        updateAdditionalSlots()
        return
    end
    preferredListWindow = g_ui.createWidget('PreferredListWindow', rootWidget)
    wirePreferredListButtons()
    populatePreferredList()
    updateAdditionalSlots()
end

function closePreferredList()
    if preferredListWindow then
        preferredListWindow:hide()
    end
    selectedPreferredItem = nil
    selectedRaceId = nil
    -- Do NOT clear widgetRaceId here — the list widgets persist in the hidden window
    -- and would lose their raceId mapping if we cleared it
end
