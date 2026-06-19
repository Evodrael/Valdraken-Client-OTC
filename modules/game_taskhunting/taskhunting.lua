-- ─────────────────────────────────────────────────────────────────────────────
-- game_taskhunting / taskhunting.lua
-- Globals, constants, lifecycle (init / terminate / online / offline / toggle)
-- ─────────────────────────────────────────────────────────────────────────────

taskBoardWindow = nil
currentShopCategory = "trophies"
currentDifficulty = 0      -- 0=Beginner, 1=Adept, 2=Expert, 3=Master
rerollCoins = 0
rerollMode = 1             -- 0=claimable, 1=timer running, 2=limit reached
activeTaskData = nil
currentTab = 'weekly'

-- Server-provided data (populated by C++ callbacks, shared across sub-modules)
cachedBountyTasks    = nil
cachedTalismans      = nil
cachedPreferredLists = nil
cachedWeeklyData     = nil
cachedShopData       = nil

-- Client→server option bytes (used in this file)
local OPT_OPEN_BOUNTY              = 0
local OPT_OPEN_WEEKLY              = 1
local OPT_CHANGE_DIFFICULTY        = 2
local OPT_REROLL_TASKS             = 3
local OPT_CLAIM_DAILY              = 4
local OPT_WEEKLY_SELECT_DIFFICULTY = 9
local OPT_OPEN_SHOP                = 10


-- ─────────────────────────────────────────────────────────────────────────────
-- C++ → Lua callbacks (connected in init, disconnected in terminate)
-- ─────────────────────────────────────────────────────────────────────────────

local function onResourcesBalanceChange(value, oldValue, type)
    if type == ResourceHuntingTask or type == ResourceBountyPoints or type == ResourceSoulseals then
        updatePlayerPoints()
    end
    if type == ResourceBountyPoints and updateClearButtons then
        updateClearButtons()
    end
    -- saldo de HTP mudou (comprou item / ganhou pontos): re-renderiza a loja p/ atualizar
    -- quais Buy ficam clicaveis e quais precos ficam em vermelho.
    if type == ResourceHuntingTask and currentTab == 'shop' and cachedShopData and populateShop then
        populateShop()
    end
end

local function onServerError(code, message)
    if code == 0x14 and taskBoardWindow and taskBoardWindow:isVisible() then
        if message:find("Rookgaard") then
            if currentTab == 'bounty' then
                local bountyDither = taskBoardWindow:recursiveGetChildById('bountyDitherPattern')
                local weeklyDither = taskBoardWindow:recursiveGetChildById('weeklyDitherPattern')
                if bountyDither then bountyDither:setVisible(true) end
                if weeklyDither then weeklyDither:setVisible(true) end

                local mb
                local onOk = function()
                    mb:ok()
                    local bd = taskBoardWindow:recursiveGetChildById('bountyDitherPattern')
                    local wd = taskBoardWindow:recursiveGetChildById('weeklyDitherPattern')
                    if bd then bd:setVisible(false) end
                    if wd then wd:setVisible(false) end
                    selectTab('weekly')
                end
                mb = UIMessageBox.display(tr('Task Board'), message, { {
                    text = 'Ok',
                    callback = onOk
                } }, onOk)
            end
        else
            displayInfoBox(tr('Task Board'), message)
        end
    end
end

-- Returns true when any of the cached task lists holds at least one active
-- task (kill or delivery). Drives the side-button highlight ring so the
-- player can see at a glance that there is unredeemed Task Board progress.
local function hasActiveTasks()
    if type(cachedBountyTasks) == "table" then
        for _, t in ipairs(cachedBountyTasks) do
            if (t.requiredKills or 0) > 0 then return true end
        end
    end
    if type(cachedWeeklyData) == "table" then
        if (cachedWeeklyData.anyCreatureTotalKills or 0) > 0 then return true end
        if type(cachedWeeklyData.killTasks) == "table" and #cachedWeeklyData.killTasks > 0 then return true end
        if type(cachedWeeklyData.deliveryTasks) == "table" and #cachedWeeklyData.deliveryTasks > 0 then return true end
    end
    return false
end

