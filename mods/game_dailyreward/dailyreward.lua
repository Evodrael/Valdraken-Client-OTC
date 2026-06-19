dailyRewardWindow = nil
confirmRewardWindow = nil
selectRewardWindow = nil

local instantTokens = 0
local jokerTokens = 0
local rewardAmount = 0
local totalOz = 0
local freeCap = 0
local globalMessage
local gameFromShrine
local dailyRewardTimerEvent = nil
local dailyRewardTimerDeadline = nil
local dailyRewardTimerMode = nil
local dailyRewardCollectionState = nil
local lastOpenRewardWallArgs = nil
local staleRefreshAttempts = 0
local STALE_REFRESH_MAX_ATTEMPTS = 2

local DAY_SECONDS = 24 * 60 * 60
-- Mirrors the server's DailyReward.serverTimeThreshold (Servidor/data/modules/
-- scripts/daily_reward/daily_reward.lua:79) = 25h. The previous 20h was a
-- legacy CIP cycle that made every relog clamp the countdown to "20:00:00"
-- because the server's freshly-issued nextRewardTime (lastServerSave + 25h)
-- was always greater than the client cap.
local NEXT_REWARD_SECONDS = 25 * 60 * 60
local SERVER_STREAK_OFFSET = 7
local DAILY_REWARD_COLLECTED = 0
local DAILY_REWARD_NOTCOLLECTED = 1
local RESTING_BONUS_NAMES = {
  [1] = "Hit Points Regeneration",
  [2] = "Mana Points Regeneration",
  [3] = "Stamina Points Regeneration",
  [4] = "Double Hit Points Regeneration",
  [5] = "Double Mana Points Regeneration",
  [6] = "Soul Points Regeneration",
}

local function getResourceValue(resourceType)
  local player = g_game.getLocalPlayer()
  return player and player:getResourceValue(resourceType) or 0
end

local function nowSeconds()
  local ok, time = pcall(os.time)
  if ok and type(time) == "number" and time > 0 then
    return time
  end
  return g_clock.seconds()
end

local function getRemainingSeconds(time)
  time = tonumber(time) or 0
  if time <= 0 then
    return 0
  end

  if time > DAY_SECONDS * 365 then
    return math.max(0, time - nowSeconds())
  end

  return time
end

local function getDisplayRewardSeconds(time)
  local seconds = getRemainingSeconds(time)
  return math.min(seconds, DAY_SECONDS)
end

local function getNextRewardSeconds(time)
  local seconds = getRemainingSeconds(time)
  return math.min(seconds, NEXT_REWARD_SECONDS)
end

local function formatDuration(seconds)
  seconds = math.max(0, tonumber(seconds) or 0)
  local hours = math.floor(seconds / 3600)
  local minutes = math.floor((seconds % 3600) / 60)
  return string.format("%02d:%02d", hours, minutes)
end

local function updateDurationProgress(progress, seconds, totalSeconds)
  local total = tonumber(totalSeconds) or DAY_SECONDS
  seconds = math.min(math.max(0, tonumber(seconds) or 0), total)
  progress:setText(formatDuration(seconds))
  progress:setValue(seconds, 0, total)
  progress:setMinimum(0)
  progress:updateBackground()
end

local function stopDailyRewardTimer()
  if dailyRewardTimerEvent then
    removeEvent(dailyRewardTimerEvent)
    dailyRewardTimerEvent = nil
  end
end

local function getDailyRewardTimerStorageKey(mode)
  local player = g_game.getLocalPlayer()
  local name = player and player:getName() or "unknown"
  name = name:lower():gsub("[^%w_%-]", "_")
  mode = tostring(mode or "default"):lower():gsub("[^%w_%-]", "_")
  return "daily_reward_timer_deadline_" .. name .. "_" .. mode
end

local function loadDailyRewardTimerDeadline(mode)
  local deadline = tonumber(g_settings.getNumber(getDailyRewardTimerStorageKey(mode), 0)) or 0
  if deadline > nowSeconds() then
    return deadline
  end
  return nil
end

local function saveDailyRewardTimerDeadline(mode, deadline)
  g_settings.set(getDailyRewardTimerStorageKey(mode), math.floor(tonumber(deadline) or 0))
end

