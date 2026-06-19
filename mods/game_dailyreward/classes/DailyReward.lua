DailyReward = {}
DailyReward.__index = DailyReward

DailyReward.freeRewards = {}
DailyReward.premiumRewards = {}
DailyReward.descriptions = {}

local rewardFreeBase = "Rewards for Free Account: %s"
local rewardPremiumBase = "Rewards for Premium Account: %s"
local potionList = "\nPick %d item from the list. Among \nother items it contains: %s"
local preyText = "<li>%dx Prey Wildcard</li>"
local boostText = "<li>%d minutes 50%% XP Boost</li>"

local function makeDailyRewardText(dailyReward)
  dailyReward = dailyReward or {}
  local text = ''
  if dailyReward.type == 1 then
    local ss = ''
    for i, items in pairs(dailyReward.items or {}) do
      if ss == '' then
        ss = '\n' .. items.name
      elseif i < 3 then
        ss = ss .. ', ' .. (i % 2 == 0 and '\n' or '') .. items.name
      else
        ss = ss .. '...'
        break
      end
    end

    return string.format(potionList, dailyReward.amount, ss)
  else
    if (tonumber(dailyReward.preyCount) or 0) > 0 then
      return string.format(preyText, dailyReward.preyCount)
    elseif (tonumber(dailyReward.xpboost) or 0) > 0 then
      return string.format(boostText, dailyReward.xpboost)
    end
  end
  return text
end

function DailyReward:onDailyReward(freeRewards, premiumRewards, descriptions )
    DailyReward.freeRewards = freeRewards or {}
    DailyReward.premiumRewards = premiumRewards or {}
    DailyReward.descriptions = descriptions or {}

    DailyReward:configureRewardDescriptions()
end

function DailyReward:configureRewardDescriptions()
    if not dailyRewardWindow or not dailyRewardWindow.miniWindowDailyReward or not dailyRewardWindow.miniWindowBonuses then
        return
    end

    for i = 0, 6 do
        local widget = dailyRewardWindow.miniWindowDailyReward.dailyReward:recursiveGetChildById("dailyButton_".. i)
        if widget then
            widget.freeRewards = DailyReward.freeRewards[i + 1] or {}
            widget.premiumRewards = DailyReward.premiumRewards[i + 1] or {}

            if widget.freeRewards.type == 1 then
                widget:setIcon("/images/dailyreward/icon-reward-pickitems")
            else
                if (tonumber(widget.freeRewards.preyCount) or 0) > 0 then
                    widget:setIcon("/images/dailyreward/icon-reward-fixeditems")
                elseif (tonumber(widget.freeRewards.xpboost) or 0) > 0 then
                    widget:setIcon("/images/dailyreward/icon-reward-xpboost")
                end
            end


            widget.onHoverChange =
            function(selfWidget, hovered)
                dailyRewardWindow.Description.tooltipTodo:setText("")
                dailyRewardWindow.Description.freeDesc.freeDescLabel:setText("")
                dailyRewardWindow.Description.freeDesc.freeDescLabel:setFormatedText("")
                dailyRewardWindow.Description.premDesc.premiumDescLabel:setText("")
                dailyRewardWindow.Description.premDesc.premiumDescLabel:setFormatedText("")
                if hovered then
                    dailyRewardWindow.Description.freeDesc.freeDescLabel:setFormatedText(string.format(rewardFreeBase, makeDailyRewardText(selfWidget.freeRewards)))
                    dailyRewardWindow.Description.premDesc.premiumDescLabel:setFormatedText(string.format(rewardPremiumBase, makeDailyRewardText(selfWidget.premiumRewards)))
                end
            end
        end
    end

    for i = 0, 5 do
        local widget = dailyRewardWindow.miniWindowBonuses.preyBonus:recursiveGetChildById("bonusStreak_".. i)
        if widget then
            widget.textTooltip = DailyReward.descriptions[i + 1]
            widget.onHoverChange =
            function(selfWidget, hovered)
                dailyRewardWindow.Description.tooltipTodo:setText("")
                dailyRewardWindow.Description.freeDesc.freeDescLabel:setText("")
                dailyRewardWindow.Description.premDesc.premiumDescLabel:setText("")
                dailyRewardWindow.Description.premDesc.premiumDescLabel:setFormatedText("")
                if hovered then
                    dailyRewardWindow.Description.tooltipTodo:setText(selfWidget.textTooltip)
                end
            end
        end
    end
end

function DailyReward:onOpenRewardWall(fromShrine, nextRewardTime, currentIndex, message, jokerToken, serverSave, dayStreakLevel)
end
