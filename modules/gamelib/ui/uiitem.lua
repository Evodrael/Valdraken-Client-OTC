local toolTipLabel = nil
local rarityPriceRefreshConnected = false

local function refreshRarityFrames(widget)
  if not widget or (widget.isDestroyed and widget:isDestroyed()) then
    return
  end

  if widget.getItem and widget.setIcon and ItemsDatabase and ItemsDatabase.setRarityItem then
    local item = widget:getItem()
    if not item and widget.getItemId then
      local itemId = tonumber(widget:getItemId()) or 0
      if itemId > 0 then
        item = itemId
      end
    end
    if item then
      ItemsDatabase.setRarityItem(widget, item)
    end
  end

  if widget.getChildren then
    for _, child in pairs(widget:getChildren()) do
      refreshRarityFrames(child)
    end
  end
end

local function ensureRarityPriceRefresh()
  if rarityPriceRefreshConnected or not g_things then
    return
  end

  rarityPriceRefreshConnected = true
  connect(g_things, {
    onItemsPrice = function()
      scheduleEvent(function()
        local root = (m_interface and m_interface.getRootPanel and m_interface.getRootPanel()) or rootWidget
        if root then
          refreshRarityFrames(root)
        end
      end, 100)
    end
  })
end

ensureRarityPriceRefresh()

function UIItem:onDragMove(mousePos, mouseMoved)
  if self.dragClone then
    self.dragClone:setX(mousePos.x + 12)
    self.dragClone:setY(mousePos.y + 9)
  end

  self:onDragMoveEquipment(mousePos)
  return true
end

function UIItem:onDragMoveEquipment(mousePos)
  local destination = rootWidget:recursiveGetChildByPos(mousePos, true)
  if destination and string.find(destination:getId(), "equipSlot") and destination:getId() ~= "equipSlot3" then
    local item = self:getItem()
    if not item then
      return
    end

    local color = "$var-text-cip-color-green"
    local slot = tonumber(string.match(destination:getId(), "%d+"))
    local canEquip, message = modules.game_actionbar.isValidEquipSlot(item, slot)
    if not canEquip then
      color = "$var-text-cip-store-red"

      if toolTipLabel then
        toolTipLabel:setText(message)
      else
        toolTipLabel = g_ui.createWidget('UILabel', rootWidget)
        toolTipLabel:setId('toolTip')
        toolTipLabel:setTextAlign(AlignNone)
        toolTipLabel:setTextOffset(topoint(3 .. " " .. 2))
        toolTipLabel:setText(message)
        toolTipLabel:setFont("Verdana Bold-11px")
        toolTipLabel:resizeToText()
        toolTipLabel:resize(toolTipLabel:getWidth() + 8, toolTipLabel:getHeight() + 4)
        toolTipLabel:setBackgroundColor("#c0c0c0")
        toolTipLabel:setColor("#3f3f3f")
        toolTipLabel:setBorderWidth(1)
        toolTipLabel:setBorderColor("#000000")
      end
    end

    if canEquip and toolTipLabel then
      toolTipLabel:destroy()
      toolTipLabel = nil
    end

    destination:setBorderWidth(1)
    destination:setBorderColor(color)
  elseif toolTipLabel then
    toolTipLabel:destroy()
    toolTipLabel = nil
  end

  if toolTipLabel then
    toolTipLabel:setX(mousePos.x + 12)
    toolTipLabel:setY(mousePos.y + 46)
  end
end

function UIItem:onDragEnter(mousePos)
  if self:isVirtual() and not self:isDraggable() then return false end

  local item = self:getItem()
  if not item or item:getId() == 0 then
    return false
  end
  if not item and self:getImageSource() == '' then return false end

  self:setBorderWidth(1)
  self.currentDragThing = item
  g_mouse.pushCursor('target')

  if not item:isNotMoveable() then
    local dragClone = g_ui.createWidget("DragItem")
    dragClone._skipRarityFrame = true
    -- Parent no gameRootPanel (mesmo padrao do drag da actionbar, que funciona). Antes era
    -- getRootPanel():getParent() (rootWidget) e o ghost sumia atras dos paineis de
    -- inventario/equip/container; como filho do gameRootPanel o clone e o ultimo filho = sempre por cima.
    dragClone:setParent(m_interface.getRootPanel())
    dragClone:raise()
    dragClone:setItemId(item:getStoreId() > 0 and item:getStoreId() or item:getId())
    dragClone:setItemSubType(item:getSubType())
    dragClone:setX(mousePos.x + 12)
    dragClone:setY(mousePos.y + 9)
    self.dragClone = dragClone
  end
  return true
