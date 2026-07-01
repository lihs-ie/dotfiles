local M = {}

local default_config = {
  auto = false,
  max_diagnostics = 8,
  max_messages = 8,
  width = 78,
  height = 18,
  message_provider = nil,
}

M.config = vim.deepcopy(default_config)
M.current_win = nil

local function is_haskell_buffer(bufnr)
  local ft = vim.bo[bufnr].filetype
  return ft == "haskell" or ft == "lhaskell"
end

local function severity_name(severity)
  local names = {
    [vim.diagnostic.severity.ERROR] = "ERROR",
    [vim.diagnostic.severity.WARN] = "WARN",
    [vim.diagnostic.severity.INFO] = "INFO",
    [vim.diagnostic.severity.HINT] = "HINT",
  }
  return names[severity] or "UNKNOWN"
end

local function has_hls_client(bufnr)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    local name = client.name:lower()
    if name == "hls" or name:find("haskell", 1, true) then
      return true
    end
  end
  return false
end

local function collect_lsp_clients(bufnr)
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  local lines = {}
  local hls_attached = false

  for _, client in ipairs(clients) do
    local name = client.name or "<unnamed>"
    local root = client.root_dir or client.config and client.config.root_dir or "<no root_dir>"
    local cmd = client.config and client.config.cmd and table.concat(client.config.cmd, " ") or "<no cmd>"
    if name:lower() == "hls" or name:lower():find("haskell", 1, true) then
      hls_attached = true
    end
    table.insert(lines, string.format("- %s root=%s cmd=%s", name, root, cmd))
  end

  if #lines == 0 then
    table.insert(lines, "- no LSP clients attached to this buffer")
  end

  return {
    hls_attached = hls_attached,
    lines = lines,
    count = #clients,
  }
end

local function collect_diagnostics(bufnr, max_items)
  local items = vim.diagnostic.get(bufnr)
  table.sort(items, function(a, b)
    if a.severity ~= b.severity then
      return a.severity < b.severity
    end
    if a.lnum ~= b.lnum then
      return a.lnum < b.lnum
    end
    return a.col < b.col
  end)

  local lines = {}
  for i, diagnostic in ipairs(items) do
    if i > max_items then
      break
    end
    local msg = diagnostic.message:gsub("%s+", " ")
    table.insert(
      lines,
      string.format(
        "%s:%d:%d %s %s",
        vim.api.nvim_buf_get_name(bufnr),
        diagnostic.lnum + 1,
        diagnostic.col + 1,
        severity_name(diagnostic.severity),
        msg
      )
    )
  end
  return lines, items
end

