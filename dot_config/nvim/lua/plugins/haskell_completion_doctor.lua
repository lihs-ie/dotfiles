return {
  {
    name = "haskell-completion-doctor",
    dir = vim.fn.stdpath("config"),
    cmd = { "HCDoc", "HaskellCompletionDoctor" },
    keys = {
      {
        "<leader>hd",
        function()
          require("haskell_completion_doctor").open(0)
        end,
        desc = "Haskell completion doctor",
      },
      {
        "<leader>hD",
        function()
          require("haskell_completion_doctor").close()
        end,
        desc = "Close Haskell completion doctor",
      },
    },
    config = function()
      require("haskell_completion_doctor").setup()
    end,
  },
}
