-- ─────────────────────────────────────────────────────────────────────────────
-- game_taskhunting / taskhunting_bounty.lua
-- Bounty board UI, talisman upgrades, points/reroll display
-- ─────────────────────────────────────────────────────────────────────────────

local OPT_SELECT_TASK   = 5
local OPT_CLAIM_REWARD  = 6
local OPT_UPGRADE_TALISMAN = 7

local CLAIM_NO_CLICK = 1
local CLAIM_CLICKED  = 2

-- ─────────────────────────────────────────────────────────────────────────────
-- Bounty task slots
-- ─────────────────────────────────────────────────────────────────────────────

function populateBountyTasks()
    if not taskBoardWindow or not cachedBountyTasks then return end

    local activeTask = nil
    local selectionTasks = {}
    for _, t in ipairs(cachedBountyTasks) do
        if t.claimState == CLAIM_NO_CLICK or t.claimState == CLAIM_CLICKED then
            activeTask = t
        else
            selectionTasks[#selectionTasks + 1] = t
        end
    end

    if activeTask then
        updateActiveTaskUI(true, activeTask)
    else
        updateActiveTaskUI(false, nil)
        for i = 1, 3 do
            local slot = taskBoardWindow:recursiveGetChildById('taskSlot' .. i)
            local task = selectionTasks[i]
            if slot and task then
                populateTaskSlot(slot, task, i)
            end
        end
    end

    local diffCombo = taskBoardWindow:recursiveGetChildById('difficultyComboBox')
    if diffCombo then
        local prevCallback = diffCombo.onOptionChange
        diffCombo.onOptionChange = nil
        diffCombo:setCurrentIndex(currentDifficulty + 1)
        diffCombo.onOptionChange = prevCallback
    end
end

function populateTaskSlot(slot, task, slotIndex)
    local monsterNameLabel = slot:getChildById('monsterName')
    if monsterNameLabel then
        monsterNameLabel:setText(getCreatureNameByRaceId(task.raceId) or ('Race #' .. task.raceId))
    end

    local banner = slot:getChildById('banner')
    if banner then
        if task.taskGrade == 2 then
            banner:setImageSource('/images/task_bounty/gold_banner')
        elseif task.taskGrade == 1 then
            banner:setImageSource('/images/task_bounty/silver_banner')
        else
            banner:setImageSource('/images/task_bounty/task_banner')
        end
    end

    local creatureSlot = slot:getChildById('creatureSlot')
    if creatureSlot then setCreatureByRaceId(creatureSlot, task.raceId) end

    local killProgress = slot:getChildById('killProgress')
    if killProgress then
        killProgress:setText(task.currentKills .. '/' .. task.requiredKills)
        killProgress:setColor('#dfdfdf')
    end

    local rewardItem1 = slot:getChildById('rewardItem1')
    if rewardItem1 then
        local r = rewardItem1:getChildById('rewardText')
        if r then r:setText(task.rewardExp .. ' XP') end
    end

    local rewardItem2 = slot:getChildById('rewardItem2')
    if rewardItem2 then
        local r = rewardItem2:getChildById('rewardText')
        if r then r:setText(task.rewardPoints .. ' ') end
    end

    local rewardItem3 = slot:getChildById('rewardItem3')
    if rewardItem3 then
        local r = rewardItem3:getChildById('rewardText')
        if r then r:setText('1 ') end
    end

    local selectBtn = slot:getChildById('selectTaskBtn')
    if selectBtn then
        selectBtn:show()
        selectBtn.onClick = function()
            taskSendAction(OPT_SELECT_TASK, task.taskIndex)
        end
    end
end

function updateActiveTaskUI(active, task)
    local slot1 = taskBoardWindow:recursiveGetChildById('taskSlot1')
    local slot2 = taskBoardWindow:recursiveGetChildById('taskSlot2')
    local slot3 = taskBoardWindow:recursiveGetChildById('taskSlot3')
    local rerollBtn = taskBoardWindow:recursiveGetChildById('rerollTasksBtn')
    local diffCombo = taskBoardWindow:recursiveGetChildById('difficultyComboBox')

    if active and task then
        if slot1 then slot1:hide() end
        if slot3 then slot3:hide() end
        if slot2 then
            slot2:show()
            slot2:setMarginLeft(306)

            local monsterName  = slot2:getChildById('monsterName')
            local creatureSlot = slot2:getChildById('creatureSlot')
            local killProgress = slot2:getChildById('killProgress')

            local name = getCreatureNameByRaceId(task.raceId) or ('Race #' .. task.raceId)
            if monsterName then monsterName:setText(name) end
            if creatureSlot then setCreatureByRaceId(creatureSlot, task.raceId) end

            local banner = slot2:getChildById('banner')
            if banner then
                if task.taskGrade == 2 then
                    banner:setImageSource('/images/task_bounty/gold_banner')
                elseif task.taskGrade == 1 then
                    banner:setImageSource('/images/task_bounty/silver_banner')
                else
                    banner:setImageSource('/images/task_bounty/task_banner')
                end
            end

            local isCompleted = (task.currentKills >= task.requiredKills) or (task.claimState == CLAIM_CLICKED)
            if killProgress then
                killProgress:setText(task.currentKills .. '/' .. task.requiredKills)
                killProgress:setColor('#dfdfdf')
            end

            local r1 = slot2:getChildById('rewardItem1')
            if r1 then local rt = r1:getChildById('rewardText'); if rt then rt:setText(task.rewardExp .. ' XP') end end
            local r2 = slot2:getChildById('rewardItem2')
            if r2 then local rt = r2:getChildById('rewardText'); if rt then rt:setText(task.rewardPoints .. ' ') end end
            local r3 = slot2:getChildById('rewardItem3')
            if r3 then local rt = r3:getChildById('rewardText'); if rt then rt:setText('1 ') end end

            local selectBtn = slot2:getChildById('selectTaskBtn')
            if selectBtn then selectBtn:hide() end

            local claimBtn = slot2:getChildById('claimRewardBtn')
            if isCompleted then
                if rerollBtn then rerollBtn:hide() end
                if claimBtn then
                    claimBtn:show()
                    claimBtn.onClick = function()
                        taskSendAction(OPT_CLAIM_REWARD)
                    end
                end
            else
                if rerollBtn then rerollBtn:show(); rerollBtn:setEnabled(rerollCoins > 0) end
                if claimBtn then claimBtn:hide() end
            end
        end

        activeTaskData = task
    else
        if slot2 then slot2:setMarginLeft(0) end
        if slot1 then slot1:show() end
        if slot2 then slot2:show() end
        if slot3 then slot3:show() end

        if slot2 then
            local selectBtn = slot2:getChildById('selectTaskBtn')
            if selectBtn then selectBtn:show() end
            local claimBtn = slot2:getChildById('claimRewardBtn')
            if claimBtn then claimBtn:hide() end
        end

        if rerollBtn then rerollBtn:show(); rerollBtn:setEnabled(rerollCoins > 0) end
        activeTaskData = nil
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Talisman UI
-- ─────────────────────────────────────────────────────────────────────────────

local TALISMAN_NAMES = {
    'Damage Against \nCreatures',
    'Life Leech',
    'More Loot',
    'Chance for Double \nBestiary Progress',
}
local TALISMAN_LABELS = { 'damageLabel', 'lifeLeechLabel', 'lootLabel', 'bestiaryLabel' }
local TALISMAN_BTNS   = { 'talismanBtn1', 'talismanBtn2', 'talismanBtn3', 'talismanBtn4' }
local TALISMAN_PANELS = { 'talismanInfoPanel1', 'talismanInfoPanel2', 'talismanInfoPanel3', 'talismanInfoPanel4' }
local TALISMAN_BASE   = { [0]=250, [1]=250, [2]=250, [3]=500 }

local function getTalismanBonusHundredths(level, pathIndex)
    local base = TALISMAN_BASE[pathIndex] or 250
    if pathIndex <= 2 then
        return math.min(base + level * 50, 5000)
    else
        return math.min(base + level * 100, 10000)
    end
end

local function formatBonus(hundredths)
    return string.format('%.2f%%', hundredths / 100)
end

function updateTalismanUI()
    if not taskBoardWindow or not cachedTalismans then return end

    for i = 1, 4 do
        local tier = cachedTalismans[i]
        if tier then
            local level   = tier.multiplier1
            local cost    = tier.bountyPointsToUpgrade
            local pathIdx = i - 1

            local currentBonus = getTalismanBonusHundredths(level, pathIdx)

            local lbl = taskBoardWindow:recursiveGetChildById(TALISMAN_LABELS[i])
            if lbl then
                lbl:setText(TALISMAN_NAMES[i] .. '\nCurrent: ' .. formatBonus(currentBonus))
            end

            local btn = taskBoardWindow:recursiveGetChildById(TALISMAN_BTNS[i])
            if btn then
                if tier.isActivedUpgrade == 0 or cost == 0 then
                    btn:setText('Upgrade (Max)')
                    btn:setEnabled(false)
                else
                    local afterBonus = getTalismanBonusHundredths(level + 1, pathIdx)
                    btn:setText('Upgrade (' .. formatBonus(afterBonus) .. ')')
                    btn:setEnabled(true)
                end
            end

            local panel = taskBoardWindow:recursiveGetChildById(TALISMAN_PANELS[i])
            if panel then
                local costLabel = panel:getChildById('pointsLabel')
                if costLabel then costLabel:setText(tostring(cost)) end
            end
        end
    end
end

function confirmTalismanUpgrade(pathIndex)
    taskSendAction(OPT_UPGRADE_TALISMAN, pathIndex)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Points / reroll display
-- ─────────────────────────────────────────────────────────────────────────────

function updatePlayerPoints()
    if not taskBoardWindow then return end

    local htpLabel = taskBoardWindow:recursiveGetChildById('pointsValue')
    if htpLabel then htpLabel:setText(formatPrice(g_game.getResource(ResourceHuntingTask))) end

    local bpLabel = taskBoardWindow:recursiveGetChildById('bountyPointsValue')
    if bpLabel then bpLabel:setText(formatPrice(g_game.getResource(ResourceBountyPoints))) end

    local soulsealsPanel = taskBoardWindow:recursiveGetChildById('infoPanel3')
    if soulsealsPanel then soulsealsPanel:setText(tostring(g_game.getResource(ResourceSoulseals))) end

    local shopItemsPanel = taskBoardWindow:recursiveGetChildById('shopItemsPanel')
    if shopItemsPanel and cachedShopData then
        local children = shopItemsPanel:getChildren()
        for i, offer in ipairs(cachedShopData) do
            local child = children[i]
            if child then
                if offer.offerType == 4 then
                    local canBuy = (offer.promoStatus == 0) and (offer.nextPrice > 0)
                    local isBought = (offer.nextPrice == 0)
                    applyBuyButtonState(child, canBuy, isBought)
                elseif offer.price then
                    local canBuy = (offer.status == 0)
                    local isBought = (offer.status == 4)
                    applyBuyButtonState(child, canBuy, isBought)
                end
            end
        end
    end
end

function updateRerollUI()
    if not taskBoardWindow then return end

    local coinsLabel = taskBoardWindow:recursiveGetChildById('rerollCoinsLabel')
    if coinsLabel then coinsLabel:setText(tostring(rerollCoins)) end

    local claimBtn = taskBoardWindow:recursiveGetChildById('claimDailyBtn')
    if claimBtn then
        if rerollMode == 0 then
            claimBtn:setEnabled(true)
            claimBtn:setText('Claim Daily')
        else
            claimBtn:setEnabled(false)
            claimBtn:setText(rerollMode == 2 and 'Limit Reached' or 'Claimed')
        end
    end

    local rerollBtn = taskBoardWindow:recursiveGetChildById('rerollTasksBtn')
    if rerollBtn then rerollBtn:setEnabled(rerollCoins > 0) end
end
