local differ = require("neogram.diff")
local log = require("neogram.log")
local status = require("neogram.status")
local text_prompt = require("neogram.text_prompt")
local tpl_grammar = require("neogram.templates.grammar")
local tpl_interact = require("neogram.templates.interact_with_content")
local tpl_language = require("neogram.templates.recognize_language")

local M = { all_diff_info = {} }

local function apply_visual_effects(info, inlay)
  info.hl_id = M.buffer_helper.add_hl_group(info)
  if inlay or info.inlay_id then
    info.inlay_id = M.buffer_helper.add_inlay(info)
  end
end

local function delete_visual_effects(info)
  M.buffer_helper.delete_hl_group(info.buf_nr, info.hl_id)

  if info.inlay_id then
    M.buffer_helper.delete_inlay(info.buf_nr, info.inlay_id)
  end
end

local function delete_suggestions()
  local buf_nr = M.buffer_helper.current_buffer_nr()
  for _, info in ipairs(M.all_diff_info) do
    if info.buf_nr == buf_nr then
      delete_visual_effects(info)
    end
  end

  for i = #M.all_diff_info, 1, -1 do
    if M.all_diff_info[i].buf_nr == buf_nr then
      table.remove(M.all_diff_info, i)
    end
  end
end

local function pos_le(a_line, a_col, b_line, b_col)
  return a_line < b_line or (a_line == b_line and a_col <= b_col)
end

