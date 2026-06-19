-- ─────────────────────────────────────────────────────────────────────────────
-- game_taskhunting / taskhunting_otcv8_bridge.lua
--
-- Adapter that translates OTCV8's native task-board events into the
-- "Luminaris-shaped" events the rest of this module expects. Keeps the
-- upstream Luminaris game_taskhunting code unchanged on the .lua side and
-- lets the OTCV8 C++ parser stay untouched.
--
-- OTCV8 (src/client/protocolgameparse.cpp) fires:
--   onBountyTaskData(headerMap, monsterData, talismanData)
--   onBountyPreferredData(preferredSlotData, _, allRaceIds)
--   onWeeklyTaskData(headerMap, monsterData, itemData)
--   onTaskHuntingShopData(shopData)
--   onResourceBalance(resourceType, amount)
--
-- Luminaris taskhunting.lua expects:
--   onTaskBoardBounty({ tasks, talismans, preferredSlots, rerollCoins,
--                       rerollMode, selectedDifficulty })
--   onTaskBoardWeekly({ weeklyProgressFinished, hasWeeklyTaskExpansion, ... })
--   onTaskBoardShop({ offers = { ... } })
--   onResourcesBalanceChange(value, oldValue, type)
--   ResourceHuntingTask / ResourceBountyPoints / ResourceSoulseals globals
-- ─────────────────────────────────────────────────────────────────────────────

-- Mirror of Otc::ResourceTypes_t (src/client/const.h) for the names the
-- Luminaris module reads. These three are the only ones the task hunting
-- module references.
ResourceHuntingTask  = ResourceHuntingTask  or 50  -- RESOURCE_TASK_HUNTING
ResourceBountyPoints = ResourceBountyPoints or 86  -- RESOURCE_BOUNTY_POINTS
ResourceSoulseals    = ResourceSoulseals    or 87  -- RESOURCE_SOULSEALS

-- Polyfill: Luminaris reads `g_game.getResource(type)`; OTCV8 only exposes
-- `LocalPlayer:getResourceBalance(type)`. We install a thin wrapper on the
-- g_game singleton so taskhunting_bounty/weekly/shop can call it unmodified.
if not g_game.getResource then
    function g_game.getResource(resourceType)
        local player = g_game.getLocalPlayer()
        if not player or not player.getResourceBalance then return 0 end
        return player:getResourceBalance(resourceType) or 0
    end
end

-- Cached pieces of the bounty payload (OTCV8 sends header+monsters+talismans
-- and preferred slots in two separate events; Luminaris expects one merged
-- `data` table — we buffer until both pieces have arrived at least once).
local cachedBountyHeader     = nil
local cachedBountyMonsters   = nil
local cachedBountyTalismans  = nil
local cachedBountyPreferred  = {}
local lastReportedRerollMode = nil

local function rerollModeFromHeader(header)
    -- Luminaris uses 0=claimable, 1=timer running, 2=limit reached. OTCV8's
    -- header only carries `claimDaily` (1 if a free reroll is available);
    -- we infer the rest from rerollPoints availability.
    if header.claimDaily == 1 then return 0 end
    return (header.rerollPoints and header.rerollPoints > 0) and 1 or 2
end

local function fireBounty()
    if not cachedBountyHeader or not cachedBountyMonsters or not cachedBountyTalismans then
        return
    end

    local data = {
        tasks              = cachedBountyMonsters,
        talismans          = cachedBountyTalismans,
        preferredSlots     = cachedBountyPreferred,
        rerollCoins        = cachedBountyHeader.rerollPoints or 0,
        rerollMode         = rerollModeFromHeader(cachedBountyHeader),
        selectedDifficulty = (cachedBountyHeader.difficulty or 1) - 1, -- OTCV8 is 1..4
    }
    lastReportedRerollMode = data.rerollMode

    signalcall(g_game.onTaskBoardBounty, data)
end