local function refreshSideButtonHighlight()
    if modules.game_sidebuttons and modules.game_sidebuttons.setTaskBoardHighlight then
        modules.game_sidebuttons.setTaskBoardHighlight(hasActiveTasks())
    end
end

local function onTaskBoardBounty(data)
    cachedBountyTasks    = data.tasks
    cachedTalismans      = data.talismans
    cachedPreferredLists = data.preferredSlots
    rerollCoins          = data.rerollCoins
    rerollMode           = data.rerollMode
    currentDifficulty    = data.selectedDifficulty

    if updateAdditionalSlots then updateAdditionalSlots() end
    updateRerollUI()
    populateBountyTasks()
    updatePlayerPoints()
    updateTalismanUI()
    refreshSideButtonHighlight()
end

-- Lightweight callback: only kill counters changed (fired on every kill).
local function onTaskBoardKillUpdate(tasks)
    cachedBountyTasks = tasks
    updatePlayerPoints()
    if not taskBoardWindow then return end
    for _, task in ipairs(tasks) do
        if task.claimState == 1 or task.claimState == 2 then
            local slot = taskBoardWindow:recursiveGetChildById('taskSlot2')
            if slot then
                local kp = slot:getChildById('killProgress')
                if kp then kp:setText(task.currentKills .. '/' .. task.requiredKills) end
                if task.currentKills >= task.requiredKills then
                    local claimBtn = slot:getChildById('claimRewardBtn')
                    local rerollBtn = taskBoardWindow:recursiveGetChildById('rerollTasksBtn')
                    if claimBtn then claimBtn:show() end
                    if rerollBtn then rerollBtn:hide() end
                end
            end
            return
        end
    end
    local selIdx = 0
    for _, task in ipairs(tasks) do
        selIdx = selIdx + 1
        local slot = taskBoardWindow:recursiveGetChildById('taskSlot' .. selIdx)
        if slot then
            local kp = slot:getChildById('killProgress')
            if kp then kp:setText(task.currentKills .. '/' .. task.requiredKills) end
        end
    end
end

local function onTaskBoardWeekly(data)
    cachedWeeklyData = data
    populateWeeklyTasks()
    refreshSideButtonHighlight()
    if currentTab == 'weekly' then
        local needsDiff = (cachedWeeklyData.weeklyProgressFinished == 1)
        print(string.format('[TaskBoard] onTaskBoardWeekly: showing diffWindow=%s weeklyProgressFinished=%s currentTab=%s',
            tostring(needsDiff), tostring(cachedWeeklyData.weeklyProgressFinished), tostring(currentTab)))
        setDifficultyWindowVisible(needsDiff)
    end
end

local function onTaskBoardShop(data)
    local expansionJustBought = false
    if cachedShopData and cachedWeeklyData and (cachedWeeklyData.hasWeeklyTaskExpansion ~= 1) then
        for i, offer in ipairs(data.offers) do
            local prev = cachedShopData[i]
            if offer.status == 4 and prev and prev.status ~= 4 then
                expansionJustBought = true
                break
            end
        end
    end

    cachedShopData = data.offers
    updatePlayerPoints()
    populateShop()

    if expansionJustBought then
        taskSendAction(OPT_OPEN_WEEKLY)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Module lifecycle
-- ─────────────────────────────────────────────────────────────────────────────

