if not MinimapLoader then
  MinimapLoader = {
    loaded = false
  }
  MinimapLoader.__index = MinimapLoader
end

minimapWidget = nil
minimapWindow = nil
otmm = true
preloaded = false
fullmapView = false
oldZoom = nil
oldPos = nil
local HD_MAP_MAX_ZOOM = 8
local HD_MAP_TARGET_ZOOM = 4
local HD_MAP_FLOOR_SEPARATOR_OPACITY = 0.0
local hdMapModeEnabled = false
local hdMapPreviousMaxZoom = nil
local hdMapPreviousZoom = nil
local hdMapLastViewKey = nil
local staticMarkWidgets = {}
local trackedRouteWidgets = {}
local otmmLoadEvent = nil
local staticMarkStartEvent = nil
local staticMarkLoadEvent = nil
local staticMarkViewportEvent = nil
local staticMarkRenderToken = 0
local staticMarksRenderedFileTime = nil
local staticMarksIndex = nil
local staticMarksCache = {
  fileTime = nil,
  entries = nil
}
local STATIC_MARK_BATCH_SIZE = 32
local STATIC_MARK_BATCH_DELAY = 8
local STATIC_MARK_START_DELAY = 900
local STATIC_MARK_CELL_SIZE = 256
local STATIC_MARK_VIEW_MARGIN = 256
local STATIC_MARK_MIN_RADIUS = 220
local STATIC_MARK_MAX_ACTIVE = 300
local STATIC_MARK_UPDATE_DELAY = 250
local TRACKED_ROUTE_MAX_WIDGETS = 120
local TRACKED_ROUTE_SAMPLE_STEP = 2
local TRACKED_ROUTE_ICON = '/data/images/game/minimap/icon/icon-map-passage-selected.png'
local TRACKED_ROUTE_ICON_SIZE = { width = 11, height = 11 }
-- Default minimap zoom on login. Negative values are "zoomed out" (more area
-- visible); positive values are "zoomed in". The previous policy of halving
-- the persisted zoom still left the view too close on login, so we force a
-- fixed wide view here regardless of what the player saved. A subsequent
-- zoom-in/out by the player is preserved for the current session.
local LOGIN_ZOOM_DEFAULT = -2
local loginZoomApplied = false
local staticMarksIconConfig = {
  ["checkmark"] = 1,
  ["?"] = 2,
  ["!"] = 3,
  ["star"] = 4,
  ["crossmark"] = 5,
  ["cross"] = 7,
  ["mouth"] = 8,
  ["spear"] = 9,
  ["sword"] = 10,
  ["flag"] = 11,
  ["lock"] = 13,
  ["bag"] = 14,
  ["skull"] = 15,
  ["$"] = 16,
  ["red up"] = 17,
  ["red down"] = 19,
  ["red right"] = 20,
  ["red left"] = 21,
  ["up"] = 22,
  ["down"] = 23,
}

local keybindMoveEast = KeyBind:getKeyBind("Minimap", "Scroll East")
local keybindMoveNorth = KeyBind:getKeyBind("Minimap", "Scroll North")
local keybindMoveSouth = KeyBind:getKeyBind("Minimap", "Scroll South")
local keybindMoveWest = KeyBind:getKeyBind("Minimap", "Scroll West")
local keybindFloorUp = KeyBind:getKeyBind("Minimap", "One Floor Up")
local keybindFloorDown = KeyBind:getKeyBind("Minimap", "One Floor Down")
local keybindZoomIn = KeyBind:getKeyBind("Minimap", "Zoom In")
local keybindZoomOut = KeyBind:getKeyBind("Minimap", "Zoom Out")
local keybindCenter = KeyBind:getKeyBind("Minimap", "Center")
local keybindShowMinimap = KeyBind:getKeyBind("Minimap", "Show")

local function customStaticMarkSort(a, b)
  if (a.z >= 0 and a.z <= 7 and b.z >= 0 and b.z <= 7) or (a.z >= 8 and a.z <= 14 and b.z >= 8 and b.z <= 14) then
    return a.z > b.z
  elseif a.z >= 0 and a.z <= 7 then
    return true
  elseif b.z >= 0 and b.z <= 7 then
    return false
  else
    return a.z < b.z
  end
end

local function cancelStaticMarksLoading()
  staticMarkRenderToken = staticMarkRenderToken + 1
  if staticMarkStartEvent then
    removeEvent(staticMarkStartEvent)
    staticMarkStartEvent = nil
  end
  if staticMarkLoadEvent then
    removeEvent(staticMarkLoadEvent)
    staticMarkLoadEvent = nil
  end
  if staticMarkViewportEvent then
    removeEvent(staticMarkViewportEvent)
    staticMarkViewportEvent = nil
  end
end

