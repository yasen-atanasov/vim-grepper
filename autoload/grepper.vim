" vim: tw=80

" Escaping test line:
" ..ad\\f40+$':-# @=,!;%^&&*()_{}/ /4304\'""?`9$343%$ ^adfadf[ad)[(

let s:options = {
      \ 'quickfix':  1,
      \ 'open':      1,
      \ 'switch':    1,
      \ 'jump':      0,
      \ 'cword':     0,
      \ 'prompt':    1,
      \ 'highlight': 0,
      \ 'next_tool': '<tab>',
      \ 'tools':     ['ag', 'ack', 'grep', 'findstr', 'rg', 'pt', 'git'],
      \ 'git':       { 'grepprg':    'git grep -nI',
      \                'grepformat': '%f:%l:%m',
      \                'escape':     '\^$.*[]' },
      \ 'ag':        { 'grepprg':    'ag --vimgrep',
      \                'grepformat': '%f:%l:%c:%m,%f:%l:%m',
      \                'escape':     '\^$.*+?()[]{}|' },
      \ 'rg':        { 'grepprg':    'rg --no-heading --vimgrep',
      \                'grepformat': '%f:%l:%c:%m',
      \                'escape':     '\^$.*+?()[]{}|' },
      \ 'pt':        { 'grepprg':    'pt --nogroup',
      \                'grepformat': '%f:%l:%m' },
      \ 'ack':       { 'grepprg':    'ack --noheading --column',
      \                'grepformat': '%f:%l:%c:%m',
      \                'escape':     '\^$.*+?()[]{}|' },
      \ 'grep':      { 'grepprg':    'grep -Rn $* .',
      \                'grepformat': '%f:%l:%m',
      \                'escape':     '\^$.*[]' },
      \ 'findstr':   { 'grepprg':    'findstr -rspnc:"$*" *',
      \                'grepformat': '%f:%l:%m' },
      \ }

let s:has_doau_modeline = v:version > 703 || v:version == 703 && has('patch442')

if exists('g:grepper')
  for key in keys(g:grepper)
    if type(g:grepper[key]) == type({})
      if !has_key(s:options, key)
        let s:options[key] = {}
      endif
      call extend(s:options[key], g:grepper[key])
    else
      let s:options[key] = g:grepper[key]
    endif
  endfor
endif

for tool in s:options.tools
  if !has_key(s:options, tool)
        \ || !has_key(s:options[tool], 'grepprg')
        \ || !executable(expand(matchstr(s:options[tool].grepprg, '^[^ ]*')))
    call remove(s:options.tools, index(s:options.tools, tool))
  endif
endfor

" Special case: ag (-vimgrep isn't available in versions < 0.25)
if index(s:options.tools, 'ag') >= 0
      \ && !exists('g:grepper.ag.grepprg')
      \ && split(system('ag --version'))[2] =~ '^\v\d+\.%([01]|2[0-4])'
  let s:options.ag.grepprg = 'ag --column --nogroup'
endif

" Special case: ack (different distros use different names for ack)
let ack     = index(s:options.tools, 'ack')
let ackgrep = index(s:options.tools, 'ack-grep')
if (ack >= 0) && (ackgrep >= 0)
  call remove(s:options.tools, ackgrep)
endif

let s:cmdline = ''
let s:slash   = exists('+shellslash') && !&shellslash ? '\' : '/'
let s:magic   = { 'next': '$$$next###', 'esc': '$$$esc###' }

" s:error() {{{1
function! s:error(msg)
  echohl ErrorMsg
  echomsg a:msg
  echohl NONE
endfunction
" }}}

" s:on_stdout_nvim() {{{1
function! s:on_stdout_nvim(job_id, data) dict abort
  let self.stdoutbuf += a:data
endfunction

" s:on_stdout_vim() {{{1
function! s:on_stdout_vim(job_id, data) dict abort
  let self.stdoutbuf += [a:data]
endfunction

" s:on_stderr() {{{1
function! s:on_stderr(job_id, data) dict abort
  let self.stdoutbuf += a:data
endfunction

" s:on_exit() {{{1
function! s:on_exit(id_or_channel) dict abort
  execute 'tabnext' self.tabpage
  execute self.window .'wincmd w'

  if has('nvim')
    call filter(self.stdoutbuf, '!empty(v:val)')
  endif

  execute (self.flags.quickfix ? 'cgetexpr' : 'lgetexpr') 'self.stdoutbuf'

  silent! unlet s:id
  return s:finish_up(self.flags)
endfunction
" }}}

