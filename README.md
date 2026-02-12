# nvim-ozone

nvim-ozone is a plugin manager for Neovim, mainly focused on reducing file I/O during Neovim startup and plugin loading.

## Getting Started

### Requirements

- Neovim stable or later built with LuaJIT

### Installation

Copy the following code into your `init.lua`:

```lua
local main = loadfile(vim.fn.stdpath("data") .. "/ozone/main")
if main then
    return main()
end
local ozone_path = vim.fn.stdpath("data") .. "/ozone/_/nvim-ozone"
if not vim.uv.fs_stat(ozone_path) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/futsuuu/nvim-ozone",
        ozone_path,
    })
end
vim.opt.runtimepath:prepend(ozone_path)
return require("ozone").run()
```

### Adding Plugins


```lua
-- stdpath("config")/lua/_build.lua
local ozone = require("ozone")

ozone.add({
    name = {
        path = "path/to/local/plugin",
    }
})
```

## Build Scripts

Lua modules located in `stdpath("config")/lua/_build.lua` and `stdpath("config")/lua/_build/**/*.lua` are only evaluated during the build process.

## License

This repository is licensed under the [MIT License](./LICENSE).
