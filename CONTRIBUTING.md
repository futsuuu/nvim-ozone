# Contributing to nvim-ozone

## Code Style

- Always run `mise run check` and fix problems after making code changes.
- Write type annotations for all function arguments and return values by default.
    - You don't need to write annotations for items with types already determined, such as callback functions or overridden methods.
- Do not overload operators.
- Do not use enum tables (use string literals instead).
- Call `require()` at the top level, except when avoiding circular dependencies.
- Do not define aliases for omitting field access at the top level of a module, except for `ffi.C`. \
    Prefer
    ```lua
    -- ...
    local function foo(path)
        return vim.fs.joinpath(vim.fs.dirname(path), vim.fs.basename(path))
    end
    ```
    Over
    ```lua
    local fs = vim.fs
    -- ...
    local function foo(path)
        return fs.joinpath(fs.dirname(path), fs.basename(path))
    end
    ```
- Prefer Neovim Lua API over Vim script API (e.g.: use `vim.fs.*` instead of `vim.fn.fnamemodify()` if possible).

### Naming Conventions

- Add `_` as a prefix for unused variables and private fields.
- When writing abbreviations in `CamelCase`, do not unnaturally convert them to lowercase (use `ID` instead of `Id`).
- Files
    - Use `snake_case`.
    - Do not use `init.lua` (use `foo.lua` instead of `foo/init.lua`).
- Values
    - Use `snake_case` except for the following cases.
    - Use `TITLE_CASE` for variables and metafields treated as constants.
    - Use `CamelCase` for variables and metafields treated as class types.
    - Variables storing values returned by `require()` should be named to match the module's value, not the module name.
        ```lua
        -- lua/foo/bar.lua
        ---@class foo.Bar
        local Bar = {}
        -- ...
        return Bar
        ```
        ```lua
        -- lua/another/module.lua
        local Bar = require("foo.bar")
        ```
- Type Annotations
    - Add the module name as a prefix. If the module returns a class, the prefix should be that class's type name.
        ```lua
        -- lua/mod/name.lua
        local name = {}
        ---@class mod.name.Foo
        local Foo = {}
        -- ...
        return name
        ```
        ```lua
        -- lua/foo/bar.lua
        ---@class foo.Bar
        local Bar = {}
        ---@class foo.Bar.Baz
        local Baz = {}
        -- ...
        return Bar
        ```
