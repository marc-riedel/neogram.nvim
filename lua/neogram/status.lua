local M = { active = false, start_time_ns = 0, current_token = 0 }

local refresh_timer = nil

local function stop_timer()
  if refresh_timer and not refresh_timer:is_closing() then
    refresh_timer:stop()
    refresh_timer:close()
  end
  refresh_timer = nil
end

M.start = function()
  M.active = true
  M.current_token = M.current_token + 1
  M.start_time_ns = vim.loop.hrtime()
  pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "NeogramRequestStarted" })

  stop_timer()
  refresh_timer = vim.loop.new_timer()
  refresh_timer:start(
    100,
    100,
    vim.schedule_wrap(function()
      if M.active then
        pcall(vim.cmd, "redrawstatus")
      end
    end)
  )
  return M.current_token
end

M.finish = function()
  M.active = false
  pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "NeogramRequestFinished" })
  stop_timer()
  pcall(vim.cmd, "redrawstatus")
end

M.cancel = function()
  if not M.active then
    return
  end
  M.current_token = M.current_token + 1
  M.finish()
end

M.is_current = function(token)
  return token == M.current_token
end

M.elapsed_seconds = function()
  if not M.active then
    return 0
  end
  return (vim.loop.hrtime() - M.start_time_ns) / 1e9
end

return M
