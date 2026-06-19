blessingWindow = nil

local blessingIcons = {
  ["2"] = "/images/game/blessings/blessings-icons_9",
  ["4"] = "/images/game/blessings/blessings-icons_4",
  ["8"] = "/images/game/blessings/blessings-icons_6",
  ["16"] = "/images/game/blessings/blessings-icons_3",
  ["32"] = "/images/game/blessings/blessings-icons_5",
  ["64"] = "/images/game/blessings/blessings-icons_2",
  ["128"] = "/images/game/blessings/blessings-icons_7",
  ["256"] = "/images/game/blessings/blessings-icons_8"
}

local blessingInfo = {
  ["2"] = {
    name = "Twist of Fate",
    description = "Protects your regular blessings and amulet of loss on a PvP death."
  },
  ["4"] = {
    name = "The Wisdom of Solitude",
    description = "Reduces experience and skill loss and improves equipment protection."
  },
  ["8"] = {
    name = "The Spark of the Phoenix",
    description = "Reduces experience and skill loss and improves equipment protection."
  },
  ["16"] = {
    name = "The Fire of the Suns",
    description = "Reduces experience and skill loss and improves equipment protection."
  },
  ["32"] = {
    name = "The Spiritual Shielding",
    description = "Reduces experience and skill loss and improves equipment protection."
  },
  ["64"] = {
    name = "The Embrace of Tibia",
    description = "Reduces experience and skill loss and improves equipment protection."
  },
  ["128"] = {
    name = "Heart of the Mountain",
    description = "Reduces experience and skill loss and improves equipment protection."
  },
  ["256"] = {
    name = "Blood of the Mountain",
    description = "Reduces experience and skill loss and improves equipment protection."
  }
}

local function normalizeBlessDialog(dataOrBlesses, premium, promotion, pvpMinXpLoss, pvpMaxXpLoss, pveExpLoss, equipPvpLoss, equipPveLoss, skull, aol, logger)
  if type(dataOrBlesses) == "table" and dataOrBlesses.blesses then
    return dataOrBlesses
  end

  return {
    blesses = dataOrBlesses or {},
    premium = premium or 0,
    promotion = promotion or 0,
    pvpMinXpLoss = pvpMinXpLoss or 0,
    pvpMaxXpLoss = pvpMaxXpLoss or 0,
    pveExpLoss = pveExpLoss or 0,
    equipPvpLoss = equipPvpLoss or 0,
    equipPveLoss = equipPveLoss or 0,
    skull = skull or 0,
    aol = aol or 0,
    logs = logger or {}
  }
end

local function getBlessField(content, field, index, default)
  if type(content) ~= "table" then
    return default
  end
  local value = content[field]
  if value == nil then
    value = content[index]
  end
  return value == nil and default or value
end

local function getBlessInfo(blessBitwise)
  return blessingInfo[tostring(blessBitwise)] or {
    name = string.format("Blessing %s", tostring(blessBitwise)),
    description = "Blessing information was not received from the server."
  }
end

local function colorText(text, color)
  return string.format("{%s,%s}", tostring(text), color)
end

local function hasBit(value, mask)
  if Bit and Bit.hasBit then
    return Bit.hasBit(value, mask)
  end
  if bit and bit.band then
    return bit.band(value, mask) ~= 0
  end
  return false
end

local function hasAdventurerBlessing()
  local player = g_game.getLocalPlayer()
  if not player or not player.getBlessings then
    return false
  end

  local adventurerMask = Blessings and Blessings.Adventurer or 1
  return hasBit(player:getBlessings(), adventurerMask)
end

local function hasPremiumStatus()
  local player = g_game.getLocalPlayer()
  return player and player.isPremium and player:isPremium() or false
end

local function createHistoryLine(historyList, dateText, message, color)
  local label = g_ui.createWidget("BlessingHistoryLabel", historyList)
  label:setText(string.format("%-18s %s", dateText or "", message or ""))
  label:setColor(color or "#c0c0c0")
  return label
end

local function updateHistory(logs, blesses)
  if not historyWindow then
    return
  end

  local historyList = historyWindow:recursiveGetChildById("historyList")
  if not historyList then
    return
  end

  historyList:destroyChildren()

  if logs and #logs > 0 then
    for _, log in ipairs(logs) do
      local timestamp = tonumber(log.timestamp or log[1] or 0) or 0
      local message = log.historyMessage or log.message or log[3] or ""
      local dateText = timestamp > 0 and os.date("%Y-%m-%d %H:%M", timestamp) or ""
      createHistoryLine(historyList, dateText, message, log.colorMessage == 1 and "#d33c3c" or "#c0c0c0")
    end
    return
  end

  createHistoryLine(historyList, "", "Current Record of Blessings", "#f0d48a")
  local hasAnyBlessing = false
  for _, content in ipairs(blesses or {}) do
    local blessBitwise = getBlessField(content, "blessBitwise", 1, 0)
    local blessCount = tonumber(getBlessField(content, "playerBlessCount", 2, 0)) or 0
    local storeCount = tonumber(getBlessField(content, "store", 3, 0)) or 0
    local blessInfo = getBlessInfo(blessBitwise)
    if blessCount > 0 or storeCount > 0 then
      hasAnyBlessing = true
      createHistoryLine(historyList, "", string.format("%s: %d active, %d in store", blessInfo.name, blessCount, storeCount), blessCount > 0 and "#c0c0c0" or "#909090")
    end
  end

  if hasAdventurerBlessing() then
    hasAnyBlessing = true
    createHistoryLine(historyList, "", "Adventure Blessing: active", "#44ad25")
  end

  if not hasAnyBlessing then
    createHistoryLine(historyList, "", "No blessing records are currently active.", "#909090")
  end
