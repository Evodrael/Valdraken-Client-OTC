EnterGame = {}

-- private variables
local loadBox
local enterGame
local logpass
local twofactor
local protocolLogin

local customServerSelectorPanel
local serverSelectorPanel
local serverSelector
local clientVersionSelector
local serverHostTextEdit
local rememberPasswordBox
local rememberEmailBox
local protos = { "740", "760", "772", "792", "800", "810", "854", "860", "870", "910", "961", "1000", "1077", "1090",
  "1096", "1098", "1099", "1100", "1200", "1220", "1312", "1524" }

local waitingForHttpResults = 0

local keybindChangeChar = KeyBind:getKeyBind("Misc.", "Change Character")

-- private functions
local function onProtocolError(protocol, message, errorCode)
  if errorCode then
    return EnterGame.onError(message)
  end
  return EnterGame.onLoginError(message)
end

local function onSessionKey(protocol, sessionKey)
  G.sessionKey = sessionKey
end

local function getServerInfoByName(name)
  if Servers then
    for _, server in pairs(Servers) do
      if name == server.name then
        return server
      end
    end
    -- Com um unico server, o serverSelector pode exibir o NOME DO WORLD ativo (em vez do nome do
    -- descriptor); o login ainda resolve para o unico server configurado.
    if #Servers == 1 then
      return Servers[1]
    end
  end
  return nil
end

local function onCharacterList(protocol, characters, account, otui)
  if rememberEmailBox:isChecked() then
    local account = g_crypt.encrypt(G.account)
    g_settings.set('account', account)
  else
    g_settings.remove('account')
  end

  if rememberPasswordBox:isChecked() and (G.gtoken == '' or G.gtoken == nil) then
    local password = g_crypt.encrypt(G.password)
    g_settings.set('password', password)
  elseif not rememberPasswordBox:isChecked() then
    g_settings.remove('password')
  end

  for _, characterInfo in pairs(characters) do
    if characterInfo.previewState and characterInfo.previewState ~= PreviewState.Default then
      characterInfo.worldName = characterInfo.worldName .. ', Preview'
    end
  end

  if loadBox then
    loadBox:destroy()
    loadBox = nil
  end

  if twofactor then
    twofactor:destroy()
    twofactor = nil
  end

  modules.client_background.toggleLogo(false)
  CharacterList.create(characters, account, otui)
  CharacterList.show()

  g_settings.save()
end

local function onUpdateNeeded(protocol, signature)
  return EnterGame.onError(tr('Your client needs updating, try redownloading it.'))
end

local function onProxyList(protocol, proxies)
  for _, proxy in ipairs(proxies) do
    g_proxy.addProxy(proxy["host"], proxy["port"], proxy["priority"])
  end
end

local function parseFeatures(features)
  for feature_id, value in pairs(features) do
    if value == "1" or value == "true" or value == true then
      g_game.enableFeature(feature_id)
    else
      g_game.disableFeature(feature_id)
    end
  end
end

local worlds = {}
function getWorldInfo(id)
  return worlds[id]
end