" #complete() {{{1
function! grepper#complete(lead, line, _pos) abort
  if a:lead =~ '^-'
    let flags = ['-cword', '-grepprg', '-highlight', '-jump', '-open', '-prompt',
          \ '-query', '-quickfix', '-switch', '-tool', '-nohighlight', '-nojump',
          \ '-noopen', '-noprompt', '-noquickfix', '-noswitch']
    return filter(map(flags, 'v:val." "'), 'v:val[:strlen(a:lead)-1] ==# a:lead')
  elseif a:line =~# '-tool \w*$'
    return filter(map(sort(copy(s:options.tools)), 'v:val." "'),
          \ 'empty(a:lead) || v:val[:strlen(a:lead)-1] ==# a:lead')
  else
    return grepper#complete_files(a:lead, 0, 0)
  endif
endfunction

" #complete_files() {{{1
function! grepper#complete_files(lead, _line, _pos)
  let [head, path] = s:extract_path(a:lead)
  " handle relative paths
  if empty(path) || (path =~ '\s$')
    return map(split(globpath('.'.s:slash, path.'*'), '\n'), 'head . "." . v:val[1:] . (isdirectory(v:val) ? s:slash : "")')
  " handle sub paths
  elseif path =~ '^.\/'
    return map(split(globpath('.'.s:slash, path[2:].'*'), '\n'), 'head . "." . v:val[1:] . (isdirectory(v:val) ? s:slash : "")')
  " handle absolute paths
  elseif path[0] == '/'
    return map(split(globpath(s:slash, path.'*'), '\n'), 'head . v:val[1:] . (isdirectory(v:val) ? s:slash : "")')
  endif
endfunction

" s:extract_path() {{{1
function! s:extract_path(string) abort
  let item = split(a:string, '.*\s\zs', 1)
  let len  = len(item)

  if     len == 0 | let [head, path] = ['', '']
  elseif len == 1 | let [head, path] = ['', item[0]]
  elseif len == 2 | let [head, path] = item
  else            | throw 'The unexpected happened!'
  endif

  return [head, path]
endfunction
" }}}

" s:lstrip() {{{1
function! s:lstrip(string) abort
  return substitute(a:string, '^\s\+', '', '')
endfunction
" }}}

" s:split_one() {{{1
function! s:split_one(string) abort
  let stripped = s:lstrip(a:string)
  let first_word = substitute(stripped, '\v^(\S+).*', '\1', '')
  let rest = substitute(stripped, '\v^\S+\s*(.*)', '\1', '')
  return [first_word, rest]
endfunction
" }}}

" #parse_flags() {{{1
function! grepper#parse_flags(args) abort
  let flags = extend({ 'query': '', 'query_escaped': 0 }, s:options)
  let [flag, args] = s:split_one(a:args)

  while flag != ''
    if     flag =~? '\v^-%(no)?(quickfix|qf)$' | let flags.quickfix  = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?open$'          | let flags.open      = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?switch$'        | let flags.switch    = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?jump$'          | let flags.jump      = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?prompt$'        | let flags.prompt    = flag !~? '^-no'
    elseif flag =~? '\v^-%(no)?highlight$'     | let flags.highlight = flag !~? '^-no'
    elseif flag =~? '^-cword$'                 | let flags.cword     = 1
    elseif flag =~? '^-grepprg$'
      if args != ''
        if !exists('tool')
          let tool = s:options.tools[0]
        endif
        let flags.tools = [tool]
        let flags[tool] = copy(s:options[tool])
        let flags[tool].grepprg = args
      else
        echomsg 'Missing argument for: -grepprg'
      endif
      break
    elseif flag =~? '^-query$'
      if args != ''
        let flags.query = args
        let flags.prompt = 0
        break
      else
        " No warning message here. This allows for..
        " nnoremap ... :Grepper! -tool ag -query<space>
        " ..thus you get nicer file completion.
        break
      endif
    elseif flag =~? '^-tool$'
      let [tool, args] = s:split_one(args)
      if tool == ''
        echomsg 'Missing argument for: -tool'
        break
      endif
      if index(s:options.tools, tool) >= 0
        let flags.tools =
              \ [tool] + filter(copy(s:options.tools), 'v:val != tool')
      else
        echomsg 'No such tool: '. tool
      endif
    else
      echomsg 'Ignore unknown flag: '. flag
    endif

    let [flag, args] = s:split_one(args)
  endwhile

  return s:start(flags)
endfunction

" s:process_flags() {{{1
function! s:process_flags(flags)
  if a:flags.cword
    let a:flags.query = s:escape_query(a:flags, expand('<cword>'))
  endif

  if a:flags.prompt
    call s:prompt(a:flags)
    if empty(a:flags.query)
      let a:flags.query = s:escape_query(a:flags, expand('<cword>'))
    elseif a:flags.query =~# s:magic.esc
      return
    endif
  endif

  if a:flags.highlight
    call s:highlight_query(a:flags)
  endif

  call histadd('input', a:flags.query)
