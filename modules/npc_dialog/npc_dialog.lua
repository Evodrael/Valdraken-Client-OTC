local npcName = nil
local dialogStarted = false
local connectedPlayer = nil
local refreshPlayerEvent = nil
local sessionId = 0       -- incremented on close; guards onTalk/onNpcChatWindow from stale packets

function init()
  npcWindow = g_ui.displayUI('npc_dialog')
  
  -- Bind Input Enter Key explicitly via keyboard handler
  g_keyboard.bindKeyPress('Enter', function()
    if npcWindow and npcWindow:isVisible() then
      local textInput = npcWindow:recursiveGetChildById('textInput')
      if textInput:isFocused() then
        onTextSubmit()
      end
    end
  end, npcWindow)

  npcWindow.onClick = function()
    local textInput = npcWindow:recursiveGetChildById('textInput')
    if textInput then
      textInput:focus()
    end
  end
  
  connect(g_game, {
    onTalk = onTalk,
    onGameStart = refreshPlayerConnection,
    onGameEnd = disconnectPlayer,
    onNpcChatWindow = onNpcChatWindow
  })
  
  if g_game.isOnline() then
    refreshPlayerConnection()
  end
end

-- ... (rest of file)


function sendTalk(message)
  if not g_game.isOnline() then return end

  -- Try to use game_console logic to mirror behavior. OTCV8 exposes the tab
  -- lookup as `getTabByName`; upstream uses `getTab`. Try both.
  if modules.game_console then
    local console = modules.game_console
    local getTab = console.getTab or console.getTabByName
    local tab = getTab and (getTab("NPCs") or getTab("NPC")) or nil
    if tab then
      -- OTCV8's `console.sendMessage` takes only `(message)` (g_chat:sendMessage
      -- handles routing to the active tab). We focus the NPC tab first so the
      -- message lands in the right log, then send.
      if console.consoleTabBar and console.consoleTabBar.selectTab then
        console.consoleTabBar:selectTab(tab)
      end
      console.sendMessage(message)
      local player = g_game.getLocalPlayer()
      local playerName = player and player:getName() or 'You'
      addText(playerName .. ': ' .. message, MessageModes.NpcTo)
      return
    end
  end

  -- Fallback if game_console/NPC tab not found
  g_game.talk(message)
  local player = g_game.getLocalPlayer()
  local playerName = player and player:getName() or 'You'
  addText(playerName .. ': ' .. message, MessageModes.NpcTo)
end

function terminate()
  g_client.setInputLockWidget(nil)
  disconnectPlayer()
  disconnect(g_game, {
    onTalk = onTalk,
    onGameStart = refreshPlayerConnection,
    onGameEnd = disconnectPlayer,
    onNpcChatWindow = onNpcChatWindow
  })

  if npcWindow then
    npcWindow:destroy()
    npcWindow = nil
  end
end

function refreshPlayerConnection()
  if not g_game.isOnline() then
    disconnectPlayer()
    return
  end

  local player = g_game.getLocalPlayer()
  if player then
    if connectedPlayer ~= player then
       disconnectPlayer()
       connect(player, { onPositionChange = onPlayerPositionChange })
       connectedPlayer = player
    end
  else
    -- Retry in 500ms if player object is not ready yet during login
    removeEvent(refreshPlayerEvent)
    refreshPlayerEvent = scheduleEvent(refreshPlayerConnection, 500)
  end
end

function disconnectPlayer()
  if connectedPlayer then
    disconnect(connectedPlayer, { onPositionChange = onPlayerPositionChange })
    connectedPlayer = nil
  end
end

function onPlayerPositionChange(creature, newPos, oldPos)
  if not npcWindow or not npcWindow:isVisible() then return end

  -- 1. Close on teleport (large distance jump or Z floor change)
  local isTeleport = oldPos and (math.abs(newPos.x - oldPos.x) > 1 or math.abs(newPos.y - oldPos.y) > 1 or newPos.z ~= oldPos.z)
  
  -- 2. Close if no NPC is within talk range (4 tiles)
  -- This handles walking away tile-by-tile
  if isTeleport or not isNpcNearby() then
    close()
  end
end

