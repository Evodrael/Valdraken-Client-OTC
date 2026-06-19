-- @docclass UIWidget

function UIWidget:setMargin(...)
  local params = {...}
  if #params == 1 then
    self:setMarginTop(params[1])
    self:setMarginRight(params[1])
    self:setMarginBottom(params[1])
    self:setMarginLeft(params[1])
  elseif #params == 2 then
    self:setMarginTop(params[1])
    self:setMarginRight(params[2])
    self:setMarginBottom(params[1])
    self:setMarginLeft(params[2])
  elseif #params == 4 then
    self:setMarginTop(params[1])
    self:setMarginRight(params[2])
    self:setMarginBottom(params[3])
    self:setMarginLeft(params[4])
  end
end

function UIWidget:isTextWraped()
  return self:isTextWrap()
end

function UIWidget:getWrappedLinesCount()
  local text = self.getDrawText and self:getDrawText() or self:getText()
  text = text or ""

  local lines = 1
  for _ in tostring(text):gmatch("\n") do
    lines = lines + 1
  end
  return lines
end

function UIWidget:constructEnviorementVariables()
  for _, child in ipairs(self:getChildren()) do
    local id = child:getId()
    if id and id ~= '' then
      self[id] = child
    end
    child:constructEnviorementVariables()
  end
end

local function htmlUnescape(text)
  text = text or ""
  text = text:gsub("&nbsp;", " ")
  text = text:gsub("&amp;", "&")
  text = text:gsub("&lt;", "<")
  text = text:gsub("&gt;", ">")
  text = text:gsub("&quot;", "\"")
  text = text:gsub("&#39;", "'")
  text = text:gsub("&#8226;", "-")
  text = text:gsub("&#(%d+);", "")
  return text
end

local function parseHtmlAttributes(tag)
  local attrs = {}
  for key, value in tag:gmatch('([%w_%-]+)%s*=%s*"(.-)"') do
    attrs[key] = value
  end
  for key, value in tag:gmatch("([%w_%-]+)%s*=%s*'(.-)'") do
    attrs[key] = value
  end
  for key, value in tag:gmatch("([%w_%-]+)%s*=%s*([^%s\"'>/]+)") do
    if attrs[key] == nil then
      attrs[key] = value
    end
  end
  return attrs
end

local function cleanHtmlText(text)
  text = htmlUnescape(text)
  text = text:gsub("</?i>", "")
  text = text:gsub("</?b>", "")
  text = text:gsub("<.->", "")
  return text
end

function UIWidget:setHTML(html)
  self:destroyChildren()

  if self.setText then
    self:setText("")
  end

  html = html or ""
  if html == "" then
    return
  end

  if self.isOnHtml and self:isOnHtml() and self.html then
    return self:html(html)
  end

  html = html:gsub("\r\n", "\n")
  html = html:gsub("<br%s*/?>", "\n")

  local parentWidth = self:getWidth()
  if parentWidth <= 0 then
    parentWidth = 260
  end

  local x = 0
  local y = 0
  local lineHeight = 13
  local lineGap = 5
  local imageTextGap = 4
  local childIndex = 0

  local function nextId()
    childIndex = childIndex + 1
    return "htmlElement_" .. childIndex
  end

  local function applyPosition(widget, x, top)
    widget:addAnchor(AnchorTop, "parent", AnchorTop)
    widget:addAnchor(AnchorLeft, "parent", AnchorLeft)
    widget:setMarginTop(top)
    widget:setMarginLeft(x)
  end

  local function finishLine(force)
    if not force and x == 0 then
      return
    end

    y = y + lineHeight + lineGap
    x = 0
    lineHeight = 13
  end

  local function wrapIfNeeded(width)
    if x > 0 and x + width > parentWidth then
      finishLine(true)
    end
  end

  local function addText(text)
    text = cleanHtmlText(text)
    if text == "" then
      return
    end

    for word in text:gmatch("%S+%s*") do
      local label = g_ui.createWidget("Label", self)
      label:setId(nextId())
      label:setText(word)
      label:setTextAutoResize(true)
      label:setPhantom(true)

      local size = label:getTextSize()
      local width = size and size.width or label:getWidth()
      local height = size and size.height or label:getHeight()

      wrapIfNeeded(width)
      applyPosition(label, x, y)

      x = x + width
      lineHeight = math.max(lineHeight, height)
    end
  end

  local function addImage(attrsText)
    local attrs = parseHtmlAttributes(attrsText)
    local width = tonumber(attrs.width) or 13
    local height = tonumber(attrs.height) or width

    wrapIfNeeded(width)

    local image = g_ui.createWidget("UIWidget", self)
    image:setId(nextId())
    image:setSize(width .. " " .. height)
    image:setPhantom(true)
    if attrs.src then
      image:setImageSource(attrs.src)
    end
    if attrs.clip then
      image:setImageClip(attrs.clip)
    end
    image:setImageWidth(width)
    image:setImageHeight(height)

    local offsetX, offsetY = 0, 0
    if attrs.offset then
      offsetX, offsetY = attrs.offset:match("(-?%d+)%s+(-?%d+)")
      offsetX = tonumber(offsetX) or 0
      offsetY = tonumber(offsetY) or 0
    end
    applyPosition(image, x + offsetX, y + offsetY)

    x = x + width + imageTextGap
    lineHeight = math.max(lineHeight, height + math.max(offsetY, 0))
  end

  for line in (html .. "\n"):gmatch("(.-)\n") do
    local cursor = 1

    while cursor <= #line do
      local imgStart, imgEnd, attrsText = line:find("<img%s+(.-)%s*/?>", cursor)
      local text = imgStart and line:sub(cursor, imgStart - 1) or line:sub(cursor)
      addText(text)

      if not imgStart then
        break
      end

      addImage(attrsText)
      cursor = imgEnd + 1
    end

    finishLine(true)
  end

  if y > 0 then
    self:setHeight(y)
  end