local function startDailyRewardTimer(seconds, progressWidgets, mode, onExpire, totalSeconds)
  stopDailyRewardTimer()

  totalSeconds = tonumber(totalSeconds) or DAY_SECONDS
  seconds = math.min(math.max(0, tonumber(seconds) or 0), totalSeconds)
  if seconds <= 0 then
    dailyRewardTimerMode = nil
    dailyRewardTimerDeadline = nil
    saveDailyRewardTimerDeadline(mode, 0)
    for _, progress in ipairs(progressWidgets) do
      if progress and not progress:isDestroyed() then
        updateDurationProgress(progress, 0, totalSeconds)
      end
    end
    return
  end

  local now = nowSeconds()
  local cachedDeadline = loadDailyRewardTimerDeadline(mode)
  if dailyRewardTimerDeadline and dailyRewardTimerMode == mode then
    cachedDeadline = cachedDeadline and math.min(cachedDeadline, dailyRewardTimerDeadline) or dailyRewardTimerDeadline
  end

  if cachedDeadline then
    local cachedSeconds = math.max(0, cachedDeadline - now)
    if cachedSeconds > 0 then
      seconds = math.min(seconds, cachedSeconds)
    end
  end

  dailyRewardTimerMode = mode
  dailyRewardTimerDeadline = now + seconds
  saveDailyRewardTimerDeadline(mode, dailyRewardTimerDeadline)

  local function refreshTimer()
    local remaining = math.max(0, dailyRewardTimerDeadline - nowSeconds())
    for _, progress in ipairs(progressWidgets) do
      if progress and not progress:isDestroyed() then
        updateDurationProgress(progress, remaining, totalSeconds)
      end
    end

    if remaining <= 0 then
      stopDailyRewardTimer()
      saveDailyRewardTimerDeadline(mode, 0)
      dailyRewardTimerDeadline = nil
      dailyRewardTimerMode = nil
      if onExpire then
        onExpire()
      end
    end
  end

  refreshTimer()
  dailyRewardTimerEvent = cycleEvent(refreshTimer, 1000)
end

local function getDisplayStreak(dayStreakLevel, currentIndex)
  dayStreakLevel = tonumber(dayStreakLevel) or 0
  currentIndex = tonumber(currentIndex) or 0

  if dayStreakLevel >= SERVER_STREAK_OFFSET then
    return dayStreakLevel - SERVER_STREAK_OFFSET
  end

  return dayStreakLevel
end

local function buildRestingAreaMessage(streak)
  streak = tonumber(streak) or 0
  if streak < 1 then
    return "Resting Area (no active bonus)"
  end

  local bonuses = {}
  table.insert(bonuses, streak >= 4 and RESTING_BONUS_NAMES[4] or RESTING_BONUS_NAMES[1])
  if streak >= 2 then
    table.insert(bonuses, streak >= 5 and RESTING_BONUS_NAMES[5] or RESTING_BONUS_NAMES[2])
  end
  if streak >= 3 then
    table.insert(bonuses, RESTING_BONUS_NAMES[3])
  end
  if streak >= 6 then
    table.insert(bonuses, RESTING_BONUS_NAMES[6])
  end

  return "Active Resting Area Bonuses:\n" .. table.concat(bonuses, ",\n") .. "."
end

local function refreshRestingAreaCondition()
  if ConditionsHUD and ConditionsHUD.notifierRestingAreaState and ConditionsHUD.zone ~= nil then
    local streak = tonumber(DailyRewardDisplayStreak) or 0
    ConditionsHUD.dailyRewardDisplayStreak = streak
    ConditionsHUD.dailyRewardRestingAreaMessage = DailyRewardRestingAreaMessage
    ConditionsHUD:notifierRestingAreaState(ConditionsHUD.zone, streak >= 1 and 1 or 0, DailyRewardRestingAreaMessage)
  end
end

local function resetDailyRewardRestingAreaState()
  DailyRewardDisplayStreak = nil
  DailyRewardRestingAreaMessage = nil
  dailyRewardTimerDeadline = nil
  dailyRewardTimerMode = nil
  if ConditionsHUD then
    ConditionsHUD.dailyRewardDisplayStreak = nil
    ConditionsHUD.dailyRewardRestingAreaMessage = nil
  end
end

local function ensureBonusWidget(parent, id, setup)
  local widget = parent:recursiveGetChildById(id)
  if widget then
    return widget
  end

  widget = g_ui.createWidget('UIWidget', parent)
  widget:setId(id)
  widget:setPhantom(true)
  setup(widget)
  return widget
end

local function setupBonusBanner(banner)
  banner:breakAnchors()
  banner:setSize(tosize("31 31"))
  banner:addAnchor(AnchorBottom, "parent", AnchorBottom)
  banner:addAnchor(AnchorRight, "parent", AnchorRight)
  banner:setMarginBottom(2)
  banner:setMarginRight(2)
  banner:setImageSource("/images/dailyreward/icon-banner-days")
  banner:setTextOffset("0 7")
  banner:setTextAlign(AlignCenter)
  banner:setColor("#f8f0c6")
  banner:setFont("$var-cip-font")
end