function init()
    taskBoardWindow = g_ui.displayUI('taskhunting.otui')
    taskBoardWindow:hide()

    -- Difficulty selection overlay window
    local diffWin = g_ui.createWidget('NewMainWindow', taskBoardWindow)
    diffWin:setId('difficultySelectWindow')
    diffWin:setWidth(320)
    diffWin:setHeight(345)
    diffWin:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    diffWin:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    diffWin:setText(tr('Weekly Progress'))
    diffWin:setDraggable(false)

    local backdrop = g_ui.createWidget('UIWidget', diffWin)
    backdrop:setId('weeklyBackdrop')
    backdrop:setImageSource('/images/task_bounty/backdrop_weeklyresults')
    backdrop:setWidth(175)
    backdrop:setHeight(66)
    backdrop:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    backdrop:addAnchor(AnchorTop, 'parent', AnchorTop)
    backdrop:setMarginTop(41)

    local killLabel = g_ui.createWidget('Label', diffWin)
    killLabel:setId('weeklyKillTasksLabel')
    killLabel:setWidth(290)
    killLabel:setHeight(32)
    killLabel:setFont('verdana-11px-monochrome')
    killLabel:setColor('#dfdfdf')
    killLabel:setTextAlign(AlignCenter)
    killLabel:setTextWrap(true)
    killLabel:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    killLabel:addAnchor(AnchorTop, 'weeklyBackdrop', AnchorBottom)
    killLabel:setMarginTop(10)

    local delivLabel = g_ui.createWidget('Label', diffWin)
    delivLabel:setId('weeklyDeliveryTasksLabel')
    delivLabel:setWidth(290)
    delivLabel:setHeight(16)
    delivLabel:setFont('verdana-11px-monochrome')
    delivLabel:setColor('#dfdfdf')
    delivLabel:setTextAlign(AlignCenter)
    delivLabel:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    delivLabel:addAnchor(AnchorTop, 'weeklyKillTasksLabel', AnchorBottom)
    delivLabel:setMarginTop(4)

    local totalLabel = g_ui.createWidget('Label', diffWin)
    totalLabel:setId('weeklyTotalEarnedLabel')
    totalLabel:setWidth(290)
    totalLabel:setHeight(16)
    totalLabel:setFont('verdana-11px-monochrome')
    totalLabel:setColor('#dfdfdf')
    totalLabel:setTextAlign(AlignCenter)
    totalLabel:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    totalLabel:addAnchor(AnchorTop, 'weeklyDeliveryTasksLabel', AnchorBottom)
    totalLabel:setMarginTop(15)

    local selectLabel = g_ui.createWidget('Label', diffWin)
    selectLabel:setId('weeklySelectDiffLabel')
    selectLabel:setWidth(290)
    selectLabel:setHeight(16)
    selectLabel:setFont('verdana-11px-monochrome')
    selectLabel:setColor('#dfdfdf')
    selectLabel:setTextAlign(AlignCenter)
    selectLabel:setText(tr('Select the difficulty for your next tasks.'))
    selectLabel:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    selectLabel:addAnchor(AnchorTop, 'weeklyTotalEarnedLabel', AnchorBottom)
    selectLabel:setMarginTop(10)

    local difficulties = { {0, 'Beginner'}, {1, 'Adept'}, {2, 'Expert'}, {3, 'Master'} }
    local prevId = 'weeklySelectDiffLabel'
    for i, diff in ipairs(difficulties) do
        local diffValue, diffName = diff[1], diff[2]
        local btn = g_ui.createWidget('Button', diffWin)
        btn:setId('diffBtn' .. diffName)
        btn:setWidth(108)
        btn:setText(tr(diffName))
        btn:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
        btn:addAnchor(AnchorTop, prevId, AnchorBottom)
        btn:setMarginTop(i == 1 and 10 or 5)
        btn.onClick = function()
            taskSendAction(OPT_WEEKLY_SELECT_DIFFICULTY, diffValue)
        end
        prevId = btn:getId()
    end

    diffWin:setVisible(false)

    -- Tab buttons
    taskBoardWindow:recursiveGetChildById('bountyTasksBtn').onClick = function() selectTab('bounty') end
    taskBoardWindow:recursiveGetChildById('weeklyTasksBtn').onClick = function() selectTab('weekly') end
    taskBoardWindow:recursiveGetChildById('shopBtn').onClick        = function() selectTab('shop') end

    -- Difficulty ComboBox
    local diffCombo = taskBoardWindow:recursiveGetChildById('difficultyComboBox')
    if diffCombo then
        diffCombo:addOption('Beginner')
        diffCombo:addOption('Adept')
        diffCombo:addOption('Expert')
        diffCombo:addOption('Master')
        diffCombo:setCurrentIndex(1)
        diffCombo.onOptionChange = function(widget, text)
            local map = { beginner=0, adept=1, expert=2, master=3 }
            local newDiff = map[text:lower()] or 0
            if newDiff ~= currentDifficulty then
                currentDifficulty = newDiff
                if g_game.isOnline() then
                    taskSendAction(OPT_CHANGE_DIFFICULTY, newDiff)
                end
            end
        end
    end

    -- Unlock permanently buttons
    local function openStoreExpansion()
        if taskBoardWindow then taskBoardWindow:hide() end
        if modules.game_store then
            modules.game_store.showStoreWindow()
            g_game.openStore()
            scheduleEvent(function()
                g_game.requestStoreOffers('Useful things', '', 0, 1)
            end, 300)
        end
    end

    local function setupUnlockBtn(btn)
        if not btn then return end
        btn.onClick = openStoreExpansion
        local icon = btn:getChildById('tibiaCoinIcon')
        if icon then
            btn.onMousePress = function() icon:setMarginRight(66) icon:setMarginTop(0) end
            btn.onMouseRelease = function() icon:setMarginRight(67) icon:setMarginTop(1) end
        end
    end

    setupUnlockBtn(taskBoardWindow:recursiveGetChildById('unlockPermanentlyBtn'))
    setupUnlockBtn(taskBoardWindow:recursiveGetChildById('unlockPermanentlyBtnDelivery'))

    -- Reroll button
    local rerollBtn = taskBoardWindow:recursiveGetChildById('rerollTasksBtn')
    if rerollBtn then
        rerollBtn.onClick = function()
            if rerollCoins <= 0 then return end
            taskSendAction(OPT_REROLL_TASKS)
        end
    end

    -- Claim daily
    local claimDailyBtn = taskBoardWindow:recursiveGetChildById('claimDailyBtn')
    if claimDailyBtn then
        claimDailyBtn.onClick = function()
            taskSendAction(OPT_CLAIM_DAILY)
        end
    end

    -- Talisman upgrade buttons
    local talismanPaths = { 'talismanBtn1', 'talismanBtn2', 'talismanBtn3', 'talismanBtn4' }
    for idx, btnId in ipairs(talismanPaths) do
        local btn = taskBoardWindow:recursiveGetChildById(btnId)
        if btn then
            local pathIndex = idx - 1
            btn.onClick = function()
                confirmTalismanUpgrade(pathIndex)
            end
        end
    end

    selectTab('weekly')

    connect(g_game, {
        onGameStart              = online,
        onGameEnd                = offline,
        onServerError            = onServerError,
        onTaskBoardBounty        = onTaskBoardBounty,
        onTaskBoardKillUpdate    = onTaskBoardKillUpdate,
        onTaskBoardWeekly        = onTaskBoardWeekly,
        onTaskBoardShop          = onTaskBoardShop,
        onResourcesBalanceChange = onResourcesBalanceChange,
    })

    if g_game.isOnline() then
        online()
    end
