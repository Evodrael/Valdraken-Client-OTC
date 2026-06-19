-- @docvars @{

-- root widget
rootWidget = g_ui.getRootWidget()
rootWidget:insertLuaCall("onGeometryChange")

-- G is used as a global table to save variables in memory between reloads
G = G or {}

-- @}

-- @docfuncs @{

function scheduleEvent(callback, delay, print)
  local desc = "lua"
  local info = debug.getinfo(2, "Sl")
  if info then
    desc = info.short_src .. ":" .. info.currentline
  end
  local event = g_dispatcher.scheduleEvent(desc, callback, delay, print)
  -- must hold a reference to the callback, otherwise it would be collected
  event._callback = callback
  return event
end

function addEvent(callback, front)
  local desc = "lua"
  local info = debug.getinfo(2, "Sl")
  if info then
    desc = info.short_src .. ":" .. info.currentline
  end
  local event = g_dispatcher.addEvent(desc, callback, front)
  -- must hold a reference to the callback, otherwise it would be collected
  event._callback = callback
  return event
end

function cycleEvent(callback, interval)
  local desc = "lua"
  local info = debug.getinfo(2, "Sl")
  if info then
    desc = info.short_src .. ":" .. info.currentline
  end
  local event = g_dispatcher.cycleEvent(desc, callback, interval)
  -- must hold a reference to the callback, otherwise it would be collected
  event._callback = callback
  return event
end

function periodicalEvent(eventFunc, conditionFunc, delay, autoRepeatDelay)
  delay = delay or 30
  autoRepeatDelay = autoRepeatDelay or delay

  local func
  func = function()
    if conditionFunc and not conditionFunc() then
      func = nil
      return
    end
    eventFunc()
    scheduleEvent(func, delay)
  end

  scheduleEvent(function()
    func()
  end, autoRepeatDelay)
end

function removeEvent(event)
  if event then
    event:cancel()
    event._callback = nil
  end
end

-- Stub: StaticText:addColoredMessage — concatenates highlighted segments and calls addMessage
function StaticText:addColoredMessage(name, mode, segments)
    local text = ""
    if type(segments) == "table" then
        for i = 1, #segments, 2 do
            if type(segments[i]) == "string" then
                text = text .. segments[i]
            end
        end
    else
        text = tostring(segments or "")
    end
    self:addMessage(name, mode, text)
end

-- @}