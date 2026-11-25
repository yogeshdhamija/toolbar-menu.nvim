-- toolbar-menu.nvim - a menu, as clickable buttons in any statusline
-- Maintainer: Yogesh Dhamija <yogeshdhamija@outlook.com>
-- Version 0.1
--
-- render() returns 'statusline'-format text, so it goes wherever that does:
-- 'statusline', 'winbar' or 'tabline' directly, or a component of lualine,
-- heirline or the like. See :help toolbar-menu.

local M = {}

local defaults = {
  menu = 'ToolBar',
  bar = 'statusline',
  max_width = nil,
  overflow = '…',
  separator = '│',
  keep = 0,
  hints = false,
  help = nil,
}

local CLICK = "v:lua.require'toolbar-menu'.click"
-- A menu that starts with ] is hidden (:help hidden-menus)
local POPUP = ']ToolbarMenuPopup'

-- What each click region runs, by the number it passes back (its minwid).
-- Each button gets its number once and keeps it, so redraws don't add more.
-- An item's arg is its name; an overflow button's, the first and last of the
-- items it pops up. A help button pops up all of them, so it has none.
local targets, target_ids = {}, {}
local function target_id(kind, menu, arg, last)
  local key = table.concat({ kind, menu, tostring(arg), tostring(last) }, '\n')
  if not target_ids[key] then
    table.insert(targets, { kind = kind, menu = menu, arg = arg, last = last })
    target_ids[key] = #targets
  end
  return target_ids[key]
end

local function is_separator(name)
  return name:match('^%-.*%-$') ~= nil
end