end

function terminate()
    disconnect(g_game, {
        onGameStart              = online,
        onGameEnd                = offline,
        onServerError            = onServerError,
        onTaskBoardBounty        = onTaskBoardBounty,
        onTaskBoardKillUpdate    = onTaskBoardKillUpdate,
        onTaskBoardWeekly        = onTaskBoardWeekly,
        onTaskBoardShop          = onTaskBoardShop,
        onResourcesBalanceChange = onResourcesBalanceChange,
    })

    if taskBoardWindow then
        taskBoardWindow:destroy()
        taskBoardWindow = nil
    end
end

function online()
    -- Eager-fetch bounty + weekly data on login so the prey-tracker mini-window
    -- (which mirrors the active bounty/weekly task) shows the current state
    -- without forcing the player to open the Task Board first. The bridge
    -- (`taskhunting_otcv8_bridge.lua`) calls updatePreyTrackerBounty /
    -- updatePreyTrackerWeekly when the server response arrives.
    scheduleEvent(function()
        if g_game.isOnline() then
            taskSendAction(OPT_OPEN_BOUNTY)
            taskSendAction(OPT_OPEN_WEEKLY)
        end
    end, 500)
end

function offline()
    activeTaskData    = nil
    cachedBountyTasks = nil
    cachedTalismans   = nil
    cachedWeeklyData  = nil
    cachedShopData    = nil

    if taskBoardWindow then
        setDifficultyWindowVisible(false)
        taskBoardWindow:hide()
        if modules.game_sidebuttons and modules.game_sidebuttons.setButtonVisible then
            modules.game_sidebuttons.setButtonVisible('button_taskhunting', false)
        end
    end