-- OTCV8 only exposes the talisman's *current bonus value* (in hundredths of a
-- %). Luminaris's taskhunting_bounty.lua needs the *level* (an integer 0..N)
-- to compute the next-step bonus. Invert the formula:
--   pathIndex 0..2: bonus = 250 + level*50
--   pathIndex 3   : bonus = 500 + level*100
local function levelFromTalismanValue(currentValue, pathIndex)
    if pathIndex <= 2 then
        return math.max(0, math.floor(((currentValue or 250) - 250) / 50))
    end
    return math.max(0, math.floor(((currentValue or 500) - 500) / 100))
end

local function aliasTalismanFields(talismans)
    for i, t in ipairs(talismans or {}) do
        local pathIdx = i - 1
        t.multiplier1            = t.multiplier1            or levelFromTalismanValue(t.currentValue, pathIdx)
        t.bountyPointsToUpgrade  = t.bountyPointsToUpgrade  or t.upgradeCost or 0
        -- Luminaris reads `isActivedUpgrade` (typo preserved upstream); OTCV8
        -- emits `isActiveUpgrade`. Mirror to both spellings.
        if t.isActivedUpgrade == nil then
            t.isActivedUpgrade = t.isActiveUpgrade or 0
        end
    end
end

-- OTCV8's protocolgameparse.cpp ships monsters/tasks with these fields:
--   { taskIndex, raceId, currentKills, totalKills, rewardXp, rewardPoints,
--     rewardReroll, rarity, isActive, isCompleted }
-- The Luminaris taskhunting_*.lua scripts read different names. Alias them in
-- place so we don't have to touch the upstream Luminaris code.
local function aliasBountyMonsterFields(monster)
    monster.requiredKills = monster.requiredKills or monster.totalKills or 0
    monster.rewardExp     = monster.rewardExp     or monster.rewardXp   or 0
    monster.taskGrade     = monster.taskGrade     or monster.rarity     or 0
    -- claimState in taskhunting_bounty.lua:
    --   1 = CLAIM_NO_CLICK (active task, kill progress visible)
    --   2 = CLAIM_CLICKED  (completed, ready to claim reward)
    --   other (0/nil)      = selection mode (one of 3 choices)
    if monster.claimState == nil then
        if monster.isCompleted == 1 then
            monster.claimState = 2
        elseif monster.isActive == 1 then
            monster.claimState = 1
        else
            monster.claimState = 0
        end
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- Prey-tracker integration
-- The prey.otui mini-window has a `bountySlot1` and a `weeklySlot1` (+ label
-- and separator pair). We populate them whenever bounty / weekly data arrives.
-- ────────────────────────────────────────────────────────────────────────────

local function getPreyTrackerWidget()
    if modules.game_prey and modules.game_prey.preyTracker then
        return modules.game_prey.preyTracker
    end
    return nil
end

local function getActiveBountyTask(monsters)
    for _, task in ipairs(monsters or {}) do
        if task.claimState == 2 or task.claimState == 3 then
            return task
        end
    end
    -- No "active" task: fall back to the first one with progress so the
    -- tracker still shows something useful.
    for _, task in ipairs(monsters or {}) do
        if (task.currentKills or 0) > 0 then return task end
    end
    return (monsters or {})[1]
end

