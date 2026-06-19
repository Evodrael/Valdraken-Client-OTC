-- ─────────────────────────────────────────────────────────────────────────────
-- game_taskhunting / taskhunting_weekly.lua
-- Weekly board UI
-- ─────────────────────────────────────────────────────────────────────────────

local OPT_WEEKLY_DELIVER           = 8
local OPT_WEEKLY_SELECT_DIFFICULTY = 9

local function truncateText(text, maxChars)
    if #text > maxChars then
        return text:sub(1, maxChars - 3) .. '...'
    end
    return text
end

function populateWeeklyTasks()
    if not taskBoardWindow or not cachedWeeklyData then return end
    local data = cachedWeeklyData

    local hasExpansion = (data.hasWeeklyTaskExpansion == 1)

    local unlockBtn = taskBoardWindow:recursiveGetChildById('unlockPermanentlyBtn')
    if unlockBtn then
        unlockBtn:setVisible(true)
        unlockBtn:setHeight(hasExpansion and 0 or 100)
        unlockBtn:setMarginBottom(hasExpansion and 0 or 12)
        unlockBtn:setOpacity(hasExpansion and 0 or 1)
        unlockBtn:setEnabled(not hasExpansion)
        unlockBtn:setPhantom(hasExpansion)
    end
    local unlockBtnDelivery = taskBoardWindow:recursiveGetChildById('unlockPermanentlyBtnDelivery')
    if unlockBtnDelivery then
        unlockBtnDelivery:setVisible(true)
        unlockBtnDelivery:setHeight(hasExpansion and 0 or 100)
        unlockBtnDelivery:setMarginBottom(hasExpansion and 0 or 12)
        unlockBtnDelivery:setOpacity(hasExpansion and 0 or 1)
        unlockBtnDelivery:setEnabled(not hasExpansion)
        unlockBtnDelivery:setPhantom(hasExpansion)
    end



    -- Difficulty selection overlay
    local diffWindow = taskBoardWindow:getChildById('difficultySelectWindow')
    if diffWindow then
        local needsSelection = (data.weeklyProgressFinished == 1)
        setDifficultyWindowVisible(needsSelection)

        if needsSelection then
            local maxKill     = hasExpansion and 9 or 6
            local maxDelivery = hasExpansion and 9 or 6
            -- data.completedKillTasks already counts Any Creature once it's finished
            -- (see ioweeklytasks.cpp:241-242 where the server increments completedKillTasks++
            -- when the Any Creature kill quota is reached). Adding anyDone here used to
            -- double-count it, making completedKill = 3 when the player actually finished 2.
            local completedKill     = data.completedKillTasks or 0
            local completedDelivery = data.completedDeliveryTasks or 0

            local killLbl = diffWindow:getChildById('weeklyKillTasksLabel')
            if killLbl then
                killLbl:setText('You have completed ' .. completedKill .. ' / ' .. maxKill .. ' kill tasks.')
            end

            local delivLbl = diffWindow:getChildById('weeklyDeliveryTasksLabel')
            if delivLbl then
                delivLbl:setText('You have completed ' .. completedDelivery .. ' / ' .. maxDelivery .. ' delivery tasks.')
            end

            local totalLbl = diffWindow:getChildById('weeklyTotalEarnedLabel')
            if totalLbl then
                totalLbl:setText('Total earned: ' .. (data.rewardHuntingTasksPoints or 0) .. ' and ' .. (data.rewardSoulseals or 0))
            end
        end
    end

    -- Weekly difficulty combo
    local weeklyDiffCombo = taskBoardWindow:recursiveGetChildById('weeklyDifficultyComboBox')
    if weeklyDiffCombo then
        weeklyDiffCombo.onOptionChange = function(widget, text)
            local map = { beginner=0, adept=1, expert=2, master=3 }
            local diff = map[text:lower()] or 0
            taskSendAction(OPT_WEEKLY_SELECT_DIFFICULTY, diff)
        end
    end

    -- Kill tasks
    local killTaskPanel = taskBoardWindow:recursiveGetChildById('killTaskPanel')
    if killTaskPanel then
        killTaskPanel:destroyChildren()

        local function applyKillTaskDone(widget, isDone)
            local cur      = widget:getChildById('killCurrent')
            local killOf   = widget:getChildById('killOf')
            local tot      = widget:getChildById('killTotal')
            local doneIcon = widget:getChildById('doneIcon')
            if cur      then cur:setVisible(not isDone) end
            if killOf   then killOf:setVisible(not isDone) end
            if tot      then tot:setVisible(not isDone) end
            if doneIcon then doneIcon:setVisible(isDone) end
        end

        local anyWidget = g_ui.createWidget('WeeklyKillTask', killTaskPanel)
        if anyWidget then
            local nameLabel = anyWidget:getChildById('monsterName')
            if nameLabel then nameLabel:setText(truncateText('Any Creature', 18)) end
            local anyDone = (data.anyCreatureCurrentKills or 0) >= (data.anyCreatureTotalKills or 1)
                            and (data.anyCreatureTotalKills or 0) > 0
            local cur = anyWidget:getChildById('killCurrent')
            if cur then cur:setText(tostring(data.anyCreatureCurrentKills or 0)) end
            local tot = anyWidget:getChildById('killTotal')
            if tot then tot:setText(tostring(data.anyCreatureTotalKills or 0)) end
            local anyImg = anyWidget:getChildById('anyCreatureImg')
            if anyImg then anyImg:setVisible(true) end
            applyKillTaskDone(anyWidget, anyDone)
        end

        for _, task in ipairs(data.killTasks or {}) do
            local widget = g_ui.createWidget('WeeklyKillTask', killTaskPanel)
            if widget then
                local nameLabel = widget:getChildById('monsterName')
                if nameLabel then
                    local fullName = getCreatureNameByRaceId(task.raceId) or ('Race #' .. task.raceId)
                    local truncated = truncateText(fullName, 18)
                    nameLabel:setText(truncated)
                    if truncated ~= fullName then nameLabel:setTooltip(fullName) end
                end
                local isDone = task.currentKills >= task.totalKills and task.totalKills > 0
                local cur = widget:getChildById('killCurrent')
                if cur then cur:setText(tostring(task.currentKills)) end
                local tot = widget:getChildById('killTotal')
                if tot then tot:setText(tostring(task.totalKills)) end
                local icon = widget:getChildById('creatureIcon')
                if icon then setCreatureByRaceId(icon, task.raceId) end
                applyKillTaskDone(widget, isDone)
            end
        end
    end

    -- Delivery tasks
    local delivPanel = taskBoardWindow:recursiveGetChildById('deliveryTaskPanel')
    if delivPanel then
        delivPanel:destroyChildren()
        for _, task in ipairs(data.deliveryTasks or {}) do
            local widget = g_ui.createWidget('WeeklyDeliveryTask', delivPanel)
            if widget then
                local nameLabel = widget:getChildById('monsterName')
                if nameLabel then
                    local itemName = task.itemId and g_things.getThingType(task.itemId, ThingCategoryItem) and
                                     g_things.getThingType(task.itemId, ThingCategoryItem):getName() or ('Item #' .. (task.itemId or 0))
                    local truncated = truncateText(itemName, 18)
                    nameLabel:setText(truncated)
                    if truncated ~= itemName then nameLabel:setTooltip(itemName) end
                end
                local iconWidget = widget:getChildById('itemIcon')
                local itemWidget = iconWidget and iconWidget:getChildById('itemDisplay')
                if itemWidget and task.itemId then itemWidget:setItemId(task.itemId) end

                local isDelivered = (task.delivered == 1)
                local available   = task.availableOrCollected or 0
                local total       = task.totalItems or 0
                local current     = isDelivered and total or available
                local hasEnough   = available >= total and total > 0

                local cur      = widget:getChildById('killCurrent')
                local killOf   = widget:getChildById('killOf')
                local tot      = widget:getChildById('killTotal')
                local doneIcon = widget:getChildById('doneIcon')
                if isDelivered then
                    if cur      then cur:setVisible(false) end
                    if killOf   then killOf:setVisible(false) end
                    if tot      then tot:setVisible(false) end
                    if doneIcon then doneIcon:setVisible(true) end
                else
                    if cur    then cur:setVisible(true); cur:setText(tostring(current)); cur:setColor(hasEnough and '#00ff00' or '#d13b3b') end
                    if killOf then killOf:setVisible(true) end
                    if tot    then tot:setVisible(true); tot:setText(tostring(total)) end
                    if doneIcon then doneIcon:setVisible(false) end
                end

                local delivBtn = widget:getChildById('deliverBtn')
                if delivBtn then
                    if isDelivered then
                        delivBtn:setVisible(false)
                    else
                        delivBtn:setVisible(true)
                        delivBtn:setEnabled(hasEnough)
                        local idx = task.index
                        delivBtn.onClick = function()
                            taskSendAction(OPT_WEEKLY_DELIVER, idx)
                        end
                    end
                end
            end
        end
    end

    -- Progress bar
    local infoPanel = taskBoardWindow:recursiveGetChildById('weeklyProgressInfoPanel')
    if infoPanel then
        local maxKill     = hasExpansion and 9 or 6
        local maxDelivery = hasExpansion and 9 or 6
        local totalTasks  = maxKill + maxDelivery
        -- data.completedKillTasks already includes Any Creature (server increments it
        -- automatically when the quota is reached). See comment in the difficulty branch above.
        local completedKill     = data.completedKillTasks or 0
        local completedDelivery = data.completedDeliveryTasks or 0
        local completedTotal    = completedKill + completedDelivery

        local bar = infoPanel:getChildById('weeklyProgressBar')
        if bar then
            local panelWidth = infoPanel:getWidth() - 2
            -- Segment breakpoints in pixels matching separator positions (4/8/12/16/18 tasks)
            local segPx   = { 0, 126, 255, 384, 513, panelWidth }
            local segTask = { 0,   4,   8,  12,  16,  totalTasks }
            local barWidth = 0
            if totalTasks > 0 then
                local t = math.min(completedTotal, totalTasks)
                for i = 1, #segTask - 1 do
                    if t <= segTask[i + 1] then
                        local frac = (t - segTask[i]) / (segTask[i + 1] - segTask[i])
                        barWidth = segPx[i] + math.floor(frac * (segPx[i + 1] - segPx[i]))
                        break
                    end
                end
            end
            bar:setWidth(math.max(0, barWidth))
            bar:setImageSource('/game_cyclopedia/images/bestiary/progressbar-orange-small')
            -- The user wants the Weekly Progress bar to always read as a
            -- "this is your accumulating progress" green, regardless of how
            -- many tasks are still pending. The asset is a 1-pixel dark
            -- orange swatch, so tint it with setImageColor to force the
            -- color we want on top of the stretched texture.
            bar:setImageColor('#5fd54a')
        end
    end

    -- Reward labels
    local rewardHTP = taskBoardWindow:recursiveGetChildById('weeklyRewardHTP')
    if rewardHTP then rewardHTP:setText(tostring(data.rewardHuntingTasksPoints or 0)) end
    local rewardSeals = taskBoardWindow:recursiveGetChildById('weeklyRewardSeals')
    if rewardSeals then rewardSeals:setText(tostring(data.rewardSoulseals or 0)) end

    -- Reward info icon tooltips
    do
        -- data.completedKillTasks already includes Any Creature (server bumps the counter
        -- when the kill quota is reached, see ioweeklytasks.cpp). Summing anyDone again
        -- inflated the kill count and produced wrong HTP/Soulseal numbers in the tooltip.
        local completedKill     = data.completedKillTasks or 0
        local completedDelivery = data.completedDeliveryTasks or 0
        local totalCompleted    = completedKill + completedDelivery

        -- difficultyMultiplier is the difficulty level: 0=Beginner(25), 1=Adept(50), 2=Expert(100), 3=Master(110)
        local diffLevel  = data.difficultyMultiplier or 0
        local htpPerKill = ({ [0]=25, [1]=50, [2]=100, [3]=110 })[diffLevel] or 25
        local htpPerDeliv = 75

        -- Task-count multiplier: 0-4=x1, 5-8=x2, 9-12=x3, 13-16=x5, 17-18=x8
        local countMultiplier = 1
        if     totalCompleted >= 17 then countMultiplier = 8
        elseif totalCompleted >= 13 then countMultiplier = 5
        elseif totalCompleted >= 9  then countMultiplier = 3
        elseif totalCompleted >= 5  then countMultiplier = 2
        end

        local baseHTP  = completedKill * htpPerKill + completedDelivery * htpPerDeliv
        local totalHTP = baseHTP * countMultiplier

        local htpTooltip = 'Hunting Task Points:\n\n'
            .. '  ' .. completedKill      .. ' * ' .. htpPerKill  .. ' (from Kill Tasks)\n'
            .. '+ ' .. completedDelivery  .. ' * ' .. htpPerDeliv .. ' (from Delivery Tasks)\n'
            .. string.rep('-', 27) .. '\n'
            .. '* ' .. countMultiplier .. ' (from completing Tasks)\n'
            .. '= ' .. totalHTP .. ' Hunting Task Points'

        local totalSeals = data.rewardSoulseals or 0

        local sealsTooltip = 'Soulseals:\n\n'
            .. '  ' .. completedKill  .. ' * 1 (from Kill Tasks)\n'
            .. '+ ' .. completedDelivery .. ' * 1 (from Delivery Tasks)\n'
            .. string.rep('-', 27) .. '\n'
            .. '* ' .. countMultiplier .. ' (from completing Tasks)\n'
            .. '= ' .. totalSeals .. ' Soulseals'

        local infoIcon1 = taskBoardWindow:recursiveGetChildById('weeklyRewardInfoIcon1')
        if infoIcon1 then infoIcon1:setTooltip(htpTooltip) end

        local infoIcon2 = taskBoardWindow:recursiveGetChildById('weeklyRewardInfoIcon2')
        if infoIcon2 then infoIcon2:setTooltip('You receive 1 Soulseal for each completed task.\n\nSoulseals can be used in the Soulpit. Click the obelisk there, then your character to open a menu where you can select a creature you want to challenge on your own.') end
    end

    -- Countdown ate o reset semanal. O servidor (Winter Update 2025) envia o
    -- timestamp absoluto do proximo reset (segunda-feira no server-save); o parser
    -- guarda em data.resetTimestamp e ja pre-calcula data.remainingDays.
    -- Regra pedida: sempre mostrar DIAS; so quando faltar menos de 24h mostrar HORAS.
    local daysLabel = taskBoardWindow:recursiveGetChildById('weeklyDaysRemainingLabel')
    if daysLabel then
        local resetTs = data.resetTimestamp or 0
        local secs = resetTs > 0 and (resetTs - os.time()) or 0

        if resetTs > 0 and secs > 0 and secs < 86400 then
            -- Menos de 24h: mostrar horas (minimo 1h para nao exibir "0 hour(s)").
            local hours = math.max(1, math.ceil(secs / 3600))
            daysLabel:setText(hours .. ' hour(s) remaining')
        else
            -- Caso geral: dias. Prefere o valor pre-calculado do parser; se nao
            -- houver timestamp, cai para remainingDays (ou 0).
            local days = data.remainingDays or 0
            if resetTs > 0 and secs > 0 then
                days = math.ceil(secs / 86400)
            end
            daysLabel:setText(days .. ' day(s) remaining')
        end
    end

    -- XP reward label. The server publishes the per-task XP via
    -- maxExperience (kill task) and maxDeliveryExperience (delivery task) in
    -- the weekly header (see protocolgameparse.cpp:4882-4883). The Luminaris
    -- aliases `killTaskRewardExp` / `deliveryTaskRewardExp` are also honored
    -- for backward compatibility with mods that still set them.
    local xpLabel = taskBoardWindow:recursiveGetChildById('weeklyXpRewardLabel')
    if xpLabel then
        local killXp  = data.killTaskRewardExp or data.maxExperience or 0
        local delivXp = data.deliveryTaskRewardExp or data.maxDeliveryExperience or 0
        local function formatCommas(n)
            local s = tostring(math.floor(n))
            return s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
        end
        xpLabel:setText('Each kill task will reward you with ' .. formatCommas(killXp) ..
            ' XP and each delivery task will reward you with ' .. formatCommas(delivXp) .. ' XP.')
    end
end
