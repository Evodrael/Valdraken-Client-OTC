if not EventSchedule then
	EventSchedule = {}
	EventSchedule.__index = EventSchedule
end

EventSchedule.events = {}

local function convertStringToTime(date_string)
	if type(date_string) ~= 'string' then
		return nil
	end

	local year, month, day, hour, min, sec = date_string:match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
	if not year then
		return nil
	end

	-- Converte para timestamp usando os.time
	local timestamp = os.time({
		year = tonumber(year),
		month = tonumber(month),
		day = tonumber(day),
		hour = tonumber(hour),
		min = tonumber(min),
		sec = tonumber(sec)
	})

	return timestamp
end

local function normalizeEventTime(value)
	if type(value) == 'number' then
		return value
	end
	if type(value) == 'table' then
		return normalizeEventTime(value.date)
	end
	return convertStringToTime(value)
end

function EventSchedule:configureEvent(widget)
	local activesEvents = {}
	local upcomingEvents = {}
	local activeTooltip = ''
	local upcomingTooltip = ''
	local time = os.time()

	for _, event in ipairs(EventSchedule.events or {}) do
		local startdate = normalizeEventTime(event.startdate)
		local enddate = normalizeEventTime(event.enddate)

		if startdate and enddate and time >= startdate and time <= enddate then
			table.insert(activesEvents, event)
			if activeTooltip ~= '' then
				activeTooltip = activeTooltip .. '\n\n'
			end
			activeTooltip = activeTooltip .. event.name ..":\n"..string.todivide(event.description, 10)
		elseif startdate and time < startdate and time + (5*24*60*60) >= startdate then
			table.insert(upcomingEvents, event)
			if upcomingTooltip ~= '' then
				upcomingTooltip = upcomingTooltip .. '\n\n'
			end
			upcomingTooltip = upcomingTooltip .. event.name ..":\n"..string.todivide(event.description, 10)
		end
	end

	widget.panel1.activeEvent:destroyChildren()
	for _, data in pairs(activesEvents) do
		local ui = g_ui.createWidget('EventsScheduleLabel', widget.panel1.activeEvent)
		ui:setText(data.name)
		ui:setBackgroundColor(data.colorlight)
		ui:setTooltip(activeTooltip)
		-- evento ATIVO: abre o calendario no dia ativo (hoje, que esta dentro do periodo)
		ui.onClick = function() modules.game_schedule.toggle(os.time()) end
	end

	widget.panel2.upcomingEvent:destroyChildren()
	for _, data in pairs(upcomingEvents) do
		local ui = g_ui.createWidget('EventsScheduleLabel', widget.panel2.upcomingEvent)
		ui:setText(data.name)
		ui:setBackgroundColor(data.colordark)
		ui:setTooltip(upcomingTooltip)
		-- evento UPCOMING: abre exatamente no dia (startdate) do evento clicado
		local startTime = normalizeEventTime(data.startdate)
		ui.onClick = function() modules.game_schedule.toggle(startTime) end
	end
end


function getEventByDay(time)
	local activesEvents = {}
	local activeTooltip = ''
	if not time then
		return activesEvents, activeTooltip
	end

	-- time = o dia as 13:00 (makeCalendar). Comparamos por SOBREPOSICAO com o dia inteiro, nao so
	-- com o ponto 13:00 — senao eventos que comecam/terminam em outra hora "sumiam" do calendario.
	local dayStart = time - (13 * 3600)
	local dayEnd = dayStart + (24 * 3600) - 1

	for _, event in ipairs(EventSchedule.events) do
		local startdate = normalizeEventTime(event.startdate)
		local enddate = normalizeEventTime(event.enddate)

		if startdate and enddate and startdate <= dayEnd and enddate >= dayStart then
			table.insert(activesEvents, event)
			if activeTooltip ~= '' then
				activeTooltip = activeTooltip .. '\n\n'
			end
			activeTooltip = activeTooltip .. event.name ..":\n"..string.todivide(event.description, 10)
		end
	end

	return activesEvents, activeTooltip
end

-- Menor startdate entre os eventos (ativos ou futuros). Usado para abrir o calendario ja no mes
-- onde estao os eventos, em vez de sempre no mes atual (onde pode nao haver evento visivel).
function getEarliestEventTime()
	local earliest = nil
	for _, event in ipairs(EventSchedule.events or {}) do
		local startdate = normalizeEventTime(event.startdate)
		if startdate and (not earliest or startdate < earliest) then
			earliest = startdate
		end
	end
	return earliest
end