local function getCachedStaticMarks(file)
  local fileTime = g_resources.getFileTime(file) or 0
  if staticMarksCache.fileTime == fileTime and staticMarksCache.entries then
    return staticMarksCache.entries, fileTime
  end

  local status, result = pcall(function()
    return json.decode(g_resources.readFileContents(file))
  end)
  if not status then
    g_logger.error("Error while reading marks file. Details: " .. result)
    return nil, fileTime
  end

  if type(result) ~= "table" then
    result = {}
  end

  table.sort(result, customStaticMarkSort)
  staticMarksCache.fileTime = fileTime
  staticMarksCache.entries = result
  return result, fileTime
end

local function getStaticMarkKey(info, index)
  return string.format('%s,%s,%s:%s:%s', tostring(info.x), tostring(info.y), tostring(info.z), tostring(info.icon), tostring(index))
end

local function buildStaticMarksIndex(marks, fileTime)
  if staticMarksIndex and staticMarksIndex.fileTime == fileTime then
    return staticMarksIndex
  end

  local index = {
    fileTime = fileTime,
    byFloor = {},
    total = #marks
  }

  for i, info in ipairs(marks) do
    local x, y, z = tonumber(info.x), tonumber(info.y), tonumber(info.z)
    local iconId = info and staticMarksIconConfig[info.icon]
    if x and y and z and iconId then
      local floor = math.floor(z)
      local cellX = math.floor(x / STATIC_MARK_CELL_SIZE)
      local cellY = math.floor(y / STATIC_MARK_CELL_SIZE)
      local floorIndex = index.byFloor[floor]
      if not floorIndex then
        floorIndex = {}
        index.byFloor[floor] = floorIndex
      end
      local cellKey = cellX .. ':' .. cellY
      local cell = floorIndex[cellKey]
      if not cell then
        cell = {}
        floorIndex[cellKey] = cell
      end
      cell[#cell + 1] = {
        key = getStaticMarkKey(info, i),
        x = x,
        y = y,
        z = floor,
        iconId = iconId,
        description = info.description or '',
      }
    end
  end

  staticMarksIndex = index
  return index
end

local function getMinimapPixelSize()
  if not minimapWidget then
    return 120, 120
  end
  local width = minimapWidget.getWidth and minimapWidget:getWidth() or 120
  local height = minimapWidget.getHeight and minimapWidget:getHeight() or 120
  return width, height
end

local function getStaticMarkRadius()
  local scale = minimapWidget and minimapWidget.getScale and minimapWidget:getScale() or 1
  if not scale or scale <= 0 then
    scale = 1
  end
  local width, height = getMinimapPixelSize()
  return math.max(STATIC_MARK_MIN_RADIUS, math.ceil(math.max(width, height) / scale / 2) + STATIC_MARK_VIEW_MARGIN)
end