local function onTibia12HTTPResult(session, playdata)
  local characters = {}
  local account = {
    status = 0,
    subStatus = 0,
    premDays = 0,
  }

  if table.empty(playdata["characters"]) then
    return EnterGame.onError("No characters found on this account.")
  end

  -- Diagnostic: log exactly what the HTTP session JSON contained so we can tell
  -- server-side bugs apart from a client misread of the premium-related fields.
  -- [CharListHTTP] debug log desativado

  if session["status"] ~= "active" then
    account.status = 1
  end

  -- Premium resolution priority:
  --   1. viptime (timestamp in seconds) → preferred, has the actual expiration
  --   2. premiumuntil (timestamp in seconds) → TFS-style fallback
  --   3. ispremium (bool) → no expiration info, just show ∞ days
  -- The previous logic overwrote subStatus with a days-count (wrong type) and then
  -- forced subStatus=Free whenever viptime was missing, even with ispremium=true.
  local now = os.time()
  local viptime = tonumber(session["viptime"])
  local premUntil = tonumber(session["premiumuntil"])
  local isPremiumFlag = session["ispremium"] == true or session["ispremium"] == 1
                        or session["ispremium"] == "1" or session["ispremium"] == "true"

  if viptime and viptime > now then
    account.premDays = math.max(0, math.ceil((viptime - now) / 86400))
    account.subStatus = SubscriptionStatus.Premium
  elseif premUntil and premUntil > now then
    account.premDays = math.max(0, math.ceil((premUntil - now) / 86400))
    account.subStatus = SubscriptionStatus.Premium
  elseif isPremiumFlag then
    -- Premium without an expiration timestamp — render as "Free days left" (65535
    -- is the legacy "premium forever" sentinel the character-list label expects).
    account.premDays = 65535
    account.subStatus = SubscriptionStatus.Premium
  else
    account.premDays = 0
    account.subStatus = SubscriptionStatus.Free
  end
  G.clientVersion = tonumber(session["version"]) or GameInfo.version
  g_game.setClientVersion(G.clientVersion)
  g_game.setStringVersion(GameInfo.strVersion)
  g_game.setProtocolVersion(g_game.getClientProtocolVersion(G.clientVersion))

  onSessionKey(nil, session["sessionkey"])

  -- Le automaticamente TODOS os mundos ativos retornados pelo login.php.
  Worlds:loadWorlds(playdata)
  for _, world in pairs(playdata["worlds"]) do
    worlds[world.id] = {
      name = world.name,
      port = world.externalportunprotected or world.externalportprotected,
      address = world.externaladdressunprotected or world.externaladdressprotected,
      pvptype = world.pvptype
    }
  end

  -- (Filtro de mundos removido da UI.) Nao repovoamos mais o serverSelector com nomes de world:
  -- ele fica escondido com o nome do server descriptor, que e o que getServerInfoByName casa no login.

  for _, character in pairs(playdata["characters"]) do
    local world = worlds[character.worldid]
    if world then
      -- The official Tibia client lets the player pin a "main character" in the
      -- account panel; TFS-style servers (OTServBR/OTZudo) don't ship that
      -- feature, so `ismaincharacter` arrives `false` for every character.
      -- Accept any of the names a fork might pick; fall back to a heuristic
      -- (highest-level character on the account) further down once all
      -- characters are collected.
      local isMain = character.ismaincharacter
                     or character.maincharacter
                     or character.ismain
                     or character.main
                     or false

      table.insert(characters, {
        name = character.name,
        worldName = world.name,
        worldIp = world.address,
        worldPort = world.port,
        pvpType = world.pvptype,
        mainCharacter = isMain,
        dailyRewardState = tonumber(character.dailyrewardstate) or 0,
        level = character.level,
        vocation = character.vocation,
        worldId = character.worldid,
        outfit = {
          type = character.outfitid,
          head = character.headcolor,
          body = character.torsocolor,
          legs = character.legscolor,
          feet = character.detailcolor,
          addons = character.addonsflags,
        },
      })
    end
  end

  -- Fallback: if the server never tagged any character as main (TFS-style
  -- servers don't expose the official "main" account setting), highlight the
  -- highest-level character on the account so the player still sees an "M"
  -- next to their strongest pick. Ties are broken by the original order.
  local anyServerMain = false
  for _, c in ipairs(characters) do
    if c.mainCharacter then anyServerMain = true; break end
  end
  if not anyServerMain and #characters > 0 then
    local bestIdx, bestLevel = nil, -1
    for idx, c in ipairs(characters) do
      local lvl = tonumber(c.level) or 0
      if lvl > bestLevel then
        bestLevel = lvl
        bestIdx = idx
      end
    end
    if bestIdx then
      characters[bestIdx].mainCharacter = true
    end
  end

  -- proxies
  if g_proxy then
    Proxies:loadProxyConfig(playdata)
  end

  g_game.setCustomProtocolVersion(0)
  g_game.chooseRsa(G.host)
  g_game.setCustomOs(-1)

  onCharacterList(nil, characters, account, nil)
end

local function onHTTPResult(data, err)
  if waitingForHttpResults == 0 then
    return
  end

  waitingForHttpResults = waitingForHttpResults - 1
  if err and waitingForHttpResults > 0 then
    return -- ignore, wait for other requests
  end

  if err then
    return EnterGame.onError(err)
  end
  waitingForHttpResults = 0

  if data['errorCode'] == 6 then
    if loadBox then
      loadBox:destroy()
      loadBox = nil
    end

    local doCancelLogin = function()
      g_client.setInputLockWidget(nil);
      twofactor:destroy();
      twofactor = nil;
      EnterGame.show()
    end

    local doEnterGame = function()
      g_client.setInputLockWidget(nil)
      EnterGame.doLogin(G.account, G.password, twofactor.tokenEnter:getText(), G.host, G.gtoken)
      twofactor:destroy()
      twofactor = nil
    end

    twofactor = g_ui.displayUI('twofactor')
    twofactor.onEscape = doCancelLogin
    twofactor.onEnter = doEnterGame
    twofactor.cancelButton.onClick = doCancelLogin
    twofactor.okButton.onClick = doEnterGame
    g_client.setInputLockWidget(twofactor)
    return
  end

  if data['error'] and data['error']:len() > 0 then
    return EnterGame.onLoginError(data['error'])
  elseif data['errorMessage'] and data['errorMessage']:len() > 0 then
    return EnterGame.onLoginError(data['errorMessage'])
  end

  if type(data["session"]) == "table" and type(data["playdata"]) == "table" then
    return onTibia12HTTPResult(data["session"], data["playdata"])
  end

  local characters = data["characters"]
  local account = data["account"]
  local session = data["session"]

  local version = data["version"]
  local things = data["things"]
  local customProtocol = data["customProtocol"]

  local features = data["features"]
  local settings = data["settings"]
  local rsa = data["rsa"]
  local proxies = data["proxies"]

  -- custom protocol
  g_game.setCustomProtocolVersion(0)
  if customProtocol ~= nil then
    customProtocol = tonumber(customProtocol)
    if customProtocol ~= nil and customProtocol > 0 then
      g_game.setCustomProtocolVersion(customProtocol)
    end
  end

  -- force player settings
  if settings ~= nil then
    for option, value in pairs(settings) do
      m_settings.setOption(option, value, true)
    end
  end

  -- version
  G.clientVersion = version
  g_game.setClientVersion(version)
  g_game.setStringVersion(GameInfo.strVersion)
  g_game.setProtocolVersion(g_game.getClientProtocolVersion(version))
  g_game.setCustomOs(-1) -- disable

  if rsa ~= nil then
    g_game.setRsa(rsa)
  end

  if features ~= nil then
    parseFeatures(features)
  end

  if session ~= nil and session:len() > 0 then
    onSessionKey(nil, session)
  end

  -- proxies
  if g_proxy then
    g_proxy.clear()
    if proxies then
      for i, proxy in ipairs(proxies) do
        g_proxy.addProxy(proxy["host"], tonumber(proxy["port"]), tonumber(proxy["priority"]))
      end
    end
  end

  onCharacterList(nil, characters, account, nil)
end


function EnterGame.addTestServer()
  local testServer = {
    name = "OTServBR-Global 15.24",
    loginLink = "http://127.0.0.1/login.php",
    clientServicesLink = "http://127.0.0.1/login.php",
    hintsLink = "",
    googleLogin = ""
  }

  if not Servers then
    Servers = {}
  end

  if not getServerInfoByName(testServer.name) then
    table.insert(Servers, testServer)
    serverSelector:addOption(testServer.name)
    serverSelector:setCurrentOption(testServer.name, true)
    g_logger.info("Added local 15.24 server to server list via Lua.")
  end
end

-- public functions
function EnterGame.init()
  if USE_NEW_ENERGAME then return end
  enterGame = g_ui.displayUI('entergame')
  if LOGPASS ~= nil then
    logpass = g_ui.loadUI('logpass', enterGame:getParent())
  end

  keybindChangeChar:active(gameRootPanel)

  serverSelectorPanel = enterGame:getChildById('serverSelectorPanel')
  customServerSelectorPanel = enterGame:getChildById('customServerSelectorPanel')

  serverSelector = serverSelectorPanel:getChildById('serverSelector')
  rememberEmailBox = enterGame:getChildById('rememberEmailBox')
  rememberPasswordBox = enterGame:getChildById('rememberPasswordBox')
  serverHostTextEdit = customServerSelectorPanel:getChildById('serverHostTextEdit')
  clientVersionSelector = customServerSelectorPanel:getChildById('clientVersionSelector')

  if Servers ~= nil then
    for i, server in pairs(Servers) do
      serverSelector:addOption(server.name)
    end
  end
  if serverSelector:getOptionsCount() == 0 or ALLOW_CUSTOM_SERVERS then
    serverSelector:addOption(tr("Another"))
  end
  for i, proto in pairs(protos) do
    clientVersionSelector:addOption(proto)
  end

  local account = g_crypt.decrypt(g_settings.get('account'))
  local password = g_crypt.decrypt(g_settings.get('password'))
  local hiddenEmail = g_settings.get('hiddenEmail')
  local server = g_settings.get('server')
  local host = g_settings.get('host')
  local clientVersion = g_settings.get('client-version')

  if serverSelector:isOption(server) then
    serverSelector:setCurrentOption(server, false)
    if Servers == nil then
      serverHostTextEdit:setText(host)
    end
    clientVersionSelector:setOption(clientVersion)
  else
    server = ""
    host = ""
  end

  g_keyboard.bindKeyDown("Ctrl+Alt+T", EnterGame.addTestServer, enterGame)

  enterGame:getChildById('accountPasswordTextEdit'):setText(password)

  local accountWidget = enterGame:getChildById('accountNameTextEdit')
  accountWidget:setText(account)
  accountWidget:setCursorPos(#account)
  rememberEmailBox:setChecked(#account > 0)

  rememberPasswordBox:setChecked(#password > 0)
  if hiddenEmail == "1" then
    enterGame.accountNameTextEdit:setTextHidden(true)
  end

  if g_game.isOnline() then
    return EnterGame.hide()
  end

  scheduleEvent(function()
    EnterGame.show()
  end, 100)

  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd
  })
end

function onGameStart(...)
  local benchmark = g_clock.millis()
  if g_game.isOnline() then
    g_keyboard.bindKeyDown("Alt+F4", function() m_interface.tryExit() end, gameRootPanel)
    return EnterGame.hide()
  end
  consoleln("EnterGame loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function onGameEnd(...)
  g_keyboard.unbindKeyDown("Alt+F4", nil, gameRootPanel)
end

function EnterGame.terminate()
  if not enterGame then return end

  keybindChangeChar:deactive(gameRootPanel)
  g_keyboard.unbindKeyDown("Ctrl+Alt+T", enterGame)

  if logpass then
    logpass:destroy()
    logpass = nil
  end

  enterGame:destroy()
  if loadBox then
    loadBox:destroy()
    loadBox = nil
  end
  if twofactor then
    twofactor:destroy()
    twofactor = nil
  end
  if protocolLogin then
    protocolLogin:cancelLogin()
    protocolLogin = nil
  end
  EnterGame = nil

  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd
  })
end

function EnterGame.show()
  G.characters = nil
  if not enterGame then return end
  g_client.setInputLockWidget(nil)
  -- game_patch_notes removido: vai direto para a tela de login.
  if modules.client_background and modules.client_background.showIcon then
    modules.client_background.showIcon()
  end
  enterGame:show()
  enterGame:raise()
  enterGame:focus()
  enterGame:getChildById('accountNameTextEdit'):focus()
  if logpass then
    logpass:show()
    logpass:raise()
    logpass:focus()
  end
end

function EnterGame.hide()
  if not enterGame then return end
  if not rememberPasswordBox:isChecked() then
    enterGame:getChildById('accountPasswordTextEdit'):clearText()
    g_settings.remove('password')
  end
  enterGame:hide()
  if logpass then
    logpass:hide()
    if modules.logpass then
      modules.logpass:hide()
    end
  end
end

function EnterGame.openWindow()
  if g_game.isOnline() then
    CharacterList.show()
  elseif not g_game.isLogging() and not CharacterList.isVisible() then
    EnterGame.show()
  end
end

function EnterGame.clearAccountFields()
  if not rememberEmailBox:isChecked() then
    enterGame:getChildById('accountNameTextEdit'):clearText()
    enterGame:getChildById('accountNameTextEdit'):focus()
    g_settings.remove('account')
  end
  if not rememberPasswordBox:isChecked() then
    enterGame:getChildById('accountPasswordTextEdit'):clearText()
    g_settings.remove('password')
  end
  enterGame:getChildById('accountTokenTextEdit'):clearText()
  enterGame:getChildById('accountNameTextEdit'):focus()
end

function EnterGame.onServerChange()
  serverName = serverSelector:getText()
  local serverInfo = Servers and getServerInfoByName(serverName) or nil
  if serverName == tr("Another") then
    if not customServerSelectorPanel:isOn() then
      serverHostTextEdit:setText("")
      customServerSelectorPanel:setOn(true)
    end
  else
    customServerSelectorPanel:setOn(false)
  end
  if serverInfo then
    serverHostTextEdit:setText(serverInfo.name)
    modules.client_background.updateStatus(serverInfo)
  end
end

function EnterGame.doLogin(account, password, token, host, gtoken)
  if g_game.isOnline() then
    local errorBox = displayErrorBox(tr('Login Error'), tr('Cannot login while already in game.'))
    connect(errorBox, { onOk = EnterGame.show })
    return
  end


  G.account = account or enterGame:getChildById('accountNameTextEdit'):getText()
  G.password = password or enterGame:getChildById('accountPasswordTextEdit'):getText()
  G.authenticatorToken = token or enterGame:getChildById('accountTokenTextEdit'):getText()
  G.gtoken = gtoken or ""
  G.stayLogged = true
  G.server = serverSelector:getText():trim()
  local chosenServer = getServerInfoByName(G.server)
  G.host = chosenServer and chosenServer.loginLink or serverHostTextEdit:getText()
  G.clientVersion = tonumber(clientVersionSelector:getText())

  if G.password == "" then
    return
  end

  if not rememberEmailBox:isChecked() then
    g_settings.set('account', G.account)
  end

  if rememberPasswordBox:isChecked() and G.gtoken == '' then
    g_settings.set('password', g_crypt.encrypt(G.password))
  end

  g_settings.set('host', G.host)
  g_settings.set('server', G.server)
  g_settings.set('client-version', G.clientVersion)
  g_settings.set('hiddenEmail', enterGame.accountNameTextEdit:isTextHidden() and 1 or 0)

  g_settings.save()

  local server_params = G.host:split(":")
  if G.host:lower():find("http") ~= nil then
    if #server_params >= 4 then
      G.host = server_params[1] .. ":" .. server_params[2] .. ":" .. server_params[3]
      G.clientVersion = tonumber(server_params[4])
    elseif #server_params >= 3 then
      if tostring(tonumber(server_params[3])) == server_params[3] then
        G.host = server_params[1] .. ":" .. server_params[2]
        G.clientVersion = tonumber(server_params[3])
      end
    end
    return EnterGame.doLoginHttp()
  end

  local server_ip = server_params[1]
  local server_port = 7171
  if #server_params >= 2 then
    server_port = tonumber(server_params[2])
  end

  if #server_params >= 3 then
    G.clientVersion = tonumber(server_params[3])
  end
  if type(server_ip) ~= 'string' or server_ip:len() <= 3 or not server_port or not G.clientVersion then
    return EnterGame.onError("Invalid server, it should be in format IP:PORT or it should be http url to login script")
  end

  protocolLogin = ProtocolLogin.create()
  protocolLogin.onLoginError = onProtocolError
  protocolLogin.onSessionKey = onSessionKey
  protocolLogin.onCharacterList = onCharacterList
  protocolLogin.onUpdateNeeded = onUpdateNeeded
  protocolLogin.onProxyList = onProxyList

  EnterGame.hide()
  loadBox = displayCancelBox(tr('Please wait'), tr('Connecting to login server...'))
  connect(loadBox, {
    onCancel = function(msgbox)
      loadBox = nil
      protocolLogin:cancelLogin()
      EnterGame.show()
    end
  })

  if G.clientVersion == 1000 then -- some people don't understand that OTZudo 10 uses 1100 protocol
    G.clientVersion = 1100
  end
  -- if you have custom rsa or protocol edit it here
  g_game.setClientVersion(G.clientVersion)
  g_game.setStringVersion(GameInfo.strVersion)
  g_game.setProtocolVersion(g_game.getClientProtocolVersion(G.clientVersion))
  g_game.setCustomProtocolVersion(0)
  g_game.setCustomOs(-1) -- disable
  g_game.chooseRsa(G.host)

  -- extra features from init.lua
  for i = 4, #server_params do
    g_game.enableFeature(tonumber(server_params[i]))
  end

  -- proxies
  if g_proxy then
    g_proxy.clear()
  end

  if modules.game_things.isLoaded() then
    g_logger.info("Connecting to: " .. server_ip .. ":" .. server_port)
    protocolLogin:login(server_ip, server_port, G.account, G.password, G.authenticatorToken, G.stayLogged)
  else
    loadBox:destroy()
    loadBox = nil
    EnterGame.show()
  end
end

function EnterGame.doLoginHttp()
  if G.host == nil or G.host:len() < 10 then
    return EnterGame.onError("Invalid server url: " .. G.host)
  end

  loadBox = displayCancelBox(tr('Please wait'), tr('Connecting to login server...'))
  connect(loadBox, {
    onCancel = function(msgbox)
      loadBox = nil
      EnterGame.show()
    end
  })

  local data = {
    type = "login",
    account = G.account,
    accountname = G.account,
    email = G.account,
    password = G.password,
    gtoken = G.gtoken,
    token = G.authenticatorToken,
    version = APP_VERSION,
    uid = G.UUID,
    stayloggedin = true
  }

  local server = serverSelector:getText()
  local chosenServer = Servers and getServerInfoByName(server) or nil
  if chosenServer then
    local loginLink = chosenServer.loginLink
    waitingForHttpResults = 1
    HTTP.postJSON(loginLink, data, onHTTPResult)
  end
  EnterGame.hide()
end

function EnterGame.onError(err)
  if loadBox then
    loadBox:destroy()
    loadBox = nil
  end
  local errorBox = displayErrorBox(tr('Login Error'), err)
  errorBox.onOk = EnterGame.show
end

function EnterGame.onLoginError(err)
  if loadBox then
    loadBox:destroy()
    loadBox = nil
  end
  local errorBox = displayErrorBox(tr('Login Error'), err)
  errorBox.onOk = EnterGame.show
  if err:lower():find("invalid") or err:lower():find("not correct") or err:lower():find("or password") then
    EnterGame.clearAccountFields()
  end
end

function chooseTextMode()
  local hiddenButton = enterGame:getChildById('hidden')
  local hidden = enterGame.accountNameTextEdit:isTextHidden()

  isButtonPressed = not isButtonPressed

  if isButtonPressed then
    hiddenButton:setImageSource("/images/ui/hidden-button-down")
    enterGame.accountNameTextEdit:setTextHidden(false)
  else
    hiddenButton:setImageSource("/images/ui/hidden-button")
    enterGame.accountNameTextEdit:setTextHidden(true)
  end
end

function chooseButtonVisibility()
  local checkboxEmail = enterGame:getChildById('rememberEmailBox')
  local checkbox = enterGame:getChildById('rememberPasswordBox')
  local buttonMail = enterGame:getChildById('buttonInformation')
  local buttonPass = enterGame:getChildById('passwordInformation')

  if checkboxEmail:isChecked() then
    buttonMail:setVisible(true)
  else
    buttonMail:setVisible(false)
  end

  if checkbox:isChecked() then
    buttonPass:setVisible(true)
  else
    buttonPass:setVisible(false)
  end
end

local function isValidEmail(value)
  return value == "" or (string.len(value) > 3 and string.find(value, "@"))
end

function onTextChange()
  if not isValidEmail(enterGame.accountNameTextEdit:getText()) then
    enterGame.emailStatus:setVisible(true)
  else
    enterGame.emailStatus:setVisible(false)
  end
end

local charset = {}

for c = 48, 57 do
  table.insert(charset, string.char(c))
end

for c = 65, 90 do
  table.insert(charset, string.char(c))
end

for c = 97, 122 do
  table.insert(charset, string.char(c))
end


local function randomString(length)
  if not length or length <= 0 then
    return ""
  end

  math.randomseed(os.clock() ^ 5)

  if length == 1 then
    return charset[math.random(1, #charset)]
  end

  return randomString(length - 1) .. charset[math.random(1, #charset)]
end

-- (Login with Google removido a pedido: OAuth do Google nao e mais usado.)
