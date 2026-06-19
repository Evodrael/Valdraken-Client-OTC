-- @docclass
UIButton = extends(UIWidget, "UIButton")

function UIButton.create()
  local button = UIButton.internalCreate()
  button:setFocusable(false)
  button:setClickSound(2774)
  return button
end

function UIButton:onMouseRelease(pos, button)
  return self:isPressed()
end

function UIButton:setButtonColor(value)
  if value == 'green' then
    self:setImageSource('/images/store/button_green')
  elseif value == 'red' then
    self:setImageSource('/images/store/button_red')
  else
    self:setImageSource('/images/store/button_blue')
  end
end
