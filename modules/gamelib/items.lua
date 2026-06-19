ItemsDatabase = ItemsDatabase or {}

local knownNpcPriceFallbacks = {
  [2173] = 50000, -- Amulet of Loss on older protocol ids
  [3057] = 50000, -- Amulet of Loss on current client ids
}

local function toPositiveNumber(value)
  value = tonumber(value) or 0
  if value < 0 then
    return 0
  end
  return value
end

local function safeCall(object, method)
  if not object then
    return nil
  end

  local ok, fn = pcall(function()
    return object[method]
  end)
  if not ok or not fn then
    return nil
  end

  local ok, value = pcall(fn, object)
  if ok then
    return value
  end
  return nil
end

local function getItemId(item)
  if type(item) == "number" then
    return toPositiveNumber(item)
  end
  return toPositiveNumber(safeCall(item, "getId"))
end

local function getItemThingType(itemId)
  if itemId <= 0 or not g_things or not g_things.getThingType then
    return nil
  end

  local ok, thingType = pcall(function()
    return g_things.getThingType(itemId, ThingCategoryItem)
  end)
  if ok and thingType then
    return thingType
  end

  ok, thingType = pcall(function()
    return g_things.getThingType(itemId)
  end)
  if ok then
    return thingType
  end
  return nil
end

local function getLoadedMarketValue(itemId)
  if itemId <= 0 or not g_things or not g_things.getItemsPrice then
    return 0
  end

  local ok, prices = pcall(g_things.getItemsPrice)
  if not ok or type(prices) ~= "table" then
    return 0
  end

  return math.max(toPositiveNumber(prices[itemId]), toPositiveNumber(prices[tostring(itemId)]))
end

local function getNpcPriceValue(data)
  if type(data) ~= "table" then
    return 0
  end

  local value = 0
  for _, entry in pairs(data) do
    if type(entry) == "table" then
      value = math.max(
        value,
        toPositiveNumber(entry.buyPrice),
        toPositiveNumber(entry.salePrice),
        toPositiveNumber(entry.buy_price),
        toPositiveNumber(entry.sale_price),
        toPositiveNumber(entry.price),
        toPositiveNumber(entry.value),
        toPositiveNumber(entry[3]),
        toPositiveNumber(entry[4])
      )
    end
  end
  return value
end

local function getRarityFrameOption()
  return "frames"
end

local rarityFrames = {
  { minValue = 1000000, level = 5, name = "gold", frame = "/images/ui/rarity_gold_frame", tag = "/images/ui/rarity_gold_tag" },
  { minValue = 100000, level = 4, name = "purple", frame = "/images/ui/rarity_purple_frame", tag = "/images/ui/rarity_purple_tag" },
  { minValue = 10000, level = 3, name = "blue", frame = "/images/ui/rarity_blue_frame", tag = "/images/ui/rarity_blue_tag" },
  { minValue = 1000, level = 2, name = "green", frame = "/images/ui/rarity_green_frame", tag = "/images/ui/rarity_green_tag" },
  { minValue = 1, level = 1, name = "white", frame = "/images/ui/rarity_white_frame", tag = "/images/ui/rarity_white_tag" },
}

local rarityFrameSources = {
  ["/images/ui/rarity_frames"] = true,
  ["/images/ui/rarity_frames.png"] = true,
}

for _, rarity in ipairs(rarityFrames) do
  rarityFrameSources[rarity.frame] = true
  rarityFrameSources[rarity.frame .. ".png"] = true
  rarityFrameSources[rarity.tag] = true
  rarityFrameSources[rarity.tag .. ".png"] = true
end

local function rememberDefaultItemImage(widget)
  if widget._rarityDefaultImageRemembered then
    return
  end

  widget._rarityDefaultImageRemembered = true
  if widget.getImageSource then
    local source = widget:getImageSource()
    if source and not rarityFrameSources[source] then
      widget._rarityDefaultImageSource = source
    end
  end
  if widget.getImageClip then
    widget._rarityDefaultImageClip = widget:getImageClip()
  end
end

local function clearWidgetIcon(widget)
  if widget.setIcon then
    widget:setIcon("")
  end
  if widget.setIconClip then
    widget:setIconClip(torect("0 0 0 0"))
  end
end

local function restoreDefaultItemImage(widget)
  if widget.setImageSource and widget._rarityDefaultImageSource then
    widget:setImageSource(widget._rarityDefaultImageSource)
  end
  if widget.setImageClip and widget._rarityDefaultImageClip then
    widget:setImageClip(widget._rarityDefaultImageClip)
  end
end

local function setRarityFrame(widget, frameSource)
  if not widget.setImageSource then
    return
  end

  -- in case there's an old frame child from previous logic, hide it
  if widget.getChildById then
    local oldFrame = widget:getChildById('rarityFrame')
    if oldFrame then oldFrame:setVisible(false) end
  end

  clearWidgetIcon(widget)
  widget:setImageSource(frameSource)
  if widget.setImageClip then
    widget:setImageClip(torect("0 0 0 0"))
  end
end

function ItemsDatabase.getRarityInfoByValue(value)
  value = toPositiveNumber(value)
  for _, rarity in ipairs(rarityFrames) do
    if value >= rarity.minValue then
      return rarity
    end
  end
  return nil
end

function ItemsDatabase.getRarityFrameByValue(value, useTag)
  local rarity = ItemsDatabase.getRarityInfoByValue(value)
  if not rarity then
    return nil
  end
  return useTag and rarity.tag or rarity.frame
end