end

function UIItem:onDragLeave(droppedWidget, mousePos)
  if toolTipLabel then
    toolTipLabel:destroy()
    toolTipLabel = nil
  end

  if self:isVirtual() and not self:isDraggable() then return false end
  self.currentDragThing = nil

  g_mouse.popCursor('target')

  self:setBorderWidth(0)
  self.hoveredWho = nil

  if self.dragClone then
    self.dragClone:destroy()
    self.dragClone = nil
  end
  return true
end

function UIItem:onDrop(widget, mousePos, forced)
  if toolTipLabel then
    toolTipLabel:destroy()
    toolTipLabel = nil
  end

  self:setBorderWidth(0)
  if not self:canAcceptDrop(widget, mousePos) and not forced then return false end

  local item = widget.currentDragThing
  if not item or not item:isItem() then return false end

  local destination = rootWidget:recursiveGetChildByPos(mousePos, true)
  if destination and destination:backwardsGetWidgetById("tabBar") then
    local actionbar = destination:getParent():getParent()
    if actionbar.locked then
      return false
    end

    modules.game_actionbar.assignItem(destination:getParent(), item:getId(), item:getTier(), true)
    return true
  end

  if destination and string.find(destination:getId(), "equipSlot") then
    modules.game_actionbar.onDropPresetItem(destination, item)
    return true
  end

  if destination:getId() == "slot5" and destination:getChildById("slot5Dual"):isVisible() then
    return false
  end

  if self.selectable then
    if item:isPickupable() then
      local newItem = Item.create(item:getId(), item:getCountOrSubType())
      newItem:setTier(item:getTier())
      self:setItem(newItem)
      return true
    end
    return false
  end

  local toPos = self.position
  if not toPos then
    return false
  end

  local itemPos = item:getPosition() or {x = 0, y = 0, z = 0}
  if itemPos.x == toPos.x and itemPos.y == toPos.y and itemPos.z == toPos.z then return false end
  if toPos.y == 0x20 or toPos.y == 0x21 then
    return false
  end

  if item:getCount() > 1 then
    m_interface.moveStackableItem(item, toPos)
  else
    local manualSort = modules.game_containers.useManualSort()

    if item:isContainer() then
      local canMoveContainer = true
      local destWidget = rootWidget:recursiveGetChildByPos(mousePos, false)
      if destWidget and (destWidget:getClassName() == "UIItem" or destWidget:getClassName() == "Item") and destWidget:getItem() and not destWidget:isVirtual() then
        local destPos = destWidget:getItem():getPosition()
        local canAsk = m_settings.getOption('stowContainer')
        if canAsk and (destPos.x == 65535 and destPos.y == 65 and destPos.z == 1) and destWidget:getItemId() == 28750 then
          modules.game_stash.stowContainerContent(item, toPos, true)
          canMoveContainer = false
        end
      end
      if canMoveContainer then
        g_game.move(item, toPos, 1, manualSort)
      end
    else
      g_game.move(item, toPos, 1, manualSort)
    end
  end

  self:setBorderWidth(0)
  return true
end

function UIItem:onDestroy()
  if self == g_ui.getDraggingWidget() and self.hoveredWho then
    self.hoveredWho:setBorderWidth(0)
  end

  if self.hoveredWho then
    self.hoveredWho = nil
  end

  if self.dragClone then
    self.dragClone:destroy()
    self.dragClone = nil
  end
end

