local musicFilename = "/sounds/startup"
local musicChannel = nil

function setMusic(filename)
  musicFilename = filename

  if not g_game.isOnline() and musicChannel ~= nil then
    musicChannel:stop()
    musicChannel:enqueue(musicFilename, 3)
  end
end

function reloadScripts()
  if g_game.getFeature(GameNoDebug) then
    return
  end

  if not DEVELOPERMODE then
    return
  end

  if not g_app.isDevMode() then
      return
  end
  g_textures.clearCache()
  g_modules.reloadModules()

  local script = '/' .. g_app.getCompactName() .. 'rc.lua'
  if g_resources.fileExists(script) then
    dofile(script)
  end

  local message = tr('All modules and scripts were reloaded.')

  modules.game_textmessage.displayGameMessage(message)
  print(message)
end

function startup()
  if g_sounds ~= nil then
    musicChannel = g_sounds.getChannel(1)
  end

  G.UUID = g_settings.getString('report-uuid')
  if not G.UUID or #G.UUID ~= 36 then
    G.UUID = g_crypt.genUUID()
    g_settings.set('report-uuid', G.UUID)
  end

  -- UI sound policy (matches the reference OTC client):
  --   * Click sounds are NOT defaulted — buttons stay silent unless their own
  --     style explicitly declares click-sound.
  --   * Show sounds: NAO defaultar a partir do catalogo. A categoria "UI" do
  --     catalogo protobuf contem cliques/blips de ~0.15s; setar isso como
  --     defaultShowSound GLOBAL faz CADA widget que fica visivel (paineis, rows,
  --     tooltips, labels) tocar o clique -> "som de clique que nao para".
  --     Janelas que querem som de abertura ja declaram `display-sound:` no estilo
  --     (data/styles/10-windows.otui), via path por-widget independente do default.
  --     So usamos um arquivo BUNDLED dedicado, se existir; nunca o catalogo UI.
  local function resolveShowSound()
    local current = UIWidget and UIWidget.getDefaultShowSound and UIWidget.getDefaultShowSound() or ""
    if current ~= "" then
      return current
    end
    if g_resources and g_resources.fileExists then
      for _, file in ipairs({ "/sounds/window.ogg", "/sounds/window_open.ogg", "/sounds/ui_open.ogg" }) do
        if g_resources.fileExists(file) then
          return file
        end
      end
    end
    return ""
  end

  local startupSoundPlayed = false
  local function applyShowSoundDefaults()
    if UIWidget and UIWidget.setDefaultShowSound then
      local resolved = resolveShowSound()
      if resolved ~= "" and resolved ~= (UIWidget.getDefaultShowSound and UIWidget.getDefaultShowSound() or "") then
        UIWidget.setDefaultShowSound(resolved)
      end
      -- Play the resolved show sound once at otclient startup (before login)
      -- so the user gets an audible "client is alive" cue, mirroring the
      -- request that "esse som aparece também no inicio do otclient antes de
      -- logado no personagem".
      if not startupSoundPlayed and resolved ~= "" and g_sounds then
        local uiChannel = g_sounds.getChannel(12) -- NUMERIC_SOUND_TYPE_UI
        if uiChannel and uiChannel.play then
          uiChannel:play(resolved)
        elseif g_sounds.play then
          g_sounds.play(resolved)
        end
        startupSoundPlayed = true
      end
    end
  end

  applyShowSoundDefaults()
  -- The protobuf catalog loads lazily (after game_things runs). Re-run the
  -- resolver so the first session also wires the catalog-based default.
  connect(g_things, { onLoadDat = applyShowSoundDefaults })

  -- Resolves the startup/login music: prefers the bundled /sounds/startup.ogg
  -- when present, otherwise falls back to whatever the protobuf catalog ships
  -- as MUSIC_TYPE_MUSIC_TITLE (=3). Empty string means no login music.
  local function resolveStartupMusic()
    if g_resources and g_resources.fileExists and g_resources.fileExists(musicFilename .. ".ogg") then
      return musicFilename
    end
    if g_sounds and g_sounds.getAnyAudioFileForMusicType then
      local catalogMusic = g_sounds.getAnyAudioFileForMusicType(3) -- MUSIC_TYPE_MUSIC_TITLE
      if catalogMusic and catalogMusic ~= "" then
        return catalogMusic
      end
    end
    return ""
  end

  local function playStartupMusic()
    if musicChannel == nil then return end
    local file = resolveStartupMusic()
    if file ~= "" then
      musicChannel:enqueue(file, 3)
    end
  end

  -- O catalogo de sons (protobuf) so carregava em game_things.load(), que roda
  -- APOS o 1o login (quando a versao do client e definida). Por isso a musica do
  -- menu so tocava depois de logar+deslogar. Aqui carregamos o catalogo ja no
  -- boot, varrendo /sounds/<versao>/, para a musica tocar na 1a abertura.
  local function ensureSoundCatalogLoaded()
    if not (g_sounds and g_sounds.loadClientFiles) then return end
    -- ja ha musica resolvivel? entao o catalogo ja esta carregado
    if g_sounds.getAnyAudioFileForMusicType and g_sounds.getAnyAudioFileForMusicType(3) ~= "" then
      return
    end
    if not (g_resources and g_resources.listDirectoryFiles) then return end
    local ok, entries = pcall(g_resources.listDirectoryFiles, '/sounds', true, false)
    if not ok or not entries then return end
    for _, entry in ipairs(entries) do
      if g_resources.directoryExists and g_resources.directoryExists(entry) then
        -- loadClientFiles concatena directory.."catalog-sound", entao precisa de "/" final
        local dir = entry:sub(-1) == '/' and entry or (entry .. '/')
        if g_sounds.loadClientFiles(dir) then
          break
        end
      end
    end
  end

  ensureSoundCatalogLoaded()
  playStartupMusic()
  connect(g_game, { onGameStart = function() if musicChannel ~= nil then musicChannel:stop(3) end end })
  connect(g_game, { onGameEnd = function()
      if g_sounds ~= nil then
        g_sounds.stopAll()
        playStartupMusic()
      end
  end })
  -- Catalog loads after first character login; replay on dat load so the
  -- music is heard on the second startup screen without requiring a restart.
  connect(g_things, { onLoadDat = function()
      if musicChannel ~= nil and not g_game.isOnline() then
        playStartupMusic()
      end
  end })