function ItemsDatabase.getRarityValue(item, valueOverride)
  local value = toPositiveNumber(valueOverride)
  if value > 0 then
    return value
  end

  local itemId = getItemId(item)
  local itemObject = type(item) ~= "number" and item or nil
  if not itemObject and itemId > 0 and rawget(_G, "Item") and Item.create then
    local ok, createdItem = pcall(function()
      return Item.create(itemId)
    end)
    if ok then
      itemObject = createdItem
    end
  end
  local thingType = getItemThingType(itemId)

  value = math.max(value, getLoadedMarketValue(itemId))
  value = math.max(value, toPositiveNumber(knownNpcPriceFallbacks[itemId]))

  local cyclopediaItems = rawget(_G, "CyclopediaItems")
  if not cyclopediaItems and rawget(_G, "modules") and modules.game_cyclopedia then
    cyclopediaItems = modules.game_cyclopedia.CyclopediaItems
  end
  if itemObject and cyclopediaItems and cyclopediaItems.getCurrentItemValue then
    local ok, currentValue = pcall(function()
      return cyclopediaItems.getCurrentItemValue(itemObject)
    end)
    if ok then
      value = math.max(value, toPositiveNumber(currentValue))
    end
  end

  value = math.max(
    value,
    toPositiveNumber(safeCall(itemObject, "getAverageMarketValue")),
    toPositiveNumber(safeCall(itemObject, "getRarityValue")),
    toPositiveNumber(safeCall(itemObject, "getMeanPrice")),
    toPositiveNumber(safeCall(itemObject, "getPriceValue")),
    toPositiveNumber(safeCall(itemObject, "getDefaultValue")),
    toPositiveNumber(safeCall(itemObject, "getDefaultBuyPrice")),
    toPositiveNumber(safeCall(itemObject, "getDefaultSellPrice")),
    toPositiveNumber(safeCall(thingType, "getAverageMarketValue")),
    toPositiveNumber(safeCall(thingType, "getMeanPrice")),
    toPositiveNumber(safeCall(thingType, "getPriceValue")),
    toPositiveNumber(safeCall(thingType, "getDefaultValue")),
    toPositiveNumber(safeCall(thingType, "getDefaultBuyPrice")),
    toPositiveNumber(safeCall(thingType, "getDefaultSellPrice"))
  )

  value = math.max(
    value,
    getNpcPriceValue(safeCall(itemObject, "getNPCSaleData")),
    getNpcPriceValue(safeCall(itemObject, "getNpcSaleData")),
    getNpcPriceValue(safeCall(thingType, "getNPCSaleData")),
    getNpcPriceValue(safeCall(thingType, "getNpcSaleData"))
  )

  return value
end

function ItemsDatabase.getRarityInfo(item, valueOverride)
  return ItemsDatabase.getRarityInfoByValue(ItemsDatabase.getRarityValue(item, valueOverride))
end

function ItemsDatabase.getRarityLevel(item, valueOverride)
  local rarity = ItemsDatabase.getRarityInfo(item, valueOverride)
  return rarity and rarity.level or 0
end

function ItemsDatabase.getRarityName(item, valueOverride)
  local rarity = ItemsDatabase.getRarityInfo(item, valueOverride)
  return rarity and rarity.name or nil
end

function ItemsDatabase.getRarityFrame(item, valueOverride, useTag)
  return ItemsDatabase.getRarityFrameByValue(ItemsDatabase.getRarityValue(item, valueOverride), useTag)
end

function ItemsDatabase.getColorizedFrame(item, valueOverride, lightGrayBackground)
  return ItemsDatabase.getRarityFrame(item, valueOverride, false)
end

if rawget(_G, "Item") then
  function Item:getColorizedFrame(lightGrayBackground)
    return ItemsDatabase.getColorizedFrame(self, nil, lightGrayBackground)
  end
end

function ItemsDatabase.setTier(widget, item, isSmall)
  if not g_game.getFeature(GameThingUpgradeClassification) or not widget or not widget.tier then
    return
  end

  if isSmall == nil then
    isSmall = true
  end

  local tier = type(item) == "number" and item or (item and item.getTier and item:getTier()) or 0
  if tier <= 0 then
    widget.tier:setVisible(false)
    return
  end

  local normalizedTier = math.min(math.max(tier, 1), isSmall and 10 or 10)
  local width = isSmall and 9 or 18
  local height = isSmall and 8 or 16
  local source = isSmall and "/images/game/items/tiers-strip" or "/images/game/items/tiers-strip-big"

  widget.tier:setImageSource(source)
  widget.tier:setImageClip({
    x = (normalizedTier - 1) * width,
    y = 0,
    width = width,
    height = height
  })
  widget.tier:setImageSize(string.format("%d %d", width, height))
  widget.tier:setSize(string.format("%d %d", width, height))
  widget.tier:setVisible(true)
end

function ItemsDatabase.setRarityItem(widget, item, valueOverride)
  if not widget then
    return
  end

  local function clearRarityFrame()
    clearWidgetIcon(widget)
    restoreDefaultItemImage(widget)
    if widget.getChildById then
      local frame = widget:getChildById('rarityFrame')
      if frame then
        frame:setVisible(false)
      end
    end
  end

  if widget._skipRarityFrame or not item then
    clearRarityFrame()
    return
  end

  rememberDefaultItemImage(widget)

  local frameOption = getRarityFrameOption()
  if frameOption == "none" then
    clearRarityFrame()
    return
  end

  local frameSource = ItemsDatabase.getRarityFrame(item, valueOverride, frameOption == "tags")
  if not frameSource then
    clearRarityFrame()
    return
  end

  clearWidgetIcon(widget)
  setRarityFrame(widget, frameSource)

  local tier = widget:getChildById('tier')
  if tier and tier.raise then
    tier:raise()
  end

  local quickLootFlags = widget:getChildById('quicklootflags')
  if quickLootFlags and quickLootFlags.raise then
    quickLootFlags:raise()
  end
end