local function make_byte_to_pos(lines, start_line, start_col)
  local line_infos = {}
  local byte_cursor = 0
  for i, line_text in ipairs(lines) do
    local col_in_buf = (i == 1) and start_col or 0
    table.insert(line_infos, {
      line_nr = start_line + i - 1,
      col_in_buf = col_in_buf,
      byte_start = byte_cursor,
      byte_end = byte_cursor + #line_text,
    })
    byte_cursor = byte_cursor + #line_text + 1
  end

  return function(byte_offset)
    for _, li in ipairs(line_infos) do
      if byte_offset <= li.byte_end then
        return li.line_nr, li.col_in_buf + (byte_offset - li.byte_start)
      end
    end
    local last = line_infos[#line_infos]
    return last.line_nr, last.col_in_buf + (last.byte_end - last.byte_start)
  end
end

local function create_diff_info(buf_line_text, col_start, col_end, alt_text, inlay)
  if col_end == col_start then
    return nil
  end

  local info = {
    buf_nr = buf_line_text.buf_nr,
    hl_group = buf_line_text.hl_group,
    alt_text = alt_text,
  }

  if buf_line_text.byte_to_pos then
    local s_line, s_col = buf_line_text.byte_to_pos(col_start)
    local e_line, e_col = buf_line_text.byte_to_pos(col_end)
    info.line_nr = s_line
    info.col_start = s_col
    info.end_line_nr = e_line
    info.col_end = e_col
  else
    local offset = buf_line_text.col_offset or 0
    info.line_nr = buf_line_text.line_nr
    info.col_start = col_start + offset
    info.col_end = col_end + offset
  end

  apply_visual_effects(info, inlay)

  return info
end

local function apply_diff_effects(buf_line_text_a, buf_line_text_b, inlay)
  log.trace("apply_diff_hl_groups a=%s", buf_line_text_a)
  log.trace("apply_diff_hl_groups b=%s", buf_line_text_b)

  local diff_info = {}
  local locations = differ.diff(buf_line_text_a.text, buf_line_text_b.text)

  for _, loc in ipairs(locations) do
    log.trace("diff info: %s", loc)

    local info_a = create_diff_info(buf_line_text_a, loc.a_start, loc.a_end, loc.b_text, inlay)
    if info_a then
      table.insert(diff_info, info_a)
    end

    if buf_line_text_b.buf_nr then
      local info_b = create_diff_info(buf_line_text_b, loc.b_start, loc.b_end, loc.a_text)
      if info_b then
        table.insert(diff_info, info_b)
      end
    end
  end

  return diff_info
end

local function exit_visual_mode()
  local mode = vim.api.nvim_get_mode().mode
  if mode:match("^[vV\22]") then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
  end
end

local function is_blank_line(buf, line_nr_1)
  local text = vim.api.nvim_buf_get_lines(buf, line_nr_1 - 1, line_nr_1, false)[1]
  return text == nil or text:match("^%s*$") ~= nil
end

local function current_paragraph()
  local buf = 0
  local cursor_line = vim.fn.line(".")
  if is_blank_line(buf, cursor_line) then
    return nil
  end

  local total_lines = vim.api.nvim_buf_line_count(buf)
  local start_line = cursor_line
  while start_line > 1 and not is_blank_line(buf, start_line - 1) do
    start_line = start_line - 1
  end
  local end_line = cursor_line
  while end_line < total_lines and not is_blank_line(buf, end_line + 1) do
    end_line = end_line + 1
  end

  local lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
  return {
    text = table.concat(lines, "\n"),
    lines = lines,
    start_line = start_line,
    start_col = 0,
  }
end

local function get_text_context()
  local sel = M.buffer_helper.visual_selection_info()
  if sel then
    exit_visual_mode()
    return {
      text = sel.text,
      lines = sel.lines,
      start_line = sel.start_line,
      start_col = sel.start_col,
    }
  end
  local paragraph = current_paragraph()
  if paragraph then
    return paragraph
  end
  local line_nr = M.buffer_helper.current_line_nr()
  local text = M.buffer_helper.text_under_cursor()
  return {
    text = text,
    lines = { text },
    start_line = line_nr,
    start_col = 0,
  }
end

local function source_buf_line_text(ctx, buf_nr, hl_group)
  return {
    hl_group = hl_group,
    buf_nr = buf_nr,
    line_nr = ctx.start_line,
    text = ctx.text,
    byte_to_pos = make_byte_to_pos(ctx.lines, ctx.start_line, ctx.start_col),
  }
end

local function grammar_scratch_buf(inlay)
  local buf_nr = M.buffer_helper.current_buffer_nr()
  local ctx = get_text_context()

  log.fmt_trace("ai_improve_grammar. buf_nr=%s, start_line=%s, text=%s", buf_nr, ctx.start_line, ctx.text)

  local ui_select = text_prompt.process_buf_text()
  local callback = function(scratch_buf, ai_text)
    status.finish()
    log.fmt_trace("ai_improve_grammar-callback scratch_buf=%s, ai_text=%s", scratch_buf, ai_text)
    local ai_lines = vim.split(ai_text, "\n", { plain = true })
    M.all_diff_info = apply_diff_effects(
      source_buf_line_text(ctx, buf_nr, "NeogramIssue"),
      {
        hl_group = "NeogramImprovement",
        buf_nr = scratch_buf,
        line_nr = 1,
        text = ai_text,
        byte_to_pos = make_byte_to_pos(ai_lines, 1, 0),
      },
      inlay
    )

    ui_select()
  end

  delete_suggestions()
  local token = status.start()
  local template = M.template_fn("grammar", tpl_grammar, { ctx.text })
  M.template_sender.stream(M.adapter_model["grammar"], template, ctx.text, function(scratch_buf, ai_text)
    if not status.is_current(token) then
      return
    end
    callback(scratch_buf, ai_text)
  end, "Grammar Suggestions")
end

local function grammar_inline(inlay, ctx)
  local buf_nr = M.buffer_helper.current_buffer_nr()
  ctx = ctx or get_text_context()

  local token = status.start()
  local template = M.template_fn("grammar", tpl_grammar, { ctx.text })
  M.template_sender.send(M.adapter_model["grammar"], template, ctx.text, function(ai_text)
    if not status.is_current(token) then
      return
    end
    status.finish()

    if not ai_text then
      return
    end

    if ctx.text == ai_text then
      vim.notify("Great sentence. No improvements found.", vim.log.levels.INFO)
      return
    end

    delete_suggestions()
    M.all_diff_info = apply_diff_effects(
      source_buf_line_text(ctx, buf_nr, "NeogramIssue"),
      { text = ai_text },
      inlay
    )
  end)
end

M.setup = function(buffer_helper, template_sender, adapter_model, template_fn)
  M.buffer_helper = buffer_helper
  M.template_sender = template_sender
  M.adapter_model = adapter_model
  M.template_fn = template_fn

  log.fmt_trace("commands.setup. adapter_model=%s", adapter_model)

  vim.api.nvim_create_autocmd("InsertEnter", { callback = delete_suggestions })
end

M.grammar = function(opts)
  local scratch = opts.fargs[1] == "scratch" or opts.fargs[2] == "scratch"
  local inlay = opts.fargs[1] == "inlay" or opts.fargs[2] == "inlay"

  if
    (#opts.fargs == 1 and not scratch and not inlay)
    or (#opts.fargs == 2 and not (scratch and inlay))
    or #opts.fargs > 2
  then
    return error("wrong arguments supplied")
  end

  if scratch then
    grammar_scratch_buf(inlay)
  else
    grammar_inline(inlay)
  end
end

local function info_contains_pos(info, line_nr, col_nr)
  local end_line_nr = info.end_line_nr or info.line_nr
  return pos_le(info.line_nr, info.col_start, line_nr, col_nr)
    and pos_le(line_nr, col_nr, end_line_nr, info.col_end)
end

M.hover = function()
  local buf_nr = M.buffer_helper.current_buffer_nr()
  local line_nr = M.buffer_helper.current_line_nr()
  local col_nr = M.buffer_helper.current_column_nr()
  for _, info in ipairs(M.all_diff_info) do
    if info.buf_nr == buf_nr and info_contains_pos(info, line_nr, col_nr) then
      local hover_text = (info.alt_text == "") and "[REMOVE]" or info.alt_text
      M.buffer_helper.show_hover(hover_text)
      return
    end
  end
end

M.apply_suggestion = function()
  local buf_nr = M.buffer_helper.current_buffer_nr()
  local line_nr = M.buffer_helper.current_line_nr()
  local col_nr = M.buffer_helper.current_column_nr()

  local applied_index = 0
  for i, info in ipairs(M.all_diff_info) do
    if info.buf_nr == buf_nr and info_contains_pos(info, line_nr, col_nr) then
      applied_index = i
      break
    end
  end

  if applied_index == 0 then
    return
  end

  local applied = M.all_diff_info[applied_index]
  local applied_end_line = applied.end_line_nr or applied.line_nr
  local is_multiline = applied.line_nr ~= applied_end_line or applied.alt_text:find("\n")

  M.buffer_helper.replace_text(
    buf_nr,
    applied.line_nr,
    applied.col_start,
    applied_end_line,
    applied.col_end,
    applied.alt_text
  )
  delete_visual_effects(applied)

  if is_multiline then
    for i = #M.all_diff_info, 1, -1 do
      local info = M.all_diff_info[i]
      if i == applied_index then
        table.remove(M.all_diff_info, i)
      elseif info.buf_nr == buf_nr then
        delete_visual_effects(info)
        table.remove(M.all_diff_info, i)
      end
    end
    return
  end

  local length_diff = applied.col_end - applied.col_start - #applied.alt_text
  if length_diff ~= 0 then
    for j = applied_index + 1, #M.all_diff_info do
      local info = M.all_diff_info[j]
      if info.buf_nr == buf_nr and info.line_nr == applied.line_nr then
        delete_visual_effects(info)
        info.col_start = info.col_start - length_diff
        info.col_end = info.col_end - length_diff
        apply_visual_effects(info)
      end
    end
  end
  table.remove(M.all_diff_info, applied_index)
end

local function find_cursor_suggestion()
  local buf_nr = M.buffer_helper.current_buffer_nr()
  local line_nr = M.buffer_helper.current_line_nr()
  local col_nr = M.buffer_helper.current_column_nr()
  for _, info in ipairs(M.all_diff_info) do
    if info.buf_nr == buf_nr and info_contains_pos(info, line_nr, col_nr) then
      return info
    end
  end
  return nil
end

local function move_to_suggestion(backward)
  local buf_nr = M.buffer_helper.current_buffer_nr()
  local line_nr = M.buffer_helper.current_line_nr()
  local col_nr_0 = M.buffer_helper.current_column_nr() - 1

  local best = nil
  for _, info in ipairs(M.all_diff_info) do
    if info.buf_nr == buf_nr then
      local info_end_line = info.end_line_nr or info.line_nr
      local is_candidate, is_better
      if backward then
        is_candidate = info_end_line < line_nr
          or (info_end_line == line_nr and info.col_end < col_nr_0)
        is_better = best == nil
          or info.line_nr > best.line_nr
          or (info.line_nr == best.line_nr and info.col_start > best.col_start)
      else
        is_candidate = info.line_nr > line_nr
          or (info.line_nr == line_nr and info.col_start > col_nr_0)
        is_better = best == nil
          or info.line_nr < best.line_nr
          or (info.line_nr == best.line_nr and info.col_start < best.col_start)
      end
      if is_candidate and is_better then
        best = info
      end
    end
  end

  if best then
    vim.api.nvim_win_set_cursor(0, { best.line_nr, best.col_start })
  else
    vim.notify("No more suggestions.", vim.log.levels.INFO)
  end
end

M.cancel = function()
  if not status.active then
    return false
  end
  status.cancel()
  vim.notify("Neogram: grammar check canceled", vim.log.levels.INFO)
  return true
end

M.has_suggestions_in_buffer = function()
  local buf_nr = M.buffer_helper.current_buffer_nr()
  for _, info in ipairs(M.all_diff_info) do
    if info.buf_nr == buf_nr then
      return true
    end
  end
  return false
end

-- True if cursor is on a suggestion, or there is one in the requested direction.
M.has_suggestion_nearby = function(forward)
  local buf_nr = M.buffer_helper.current_buffer_nr()
  local line_nr = M.buffer_helper.current_line_nr()
  local col_nr = M.buffer_helper.current_column_nr()
  local col_nr_0 = col_nr - 1
  for _, info in ipairs(M.all_diff_info) do
    if info.buf_nr == buf_nr then
      if info_contains_pos(info, line_nr, col_nr) then
        return true
      end
      if forward then
        if
          info.line_nr > line_nr
          or (info.line_nr == line_nr and info.col_start > col_nr_0)
        then
          return true
        end
      else
        local info_end_line = info.end_line_nr or info.line_nr
        if
          info_end_line < line_nr
          or (info_end_line == line_nr and info.col_end < col_nr_0)
        then
          return true
        end
      end
    end
  end
  return false
end

M.grammar_inline_lines = function(start_line, end_line, inlay)
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  grammar_inline(inlay == true, {
    text = table.concat(lines, "\n"),
    lines = lines,
    start_line = start_line,
    start_col = 0,
  })
end

M.apply_next = function()
  if find_cursor_suggestion() then
    M.apply_suggestion()
  end
  move_to_suggestion(false)
end

M.apply_prev = function()
  if find_cursor_suggestion() then
    M.apply_suggestion()
  end
  move_to_suggestion(true)
end

M.reject_suggestion = function()
  local buf_nr = M.buffer_helper.current_buffer_nr()
  local line_nr = M.buffer_helper.current_line_nr()
  local col_nr = M.buffer_helper.current_column_nr()
  for i, info in ipairs(M.all_diff_info) do
    if info.buf_nr == buf_nr and info_contains_pos(info, line_nr, col_nr) then
      delete_visual_effects(info)
      table.remove(M.all_diff_info, i)
      return true
    end
  end
  return false
end

M.set_spelllang = function()
  local text_under_cursor = M.buffer_helper.text_under_cursor()
  local template = M.template_fn("set_spelllang", tpl_language, text_under_cursor)
  vim.notify("Detecting language...", vim.log.levels.INFO)
  vim.cmd("redraw")
  local code = M.template_sender.send(M.adapter_model["set_spelllang"], template, text_under_cursor)
  if code then
    log.fmt_info("setting spelllang to: %s", code)
    vim.o.spelllang = code
  else
    log.fmt_error("no content returned for setting spelllang")
  end
end

M.interact = function()
  local selection = M.buffer_helper.visual_selection()
  if not selection then
    vim.notify("No visual selection found.", vim.log.levels.WARN)
    return
  end
  exit_visual_mode()

  vim.ui.input({ prompt = "Give instructions: " }, function(command)
    if command then
      local template_subs = { command, selection }
      log.fmt_trace("interact content=%s", template_subs)
      local template = M.template_fn("interact", tpl_interact, template_subs)
      local token = status.start()
      M.template_sender.stream(
        M.adapter_model["interact"],
        template,
        template_subs,
        function()
          if not status.is_current(token) then
            return
          end
          status.finish()
        end,
        "Neogram Interact"
      )
    end
  end)
end

return M
