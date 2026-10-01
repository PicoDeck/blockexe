-- Host tests for highscores.lua. Run from the repo root: lua tests/highscores_test.lua
package.path = "./?.lua;./tests/?.lua;" .. package.path
local stub = require("stub")
local eq = stub.eq

-- A freshly loaded module over a fake whose save holds `saved`.
local function fresh(saved)
    local fake = stub.new()
    fake.saves.highscores = saved
    local hs = stub.fresh("highscores")
    hs.load()
    return hs, fake
end

local function scores(hs)
    local out = {}
    for i, e in ipairs(hs.entries()) do out[i] = e.name .. "=" .. e.score end
    return table.concat(out, ",")
end

local T = {}

function T.empty_table_qualifies_any_positive_score()
    local hs = fresh(nil)
    eq(hs.qualifies(1), 1)
    eq(hs.qualifies(0), nil)
    eq(hs.qualifies(-5), nil)
end

function T.qualifies_while_fewer_than_three()
    local hs = fresh({ entries = { { name = "A", score = 500 }, { name = "B", score = 300 } } })
    eq(hs.qualifies(10), 3)
    eq(hs.qualifies(400), 2)
    eq(hs.qualifies(900), 1)
end

function T.full_table_needs_to_beat_third()
    local hs = fresh({ entries = { { name = "A", score = 500 }, { name = "B", score = 300 },
                                   { name = "C", score = 100 } } })
    eq(hs.qualifies(100), nil)   -- a tie with 3rd doesn't beat it
    eq(hs.qualifies(101), 3)
    eq(hs.qualifies(300), 3)     -- a tie ranks below the existing score
    eq(hs.qualifies(301), 2)
end

function T.insert_keeps_order_and_drops_fourth()
    local hs = fresh(nil)
    eq(hs.insert("ann", 300), 1)
    eq(hs.insert("bob", 500), 1)
    eq(hs.insert("cat", 100), 3)
    eq(scores(hs), "BOB=500,ANN=300,CAT=100")
    eq(hs.insert("dan", 300), 3)  -- ties ANN, so goes below her; CAT drops out
    eq(scores(hs), "BOB=500,ANN=300,DAN=300")
end

function T.insert_refuses_non_qualifying_and_blank_names()
    local hs = fresh({ entries = { { name = "A", score = 500 }, { name = "B", score = 300 },
                                   { name = "C", score = 100 } } })
    eq(hs.insert("zed", 50), nil)
    eq(hs.insert("!!!", 900), nil)
    eq(scores(hs), "A=500,B=300,C=100")
end

function T.insert_saves_table_and_last_name()
    local hs, fake = fresh(nil)
    hs.insert("keith", 12400)
    local saved = fake.saves.highscores
    eq(saved.version, 1)
    eq(saved.last_name, "KEITH")
    eq(#saved.entries, 1)
    eq(saved.entries[1].name, "KEITH")
    eq(saved.entries[1].score, 12400)
    eq(hs.last_name(), "KEITH")
end

function T.saved_data_round_trips()
    local hs = fresh(nil)
    hs.insert("ann", 300)
    hs.insert("bob", 500)
    hs.load()
    eq(scores(hs), "BOB=500,ANN=300")
    eq(hs.last_name(), "BOB")
end

function T.last_name_empty_on_first_run_and_unchanged_without_insert()
    eq(fresh(nil).last_name(), "")
    local hs = fresh({ last_name = "alex", entries = {} })
    eq(hs.last_name(), "ALEX")
    hs.qualifies(999)
    eq(hs.last_name(), "ALEX")
end

function T.bad_data_loads_as_empty_or_skips_rows()
    eq(scores(fresh("nonsense")), "")
    eq(scores(fresh({ entries = "nope" })), "")
    eq(fresh({ last_name = 42 }).last_name(), "")
    local hs = fresh({ entries = {
        { name = "GOOD", score = 50 },
        { name = 7, score = 60 },          -- name not a string
        { name = "!!!", score = 70 },      -- cleans to nothing
        { name = "ZERO", score = 0 },
        { name = "NEG", score = -10 },
        { name = "FRAC", score = 12.5 },
        { name = "STR", score = "900" },
        "not a table",
        { name = "whole", score = 80.0 },  -- a whole float is fine
    } })
    eq(scores(hs), "WHOLE=80,GOOD=50")
end

function T.loading_more_than_three_keeps_the_top_three()
    local hs = fresh({ entries = { { name = "D", score = 10 }, { name = "A", score = 40 },
                                   { name = "C", score = 20 }, { name = "B", score = 30 } } })
    eq(scores(hs), "A=40,B=30,C=20")
end

function T.loaded_ties_keep_their_saved_order()
    local hs = fresh({ entries = { { name = "FIRST", score = 100 }, { name = "SECOND", score = 100 } } })
    eq(scores(hs), "FIRST=100,SECOND=100")
end

function T.clean_name_rules()
    local hs = fresh(nil)
    eq(hs.clean_name("keith"), "KEITH")
    eq(hs.clean_name("a_b!c"), "ABC")
    eq(hs.clean_name("  mr. x-1  "), "MR. X-1")
    eq(hs.clean_name("abcdefghijk"), "ABCDEFGH")
    eq(hs.clean_name("abcdefg hij"), "ABCDEFG")  -- the cap leaves a trailing space, which is trimmed
    eq(hs.clean_name(nil), "")
end

function T.normalize_char_rules()
    local hs = fresh(nil)
    eq(hs.normalize_char("a"), "A")
    eq(hs.normalize_char("Z"), "Z")
    eq(hs.normalize_char("7"), "7")
    eq(hs.normalize_char(" "), " ")
    eq(hs.normalize_char("-"), "-")
    eq(hs.normalize_char("."), ".")
    eq(hs.normalize_char("_"), nil)
    eq(hs.normalize_char("\n"), nil)
    eq(hs.normalize_char("\b"), nil)
    eq(hs.normalize_char("ab"), nil)
end

function T.insert_survives_a_failing_save()
    local hs, fake = fresh(nil)
    fake.save_set_error = "disk full"
    eq(hs.insert("ann", 100), 1)
    eq(scores(hs), "ANN=100")
    assert(fake.logs[1] and fake.logs[1]:find("disk full"), "the failure should be logged")
end

function T.load_survives_a_raising_get()
    local fake = stub.new()
    fake.save_get_error = "boom"
    local hs = stub.fresh("highscores")
    hs.load()
    eq(scores(hs), "")
end

stub.run(T)
