local M = {}

M.setup = function(user_cfg)
  local buffer_helper = require("neogram.buffer_helper")
  local commands = require("neogram.commands")
  local config = require("neogram.config")
  local log = require("neogram.log")
  local post = require("plenary.curl").post
  local ResponseWriter = require("neogram.response_writer")
  local template_sender_factory = require("neogram.template_sender")

  config.setup(user_cfg)

  log.new({ level = config.settings.log_level }, true)
  log.trace("neogram.nvim log started")
  log.fmt_info("user config: %s", user_cfg)

  local template_sender = template_sender_factory(post, ResponseWriter, config.settings.timeout)
  buffer_helper.setup()

  commands.setup(
    buffer_helper,
    template_sender,
    config.command_adapter_model(),
    config.settings.template_fn
  )

  vim.api.nvim_create_user_command("NeogramGrammar", commands.grammar, {
    nargs = "*",
    complete = function()
      return { "scratch" }
    end,
  })
  vim.api.nvim_create_user_command("NeogramApplySuggestion", commands.apply_suggestion, {})
  vim.api.nvim_create_user_command("NeogramApplyNext", commands.apply_next, {})
  vim.api.nvim_create_user_command("NeogramApplyPrev", commands.apply_prev, {})
  vim.api.nvim_create_user_command("NeogramCancel", commands.cancel, {})
  vim.api.nvim_create_user_command("NeogramReject", commands.reject_suggestion, {})
end

return M
