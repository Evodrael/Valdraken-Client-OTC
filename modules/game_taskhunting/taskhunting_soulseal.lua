-- ─────────────────────────────────────────────────────────────────────────────
-- game_taskhunting / taskhunting_soulseal.lua
--
-- Soulpit / Animus Mastery picker. Ported from the HTML modal in
-- Atualizacao/Update_1524_Packets_and_Features/modules/game_taskboard
-- (controller/modal_soulseal.lua + template/html/modal_soulseal.html) into a
-- pure .otui window so it fits OTCV8 without the html runtime.
--
-- Flow:
--   1. Player uses the Soulpit Obelisk (item 47367 / 47379) in the world.
--   2. The mod calls g_game.sendSoulSealsAction(0); server replies on opcode
--      0xBA which OTCV8's parseTaskHuntingBasicData decodes into the Lua
--      event g_game.onSoulsealsData(entries).
--   3. We build the list, the player picks a creature and clicks Fight;
--      sendSoulSealsAction(raceId) tells the server to start the fight.
-- ─────────────────────────────────────────────────────────────────────────────

local OBELISK_ITEM_IDS = { [47367] = true, [47379] = true }
local SOULSEALS_RESOURCE = ResourceSoulseals or 87

local CATEGORY_LABELS = {
    [1] = 'Harmless',
    [2] = 'Trivial',
    [3] = 'Easy',
    [4] = 'Medium',
    [5] = 'Hard',
    [6] = 'Challenging',
}

local soulSealWindow = nil
local soulSealList = nil
local searchInput = nil
local categoryCombo = nil
local fightBtn = nil
local balanceLabel = nil
local selectedPreview = nil
local selectedName = nil
local selectedCategory = nil
local selectedCostLabel = nil
local selectedHintIcon = nil

local rawEntries = {}        -- all entries (normalized) as received
local visibleEntries = {}    -- post-filter list (rendered as rows)
local rowWidgets = {}        -- list-row widgets
local selectedRow = nil
local selectedEntry = nil

local searchText = ''
local categoryIndex = 1      -- 1=All, 2..7=Harmless..Challenging

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function getSoulSealsBalance()
    local player = g_game.getLocalPlayer()
    if not player then return 0 end
    if g_game.getResource then
        return tonumber(g_game.getResource(SOULSEALS_RESOURCE)) or 0
    end
    if player.getResourceBalance then
        return tonumber(player:getResourceBalance(SOULSEALS_RESOURCE)) or 0
    end
    return 0
end

local function categoryLabel(c)
    return CATEGORY_LABELS[tonumber(c) or 0] or 'Unknown'
end

local function normalize(entry)
    entry = entry or {}
    local raceId = tonumber(entry.raceId) or 0
    local raceData = raceId > 0 and g_things.getRaceData(raceId) or nil

    local name = entry.name or (raceData and raceData.name) or ('Race #' .. raceId)
    name = tostring(name)
    if name ~= '' then name = name:capitalize() end

    local category = tonumber(entry.category)
    if category == nil and raceData and raceData.hasCategory then
        category = tonumber(raceData.category) or 0
    end
    category = category or 0

    local points = tonumber(entry.soulsealPoints) or 0
    local doneRaw = entry.done
    local done = doneRaw == true or doneRaw == 1 or (tonumber(doneRaw) or 0) == 1

    return {
        raceId = raceId,
        name = name,
        sortName = name:lower(),
        outfit = entry.outfit or (raceData and raceData.outfit) or nil,
        category = category,
        categoryLabel = categoryLabel(category),
        soulsealPoints = points,
        done = done,
    }
end

local function refreshBalanceLabel()
    if balanceLabel then
        balanceLabel:setText(tostring(getSoulSealsBalance()))
    end
end