local function updatePreyTrackerBounty(monsters)
    local tracker = getPreyTrackerWidget()
    if not tracker then return end
    local slot = tracker:recursiveGetChildById('bountySlot1')
    if not slot then return end

    local task = getActiveBountyTask(monsters)
    local creature = slot:getChildById('creature')
    local noCreature = slot:getChildById('noCreature')
    local nameLabel = slot:getChildById('creatureName')
    local progress = slot:getChildById('progress')

    if not task or not task.raceId or task.raceId == 0 then
        if creature then creature:hide() end
        if noCreature then noCreature:show() end
        if nameLabel then nameLabel:setText('Inactive') end
        if progress then progress:setPercent(0) end
        slot:setTooltip('No active Bounty Task.\n\nClick to open the Task Board.')
    else
        local raceData = g_things.getRaceData(task.raceId)
        local name = (raceData and raceData.name) or ('Race #' .. task.raceId)
        if creature and raceData and raceData.outfit then
            creature:setOutfit(raceData.outfit)
            creature:show()
        end
        if noCreature then noCreature:hide() end
        if nameLabel then nameLabel:setText(name) end
        local current = task.currentKills or 0
        local required = task.requiredKills or task.totalKills or 0
        local percent = (required > 0) and math.min(100, (current / required) * 100) or 0
        if progress then
            progress:setPercent(percent)
            progress:setBackgroundColor(percent >= 100 and '#00C222' or '#C28400')
        end
        slot:setTooltip(string.format('Bounty Task: %s\nProgress: %d/%d kills\n\nClick to open the Task Board.',
            name, current, required))
    end
    slot.onClick = function()
        if modules.game_taskhunting and modules.game_taskhunting.toggle then
            if not (modules.game_taskhunting.taskBoardWindow and modules.game_taskhunting.taskBoardWindow:isVisible()) then
                modules.game_taskhunting.toggle()
            end
            if modules.game_taskhunting.selectTab then modules.game_taskhunting.selectTab('bounty') end
        end
    end
end

-- Holds the dynamically-created TaskBoardWeeklyTrack widgets after the first
-- one (which is `weeklySlot1` from prey.otui). We destroy + recreate them on
-- every update so kill counts / monsters refresh cleanly.
local dynamicWeeklySlots = {}

local function destroyDynamicWeeklySlots()
    for _, w in ipairs(dynamicWeeklySlots) do
        if w and not w:isDestroyed() then w:destroy() end
    end
    dynamicWeeklySlots = {}
end

local function populateWeeklySlot(slot, m)
    local creature   = slot:getChildById('creature')
    local noCreature = slot:getChildById('noCreature')
    local nameLabel  = slot:getChildById('creatureName')
    local progress   = slot:getChildById('progress')

    local raceId = m.raceId or 0
    if raceId > 0 then
        local raceData = g_things.getRaceData(raceId)
        if creature and raceData and raceData.outfit then
            creature:setOutfit(raceData.outfit)
            creature:show()
        end
        if noCreature then noCreature:hide() end
        if nameLabel then nameLabel:setText((raceData and raceData.name) or ('Race #' .. raceId)) end
    else
        if creature then creature:hide() end
        if noCreature then noCreature:show() end
        if nameLabel then nameLabel:setText('Any Creature') end
    end

    local current = m.current or 0
    local total = m.total or 0
    local percent = (total > 0) and math.min(100, (current / total) * 100) or 0
    if progress then
        progress:setPercent(percent)
        progress:setBackgroundColor(percent >= 100 and '#00C222' or '#C28400')
    end

    local label = (raceId > 0 and (g_things.getRaceData(raceId) and g_things.getRaceData(raceId).name)) or 'Any Creature'
    slot:setTooltip(string.format('Weekly Task: %s\nProgress: %d/%d\n\nClick to open the Task Board.', label, current, total))
    slot.onClick = function()
        if modules.game_taskhunting and modules.game_taskhunting.toggle then
            if not (modules.game_taskhunting.taskBoardWindow and modules.game_taskhunting.taskBoardWindow:isVisible()) then
                modules.game_taskhunting.toggle()
            end
            if modules.game_taskhunting.selectTab then modules.game_taskhunting.selectTab('weekly') end
        end
    end
end

