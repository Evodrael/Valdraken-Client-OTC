if not ImbuementSelection then
  ImbuementSelection = {
    pickItem = nil,
  }
end

ImbuementSelection.__index = ImbuementSelection

local self = ImbuementSelection
function ImbuementSelection.startUp()
  self.pickItem = g_ui.createWidget('UIWidget')
  self.pickItem:setVisible(true)
  self.pickItem:setFocusable(false)
  self.pickItem.onMouseRelease = self.onChooseItemMouseRelease
end

function ImbuementSelection:shutdown()
  if self.pickItem then
    self.pickItem:destroy()
    self.pickItem = nil
  end
end

function ImbuementSelection:selectItem()
  if not self.pickItem then
    self:startUp()
  end

  if g_ui.isMouseGrabbed() then return end
  g_mouse.updateGrabber(self.pickItem, 'target')
  self.pickItem:grabMouse()
  g_mouse.pushCursor('target')
end

function ImbuementSelection.onChooseItemMouseRelease(widget, mousePosition, mouseButton)
  local item = nil
  if mouseButton == MouseLeftButton then
    local clickedWidget = m_interface.getRootPanel():recursiveGetChildByPos(mousePosition, false)
    if clickedWidget then
      if clickedWidget:getClassName() == 'UIGameMap' then
        local tile = clickedWidget:getTile(mousePosition)
        if tile then
          local thing = tile:getTopMoveThing()
          if thing and thing:isItem() then
            item = thing
          end
        end
      elseif clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
        item = clickedWidget:getItem()
      end
    end
  end

  -- Reject items that are currently equipped on the character. The server
  -- expects the item to be in a container/floor and the imbuement flow needs
  -- to read its real position; equipped slots use x=0xFFFF and the server
  -- can't apply imbuements while the slot is in use. The player must
  -- unequip first.
  local function isEquippedSlot(it)
    if not it or not it.getPosition then return false end
    local pos = it:getPosition()
    if not pos then return false end
    if pos.x ~= 0xFFFF then return false end
    local slot = pos.y or 0
    return slot >= 1 and slot <= 10 -- Head .. Ammo
  end

  if item and isEquippedSlot(item) then
    modules.game_textmessage.displayFailureMessage(tr('Unequip the item before imbuing it.'))
  elseif item and item:isPickupable() then
    g_game.selectImbuementItem(item:getId(), item:getPosition(), item:getStackPos())
  else
    modules.game_textmessage.displayFailureMessage(tr('Sorry, not possible.'))
  end

  Imbuement:show()
  g_mouse.updateGrabber(self.pickItem, 'target')
  self.pickItem:ungrabMouse()
  g_mouse.popCursor('target')
  return true
end
