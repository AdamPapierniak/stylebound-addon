-- SBJSON: Minimal JSON encoder/decoder for StyleBound
-- MIT License

local MAJOR, MINOR = "SBJSON", 1
local LibJSON = LibStub:NewLibrary(MAJOR, MINOR)
if not LibJSON then return end

-- Encode a Lua value to a JSON string
function LibJSON.Encode(val)
    local t = type(val)
    if val == nil then
        return "null"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        if val ~= val then return "null" end -- NaN
        if val == math.huge or val == -math.huge then return "null" end
        return tostring(val)
    elseif t == "string" then
        return LibJSON._EncodeString(val)
    elseif t == "table" then
        -- Detect array vs object
        local maxn = 0
        local count = 0
        for k in pairs(val) do
            count = count + 1
            if type(k) == "number" and k > 0 and math.floor(k) == k then
                if k > maxn then maxn = k end
            end
        end
        if maxn == count and count > 0 then
            return LibJSON._EncodeArray(val, maxn)
        else
            return LibJSON._EncodeObject(val)
        end
    end
    return "null"
end

function LibJSON._EncodeString(s)
    local replacements = {
        ["\\"] = "\\\\", ["\""] = "\\\"", ["\n"] = "\\n",
        ["\r"] = "\\r", ["\t"] = "\\t", ["\b"] = "\\b", ["\f"] = "\\f",
    }
    s = s:gsub('[\\"%c]', function(c)
        return replacements[c] or string.format("\\u%04x", c:byte())
    end)
    return '"' .. s .. '"'
end

function LibJSON._EncodeArray(arr, n)
    local parts = {}
    for i = 1, n do
        parts[i] = LibJSON.Encode(arr[i])
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

function LibJSON._EncodeObject(obj)
    local parts = {}
    for k, v in pairs(obj) do
        if type(k) == "string" or type(k) == "number" then
            parts[#parts + 1] = LibJSON._EncodeString(tostring(k)) .. ":" .. LibJSON.Encode(v)
        end
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- Decode a JSON string to a Lua value
function LibJSON.Decode(str)
    if type(str) ~= "string" then return nil end
    local pos = 1

    local function skipWhitespace()
        pos = str:find("[^ \t\r\n]", pos) or (#str + 1)
    end

    local function peek()
        skipWhitespace()
        return str:sub(pos, pos)
    end

    local parseValue -- forward declaration

    local function parseString()
        pos = pos + 1 -- skip opening quote
        local start = pos
        local result = {}
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == '"' then
                pos = pos + 1
                return table.concat(result)
            elseif c == '\\' then
                pos = pos + 1
                local esc = str:sub(pos, pos)
                if esc == 'n' then result[#result + 1] = '\n'
                elseif esc == 'r' then result[#result + 1] = '\r'
                elseif esc == 't' then result[#result + 1] = '\t'
                elseif esc == 'b' then result[#result + 1] = '\b'
                elseif esc == 'f' then result[#result + 1] = '\f'
                elseif esc == 'u' then
                    local hex = str:sub(pos + 1, pos + 4)
                    local code = tonumber(hex, 16)
                    if code and code < 128 then
                        result[#result + 1] = string.char(code)
                    else
                        result[#result + 1] = '?'
                    end
                    pos = pos + 4
                else
                    result[#result + 1] = esc
                end
            else
                result[#result + 1] = c
            end
            pos = pos + 1
        end
        return table.concat(result)
    end

    local function parseNumber()
        local startPos = pos
        if str:sub(pos, pos) == '-' then pos = pos + 1 end
        while pos <= #str and str:sub(pos, pos):match("[%d%.eE%+%-]") do
            pos = pos + 1
        end
        return tonumber(str:sub(startPos, pos - 1))
    end

    local function parseArray()
        pos = pos + 1 -- skip [
        local arr = {}
        if peek() == ']' then pos = pos + 1; return arr end
        while true do
            arr[#arr + 1] = parseValue()
            skipWhitespace()
            local c = str:sub(pos, pos)
            if c == ']' then pos = pos + 1; return arr end
            if c == ',' then pos = pos + 1 end
        end
    end

    local function parseObject()
        pos = pos + 1 -- skip {
        local obj = {}
        if peek() == '}' then pos = pos + 1; return obj end
        while true do
            skipWhitespace()
            local key = parseString()
            skipWhitespace()
            pos = pos + 1 -- skip :
            obj[key] = parseValue()
            skipWhitespace()
            local c = str:sub(pos, pos)
            if c == '}' then pos = pos + 1; return obj end
            if c == ',' then pos = pos + 1 end
        end
    end

    parseValue = function()
        local c = peek()
        if c == '"' then return parseString()
        elseif c == '{' then return parseObject()
        elseif c == '[' then return parseArray()
        elseif c == 't' then pos = pos + 4; return true
        elseif c == 'f' then pos = pos + 5; return false
        elseif c == 'n' then pos = pos + 4; return nil
        else return parseNumber()
        end
    end

    return parseValue()
end
