if not RealMap then
    RealMap = {
        loaded = false,
        settings = {},
    }
end

if not g_realMinimap then
  local regionId = 0
  local enabledRegions = {}
  local currentHousePosition = { x = 0, y = 0, z = 7 }

  g_realMinimap = {
    loadImage = function(path, view, topLeft, tilesPerPixel, fromScale, toScale)
      if not g_satelliteMap or not g_satelliteMap.loadImage then
        return 0
      end
      return g_satelliteMap.loadImage(path, view or "realmap", topLeft or { x = 0, y = 0, z = 7 }, tilesPerPixel or 1, fromScale or 0, toScale or 100)
    end,

    loadRegion = function(image, fromPos, scale, fromZoom, toZoom, markedColor, areaId)
      regionId = regionId + 1
      return regionId
    end,

    enableRegion = function(id)
      enabledRegions[id] = true
      return true
    end,

    disableRegion = function(id)
      enabledRegions[id] = nil
      return true
    end,

    clean = function()
      enabledRegions = {}
    end,

    addWidget = function()
      return 0
    end,

    removeWidget = function()
      return true
    end,

    changeHouseFloor = function(upper)
      local nextPos = {
        x = currentHousePosition.x,
        y = currentHousePosition.y,
        z = currentHousePosition.z + (upper and -1 or 1)
      }
      if nextPos.z < 0 then nextPos.z = 0 end
      if nextPos.z > 15 then nextPos.z = 15 end
      currentHousePosition = nextPos
      return currentHousePosition.z
    end,

    getHousePosition = function()
      return currentHousePosition
    end,

    setHousePosition = function(position)
      if position then
        currentHousePosition = { x = position.x or 0, y = position.y or 0, z = position.z or 7 }
      end
    end,
  }
end

local flagToFilePath = {
  ["up"] = "data/images/game/minimap/flag18.png",
  ["flag"] = "data/images/game/minimap/flag9.png",
  ["skull"] = "data/images/game/minimap/flag12.png",
  ["crossmark"] = "data/images/game/minimap/flag4.png",
  ["star"] = "data/images/game/minimap/flag3.png",
  ["sword"] = "data/images/game/minimap/flag8.png",
  ["red up"] = "data/images/game/minimap/flag14.png",
  ["?"] = "data/images/game/minimap/flag1.png",
  ["checkmark"] = "data/images/game/minimap/flag0.png",
  ["red left"] = "data/images/game/minimap/flag17.png",
  ["red right"] = "data/images/game/minimap/flag16.png",
  ["!"] = "data/images/game/minimap/flag2.png",
  ["down"] = "data/images/game/minimap/flag19.png",
  ["mouth"] = "data/images/game/minimap/flag6.png",
  ["lock"] = "data/images/game/minimap/flag10.png",
  ["red down"] = "data/images/game/minimap/flag15.png",
  ["bag"] = "data/images/game/minimap/flag11.png",
  ["cross"] = "data/images/game/minimap/flag5.png",
  ["spear"] = "data/images/game/minimap/flag7.png",
  ["$"] = "data/images/game/minimap/flag13.png",
}

local function getRealMinimap()
  if g_realMinimap and g_realMinimap.loadRegion and g_realMinimap.enableRegion and g_realMinimap.disableRegion then
    return g_realMinimap
  end
  return nil
end

function RealMap.load(force)
    if RealMap.loaded and not force then
        return
    end

    if g_satelliteMap and g_satelliteMap.loadDirectory and g_game.getClientVersion() > 0 then
      local clientVersion = g_game.getClientVersion()
      local chunksDir = string.format('/realmap/%d', clientVersion)
      local loaded = 0
      if g_resources.directoryExists and g_resources.directoryExists(chunksDir) then
        loaded = g_satelliteMap.loadDirectory(chunksDir)
      end
      if loaded <= 0 then
        g_satelliteMap.loadDirectory(string.format('/things/%d', clientVersion))
      end
    end

    if not RealMap.loaded then
        RealMap.settings = g_settings.getNode('game_minimap') or { ignoreFlag = {} }
        RealMap.setMarkers()
    end
    RealMap.loaded = true
end

-- Convenience: force-reload chunks (e.g. if a tab cleared the satellite cache).
-- Keeps Lua-side state (markers, regions) intact.
function RealMap.reloadChunks()
    RealMap.load(true)
end

function RealMap.unload()
    if g_realMinimap and g_realMinimap.clean then
      g_realMinimap:clean()
    end
end

function RealMap.setIgnoreFlag(position)
    RealMap.settings.ignoreFlag[position.x .. ',' .. position.y .. ',' .. position.z] = true

    local settings = {}
    settings.ignoreFlag = RealMap.settings.ignoreFlag
    g_settings.setNode('game_minimap', settings)
end