endfunction

" s:highlight_query() {{{1
function! s:highlight_query(flags)
  " Change Vim's '\'' to ' so it can be understood by /.
  let vim_query = substitute(a:flags.query, "'\\\\''", "'", 'g')

  " Remove surrounding quotes that denote a string.
  let start = vim_query[0]
  let end = vim_query[-1:-1]
  if start == end && start =~ "\['\"]"
    let vim_query = vim_query[1:-2]
  endif

  if a:flags.query_escaped
    let vim_query = s:unescape_query(a:flags, vim_query)
    let vim_query = escape(vim_query, '\')
    let vim_query = '\V'. vim_query
  else
    " \bfoo\b -> \<foo\> Assume only one pair.
    let vim_query = substitute(vim_query, '\v\\b(.{-})\\b', '\\<\1\\>', '')
    " *? -> \{-}
    let vim_query = substitute(vim_query, '*\\\=?', '\\{-}', 'g')
    " +? -> \{-1,}
    let vim_query = substitute(vim_query, '\\\=+\\\=?', '\\{-1,}', 'g')
    let vim_query = escape(vim_query, '+')
  endif

  let @/ = vim_query
  call histadd('search', vim_query)
  call feedkeys(":set hls\<bar>echo\<cr>", 'n')
endfunction

" s:unescape_query() {{{1
function! s:unescape_query(flags, query)
  let tool = s:get_current_tool(a:flags)
  let q = a:query
  if has_key(tool, 'escape')
    for c in reverse(split(tool.escape, '\zs'))
      let q = substitute(q, '\V\\'.c, c, 'g')
    endfor
  endif
  return q
endfunction

" s:start() {{{1
function! s:start(flags) abort
  if empty(s:options.tools)
    call s:error('No grep tool found!')
    return
  endif

  call s:process_flags(a:flags)

  if a:flags.query =~# s:magic.esc
    redraw!
    return
  endif

  return s:run(a:flags)
endfunction

" s:prompt() {{{1
function! s:prompt(flags)
  let tool = s:get_current_tool(a:flags)
  let mapping = maparg(s:options.next_tool, 'c', '', 1)
  execute 'cnoremap' s:options.next_tool s:magic.next .'<cr>'
  execute 'cnoremap <esc>' s:magic.esc .'<cr>'
  echohl Question
  call inputsave()

  try
    let a:flags.query = input(tool.grepprg .'> ', a:flags.query,
          \ 'customlist,grepper#complete_files')
  finally
    execute 'cunmap' s:options.next_tool
    call inputrestore()
    cunmap <esc>
    call s:restore_mapping(mapping)
    echohl NONE
  endtry

  if a:flags.query =~# s:magic.next
    call histdel('input', -1)
    call s:next_tool(a:flags)
    let a:flags.query = has_key(a:flags, 'query_orig')
          \ ? '-- '. s:escape_query(a:flags, a:flags.query_orig)
          \ : a:flags.query[:-len(s:magic.next)-1]
    return s:prompt(a:flags)
  elseif a:flags.query =~# s:magic.esc
    call histdel('input', -1)
  endif
endfunction

" s:build_cmdline() {{{1
function! s:build_cmdline(flags) abort
  let grepprg = s:get_current_tool(a:flags).grepprg
  let grepprg = substitute(grepprg, '\V$.', bufname(''), '')

  if stridx(grepprg, '$+') >= 0
    let buffers = filter(map(filter(range(1, bufnr('$')), 'bufloaded(v:val)'),
          \ 'bufname(v:val)'), 'filereadable(v:val)')
    let grepprg = substitute(grepprg, '\V$+', join(buffers), '')
  endif

  if stridx(grepprg, '$*') >= 0
    let grepprg = substitute(grepprg, '\V$*', escape(a:flags.query, '\&'), 'g')
  else
    let grepprg .= ' ' . a:flags.query
  endif

  return grepprg
endfunction

" s:run() {{{1
function! s:run(flags)
  let s:cmdline = s:build_cmdline(a:flags)

  " 'cmd' and 'options' are only used for async execution.
  " Use 'cat' for stripping escape sequences.
  if has('win32') && &shell =~ 'cmd'
    let cmd = s:cmdline
  else
    let cmd = ['sh', '-c', s:cmdline]
  endif

  let options = {
        \ 'cmd':       s:cmdline,
        \ 'flags':     a:flags,
        \ 'window':    winnr(),
        \ 'tabpage':   tabpagenr(),
        \ 'stdoutbuf': [],
        \ }

  call s:store_errorformat(a:flags)

  if has('nvim')
    if exists('s:id')
      silent! call jobstop(s:id)
    endif
    let s:id = jobstart(cmd, extend(options, {
          \ 'on_stdout': function('s:on_stdout_nvim'),
          \ 'on_stderr': function('s:on_stderr'),
          \ 'on_exit':   function('s:on_exit'),
          \ }))
  elseif !get(w:, 'testing') && (v:version > 704 || v:version == 704 && has('patch1967'))
        \ && a:flags.tools[0] !~# '\v(ack|pt|rg)'
    if exists('s:id')
      silent! call job_stop(s:id)
    endif
    let s:id = job_start(cmd, {
          \ 'err_io':   'out',
          \ 'out_cb':   function('s:on_stdout_vim', options),
          \ 'close_cb': function('s:on_exit', options),
          \ })
  else
    execute 'silent' (a:flags.quickfix ? 'cgetexpr' : 'lgetexpr') 'system(s:cmdline)'
    call s:finish_up(a:flags)
  endif
endfunction

" s:get_current_tool() {{{1
function! s:get_current_tool(flags) abort
  return a:flags[a:flags.tools[0]]
endfunction

" s:store_errorformat() {{{1
function! s:store_errorformat(flags) abort
  let prog = s:get_current_tool(a:flags)
  let s:errorformat = &errorformat
  let &errorformat = has_key(prog, 'grepformat') ? prog.grepformat : &errorformat
endfunction

" s:restore_errorformat() {{{1
function! s:restore_errorformat() abort
  let &errorformat = s:errorformat
endfunction

" s:restore_mapping() {{{1
function! s:restore_mapping(mapping)
  if !empty(a:mapping)
    execute printf('%s %s%s%s%s %s %s',
          \ (a:mapping.noremap ? 'cnoremap' : 'cmap'),
          \ (a:mapping.silent  ? '<silent>' : ''    ),
          \ (a:mapping.buffer  ? '<buffer>' : ''    ),
          \ (a:mapping.nowait  ? '<nowait>' : ''    ),
          \ (a:mapping.expr    ? '<expr>'   : ''    ),
          \  a:mapping.lhs,
          \  a:mapping.rhs)
  endif
endfunction

" s:finish_up() {{{1
function! s:finish_up(flags)
  let qf = a:flags.quickfix
  let list = qf ? getqflist() : getloclist(0)
  let size = len(list)

  call s:restore_errorformat()

  try
    let title = has('nvim') ? s:cmdline : {'title': s:cmdline}
    if qf
      call setqflist(list, 'r', title)
    else
      call setloclist(0, list, 'r', title)
    endif
  catch /E118/
  endtry

  if size == 0
    execute (qf ? 'cclose' : 'lclose')
    redraw
    echo 'No matches found.'
    return
  endif

  if a:flags.jump
    execute 'silent' (qf ? 'cfirst' : 'lfirst')
  endif

  " Also open if the list contains any invalid entry.
  if a:flags.open || !empty(filter(list, 'v:val.valid == 0'))
    execute (qf ? 'botright copen' : 'lopen') (size > 10 ? 10 : size)
    let w:quickfix_title = s:cmdline
    setlocal nowrap

    if !a:flags.switch
      call feedkeys("\<c-w>p", 'n')
    endif
  endif

  redraw
  echo printf('Found %d matches.', size)
  
  if exists('#User#Grepper')
    execute 'doautocmd' (s:has_doau_modeline ? '<nomodeline>' : '') 'User Grepper'
  endif
endfunction

" s:escape_query() {{{1
function! s:escape_query(flags, query)
  let tool = s:get_current_tool(a:flags)
  let a:flags.query_escaped = 1
  return shellescape(has_key(tool, 'escape')
        \ ? escape(a:query, tool.escape)
        \ : a:query)
endfunction

" s:next_tool() {{{1
function! s:next_tool(flags)
  let a:flags.tools = a:flags.tools[1:-1] + [a:flags.tools[0]]
endfunction

" #operator() {{{1
function! grepper#operator(type) abort
  let regsave = @@
  let selsave = &selection
  let &selection = 'inclusive'

  if a:type =~? 'v'
    silent execute "normal! gvy"
  elseif a:type == 'line'
    silent execute "normal! '[V']y"
  else
    silent execute "normal! `[v`]y"
  endif

  let &selection = selsave
  let flags = deepcopy(s:options)
  let flags.query_orig = @@
  let flags.query_escaped = 0
  let flags.query = '-- '. s:escape_query(flags, @@)
  let @@ = regsave

  return s:start(flags)
endfunction