local function rebuildSelectionPanel()
    if not soulSealWindow then return end

    local entry = selectedEntry
    if not entry then
        if selectedName then selectedName:setText(tr('No creature selected')) end
        if selectedCategory then selectedCategory:setText('') end
        if selectedCostLabel then selectedCostLabel:setText('0') end
        if selectedHintIcon then selectedHintIcon:setTooltip(tr('Select a creature from the list.')) end
        if selectedPreview then selectedPreview:setVisible(false) end
        if fightBtn then fightBtn:setEnabled(false) end
        return
    end

    if selectedName then selectedName:setText(entry.name) end
    if selectedCategory then selectedCategory:setText(entry.categoryLabel) end
    if selectedCostLabel then selectedCostLabel:setText(tostring(entry.soulsealPoints)) end

    if selectedPreview then
        if entry.outfit then
            if selectedPreview.setCreatureSize then
                selectedPreview:setCreatureSize(56)
            end
            selectedPreview:setOutfit(entry.outfit)
            if selectedPreview.setDirection then
                selectedPreview:setDirection(2)
            end
            if selectedPreview.getCreature and selectedPreview:getCreature()
                and selectedPreview:getCreature().setStaticWalking then
                selectedPreview:getCreature():setStaticWalking(1000)
            end
            selectedPreview:setVisible(true)
        else
            selectedPreview:setVisible(false)
        end
    end

    local balance = getSoulSealsBalance()
    local canFight = (not entry.done) and balance >= entry.soulsealPoints and entry.raceId > 0
    if fightBtn then fightBtn:setEnabled(canFight) end
    if selectedHintIcon then
        if entry.done then
            selectedHintIcon:setTooltip(tr('Animus Mastery already unlocked for this creature.'))
        elseif canFight then
            selectedHintIcon:setTooltip(tr('Battle the chosen creature in the Soul Pit.'))
        else
            selectedHintIcon:setTooltip(tr('You do not have enough Soulseals to fight this creature.'))
        end
    end
end

local function setSelectedRow(row)
    if selectedRow and not selectedRow:isDestroyed() then
        selectedRow:setOn(false)
    end
    selectedRow = row
    if row and not row:isDestroyed() then
        row:setOn(true)
        selectedEntry = row.entry
    else
        selectedEntry = nil
    end
    rebuildSelectionPanel()
end

local function destroyRowWidgets()
    for _, w in ipairs(rowWidgets) do
        if w and not w:isDestroyed() then w:destroy() end
    end
    rowWidgets = {}
end