function RealMap.setRegions(minimapWidget, mainAreaId, regions)
  local realMinimap = getRealMinimap()

  if not minimapWidget.selectedCity then
    minimapWidget.selectedCity = 0
    minimapWidget.selectedRegions = {}
  end

  if realMinimap then
    for _, region in pairs(minimapWidget.selectedRegions) do
      realMinimap.disableRegion(region)
    end
  end

  if minimapWidget.selectedCity == mainAreaId then
    minimapWidget:setSelectedCity(0)
    return
  end

  minimapWidget.selectedCity = mainAreaId
  if realMinimap and regions then
    for _, region in pairs(RealMap.regions or {}) do
      if table.contains(regions, region.areaId) then
        local imageId = realMinimap.loadRegion(region.image, region.fromPos, 1, 0, 64, region.markedColor, region.areaId)
        realMinimap.enableRegion(imageId)
        minimapWidget.selectedRegions[#minimapWidget.selectedRegions + 1] = imageId
      end
    end
  end

  modules.game_cyclopedia.MapCyclopedia.setImprovevedValue(mainAreaId)

  if realMinimap and minimapWidget.selectedRegion then
    realMinimap.disableRegion(minimapWidget.selectedRegion.id)
    minimapWidget.selectedRegion = nil
  end
end

function RealMap.setRegion(minimapWidget)
  local realMinimap = getRealMinimap()
  if not RealMap.regions then
    return
  end
  if minimapWidget.realMapRegionsRegistered then
    return
  end
  minimapWidget.realMapRegionsRegistered = true

  for _, region in pairs(RealMap.regions) do
    local imageId = nil
    if realMinimap then
      imageId = realMinimap.loadRegion(region.image, region.fromPos, 1, 0, 64, region.markedColor, region.areaId)
    end

    minimapWidget:addCustomMouseEvent(MouseLeftButton, region.fromPos, region.toPos, function(self, mapPos, mousePos)
      if realMinimap and self.hasClickedRegion and not self:hasClickedRegion(imageId, mapPos) then
        return false
      end

      minimapWidget:setSelectedCity(0)
      if minimapWidget.selectedCity and minimapWidget.selectedCity > 0 then
        if realMinimap then
          for _, selectedRegion in pairs(minimapWidget.selectedRegions) do
            realMinimap.disableRegion(selectedRegion)
          end
        end
        minimapWidget.selectedRegions = {}
        minimapWidget.selectedCity = 0
      end

      if minimapWidget.selectedRegion then
        if minimapWidget.selectedRegion.id == imageId then
          -- if it is the same, just remove it
          if realMinimap then
            realMinimap.disableRegion(minimapWidget.selectedRegion.id)
          end
          minimapWidget.selectedRegion = nil
          return true
        end

        -- if it is another one, then we disable it, and continue to enable
        -- a new one (keeping only one selected)
        if realMinimap then
          realMinimap.disableRegion(minimapWidget.selectedRegion.id)
        end
        minimapWidget.selectedRegion = nil
      end

      minimapWidget.selectedRegion = {region = region, id = imageId}
      if realMinimap then
        realMinimap.enableRegion(imageId)
      end

      local areaName, subAreaName = self:getAreaNameById(region.areaId)
      modules.game_cyclopedia.MapCyclopedia.onChangeArea(areaName, subAreaName)
      modules.game_cyclopedia.MapCyclopedia.setImprovevedValue(region.areaId)
      if g_game.setCyclopediaMapCurrentArea then
        g_game.setCyclopediaMapCurrentArea(region.areaId)
      end

      return true
    end, true)
  end
end

function RealMap.setCameraPosition(widget, pos)
    widget:setCameraPosition(pos)
end

function RealMap.getCameraPosition(widget)
  widget:getCameraPosition()
end

function RealMap.setCrossPosition(widget, pos)
    widget:setCrossPosition(pos)
end

function RealMap.hideCross(widget)
  widget:hideCross()
end

function RealMap.setZoom(widget, zoom)
  widget:setZoom(zoom)
end

function RealMap.setMarkers()
  local ignoreFlag = RealMap.settings.ignoreFlag and RealMap.settings.ignoreFlag or {}
  for _, markerInfo in pairs(RealMap.markers or {}) do
    local filePath = flagToFilePath[markerInfo.icon]
    if filePath then
      -- g_realMinimap.addWidget(filePath, {width = 11, height = 11}, markerInfo.pos, markerInfo.description)
      if g_minimap.addWidget and not ignoreFlag[markerInfo.pos.x .. ',' .. markerInfo.pos.y .. ',' .. markerInfo.pos.z] then
        g_minimap.addWidget(filePath, {width = 11, height = 11}, markerInfo.pos, markerInfo.description)
      end
    else
      print(markerInfo.icon, "not loaded!")
    end
  end
end

function RealMap.setUIMarkers(widget, centerPos, maxDistance)
  local added = 0
  maxDistance = maxDistance or 0

  for _, markerInfo in pairs(RealMap.markers or {}) do
    local filePath = flagToFilePath[markerInfo.icon]
    if filePath then
      local pos = markerInfo.pos
      local inRange = not centerPos or maxDistance <= 0 or (
        pos.z == centerPos.z and
        math.abs(pos.x - centerPos.x) <= maxDistance and
        math.abs(pos.y - centerPos.y) <= maxDistance
      )
      if inRange then
        widget:addWidget(filePath, {width = 11, height = 11}, pos, markerInfo.description)
        added = added + 1
      end
    else
      print(markerInfo.icon, "not loaded!")
    end
  end

  return added
end

function RealMap.setLevelSeparator(widget, levelSeparator)
  widget:setLevelSeparator(levelSeparator)
end
