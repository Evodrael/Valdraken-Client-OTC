-- @docclass
function g_mouse.bindAutoPress(widget, callback, delay, button, loopingDelay)
  if not loopingDelay then
    loopingDelay = 30
  end

  local button = button or MouseLeftButton
  connect(widget, { onMousePress = function(widget, mousePos, mouseButton)
    if mouseButton ~= button then
      return false
    end
    local startTime = g_clock.millis()
    callback(widget, mousePos, mouseButton, 0)
    periodicalEvent(function()
      callback(widget, g_window.getMousePosition(), mouseButton, g_clock.millis() - startTime)
    end, function()
      return g_mouse.isPressed(mouseButton)
    end, loopingDelay, delay)
    return true
  end })
end

function g_mouse.bindPressMove(widget, callback)
  connect(widget, { onMouseMove = function(widget, mousePos, mouseMoved)
    if widget:isPressed() then
      callback(mousePos, mouseMoved)
      return true
    end
  end })
end

function g_mouse.bindPress(widget, callback, button)
  connect(widget, { onMousePress = function(widget, mousePos, mouseButton)
    if not button or button == mouseButton then
      callback(mousePos, mouseButton)
      return true
    end
    return false
  end })
end

if not g_mouse.grabbedMouse then
  g_mouse.grabbedMouse = {}
end

function g_mouse.updateGrabber(widget, mouse)
  if not g_mouse.grabbedMouse[widget] then
    g_mouse.grabbedMouse[widget] = mouse
  else
    g_mouse.grabbedMouse[widget] = nil
  end
end

function g_mouse.clearGrabber()
  for widget, mouse in pairs(g_mouse.grabbedMouse) do
    if mouse ~= '' then
      g_mouse.popCursor(mouse)
    end
    widget:ungrabMouse()
  end
  g_mouse.grabbedMouse = {}
end

-- Cursor animation gating: keep the animated cursor still while the user
-- navigates the UI (inventory, tabs, windows, etc) and only allow animation
-- frames to advance while the mouse is over the game map.
g_mouse.animationGate = g_mouse.animationGate or {
  event = nil,
  lastState = nil,
  -- Class names that should be treated as "game map" / play area. Hovering
  -- any of these (or a descendant) keeps the animation running.
  mapClasses = {
    UIGameMap = true,
  },
  -- Class names that, when found in the parent chain, force animation off
  -- even though a child claims to be the map. Currently empty but kept for
  -- future overrides.
  blockerClasses = {},
}

local function isHoverInsideGameMap(widget)
  if not widget then
    return false
  end

  -- Anima SO quando o cursor esta sobre o quadrado do jogo (o widget do mapa em si). Sidebuttons,
  -- barras e paineis laterais sao FILHOS do gameMapPanel; a versao antiga subia toda a cadeia de
  -- pais e, ao achar o UIGameMap ancestral, animava o cursor fora do jogo. Comparamos por
  -- referencia ao mapPanel (e, como fallback, a propria classe do widget sob o cursor).
  local gameInterface = modules and modules.game_interface or nil
  local mapPanel = gameInterface and gameInterface.getMapPanel and gameInterface.getMapPanel() or nil
  if mapPanel and widget == mapPanel then
    return true
  end

  local className = widget.getClassName and widget:getClassName() or nil
  if className and g_mouse.animationGate.blockerClasses[className] then
    return false
  end
  return className ~= nil and g_mouse.animationGate.mapClasses[className] == true
end

local function refreshCursorAnimationState()
  if not g_mouse.setAnimationPaused or not g_ui.getHoveredWidget then
    return
  end

  local hovered = g_ui.getHoveredWidget()
  local onMap = hovered and isHoverInsideGameMap(hovered) or false
  local paused = not onMap

  if g_mouse.animationGate.lastState ~= paused then
    g_mouse.animationGate.lastState = paused
    g_mouse.setAnimationPaused(paused)
    -- Ao SAIR do quadrado do jogo, restaura o cursor PADRAO. So pausar a animacao deixava o
    -- cursor de mapa (walk/attacker/use/...) congelado no frame 0 sobre sidebuttons/paineis.
    -- Sobre o mapa, o MapView (onMouseMove) reaplica o cursor de contexto correto.
    --
    -- EXCECAO: se houver um cursor CUSTOMIZADO empilhado (g_mouse.pushCursor -> 'target'/grab
    -- do "assign object", 'text' do textedit, etc.), NAO forcar o cursor do sistema. Antes,
    -- ao passar do mapa para o inventario/interface durante um "assign object", o gate
    -- sobrescrevia o grab com a seta padrao. isCursorChanged() = stack de cursor nao-vazia.
    if paused and g_window and g_window.setSystemCursor
        and not (g_mouse.isCursorChanged and g_mouse.isCursorChanged()) then
      g_window.setSystemCursor("default")
    end
  end
end

function g_mouse.startAnimationGate()
  if g_mouse.animationGate.event then
    return
  end
  if not g_mouse.setAnimationPaused then
    return
  end

  g_mouse.animationGate.lastState = nil
  refreshCursorAnimationState()
  g_mouse.animationGate.event = cycleEvent(refreshCursorAnimationState, 80)
end

function g_mouse.stopAnimationGate()
  if g_mouse.animationGate.event then
    removeEvent(g_mouse.animationGate.event)
    g_mouse.animationGate.event = nil
  end
  if g_mouse.setAnimationPaused then
    g_mouse.setAnimationPaused(false)
  end
  g_mouse.animationGate.lastState = nil
end

-- Auto-start the gate on module load so the behaviour is global. Other
-- modules can disable it via g_mouse.stopAnimationGate() if needed.
if g_mouse.setAnimationPaused then
  g_mouse.startAnimationGate()
end