local function populateList()
    if not soulSealList then return end
    destroyRowWidgets()
    selectedRow = nil
    selectedEntry = nil

    -- Filter
    local searchLower = (searchText or ''):lower()
    visibleEntries = {}
    for _, e in ipairs(rawEntries) do
        local matchesText = (searchLower == '' or (e.sortName or ''):find(searchLower, 1, true) ~= nil)
        local matchesCategory = (categoryIndex == 1) or (e.category == (categoryIndex - 1))
        if matchesText and matchesCategory then
            visibleEntries[#visibleEntries + 1] = e
        end
    end

    -- Sort: not-done first, then by category, then by name.
    table.sort(visibleEntries, function(a, b)
        if a.done ~= b.done then return not a.done end
        if a.category ~= b.category then return a.category < b.category end
        return a.sortName < b.sortName
    end)

    for _, e in ipairs(visibleEntries) do
        local row = g_ui.createWidget('SoulSealRowItem', soulSealList)
        row.entry = e

        -- Create the UICreature inside the 36x36 slot the same way
        -- taskhunting_preferred.lua does (setCreatureSize keeps the outfit
        -- from rendering at its huge native size). Mouse events bubble up
        -- to the row because the creature/slot are phantom.
        local creatureSlot = row:getChildById('creatureSlot')
        if creatureSlot and e.outfit then
            local c = g_ui.createWidget('UICreature', creatureSlot)
            c:fill('parent')
            c:setCreatureSize(36)
            c:setPhantom(true)
            c:setOutfit(e.outfit)
            if c.setDirection then c:setDirection(2) end
            if c.getCreature and c:getCreature() and c:getCreature().setStaticWalking then
                c:getCreature():setStaticWalking(1000)
            end
        end

        local nameLabel = row:getChildById('nameLabel')
        if nameLabel then nameLabel:setText(e.name) end

        -- Forward clicks: row is a UIWidget (not Button) and its children are
        -- phantom; we attach onMouseRelease to act as a click trigger.
        row.onMouseRelease = function(_, _, mouseButton)
            if mouseButton == MouseLeftButton then
                setSelectedRow(row)
            end
        end

        local doneIcon = row:getChildById('doneIcon')
        if doneIcon then doneIcon:setVisible(e.done) end

        local costLabel = row:getChildById('costLabel')
        if costLabel then costLabel:setText(tostring(e.soulsealPoints)) end

        rowWidgets[#rowWidgets + 1] = row
    end

    rebuildSelectionPanel()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public API used by the .otui callbacks and by external code (item-use hook).
-- ─────────────────────────────────────────────────────────────────────────────

function showSoulSeals()
    if not soulSealWindow then
        soulSealWindow = g_ui.createWidget('SoulSealsWindow', rootWidget)
        soulSealList      = soulSealWindow:recursiveGetChildById('soulSealList')
        searchInput       = soulSealWindow:recursiveGetChildById('searchInput')
        categoryCombo     = soulSealWindow:recursiveGetChildById('categoryCombo')
        fightBtn          = soulSealWindow:recursiveGetChildById('fightBtn')
        balanceLabel      = soulSealWindow:recursiveGetChildById('balanceLabel')
        selectedPreview   = soulSealWindow:recursiveGetChildById('selectedPreview')
        selectedName      = soulSealWindow:recursiveGetChildById('selectedName')
        selectedCategory  = soulSealWindow:recursiveGetChildById('selectedCategory')
        selectedCostLabel = soulSealWindow:recursiveGetChildById('selectedCostLabel')
        selectedHintIcon  = soulSealWindow:recursiveGetChildById('selectedHintIcon')
    end

    soulSealWindow:show()
    soulSealWindow:raise()
    soulSealWindow:focus()
    populateList()
    refreshBalanceLabel()
end

function hideSoulSeals()
    if soulSealWindow and not soulSealWindow:isDestroyed() then
        soulSealWindow:hide()
    end
end

function isSoulSealsOpen()
    return soulSealWindow ~= nil and not soulSealWindow:isDestroyed() and soulSealWindow:isVisible()
end

function filterSoulSeals(text)
    searchText = text or ''
    populateList()
end

function changeSoulSealCategory(value)
    categoryIndex = tonumber(value) or 1
    populateList()
end

function confirmSoulSealFight()
    if not selectedEntry then return end
    local entry = selectedEntry
    local raceId = entry.raceId or 0
    if raceId <= 0 then return end
    if entry.done then return end
    if getSoulSealsBalance() < entry.soulsealPoints then return end

    local function yes()
        if g_game.sendSoulSealsAction then
            g_game.sendSoulSealsAction(raceId)
        end
        hideSoulSeals()
    end
    displayGeneralBox(tr('Confirm'),
        tr('Are you sure you want to fight "%s" for %d Soulseal points?', entry.name, entry.soulsealPoints),
        { { text = tr('Ok'),     callback = yes },
          { text = tr('Cancel'), callback = function() end } },
        yes, function() end)
end

-- Called by the bridge layer (taskhunting_otcv8_bridge.lua) when the server
-- replies to a Soul Seals request with the list of available creatures.
function onSoulSealsData(entries)
    rawEntries = {}
    for _, e in ipairs(entries or {}) do
        local n = normalize(e)
        -- Drop entries that the client couldn't resolve to a real monster.
        -- Without a g_things.getRaceData hit the normalize() falls back to
        -- "Race #235" / numeric ids — those bestiary stubs are dummies
        -- (test creatures, unused race ids the server registered) and
        -- shouldn't be shown to the player. We also require an outfit so the
        -- creature actually renders.
        local nameIsNumeric = tostring(n.name):match('^%d+$') ~= nil
        local nameIsRaceStub = tostring(n.name):lower():find('^race%s*#') ~= nil
        if n.raceId > 0
            and n.outfit
            and not nameIsNumeric
            and not nameIsRaceStub then
            rawEntries[#rawEntries + 1] = n
        end
    end
    if not soulSealWindow then
        showSoulSeals()
    else
        populateList()
        refreshBalanceLabel()
        if not soulSealWindow:isVisible() then
            soulSealWindow:show()
            soulSealWindow:raise()
            soulSealWindow:focus()
        end
    end
end

-- Called by the bridge whenever the player uses an obelisk in the world.
-- Requests the creature list from the server (raceId=0 → sendSoulSealsWindow
-- on the server side, see Servidor/src/server/network/protocol/protocolgame.cpp:2496).
function requestSoulSeals()
    if g_game.isOnline() and g_game.sendSoulSealsAction then
        g_game.sendSoulSealsAction(0)
    end
end

function isObeliskItemId(itemId)
    return OBELISK_ITEM_IDS[tonumber(itemId) or 0] == true
end

function onResourcesBalanceChange()
    if isSoulSealsOpen() then
        refreshBalanceLabel()
        rebuildSelectionPanel()
    end
end
