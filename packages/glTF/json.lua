--
-- json.lua
--
-- Copyright (c) 2018 rxi
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
--

local pairs = pairs
local type = type
local next = next
local error = error
local select = select
local tonumber = tonumber
local utf8_char = utf8.char
local table_concat = table.concat
local string_char = string.char
local math_type = math.type
local Inf = math.huge

local json = { _version = "0.1.1" }

json.null = function() end

-------------------------------------------------------------------------------
-- Encode
-------------------------------------------------------------------------------

local encode

local escape_char_map = {
  [ "\\" ] = "\\\\",
  [ "/" ]  = "\\/",
  [ "\"" ] = "\\\"",
  [ "\b" ] = "\\b",
  [ "\f" ] = "\\f",
  [ "\n" ] = "\\n",
  [ "\r" ] = "\\r",
  [ "\t" ] = "\\t",
}

local escape_char_map_inv = { [ "\\/" ] = "/" }
for k, v in pairs(escape_char_map) do
  escape_char_map_inv[v] = k
end


local function escape_char(c)
  return escape_char_map[c] or ("\\u%04x"):format(c:byte())
end


local function encode_nil()
  return "null"
end


local function encode_null(val)
  if val == json.null then
    return "null"
  end
  error "cannot serialise function: type not supported"
end

