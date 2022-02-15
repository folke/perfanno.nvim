--- Generates tables of hottest / lines symbols for various occasions.

local callgraph = require("perfanno.callgraph")
local treesitter = require("perfanno.treesitter")
local config = require("perfanno.config")
local util = require("perfanno.util")

local M = {}

local function entry_from_line(cg, file, linenr)
    if file == "symbol" then
        return {
            symbol = linenr,
            file = nil,  -- TODO: maybe could have symbols with file but no line?
            linenr = nil,
            count = cg.node_info[file][linenr].count
        }
    else
        return {
            symbol = nil,  -- TODO: we might have this information
            file = file,
            linenr = linenr,
            count = cg.node_info[file][linenr].count
        }
    end
end

local function entry_from_symbol(cg, file, symbol)
    return {
        symbol = symbol,
        file = file,
        linenr = cg.symbols[file][symbol].min_line,
        count = cg.symbols[file][symbol].count
    }
end

function M.hottest_lines_table(event)
    local entries = {}
    local cg = callgraph.callgraphs[event]

    for file, file_tbl in pairs(cg.node_info) do
        for linenr, node_info in pairs(file_tbl) do
            if config.should_display(node_info.count, cg.total_count) then
                table.insert(entries, entry_from_line(cg, file, linenr))
            end
        end
    end

    table.sort(entries, function(e1, e2)
        return e1.count > e2.count
    end)

    return entries
end

function M.hottest_symbols_table(event)
    local entries = {}
    local cg = callgraph.callgraphs[event]

    for file, syms in pairs(cg.symbols) do
        for sym, info in pairs(syms) do
            if config.should_display(info.count, cg.total_count) then
                table.insert(entries, entry_from_symbol(cg, file, sym))
            end
        end
    end

    for sym, info in pairs(cg.node_info.symbol) do
        if config.should_display(info.count, cg.total_count) then
            table.insert(entries, entry_from_line(cg, "symbol", sym))
        end
    end

    table.sort(entries, function(e1, e2)
        return e1.count > e2.count
    end)

    return entries
end

local function hottest_callers_table(event, file, line_begin, line_end)
    local lines = {}
    local total_count = 0
    local cg = callgraph.callgraphs[event]

    for linenr, node_info in pairs(cg.node_info[file]) do
        if linenr >= line_begin and linenr <= line_end then
            table.insert(lines, {file, linenr})
            total_count = total_count + node_info.count
        end
    end

    local in_counts = callgraph.merge_in_counts(event, lines)
    local entries = {}

    for in_file, file_tbl in pairs(in_counts) do
        for in_line, count in pairs(file_tbl) do
            if config.format(count, total_count) then
                table.insert(entries, entry_from_line(cg, in_file, in_line))
            end
        end
    end

    table.sort(entries, function(e1, e2)
        return e1.count > e2.count
    end)

    return entries
end

local function current_canonical_file()
    local file = vim.fn.expand("%", ":p")
    return vim.loop.fs_realpath(file)
end

function M.hottest_callers_function_table(event)
    local file = current_canonical_file()

    if not file then
        vim.notify("Could not find current file!")
        return nil
    end

    local line_begin, line_end = treesitter.get_function_lines()

    if line_begin and line_end then
        return hottest_callers_table(event, file, line_begin, line_end)
    else
        vim.notify("Could not find surrounding function!")
    end
end

function M.hottest_callers_selection_table(event)
    local file = current_canonical_file()

    if not file then
        vim.notify("Could not find current file!")
        return nil
    end

    local line_begin, _, line_end, _ = util.visual_selection_range()

    if line_begin and line_end then
        return hottest_callers_table(event, file, line_begin, line_end)
    else
        vim.notify("Could not get visual selection!")
    end
end

local function go_to_entry(entry)
    if entry and entry.file and vim.fn.fileisreadable(entry.file) then
        -- Isn't there a way to do this via the lua API??
        if entry.linenr then
            vim.cmd(":edit +" .. entry.linenr .. " " .. vim.fn.fnameescape(entry.file))
        else
            vim.cmd(":edit " .. vim.fn.fnameescape(entry.file))
        end
    end
end

function M.format_entry(entry, total_count)
    local display = config.format(entry.count, total_count)

    if entry.file then
        local path = vim.fn.fnamemodify(entry.file, ":~:.")

        if entry.linenr then
            path = path .. ":" .. entry.linenr
        end

        if entry.symbol then
            display = display .. " " .. entry.symbol .. " at " .. path
        else
            display = display .. " " .. path
        end
    elseif entry.symbol then
        display = display .. " " .. entry.symbol
    else
        display = display .. " ??"
    end

    return display
end

local function find_hottest(event, prompt, table_fn)
    assert(callgraph.is_loaded(), "Callgraph is not loaded!")
    event = event or config.selected_event
    assert(callgraph.callgraphs[event], "Invalid event!")

    local entries = table_fn(event)

    local opts = {
        prompt = prompt,
        format_item = function(entry)
            M.format_entry(entry, callgraph.callgraphs[event].total_count)
        end,
        kind = "File"
    }

    vim.ui.select(entries, opts, go_to_entry)
end

function M.find_hottest_lines(event)
    find_hottest(event, "Hottest lines: ", M.hottest_lines_table)
end

function M.find_hottest_symbols(event)
    find_hottest(event, "Hottest symbols: ", M.hottest_symbols_table)
end

function M.find_hottest_callers_function(event)
    find_hottest(event, "Hottest callers: ", M.hottest_callers_function_table)
end

function M.find_hottest_callers_selection(event)
    find_hottest(event, "Hottest callers: ", M.hottest_callers_selection_table)
end

return M