end

-- Keeps the "Task Hunting" sidebutton's pressed state in sync with the
-- task-board window. Called from toggle/hide and from the window's @onEscape.
local function syncSideButton(open)
    if modules.game_sidebuttons and modules.game_sidebuttons.setButtonVisible then
        modules.game_sidebuttons.setButtonVisible('button_taskhunting', open)
    end
end

function toggle()
    if not taskBoardWindow then return end

    if taskBoardWindow:isVisible() then
        taskBoardWindow:hide()
        syncSideButton(false)
    else
        -- Open window first, then request data — same pattern as game_wheel
        selectTab('weekly')
        taskBoardWindow:show()
        taskBoardWindow:raise()
        taskBoardWindow:focus()
        syncSideButton(true)
        taskSendAction(OPT_OPEN_BOUNTY)
        taskSendAction(OPT_OPEN_WEEKLY)
    end
end

-- Window can be dismissed by Esc / clicking the close button on the window's
-- chrome; this entrypoint hides + syncs the sidebutton in one call.
function closeTaskBoard()
    if not taskBoardWindow then return end
    if taskBoardWindow:isVisible() then
        taskBoardWindow:hide()
    end
    setDifficultyWindowVisible(false)
    syncSideButton(false)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Tab switching
-- ─────────────────────────────────────────────────────────────────────────────

function setDifficultyWindowVisible(visible)
    local diffWindow = taskBoardWindow:getChildById('difficultySelectWindow')
    if diffWindow then diffWindow:setVisible(visible) end
    local dither = taskBoardWindow:recursiveGetChildById('weeklyDitherPattern')
    if dither then dither:setVisible(visible) end
end

function selectTab(tab)
    if not taskBoardWindow then return end
    currentTab = tab

    local bountyBtn = taskBoardWindow:recursiveGetChildById('bountyTasksBtn')
    local weeklyBtn = taskBoardWindow:recursiveGetChildById('weeklyTasksBtn')
    local shopBtn   = taskBoardWindow:recursiveGetChildById('shopBtn')
    local bountyTab = taskBoardWindow:recursiveGetChildById('bountyTab')
    local weeklyTab = taskBoardWindow:recursiveGetChildById('weeklyTab')
    local shopTab   = taskBoardWindow:recursiveGetChildById('shopTab')

    if tab == 'bounty' then
        bountyBtn:setChecked(true); weeklyBtn:setChecked(false); shopBtn:setChecked(false)
        if bountyTab then bountyTab:setVisible(true) end
        if weeklyTab then weeklyTab:setVisible(false) end
        if shopTab then shopTab:setVisible(false) end
        setDifficultyWindowVisible(false)
        if taskBoardWindow:isVisible() then taskSendAction(OPT_OPEN_BOUNTY) end
    elseif tab == 'weekly' then
        bountyBtn:setChecked(false); weeklyBtn:setChecked(true); shopBtn:setChecked(false)
        if bountyTab then bountyTab:setVisible(false) end
        if weeklyTab then weeklyTab:setVisible(true) end
        if shopTab then shopTab:setVisible(false) end
        if taskBoardWindow:isVisible() then taskSendAction(OPT_OPEN_WEEKLY) end
        populateWeeklyTasks()
        local needsDiff = cachedWeeklyData ~= nil and (cachedWeeklyData.weeklyProgressFinished == 1)
        setDifficultyWindowVisible(needsDiff)
    elseif tab == 'shop' then
        bountyBtn:setChecked(false); weeklyBtn:setChecked(false); shopBtn:setChecked(true)
        if bountyTab then bountyTab:setVisible(false) end
        if weeklyTab then weeklyTab:setVisible(false) end
        if shopTab then shopTab:setVisible(true) end
        setDifficultyWindowVisible(false)
        if taskBoardWindow:isVisible() then taskSendAction(OPT_OPEN_SHOP) end
    end
end
