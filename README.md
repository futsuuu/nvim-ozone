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
    local_plugin = {
        path = "path/to/local/plugin",
    },
    remote_plugin = {
        url = "https://github.com/author/repo",
    },
    remote_plugin_versioned = {
        url = "https://github.com/author/repo",
        version = "v1.2.3",
    },
    remote_plugin_with_path = {
        url = "https://github.com/author/repo",
        path = vim.fn.stdpath("data") .. "/ozone/custom/repo",
    },
    dependent_plugin = {
        path = "path/to/dependent/plugin",
        deps = { "remote_plugin" },
    },
})
```

`url` currently supports `git clone` only.
`version` is optional and is resolved with `git checkout`, so branch names, tags, and revisions can be used.
`deps` is optional and controls plugin load order.
Missing dependencies and circular dependencies are reported as warnings, and loading continues with best-effort ordering.
Invalid plugin specs or install failures are collected and reported together after the build step.

### Updating Plugins

nvim-ozone writes a lock file to `stdpath("config")/ozone-lock.json` after each successful build.
Each git plugin entry stores `url`, optional `version`, and the resolved `revision`.

Call `ozone.update()` to fetch all git plugins and update the lock file to the latest revisions:

```lua
require("ozone").update()
```

`ozone.update()` only updates lock data. The actual checkout happens on the next `ozone.run()`.
When `version` is set on a plugin, `ozone.update()` keeps respecting that ref and updates the locked `revision`.

Plugins removed from your build config are also removed from `ozone-lock.json` on the next build.

### Cleaning Generated Files

Call `ozone.clean()` to remove the generated startup script:

```lua
require("ozone").clean()
```

To also remove installed plugin directories under `stdpath("data")/ozone`, pass `{ all = true }`:

```lua
require("ozone").clean({ all = true })
```

`ozone.clean()` does not delete `ozone-lock.json`.

## Build Scripts

Lua modules located in `stdpath("config")/lua/_build.lua` and `stdpath("config")/lua/_build/**/*.lua` are only evaluated during the build process.

## License

This repository is licensed under the [MIT License](./LICENSE).
