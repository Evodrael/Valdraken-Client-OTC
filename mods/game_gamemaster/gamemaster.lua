local lockedLevel = 7

if not GameMasterOptions then
  GameMasterOptions = {}
end

-- mapPanel com guarda de nil (pode nao existir fora do jogo)
local function mapPanel()
  if not modules.game_interface then return nil end
  return modules.game_interface.getMapPanel()
end

function init()
  connect(g_game, {
    onGameStart = onStartGame,
    onViewFloor = onViewFloor,
    onGotoPlayer = onGotoPlayer,
  })

  connect(LocalPlayer, {
    onPositionChange = onPlayerPositionChange
  })
end

function terminate()
  disconnect(g_game, {
    onGameStart = onStartGame,
    onViewFloor = onViewFloor,
    onGotoPlayer = onGotoPlayer,
  })

  disconnect(LocalPlayer, {
    onPositionChange = onPlayerPositionChange
  })
end

function onStartGame()
  local benchmark = g_clock.millis()
  lockedLevel = 7
  local player = g_game.getLocalPlayer()
  if player and player:getPosition() then
    lockedLevel = player:getPosition().z
  end

  -- Goto cross-world: apos reconectar no mundo do alvo, executa o /goto guardado.
  if GameMasterOptions.targetName then
    local n = GameMasterOptions.targetName
    scheduleEvent(function()
      ExecuteGoto(n)
    end, 1000)
    GameMasterOptions.targetName = nil
  end

  GameMasterOptions = {}
  consoleln("Game Master loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

-- C++ dispara onPositionChange(newPos, oldPos) (sem creature). Usamos o localplayer.
function onPlayerPositionChange(newPos, oldPos)
  local player = g_game.getLocalPlayer()
  if player and player:getPosition() then
    lockedLevel = player:getPosition().z
  end
  local mp = mapPanel()
  if mp then mp:unlockVisibleFloor() end
end

-- "Espiar" andar acima/abaixo (sinal opcional; so age se for disparado).
function onViewFloor(upView)
  local mp = mapPanel()
  if not mp then return end
  if not upView then
    lockedLevel = lockedLevel + 1
  else
    lockedLevel = lockedLevel - 1
  end
  mp:lockVisibleFloor(lockedLevel)
end

-- Ponto de entrada (GM): pede ao servidor onde esta o jogador alvo.
-- Pode ser chamado de um keybind/console: modules.game_gamemaster.gotoPlayer("Nome")
function gotoPlayer(targetName)
  if not targetName or targetName == '' then return end
  if g_game.requestGotoPlayer then
    g_game.requestGotoPlayer(targetName)
  end
end

-- Resposta do servidor (0x39 cat1). status: 0=nao achou, 1=teleportado (mesmo mundo,
-- ja resolvido no servidor), 2=reconectar no worldId (jogador em outro mundo).
function onGotoPlayer(targetName, status, worldId)
  if status == 2 and worldId and worldId > 0 then
    GameMasterOptions.targetName = targetName
    modules.client_entergame.SetLoginOption(worldId)
  elseif status == 0 then
    if modules.game_textmessage then
      modules.game_textmessage.displayFailureMessage("Player '" .. tostring(targetName) .. "' nao encontrado online.")
    end
  end
  -- status 1: ja teleportado no servidor; nada a fazer no cliente.
end

function ExecuteGoto(targetName)
  g_game.talk("/goto " .. targetName)
end
