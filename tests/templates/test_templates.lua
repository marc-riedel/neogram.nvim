local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local format = require("neogram.template_formatter")
local grammar = require("neogram.templates.grammar")
local interact = require("neogram.templates.interact_with_content")
local languague = require("neogram.templates.recognize_language")

local T = new_set()

T["templates"] = new_set()

T["templates"]["grammar"] = function()
  local json = format(grammar, "foo")
  local message = vim.fn.json_decode(json).message
  eq(message, "foo")
end

T["templates"]["interact"] = function()
  local json = format(interact, { "foo", "bar" })
  local message = vim.fn.json_decode(json).message
  eq(message, "foo\n\nbar")
end

T["templates"]["language"] = function()
  local json = format(languague, "foo")
  local message = vim.fn.json_decode(json).message
  eq(message, "foo")
end

return T
