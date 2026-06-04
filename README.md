# Neogram

Neogram is a Neovim plugin that uses LLMs (Claude, Gemini, OpenAI) to check
grammar and spelling of natural language prose — directly in your buffer. It
highlights changes at word granularity, supports visual selections and
multi-line paragraphs, streams suggestions asynchronously, and lets you step
through corrections with your existing diagnostic keybindings.

Neogram is a fork of [taal.nvim](https://github.com/bennorichters/taal.nvim)
and extends it with visual/paragraph selection, async requests with cancel,
navigation, status-line progress, and more.

## Features

- **Grammar and spelling checks** — language-agnostic, limited only by the LLM.
- **Word-level diffs** — original and corrected text are compared per-word and
  highlighted inline or offered in a scratch buffer.
- **Visual selection** — run the check on a `v`/`V` selection; single-line
  selections use a column offset, multi-line selections map byte positions back
  to buffer coordinates for accurate highlights.
- **Paragraph detection** — without a selection, Neogram operates on the whole
  paragraph the cursor is in (bounded by blank lines), not just the current
  line.
- **Asynchronous requests** — the UI never blocks. A request can be canceled at
  any time with `<Esc>`.
- **Status-line indicator** — fires `User NeogramRequestStarted` /
  `User NeogramRequestFinished` autocmds and ticks a 100ms redraw so your
  status line can show a spinner and elapsed seconds. A ready-to-use
  `lualine.nvim` component is included below.
- **Navigation** — `NeogramApplyNext` / `NeogramApplyPrev` apply the suggestion
  under the cursor (if any) and jump to the next/previous suggestion. Combined
  with `NeogramReject`, you can walk through a paragraph and accept or reject
  each change with two keys.
- **Named scratch buffer** — `Grammar Suggestions` rather than an anonymous
  temp buffer.
- **Multiple adapters** — Claude, Gemini, and OpenAI (Responses API); Ollama is
  supported for local testing.

![Inlay hint suggestions](assets/inlay.png)
![Scratch buffer diff](assets/scratch.png)

### Limitations

- Suggestions are cleared when you enter insert mode in the affected buffer.
- Applying a multi-line replacement invalidates the remaining suggestions in
  that buffer (positions shift unpredictably), so they are cleared.

## Installation

Neogram uses `curl` via [nvim-lua/plenary.nvim](https://github.com/nvim-lua/plenary.nvim).

<details>
<summary><a href="https://github.com/folke/lazy.nvim/">lazy.nvim</a></summary>

```lua
{
  "marc-riedel/neogram.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  cmd = {
    "NeogramGrammar", "NeogramApplySuggestion",
    "NeogramApplyNext", "NeogramApplyPrev",
    "NeogramCancel", "NeogramReject",
  },
  keys = {
    { "<leader>agg", "<Cmd>NeogramGrammar<Cr>",         desc = "Check grammar" },
    { "<leader>agg", "<Cmd>NeogramGrammar<Cr>", mode = "v", desc = "Check grammar" },
    { "<leader>aga", "<Cmd>NeogramApplySuggestion<Cr>", desc = "Apply suggestion" },
  },
  opts = {
    adapter = "openai_responses",
    model = "gpt-5",
  },
}
```

</details>

<details>
<summary><a href="https://nvim-mini.org/mini.nvim/readmes/mini-deps">mini.deps</a></summary>

```lua
MiniDeps.later(function()
  MiniDeps.add {
    source = "marc-riedel/neogram.nvim",
    depends = { "nvim-lua/plenary.nvim" },
  }
  require("neogram").setup()
end)
```

</details>

### API keys

Each adapter reads an API key from its own environment variable:

| Adapter             | Environment variable |
| ------------------- | -------------------- |
| `claude`            | `CLAUDE_API_KEY`     |
| `gemini`            | `GEMINI_API_KEY`     |
| `openai_responses`  | `OPENAI_API_KEY`     |

### Setup

`require("neogram").setup(opts)` is mandatory. `opts` is optional and
merged onto the defaults:

```lua
require("neogram").setup({
  log_level = "error",   -- trace | debug | info | warn | error | fatal
  timeout   = 6000,      -- request timeout (ms)
  adapter   = "openai_responses",
  model     = "gpt-5",
  -- Per-command overrides:
  commands = {
    grammar = { adapter = nil, model = nil },
  },
  -- Optional hook to rewrite the prompt template before it is sent.
  template_fn = function(_command, default_template, _user_input)
    return default_template
  end,
})
```

## Commands

| Command                     | Description                                                                                                   |
| --------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `:NeogramGrammar [scratch]` | Check grammar on the visual selection, current paragraph (no selection), or the buffer range; corrections show inline with inlay hints. |
| `:NeogramApplySuggestion`   | Accept the suggestion under the cursor.                                                                       |
| `:NeogramApplyNext`         | Accept the suggestion under the cursor (if any) and jump to the next suggestion.                              |
| `:NeogramApplyPrev`         | Accept the suggestion under the cursor (if any) and jump to the previous suggestion.                          |
| `:NeogramReject`            | Remove the suggestion under the cursor without applying it.                                                   |
| `:NeogramCancel`            | Cancel the in-flight LLM request.                                                                             |

`NeogramGrammar` modes:

- **inline** (default): highlights changed words in place using `NeogramIssue`
  highlights, plus the corrected word as virtual inline text (`NeogramInlay`
  group).
- **scratch**: streams the corrected version into a side-by-side scratch
  buffer named `Grammar Suggestions`.

## A recommended workflow

Check a paragraph, then step through each correction using your existing
diagnostic keys:

```lua
-- Accept or reject suggestions with the same keys you use for diagnostics.
-- When there is a suggestion at or in the direction of the cursor, these
-- keys route to Neogram; otherwise they fall back to vim.diagnostic.jump.
local function neogram_or_diagnostic(forward)
  return function()
    local ok, c = pcall(require, "neogram.commands")
    if ok and c.has_suggestion_nearby and c.has_suggestion_nearby(forward) then
      if forward then c.apply_next() else c.apply_prev() end
      return
    end
    vim.diagnostic.jump({ count = forward and 1 or -1, float = true })
  end
end
vim.keymap.set("n", "]d", neogram_or_diagnostic(true),  { desc = "Next suggestion/diagnostic" })
vim.keymap.set("n", "[d", neogram_or_diagnostic(false), { desc = "Prev suggestion/diagnostic" })

-- Reject the suggestion under the cursor.
vim.keymap.set("n", "\\", function()
  local ok, c = pcall(require, "neogram.commands")
  if ok and c.reject_suggestion() then return end
end, { desc = "Reject Neogram suggestion" })

-- Cancel an in-flight request.
vim.keymap.set("n", "<Esc>", function()
  local ok, c = pcall(require, "neogram.commands")
  if ok and c.cancel and c.cancel() then return "" end
  vim.cmd("noh")
  return "<Esc>"
end, { expr = true, desc = "Cancel Neogram / clear hlsearch" })
```

With this setup:

- `]d` advances through Neogram suggestions *or* diagnostics, accepting the
  one under the cursor.
- `[d` does the same in reverse.
- `\` rejects a suggestion without applying.
- `<Esc>` cancels an in-flight request (and still clears `hlsearch` otherwise).

## Status line integration (lualine)

Neogram fires `User NeogramRequestStarted` and `User NeogramRequestFinished`
autocmds and ticks a 100ms `redrawstatus`, so a plain lualine component is
enough to show a spinner and elapsed time. Drop this into your config:

```lua
-- ~/.config/nvim/lua/lualine_neogram.lua
local M = require("lualine.component"):extend()

M.processing    = false
M.spinner_index = 1
M.start_time    = nil

local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

function M:init(options)
  M.super.init(self, options)
  local group = vim.api.nvim_create_augroup("NeogramHooks", {})
  vim.api.nvim_create_autocmd("User", {
    pattern = "NeogramRequest*",
    group = group,
    callback = function(req)
      if req.match == "NeogramRequestStarted" then
        self.processing = true
        self.start_time = vim.loop.hrtime()
      elseif req.match == "NeogramRequestFinished" then
        self.processing = false
        self.start_time = nil
      end
    end,
  })
end

function M:update_status()
  if not self.processing then return nil end
  self.spinner_index = (self.spinner_index % #spinner) + 1
  local elapsed = self.start_time and (vim.loop.hrtime() - self.start_time) / 1e9 or 0
  return string.format("%s Checking %.1fs", spinner[self.spinner_index], elapsed)
end

return M
```

Then add it to a lualine section:

```lua
table.insert(opts.sections.lualine_c or {}, require("lualine_neogram"))
```

## Lua API

The following functions are available on `require("neogram.commands")`:

| Function                             | Returns  | Notes                                                                                 |
| ------------------------------------ | -------- | ------------------------------------------------------------------------------------- |
| `grammar_inline_lines(start, end, inlay)` | nil   | Programmatic inline grammar check on a 1-indexed line range.                          |
| `apply_suggestion()`                 | nil      | Apply the suggestion at the cursor.                                                   |
| `apply_next()`                       | nil      | Apply suggestion at cursor (if any), then move to next.                               |
| `apply_prev()`                       | nil      | Apply suggestion at cursor (if any), then move to previous.                           |
| `reject_suggestion()`                | bool     | `true` if a suggestion under the cursor was removed.                                  |
| `cancel()`                           | bool     | `true` if an in-flight request was canceled.                                          |
| `has_suggestions_in_buffer()`        | bool     | Whether any suggestion exists in the current buffer.                                  |
| `has_suggestion_nearby(forward)`     | bool     | Whether the cursor is on a suggestion or one exists in the requested direction.       |

## Highlight groups

- `NeogramIssue` — the original text with an error.
- `NeogramImprovement` — the corrected text (used in the scratch buffer).
- `NeogramInlay` — inline virtual text for inlay mode.

## License

Same as the upstream project (MIT). See `LICENSE`.