local function isOutfitWindowOpen()
    -- Both checks must guard the function existence: game_hireling_outfit/game_outfit
    -- exist in OTCV8 but neither necessarily exposes :isVisible().
    if modules.game_hireling_outfit and modules.game_hireling_outfit.isVisible and modules.game_hireling_outfit.isVisible() then
        return true
    end
    if modules.game_outfit and modules.game_outfit.isVisible and modules.game_outfit.isVisible() then
        return true
    end
    return false
end

function show()
  if not connectedPlayer then
    refreshPlayerConnection()
  end

  if npcWindow then
    if isOutfitWindowOpen() then return end
    if not npcWindow:isVisible() then
      npcWindow:setWidth(397)
      local separator = npcWindow:recursiveGetChildById('separator')
      if separator then separator:setVisible(false) end
    end
    npcWindow:show()
    npcWindow:raise()
    g_client.setInputLockWidget(npcWindow)

    local textInput = npcWindow:recursiveGetChildById('textInput')
    if textInput then
      addEvent(function()
        if npcWindow and npcWindow:isVisible() then
          textInput:focus()
        end
      end)
    end
  end
end


function close()
  if npcWindow then
    sessionId = sessionId + 1   -- invalidate any in-flight packets from the old session
    g_client.setInputLockWidget(nil)
    npcWindow:hide()
    clearContext()
    npcName = nil
    dialogStarted = false
    knownNpcIds = {}
    currentNpcId = 0
  end
end

-- Local definitions to match console colors
local NpcSpeakTypes = {
  [MessageModes.NpcTo] = { color = '#9F9DFD' },
  [MessageModes.NpcFrom] = { color = '#5FF7F7' },
  [MessageModes.NpcFromStartBlock] = { color = '#5FF7F7' }
}

