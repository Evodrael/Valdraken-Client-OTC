-- @docclass table

function table.dump(t, depth)
  if not depth then depth = 0 end
  for k,v in pairs(t) do
    str = (' '):rep(depth * 2) .. k .. ': '
    if type(v) ~= "table" then
      print(str .. tostring(v))
    else
      print(str)
      table.dump(v, depth+1)
    end
  end
end

function table.reserve(n, value)
  local t = {}
  for i = 1, n do
    t[i] = value
  end
  return t
end

function table.clear(t)
  for k,v in pairs(t) do
    t[k] = nil
  end
end

function table.copy(t)
  if type(t) ~= "table" then
    return t
  end
  local res = {}
  for k,v in pairs(t) do
    res[k] = v
  end
  return res
end

function table.recursivecopy(t)
  if type(t) ~= "table" then
    return t
  end
  local res = {}
  for k,v in pairs(t) do
    if type(v) == "table" then
      res[k] = table.recursivecopy(v)
    else
      res[k] = v
    end
  end
  return res
end

function table.selectivecopy(t, keys)
  local res = { }
  for i,v in ipairs(keys) do
    res[v] = t[v]
  end
  return res
end

function table.merge(t, src)
  for k,v in pairs(src) do
    t[k] = v
  end
end

function table.find(t, value, lowercase)
  for k,v in pairs(t) do
    if lowercase and type(value) == 'string' and type(v) == 'string' then
      if v:lower() == value:lower() then return k end
    end
    if v == value then return k end
  end
end

function table.findbykey(t, key, lowercase)
  for k,v in pairs(t) do
    if lowercase and type(key) == 'string' and type(k) == 'string' then
      if k:lower() == key:lower() then return v end
    end
    if k == key then return v end
  end
end

function table.contains(t, value, lowercase)
  return table.find(t, value, lowercase) ~= nil
end

function table.containkeys(t, keys)
  for i, key in ipairs(keys) do
    if table.find(t, key) ~= nil then
      return true
    end
  end
  return false
end


function table.isIn(t, str)
  for i, v in pairs(t) do
    if v == str then
      return true
    end
  end

  return false
end

function table.findkey(t, key)
  if t and type(t) == 'table' then
    for k,v in pairs(t) do
      if k == key then return k end
    end
  end
end

function table.haskey(t, key)
  return table.findkey(t, key) ~= nil
end

function table.removevalue(t, value)
  for k,v in pairs(t) do
    if v == value then
      table.remove(t, k)
      return true
    end
  end
  return false
end

function table.popvalue(t, value)
  local index = nil
  for k,v in pairs(t) do
    if v == value or not value then
      index = k
    end
  end
  if index then
    table.remove(t, index)
    return true
  end
  return false
end

function table.compare(t, other)
  if #t ~= #other then return false end
  for k,v in pairs(t) do
    if v ~= other[k] then return false end
  end
  return true
end

function table.empty(t)
  if t and type(t) == 'table' then
    return next(t) == nil
  end
  return true
end

function table.permute(t, n, count)
  n = n or #t
  for i=1,count or n do
    local j = math.random(i, n)
    t[i], t[j] = t[j], t[i]
  end
  return t
end

function table.findbyfield(t, fieldname, fieldvalue)
  for _i,subt in pairs(t) do
    if subt[fieldname] == fieldvalue then
      return subt
    end
  end
  return nil
end

function table.size(t)
  local size = 0
  for i, n in pairs(t) do
    size = size + 1
  end

  return size
end

function table.tostring(t)
  local maxn = #t
  local str = ""
  for k,v in pairs(t) do
    v = tostring(v)
    if k == maxn and k ~= 1 then
      str = str .. " and " .. v
    elseif maxn > 1 and k ~= 1 then
      str = str .. ", " .. v
    else
      str = str .. " " .. v
    end
  end
  return str
end

function table.collect(t, func)
  local res = {}
  for k,v in pairs(t) do
    local a,b = func(k,v)
    if a and b then
      res[a] = b
    elseif a ~= nil then
      table.insert(res,a)
    end
  end
  return res
end

function table.equals(t, comp)
  if type(t) == "table" and type(comp) == "table" then
    for k,v in pairs(t) do
      if v ~= comp[k] then return false end
    end
  end
  return true
end

function table.equal(t1,t2,ignore_mt)
   local ty1 = type(t1)
   local ty2 = type(t2)
   if ty1 ~= ty2 then return false end
   -- non-table types can be directly compared
   if ty1 ~= 'table' and ty2 ~= 'table' then return t1 == t2 end
   -- as well as tables which have the metamethod __eq
   local mt = getmetatable(t1)
   if not ignore_mt and mt and mt.__eq then return t1 == t2 end
   for k1,v1 in pairs(t1) do
      local v2 = t2[k1]
      if v2 == nil or not table.equal(v1,v2) then return false end
   end
   for k2,v2 in pairs(t2) do
      local v1 = t1[k2]
      if v1 == nil or not table.equal(v1,v2) then return false end
   end
   return true
end

function table.isList(t)
  local size = #t
  return table.size(t) == size and size > 0
end