local function collectVisibleStaticMarks(index)
  if not minimapWidget or not index then
    return {}
  end

  local center = minimapWidget:getCameraPosition()
  if not center then
    return {}
  end

  local floorIndex = index.byFloor[tonumber(center.z)]
  if not floorIndex then
    return {}
  end

  local radius = getStaticMarkRadius()
  local minCellX = math.floor((center.x - radius) / STATIC_MARK_CELL_SIZE)
  local maxCellX = math.floor((center.x + radius) / STATIC_MARK_CELL_SIZE)
  local minCellY = math.floor((center.y - radius) / STATIC_MARK_CELL_SIZE)
  local maxCellY = math.floor((center.y + radius) / STATIC_MARK_CELL_SIZE)
  local result = {}

  for cellX = minCellX, maxCellX do
    for cellY = minCellY, maxCellY do
      local cell = floorIndex[cellX .. ':' .. cellY]
      if cell then
        for _, mark in ipairs(cell) do
          local dx = math.abs(mark.x - center.x)
          local dy = math.abs(mark.y - center.y)
          if dx <= radius and dy <= radius then
            mark.distance = dx + dy
            result[#result + 1] = mark
          end
        end
      end
    end
  end

  table.sort(result, function(a, b)
    return a.distance < b.distance
  end)

  if #result > STATIC_MARK_MAX_ACTIVE then
    for i = #result, STATIC_MARK_MAX_ACTIVE + 1, -1 do
      result[i] = nil
    end
  end

  return result
end

local function getHDMapModeOption()
  -- Opcao "HD Map Mode" removida do Settings: o recurso fica sempre desligado.
  -- (Evita o erro "Option not found: hdMapModeBox" do GameOptions:getOption.)
  return false
end

local function hasLoadedSatelliteChunks(floor)
  if not g_satelliteMap then
    return false
  end
  floor = tonumber(floor) or 7
  if g_satelliteMap.hasRealMapChunksForFloor and g_satelliteMap.hasRealMapChunksForFloor(floor) then
    return true
  end
  if g_satelliteMap.hasChunksForView and g_satelliteMap.hasChunksForView(floor) then
    return true
  end
  if g_satelliteMap.hasMinimapChunksForFloor and g_satelliteMap.hasMinimapChunksForFloor(floor) then
    return true
  end
  return false
end

-- HD realmap chunk packs in this project are authored with their (posX, posY)
-- DO NOT use a fixed offset for this chunk pack — the drift is
-- position-dependent, not uniform:
--   * Issavi (33921, 31492)  → drift ≈ (-2,-4)
--   * Thais  (32349, 32215)  → drift ≈ (-14,-10)
-- A 14-tile difference between regions proves the PNG assets were
-- generated from a different `world.otbm` than what the server runs.
-- A single setRealMapTileOffset() cannot reconcile both. The real fix
-- is to regenerate the realmap-*.png chunks against the current server
-- map. Leaving the offset at zero so behavior is predictable until then.
HD_MAP_REALMAP_TILE_OFFSET_X = 0
HD_MAP_REALMAP_TILE_OFFSET_Y = 0

local function applyRealMapTileOffset()
  if g_satelliteMap and g_satelliteMap.setRealMapTileOffset then
    g_satelliteMap.setRealMapTileOffset(
      HD_MAP_REALMAP_TILE_OFFSET_X or 0,
      HD_MAP_REALMAP_TILE_OFFSET_Y or 0
    )
  end
end

local function loadHDMapAssets()
  if not g_game.isOnline or not g_game.isOnline() then
    return
  end

  local clientVersion = g_game.getClientVersion and g_game.getClientVersion() or 0
  if clientVersion <= 0 then
    return
  end

  applyRealMapTileOffset()

  -- Reload satellite chunks whenever the cache is empty (e.g. another tab wiped it).
  -- Without this, HD Map Mode stays dark forever after some side-modules clear chunks.
  local player = g_game.getLocalPlayer()
  local floor = player and player:getPosition() and player:getPosition().z or 7
  local needsReload = not hasLoadedSatelliteChunks(floor)

  if RealMap and RealMap.load then
    if needsReload and RealMap.reloadChunks then
      RealMap.reloadChunks()
    else
      RealMap.load()
    end
    return
  end

  if g_satelliteMap and g_satelliteMap.loadDirectory then
    local chunksDir = string.format('/realmap/%d', clientVersion)
    local loaded = 0
    if g_resources.directoryExists and g_resources.directoryExists(chunksDir) then
      loaded = g_satelliteMap.loadDirectory(chunksDir)
    end
    if loaded <= 0 then
      g_satelliteMap.loadDirectory(string.format('/things/%d', clientVersion))
    end
  end
end

local function applyHDMapViewForFloor()
  if not minimapWidget then
    return "none"
  end

  local player = g_game.getLocalPlayer()
  local pos = player and player:getPosition()
  if not pos and minimapWidget.getCameraPosition then
    pos = minimapWidget:getCameraPosition()
  end

  local floor = pos and tonumber(pos.z)
  local hasSatelliteMap = g_satelliteMap ~= nil
  local selectedView = "none"

  if minimapWidget.setRealMapMode then
    minimapWidget:setRealMapMode(false)
  end
  if minimapWidget.setUseStaticMinimap then
    minimapWidget:setUseStaticMinimap(false)
  end
  if minimapWidget.setSatelliteMode then
    minimapWidget:setSatelliteMode(false)
  end

  if not hasSatelliteMap or not floor then
    selectedView = "none"
    -- Suppress the "no static chunks for floor ?" log before the player has a
    -- known position (pre-login). It's expected and not actionable.
    if floor ~= nil then
      local viewKey = tostring(floor) .. ':' .. selectedView
      if hdMapLastViewKey ~= viewKey then
        hdMapLastViewKey = viewKey
        consoleln("HD Map Mode: no static chunks available for floor " .. tostring(floor))
      end
    end
    return selectedView
  end

  if g_satelliteMap.hasRealMapChunksForFloor and g_satelliteMap.hasRealMapChunksForFloor(floor) then
    if minimapWidget.setRealMapMode then
      minimapWidget:setRealMapMode(true)
    end
    selectedView = "realmap"
    local viewKey = tostring(floor) .. ':' .. selectedView
    if hdMapLastViewKey ~= viewKey then
      hdMapLastViewKey = viewKey
      consoleln("HD Map Mode: using realmap chunks for floor " .. tostring(floor))
    end
    return selectedView
  end

  if g_satelliteMap.hasMinimapChunksForFloor and g_satelliteMap.hasMinimapChunksForFloor(floor) then
    if minimapWidget.setUseStaticMinimap then
      minimapWidget:setUseStaticMinimap(true)
    end
    selectedView = "minimap"
    local viewKey = tostring(floor) .. ':' .. selectedView
    if hdMapLastViewKey ~= viewKey then
      hdMapLastViewKey = viewKey
      consoleln("HD Map Mode: using minimap chunks for floor " .. tostring(floor))
    end
    return selectedView
  end

  if g_satelliteMap.hasChunksForView and g_satelliteMap.hasChunksForView(floor) then
    if minimapWidget.setSatelliteMode then
      minimapWidget:setSatelliteMode(true)
    end
    selectedView = "satellite"
    local viewKey = tostring(floor) .. ':' .. selectedView
    if hdMapLastViewKey ~= viewKey then
      hdMapLastViewKey = viewKey
      consoleln("HD Map Mode: using satellite chunks for floor " .. tostring(floor))
    end
    return selectedView
  end

  local viewKey = tostring(floor) .. ':' .. selectedView
  if hdMapLastViewKey ~= viewKey then
    hdMapLastViewKey = viewKey
    consoleln("HD Map Mode: no static chunks available for floor " .. tostring(floor))
  end
  return selectedView
end

local function applyHDMapMode()
  if not minimapWidget then
    return
  end

  if hdMapModeEnabled then
    loadHDMapAssets()

    applyHDMapViewForFloor()
    if minimapWidget.setFloorSeparatorOpacity then
      minimapWidget:setFloorSeparatorOpacity(HD_MAP_FLOOR_SEPARATOR_OPACITY)
    end

    if minimapWidget.getMaxZoom and minimapWidget.setMaxZoom then
      if not hdMapPreviousMaxZoom then
        hdMapPreviousMaxZoom = minimapWidget:getMaxZoom()
      end
      minimapWidget:setMaxZoom(math.max(hdMapPreviousMaxZoom, HD_MAP_MAX_ZOOM))
    end

    if minimapWidget.getZoom and minimapWidget.setZoom then
      local applyTargetZoom = false
      if not hdMapPreviousZoom then
        hdMapPreviousZoom = minimapWidget:getZoom()
        applyTargetZoom = true
      end
      if applyTargetZoom or minimapWidget:getZoom() < HD_MAP_TARGET_ZOOM then
        minimapWidget:setZoom(HD_MAP_TARGET_ZOOM)
      end
    end
  else
    hdMapLastViewKey = nil
    if minimapWidget.setRealMapMode then
      minimapWidget:setRealMapMode(false)
    end
    if minimapWidget.setSatelliteMode then
      minimapWidget:setSatelliteMode(false)
    end
    if minimapWidget.setUseStaticMinimap then
      minimapWidget:setUseStaticMinimap(false)
    end
    if minimapWidget.setFloorSeparatorOpacity then
      minimapWidget:setFloorSeparatorOpacity(1.0)
    end
    if hdMapPreviousMaxZoom and minimapWidget.setMaxZoom then
      minimapWidget:setMaxZoom(hdMapPreviousMaxZoom)
      hdMapPreviousMaxZoom = nil
    end
    if hdMapPreviousZoom and minimapWidget.setZoom then
      minimapWidget:setZoom(hdMapPreviousZoom)
      hdMapPreviousZoom = nil
    end
  end
end

function setHDMapMode(enabled)
  hdMapModeEnabled = enabled == true
  applyHDMapMode()
end

local function applyLoginZoom()
  if not minimapWidget or not minimapWidget.getZoom or not minimapWidget.setZoom then
    return
  end
  if loginZoomApplied then
    return
  end

  -- Force a fixed wide view on login. Players can still zoom in/out manually
  -- during the session; this just resets the starting point so they don't
  -- spawn glued to their character icon.
  minimapWidget:setZoom(LOGIN_ZOOM_DEFAULT)
  loginZoomApplied = true
end


function init()
  minimapWindow = g_ui.loadUI('minimap', m_interface.getRightPanel())

  if not minimapWindow.forceOpen then
    minimapButton = modules.client_topmenu.addRightGameToggleButton('minimapButton',
      tr('Minimap') .. ' (Ctrl+M)', '/images/topbuttons/minimap', toggle)
    minimapButton:setOn(true)
  end
  minimapWidget = minimapWindow:recursiveGetChildById('minimap')
  setHDMapMode(getHDMapModeOption())
  minimapWidget.onCameraPositionChange = function(self, cameraPos, oldPos)
    if UIMinimap and UIMinimap.onCameraPositionChange then
      UIMinimap.onCameraPositionChange(self, cameraPos, oldPos)
    end
    modules.game_minimap.scheduleStaticMarksViewportUpdate()
  end
  minimapWidget.onZoomChange = function(self, zoom, oldZoom)
    if UIMinimap and UIMinimap.onZoomChange then
      UIMinimap.onZoomChange(self, zoom, oldZoom)
    end
    modules.game_minimap.scheduleStaticMarksViewportUpdate()
  end

  local gameRootPanel = m_interface.getRootPanel()
  keybindMoveEast:active(gameRootPanel)
  keybindMoveNorth:active(gameRootPanel)
  keybindMoveSouth:active(gameRootPanel)
  keybindMoveWest:active(gameRootPanel)
  keybindFloorUp:active(gameRootPanel)
  keybindFloorDown:active(gameRootPanel)
  keybindZoomIn:active(gameRootPanel)
  keybindZoomOut:active(gameRootPanel)
  keybindCenter:active(gameRootPanel)
  keybindShowMinimap:active(gameRootPanel)


  minimapWindow:setup()
  minimapWindow:close()
  if minimapWindow.iconResize then
    minimapWindow:getChildById('iconResize'):hide()
  end


  minimapWindow.floorPosition.onMouseWheel = onMouseWheel
  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
    onPartyDataUpdate = Party.Update,
    onPartyDataClear = Party.Reset,

    onServerTime = onServerTime
  })

  connect(LocalPlayer, {
    onPositionChange = updateCameraPosition
  })

  if g_game.isOnline() then
    online()
  end
