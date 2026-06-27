-- CONFIG
APP_NAME = "valdraken"  -- important, change it, it's name for config dir and files in appdata
APP_VERSION = 1524        -- client version for updater and login to identify outdated client
DEFAULT_LAYOUT = "data"  -- on android it's forced to "mobile", check code bellow

GameInfo = {
  name = "Valdraken",
  version = 1524,
  strVersion = "15.24",
  CoinName = "Valdraken Coins"
}

-- If you don't use updater or other service, set it to updater = ""
Services = {
  website = "", -- currently not used
  updater = "",
  stats = "",
  crash = "",
  feedback = "",
  status = {}
}

-- RubinOT enter game expects a list of server descriptors.
Servers = {
  {
    name = "Valdraken",
    loginLink = "http://valdraken.com.br/login.php",
    clientServicesLink = "http://valdraken.com.br/login.php",
    hintsLink = "",
    googleLogin = ""
  }
}

-- Link do botao "Join Discord" da barra superior da tela de login. Altere aqui (hook do init).
-- O topmenu le DISCORD_LINK como padrao; o servidor ainda pode sobrescrever via data.discord_link.
DISCORD_LINK = "https://discord.gg/WnTXymJpQc"

-- Multi-world: os mundos ATIVOS sao lidos automaticamente do login.php (playdata.worlds) e
-- vinculados a cada personagem pelo worldid. Para multiplos endpoints de login, adicione mais
-- entradas na tabela Servers acima (cada uma com seu loginLink). Fallback offline opcional:
WORLDS = WORLDS or {
  -- { id = 1, name = "BravesOT", host = "127.0.0.1", port = 7172, pvptype = 0 },
}

if type(Services.status) == 'string' then
  Services.status = Services.status:len() > 0 and { Services.status } or {}
end

if #Services.status == 0 and Servers and Servers[1] and type(Servers[1].clientServicesLink) == 'string' and Servers[1].clientServicesLink:len() > 0 then
  Services.status = { Servers[1].clientServicesLink }
end

--Server = "ws://otclient.ovh:3000/"
--Server = "ws://127.0.0.1:88/"
--USE_NEW_ENERGAME = true -- uses entergamev2 based on websockets instead of entergame
ALLOW_CUSTOM_SERVERS = false -- if true it shows option ANOTHER on server list

g_app.setName("Valdraken")
g_app.setCompactName(APP_NAME)
g_resources.setupUserWriteDir(APP_NAME)
-- CONFIG END

-- print first terminal message
g_logger.info(os.date("== application started at %b %d %Y %X"))
g_logger.info(g_app.getName() .. ' ' .. g_app.getVersion() .. ' rev ' .. g_app.getBuildRevision() .. ' (' .. g_app.getBuildCommit() .. ') made by ' .. g_app.getAuthor() .. ' built on ' .. g_app.getBuildDate() .. ' for arch ' .. g_app.getBuildArch())

if not g_resources.directoryExists("/data") then
  g_logger.fatal("Data dir doesn't exist.")
end

if not g_resources.directoryExists("/modules") then
  g_logger.fatal("Modules dir doesn't exist.")
end

-- settings
g_configs.loadSettings("/config.otml")

-- set layout
local settings = g_configs.getSettings()
local layout = DEFAULT_LAYOUT
if g_app.isMobile() then
  layout = "mobile"
elseif settings:exists('layout') then
  layout = settings:getValue('layout')
end
if g_resources.directoryExists('/layouts/' .. layout) then
  g_resources.setLayout(layout)
end

-- Mount the mods/ folder at root so user mods (e.g. mods/game_cyclopedia)
-- can reference their assets via `/game_cyclopedia/...` instead of the
-- longer `/mods/game_cyclopedia/...`. Matches the upstream OTC convention.
g_resources.addSearchPath(g_resources.getWorkDir() .. 'mods', true)

-- load mods
g_modules.discoverModules()
g_modules.ensureModuleLoaded("corelib")
  
local function loadModules()
  -- libraries modules 0-99
  g_modules.autoLoadModules(99)
  g_modules.ensureModuleLoaded("gamelib")

  -- client modules 100-499
  g_modules.autoLoadModules(499)
  g_modules.ensureModuleLoaded("client")

  -- game modules 500-999
  g_modules.autoLoadModules(999)
  g_modules.ensureModuleLoaded("game_interface")

  -- mods 1000-9999
  g_modules.autoLoadModules(9999)
end

-- report crash
if type(Services.crash) == 'string' and Services.crash:len() > 4 and g_modules.getModule("crash_reporter") then
  g_modules.ensureModuleLoaded("crash_reporter")
end

-- run updater, must use data.zip
if type(Services.updater) == 'string' and Services.updater:len() > 4 
  and g_resources.isLoadedFromArchive() and g_modules.getModule("updater") then
  g_modules.ensureModuleLoaded("updater")
  return Updater.init(loadModules)
end
loadModules()