local function collect_messages(max_items)
  local raw
  if M.config.message_provider then
    raw = M.config.message_provider()
  else
    local ok, result = pcall(vim.api.nvim_exec2, "messages", { output = true })
    raw = ok and result.output or ""
  end

  local matches = {}
  for line in tostring(raw):gmatch("[^\n]+") do
    local lower = line:lower()
    if lower:find("hls", 1, true)
        or lower:find("haskell", 1, true)
        or lower:find("cabal", 1, true)
        or lower:find("cradle", 1, true)
        or lower:find("ghcup", 1, true)
        or lower:find("error", 1, true)
        or lower:find("failed", 1, true) then
      local cleaned = line:gsub("%s+", " ")
      table.insert(matches, cleaned)
    end
  end

  local start = math.max(1, #matches - max_items + 1)
  local lines = {}
  for i = start, #matches do
    table.insert(lines, matches[i])
  end
  return lines
end

local function first_matching_message(messages, patterns)
  for _, line in ipairs(messages) do
    local lower = line:lower()
    for _, pattern in ipairs(patterns) do
      if lower:find(pattern, 1, true) then
        return line
      end
    end
  end
  return nil
end

local function normalize_message(message)
  return tostring(message):gsub("%s+", " ")
end

local function normalize_quotes(message)
  return normalize_message(message)
      :gsub("‘", "'")
      :gsub("’", "'")
      :gsub("“", '"')
      :gsub("”", '"')
end

local function parse_hidden_package(message)
  message = normalize_quotes(message)
  return message:match("hidden package [‘']([^’']+)[’']")
      or message:match("hidden package [`']([^`']+)[`']")
      or message:match("hidden package ([%w%._%-]+)")
end

local function parse_import_module(message)
  message = normalize_quotes(message)
  return message:match("Could not load module [‘']([^’']+)[’']")
      or message:match("Could not load module [`']([^`']+)[`']")
      or message:match("Could not find module [‘']([^’']+)[’']")
      or message:match("Could not find module [`']([^`']+)[`']")
end

local function package_name_from_package_id(package_id)
  return package_id:gsub("%-%d[%d%.]*$", "")
end

local function display_prefix(line)
  if line:match("^%- ") then
    return "  "
  end
  return ""
end

local function split_display_line(line, width)
  if line == "" or vim.fn.strdisplaywidth(line) <= width then
    return { line }
  end

  local wrapped = {}
  local current = ""
  local current_width = 0
  local continuation_prefix = display_prefix(line)
  local continuation_width = vim.fn.strdisplaywidth(continuation_prefix)
  local chars = vim.fn.strchars(line)

  for i = 0, chars - 1 do
    local ch = vim.fn.strcharpart(line, i, 1)
    local ch_width = vim.fn.strdisplaywidth(ch)
    if current ~= "" and current_width + ch_width > width then
      table.insert(wrapped, current)
      current = continuation_prefix .. ch
      current_width = continuation_width + ch_width
    else
      current = current .. ch
      current_width = current_width + ch_width
    end
  end

  if current ~= "" then
    table.insert(wrapped, current)
  end
  return wrapped
end

local function wrap_lines(lines, width)
  local wrapped = {}
  local effective_width = math.max(20, width - 2)
  for _, line in ipairs(lines) do
    for _, part in ipairs(split_display_line(line, effective_width)) do
      table.insert(wrapped, part)
    end
  end
  return wrapped
end

local function infer_causes(bufnr, diagnostics, lsp_info, messages)
  local causes = {}
  local solutions = {}

  if not lsp_info.hls_attached then
    table.insert(causes, "HLS client is not attached to this buffer.")
    table.insert(solutions, "No HLS client is attached. Check that the buffer filetype is haskell and the project root contains cabal.project, hie.yaml, stack.yaml, or package.yaml.")
  end

  local cradle_message = first_matching_message(messages, { "cradle", "cabal", "failed to load" })
  if cradle_message then
    table.insert(causes, "Recent Neovim messages include a Cabal/cradle failure: " .. cradle_message)
    table.insert(solutions, "Fix the Cabal/cradle error shown above. The same component must load before HLS can provide reliable completion.")
  end

  for _, diagnostic in ipairs(diagnostics) do
    local message = diagnostic.message
    local lower = message:lower()
    if lower:find("could not load module", 1, true) or lower:find("could not find module", 1, true) then
      local module_name = parse_import_module(message) or "<unknown module>"
      local hidden_package = parse_hidden_package(message)
      table.insert(causes, "Import failed: module " .. module_name .. " could not be loaded.")
      if hidden_package then
        local package_name = package_name_from_package_id(hidden_package)
        table.insert(causes, "The module is provided by hidden package " .. hidden_package .. ".")
        table.insert(solutions, "Add " .. package_name .. " to the owning component's build-depends, or import the module from a package that is already in build-depends.")
      else
        table.insert(solutions, "Add the package exposing " .. module_name .. " to the owning component's build-depends, then reload HLS.")
      end
      table.insert(solutions, "Owning component is the Cabal component that HLS selected for this buffer; check the component's build-depends stanza.")
      break
    end
  end

  for _, diagnostic in ipairs(diagnostics) do
    local message = diagnostic.message
    if message:find("Not in scope", 1, true) then
      table.insert(causes, "Current module does not typecheck: a name or type is not in scope.")
      table.insert(solutions, "Fix the first not-in-scope error, then wait for HLS to reload diagnostics.")
      if message:find(":>", 1, true) then
        table.insert(causes, "Servant API operators may be missing from imports, for example Servant.API (:>, Get, JSON).")
        table.insert(solutions, "Import the Servant API symbols used by the type, for example Servant.API (:>, Get, JSON).")
      end
      break
    end
  end

  for _, diagnostic in ipairs(diagnostics) do
    local message = diagnostic.message:lower()
    if message:find("cradle", 1, true) or message:find("failed to load cabal", 1, true) then
      table.insert(causes, "Cabal or HLS cradle failed; check hie.yaml, cabal.project, and the selected component.")
      table.insert(solutions, "Fix this diagnostic first: " .. normalize_message(diagnostic.message))
      break
    end
  end

  if #diagnostics == 0 and lsp_info.hls_attached then
    table.insert(causes, "HLS is attached and no diagnostics are present. The completion engine may be inactive or misconfigured.")
    table.insert(solutions, "HLS appears attached. Check the completion engine source list for this buffer and whether LSP completion is enabled.")
  end

  if #causes == 0 then
    table.insert(causes, "Completion is unavailable, but no specific Haskell cause was detected.")
    table.insert(solutions, "The plugin did not find HLS, Cabal, cradle, or diagnostic evidence. Check the completion engine configuration for this buffer.")
  end

  return causes, solutions
end

function M.report(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local diagnostic_lines, diagnostics = collect_diagnostics(bufnr, M.config.max_diagnostics)
  local lsp_info = collect_lsp_clients(bufnr)
  local messages = collect_messages(M.config.max_messages)
  local causes, solutions = infer_causes(bufnr, diagnostics, lsp_info, messages)

  local lines = {
    "Haskell Completion Doctor",
    "",
    "Causes:",
  }

  for _, cause in ipairs(causes) do
    table.insert(lines, "- " .. cause)
  end

  table.insert(lines, "")
  table.insert(lines, "Solutions:")
  for _, solution in ipairs(solutions) do
    table.insert(lines, "- " .. solution)
  end

  table.insert(lines, "")
  table.insert(lines, "Observed LSP clients:")
  for _, line in ipairs(lsp_info.lines) do
    table.insert(lines, line)
  end

  table.insert(lines, "")
  table.insert(lines, "Relevant messages:")
  if #messages == 0 then
    table.insert(lines, "- none")
  else
    for _, line in ipairs(messages) do
      table.insert(lines, "- " .. line)
    end
  end

  table.insert(lines, "")
  table.insert(lines, "Recent diagnostics:")
  if #diagnostic_lines == 0 then
    table.insert(lines, "- none")
  else
    for _, line in ipairs(diagnostic_lines) do
      table.insert(lines, "- " .. line)
    end
  end

  return lines
end

function M.open(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not is_haskell_buffer(bufnr) then
    vim.notify("HaskellCompletionDoctor: current buffer is not Haskell", vim.log.levels.INFO)
    return
  end

  local width = math.min(M.config.width, math.max(40, vim.o.columns - 8))
  local lines = wrap_lines(M.report(bufnr), width)
  local panel = vim.api.nvim_create_buf(false, true)
  vim.b[panel].haskell_completion_doctor = true
  vim.bo[panel].bufhidden = "wipe"
  vim.bo[panel].filetype = "markdown"
  vim.api.nvim_buf_set_lines(panel, 0, -1, false, lines)

  local height = math.min(M.config.height, math.max(8, vim.o.lines - 6), #lines)
  local win = vim.api.nvim_open_win(panel, false, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    width = width,
    height = height,
    row = math.max(1, math.floor((vim.o.lines - height) / 3)),
    col = math.max(1, math.floor((vim.o.columns - width) / 2)),
  })
  M.current_win = win
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].breakindent = true
  vim.wo[win].sidescrolloff = 0

  local close = function()
    M.close()
  end
  vim.keymap.set("n", "q", close, { buffer = panel, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = panel, nowait = true, silent = true })
  vim.keymap.set("n", "<C-c>", close, { buffer = panel, nowait = true, silent = true })
end

M._wrap_lines = wrap_lines

function M.close()
  if M.current_win and vim.api.nvim_win_is_valid(M.current_win) then
    vim.api.nvim_win_close(M.current_win, true)
    M.current_win = nil
    return
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local cfg = vim.api.nvim_win_get_config(win)
    local buf = vim.api.nvim_win_get_buf(win)
    local ok, is_panel = pcall(function()
      return vim.b[buf].haskell_completion_doctor
    end)
    if vim.api.nvim_win_is_valid(win) and ((ok and is_panel) or cfg.relative ~= "") then
      vim.api.nvim_win_close(win, true)
    end
  end
end

function M.setup(config)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(default_config), config or {})
  vim.api.nvim_create_user_command("HaskellCompletionDoctor", function()
    M.open(0)
  end, {})
  vim.api.nvim_create_user_command("HCDoc", function()
    M.open(0)
  end, {})
  vim.api.nvim_create_user_command("HCDocClose", function()
    M.close()
  end, {})
end

return M