end

function terminate()
  removeEvent(otmmLoadEvent)
  otmmLoadEvent = nil
  cancelStaticMarksLoading()

  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
    onPartyDataUpdate = Party.Update,
    onPartyDataClear = Party.Reset,

    onServerTime = onServerTime
  })

  disconnect(LocalPlayer, {
    onPositionChange = updateCameraPosition
  })

  keybindMoveEast:deactive()
  keybindMoveNorth:deactive()
  keybindMoveSouth:deactive()
  keybindMoveWest:deactive()
  keybindFloorUp:deactive()
  keybindFloorDown:deactive()
  keybindZoomIn:deactive()
  keybindZoomOut:deactive()
  keybindShowMinimap:deactive()

  minimapWindow:destroy()
  if minimapButton then
    minimapButton:destroy()
  end
end

function toggle()
  if not minimapButton then return end
  local sideButton = modules.game_sidebuttons.getButtonById("lenshelpFunction")
  if minimapWindow:isVisible() then
    minimapWindow:close()
    minimapButton:setOn(false)
    modules.game_sidebuttons.setButtonVisible("lenshelpFunction", false)
    if sideButton then
      sideButton.highlight:setVisible(true)
    end
  else
    if m_interface.addToPanels(minimapWindow) then
      minimapWindow:open()
      if sideButton then
        sideButton.highlight:setVisible(false)
      end
    end
    minimapButton:setOn(true)
    modules.game_sidebuttons.setButtonVisible("lenshelpFunction", true)
  end