local function updateRestingAreaBonuses(streak)
  streak = tonumber(streak) or 0

  for i = 0, 5 do
    local bonusBox = dailyRewardWindow.miniWindowBonuses.preyBonus:recursiveGetChildById("bonusBox_" .. i)
    local bonusIcon = dailyRewardWindow.miniWindowBonuses.preyBonus:recursiveGetChildById("bonusStreak_" .. i)
    if bonusBox and bonusIcon then
      local bonusLevel = i + 1
      local unlocked = streak >= bonusLevel
      bonusIcon:setVisible(true)

      local overlay = ensureBonusWidget(bonusBox, "bonusOverlay_" .. i, function(widget)
        widget:setSize(tosize("64 64"))
        widget:addAnchor(AnchorTop, "parent", AnchorTop)
        widget:addAnchor(AnchorLeft, "parent", AnchorLeft)
        widget:setMargin(1)
        widget:setImageSource("/images/ui/rawpattern")
      end)

      local banner = ensureBonusWidget(bonusBox, "bonusBanner_" .. i, function(widget)
        setupBonusBanner(widget)
      end)
      setupBonusBanner(banner)

      overlay:setVisible(not unlocked)
      banner:setVisible(not unlocked)
      banner:setText(tostring(bonusLevel))
    end
  end
end

local function updateResourceLabels()
  instantTokens = getResourceValue(ResourceReward)
  jokerTokens = getResourceValue(ResourceJokerReward)

  if dailyRewardWindow then
    dailyRewardWindow.instantAcess.instantLabel:setText(instantTokens)
    dailyRewardWindow.jokers.jokersLabel:setText(jokerTokens)
  end

  if dailyRewardHistory then
    dailyRewardHistory.instantAcess.instantLabel:setText(instantTokens)
    dailyRewardHistory.jokers.jokersLabel:setText(jokerTokens)
  end
end

local function getConfirmMessage()
  if type(globalMessage) == "string" and not string.empty(globalMessage) then
    return globalMessage
  end

  if not gameFromShrine then
    updateResourceLabels()
    if instantTokens > 0 then
      return string.format("Remember! You can always collect your daily reward for free by visiting a reward shrine!\n\nYou currently own %dx Instant Reward Access. Do you really want to use one to claim your daily reward now?", instantTokens)
    end
    return "Remember! You can always collect your daily reward for free by visiting a reward shrine!\nYou do not have an Instant Reward Access.\nVisit the store to buy more!"
  end

  return "Are you sure you want to claim this reward?"
end

function init()
  dailyRewardWindow = g_ui.displayUI('dailyreward')
  dailyRewardWindow:hide()

  g_ui.importStyle('selectreward')

  connect(g_game, {
    onGameEnd = offline,
    onDailyReward = onDailyReward,
    onOpenRewardWall = onOpenRewardWall,
    onDailyRewardCollectionState = onDailyRewardCollectionState,
    onDailyRewardHistory = onDailyRewardHistory,
    onResourceBalance = onResourceBalance,
  })

  connect(LocalPlayer, {
    onFreeCapacityChange = onFreeCapacityChange,
  })
end

function terminate()
  stopDailyRewardTimer()
  resetDailyRewardRestingAreaState()

  disconnect(g_game, {
    onGameEnd = offline,
    onDailyReward = onDailyReward,
    onOpenRewardWall = onOpenRewardWall,
    onDailyRewardCollectionState = onDailyRewardCollectionState,
    onDailyRewardHistory = onDailyRewardHistory,
    onResourceBalance = onResourceBalance,
  })

  disconnect(LocalPlayer, {
    onFreeCapacityChange = onFreeCapacityChange,
  })

  dailyRewardWindow:destroy()

  if dailyRewardHistory then
    dailyRewardHistory:destroy()
    dailyRewardHistory = nil
  end

  if selectRewardWindow then
    g_client.setInputLockWidget(nil)
    selectRewardWindow:destroy()
    selectRewardWindow = nil
  end
  if confirmRewardWindow then
    g_client.setInputLockWidget(nil)
    confirmRewardWindow:destroy()
    confirmRewardWindow = nil
  end
end

function closeSelectReward()
  g_client.setInputLockWidget(nil)
  selectRewardWindow:destroy()
  selectRewardWindow = nil
  dailyRewardWindow:show(true)
  g_client.setInputLockWidget(dailyRewardWindow)
end

function closeDaily()
  stopDailyRewardTimer()
  dailyRewardWindow:hide()
  g_client.setInputLockWidget(nil)
  modules.game_sidebuttons.setButtonVisible("rewardWallDialog", false)
  if selectRewardWindow then
    selectRewardWindow:hide()
    g_client.setInputLockWidget(nil)
  end
  if confirmRewardWindow then
    confirmRewardWindow:hide()
  end
  if dailyRewardHistory then
    dailyRewardHistory:destroy()
    dailyRewardHistory = nil
  end

  modules.game_console.getConsole():recursiveFocus(2)