end

function init()
  connect(g_app, { onRun = startup,
                   onExit = exit })
  connect(g_game, { onGameStart = onGameStart,
                    onGameEnd = onGameEnd })

  if g_sounds ~= nil then
    --g_sounds.preload(musicFilename)
  end

  if not Updater then
    --if g_resources.getLayout() == "mobile" then
      --g_window.setMinimumSize({ width = 640, height = 360 })
    --else
      g_window.setMinimumSize({ width = 1490, height = 714 })
    --end

    -- window size
    local size = { width = 1024, height = 600 }
    size = g_settings.getSize('window-size', size)
    g_window.resize(size)

    -- window position, default is the screen center
    local displaySize = g_window.getDisplaySize()
    local defaultPos = { x = (displaySize.width - size.width)/2,
                         y = (displaySize.height - size.height)/2 }
    local pos = g_settings.getPoint('window-pos', defaultPos)
    pos.x = math.max(pos.x, 0)
    pos.y = math.max(pos.y, 0)
    g_window.move(pos)

    -- window maximized?
    local maximized = g_settings.getBoolean('window-maximized', false)
    if maximized then g_window.maximize() end
  end

  g_window.setTitle(g_app.getName())
  g_window.setIcon('/images/clienticon')

  -- g_keyboard.bindKeyDown('Ctrl+Shift+R', reloadScripts)

  -- generate machine uuid, this is a security measure for storing passwords
  if not g_crypt.setMachineUUID(g_settings.get('uuid')) then
    g_settings.set('uuid', g_crypt.getMachineUUID())
    g_settings.save()
  end
end

function terminate()
  disconnect(g_app, { onRun = startup,
                      onExit = exit })
  disconnect(g_game, { onGameStart = onGameStart,
                       onGameEnd = onGameEnd })
  -- save window configs
  g_settings.set('window-size', g_window.getUnmaximizedSize())
  g_settings.set('window-pos', g_window.getUnmaximizedPos())
  g_settings.set('window-maximized', g_window.isMaximized())
end

function exit()
  KeyBinds:offline()
  g_logger.info("Exiting application..")
end

function onGameStart()
  local benchmark = g_clock.millis()

  if LoadedPlayer:isLoaded() then
    local function extractNumbers(str)
      local numbers = str:match("%d+")
      return numbers or false
    end

    local numberedName = extractNumbers(LoadedPlayer:getName())
    if numberedName then
      g_window.setTitle(g_app.getName() .. " - CAM" .. numberedName)
    else
      g_window.setTitle(g_app.getName() .. " - " .. LoadedPlayer:getName())
    end
  end

  consoleln("Game loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function onGameEnd()
  g_window.setTitle(g_app.getName())
end