function UIItem:onHoverChange(hovered)
  UIWidget.onHoverChange(self, hovered)

  if (self:isVirtual() and not self.clone) or (not self:isDraggable() and not self.clone) then
    self:setBorderWidth(0)
    return
  end

  local draggingWidget = g_ui.getDraggingWidget()
  if draggingWidget then
    if self == draggingWidget and hovered then
	  draggingWidget:setBorderWidth(1)
	else
	  draggingWidget:setBorderWidth(0)
	end
  end

  if draggingWidget and self ~= draggingWidget then
    local gotMap = draggingWidget:getClassName() == 'UIGameMap'
    local gotItem = draggingWidget:getClassName() == 'UIItem' and not draggingWidget:isVirtual()
	  if hovered and (gotItem or gotMap) then
      self:setBorderWidth(1)
      draggingWidget.hoveredWho = self
    else
      self:setBorderWidth(0)
      draggingWidget.hoveredWho = nil
    end
  end
end

local function shouldOpenItemMenu(mouseButton)
  if mouseButton ~= MouseRightButton then
    return false
  end

  local gameControl = m_settings.getOption('classicControl')
  if gameControl == 1 then
    return g_keyboard.isCtrlPressed()
  end

  if gameControl == 2 then
    return not g_keyboard.isCtrlPressed() and not g_keyboard.isAltPressed() and not g_keyboard.isShiftPressed()
  end

  return false
end

function UIItem:onMousePress(mousePosition, mouseButton)
  if not shouldOpenItemMenu(mouseButton) or self:isVirtual() then
    return false
  end

  local item = self:getItem()
  if not item or not self:containsPoint(mousePosition) then
    return false
  end

  if m_interface.processItemMenuAction then
    self.cancelNextRelease = true
    return m_interface.processItemMenuAction(mousePosition, item)
  end

  if m_interface.processMouseAction then
    self.cancelNextRelease = true
    return m_interface.processMouseAction(nil, mousePosition, mouseButton, nil, item, item, nil, nil)
  end

  return false
end

function UIItem:onMouseRelease(mousePosition, mouseButton)
  if self.cancelNextRelease then
    self.cancelNextRelease = false
    return true
  end

  if self:isVirtual() then return false end

  local item = self:getItem()
  if not item or not self:containsPoint(mousePosition) then return false end

  local gameControl = m_settings.getOption('classicControl')
  local classic = gameControl == 1
  if classic and --and not g_app.isMobile() and
     ((g_mouse.isPressed(MouseLeftButton) and mouseButton == MouseRightButton) or
      (g_mouse.isPressed(MouseRightButton) and mouseButton == MouseLeftButton)) then
    g_game.look(item)
    self.cancelNextRelease = true
    return true
  elseif shouldOpenItemMenu(mouseButton) and m_interface.processItemMenuAction then
    return m_interface.processItemMenuAction(mousePosition, item)
  elseif m_interface.processMouseAction(nil, mousePosition, mouseButton, nil, item, item, nil, nil) then
    return true
  end
  return false
end

function UIItem:canAcceptDrop(widget, mousePos)
  local destination = rootWidget:recursiveGetChildByPos(mousePos, true)
  if destination and string.find(destination:getId(), "equipSlot") and destination:getId() ~= "equipSlot3" then
    return true
  end

  if not self.selectable and ((self:isVirtual() and not self.clone) or not (self:isDraggable() or self.clone)) then return false end
  if not widget or not widget.currentDragThing then return false end

  local children = rootWidget:recursiveGetChildrenByPos(mousePos)
  for i=1,#children do
    local child = children[i]
    if child == self then
      return true
    elseif not child:isPhantom() then
      return false
    end
  end

  error('Widget ' .. self:getId() .. ' not in drop list.')
  return false
end

function UIItem:onClick(mousePos)
  g_client.onReleaseFocusedWidgets()
  if not self.selectable or not self.editable then
    return
  end

  if modules.game_itemselector then
    modules.game_itemselector.show(self)
  end
end

function UIItem:onItemChange()
  local tooltip = nil
  local item = self:getItem()
  if item and item:getTooltip():len() > 0 then
    tooltip = item:getTooltip()
  end
  self:setTooltip(tooltip)
  if ItemsDatabase and ItemsDatabase.setRarityItem then
    local rarityItem = item
    if not rarityItem and self.getItemId then
      local itemId = tonumber(self:getItemId()) or 0
      if itemId > 0 then
        rarityItem = itemId
      end
    end
    ItemsDatabase.setRarityItem(self, rarityItem)
  end
end