function table.isStringList(t)
  if not table.isList(t) then return false end
  for k,v in ipairs(t) do
    if type(v) ~= 'string' then
      return false
    end
  end
  return true
end

function table.isStringPairList(t)
  if not table.isList(t) then return false end
  for k,v in ipairs(t) do
    if type(v) ~= 'table' or #v ~= 2 or type(v[1]) ~= 'string' or type(v[2]) ~= 'string' then
      return false
    end
  end
  return true
end

function table.encodeStringPairList(t)
  local ret = ""
  for k,v in ipairs(t) do
    if v[2]:find("\n") then
      ret = ret .. v[1] .. ":[[\n" .. v[2] .. "\n]]\n"
    else
      ret = ret .. v[1] .. ":" .. v[2] .. "\n"
    end
  end
  return ret
end

function table.decodeStringPairList(l)
  local ret = {}
  local r = regexMatch(l, "(?:^|\\n)([^:^\n]{1,20}):?(.*)(?:$|\\n)")
  local multiline = ""
  local multilineKey = ""
  local multilineActive = false
  for k,v in ipairs(r) do
    if multilineActive then
      local endPos = v[1]:find("%]%]")
      if endPos then
        if endPos > 1 then
          table.insert(ret, {multilineKey, multiline .. "\n" .. v[1]:sub(1, endPos - 1)})
        else
          table.insert(ret, {multilineKey, multiline})
        end
        multilineActive = false
        multiline = ""
        multilineKey = ""
      else
        if multiline:len() == 0 then
          multiline = v[1]
        else
          multiline = multiline .. "\n" .. v[1]
        end
      end
    else
      local bracketPos = v[3]:find("%[%[")
      if bracketPos == 1 then -- multiline begin
        multiline = v[3]:sub(bracketPos + 2)
        multilineActive = true
        multilineKey = v[2]
      elseif v[2]:len() > 0 and v[3]:len() > 0 then
        table.insert(ret, {v[2], v[3]})
      end
    end
  end
  return ret
end

function table.exists(t)
  return t ~= nil
end

function table.getindex(t, value)
  for i = 1, #t do
    if t[i] == value then
      return i
    end
  end

  return nil
end

function table.uniqueInsert(t, value)
    for _, v in ipairs(t) do
        if v == value then
            return false
        end
    end
    table.insert(t, value)
    return true
end

