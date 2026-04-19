local format_template = require("neogram.template_formatter")
local log = require("neogram.log")

local function on_chunk_wrap(parse_stream, writer, done_callback)
  return function(error, stream_data)
    if error then
      local msg = string.format(
        "error in stream call back: error=%s, stream_data=%s",
        error,
        vim.inspect(stream_data)
      )
      log.fmt_error(msg)
      vim.notify(msg, vim.log.levels.ERROR)
      return
    end

    log.fmt_trace("on_chunk: stream_data=%s", stream_data or "--no stream_data--")

    local done, delta = parse_stream(stream_data)

    if delta then
      writer:write(delta)
    end

    if done and done_callback then
      done_callback(writer.bufnr, writer.content)
    end
  end
end

return function(post, ResponseWriter, timeout)
  local function send_request(endpoint, headers, body, extra_opts)
    log.fmt_trace("posting with endpoint=%s, body=%s, extra_opts=%s", endpoint, body, extra_opts)

    local opts = { headers = headers, body = body }

    if extra_opts then
      opts = vim.tbl_deep_extend("error", opts, extra_opts)
    end

    return post(endpoint, opts)
  end

  local M = {}

  local function parse_response(response, adapter)
    log.fmt_trace(
      "parse_response: %s",
      response and response.status and vim.inspect(response) or "---no valid response---"
    )
    if response and response.status and response.status == 200 then
      local status, json = pcall(vim.fn.json_decode, response.body)

      if not status then
        log.fmt_error("Could not parse json: %s", response.body or "--no body--")
        return nil
      end

      local content = adapter.parse(json)
      if content then
        return content
      end

      log.fmt_error("response: %s", vim.inspect(response))
      vim.notify("Error processing response", vim.log.levels.ERROR)
    else
      log.fmt_error(
        "response status is not 200. response status=%s. response=%s",
        response and response.status,
        response
      )
      vim.notify(
        string.format("unexpected response from server: %s", vim.inspect(response)),
        vim.log.levels.ERROR
      )
    end
    return nil
  end

  M.send = function(adapter_model, template, user_input, callback)
    log.fmt_trace("send with adapter_model=%s, async=%s", adapter_model, callback ~= nil)

    local adapter = adapter_model.adapter

    local endpoint = adapter:endpoint(adapter_model.model)
    local headers = adapter.post_headers()

    local adapter_template = adapter.template(template, adapter_model.model)
    local body_content = format_template(adapter_template, user_input)

    local extra_opts = { timeout = timeout }
    if callback then
      extra_opts.callback = vim.schedule_wrap(function(response)
        callback(parse_response(response, adapter))
      end)
      send_request(endpoint, headers, body_content, extra_opts)
      return
    end

    local response = send_request(endpoint, headers, body_content, extra_opts)
    return parse_response(response, adapter)
  end

  M.stream = function(adapter_model, template, user_input, callback, scratch_name)
    log.fmt_trace("stream with adapter_model=%s", adapter_model)

    local adapter = adapter_model.adapter

    local endpoint = adapter:endpoint(adapter_model.model, true)
    local headers = adapter.post_headers()

    local adapter_template = adapter.template_stream(template, adapter_model.model)
    local body_content = format_template(adapter_template, user_input)

    local writer = ResponseWriter:new()
    writer:create_scratch_buffer(scratch_name)

    local on_chunk = on_chunk_wrap(adapter.parse_stream, writer, callback)
    local extra_opts = {
      stream = vim.schedule_wrap(on_chunk),
      raw = { "--tcp-nodelay", "--no-buffer" },
    }

    send_request(endpoint, headers, body_content, extra_opts)
  end

  return M
end