end

local copyToClipboardConfirmWindow = nil
local function showCopyToClipboardConfirmWindow(text)
  if copyToClipboardConfirmWindow then
    copyToClipboardConfirmWindow:destroy()
  end

  local confirm = function()
    g_window.setClipboardText(text)
   if copyToClipboardConfirmWindow then
      copyToClipboardConfirmWindow:destroy()
      copyToClipboardConfirmWindow = nil
    end
    return true
  end

  local deny = function()
    if copyToClipboardConfirmWindow then
      copyToClipboardConfirmWindow:destroy()
      copyToClipboardConfirmWindow = nil
    end
    return false
  end

  copyToClipboardConfirmWindow = displayGeneralBox('Link Copy Warning', tr("The text you are trying to copy seems to include a link. Please be very careful when following links sent to you\nby other players as they might be used to hack your account! If you are not sure if the link is safe, do not\ncontinue.\n\nIf you do not want to see this warning again, you can deactivate it in the Options menu.\n\nContinue?"),
    { { text=tr('Yes'), callback=confirm }, { text=tr('No'), callback=deny }
    }, confirm, deny)
end

function UIWidget:onCopyText(text)
  if m_settings.getOption('linkCopyWarning') and hasLink(text) then
    return showCopyToClipboardConfirmWindow(text)
  end
  g_window.setClipboardText(text)
  return true
end

function UIWidget:getEmptySlot(widget)
  local childsSize = 0
  for _, child in pairs(self:getChildren()) do
    if child:isVisible() and widget:getId() ~= child:getId() then
      childsSize = child:getHeight() + childsSize
    end
  end

  return self:getHeight() - childsSize
end

function UIWidget:getChildInPanel()
  local childsSize = 0
  for _, child in pairs(self:getChildren()) do
    if child:isVisible() then
      childsSize = 1 + childsSize
    end
  end

  return childsSize
end

function UIWidget:onClick(mousePos)
  if self and type(self.onClick) == "table" then
    for _, func in pairs(self.onClick) do
      if type(func) == "function" and func ~= UIWidget.onClick then
        func(self, mousePos)
      end
    end
  end

  -- Used to release the focus of the widget when clicking outside it
  local focusedWidgets = modules.game_interface.focusReason
  if not focusedWidgets or table.empty(focusedWidgets) then
    return true
  end

  local clickedWidget = rootWidget:recursiveGetChildByPos(mousePos, false)
  if not clickedWidget then
		return true
	end

  local ignorableWidgets = { "searchText", "amountText" }
  if table.contains(ignorableWidgets, clickedWidget:getId()) then
    return true
  end

  modules.game_npctrade.toggleNPCFocus(false)
  return true
end

function g_client.onReleaseFocusedWidgets()
  local focusedWidgets = modules.game_interface.focusReason
  if not focusedWidgets or table.empty(focusedWidgets) then
    return true
  end

  modules.game_interface.toggleInternalFocus()
end

function g_client.setInputLockWidget(widget)
  if widget ~= nil then
    g_mouse.clearGrabber()
  end
  if g_ui.getCustomInputWidget() then
    g_ui.setInputLockWidget(nil)
  end

  if widget and g_game.isOnline() then
    g_client.onReleaseFocusedWidgets()
  end

  g_ui.setInputLockWidget(widget)

  if widget then
    scheduleEvent(function() widget:focus() end, 50)
  elseif not widget and g_game.isOnline() then
    scheduleEvent(function()
      if g_game.isOnline() and rootWidget and rootWidget:getChildById("gameRootPanel") then
        rootWidget:getChildById("gameRootPanel"):focus()
      end
    end, 50)
  end
end

function UIWidget:stopGif()
  if self.gifEvent then
    removeEvent(self.gifEvent)
    self.gifEvent = nil
  end
end

function UIWidget:loadGif(file, frames, duration, size, pingPong)
  self:stopGif()
  self:setImageSource(file)

  local width = size and size.width or 0
  local height = size and size.height or 0
  if width <= 0 or height <= 0 or frames <= 0 then
    return
  end

  local frame = 0
  local direction = 1
  local function updateFrame()
    if self:isDestroyed() then
      self:stopGif()
      return
    end

    self:setImageClip(torect(string.format('%d 0 %d %d', frame * width, width, height)))

    if pingPong then
      frame = frame + direction
      if frame >= frames - 1 then
        frame = frames - 1
        direction = -1
      elseif frame <= 0 then
        frame = 0
        direction = 1
      end
    else
      frame = (frame + 1) % frames
    end
  end

  updateFrame()
  self.gifEvent = cycleEvent(updateFrame, duration)
end

function UIWidget:onStyleApply(styleName, styleNode)
  if g_tooltip then
    g_tooltip.onWidgetStyleApply(self, styleName, styleNode)
  end
  for name,value in pairs(styleNode) do
    if name == 'main-window-size' then
      self.main_window_size = tosize(value)
    elseif name == 'buttoncolor' and self.setButtonColor then
      addEvent(function()
        if not self:isDestroyed() then
          self:setButtonColor(value)
        end
      end)
    end
  end
end
