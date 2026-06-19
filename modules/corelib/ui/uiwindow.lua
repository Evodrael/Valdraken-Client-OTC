-- @docclass
UIWindow = extends(UIWidget, "UIWindow")

local function canMoveWindowFromTitle(window, mousePos)
  if window.static then
    return false
  end

  local titleHeight = window.titleDragHeight or 40
  if mousePos.y < window:getY() or mousePos.y > window:getY() + titleHeight then
    return false
  end

  -- Block window drag if the click landed on an interactive child widget
  -- (button, label with handler, etc). Phantom children pass through and
  -- still allow dragging from the title bar background.
  local child = window:recursiveGetChildByPos(mousePos, false)
  if child and child ~= window and not child:isPhantom() then
    return false
  end

  return true
end

function UIWindow.create()
  local window = UIWindow.internalCreate()
  window:setTextAlign(AlignTopCenter)
  window:setDraggable(true)
  window:setAutoFocusPolicy(AutoFocusFirst)
  window:insertLuaCall("onFocusChange")
  return window
end

function UIWindow:onKeyDown(keyCode, keyboardModifiers)
  if not self:isVisible() then
    return false
  end

  if keyboardModifiers == KeyboardNoModifier then
    if keyCode == KeyEnter or keyCode == KeyNumEnter then
      g_ui.setCallEnterKey(true)
      signalcall(self.onEnter, self)
    elseif keyCode == KeyEscape then
      g_ui.setCallEscapeKey(true)
      signalcall(self.onEscape, self)
    end
  end
end

function UIWindow:onFocusChange(focused)
  if focused then self:raise() end
end

function UIWindow:onMousePress(mousePos, mouseButton)
  if mouseButton ~= MouseLeftButton or not canMoveWindowFromTitle(self, mousePos) then
    return false
  end

  self:raise()
  self:breakAnchors()
  self.titleMoving = true
  self.movingReference = { x = mousePos.x - self:getX(), y = mousePos.y - self:getY() }
  self:grabMouse()
  return true
end

function UIWindow:onMouseRelease(mousePos, mouseButton)
  if mouseButton ~= MouseLeftButton or not self.titleMoving then
    return false
  end

  self.titleMoving = false
  self:ungrabMouse()
  return true
end

local function cancelTitleMove(window)
  if window.titleMoving then
    window.titleMoving = false
    pcall(function() window:ungrabMouse() end)
  end
end

function UIWindow:onVisibilityChange(visible)
  if not visible then
    cancelTitleMove(self)
  end
end

function UIWindow:onMouseMove(mousePos, mouseMoved)
  if not self.titleMoving then
    return false
  end

  local pos = { x = mousePos.x - self.movingReference.x, y = mousePos.y - self.movingReference.y }
  self:setPosition(pos)
  self:bindRectToParent()
  return true
end

function UIWindow:onDragEnter(mousePos)
  if self.static then
    return false
  end
  self:breakAnchors()
  self.movingReference = { x = mousePos.x - self:getX(), y = mousePos.y - self:getY() }
  return true
end

function UIWindow:onDragLeave(droppedWidget, mousePos)
  -- TODO: auto detect and reconnect anchors
end

function UIWindow:onDragMove(mousePos, mouseMoved)
  if self.static then
    return
  end
  local pos = { x = mousePos.x - self.movingReference.x, y = mousePos.y - self.movingReference.y }
  self:setPosition(pos)
  self:bindRectToParent()
end
