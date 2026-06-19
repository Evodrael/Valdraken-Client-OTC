-- @docclass
UIPopupMenu = extends(UIWidget, "UIPopupMenu")

local currentMenu

function UIPopupMenu.create()
  local menu = UIPopupMenu.internalCreate()
  local layout = UIVerticalLayout.create(menu)
  layout:setFitChildren(true)
  menu:setLayout(layout)
  menu.isGameMenu = false
  menu:insertLuaCall("onGeometryChange")
  menu:insertLuaCall("onDestroy")
  return menu
end

function UIPopupMenu:display(pos)
  -- don't display if not options was added
  if self:getChildCount() == 0 then
    self:destroy()
    return
  end

  -- Guard against stale references: rapid right-clicks (e.g. on Multi-Action
  -- slots) can leave currentMenu pointing at an already-destroyed widget;
  -- calling :destroy() on it triggers the "destroy widget two times" warning.
  if currentMenu and not currentMenu:isDestroyed() then
    currentMenu:destroy()
  end
  currentMenu = nil

  if pos == nil then
    pos = g_window.getMousePosition()
  end

  rootWidget:addChild(self)
  self:setPosition(pos)
  self:grabMouse()
  self:raise()
  self:focus()
  self:setHeight(self:getHeight() + 10)
  --self:grabKeyboard()
  currentMenu = self
end

function UIPopupMenu:onGeometryChange(oldRect, newRect)
  local parent = self:getParent()
  if not parent then return end
  local ymax = parent:getY() + parent:getHeight()
  local xmax = parent:getX() + parent:getWidth()
  if newRect.y + newRect.height > ymax then
    local newy = ymax - newRect.height
    if newy > 0 and newy + newRect.height < ymax then self:setY(newy) end
  end
  if newRect.x + newRect.width > xmax then
    local newx = xmax - newRect.width
    if newx > 0 and newx + newRect.width < xmax then self:setX(newx) end
  end
  self:bindRectToParent()
end

function UIPopupMenu:addOption(optionName, optionCallback, shortcut)
  local optionWidget = g_ui.createWidget(self:getStyleName() .. 'Button', self)
  optionWidget.onClick = function(widget)
    self:destroy()
    optionCallback()
  end
  if type(optionName) == 'table' then
    optionWidget:setColoredText(optionName)
  else
    optionWidget:setText(optionName)
  end
  local width = optionWidget:getTextSize().width + optionWidget:getMarginLeft() + optionWidget:getMarginRight() + 50

  if shortcut then
    local shortcutLabel = g_ui.createWidget(self:getStyleName() .. 'ShortcutLabel', optionWidget)
    if type(shortcut) == 'table' then
      shortcutLabel:setColoredText(shortcut)
    else
      shortcutLabel:setText(tr(shortcut))
    end
    width = width + shortcutLabel:getTextSize().width + shortcutLabel:getMarginLeft() + shortcutLabel:getMarginRight()
  end

  self:setWidth(math.max(self:getWidth(), width))
  self:setHeight(self:getHeight() + optionWidget:getHeight())
end

function UIPopupMenu:addCheckBoxOption(optionName, optionCallback, shortcut, checked)
  local optionWidget = g_ui.createWidget(self:getStyleName() .. 'CheckBox', self)
  optionWidget.onClick = function(widget)
    optionCallback()
    self:destroy()
  end
  optionWidget:setText(optionName)
  optionWidget:setChecked(checked)
  local width = optionWidget:getTextSize().width + optionWidget:getMarginLeft() + optionWidget:getMarginRight() + 50

  if shortcut then
    local shortcutLabel = g_ui.createWidget(self:getStyleName() .. 'ShortcutLabel', optionWidget)
    shortcutLabel:setText(shortcut)
    width = width + shortcutLabel:getTextSize().width + shortcutLabel:getMarginLeft() + shortcutLabel:getMarginRight()
  end

  self:setWidth(math.max(self:getWidth(), width))
  return optionWidget
end

function UIPopupMenu:addSeparator()
  local separator = g_ui.createWidget('HorizontalSeparator', self)
  separator:setMarginLeft(1)
  separator:setMarginRight(1)
  self:setHeight(self:getHeight() + (separator:getHeight() + 4))
end

function UIPopupMenu:setGameMenu(state)
  self.isGameMenu = state
  self:setHeight(22)
end

function UIPopupMenu:onDestroy()
  if currentMenu == self then
    currentMenu = nil
  end
  self:ungrabMouse()

  -- Bring back focus to main panel
  scheduleEvent(function() rootWidget:getChildById("gameRootPanel"):focus() end, 50)
end

function UIPopupMenu:onMousePress(mousePos, mouseButton)
  -- clicks outside menu area destroys the menu
  if not self:containsPoint(mousePos) then
    self:destroy()
  end
  return true
end

function UIPopupMenu:onKeyPress(keyCode, keyboardModifiers)
  if keyCode == KeyEscape then
    self:destroy()
    return true
  end
  return false
end

-- close all menus when the window is resized
local function onRootGeometryUpdate()
  if currentMenu and not currentMenu:isDestroyed() then
    currentMenu:destroy()
  end
  currentMenu = nil
end

local function onGameEnd()
  if currentMenu and currentMenu.isGameMenu and not currentMenu:isDestroyed() then
    currentMenu:destroy()
    currentMenu = nil
  end
end

connect(rootWidget, { onGeometryChange = onRootGeometryUpdate })
connect(g_game, { onGameEnd = onGameEnd } )