local function encode_table(val, stack)
  local res = {}
  stack = stack or {}

  -- Circular reference?
  if stack[val] then error("circular reference") end

  stack[val] = true

  if next(val) == nil then
    local meta = getmetatable(val)
    if meta and meta.__name == 'json.object' then
      return "{}"
    else
      return "[]"
    end
  elseif type(next(val)) == 'number' then
    -- Treat as array -- check keys are valid and it is not sparse
    local max = 0
    for k in pairs(val) do
      if math_type(k) ~= "integer" then
        error("invalid table: mixed or invalid key types")
      end
      max = max > k and max or k
    end
    for i = 1, max do
      res[#res+1] = encode(val[i], stack)
    end
    -- Encode
    stack[val] = nil
    return "[" .. table_concat(res, ",") .. "]"
  else
    -- Treat as an object
    for k, v in pairs(val) do
      if type(k) ~= "string" then
        error("invalid table: mixed or invalid key types")
      end
      res[#res+1] = encode(k, stack) .. ":" .. encode(v, stack)
    end
    stack[val] = nil
    return "{" .. table_concat(res, ",") .. "}"
  end
end


local function encode_string(val)
  return '"' .. val:gsub('[%z\1-\31\127\\"/]', escape_char) .. '"'
end


local function encode_number(val)
  -- Check for NaN, -inf and inf
  if val ~= val or val <= -Inf or val >= Inf then
    error("unexpected number value '" .. tostring(val) .. "'")
  end
  return ("%.17g"):format(val):gsub(',', '.')
end


local type_func_map = {
  [ "nil"     ] = encode_nil,
  [ "table"   ] = encode_table,
  [ "string"  ] = encode_string,
  [ "number"  ] = encode_number,
  [ "boolean" ] = tostring,
  [ "function" ] = encode_null,
}


encode = function(val, stack)
  local t = type(val)
  local f = type_func_map[t]
  if f then
    return f(val, stack)
  end
  error("unexpected type '" .. t .. "'")
end


function json.encode(val)
  return ( encode(val) )
end


-------------------------------------------------------------------------------
-- Decode
-------------------------------------------------------------------------------

local parse

local function create_set(...)
  local res = {}
  for i = 1, select("#", ...) do
    res[ select(i, ...) ] = true
  end
  return res
end

local space_chars   = create_set(" ", "\t", "\r", "\n")
local delim_chars   = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
local escape_chars  = create_set("\\", "/", '"', "b", "f", "n", "r", "t", "u")
local literals      = create_set("true", "false", "null")

local literal_map = {
  [ "true"  ] = true,
  [ "false" ] = false,
  [ "null"  ] = json.null,
}


local function next_char(str, idx, set, negate)
  for i = idx, #str do
    if set[str:sub(i, i)] ~= negate then
      return i
    end
  end
  return #str + 1
end


local function decode_error(str, idx, msg)
  local line_count = 1
  local col_count = 1
  for i = 1, idx - 1 do
    col_count = col_count + 1
    if str:sub(i, i) == "\n" then
      line_count = line_count + 1
      col_count = 1
    end
  end
  error( ("%s at line %d col %d"):format(msg, line_count, col_count) )
end


local function parse_unicode_escape(s)
  local n1 = tonumber( s:sub(3, 6),  16 )
  local n2 = tonumber( s:sub(9, 12), 16 )
  -- Surrogate pair?
  if n2 then
    return utf8_char((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000)
  else
    return utf8_char(n1)
  end
end


local function parse_string(str, i)
  local has_unicode_escape = false
  local has_surrogate_escape = false
  local has_escape = false
  local last
  for j = i + 1, #str do
    local x = str:byte(j)

    if x < 32 then
      decode_error(str, j, "control character in string")
    end

    if last == 92 then -- "\\" (escape char)
      if x == 117 then -- "u" (unicode escape sequence)
        local hex = str:sub(j + 1, j + 5)
        if not hex:find("%x%x%x%x") then
          decode_error(str, j, "invalid unicode escape in string")
        end
        if hex:find("^[dD][89aAbB]") then
          if not str:sub(j + 5, j + 10):match('\\u%x%x%x%x') then
            decode_error(str, j, "missing low surrogate")
          end
          has_surrogate_escape = true
        else
          has_unicode_escape = true
        end
      else
        local c = string_char(x)
        if not escape_chars[c] then
          decode_error(str, j, "invalid escape char '" .. c .. "' in string")
        end
        has_escape = true
      end
      last = nil

    elseif x == 34 then -- '"' (end of string)
      local s = str:sub(i + 1, j - 1)
      if has_surrogate_escape then
        s = s:gsub("\\u[dD][89aAbB]..\\u....", parse_unicode_escape)
      end
      if has_unicode_escape then
        s = s:gsub("\\u....", parse_unicode_escape)
      end
      if has_escape then
        s = s:gsub("\\.", escape_char_map_inv)
      end
      return s, j + 1

    else
      last = x
    end
  end
  decode_error(str, i, "expected closing quote for string")
end


local function parse_number(str, i)
  local x = next_char(str, i, delim_chars)
  local s = str:sub(i, x - 1)
  local n = tonumber(s)
  if not n or s:find '[^-+.%deE]' or s:match '^0[1-9]' then
    decode_error(str, i, "invalid number '" .. s .. "'")
  end
  return n, x
end


local function parse_literal(str, i)
  local x = next_char(str, i, delim_chars)
  local word = str:sub(i, x - 1)
  if not literals[word] then
    decode_error(str, i, "invalid literal '" .. word .. "'")
  end
  return literal_map[word], x
end


local function parse_array(str, i)
  local res = {}
  local n = 1
  i = i + 1
  while 1 do
    local x
    i = next_char(str, i, space_chars, true)
    -- Empty / end of array?
    if str:sub(i, i) == "]" then
      i = i + 1
      break
    end
    -- Read token
    x, i = parse(str, i)
    res[n] = x
    n = n + 1
    -- Next token
    i = next_char(str, i, space_chars, true)
    local chr = str:sub(i, i)
    i = i + 1
    if chr == "]" then break end
    if chr ~= "," then decode_error(str, i, "expected ']' or ','") end
  end
  return res, i
end


local function parse_object(str, i)
  local res = {}
  i = i + 1
  while 1 do
    local key, val
    i = next_char(str, i, space_chars, true)
    -- Empty / end of object?
    if str:sub(i, i) == "}" then
      i = i + 1
      break
    end
    -- Read key
    if str:sub(i, i) ~= '"' then
      decode_error(str, i, "expected string for key")
    end
    key, i = parse(str, i)
    -- Read ':' delimiter
    i = next_char(str, i, space_chars, true)
    if str:sub(i, i) ~= ":" then
      decode_error(str, i, "expected ':' after key")
    end
    i = next_char(str, i + 1, space_chars, true)
    -- Read value
    val, i = parse(str, i)
    -- Set
    res[key] = val
    -- Next token
    i = next_char(str, i, space_chars, true)
    local chr = str:sub(i, i)
    i = i + 1
    if chr == "}" then break end
    if chr ~= "," then decode_error(str, i, "expected '}' or ','") end
  end
  if next(res) == nil then
    setmetatable(res, {__name = 'json.object'})
  end
  return res, i
end


local char_func_map = {
  [ '"' ] = parse_string,
  [ "0" ] = parse_number,
  [ "1" ] = parse_number,
  [ "2" ] = parse_number,
  [ "3" ] = parse_number,
  [ "4" ] = parse_number,
  [ "5" ] = parse_number,
  [ "6" ] = parse_number,
  [ "7" ] = parse_number,
  [ "8" ] = parse_number,
  [ "9" ] = parse_number,
  [ "-" ] = parse_number,
  [ "t" ] = parse_literal,
  [ "f" ] = parse_literal,
  [ "n" ] = parse_literal,
  [ "[" ] = parse_array,
  [ "{" ] = parse_object,
}


parse = function(str, idx)
  local chr = str:sub(idx, idx)
  local f = char_func_map[chr]
  if f then
    return f(str, idx)
  end
  decode_error(str, idx, "unexpected character '" .. chr .. "'")
end


function json.decode(str)
  if type(str) ~= "string" then
    error("expected argument of type string, got " .. type(str))
  end
  local res, idx = parse(str, next_char(str, 1, space_chars, true))
  idx = next_char(str, idx, space_chars, true)
  if idx <= #str then
    decode_error(str, idx, "trailing garbage")
  end
  return res
end


return json
