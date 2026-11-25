-- Run by run.sh with `nvim -l`. This nvim is only the driver: it runs a
-- second nvim, with init.lua, in a terminal buffer, so that it draws a real
-- screen, and clicks it by sending the terminal the same escape sequences a
-- mouse would (SGR mouse encoding). The screen is read back from the terminal
-- buffer, and what the menu items ran from the log they write.

local root = assert(os.getenv('TM_ROOT'), 'run me through test/run.sh')

local pass, fail = 0, 0
local function out(s)
  io.stdout:write(s .. '\n')
  io.stdout:flush()
end
local function describe(name)
  out('')
  out(name)
end
local function ok(cond, msg)
  if cond then
    pass = pass + 1
    out('  ok    ' .. msg)
  else
    fail = fail + 1
    out('  FAIL  ' .. msg)
  end
end
local function is(got, want, msg)
  if vim.deep_equal(got, want) then
    ok(true, msg)
  else
    ok(false, msg .. '  [got ' .. vim.inspect(got) .. ', want ' .. vim.inspect(want) .. ']')
  end
end

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, 'p')
local log = tmp .. '/log'

local env = vim.fn.environ()
-- $NVIM is set when this runs inside a Neovim terminal; the nvim under test
-- must not think it is nested in that one
for _, name in ipairs({ 'NVIM', 'NVIM_LISTEN_ADDRESS', 'VIMRUNTIME', 'VIM', 'MYVIMRC' }) do
  env[name] = nil
end
env.TERM = 'xterm-256color'
env.TM_ROOT = root
env.TM_LOG = log

local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
local chan = vim.fn.jobstart(
  { 'nvim', '--clean', '-n', '-i', 'NONE', '-u', root .. '/test/init.lua' },
  { term = true, cwd = tmp, clear_env = true, env = env }
)
vim.wait(1500)

local function send(keys)
  vim.fn.chansend(chan, keys)
  vim.wait(300)
end
local function screen()
  vim.wait(200)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end