-- Helper to parse {keyword}
function getHighlightedText(text)
  local tmpData = {}
  repeat
    local tmp = {string.find(text, '{([^}]+)}', tmpData[#tmpData - 1])}
    for _, v in pairs(tmp) do
      table.insert(tmpData, v)
    end
  until not (string.find(text, '{([^}]+)}', tmpData[#tmpData - 1]))
  return tmpData
end

function addText(text, mode, colorOverride)
  if not npcWindow then return end
  local panel = npcWindow:recursiveGetChildById('dialogPanel')
  if not panel then return end

  local label = g_ui.createWidget('NpcDialogLabel', panel)
  label.highlightInfo = {}
  
  local speaktype = NpcSpeakTypes[mode]
  local color = '#5FF7F7' -- Default NPC
  if speaktype and speaktype.color then
    color = speaktype.color
  end
  if colorOverride then
    color = colorOverride
  end
  label:setColor(color)

  -- Process highlighting if NPC message
  if mode == MessageModes.NpcFrom or mode == MessageModes.NpcFromStartBlock then
    local formattedText = ""
    local plainText = ""
    local lastIndex = 1
    local found = false
    
    for s, word, e in text:gmatch("()%{(.-)%}()") do
        found = true
        -- Text before matches
        local pre = text:sub(lastIndex, s - 1)
        if #pre > 0 then
            formattedText = formattedText .. string.format("{%s, %s}", pre, color)
            plainText = plainText .. pre
        end
        
        -- Check for suffix (e.g., 's' in {offer}s)
        -- Check for suffix (e.g., 's' in {offer}s)
        -- Using explicit ranges to avoid any %w locale weirdness
        local suffix = text:match("^([a-zA-Z0-9]+)", e) or ""
        
        local displayWord = word .. suffix
        
        -- The highlighted keyword + suffix
        local startMap = #plainText + 1
        
        formattedText = formattedText .. string.format("{%s, %s}", displayWord, '#1f9ffe')
        plainText = plainText .. displayWord
        
        local endMap = #plainText
        
        -- Map indices for click detection (send original 'word')
        for i = startMap, endMap do
            label.highlightInfo[i] = word
        end
        
        lastIndex = e + #suffix
    end
    
    if found then
        -- Remaining text
        local post = text:sub(lastIndex)
        if #post > 0 then
            formattedText = formattedText .. string.format("{%s, %s}", post, color)
            plainText = plainText .. post
        end
        label:setColoredText(formattedText)
    else
        label:setText(text)
        label:setColor(color) -- Ensure basic color is applied if no keywords found
    end
  else
    label:setText(text)
  end
  
  -- Click handler
  label.onMouseRelease = function(self, mousePos, mouseButton)
    if mouseButton == MouseLeftButton then
      local position = label:getTextPos(mousePos)
      if position and label.highlightInfo[position] then
        sendTalk(label.highlightInfo[position])
      end
    end
  end
end

-- Mapping keyword IDs to their respective UI button IDs
local buttonIdMap = {
  [0] = 'buttonTrade',
  [1] = 'buttonTrade', -- Potion Trade
  [2] = 'buttonTrade', -- Equipment Trade
  [3] = 'buttonSail',
  [4] = 'buttonDeposit',
  [5] = 'buttonWithdraw',
  [6] = 'buttonBalance',
  [7] = 'buttonYes',
  [8] = 'buttonNo',
  [9] = 'buttonBye'
}

local currentNpcId = 0
-- Accumulated set of all NPC IDs currently in this dialog session.
-- Values: { hasTrade = bool }
-- Only cleared on explicit close (empty packet) or full NPC change.
local knownNpcIds = {}

-- Returns true if the given NPC ID currently has a trade button in the dialog.
function getNpcHasTrade(npcId)
  return knownNpcIds[npcId] and knownNpcIds[npcId].hasTrade or false
end

-- Opens the NPC dialog, optionally jumping straight to trade.
function openNpcDialogFor(npcId, withTrade)
  local creature = g_map.getCreatureById(npcId)
  if not creature then return end

  local known = knownNpcIds[npcId]

  -- Already in dialog: open trade if available, otherwise just show the window
  if known then
    if withTrade and known.hasTrade then
      sendTalk('trade')
    end
    return
  end

  -- Open window immediately with local NPC data — no round-trip wait
  local nameLabel = npcWindow and npcWindow:recursiveGetChildById('npcNameLabel')
  local npcOutfitWidget = npcWindow and npcWindow:recursiveGetChildById('npcOutfit')
  local npcOutfitMultiple = npcWindow and npcWindow:recursiveGetChildById('npcOutfitMultiple')
  if nameLabel then nameLabel:setText(creature:getName()) end
  if npcOutfitMultiple then npcOutfitMultiple:setVisible(false) end
  if npcOutfitWidget then
    npcOutfitWidget:setVisible(true)
    npcOutfitWidget:setOutfit(creature:getOutfit())
  end
  npcName = creature:getName()

  -- Emit "Talking To" immediately, before server responds
  if not dialogStarted then
    local timestamp = os.date("%H:%M:%S")
    addText(timestamp .. ' Talking To ' .. creature:getName(), MessageModes.NpcFromStartBlock, '#FFFFFF')
    dialogStarted = true
  end

  show()

  -- Greet — server will auto-send 'trade' if NPC has a shop.
  -- `g_game.greetNpc(npcId)` is a Luminaris-specific binding (a single packet
  -- that says "hi" to a specific NPC by id). Retail Tibia / OTCV8 source does
  -- not expose it; we fall back to broadcasting "hi" in the default channel,
  -- which any standard NPC listener picks up the same way.
  if g_game.greetNpc then
    g_game.greetNpc(npcId)
  else
    g_game.talk('hi')
  end
end

local function updatePedestal()
  if not npcWindow then return end
  local nameLabel = npcWindow:recursiveGetChildById('npcNameLabel')
  local npcOutfitWidget = npcWindow:recursiveGetChildById('npcOutfit')
  local npcOutfitMultiple = npcWindow:recursiveGetChildById('npcOutfitMultiple')

  -- Collect all known IDs that still exist on the map
  local names = {}
  local firstOutfit = nil
  for id in pairs(knownNpcIds) do
    local creature = g_map.getCreatureById(id)
    if creature then
      table.insert(names, creature:getName())
      if not firstOutfit then firstOutfit = { outfit = creature:getOutfit(), name = creature:getName() } end
    end
  end

  if #names > 1 then
    if npcOutfitWidget then npcOutfitWidget:setVisible(false) end
    if npcOutfitMultiple then npcOutfitMultiple:setVisible(true) end
    -- Sort for stable ordering so first name is always the same
    table.sort(names)
    npcName = table.concat(names, ', ')
    if nameLabel then nameLabel:setText(names[1] .. ' and others') end
  elseif #names == 1 then
    if npcOutfitMultiple then npcOutfitMultiple:setVisible(false) end
    if npcOutfitWidget then npcOutfitWidget:setVisible(true) end
    npcName = names[1]
    if nameLabel then nameLabel:setText(npcName) end
    if npcOutfitWidget and firstOutfit then npcOutfitWidget:setOutfit(firstOutfit.outfit) end
  end
end

function onNpcChatWindow(data)
  if not npcWindow then return end

  local mySession = sessionId

  -- Conversation ended
  if #data.npcIds == 0 and #data.buttons == 0 then
    currentNpcId = 0
    knownNpcIds = {}
    close()
    return
  end

  local npcId = data.npcIds[1]

  -- Detect a completely new conversation (different primary NPC and no overlap)
  local hasOverlap = false
  for _, id in ipairs(data.npcIds) do
    if knownNpcIds[id] then hasOverlap = true break end
  end

  if not hasOverlap and currentNpcId ~= 0 then
    -- Genuine NPC change: reset everything
    local nameLabel = npcWindow:recursiveGetChildById('npcNameLabel')
    local npcOutfitWidget = npcWindow:recursiveGetChildById('npcOutfit')
    local npcOutfitMultiple = npcWindow:recursiveGetChildById('npcOutfitMultiple')
    if nameLabel then nameLabel:setText('') end
    if npcOutfitWidget then npcOutfitWidget:setOutfit({}) end
    if npcOutfitMultiple then npcOutfitMultiple:setVisible(false) end
    clearContext()
    dialogStarted = false
    knownNpcIds = {}
  end

  -- Detect if any button is a trade button (iconId 0, 1 or 2).
  -- OTCV8 exposes the icon enum as `.id` (see luavaluecasts_client.cpp's
  -- setField("id")); upstream codebases sometimes use `.iconId`. Read both so
  -- this module runs unchanged on either fork.
  local hasTrade = false
  if data.buttons then
    for _, btn in ipairs(data.buttons) do
      local iconId = btn.iconId or btn.id
      if iconId == 0 or iconId == 1 or iconId == 2 then
        hasTrade = true
        break
      end
    end
  end

  -- Merge incoming IDs into the known set, preserving hasTrade once set
  for _, id in ipairs(data.npcIds) do
    local existing = knownNpcIds[id]
    knownNpcIds[id] = { hasTrade = hasTrade or (existing and existing.hasTrade or false) }
  end
  currentNpcId = npcId

  if sessionId ~= mySession then return end
  show()
  updatePedestal()

  -- Emit "Talking To" on first packet of a new conversation (covers "hi" typed manually)
  if not dialogStarted then
    local timestamp = os.date("%H:%M:%S")
    local names = {}
    for id in pairs(knownNpcIds) do
      local c = g_map.getCreatureById(id)
      if c then table.insert(names, c:getName()) end
    end
    table.sort(names)
    for _, n in ipairs(names) do
      addText(timestamp .. ' Talking To ' .. n, MessageModes.NpcFromStartBlock, '#FFFFFF')
    end
    dialogStarted = true
  end

  -- Update buttons
  local container = npcWindow:recursiveGetChildById('buttonContainer')
  if container then
    for _, child in ipairs(container:getChildren()) do
      child:setVisible(false)
      child:setWidth(0)
    end
  end
  if data.buttons then
    for _, btn in ipairs(data.buttons) do
      local iconId = btn.iconId or btn.id
      local widgetId = buttonIdMap[iconId]
      if widgetId then
        local button = npcWindow:recursiveGetChildById(widgetId)
        if button then
          button:setVisible(true)
          button:setWidth(34)
          if button.tooltip then button:setTooltip(btn.text) end
        end
      end
    end
  end
end


function findNpcCreature(name, pos)
  local spectators = g_map.getSpectators(pos, false)
  for _, creature in pairs(spectators) do
    if creature:getName() == name then
      return creature
    end
  end
  return nil
end

-- Check if any NPC is within talk range (4 tiles) of the local player
function isNpcNearby()
  local player = g_game.getLocalPlayer()
  if not player then return false end
  
  local playerPos = player:getPosition()
  if not playerPos then return false end
  
  local spectators = g_map.getSpectators(playerPos, false)
  for _, creature in pairs(spectators) do
    if creature:isNpc() then
      local creaturePos = creature:getPosition()
      if creaturePos and creaturePos.z == playerPos.z then
        local dx = math.abs(creaturePos.x - playerPos.x)
        local dy = math.abs(creaturePos.y - playerPos.y)
        if dx <= 4 and dy <= 4 then
          return true
        end
      end
    end
  end
  return false
end

-- Find the nearest NPC within talk range (4 tiles)
function findNearestNpc()
  local player = g_game.getLocalPlayer()
  if not player then return nil end
  
  local playerPos = player:getPosition()
  if not playerPos then return nil end
  
  local bestNpc = nil
  local bestDist = 999
  
  local spectators = g_map.getSpectators(playerPos, false)
  for _, creature in pairs(spectators) do
    if creature:isNpc() then
      local creaturePos = creature:getPosition()
      if creaturePos and creaturePos.z == playerPos.z then
        local dx = math.abs(creaturePos.x - playerPos.x)
        local dy = math.abs(creaturePos.y - playerPos.y)
        if dx <= 4 and dy <= 4 then
          local dist = math.max(dx, dy)
          if dist < bestDist then
            bestDist = dist
            bestNpc = creature
          end
        end
      end
    end
  end
  return bestNpc
end

function clearContext()
  if not npcWindow then return end
  local panel = npcWindow:recursiveGetChildById('dialogPanel')
  if panel then
    panel:destroyChildren()
  end
end

local function npcNameContains(fullName, singleName)
  if not fullName or not singleName then return false end
  for part in fullName:gmatch('[^,]+') do
    if part:match('^%s*(.-)%s*$') == singleName then return true end
  end
  return false
end

function onTalk(name, level, mode, text, channelId, creaturePos)
  -- Ignore messages that arrive after the window was closed
  if not npcWindow or not npcWindow:isVisible() then return end
  if mode == MessageModes.NpcFromStartBlock then
    -- Only reset context when talking to a completely different NPC
    local isKnownNpc = npcNameContains(npcName, name) or npcName == name
    if not isKnownNpc then
      clearContext()
      dialogStarted = false
      npcName = name
    end

    addText(name .. ' says: ' .. text, mode)

  elseif mode == MessageModes.NpcFrom then
    addText(name .. ' says: ' .. text, mode)

  elseif mode == MessageModes.NpcTo then
    addText(name .. ': ' .. text, mode)
  end
end

function doBalance()
  sendTalk('balance')
end

function doDepositAll()
  sendTalk('deposit all')
end

function doWithdraw()
  sendTalk('withdraw')
end

function doSail()
  sendTalk('sail')
end

function doYes()
  sendTalk('yes')
end

function doNo()
  sendTalk('no')
end

function doTrade()
  sendTalk('trade')
end

function doBye()
  g_game.closeNpcChannel()
  close()
end

function doChatToggle()
  local chatButton = npcWindow:recursiveGetChildById('chatButton')
  local textInput = npcWindow:recursiveGetChildById('textInput')
  
  if chatButton:getText() == tr('Chat On') then
    chatButton:setText(tr('Chat Off'))
    textInput:setEnabled(false)
    textInput:clearFocus()
  else
    chatButton:setText(tr('Chat On'))
    textInput:setEnabled(true)
    textInput:focus()
  end
end

function getWindow()
  return npcWindow
end

function getNpcName()
  return npcName
end

function getTradeContainer()
  if npcWindow then
    return npcWindow:recursiveGetChildById('tradeContainer')
  end
  return nil
end

-- Verifica se a janela do NPC está expandida para trade
function isExpanded()
  if npcWindow then
    return npcWindow:getWidth() >= 600
  end
  return false
end

-- Expande a janela para acomodar o trade
function expandForTrade()
  if npcWindow then
    npcWindow:setWidth(600)
    local separator = npcWindow:recursiveGetChildById('separator')
    if separator then separator:setVisible(true) end
  end
end

function onTextSubmit()
  local textInput = npcWindow:recursiveGetChildById('textInput')
  local text = textInput:getText()
  if #text > 0 then
    sendTalk(text)
    textInput:setText('')
  end
end
