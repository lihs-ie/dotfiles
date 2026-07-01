local repo = vim.fn.getcwd()
vim.opt.runtimepath:prepend(repo .. "/dot_config/nvim")

local ok_require, doctor = pcall(require, "haskell_completion_doctor")
if not ok_require then
  print("not ok - require haskell_completion_doctor")
  print(doctor)
  vim.cmd("cquit 1")
end
doctor.setup({ auto = false })

local function assert_contains(lines, needle)
  local text = table.concat(lines, "\n")
  if not text:find(needle, 1, true) then
    error("expected report to contain " .. vim.inspect(needle) .. "\nreport:\n" .. text)
  end
end

local function with_haskell_buffer(name)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, "/tmp/hcdoc-" .. tostring(bufnr) .. "/" .. name)
  vim.bo[bufnr].filetype = "haskell"
  vim.api.nvim_set_current_buf(bufnr)
  return bufnr
end

local tests = {}

tests["reports missing HLS client"] = function()
  doctor.setup({ auto = false, message_provider = function()
    return ""
  end })
  local bufnr = with_haskell_buffer("MissingHls.hs")
  local report = doctor.report(bufnr)
  assert_contains(report, "HLS client is not attached to this buffer.")
  assert_contains(report, "Observed LSP clients:")
  assert_contains(report, "no LSP clients attached to this buffer")
  assert_contains(report, "project root contains cabal.project")
end

tests["registers short command"] = function()
  if vim.fn.exists(":HCDoc") ~= 2 then
    error("expected :HCDoc command to be registered")
  end
  if vim.fn.exists(":HCDocClose") ~= 2 then
    error("expected :HCDocClose command to be registered")
  end
end

tests["does not enable auto display by default"] = function()
  if doctor.config.auto ~= false then
    error("expected auto display to be disabled by default")
  end
end

tests["hard wraps long report lines"] = function()
  local wrapped = doctor._wrap_lines({
    "- Add servant-server to the owning component's build-depends, or import the module from a package that is already in build-depends.",
  }, 42)

  if #wrapped < 2 then
    error("expected long line to be split")
  end

  for _, line in ipairs(wrapped) do
    if vim.fn.strdisplaywidth(line) > 40 then
      error("wrapped line is too wide: " .. line)
    end
  end
end

tests["reports not-in-scope diagnostics"] = function()
  doctor.setup({ auto = false, message_provider = function()
    return ""
  end })
  local bufnr = with_haskell_buffer("Main.hs")
  local namespace = vim.api.nvim_create_namespace("haskell_completion_doctor_test")
  vim.diagnostic.set(namespace, bufnr, {
    {
      lnum = 15,
      col = 23,
      severity = vim.diagnostic.severity.ERROR,
      message = "Not in scope: type constructor or class ':>'",
      source = "hls",
    },
  })

  local report = doctor.report(bufnr)
  assert_contains(report, "Current module does not typecheck")
  assert_contains(report, "Servant API operators may be missing from imports")
  assert_contains(report, "Import the Servant API symbols")
  assert_contains(report, "Main.hs:16:24 ERROR Not in scope")
end

tests["reports cabal or cradle diagnostics"] = function()
  doctor.setup({ auto = false, message_provider = function()
    return "hls: Failed to load Cabal cradle for /tmp/Types.hs\nunrelated message"
  end })
  local bufnr = with_haskell_buffer("Types.hs")
  local namespace = vim.api.nvim_create_namespace("haskell_completion_doctor_cabal_test")
  vim.diagnostic.set(namespace, bufnr, {
    {
      lnum = 0,
      col = 0,
      severity = vim.diagnostic.severity.ERROR,
      message = "Failed to load Cabal cradle for this file",
      source = "hls",
    },
  })

  local report = doctor.report(bufnr)
  assert_contains(report, "Recent Neovim messages include a Cabal/cradle failure")
  assert_contains(report, "hls: Failed to load Cabal cradle")
  assert_contains(report, "Relevant messages:")
  assert_contains(report, "Cabal or HLS cradle failed")
  assert_contains(report, "Fix this diagnostic first")
end

tests["reports hidden package import diagnostics"] = function()
  doctor.setup({ auto = false, message_provider = function()
    return ""
  end })
  local bufnr = with_haskell_buffer("Main.hs")
  local namespace = vim.api.nvim_create_namespace("haskell_completion_doctor_hidden_package_test")
  vim.diagnostic.set(namespace, bufnr, {
    {
      lnum = 12,
      col = 0,
      severity = vim.diagnostic.severity.ERROR,
      message = table.concat({
        "Could not load module ‘Servant’.",
        "It is a member of the hidden package ‘servant-server-0.20.3.0’.",
        "Perhaps you need to add ‘servant-server’ to the build-depends in your .cabal file.",
      }, "\n"),
      source = "hls",
    },
  })

  local report = doctor.report(bufnr)
  assert_contains(report, "Import failed: module Servant could not be loaded.")
  assert_contains(report, "hidden package servant-server-0.20.3.0")
  assert_contains(report, "Add servant-server to the owning component's build-depends")
  assert_contains(report, "Owning component is the Cabal component")
end

local failures = {}
for name, test in pairs(tests) do
  local ok, err = pcall(test)
  if ok then
    print("ok - " .. name)
  else
    table.insert(failures, "not ok - " .. name .. "\n" .. err)
  end
end

if #failures > 0 then
  for _, failure in ipairs(failures) do
    print(failure)
  end
  vim.cmd("cquit 1")
end

print("haskell_completion_doctor: all tests passed")
vim.cmd("quitall!")