-- The bottom row is the command line; the one above it, the statusline
local function statusline()
  local lines = screen()
  return lines[#lines - 1], #lines - 1
end
-- Without the space a %= fills, and the rest squeezed to one
local function trimmed(line)
  return vim.trim((line or ''):gsub('%s+', ' '))
end
-- Screen column (1-based) of text in line, at or after column `from`
local function column(line, text, from)
  local byte = line:find(text, vim.fn.byteidx(line, (from or 1) - 1) + 1, true)
  return byte and vim.fn.strdisplaywidth(line:sub(1, byte - 1)) + 1
end
-- Let go a moment after it goes down, as a hand does, so that whatever runs
-- on the press has run before the release comes
local function click(button, col, row)
  local code = ({ left = 0, right = 2 })[button]
  send(('\27[<%d;%d;%dM'):format(code, col, row))
  send(('\27[<%d;%d;%dm'):format(code, col, row))
end
-- Clicks text in the statusline (the last match, as the buttons are on the right)
local function click_statusline(text, button)
  local line, row = statusline()
  local col, at = nil, 1
  while true do
    local found = column(line, text, at)
    if not found then
      break
    end
    col, at = found, found + 1
  end
  assert(col, ('no %q in the statusline: %q'):format(text, line))
  click(button or 'left', col, row)
end
-- Clicks text anywhere on screen (the first match)
local function click_screen(text)
  for row, line in ipairs(screen()) do
    local col = column(line, text)
    if col then
      return click('left', col, row)
    end
  end
  error(('no %q on screen'):format(text))
end
local function on_screen(text)
  for _, line in ipairs(screen()) do
    if line:find(text, 1, true) then
      return true
    end
  end
  return false
end
-- What the menu items ran since last time
local function ran()
  vim.wait(200)
  local lines = vim.fn.filereadable(log) == 1 and vim.fn.readfile(log) or {}
  vim.fn.delete(log)
  return lines
end
local function reset()
  send('\27\27:lua render_opts = nil\r')
  send(':only | vertical resize | set statusline=%!v:lua.expression_statusline()\rgg')
  ran()
end

describe('drawing')
do
  is(trimmed(statusline()), 'x A B │ C % │ D E F x y 1:1', 'all the buttons, by the first word of their names, when they fit')
end

describe('clicking')
do
  click_statusline('B')
  is(ran(), { 'Bravo mode=n win=1' }, "runs the item's Normal mode entry")
  click_statusline('%')
  is(ran(), { 'Percent mode=n win=1' }, 'a % in a name is drawn as one, not taken for a statusline item')
  send('2Gvj')
  click_statusline('A')
  is(ran(), { 'Alpha, selected 2-3 mode=v win=1' }, 'runs the Visual mode entry in Visual mode, with the selection')
  send('\27')
  send('vj')
  click_statusline('B')
  is(ran(), { 'Bravo mode=n win=1' }, 'an item with no Visual mode entry leaves Visual mode and runs the Normal one')
  send('i')
  click_statusline('C')
  is(ran(), { 'Charlie mode=n win=1' }, 'same from Insert mode')
  send('\27')
  click_statusline('F')
  send('k')
  is(ran(), { 'Foxtrot read k mode=n win=1' }, 'runs once the button is let go: the first key it reads is a key')
end

describe('a narrow window')
do
  reset()
  send(':vsplit | vertical resize 24\r')
  local line = statusline():sub(1, vim.fn.byteidx(statusline(), 24))
  is(trimmed(line), 'x A B │ C % … x y 1:1', 'what fits, then … for the rest, leaving the rest of the line alone')
  click_statusline('…')
  ok(on_screen('D Delta') and on_screen('F Foxtrot') and not on_screen('C Charlie'), '… pops up the rest, by their full names')
  click_screen('E Echo')
  is(ran(), { 'Echo mode=n win=1' }, 'and runs the one clicked')
  click_statusline('…')
  click_screen('F Foxtrot')
  send('k')
  is(ran(), { 'Foxtrot read k mode=n win=1' }, 'once the click on it is let go: the first key it reads is a key')
  click_statusline('…')
  -- Down to the third, F
  send('jjj\r')
  send('k')
  is(ran(), { 'Foxtrot read k mode=n win=1' }, 'or one picked with the keyboard, once the popup is gone')
  -- This window's A, the first in the row
  local row
  line, row = statusline()
  click('right', column(line, 'A'), row)
  ok(on_screen('A Alpha') and on_screen('E Echo'), 'a right click pops up all of them')
  send('\27')
  send(':vertical resize 12\r')
  line = statusline():sub(1, vim.fn.byteidx(statusline(), 12))
  is(trimmed(line), 'x x y 1:1', 'nothing at all when not even … fits, rather than push out the rest of the line')
end

describe('keeping the last ones')
do
  reset()
  send(':lua render_opts = { keep = 3 }\r')
  is(trimmed(statusline()), 'x A B │ C % │ D E F x y 1:1', 'all of them, as ever, when they fit')
  send(':vsplit | vertical resize 24\r')
  local line = statusline():sub(1, vim.fn.byteidx(statusline(), 24))
  is(trimmed(line), 'x A … │ D E F x y 1:1', 'the last ones stay, and the separator before them; the ones before them go')
  click_statusline('…')
  ok(on_screen('B Bravo') and on_screen('% Percent') and not on_screen('A Alpha') and not on_screen('D Delta'),
    '… pops up just the ones it stands for')
  click_screen('C Charlie')
  is(ran(), { 'Charlie mode=n win=1' }, 'and runs the one clicked')
  local row
  line, row = statusline()
  click('left', column(line, 'E'), row)
  is(ran(), { 'Echo mode=n win=1' }, 'a kept one runs, as any other does')
  send(':vertical resize 16\r')
  line = statusline():sub(1, vim.fn.byteidx(statusline(), 16))
  is(trimmed(line), 'x A … x y 1:1', 'they go too, from the end, when there is no room for them with the …')
end

describe('another window')
do
  reset()
  send(':vsplit\r')
  -- The right window's statusline; the cursor is in the left one
  local line, row = statusline()
  local right = column(line, 'B', 41)
  click('left', right, row)
  is(ran(), { 'Bravo mode=n win=2' }, "a click on another window's buttons runs in that window")
end

describe('text drawn ahead of time, as lualine does')
do
  reset()
  send(':vsplit | vertical resize 24\r')
  send(':lua set_statusline_text()\r')
  send(':lua set_statusline_text()\r')
  local line = statusline():sub(1, vim.fn.byteidx(statusline(), 24))
  is(trimmed(line), 'x A B │ C % … x y 1:1', 'fits once drawn again: the room is measured from what was set last')
  send(':lua set_statusline_text()\r')
  line = statusline():sub(1, vim.fn.byteidx(statusline(), 24))
  is(trimmed(line), 'x A B │ C % … x y 1:1', 'and stays put')
end

describe('state')
do
  reset()
  send([[:let g:n = 2 | let g:toolbar_menu_state = {'B Bravo': {-> '(' . g:n . ')'}, ]]
    .. [['C Charlie': 'NoSuchFunction', 'E Echo': {-> g:no_such_variable}} | redrawstatus]] .. '\r')
  is(trimmed(statusline()), 'x A B(2) │ C % │ D E F x y 1:1', "an item's state, right after its label")
  ok(not on_screen('E117') and not on_screen('E121'), 'one whose function fails draws nothing, and says nothing')
  send(':let g:n = 3 | redrawstatus\r')
  is(trimmed(statusline()), 'x A B(3) │ C % │ D E F x y 1:1', 'called again every time the buttons are drawn')
  click_statusline('(3)')
  is(ran(), { 'Bravo mode=n win=1' }, 'a click on the state runs the item, as one on the label does')
  local line, row = statusline()
  click('right', column(line, 'A'), row)
  ok(on_screen('B Bravo (3)') and on_screen('C Charlie') and not on_screen('C Charlie ('), 'the popups show it after the full name')
  send('\27')
  send([[:lua vim.g.toolbar_menu_state = { ['D Delta'] = function() return '*' end }]] .. '\r')
  send(':redrawstatus\r')
  is(trimmed(statusline()), 'x A B │ C % │ D* E F x y 1:1', 'a Lua function, set from Lua, works too')
  send(':unlet g:toolbar_menu_state | redrawstatus\r')
end

describe('hints')
do
  reset()
  send(':lua render_opts = { hints = true }\r')
  is(trimmed(statusline()), 'x A:a B │ C^C % │ Dd|D E\\e F x y 1:1', "each item's hint, right after its label")
  click_statusline('\\e')
  is(ran(), { 'Echo mode=n win=1' }, 'a click on the hint runs the item, as one on the label does')
  send(':lua render_opts = nil\r')
  local line, row = statusline()
  click('right', column(line, 'A'), row)
  local lines = {}
  for _, l in ipairs(screen()) do
    for _, name in ipairs({ 'A Alpha', 'C Charlie', 'D Delta', 'E Echo' }) do
      if l:find(name, 1, true) then
        lines[name] = l
      end
    end
  end
  local a = lines['A Alpha'] and column(lines['A Alpha'], ':a')
  is({ a, lines['D Delta'] and column(lines['D Delta'], 'd|D'), lines['E Echo'] and column(lines['E Echo'], '\\e') },
    { a, a, a }, 'the popups show them, lined up, without the option too')
  ok(a and a > column(lines['C Charlie'], 'C Charlie') + #'C Charlie', 'after the longest name, and a gap')
  click_screen('D Delta')
  is(ran(), { 'Delta mode=n win=1' }, 'and run the one clicked, a | in its hint and all')
end

describe('help')
do
  reset()
  send(':lua render_opts = { help = "?" }\r')
  is(trimmed(statusline()), 'x ? A B │ C % │ D E F x y 1:1', 'a help button, first')
  click_statusline('?')
  ok(on_screen('A Alpha') and on_screen('F Foxtrot'), 'a click on it pops up all of them, as a right click does')
  click_screen('B Bravo')
  is(ran(), { 'Bravo mode=n win=1' }, 'and runs the one clicked')
  send(':vsplit | vertical resize 24\r')
  local function left(width)
    local line = statusline()
    return trimmed(line:sub(1, vim.fn.byteidx(line, width)))
  end
  is(left(24), 'x ? A B │ C … x y 1:1', 'the rest go behind … from the end, as ever')
  click_statusline('…')
  ok(on_screen('% Percent') and on_screen('F Foxtrot') and not on_screen('A Alpha'), '… pops up just those, not help')
  send('\27')
  send(':lua render_opts = { help = "?", keep = 3 }\r')
  send(':vertical resize 18\r')
  is(left(18), 'x ? A … x y 1:1', 'it stays when the kept ones go')
  send(':vertical resize 16\r')
  is(left(16), 'x ? x y 1:1', 'and on its own, without a … that would stand for all of them')
  send(':vertical resize 13\r')
  is(left(13), 'x ? x y 1:1', 'down to the last cell it needs')
  send(':vertical resize 12\r')
  is(left(12), 'x x y 1:1', 'then nothing at all')
end

vim.fn.chansend(chan, '\27\27:qa!\r')
vim.wait(300)
vim.fn.delete(tmp, 'rf')
out('')
out(('%d passed, %d failed'):format(pass, fail))
vim.cmd(fail > 0 and 'cquit' or 'qall!')
