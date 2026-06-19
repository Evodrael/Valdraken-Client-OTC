filename = nil
loaded = false

function setFileName(name)
  filename = name
end

function isLoaded()
  return loaded
end

local function loadLegacyDatSpr(version)
  local things = g_settings.getNode('things')
  local datPath, sprPath

  if things and things.data ~= nil and things.sprites ~= nil then
    datPath = resolvepath('/things/' .. things.data)
    sprPath = resolvepath('/things/' .. things.sprites)
  elseif filename then
    datPath = resolvepath('/things/' .. filename)
    sprPath = resolvepath('/things/' .. filename)
  else
    datPath = resolvepath('/things/' .. version .. '/Tibia')
    sprPath = resolvepath('/things/' .. version .. '/Tibia')
  end

  local errorMessage = ''
  if not g_things.loadDat(datPath) then
    errorMessage = errorMessage .. tr("Unable to load dat file, please place a valid dat in '%s'", datPath) .. '\n'
  end

  if not g_sprites.loadSpr(sprPath) then
    errorMessage = errorMessage .. tr("Unable to load spr file, please place a valid spr in '%s'", sprPath)
  end

  return errorMessage
end

function load()
  local version = g_game.getClientVersion()
  local errorMessage = ''

  if version >= 1281 and not g_game.getFeature(GameLoadSprInsteadProtobuf) then
    local thingsPath = resolvepath(string.format('/things/%d/', version))
    local soundsPath = resolvepath(string.format('/sounds/%d/', version))

    if not g_things.loadAppearances(thingsPath) then
      errorMessage = errorMessage .. tr("Unable to load appearances from '%s'", thingsPath) .. '\n'
    end

    if errorMessage:len() == 0 and not g_things.loadStaticData(thingsPath) then
      errorMessage = errorMessage .. tr("Unable to load static data from '%s'", thingsPath) .. '\n'
    end

    if errorMessage:len() == 0 and not g_sounds.loadClientFiles(soundsPath) then
      errorMessage = errorMessage .. tr("Unable to load client sounds from '%s'", soundsPath)
    end
  else
    errorMessage = loadLegacyDatSpr(version)
  end

  loaded = (errorMessage:len() == 0)

  if errorMessage:len() > 0 then
    local messageBox = displayErrorBox(tr('Error'), errorMessage)
    addEvent(function() messageBox:raise() messageBox:focus() end)

    g_game.setClientVersion(0)
    g_game.setProtocolVersion(0)
  end
end