end

function show()
  dailyRewardCollectionState = nil
  lastOpenRewardWallArgs = nil
  g_game.openDailyReward()
  g_client.setInputLockWidget(dailyRewardWindow)
end

function requestHistory()
  closeDaily()
  g_game.dailyRewardHistory()

end

function offline()
  stopDailyRewardTimer()
  resetDailyRewardRestingAreaState()
  dailyRewardCollectionState = nil
  lastOpenRewardWallArgs = nil

  dailyRewardWindow:hide()
  g_client.setInputLockWidget(nil)
  if confirmRewardWindow then
    confirmRewardWindow:destroy()
    confirmRewardWindow = nil
  end
  if selectRewardWindow then
    selectRewardWindow:destroy()
    selectRewardWindow = nil
  end
end

function onDailyReward( freeRewards, premiumRewards, descriptions )
  DailyReward:onDailyReward( freeRewards, premiumRewards, descriptions )
end

local function syncRewardWallFromCollectionState()
  if not lastOpenRewardWallArgs or not dailyRewardWindow or not dailyRewardWindow:isVisible() then
    return
  end

  local syncedState = nil
  if dailyRewardCollectionState == DAILY_REWARD_COLLECTED then
    syncedState = 0
  elseif dailyRewardCollectionState == DAILY_REWARD_NOTCOLLECTED then
    syncedState = 2
  end

  if not syncedState or lastOpenRewardWallArgs.dailyState == syncedState then
    return
  end

  local nextRewardTime = lastOpenRewardWallArgs.nextRewardTime
  onOpenRewardWall(
    lastOpenRewardWallArgs.fromShrine,
    nextRewardTime,
    lastOpenRewardWallArgs.currentIndex,
    lastOpenRewardWallArgs.message,
    syncedState,
    lastOpenRewardWallArgs.jokerToken,
    lastOpenRewardWallArgs.serverSave,
    lastOpenRewardWallArgs.dayStreakLevel,
    true
  )
end

function onDailyRewardCollectionState(state)
  dailyRewardCollectionState = tonumber(state)
  syncRewardWallFromCollectionState()
end

