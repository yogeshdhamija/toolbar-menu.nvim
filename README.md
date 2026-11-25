# toolbar-menu.nvim

A menu, Vim's `ToolBar` by default, as clickable buttons in any Neovim statusline, winbar or tabline. Declare the buttons the way Vim always has, with `:menu`; each one shows its name's first word, so a name like `󰱼 Open file` draws as a one-character icon. When they don't all fit, the rest go behind a `…` button that pops them up under their full names (the last few can be kept in place, with `keep`), and a right click on any of them pops up the lot.

```vim
nnoremenu ToolBar.󰱼\ Open\ file   <Cmd>Telescope find_files<CR>
nnoremenu ToolBar.󰆍\ Terminal    <Cmd>terminal<CR>
anoremenu ToolBar.-1-            <Nop>
nnoremenu ToolBar.󰁍\ Back        <C-O>
nnoremenu ToolBar.󰁔\ Forward     <C-I>
```

```
 init.vim                                        󰱼 󰆍 │ 󰁍 󰁔   vim  12:5
```

An item can also show live text after its label, like a count, from a function in `g:toolbar_menu_state`:

```vim
nnoremenu ToolBar.󰈢\ List\ buffers  <Cmd>ls<CR>
let g:toolbar_menu_state = {'󰈢 List buffers': {-> '(' . len(getbufinfo({'buflisted': 1})) . ')'}}
```

draws as `󰈢(3)`. See `:help toolbar-menu-state`.

The keys or command an item does the same as can go after a `<Tab>` in its name, as Vim's own menus show them (`:help menu-text`). The popups always show that text, and with `render({ hints = true })` the buttons do too:

```vim
nmenu ToolBar.󰈞\ Open\ file<Tab>\\oo   \oo
```

draws as `󰈞\oo`. With `render({ help = '?' })`, a `?` button goes first, and a separator after it, that pops up all of the items as a right click does; it's the last to go when there isn't room. See `:help toolbar-menu-hints` and `:help toolbar-menu-help`.

It doesn't draw a statusline of its own: `require('toolbar-menu').render()` returns `'statusline'`-format text, to put in your own (`%!` or `%{%...%}`) or in a lualine, heirline or other component. By default the buttons take whatever room the rest of the line leaves, measured from the line itself, so there's nothing to tell it about what else is there.

A click runs the item's entry for the current mode, the way `:emenu` does, so an item can do something else on a Visual selection; one with no entry for that mode leaves it and runs its Normal mode one.

See `:help toolbar-menu` once installed, or the `doc/` directory.

Requires Neovim.

To install:
- Using [vim-plug](https://github.com/junegunn/vim-plug): `Plug 'yogeshdhamija/toolbar-menu.nvim'`

Tests: `test/run.sh`.