function table.obscure(value)
  local function manual_frexp(x)
    if x == 0 then
      return 0, 0
    end

    local e = math.floor(math.log(x, 2)) + 1
    local m = x / 2 ^ (e - 1)
    return m * 0.5, e
  end

  local function encode_double_le(num)
    if num ~= num then
      return string.char(0, 0, 0, 0, 0, 0, 0, 0xF8)
    end

    if num == math.huge then
      return string.char(0, 0, 0, 0, 0, 0, 0xF0, 0x7F)
    end

    if num == -math.huge then
      return string.char(0, 0, 0, 0, 0, 0, 0xF0, 0xFF)
    end

    local sign = 0
    if num < 0 or (num == 0 and 1/num < 0) then
      sign = 1
      num = -num
    end

    if num == 0 then
      return string.char(0, 0, 0, 0, 0, 0, 0, sign == 1 and 0x80 or 0x00)
    end

    local mantissa, exponent = manual_frexp(num)
    mantissa = mantissa * 2
    exponent = exponent - 1
    exponent = exponent + 1023
    if exponent <= 0 then
      exponent = 0
    elseif exponent >= 0x7FF then
      exponent = 0x7FF
      mantissa = 1
    end

    local mantInt = math.floor((mantissa - 1) * 2 ^ 52 + 0.5)
    local signBit = sign * 0x80
    local exponentHigh = math.floor(exponent / 16)
    local exponentLow = exponent % 16
    local mant48to51 = math.floor(mantInt / 2 ^ 48) % 16
    local b7 = signBit + exponentHigh
    local b6 = exponentLow * 16 + mant48to51
    local b5 = math.floor(mantInt / 2 ^ 40) % 256
    local b4 = math.floor(mantInt / 2 ^ 32) % 256
    local b3 = math.floor(mantInt / 2 ^ 24) % 256
    local b2 = math.floor(mantInt / 2 ^ 16) % 256
    local b1 = math.floor(mantInt / 2 ^ 8) % 256
    local b0 = mantInt % 256
    return string.char(b0, b1, b2, b3, b4, b5, b6, b7)
  end

  local function write_uint16(n)
    return string.char(n % 256, math.floor(n / 256) % 256)
  end

  local function write_uint32(n)
    return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
  end

  local function write_int64(n)
    if n < 0 then
      n = n + 2 ^ 63 * 2
    end

    local bytes = {}
    for i = 1, 8 do
      bytes[i] = string.char(n % 256)
      n = math.floor(n / 256)
    end

    return table.concat(bytes)
  end

  local function write_double(d)
    if string.pack then
      return string.pack('<d', d)
    else
      return encode_double_le(d)
    end
  end

  local function serialize_value(v, out)
    local tv = type(v)
    if v == nil then
      out[#out + 1] = string.char(0x01)
    elseif tv == 'boolean' then
      out[#out + 1] = string.char(v and 0x03 or 0x02)
    elseif tv == 'number' then
      if math.type and math.type(v) == 'integer' and v <= 0x7FFFFFFFFFFFFFFF and v >= -0x8000000000000000 then
        out[#out + 1] = string.char(0x04) .. write_int64(v)
      else
        out[#out + 1] = string.char(0x05) .. write_double(v)
      end
    elseif tv == 'string' then
      local len = #v
      if len <= 0xFFFF then
        out[#out + 1] = string.char(0x06) .. write_uint16(len) .. v
      else
        out[#out + 1] = string.char(0x07) .. write_uint32(len) .. v
      end
    elseif tv == 'table' then
      out[#out + 1] = string.char(0x08)
      for k, val in pairs(v) do
        serialize_value(k, out)
        serialize_value(val, out)
      end
      out[#out + 1] = string.char(0x00)
    else
      error('Unsupported type for obscure: ' .. tv)
    end
  end

  local out = {}
  serialize_value(value, out)
  local rawBytes = table.concat(out)
  local shifted = {}
  for i = 1, #rawBytes do
    local b = rawBytes:byte(i)
    shifted[i] = string.format('%02X', (b + (i * 7 + 13)) % 256)
  end

  return 'O1' .. table.concat(shifted)
end

function table.unobscure(value)
  if type(value) ~= 'string' or not value:find('^O1') then
    return nil
  end

  local hex = value:sub(3)
  if #hex % 2 ~= 0 then
    return nil
  end

  local bytes = {}
  local blen = #hex / 2
  for i = 0, blen - 1 do
    local byteHex = hex:sub(i * 2 + 1, i * 2 + 2)
    local b = tonumber(byteHex, 16)
    if not b then
      return nil
    end

    local idx = i + 1
    local offset = (idx * 7 + 13) % 256
    bytes[idx] = string.char((b - offset) % 256)
  end

  local data = table.concat(bytes)
  local pos = 1

  local function read(n)
    local chunk = data:sub(pos, pos + n - 1)
    if #chunk < n then
      error('Truncated')
    end

    pos = pos + n
    return chunk
  end

  local function read_uint16()
    local c = read(2)
    return c:byte(1) + c:byte(2) * 256
  end

  local function read_uint32()
    local c = read(4)
    return c:byte(1) + c:byte(2) * 256 + c:byte(3) * 65536 + c:byte(4) * 16777216
  end

  local function read_int64()
    local c = read(8)
    local n = 0
    local mul = 1

    for i = 1, 8 do
      n = n + c:byte(i) * mul
      mul = mul * 256
    end

    if n >= 2 ^ 63 then
      n = n - 2 ^ 64
    end

    return n
  end

  local function decode_double_le(str)
    local b0, b1, b2, b3, b4, b5, b6, b7 = str:byte(1, 8)
    local sign = math.floor(b7 / 0x80)
    local exponentHigh = b7 % 0x80
    local exponentLow = math.floor(b6 / 16)
    local exponent = exponentHigh * 16 + exponentLow
    local mantHigh = b6 % 16
    local mantissa = mantHigh
    mantissa = mantissa * 256 + b5
    mantissa = mantissa * 256 + b4
    mantissa = mantissa * 256 + b3
    mantissa = mantissa * 256 + b2
    mantissa = mantissa * 256 + b1
    mantissa = mantissa * 256 + b0

    if exponent == 0x7FF then
      if mantissa == 0 then
        return sign == 1 and -math.huge or math.huge
      else
        return 0/0
      end
    end

    local m
    if exponent == 0 then
      if mantissa == 0 then
        m = 0
      else
        m = mantissa / 2 ^ 52
        exponent = 1
      end
    else
      m = 1 + mantissa / 2 ^ 52
    end

    local val = m * 2 ^ (exponent - 1023)
    if sign == 1 then
      val = -val
    end

    return val
  end

  local function read_double()
    if string.unpack then
      local v
      v, pos = string.unpack('<d', data, pos)
      return v
    else
      return decode_double_le(read(8))
    end
  end

  local function parse_value()
    local tag = data:byte(pos)
    pos = pos + 1
    if not tag then
      error('Unexpected end')
    end

    if tag == 0x01 then
      return nil
    elseif tag == 0x02 then
      return false
    elseif tag == 0x03 then
      return true
    elseif tag == 0x04 then
      return read_int64()
    elseif tag == 0x05 then
      return read_double()
    elseif tag == 0x06 then
      return read(read_uint16())
    elseif tag == 0x07 then
      return read(read_uint32())
    elseif tag == 0x08 then
      local tbl = {}
      while true do
        local nextTag = data:byte(pos)
        if not nextTag then
          error('Unterminated table')
        end

        if nextTag == 0x00 then
          pos = pos + 1
          break
        end

        local key = parse_value()
        local val = parse_value()
        tbl[key] = val
      end

      return tbl
    elseif tag == 0x00 then
      error('Unexpected terminator')
    else
      error('Unknown tag: ' .. tag)
    end
  end

  local ok, result = pcall(parse_value)
  return ok and result or nil
end