local function updatePreyTrackerWeekly(weeklyData)
    local tracker = getPreyTrackerWidget()
    if not tracker then return end
    local firstSlot = tracker:recursiveGetChildById('weeklySlot1')
    local label  = tracker:recursiveGetChildById('weeklyTaskLabel')
    local sepa   = tracker:recursiveGetChildById('weeklyTaskSeparator')
    if not firstSlot then return end

    -- Clear any leftover dynamic slots from the previous render.
    destroyDynamicWeeklySlots()

    local monsters = weeklyData and weeklyData.monsters or {}
    local activeMonsters = {}
    for _, m in ipairs(monsters) do
        if (m.total or 0) > 0 then
            activeMonsters[#activeMonsters + 1] = m
        end
    end

    local hasAny = #activeMonsters > 0
    if label then label:setVisible(hasAny) end
    if sepa  then sepa:setVisible(hasAny) end
    firstSlot:setVisible(hasAny)
    if not hasAny then return end

    -- First task → the existing static slot. The rest get fresh widgets
    -- inserted into the same parent (MiniWindowContents) right after the
    -- static one, so the layout stays compact and ordered.
    populateWeeklySlot(firstSlot, activeMonsters[1])

    local parent = firstSlot:getParent()
    if not parent then return end
    local insertIndex = parent:getChildIndex(firstSlot)
    for i = 2, #activeMonsters do
        local newSlot = g_ui.createWidget('TaskBoardWeeklyTrack', parent)
        newSlot:setMarginTop(2)
        newSlot:setMarginLeft(3)
        if insertIndex and insertIndex >= 0 then
            insertIndex = insertIndex + 1
            parent:moveChildToIndex(newSlot, insertIndex)
        end
        newSlot:setVisible(true)
        populateWeeklySlot(newSlot, activeMonsters[i])
        dynamicWeeklySlots[#dynamicWeeklySlots + 1] = newSlot
    end

    -- Resize the mini-window so all sections (Prey, Bounty, Weekly with N
    -- monsters) fit without clipping. Without this the prey.lua init caps
    -- the content at 169px and weekly rows past the second are hidden.
    -- Layout per section (approx in px):
    --   Prey Creatures: header(13) + sep(3) + 3 slots × 24 = 88
    --   Bounty:         header(13+5) + sep(3) + 1 slot(19) = 40
    --   Weekly:         header(13+5) + sep(3) + N slots×21 = 21 + 21*N
    local extraSections = 88 + 40
    local weeklyHeight  = 21 + 21 * #activeMonsters
    local desired = extraSections + weeklyHeight + 20 -- safety margin

    -- Raise the maximum so the user can drag the window bigger if needed.
    -- Keep a low minimum so they can still shrink it. setContentHeight then
    -- sets the actual current size so all weekly rows are visible right away.
    if tracker.setContentMaximumHeight then
        tracker:setContentMaximumHeight(math.max(600, desired))
    end
    if tracker.setContentMinimumHeight then
        tracker:setContentMinimumHeight(47)
    end
    if tracker.setContentHeight then
        tracker:setContentHeight(math.max(169, desired))
    end
end

local function onBountyTaskData(header, monsters, talismans)
    monsters = monsters or {}
    for _, m in ipairs(monsters) do aliasBountyMonsterFields(m) end
    aliasTalismanFields(talismans)

    cachedBountyHeader    = header or {}
    cachedBountyMonsters  = monsters
    cachedBountyTalismans = talismans or {}
    fireBounty()

    -- If the kill counts changed we ALSO want to fire the "kill-update"
    -- lightweight callback so the bounty tab refreshes the progress bars
    -- without rebuilding the talisman/preferred UI.
    signalcall(g_game.onTaskBoardKillUpdate, cachedBountyMonsters)

    -- Update the prey-tracker bounty slot.
    updatePreyTrackerBounty(cachedBountyMonsters)
end

-- OTCV8 toPreferredSlotMap fields:
--   slot, locked, preferred, unwanted, price
-- Luminaris taskhunting_preferred.lua reads:
--   preferredRaceId, unwantedRaceId, activedList, slot, price
local function aliasPreferredSlots(slots)
    for _, s in ipairs(slots or {}) do
        s.preferredRaceId = s.preferredRaceId or s.preferred or 0
        s.unwantedRaceId  = s.unwantedRaceId  or s.unwanted  or 0
        -- locked=1 means locked → activedList = 0; locked=0 → unlocked = 1.
        if s.activedList == nil then
            s.activedList = (s.locked and s.locked == 0) and 1 or 0
        end
    end
end

local function onBountyPreferredData(preferred, _unused, _allRaceIds)
    cachedBountyPreferred = preferred or {}
    aliasPreferredSlots(cachedBountyPreferred)
    -- Re-fire if we already have the rest so the preferred panel refreshes.
    if cachedBountyHeader and cachedBountyMonsters and cachedBountyTalismans then
        fireBounty()
    end
end

local function onWeeklyTaskData(header, monsters, items)
    print(string.format(
        '[TaskBoard] onWeeklyTaskData received: monsters=%d items=%d weeklyProgressFinished=%s difficulty=%s completedKill=%s totalSlots=%s maxXP=%s maxDelivXP=%s',
        monsters and #monsters or -1,
        items and #items or -1,
        tostring(header.weeklyProgressFinished),
        tostring(header.difficulty),
        tostring(header.completedKillTasks),
        tostring(header.totalTaskSlots),
        tostring(header.maxExperience),
        tostring(header.maxDeliveryExperience)))

    -- The server sends `weeklyProgressFinished` explicitly (see
    -- protocolgame.cpp:9553); prefer that flag when present. Otherwise infer
    -- the "needs difficulty pick" state from the data: either the player has
    -- completed all kill tasks for the current week, or they have no
    -- difficulty selected yet (no kill tasks AND no delivery tasks).
    --
    -- Crucial: if the payload already carries kill or delivery tasks, the
    -- player has an ACTIVE week — never show the difficulty picker, regardless
    -- of what maxExperience/maxDeliveryExperience report. Earlier versions
    -- triggered the picker on every server restart because the reward-exp
    -- fields can briefly read 0 between load and the first send, even though
    -- the kill-task list was intact on the server. Trusting the populated
    -- task lists fixes that.
    local monstersCount = monsters and #monsters or 0
    local itemsCount    = items   and #items   or 0
    local hasActiveTasks = monstersCount > 0 or itemsCount > 0

    local needsDiffPick = false
    local serverFlag = tonumber(header.weeklyProgressFinished)
    if serverFlag and serverFlag == 1 then
        needsDiffPick = true
    elseif not hasActiveTasks then
        local total = header.totalTaskSlots or 0
        if total > 0 and (header.completedKillTasks or 0) >= total then
            needsDiffPick = true
        elseif (header.maxExperience or 0) == 0 and (header.maxDeliveryExperience or 0) == 0 then
            needsDiffPick = true
        end
    end

    -- The Luminaris weekly module (`taskhunting_weekly.lua`) reads task lists
    -- through `data.killTasks` / `data.deliveryTasks` and the "Any Creature"
    -- counters through top-level `data.anyCreature*Kills` fields. The OTCV8
    -- parser puts everything into a flat `monsters` array (with raceId=0 as
    -- the Any-Creature entry) and a `items` array using `current`/`total`
    -- field names. Translate here so the upstream module renders correctly.
    local anyCurrent, anyTotal = 0, 0
    local killTasks = {}
    for _, m in ipairs(monsters or {}) do
        if (m.raceId or 0) == 0 then
            anyCurrent = m.current or 0
            anyTotal   = m.total or 0
        else
            killTasks[#killTasks + 1] = {
                raceId       = m.raceId or 0,
                currentKills = m.current or 0,
                totalKills   = m.total or 0,
                state        = m.state or 0,
            }
        end
    end

    local deliveryTasks = {}
    for _, it in ipairs(items or {}) do
        deliveryTasks[#deliveryTasks + 1] = {
            index                = it.slotIndex or 0,
            itemId               = it.itemId or 0,
            totalItems           = it.total or 0,
            availableOrCollected = it.current or 0,
            delivered            = it.claimed or 0,
            state                = it.state or 0,
        }
    end

    -- difficultyMultiplier is the raw 0..3 value; the parser stores it as
    -- header.difficulty in the 1..4 range, so subtract 1 to recover it.
    -- When there are no generated tasks yet, header.difficulty is 0.
    local diffMultiplier = math.max(0, (header.difficulty or 0) - 1)

    -- HTP/Soulseal reward totals shown in the weekly summary. The server
    -- sends them as pointsEarned/soulsealsEarned (see protocolgame.cpp:9565
    -- on the server). Expose under the names the weekly module reads.
    local rewardHTP      = header.pointsEarned or 0
    local rewardSoulseal = header.soulsealsEarned or 0

    local data = {
        -- Header fields the Luminaris module reads directly:
        weeklyProgressFinished      = needsDiffPick and 1 or 0,
        hasWeeklyTaskExpansion      = header.totalTaskSlots and header.totalTaskSlots > 6 and 1 or 0,
        difficulty                  = (header.difficulty or 1) - 1,
        difficultyMultiplier        = diffMultiplier,
        currentPlayerLevel          = header.currentPlayerLevel,
        remainingDays               = header.remainingDays,
        resetTimestamp              = header.resetTimestamp,
        totalTaskSlots              = header.totalTaskSlots,
        maxExperience               = header.maxExperience,
        maxDeliveryExperience       = header.maxDeliveryExperience,
        completedKillTasks          = header.completedKillTasks,
        completedDeliveryTasks      = header.completedDeliveryTasks,
        pointsEarned                = header.pointsEarned,
        soulsealsEarned             = header.soulsealsEarned,
        extraSlot                   = header.extraSlot,

        -- Translated task lists in the shape Luminaris expects:
        anyCreatureCurrentKills     = anyCurrent,
        anyCreatureTotalKills       = anyTotal,
        killTasks                   = killTasks,
        deliveryTasks               = deliveryTasks,
        rewardHuntingTasksPoints    = rewardHTP,
        rewardSoulseals             = rewardSoulseal,

        -- Keep the raw lists too for any consumer that still reads them.
        monsters                    = monsters,
        items                       = items,
    }
    signalcall(g_game.onTaskBoardWeekly, data)

    -- Update the prey-tracker weekly slot.
    updatePreyTrackerWeekly(data)
end

-- OTCV8's toShopItemMap (in src/client/protocolgameparse.cpp) emits these
-- string-typed fields: id, offerType, title, description, price, bought,
-- lookType, lookAddons, itemId, maxPurchases, currentPurchases, nextCost.
--
-- The Luminaris taskhunting_shop.lua expects these aliases:
--   serverIndex, name, price, nextPrice, promoStatus, looktypeOrItemId,
--   addon, status, offerType, description.
--
-- We re-key the entries in place so the upstream module reads them naturally.
local function aliasShopOffer(offer, idx)
    -- coerce everything string→number where appropriate
    offer.offerType  = tonumber(offer.offerType) or 0
    offer.price      = tonumber(offer.price) or 0
    offer.nextPrice  = offer.nextPrice  or tonumber(offer.nextCost) or 0
    offer.bought     = tonumber(offer.bought) or 0
    offer.lookType   = tonumber(offer.lookType) or 0
    offer.lookAddons = tonumber(offer.lookAddons) or 0
    offer.itemId     = tonumber(offer.itemId) or 0
    offer.id         = tonumber(offer.id) or (idx - 1)

    offer.name = offer.name or offer.title or ''
    offer.serverIndex = offer.serverIndex or offer.id
    -- O parser C++ (protocolgameparse.cpp:5411/5439) ja COLAPSA o status bruto do
    -- servidor (4=BOUGHT) num flag 0/1 `bought`. Re-expandimos para os codigos de
    -- status que a UI espera: 4 = comprado, 0 = disponivel. (Antes copiava o flag
    -- cru 0/1 p/ status, entao status==4 nunca batia e o item ficava com "Buy".)
    offer.status = offer.status or (offer.bought == 1 and 4 or 0)
    offer.promoStatus = offer.promoStatus or (offer.bought == 1 and 4 or 0)
    offer.addon = offer.addon or offer.lookAddons

    -- Pick the right "look" id depending on offer type:
    --   ITEM/ITEM_DOUBLE → itemId
    --   MOUNT/OUTFIT     → lookType
    if offer.looktypeOrItemId == nil then
        if offer.offerType == 1 or offer.offerType == 2 then
            offer.looktypeOrItemId = offer.lookType
        else
            offer.looktypeOrItemId = offer.itemId
        end
    end
end

local function onTaskHuntingShopData(shopData)
    shopData = shopData or {}
    for i, offer in ipairs(shopData) do aliasShopOffer(offer, i) end
    signalcall(g_game.onTaskBoardShop, { offers = shopData })
end

-- OTCV8 fires onResourceBalance(type, amount); Luminaris listens to
-- onResourcesBalanceChange(value, oldValue, type).
local lastResourceValue = {}
local function onResourceBalance(resourceType, amount)
    local old = lastResourceValue[resourceType]
    lastResourceValue[resourceType] = amount
    signalcall(g_game.onResourcesBalanceChange, amount, old or 0, resourceType)
    -- Forward to the Soul Seals modal so its balance label / fight button
    -- reflect the new value in real-time. The soulseal script defines this
    -- function in the same module env, so a direct reference works.
    local mod = modules.game_taskhunting
    if mod and mod.onResourcesBalanceChange then
        mod.onResourcesBalanceChange()
    end
end

-- Forward the server-side Soul Seals creature list (opcode 0xBA, decoded by
-- parseTaskHuntingBasicData → g_game.onSoulsealsData) to the modal handler
-- defined in taskhunting_soulseal.lua.
local function onSoulsealsDataForward(entries)
    print(string.format('[SoulSeals.bridge] onSoulsealsData received: %d entries',
        type(entries) == 'table' and #entries or -1))
    local mod = modules.game_taskhunting
    if mod and mod.onSoulSealsData then
        mod.onSoulSealsData(entries)
    end
end

-- Soulpit Obelisk → request the picker. We hook both g_game.onUse (right-click
-- use) and onUseWith (use-with target = self). Server replies with the list
-- via opcode 0xBA (see parseSoulSeals on the server side).
local function isObelisk(id)
    local mod = modules.game_taskhunting
    if mod and mod.isObeliskItemId then
        return mod.isObeliskItemId(id)
    end
    -- Fallback constants in case the soulseal script hasn't initialized yet.
    return id == 47367 or id == 47379
end

local function callRequestSoulSeals()
    local mod = modules.game_taskhunting
    if mod and mod.requestSoulSeals then
        print('[SoulSeals.bridge] obelisk used → requesting list')
        mod.requestSoulSeals()
    end
end

local function onUse(_pos, itemId, _stackpos, _subtype)
    if isObelisk(itemId) then
        callRequestSoulSeals()
    end
end

local function onUseWith(_pos, itemId, target, _subtype)
    local targetId = target and target.getId and target:getId() or 0
    if isObelisk(itemId) or isObelisk(targetId) then
        callRequestSoulSeals()
    end
end

-- Connect on script load; the rest of game_taskhunting will register its own
-- handlers for `onTaskBoardBounty/Weekly/Shop` etc. and they'll receive the
-- translated payloads above.
connect(g_game, {
    onBountyTaskData          = onBountyTaskData,
    onBountyPreferredData     = onBountyPreferredData,
    onWeeklyTaskData          = onWeeklyTaskData,
    onTaskHuntingShopData     = onTaskHuntingShopData,
    onResourceBalance         = onResourceBalance,
    onSoulsealsData           = onSoulsealsDataForward,
    onUse                     = onUse,
    onUseWith                 = onUseWith,
})

-- Expose disconnect for the module's terminate(). Stored as a sandbox-global
-- so taskhunting.lua's terminate() can call it without import boilerplate.
function disconnectOTCV8Bridge()
    disconnect(g_game, {
        onBountyTaskData          = onBountyTaskData,
        onBountyPreferredData     = onBountyPreferredData,
        onWeeklyTaskData          = onWeeklyTaskData,
        onTaskHuntingShopData     = onTaskHuntingShopData,
        onResourceBalance         = onResourceBalance,
        onSoulsealsData           = onSoulsealsDataForward,
        onUse                     = onUse,
        onUseWith                 = onUseWith,
    })
    cachedBountyHeader    = nil
    cachedBountyMonsters  = nil
    cachedBountyTalismans = nil
    cachedBountyPreferred = {}
    lastResourceValue     = {}
end
