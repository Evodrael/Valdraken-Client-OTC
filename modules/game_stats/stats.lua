ui = nil
updateEvent = nil

local keybindShowPing = KeyBind:getKeyBind("UI", "Show/hide FPS / Lag indicator")

function init()
  ui = g_ui.loadUI('stats', m_interface.getMapPanel())

  keybindShowPing:active(gameRootPanel)

  if not m_settings.getOption("showPing") then
    ui.ping:hide()
  end
  if not m_settings.getOption("showFps") then
    ui.fps:hide()
  end

  updateEvent = scheduleEvent(update, 200)
end

function terminate()
  keybindShowPing:deactive()
  removeEvent(updateEvent)
end

function update()
  updateEvent = scheduleEvent(update, 500)
  if ui:isHidden() then return end

  text = g_app.getFps() .. ' fps'
  ui.fps:setText(text)

  local ping = math.round(g_game.getPing() * 0.7)
  if g_proxy and g_proxy.getPing() > 0 then
    ping = g_proxy.getPing()
  end

  ui.worldName:setText(g_game.getWorldName())

  local text = 'Ping: '
  if ping < 0 then
    text = "??"
    ui.imagePing:setImageSource('/images/latency/latency-medium')
  else
    if ping >= 500 then
      text = "High lag (".. ping .." ms)"
      ui.imagePing:setImageSource('/images/latency/latency-high')
    elseif ping >= 250 then
      text = "Medium lag (".. ping .." ms)"
      ui.imagePing:setImageSource('/images/latency/latency-medium')
    else
      text = "Low lag (".. ping .." ms)"
      ui.imagePing:setImageSource('/images/latency/latency-low')
    end
  end

  local player = g_game.getLocalPlayer()
  if player and player:getGroupType() >= 4 and player:getGroupType() <= 6 then
    local spectators = g_map.getSpectators(player:getPosition(), false)
    local playerCount = 0
    local monsterCount = 0
    local npcCount = 0
    for _, spec in pairs(spectators) do
      if spec:isPlayer() and spec ~= player then
        playerCount = playerCount + 1
      elseif spec:isMonster() and spec ~= player then
        monsterCount = monsterCount + 1
      elseif spec:isNpc() and spec ~= player then
        npcCount = npcCount + 1
      end
    end

    text = tr("%s\nPlayers: %s", text, playerCount)
    text = tr("%s\nMonsters: %s", text, monsterCount)
    text = tr("%s\nNPcs: %s", text, npcCount)
  end

  if g_game.isRecord() then
    local getCamViewerSpeed = g_game.getCamViewerSpeed
    local getRecordDuration = g_game.getRecordDuration
    local getRecordCurrentFrame = g_game.getRecordCurrentFrame

    if type(getCamViewerSpeed) == "function" and type(getRecordDuration) == "function" and type(getRecordCurrentFrame) == "function" then
      local speed = getCamViewerSpeed()
      if speed == 0 then
        text = tr("%s\nRecord Speed: Paused", text)
      else
        text = tr("%s\nRecord Speed: %s%%", text, 100 + (100 - (100 * speed)))
      end

      local duration = math.floor((getRecordDuration() or 0) / 1000) -- segundos
      local hours = math.floor(duration / 3600)
      local minutes = math.floor((duration % 3600) / 60)
      local seconds = duration % 60

      local currentDuration = math.floor((getRecordCurrentFrame() or 0) / 1000) -- segundos
      local currentHours = math.floor(currentDuration / 3600)
      local currentMinutes = math.floor((currentDuration % 3600) / 60)
      local currentSeconds = currentDuration % 60

      text = tr("%s\n%02d:%02d:%02d/%02d:%02d:%02d", text, currentHours, currentMinutes, currentSeconds, hours, minutes, seconds)
    end
  end

  ui.ping:setText(text)
end

function show()
  if ui:isHidden() then
    ui:setVisible(true)
  else
    ui:setVisible(false)
  end
end

function hide()
  ui:setVisible(false)
end
