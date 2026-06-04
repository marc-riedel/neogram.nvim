local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local format = require("neogram.template_formatter")
local grammar = require("neogram.templates.grammar")

local T = new_set()

T["templates"] = new_set()

T["templates"]["grammar"] = function()
  local json = format(grammar, "foo")
  local message = vim.fn.json_decode(json).message
  eq(message, "foo")
end

return T