end

function init()
  blessingWindow = g_ui.displayUI('blessing')
  historyWindow = g_ui.displayUI('history')
  blessingWindow:hide()
  historyWindow:hide()


  connect(g_game, {
    onGameEnd = offline,
    onUpdateBlessDialog = onBlessingDialog,
    onBlessingDialog = onBlessingDialog,
  })

end

function history()
  if blessingWindow:isVisible() then
    g_client.setInputLockWidget(nil)
    blessingWindow:hide()
    historyWindow:show()
    g_client.setInputLockWidget(historyWindow)
  else
    g_client.setInputLockWidget(nil)
    historyWindow:hide()
    blessingWindow:show()
    g_client.setInputLockWidget(blessingWindow)

  end
end

function terminate()
  disconnect(g_game, {
    onGameEnd = offline,
    onUpdateBlessDialog = onBlessingDialog,
    onBlessingDialog = onBlessingDialog,
  })

  blessingWindow:destroy()
  historyWindow:destroy()
end

function show()
  g_game.requestBlessings()
end

function closeBlessing()
  blessingWindow:hide()
  g_client.setInputLockWidget(nil)
end

function closeBlessHistory()
  historyWindow:hide()
  g_client.setInputLockWidget(nil)
end

function offline()
  blessingWindow:hide()
  g_client.setInputLockWidget(nil)
end

function onBlessingDialog(blesses, premium, promotion, pvpMinXpLoss, pvpMaxXpLoss, pveExpLoss, equipPvpLoss, equipPveLoss, skull, aol, logger)
  local data = normalizeBlessDialog(blesses, premium, promotion, pvpMinXpLoss, pvpMaxXpLoss, pveExpLoss, equipPvpLoss, equipPveLoss, skull, aol, logger)
  blessingWindow:show(true)
  blessingWindow:focus()
  g_client.setInputLockWidget(blessingWindow)
  blessingWindow.miniWindowBlessing.blessings:destroyChildren()
  for i, content in pairs(data.blesses or {}) do
    local widget = g_ui.createWidget('BlessingWidget', blessingWindow.miniWindowBlessing.blessings)

    local blessBitwise = getBlessField(content, "blessBitwise", 1, 0)
    local blessCount = tonumber(getBlessField(content, "playerBlessCount", 2, 0)) or 0
    local storeCount = tonumber(getBlessField(content, "store", 3, 0)) or 0
    local blessInfo = getBlessInfo(blessBitwise)
    local tooltip = string.format("%s\n%s\nOwned: %d\nStore: %d", blessInfo.name, blessInfo.description, blessCount, storeCount)

    widget:setTooltip(tooltip)
    widget.containerImage:setTooltip(tooltip)
    widget.containerImage.image:setTooltip(tooltip)
    widget.containerImage.image:setImageSource(blessingIcons[tostring(blessBitwise)] or blessingIcons["4"])
    widget.containerCount:setTooltip(tooltip)
    widget.containerCount:setText(string.format('%d (%d)', blessCount, storeCount))
    if blessCount < 1 then
      widget.containerCount:setVisible(false)
      widget.storeButton:setVisible(true)
      widget.storeButton:setTooltip(string.format("Buy %s in the Store", blessInfo.name))
    end
  end

  local isPromoted = tonumber(data.premium) == 1
  local isPremium = hasPremiumStatus()
  local promotionText = "\n"
  promotionText = promotionText .. "Premium Status: " .. colorText(isPremium and "active" or "not active", isPremium and "#44ad25" or "#f75f5f") .. ".\n"
  promotionText = promotionText .. "Promotion: " .. colorText(isPromoted and "active" or "not active", isPromoted and "#44ad25" or "#f75f5f")
  promotionText = promotionText .. ", death penalty reduction " .. colorText((isPromoted and (tonumber(data.promotion) or 0) or 0) .. "%", "#f75f5f") .. "."

  if hasAdventurerBlessing() then
    promotionText = promotionText .. "\nAdventure Blessings: " .. colorText("active", "#44ad25") .. ". They protect young adventurers from death penalty losses."
  else
    promotionText = promotionText .. "\nAdventure Blessings: " .. colorText("not active", "#f75f5f") .. "."
  end

  blessingWindow.miniWindowPromotion.label:setColoredText(promotionText)


  local messageT = "- Depending on the fair fight rules, you will lose between " .. colorText((data.pvpMinXpLoss or 0) .. "%", "#f75f5f") .. " and " .. colorText((data.pvpMaxXpLoss or 0) .. "%", "#f75f5f") .. " less XP and skill points upon your next PvP death.\n- You will lose " ..
  colorText((data.pveExpLoss or 0) .. "%", "#f75f5f") .. " less XP and skill points upon your next PvE death.\n- There is a " ..
  colorText((data.equipPvpLoss or 0) .. "%", "#f75f5f") .. " chance that you will lose your equipped container on your next death.\n- There is a " .. colorText((data.equipPveLoss or 0) .. "%", "#f75f5f") .. " chance that you will lose items upon your next death."


  blessingWindow.miniWindowInfo.label:setColoredText(messageT)
  updateHistory(data.logs, data.blesses)
end