function onOpenRewardWall(fromShrine, nextRewardTime, currentIndex, message, dailyState, jokerToken, serverSave, dayStreakLevel, fromCollectionSync)
  local player = g_game.getLocalPlayer()
  if not player then
    return
  end

  gameFromShrine = fromShrine ~= 0
  dailyState = tonumber(dailyState) or 2
  nextRewardTime = tonumber(nextRewardTime) or 0
  currentIndex = tonumber(currentIndex) or 0
  jokerToken = tonumber(jokerToken) or 0
  serverSave = tonumber(serverSave) or 0
  dayStreakLevel = tonumber(dayStreakLevel) or 0

  -- The server is the only source of truth for the countdown:
  --   state == 0 (collected): `nextRewardTime` is the unix timestamp of the
  --     next server save + threshold (when next reward unlocks). `serverSave`
  --     is NOT sent in this state, so it's always 0 here.
  --   state == 2 (can claim): `serverSave` is the unix timestamp of the next
  --     server save (deadline before losing streak). `nextRewardTime` is 0.
  --   state == 1 (missed): no countdown.
  -- We never synthesize cooldowns locally. If `nextRewardTime` is in the past
  -- (server hasn't refreshed lastServerSave), schedule a one-shot re-request
  -- so the wall self-heals instead of showing a stuck 00:00.
  local timerMode = "next-reward:" .. tostring(currentIndex)
  -- Wipe any local cache from previous versions so it can never override the
  -- value the server is about to send.
  saveDailyRewardTimerDeadline(timerMode, 0)
  if dailyState == 0 and getNextRewardSeconds(nextRewardTime) <= 0 and not fromCollectionSync then
    -- nextRewardTime already passed but state still says collected — server
    -- state is stale (lastServerSave hasn't rotated yet). Request a fresh
    -- open packet after a short delay so the timer can recover without the
    -- user closing/reopening the wall. Capped to avoid hammering the server
    -- if the server-side data simply won't refresh.
    if staleRefreshAttempts < STALE_REFRESH_MAX_ATTEMPTS then
      staleRefreshAttempts = staleRefreshAttempts + 1
      scheduleEvent(function()
        if dailyRewardWindow and dailyRewardWindow:isVisible() and g_game.openDailyReward then
          g_game.openDailyReward()
        end
      end, 5000)
    end
  else
    staleRefreshAttempts = 0
  end

  if fromCollectionSync then
    if dailyRewardCollectionState == DAILY_REWARD_COLLECTED then
      dailyState = 0
    elseif dailyRewardCollectionState == DAILY_REWARD_NOTCOLLECTED then
      dailyState = 2
      message = ""
    end
  end

  lastOpenRewardWallArgs = {
    fromShrine = fromShrine,
    nextRewardTime = nextRewardTime,
    currentIndex = currentIndex,
    message = message,
    dailyState = dailyState,
    jokerToken = jokerToken,
    serverSave = serverSave,
    dayStreakLevel = dayStreakLevel
  }
  
  dailyRewardWindow:focus()
  g_client.setInputLockWidget(dailyRewardWindow)
  updateResourceLabels()
  local displayStreak = getDisplayStreak(dayStreakLevel, currentIndex)
  DailyRewardDisplayStreak = displayStreak
  DailyRewardRestingAreaMessage = buildRestingAreaMessage(displayStreak)
  dailyRewardWindow.miniWindowBonuses.jokerInfo.streakWidget:setText(displayStreak)
  updateRestingAreaBonuses(displayStreak)
  refreshRestingAreaCondition()
  dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakProgress:setVisible(false)
  dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakProgress:setText("")
  dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakLabel:setText("")
  dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakLabel:setVisible(true)
  dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakCheck:setVisible(true)

  local jokerBalance = jokerTokens
  local text = jokerToken > 3 and ">3" or jokerToken
  dailyRewardWindow.miniWindowBonuses.jokerInfo.jokers.jokerInfoLabel:setText(text)

  local textColor = jokerToken > jokerBalance and "#d33c3c" or "#c0c0c0"
  dailyRewardWindow.miniWindowBonuses.jokerInfo.jokers.jokerInfoLabel:setColor(textColor)

  dailyRewardWindow.jokers.jokersLabel:setText(jokerBalance)

  dailyRewardWindow.miniWindowBonuses.bonusLabel:setText("")
  if dailyState == 0 then
    dailyRewardWindow.miniWindowBonuses.bonusLabel:setText("You already claimed your daily reward.")
  elseif dailyState == 1 then
    dailyRewardWindow.miniWindowBonuses.bonusLabel:setText("You did not claim your daily reward in time.\nToo bad, you do not have enough Daily Reward Jokers.")
  elseif dailyState == 2 then
    dailyRewardWindow.miniWindowBonuses.bonusLabel:setColorText("Claim your daily reward before server save.\n If you don't claim your reward now, your [color=#d33c3c]streak will be reset[/color].")
  end

  globalMessage = type(message) == "string" and message or ""
  dailyRewardWindow.miniWindowBonuses.bonusLabel.onHoverChange = function(_, hovered) setupBonusLabelDesc(hovered, dailyState, jokerToken) end
  local canClaimReward = dailyState ~= 0 and (gameFromShrine or instantTokens > 0)
  local countdownSeconds = nil
  local countdownProgressWidgets = {}
  local countdownMode = nil
  local countdownTotalSeconds = DAY_SECONDS

  for i = 0, 6 do
    local widget = dailyRewardWindow.miniWindowDailyReward.dailyReward:recursiveGetChildById("dailyButton_".. i)
    if widget and i ~= currentIndex then
      widget:setImageSource("/images/dailyreward/nextbg")
      widget.blocked:setImageSource("/images/ui/ditherpattern64")
      widget.blocked:setMargin(1)
      local style = {}
      style["$pressed"] = {
        ["image-clip"] = "0 0 66 66"
      }
      widget:mergeStyle(style)
      widget.onClick = function() end
    elseif widget and canClaimReward then
      widget:setImageSource("/images/dailyreward/buttonbg")
      local style = {}
      style["$pressed"] = {
        ["icon-offset"] = "1 1",
        ["image-clip"] = "0 66 66 66"
      }
      widget:mergeStyle(style)
      widget.onClick = onClaimReward
      widget.blocked:setImageSource("")
    elseif widget then
      widget.blocked:setImageSource("")
      widget:setImageSource("/images/dailyreward/nextbg")
      local style = {}
      style["$pressed"] = {
        ["image-clip"] = "0 0 66 66"
      }
      widget:mergeStyle(style)
      widget.onClick = function() end
    end

    local widget = dailyRewardWindow.miniWindowDailyReward.dailyReward:recursiveGetChildById("dailyPanel_".. i)
    if widget and widget.dailyPanelProgress then
      widget.dailyPanelProgress:setVisible(false)
    end
    if widget and i < currentIndex then
      widget.dailyBlocked:setVisible(false)
      widget.dailyPanelLabel:setVisible(true)
      widget.dailyPanelLabel:setText(" ")
      widget.dailyPanelLabel:setIcon("/images/dailyreward/icon-checkmark")
      widget.dailyIconLabel:setVisible(false)
    elseif widget and i > currentIndex then
      widget.dailyBlocked:setVisible(true)
      widget.dailyPanelLabel:setVisible(false)
      widget.dailyIconLabel:setVisible(false)
    elseif widget and dailyState == 0 then
      widget.dailyBlocked:setVisible(false)
      widget.dailyPanelLabel:setIcon("")
      widget.dailyPanelLabel:setText("")
      widget.dailyPanelLabel:setVisible(true)
      widget.dailyIconLabel:setVisible(false)

      local time = getNextRewardSeconds(nextRewardTime)
      if time > 0 then
        widget.dailyPanelProgress:setVisible(true)
        updateDurationProgress(widget.dailyPanelProgress, time, NEXT_REWARD_SECONDS)
        countdownSeconds = time
        countdownMode = "next-reward:" .. tostring(currentIndex)
        countdownTotalSeconds = NEXT_REWARD_SECONDS
        table.insert(countdownProgressWidgets, widget.dailyPanelProgress)
      else
        -- Server says "collected" but the deadline timestamp is already
        -- past (lastServerSave is stale on the server side). Replace the
        -- misleading 00:00 progress bar with a clear status label so the
        -- player knows what they're waiting on.
        widget.dailyPanelProgress:setVisible(false)
        widget.dailyPanelLabel:setText("...")
      end

    elseif widget and dailyState == 1 then
      widget.dailyBlocked:setVisible(false)
      widget.dailyPanelLabel:setIcon("")
      widget.dailyPanelLabel:setText(gameFromShrine and "0" or "1")
      widget.dailyIconLabel:setVisible(true)
      widget.dailyPanelProgress:setVisible(false)
      dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakLabel:setText("expired")
      dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakCheck:setVisible(false)
    elseif widget and dailyState == 2 then
      widget.dailyBlocked:setVisible(false)
      widget.dailyPanelLabel:setIcon("")
      widget.dailyPanelLabel:setVisible(true)
      widget.dailyPanelLabel:setText(gameFromShrine and "0" or "1")
      widget.dailyIconLabel:setVisible(true)
      widget.dailyPanelProgress:setVisible(false)

      local time = getDisplayRewardSeconds(serverSave)
      updateDurationProgress(widget.dailyPanelProgress, time, DAY_SECONDS)

      dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakProgress:setVisible(true)
      updateDurationProgress(dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakProgress, time, DAY_SECONDS)
      countdownSeconds = time
      countdownMode = "server-save:" .. tostring(currentIndex)
      countdownTotalSeconds = DAY_SECONDS
      table.insert(countdownProgressWidgets, dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakProgress)
      dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakLabel:setText("")
      dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakLabel:setVisible(false)
      dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakCheck:setVisible(false)
    end

    local widget = dailyRewardWindow.miniWindowDailyReward.dailyReward:recursiveGetChildById("processArrow_".. i)
    if widget and i < currentIndex then
      widget:setText(" ")
      widget:setIcon("/images/dailyreward/icon-rewardarrow-active")
    end
  end

  if countdownSeconds and #countdownProgressWidgets > 0 then
    startDailyRewardTimer(countdownSeconds, countdownProgressWidgets, countdownMode, function()
      if dailyRewardWindow and dailyRewardWindow:isVisible() then
        g_game.openDailyReward()
      end
    end, countdownTotalSeconds)
  else
    stopDailyRewardTimer()
    dailyRewardTimerDeadline = nil
    dailyRewardTimerMode = nil
  end

  dailyRewardWindow:show(true)
end

function setupBonusLabelDesc(hovered, dailyState, jokerToken)
  if not hovered then
    dailyRewardWindow.Description.tooltipTodo:setText("")
    return
  end

  local text = ""
  if dailyState == 0 then
    text = "Congratulations! You claimed your daily reward in time. Come back after\nthe next regular server save for more rewards.\nRaise your reward streak to benefit from bonuses in resting areas."
  elseif dailyState == 1 then
    text = string.format("Oh no! You are too late! You did not claim your daily reward before server\nsave. Your reward streak will be reset to 1 as you do not have at least %s\nDaily Reward Jokers to keep the streak going.\nRaise your reward streak to benefit from bonuses in resting areas.", jokerToken)
  elseif dailyState == 2 then
    if jokerToken > 0 then
      text = string.format("Hurry! Claim your daily reward before the next regular server save to raise\nyour reward streak by one.\nTo prevent a reset of your reward streak, %d Daily Reward Jokers will be used.\nRaise your reward streak to benefit from bonuses in resting areas.", jokerToken)
    else
      text = "Hurry! Claim your daily reward before the next regular server save to raise\nyour reward streak by one.\nTo prevent a reset of your reward streak.\nRaise your reward streak to benefit from bonuses in resting areas."
    end
  end
  dailyRewardWindow.Description.tooltipTodo:setText(text)
end

function onClaimReward(widget)
  local player = g_game.getLocalPlayer()
  if not player then
    return
  end

  if selectRewardWindow then
    selectRewardWindow:destroy()
    selectRewardWindow = nil
  end

  selectedAmount = 0
  selectItems = {}
  local reward = g_game.getLocalPlayer():isPremium() and widget.premiumRewards or widget.freeRewards
  if reward.type == 1 then
    dailyRewardWindow:hide()
    g_client.setInputLockWidget(nil)
    selectRewardWindow = g_ui.createWidget('MainWindowSelect', m_interface.getRootPanel())
    g_client.setInputLockWidget(selectRewardWindow)

    for c, i in pairs(reward.items) do
      local w = g_ui.createWidget("RewardSelectLabel", selectRewardWindow.itemPanel)
      if w then
        w.item:setItemId(i.item)
        w.name:setText(i.name)
        w.oz:setText("0.00 oz")
        w.ozNumber = i.oz
        --w.oz:setText(string.format("%.2f oz", (i.oz)/100))
        w.leftSkipPlus.onClick = onClickAmount
        w.leftSkip.onClick = onClickAmount
        w.rightSkip.onClick = onClickAmount
        w.rightSkipPlus.onClick = onClickAmount
        w.leftSkipPlus.window = w
        w.leftSkip.window = w
        w.rightSkip.window = w
        w.rightSkipPlus.window = w
        w:setBackgroundColor((c % 2 ~= 0 and "#484848" or "#414141"))
      end
    end

    selectRewardWindow.freeCapacityLabel:setText(string.format("Free Capacity: %d oz", freeCap))
    local m = {}
    setStringColor(m, "You have selected ", "#C0C0C0")
    setStringColor(m, "0", "#F75F5F")
    totalOz = 0
    rewardAmount = reward.amount
    setStringColor(m, string.format(" of %d reward items.", reward.amount), "#C0C0C0")
    selectRewardWindow.selectLabel:setColoredText(m)

    selectRewardWindow.closeButton.onClick = function()
      g_client.setInputLockWidget(nil)
      selectRewardWindow:destroy()
      dailyRewardWindow:show(true)
      g_client.setInputLockWidget(dailyRewardWindow)
    end
  else
    onClickConfirm(widget)
  end
end

function onFreeCapacityChange(localPlayer, freeCapacity)
  freeCap = freeCapacity
end

function onClickAmount(widget)
  local id = widget:getId()

  local value = widget.window.countEdit:getText()
  if not tonumber(value) then
    value = 0
  end

  if id == "leftSkipPlus" then
    selectedAmount = math.max(0, selectedAmount - value)
    widget.window.countEdit:setText('0')
  elseif id == "leftSkip" then
    selectedAmount = math.max(0, selectedAmount - value)
    widget.window.countEdit:setText(tostring(math.max(0, value - 1)))
  elseif id == "rightSkip" then
    selectedAmount = selectedAmount + 1
    if selectedAmount > rewardAmount then
      selectedAmount = selectedAmount - 1
    else
      widget.window.countEdit:setText(value + 1)
    end
  elseif id == "rightSkipPlus" and selectedAmount < rewardAmount then
    selectedAmount = rewardAmount - selectedAmount
    if selectedAmount > rewardAmount then
      selectedAmount = selectedAmount - 1
    else
      widget.window.countEdit:setText(selectedAmount)
    end
  end

  local value = tonumber(widget.window.countEdit:getText()) or 0
  totalOz = (value * widget.window.ozNumber)
  widget.window.oz:setText(string.format("%.2f oz", (widget.window.ozNumber * value)/100))
  selectRewardWindow.totalWeightLabel:setText(string.format('Total Weight:        %.2f oz', totalOz/100))

  -- arrumando as coisas
  if selectedAmount < rewardAmount then
    for i, child in pairs(selectRewardWindow.itemPanel:getChildren()) do
      child.rightSkipPlus:setIcon("/images/dailyreward/icon-arrowskipright")
      child.rightSkip:setIcon("/images/dailyreward/icon-arrowright")
    end
  else
    for i, child in pairs(selectRewardWindow.itemPanel:getChildren()) do
      child.rightSkipPlus:setIcon("/images/dailyreward/icon-arrowskipright-disabled")
      child.rightSkip:setIcon("/images/dailyreward/icon-arrowright-disabled")
    end
  end

  for i, child in pairs(selectRewardWindow.itemPanel:getChildren()) do
    if tonumber(child.countEdit:getText()) > 0 then
      child.leftSkipPlus:setIcon("/images/dailyreward/icon-arrowskip")
      child.leftSkip:setIcon("/images/dailyreward/icon-arrow")
    else
      child.leftSkipPlus:setIcon("/images/dailyreward/icon-arrowskip-disabled")
      child.leftSkip:setIcon("/images/dailyreward/icon-arrow-disabled")
    end
  end

  local m = {}
  setStringColor(m, "You have selected ", "#C0C0C0")
  if selectedAmount < rewardAmount then
    setStringColor(m, string.format("%d", selectedAmount), "#F75F5F")
  else
    setStringColor(m, string.format("%d", selectedAmount), "#0B8A0A")
  end
  setStringColor(m, string.format(" of %d reward items.", rewardAmount), "#C0C0C0")
  selectRewardWindow.selectLabel:setColoredText(m)

  if selectedAmount == rewardAmount then
    selectRewardWindow.ok:setEnabled(true)
    selectRewardWindow.ok.onClick = onClickConfirm
  else
    selectRewardWindow.ok:setEnabled(false)
  end

end

function onClickConfirm(widget)
  if confirmRewardWindow then
    return
  end

  if selectRewardWindow then
    selectRewardWindow:hide()
    g_client.setInputLockWidget(nil)
  end

  dailyRewardWindow:hide()
  g_client.setInputLockWidget(nil)

  local yesCallback = function()
    updateResourceLabels()
    if not gameFromShrine and instantTokens < 1 then
      if confirmRewardWindow then
        confirmRewardWindow:destroy()
        confirmRewardWindow = nil
      end
      dailyRewardWindow:show()
      g_client.setInputLockWidget(dailyRewardWindow)
      return
    end

    if confirmRewardWindow then
      confirmRewardWindow:destroy()
      confirmRewardWindow=nil
      dailyRewardWindow:show()
      g_client.setInputLockWidget(dailyRewardWindow)
    end

    local items = {}
    local totalOz = 0
    if selectRewardWindow then
      local childrens = selectRewardWindow.itemPanel:getChildren()
      for i, child in pairs(childrens) do
        if child and child.item and tonumber(child.countEdit:getText()) and tonumber(child.countEdit:getText()) > 0 then
          local count = tonumber(child.countEdit:getText())
          items[child.item:getItemId()] = count
          totalOz = totalOz + (count * child.ozNumber)
        end
      end
    end

    if (totalOz/ 100) > freecap() then
      return
    end
    g_game.dailyRewardConfirm(not gameFromShrine, items)
  end

  local noCallback = function()
    if selectRewardWindow then
      selectRewardWindow:show(true)
      g_client.setInputLockWidget(selectRewardWindow)
    end
    confirmRewardWindow:destroy()
    confirmRewardWindow=nil
    dailyRewardWindow:show()
    g_client.setInputLockWidget(dailyRewardWindow)
  end

  confirmRewardWindow = displayGeneralBox(tr('Warning'), tr(getConfirmMessage()), {
      { text=tr('Yes'), callback=yesCallback },
      { text=tr('No'), callback=noCallback },
    }, yesCallback, noCallback)


  g_keyboard.bindKeyPress("Y", yesCallback, confirmRewardWindow)
  g_keyboard.bindKeyPress("N", noCallback, confirmRewardWindow)
end

function onTextChange(widget)
  local text = widget:getText()
  if not tonumber(text) then
    widget:setText('0')
    return false
  end

  return true
end

function onResourceBalance(type, value)
  local player = g_game.getLocalPlayer()
  if player then
    player:setResourceInfo(type, value)
  end

  if type == ResourceReward or type == ResourceJokerReward then
    updateResourceLabels()
  end
end

function closeHistory()
  closeDaily()
end
function backHistory()
  closeDaily()
  dailyRewardWindow:show(true)
  g_client.setInputLockWidget(dailyRewardWindow)
end

function onDailyRewardHistory(dailyRewardHistories)
  dailyRewardHistory = g_ui.displayUI('history')
  dailyRewardHistory:focus()
  g_client.setInputLockWidget(dailyRewardHistory)

  updateResourceLabels()
  for i, info in pairs(dailyRewardHistories) do
    local widget = g_ui.createWidget('HistoryDescription', dailyRewardHistory.historyPanel.historyListPanel)
    widget.date:setText(os.date("%Y.%m.%d, %X", info[1]))
    widget.streak:setText(info[4])
    widget.description:setText(info[3])
    widget:setBackgroundColor(i % 2 == 0 and "#414141" or "#484848")
  end
end