-- Separators, but none first, last or two in a row
local function tidy(list)
  local tidied = {}
  for _, entry in ipairs(list) do
    if not entry.separator or (#tidied > 0 and not tidied[#tidied].separator) then
      table.insert(tidied, entry)
    end
  end
  if #tidied > 0 and tidied[#tidied].separator then
    table.remove(tidied)
  end
  return tidied
end

-- An item's state (:help toolbar-menu-state): what its function in
-- g:toolbar_menu_state returns, or '' when it has none or that fails.
-- It's called from Vimscript: a Funcref in a dict comes through to Lua as
-- vim.NIL, and call() takes a Funcref, a lambda or a function's name alike.
local function state(name)
  local states = vim.g.toolbar_menu_state
  if type(states) ~= 'table' or states[name] == nil then
    return ''
  end
  local ok, text = pcall(vim.fn.eval, ('call(g:toolbar_menu_state[%s], [])'):format(vim.fn.string(name)))
  if not ok or (type(text) ~= 'string' and type(text) ~= 'number') then
    return ''
  end
  return tostring(text)
end

-- The menu's items in order: { name =, label =, state =, hint = } for each,
-- its label being the name up to the first space and its hint the text after
-- a <Tab> (:help menu-text), and { separator = true } for separators.
-- Submenus and hidden items are left out.
local function entries(menu)
  local ok, found = pcall(vim.fn.menu_get, menu)
  local list = {}
  for _, item in ipairs(ok and found[1] and found[1].submenus or {}) do
    if is_separator(item.name) then
      table.insert(list, { separator = true })
    elseif not item.submenus and item.hidden == 0 then
      table.insert(list, {
        name = item.name,
        label = item.name:match('^%S+') or item.name,
        state = state(item.name),
        hint = item.actext or '',
      })
    end
  end
  return tidy(list)
end

-- A menu path, for :emenu or :menu
local function path(menu, name)
  return menu .. '.' .. (name:gsub('[ .\\|]', '\\%0'))
end

-- The menu mode of each mode() (:help creating-menus); anything else is
-- Normal mode's
local menu_modes = {
  v = 'v', V = 'v', ['\22'] = 'v',
  s = 's', S = 's', ['\19'] = 's',
  i = 'i', R = 'i',
  c = 'c',
  t = 't',
}

-- Runs an item, as :emenu does: its entry for the current mode. One without
-- such an entry runs its Normal mode one instead, from Normal mode.
-- The :emenu is typed, not run with vim.cmd(): from a script, :emenu runs the
-- item the way :normal does, where a getchar() gets an <Esc> instead of
-- waiting for a key.
local function run(menu, name)
  local item_path = path(menu, name)
  local ok, found = pcall(vim.fn.menu_get, item_path)
  if not ok or not found[1] then
    return
  end
  local mode = menu_modes[vim.fn.mode():sub(1, 1)] or 'n'
  local leave = (mode == 'n' or found[1].mappings[mode]) and '' or '<C-\\><C-N>'
  local keys = leave .. '<Cmd>emenu ' .. item_path:gsub('<', '<lt>') .. '<CR>'
  vim.api.nvim_feedkeys(vim.keycode(keys), 'in', false)
end

-- Any number of clicks (<2-LeftMouse>, ...), with any modifiers
local presses = { l = 'LeftMouse>$', r = 'RightMouse>$' }
local releases = { l = 'LeftRelease>$', r = 'RightRelease>$' }

-- Which mouse buttons are down, by the keys read while a popup is up. A click
-- there picks an item as soon as the button goes down, so its release is
-- still to come.
local held = {}
local held_ns = vim.api.nvim_create_namespace('toolbar-menu-held')

-- Pops up these entries of the menu, at the mouse, under their full names
-- and states, with their hints lined up after them. mouse_button ('l' or 'r')
-- is the one whose click popped it up, still down.
local function popup(menu, list, mouse_button)
  list = tidy(list)
  if #list == 0 then
    return
  end
  local texts, widest = {}, 0
  for i, entry in ipairs(list) do
    if not entry.separator then
      texts[i] = entry.state == '' and entry.name or entry.name .. ' ' .. entry.state
      widest = math.max(widest, vim.api.nvim_strwidth(texts[i]))
    end
  end
  pcall(vim.cmd, 'aunmenu ' .. POPUP)
  for i, entry in ipairs(list) do
    if entry.separator then
      vim.cmd(('anoremenu %s.-%d- <Nop>'):format(POPUP, i))
    else
      -- In the name itself: a popup in a terminal leaves out a <Tab>'s text
      local text = texts[i]
      if entry.hint ~= '' then
        text = text .. (' '):rep(widest - vim.api.nvim_strwidth(text) + 2) .. entry.hint
      end
      -- & would mark the next letter as the item's shortcut key
      local item = path(POPUP, text):gsub('&', '&&')
      local rhs = ('<Cmd>lua require("toolbar-menu")._chosen(%d)<CR>'):format(target_id('item', menu, entry.name))
      for _, define in ipairs({ 'nnoremenu', 'vnoremenu', 'inoremenu' }) do
        vim.cmd(('%s %s %s'):format(define, item, rhs))
      end
    end
  end
  held = { [mouse_button] = true }
  vim.on_key(function(_, typed)
    local key = vim.fn.keytrans(typed or '')
    for button, press in pairs(presses) do
      if key:find(press) then
        held[button] = true
      elseif key:find(releases[button]) then
        held[button] = nil
      end
    end
  end, held_ns)
  -- It reads the keys itself until it's closed, running the item picked
  pcall(vim.cmd, 'popup! ' .. POPUP)
  vim.on_key(nil, held_ns)
end

-- While a statusline is being measured, render() draws nothing: what's
-- measured is everything but the buttons
local measuring = false
-- How wide what render() last drew is, by bar and window: { width = }
local drawn = { statusline = {}, winbar = {}, tabline = {} }

-- How wide the bar is, in window win, and how much of it is left once
-- everything else in it is drawn
local function room(win, bar)
  local width = bar == 'tabline' and vim.o.columns or vim.api.nvim_win_get_width(win)
  local value = bar == 'tabline' and vim.o.tabline or vim.wo[win][bar]
  -- Measured far wider than it is, so that what a %= spreads out to fill the
  -- width can be told from the rest: Neovim (0.12) leaves that out when it
  -- won't fit its buffer, and if it ever doesn't, it's a long run of spaces.
  -- Spaces, as a fillchar of anything else replaces those in %{} items too.
  measuring = true
  local ok, result = pcall(vim.api.nvim_eval_statusline, value, {
    winid = win,
    maxwidth = 10000,
    fillchar = ' ',
    use_winbar = bar == 'winbar',
    use_tabline = bar == 'tabline',
  })
  measuring = false
  if not ok then
    return math.floor(width / 2)
  end
  local rest = result.width
  for fill in result.str:gmatch(' +') do
    if #fill >= 1000 then
      rest = rest - #fill
    end
  end
  -- An expression ('%!...', '%{%...%}') was just evaluated, so the buttons it
  -- draws drew nothing. Text set ahead of time, as lualine does, still holds
  -- whatever was drawn when it was set; its click regions are how to tell.
  local last = drawn[bar][win]
  if last and value:find(CLICK, 1, true) then
    rest = rest - last.width
  end
  return width - rest
end

local function escape(text)
  return (text:gsub('%%', '%%%%'))
end

local function button(id, label)
  return ('%%%d@%s@ %s%%X'):format(id, CLICK, escape(label))
end

--- Returns the menu's items as clickable buttons, in 'statusline' format.
--- See :help toolbar-menu.render()
---@param opts? { menu?: string, bar?: 'statusline'|'winbar'|'tabline', max_width?: integer|fun(winid: integer): integer, overflow?: string, separator?: string, keep?: integer, hints?: boolean, help?: string, winid?: integer }
---@return string
function M.render(opts)
  if measuring then
    return ''
  end
  opts = vim.tbl_extend('force', defaults, opts or {})
  local win = opts.winid or vim.g.statusline_winid or vim.api.nvim_get_current_win()
  local max = opts.max_width
  if type(max) == 'function' then
    max = max(win)
  elseif max == nil then
    max = room(win, opts.bar)
  end

  local list = entries(opts.menu)
  local function text(entry)
    return entry.label .. entry.state .. (opts.hints and entry.hint or '')
  end
  local function width(entry)
    return 1 + vim.api.nvim_strwidth(entry.separator and opts.separator or text(entry))
  end
  local function widths(from, to)
    local sum = 0
    for i = from, to do
      sum = sum + width(list[i])
    end
    return sum
  end
  local overflow = 1 + vim.api.nvim_strwidth(opts.overflow)
  -- The help button goes first, and last: nothing at all is drawn when not
  -- even it fits. A separator follows it when anything else does. What's
  -- left after both is the room for the rest.
  local help = opts.help and 1 + vim.api.nvim_strwidth(opts.help) or 0
  local help_separator = opts.help and 1 + vim.api.nvim_strwidth(opts.separator) or 0
  if help > max then
    drawn[opts.bar][win] = { width = 0 }
    return ''
  end
  max = max - help - help_separator
  -- Drawn: list[1..shown], then, if that leaves some out, the overflow button
  -- for them, then list[kept..]. That's all of them when they fit.
  local shown, kept = #list, #list + 1
  if widths(1, #list) > max then
    -- The last opts.keep items, and the separator before them, stay where
    -- they are, unless not even they fit with the overflow button. The ones
    -- dropped are from before them, from the end.
    local count = 0
    while kept > 1 and count < opts.keep do
      kept = kept - 1
      count = count + (list[kept].separator and 0 or 1)
    end
    if kept > 1 and list[kept - 1].separator then
      kept = kept - 1
    end
    if kept == 1 or overflow + widths(kept, #list) > max then
      kept = #list + 1
    end
    shown = 0
    -- Nothing at all when not even the overflow button fits: it would only
    -- push out the rest of the line. With a help button, that's the button.
    if overflow > max and not opts.help then
      drawn[opts.bar][win] = { width = 0 }
      return ''
    end
    local total = overflow + widths(kept, #list)
    for i = 1, kept - 1 do
      if total + width(list[i]) > max then
        break
      end
      total = total + width(list[i])
      shown = i
    end
    while shown > 0 and list[shown].separator do
      shown = shown - 1
    end
  end
  -- The overflow button, unless it would stand for all of them: that's what
  -- the help button pops up
  local more = shown < kept - 1 and not (opts.help and shown == 0 and kept > #list)
  -- Whatever comes after the help button: an item or the overflow button,
  -- never a separator
  local after_help = opts.help and (shown > 0 or more or kept <= #list)

  local parts = {}
  local function draw(entry)
    if entry.separator then
      table.insert(parts, ' ' .. escape(opts.separator))
    else
      table.insert(parts, button(target_id('item', opts.menu, entry.name), text(entry)))
    end
  end
  if opts.help then
    table.insert(parts, button(target_id('help', opts.menu), opts.help))
  end
  if after_help then
    draw({ separator = true })
  end
  for i = 1, shown do
    draw(list[i])
  end
  if more then
    table.insert(parts, button(target_id('overflow', opts.menu, shown + 1, kept - 1), opts.overflow))
  end
  for i = kept, #list do
    draw(list[i])
  end
  drawn[opts.bar][win] = {
    width = help + (after_help and help_separator or 0) + widths(1, shown) + (more and overflow or 0) + widths(kept, #list),
  }
  return table.concat(parts)
end

local ns = vim.api.nvim_create_namespace('toolbar-menu')

-- Runs target id, from the keys typed after whatever's running now finishes.
-- It's typed, as a <Cmd>, rather than run from a callback: after one of
-- those, Neovim has keys of its own waiting, that getchar() would get.
local function run_later(id)
  local keys = vim.keycode(('<Cmd>lua require("toolbar-menu")._run(%d)<CR>'):format(id))
  vim.api.nvim_feedkeys(keys, 'n', false)
end

-- Runs target id once the mouse button that clicked is let go. A click calls
-- its handler as soon as the button goes down, so anything sooner would get
-- the release as the first key it reads.
local function after_release(mouse_button, id)
  local done = false
  local function go()
    if not done then
      done = true
      vim.on_key(nil, ns)
      run_later(id)
    end
  end
  vim.on_key(function(_, typed)
    if vim.fn.keytrans(typed or ''):find(releases[mouse_button]) then
      go()
    end
  end, ns)
  -- In case the terminal never says
  vim.defer_fn(go, 1000)
end

--- The click handler render()'s buttons call: :help toolbar-menu-clicks
function M.click(id, _, mouse_button)
  local target = targets[id]
  if not target then
    return
  end
  -- A click on a window's statusline or winbar leaves the cursor where it was
  local win = vim.fn.getmousepos().winid
  if win ~= 0 and win ~= vim.api.nvim_get_current_win() and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
  if mouse_button == 'r' or (mouse_button == 'l' and target.kind == 'help') then
    popup(target.menu, entries(target.menu), mouse_button)
  elseif mouse_button == 'l' then
    if target.kind == 'overflow' then
      popup(target.menu, vim.list_slice(entries(target.menu), target.arg, target.last), mouse_button)
    else
      after_release(mouse_button, id)
    end
  end
end

-- What the popup's items run. Picked with a click, the item runs once the
-- button's let go, as a button's does; with a key or a release, once the
-- popup's gone: the popup runs this the way :normal does, keys and all.
function M._chosen(id)
  for button in pairs(releases) do
    if held[button] then
      return after_release(button, id)
    end
  end
  vim.schedule(function()
    run_later(id)
  end)
end

-- Runs an item: what run_later() types
function M._run(id)
  local target = targets[id]
  if target then
    run(target.menu, target.arg)
  end
end

return M
