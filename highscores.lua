-- The top-3 high-score table with names, saved with pc.game.save.
local pc = picocalc

local M = {}

M.MAX_NAME = 8
local MAX_ENTRIES = 3
local SAVE_NAME = "highscores"

local entries = {}  -- { name, score }, highest first
local last = ""

-- The uppercase form of an allowed name character (A-Z 0-9 space - .), or nil.
function M.normalize_char(ch)
    if type(ch) ~= "string" or #ch ~= 1 then return nil end
    local up = ch:upper()
    if up:match("^[A-Z0-9 %-%.]$") then return up end
    return nil
end

-- Uppercases, drops disallowed characters, trims both ends and caps at 8.
function M.clean_name(s)
    if type(s) ~= "string" then return "" end
    local out = {}
    for i = 1, #s do
        out[#out + 1] = M.normalize_char(s:sub(i, i))
    end
    local name = table.concat(out):match("^%s*(.-)%s*$")
    return (name:sub(1, M.MAX_NAME):match("^(.-)%s*$"))
end

-- A whole number above 0 as an integer, or nil.
local function whole_positive(v)
    if type(v) ~= "number" then return nil end
    local i = math.tointeger(v)
    if i and i > 0 then return i end
    return nil
end

local function save()
    local list = {}
    for i, e in ipairs(entries) do list[i] = { name = e.name, score = e.score } end
    local ok, res, err = pcall(pc.game.save.set, SAVE_NAME,
        { version = 1, last_name = last, entries = list })
    if not ok then
        pc.sys.log("highscores: save failed: " .. tostring(res))
    elseif res == false then
        pc.sys.log("highscores: save failed: " .. tostring(err))
    end
end

function M.load()
    entries, last = {}, ""
    local ok, data = pcall(pc.game.save.get, SAVE_NAME)
    if not ok or type(data) ~= "table" then return end
    last = M.clean_name(data.last_name)
    if type(data.entries) ~= "table" then return end
    local list = {}
    for i, e in ipairs(data.entries) do
        if type(e) == "table" then
            local name, score = M.clean_name(e.name), whole_positive(e.score)
            if name ~= "" and score then
                list[#list + 1] = { name = name, score = score, order = i }
            end
        end
    end
    -- Highest first; equal scores keep their saved order.
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.order < b.order
    end)
    for i = 1, math.min(#list, MAX_ENTRIES) do
        entries[i] = { name = list[i].name, score = list[i].score }
    end
end

function M.entries()
    local out = {}
    for i, e in ipairs(entries) do out[i] = { name = e.name, score = e.score } end
    return out
end

function M.last_name() return last end

-- The rank (1-3) a score would take, or nil. A tie ranks below the saved score.
function M.qualifies(score)
    score = whole_positive(score)
    if not score then return nil end
    local rank = 1
    for _, e in ipairs(entries) do
        if e.score >= score then rank = rank + 1 end
    end
    if rank <= MAX_ENTRIES then return rank end
    return nil
end

function M.insert(name, score)
    local rank = M.qualifies(score)
    name = M.clean_name(name)
    if not rank or name == "" then return nil end
    table.insert(entries, rank, { name = name, score = whole_positive(score) })
    while #entries > MAX_ENTRIES do table.remove(entries) end
    last = name
    save()
    return rank
end

return M
