-- The init file of the nvim under test (see driver.lua): the plugin, a
-- ToolBar menu whose items log what they ran, and statuslines that draw it.

vim.opt.rtp:prepend(assert(os.getenv('TM_ROOT')))
vim.o.mouse = 'a'
vim.o.swapfile = false
vim.o.number = false
vim.o.laststatus = 2
vim.o.showmode = false
vim.o.shortmess = vim.o.shortmess .. 'I'

local log = assert(os.getenv('TM_LOG'))
function _G.log(what)
  vim.fn.writefile({ ('%s mode=%s win=%d'):format(what, vim.fn.mode(), vim.fn.winnr()) }, log, 'a')
end
function _G.log_selection(what)
  local from, to = vim.fn.getpos('v'), vim.fn.getpos('.')
  _G.log(('%s %d-%d'):format(what, from[2], to[2]))
end

-- Buttons A B | C % | D E F
vim.cmd([[
  nnoremenu ToolBar.A\ Alpha    <Cmd>lua log('Alpha')<CR>
  xnoremenu ToolBar.A\ Alpha    <Cmd>lua log_selection('Alpha, selected')<CR>
  nnoremenu ToolBar.B\ Bravo    <Cmd>lua log('Bravo')<CR>
  anoremenu ToolBar.-1-         <Nop>
  nnoremenu ToolBar.C\ Charlie  <Cmd>lua log('Charlie')<CR>
  nnoremenu ToolBar.%\ Percent  <Cmd>lua log('Percent')<CR>
  anoremenu ToolBar.-2-         <Nop>
  nnoremenu ToolBar.D\ Delta    <Cmd>lua log('Delta')<CR>
  nnoremenu ToolBar.E\ Echo     <Cmd>lua log('Echo')<CR>
  nnoremenu ToolBar.F\ Foxtrot  <Cmd>lua log('Foxtrot read ' .. vim.fn.getcharstr())<CR>
]])

-- An expression, evaluated as the statusline is drawn. The %{} item has a
-- space in it, which a measurement mustn't take for a %='s fill.
function _G.expression_statusline()
  return ' %f%=' .. require('toolbar-menu').render() .. ' %{"x y"} %l:%c '
end
vim.o.statusline = '%!v:lua.expression_statusline()'

-- Text drawn ahead of time and set, the way lualine does it
function _G.set_statusline_text()
  vim.wo.statusline = ' %f%=' .. require('toolbar-menu').render() .. ' %{"x y"} %l:%c '
end

vim.fn.setline(1, { 'one', 'two', 'three', 'four' })
vim.cmd('file x')
vim.bo.modified = false