end

function preload()
  loadMap(false)
  preloaded = true
end

function getOtmmPath()
  local player = g_game.getLocalPlayer()
  if not player then return nil end
  local id = player:getId()
  if not id or id == 0 then return nil end
  local dir = "/characterdata/" .. id .. "/"
  if not g_resources.directoryExists(dir) then
    g_resources.makeDir(dir)
  end
  return dir .. "minimap.otmm"
end

function online()
  loginZoomApplied = false
  local benchmark = g_clock.millis()
  if not MinimapLoader.loaded then
    loadMap(not preloaded)
  end
  setHDMapMode(getHDMapModeOption())
  local otmmPath = getOtmmPath()
  removeEvent(otmmLoadEvent)
  if otmmPath and g_resources.fileExists(otmmPath) then
    otmmLoadEvent = scheduleEvent(function()
      otmmLoadEvent = nil
      if g_game.isOnline() and g_resources.fileExists(otmmPath) then
        g_minimap.loadOtmm(otmmPath)
        applyLoginZoom()
        updateCameraPosition({x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 1})
      end
    end, 250)
  end
  cancelStaticMarksLoading()
  staticMarkStartEvent = scheduleEvent(function()
    staticMarkStartEvent = nil
    if g_game.isOnline() then
      loadMarks()
    end
  end, STATIC_MARK_START_DELAY)
  updateCameraPosition({x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 1})

  if minimapwidget then
    Party.Reset()
  end

  consoleln("Minimap loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function offline()
  loginZoomApplied = false
  removeEvent(otmmLoadEvent)
  otmmLoadEvent = nil
  cancelStaticMarksLoading()

  if minimapWidget then
    minimapWidget:resetParty()
    clearPath()
    clearRoutePath()
    minimapWidget:save()
  end

  local otmmPath = getOtmmPath()
  if otmmPath then
    g_minimap.saveOtmm(otmmPath)
  end
end

function loadMap(clean)
  if clean then
    LoadTibiaMap()
  end

  -- LoadTibiaMap()
  minimapWidget:load()
  applyHDMapMode()
  applyLoginZoom()
  m_interface.addToPanels(minimapWindow)
  MinimapLoader.loaded = true
end

function updateCameraPosition(newPosition, lastPosition)
  local player = g_game.getLocalPlayer()
  if not player then return end
  local pos = player:getPosition()
  if not pos then return end
  if not minimapWidget:isDragging() then
    if not fullmapView then
      minimapWidget:setCameraPosition(player:getPosition())
    end
    minimapWidget:setCrossPosition(player:getPosition())
  end

  if hdMapModeEnabled then
    applyHDMapViewForFloor()
  end

  if oldPos and newPosition.z ~= oldPos.z then
    Party.UpdateFloor(newPosition.z)
  end

  if #Party.Members >= 1 then
    Party.SendUpdate(newPosition)
  end
  oldPos = newPosition

  if newPosition.z ~= lastPosition.z then
    minimapWindow.floorPosition:setImageClip(player:getPosition().z * 14  .." 0 14 67")
  end
end

function updateFloorImage(posZ)
  minimapWindow.floorPosition:setImageClip((posZ) * 14  .." 0 14 67")
end

function onMouseWheel(widget, mousePos, direction)
  if direction == MouseWheelUp then
    minimapWindow:recursiveGetChildById('minimap'):floorUp(1)
  elseif direction == MouseWheelDown then
    minimapWindow:recursiveGetChildById('minimap'):floorDown(1)
  end

  updateFloorImage(minimapWindow:recursiveGetChildById('minimap'):getCameraPosition().z)
  return true
end

function zoom(bool)
  if bool then
    minimapWindow:recursiveGetChildById('minimap'):zoomIn()
  else
    minimapWindow:recursiveGetChildById('minimap'):zoomOut()
  end
end

function floor(bool)
  if bool then
    minimapWindow:recursiveGetChildById('minimap'):floorUp(1)
  else
    minimapWindow:recursiveGetChildById('minimap'):floorDown(1)
  end

  updateFloorImage(minimapWindow:recursiveGetChildById('minimap'):getCameraPosition().z)
end

function center()
  minimapWindow:recursiveGetChildById('minimap'):reset()
end

function checkXByHour(x)
  local y0 = 62
  local incremento = y0 / 12
  local result = math.floor(y0 + (x * incremento))
  if result > 124 then
    result = result - 124
  end

  return result
end

function LoadTibiaMap()
  g_minimap.clean()
  local bgOtmm = '/minimap/minimap.otmm'
  if g_resources.fileExists(bgOtmm) then
    g_minimap.loadOtmmBackground(bgOtmm)
  end
end

local function clearStaticMarks()
  if not minimapWidget then
    staticMarkWidgets = {}
    staticMarksRenderedFileTime = nil
    staticMarksIndex = nil
    return
  end

  for _, widgetId in pairs(staticMarkWidgets) do
    minimapWidget:removeWidget(widgetId)
  end
  staticMarkWidgets = {}
  staticMarksRenderedFileTime = nil
  staticMarksIndex = nil
end

function move(panel, height, index)
  if not panel then
    return
  end

  if string.find(panel:getId(), "horizontal") then
    addEvent(function()
      minimapWindow:setParent(panel)
      if height then
        minimapWindow:setHeight(height)
      end
    end)
  else
    minimapWindow:setParent(panel)
    if height then
      minimapWindow:setHeight(height)
    end
  end

  minimapWindow:open()
  modules.game_sidebuttons.setButtonVisible("lenshelpFunction", true)

  return minimapWindow
end

function onPlayerUnload()
  local index = -1
  local parent = minimapWindow:getParent()
  if parent then
    index = parent:getChildIndex(minimapWindow)
    modules.game_sidebars.registerMinimapConfig({contentHeight = minimapWindow:getHeight(), index = index})
  end
end

function loadMarks()
  local file = '/data/json/markers.json'
  g_settings.set('seeMapMark', true)
  cancelStaticMarksLoading()

  if not minimapWidget then
    staticMarkWidgets = {}
    staticMarksRenderedFileTime = nil
    staticMarksIndex = nil
    return
  end

  if not g_resources.fileExists(file) then
    clearStaticMarks()
    staticMarksCache.fileTime = nil
    staticMarksCache.entries = nil
    return
  end

  local marks, fileTime = getCachedStaticMarks(file)
  if not marks then
    return
  end

  local index = buildStaticMarksIndex(marks, fileTime)
  if index.total == 0 then
    clearStaticMarks()
    staticMarksRenderedFileTime = fileTime
    return
  end

  staticMarksRenderedFileTime = fileTime
  updateVisibleStaticMarks(true)
end

function updateVisibleStaticMarks(force)
  if not minimapWidget or not staticMarksIndex then
    return
  end

  if staticMarkViewportEvent then
    removeEvent(staticMarkViewportEvent)
    staticMarkViewportEvent = nil
  end

  local function applyVisibleMarks()
    staticMarkViewportEvent = nil
    if not g_game.isOnline() or not minimapWidget or not staticMarksIndex then
      return
    end

    local visibleMarks = collectVisibleStaticMarks(staticMarksIndex)
    local desired = {}
    for _, mark in ipairs(visibleMarks) do
      desired[mark.key] = mark
    end

    for key, widgetId in pairs(staticMarkWidgets) do
      if not desired[key] then
        minimapWidget:removeWidget(widgetId)
        staticMarkWidgets[key] = nil
      end
    end

    local pending = {}
    for _, mark in ipairs(visibleMarks) do
      if not staticMarkWidgets[mark.key] then
        pending[#pending + 1] = mark
      end
    end

    if staticMarkLoadEvent then
      removeEvent(staticMarkLoadEvent)
      staticMarkLoadEvent = nil
    end

    if #pending == 0 then
      return
    end

    local renderIndex = 1
    staticMarkRenderToken = staticMarkRenderToken + 1
    local renderToken = staticMarkRenderToken

    local function renderBatch()
      if renderToken ~= staticMarkRenderToken then
        staticMarkLoadEvent = nil
        return
      end

      if not g_game.isOnline() or not minimapWidget then
        staticMarkLoadEvent = nil
        return
      end

      local maxIndex = math.min(renderIndex + STATIC_MARK_BATCH_SIZE - 1, #pending)
      for i = renderIndex, maxIndex do
        local mark = pending[i]
        if mark and not staticMarkWidgets[mark.key] then
          local widgetId = minimapWidget:addWidget('/data/images/game/minimap/icon/' .. mark.iconId .. '.png', { width = 11, height = 11 }, { x = mark.x, y = mark.y, z = mark.z }, mark.description)
          staticMarkWidgets[mark.key] = widgetId
        end
      end

      renderIndex = maxIndex + 1
      if renderIndex <= #pending then
        staticMarkLoadEvent = scheduleEvent(renderBatch, STATIC_MARK_BATCH_DELAY)
        return
      end

      staticMarkLoadEvent = nil
    end

    renderBatch()
  end

  if force then
    applyVisibleMarks()
    return
  end

  staticMarkViewportEvent = scheduleEvent(applyVisibleMarks, STATIC_MARK_UPDATE_DELAY)
end

function scheduleStaticMarksViewportUpdate()
  if staticMarksIndex then
    updateVisibleStaticMarks(false)
  end
end

function renderAllStaticMarksDebug()
  if not minimapWidget or not staticMarksIndex or not staticMarksCache.entries then
    return
  end

  clearStaticMarks()
  local renderBenchmark = g_clock.millis()
  local marks = staticMarksCache.entries
  local total = #marks
  local renderIndex = 1
  staticMarkRenderToken = staticMarkRenderToken + 1
  local renderToken = staticMarkRenderToken

  local function renderBatch()
    if renderToken ~= staticMarkRenderToken then
      staticMarkLoadEvent = nil
      return
    end

    if not g_game.isOnline() or not minimapWidget then
      staticMarkLoadEvent = nil
      return
    end

    local maxIndex = math.min(renderIndex + STATIC_MARK_BATCH_SIZE - 1, total)
    for i = renderIndex, maxIndex do
      local info = marks[i]
      local iconId = info and staticMarksIconConfig[info.icon]
      if iconId and info.x and info.y and info.z then
        local widgetId = minimapWidget:addWidget('/data/images/game/minimap/icon/' .. iconId .. '.png', { width = 11, height = 11 }, { x = info.x, y = info.y, z = info.z }, info.description or '')
        staticMarkWidgets[getStaticMarkKey(info, i)] = widgetId
      end
    end

    renderIndex = maxIndex + 1
    if renderIndex <= total then
      staticMarkLoadEvent = scheduleEvent(renderBatch, STATIC_MARK_BATCH_DELAY)
      return
    end

    staticMarkLoadEvent = nil
    staticMarksRenderedFileTime = staticMarksCache.fileTime
    consoleln(string.format('Minimap marks debug-loaded: %d in %.3f seconds.', total, (g_clock.millis() - renderBenchmark) / 1000))
  end

  renderBatch()
end

function onClose()

end

function onServerTime(minutes, seconds)
  if not minimapWindow then
    return
  end
  minimapWindow.centerMap:setImageClip(checkXByHour(minutes) .. " 0 31 31")
end

local function isPositionData(value)
  return type(value) == "table" and tonumber(value.x) and tonumber(value.y) and tonumber(value.z)
end

local function clonePosition(position)
  return {
    x = tonumber(position.x) or 0,
    y = tonumber(position.y) or 0,
    z = tonumber(position.z) or 0
  }
end

local function flattenCoordinateNodes(node, out)
  if isPositionData(node) then
    table.insert(out, clonePosition(node))
    return
  end

  if type(node) ~= "table" then
    return
  end

  if #node > 0 then
    for _, value in ipairs(node) do
      flattenCoordinateNodes(value, out)
    end
    return
  end

  local numericKeys = {}
  for key in pairs(node) do
    local numericKey = tonumber(key)
    if numericKey then
      table.insert(numericKeys, numericKey)
    end
  end

  table.sort(numericKeys)
  for _, floor in ipairs(numericKeys) do
    flattenCoordinateNodes(node[floor] or node[tostring(floor)], out)
  end
end

local function normalizeRoutePoints(coordinates)
  if type(coordinates) ~= "table" then
    return {}
  end

  local flat = {}
  flattenCoordinateNodes(coordinates, flat)
  if #flat == 0 then
    return flat
  end

  local unique = {}
  local previous = nil
  for _, position in ipairs(flat) do
    if not previous or previous.x ~= position.x or previous.y ~= position.y or previous.z ~= position.z then
      table.insert(unique, position)
      previous = position
    end
  end

  return unique
end

local function clearTrackedRouteWidgets()
  if not minimapWidget then
    trackedRouteWidgets = {}
    return
  end

  for _, widgetId in ipairs(trackedRouteWidgets) do
    minimapWidget:removeWidget(widgetId)
  end

  trackedRouteWidgets = {}
end

local function stopTrackedRouteBlink()
  -- Legacy no-op after removing blinking marker fallback.
end

local function buildRenderableRoutePoints(points)
  local result = {}
  local total = #points
  if total == 0 then
    return result
  end

  for i, point in ipairs(points) do
    local previous = points[i - 1]
    local isFloorTransition = previous and previous.z ~= point.z
    if i == 1 or i == total or isFloorTransition or i % TRACKED_ROUTE_SAMPLE_STEP == 0 then
      table.insert(result, point)
      if #result >= TRACKED_ROUTE_MAX_WIDGETS then
        break
      end
    end
  end

  local lastPoint = points[total]
  local lastResult = result[#result]
  if lastPoint and (#result == 0 or not lastResult or lastResult.x ~= lastPoint.x or lastResult.y ~= lastPoint.y or lastResult.z ~= lastPoint.z) and #result < TRACKED_ROUTE_MAX_WIDGETS then
    table.insert(result, lastPoint)
  end

  return result
end

local function drawTrackedRouteWidgets(renderPoints, selectedState)
  clearTrackedRouteWidgets()
  if not minimapWidget or type(renderPoints) ~= "table" or #renderPoints == 0 then
    return
  end

  for _, point in ipairs(renderPoints) do
    local widgetId = minimapWidget:addWidget(TRACKED_ROUTE_ICON, TRACKED_ROUTE_ICON_SIZE, point, tr('Hunt Route'))
    if widgetId then
      table.insert(trackedRouteWidgets, widgetId)
    end
  end
end

local function renderTrackedRouteWidgets(points)
  stopTrackedRouteBlink()
  if not minimapWidget or #points == 0 then
    clearTrackedRouteWidgets()
    return
  end

  local renderPoints = buildRenderableRoutePoints(points)
  drawTrackedRouteWidgets(renderPoints, true)
end

local function drawRouteUsingNativePath(points)
  if not minimapWidget or type(points) ~= "table" or #points == 0 then
    return false
  end

  if type(minimapWidget.clearPath) ~= "function" or type(minimapWidget.addPathPoint) ~= "function" then
    return false
  end

  minimapWidget:clearPath()
  for i, point in ipairs(points) do
    minimapWidget:addPathPoint(point)
    if type(minimapWidget.addWaypoint) == "function" and (i == 1 or i == #points or i % 15 == 0) then
      minimapWidget:addWaypoint(point)
    end
  end

  return true
end

function setPath(coordinates)
  if not minimapWidget then
    return
  end

  if type(coordinates) ~= "table" then
    minimapWidget:clearWaypoints()
    minimapWidget:setDrawWaypoints(false)
    return
  end

  if coordinates.x and coordinates.y and coordinates.z then
    coordinates = {[coordinates.z] = {coordinates}}
  end

  minimapWidget:clearWaypoints()
  if table.size(coordinates) == 0 then
      minimapWidget:setDrawWaypoints(false)
      return
  end

  minimapWidget:setDrawWaypoints(true)
  for floor, coordinate in pairs(coordinates) do
      if tonumber(floor) then
          minimapWidget:makeWaypoints(coordinate, tonumber(floor))
      end
  end
end

function clearPath()
  if not minimapWidget then
    return
  end

  if minimapWidget and minimapWidget.clearPath then
    minimapWidget:clearPath()
  end
  minimapWidget:clearWaypoints()
  minimapWidget:setDrawWaypoints(false)
end

function setRoutePath(coordinates)
  if not minimapWidget then
    return
  end

  minimapWidget:clearRoutePath()
  clearTrackedRouteWidgets()

  if type(coordinates) ~= "table" then
    minimapWidget:setDrawWaypoints(false)
    return
  end

  local routePoints = normalizeRoutePoints(coordinates)
  if #routePoints == 0 then
    stopTrackedRouteBlink()
    minimapWidget:setDrawWaypoints(false)
    return
  end

  if drawRouteUsingNativePath(routePoints) then
    stopTrackedRouteBlink()
    clearTrackedRouteWidgets()
    minimapWidget:setDrawWaypoints(true)
    return
  end

  local cameraPosition = minimapWidget:getCameraPosition()
  local routePath = routePoints
  if cameraPosition then
    local sameFloorPath = {}
    for _, point in ipairs(routePoints) do
      if tonumber(point.z) == tonumber(cameraPosition.z) then
        table.insert(sameFloorPath, point)
      end
    end
    if #sameFloorPath > 0 then
      routePath = sameFloorPath
    end
  end

  minimapWidget:setDrawWaypoints(true)
  minimapWidget:makeRouth(routePath)
  renderTrackedRouteWidgets(routePoints)
end

function clearRoutePath()
  if not minimapWidget then
    trackedRouteWidgets = {}
    return
  end

  minimapWidget:clearRoutePath()
  if minimapWidget.clearPath then
    minimapWidget:clearPath()
  end
  stopTrackedRouteBlink()
  minimapWidget:setDrawWaypoints(false)
  clearTrackedRouteWidgets()
end
