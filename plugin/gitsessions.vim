" gitsessions.vim - auto save/load vim sessions based on git branches
" Maintainer:       William Ting <io at williamting.com>
" Site:             https://github.com/wting/gitsessions.vim

" SETUP

if exists('g:loaded_gitsessions') || v:version < 700 || &cp
    finish
endif
let g:loaded_gitsessions = 1

function! s:rtrim_slashes(string)
    return substitute(a:string, '[/\\]$', '', '')
endfunction

" fix for Windows users (https://github.com/wting/gitsessions.vim/issues/2)
if !exists('g:VIMFILESDIR')
    let g:VIMFILESDIR = has('unix') ? $HOME . '/.vim/' : $VIM . '/vimfiles/'
endif

" sessions save path
if !exists('g:gitsessions_dir')
    let g:gitsessions_dir = 'sessions'
else
    let g:gitsessions_dir = s:rtrim_slashes(g:gitsessions_dir)
endif

if !exists('g:gitsessions_addressed_path')
  let g:gitsessions_addressed_path = 1
endif

if !exists('g:gitsessions_reload_vimrc')
  let g:gitsessions_reload_vimrc = 0
endif

" Cache session file
" Pros: performance gain (x100) on large repositories
" Cons: switch between git branches will be missed from GitSessionUpdate()
" 	You are advised to save it manually by calling to GitSessionSave()
" Default - cache disabled
if !exists('g:gitsessions_use_cache')
    let g:gitsessions_use_cache = 1
endif

" used to control auto-save behavior
if !exists('s:session_exist')
    let s:session_exist = 0
endif

" HELPER FUNCTIONS

function! s:replace_bad_chars(string)
    return substitute(a:string, '/', '_', 'g')
endfunction

function! s:trim(string)
    return substitute(substitute(a:string, '^\s*\(.\{-}\)\s*$', '\1', ''), '\n', '', '')
endfunction

function! s:git_branch_name()
    return s:replace_bad_chars(s:trim(system("cd ". g:gitsessions_dir .";\git symbolic-ref --short HEAD;cd -;")))
endfunction

function! s:in_git_repo()
    let l:is_git_repo = system("\git rev-parse --git-dir >/dev/null")
    return v:shell_error == 0

endfunction

function! s:os_sep()
    " TODO(wting|2013-12-29): untested for Windows gvim
    return has('unix') ? '/' : '\'
endfunction

function! s:is_abs_path(path)
    return a:path[0] == s:os_sep()
endfunction

" LOGIC FUNCTIONS

function! s:parent_dir(path)
    let l:sep = s:os_sep()
    let l:front = s:is_abs_path(a:path) ? l:sep : ''
    return l:front . join(split(a:path, l:sep)[:-2], l:sep)
endfunction

function! s:find_git_dir(dir)
    if isdirectory(a:dir . '/.git')
        return a:dir . '/.git'
    elseif has('file_in_path') && has('path_extra')
        return finddir('.git', a:dir . ';')
    else
        return s:find_git_dir_aux(a:dir)
    endif
endfunction

function! s:find_git_dir_aux(dir)
    return isdirectory(a:dir . '/.git') ? a:dir . '/.git' : s:find_git_dir_aux(s:parent_dir(a:dir))
endfunction

function! s:find_project_dir(dir)
    return s:parent_dir(s:find_git_dir(a:dir))
endfunction

function! s:session_path(sdir, pdir)
    let l:path = a:sdir . (g:gitsessions_addressed_path ? a:pdir : '')
    return s:is_abs_path(a:sdir) ? l:path : g:VIMFILESDIR . l:path
endfunction

function! s:session_dir()
    if s:in_git_repo()
        return s:session_path(g:gitsessions_dir, s:find_project_dir(getcwd()))
    else
        return s:session_path(g:gitsessions_dir, getcwd())
    endif
endfunction

function! s:session_file(invalidate_cache)
    if g:gitsessions_use_cache && !a:invalidate_cache && exists('s:cached_session_file')
        return s:cached_session_file
    endif
    let l:dir = s:session_dir()
    let l:branch = s:git_branch_name()
    if exists('s:cached_session_file')
        unlet s:cached_session_file
    endif
    let s:cached_session_file = (empty(l:branch)) ? l:dir . '/master' : l:dir . '/' . l:branch
    return s:cached_session_file
endfunction

function! s:undo_dir()
    if exists('g:gitsessions_undo_dir') && g:gitsessions_undo_dir != '0'
      if !isdirectory(g:gitsessions_undo_dir)
        call mkdir(g:gitsessions_undo_dir)
      endif
      execute 'set undodir='.resolve(g:gitsessions_undo_dir)
      set undofile
    endif
endfunction

" PUBLIC FUNCTIONS

function! g:GitSessionSave()
    if !s:in_git_repo()
        echoerr "not in git repo"
        return
    endif
    let l:dir = s:session_dir()
    let l:file = s:session_file(1)

    if !empty(l:dir) && !isdirectory(l:dir)
        call mkdir(l:dir, 'p')

        if !isdirectory(l:dir)
            echoerr "cannot create directory:" l:dir
            return
        endif
    endif

    if isdirectory(l:dir) && (filewritable(l:dir) != 2)
        echoerr "cannot write to:" l:dir
        return
    endif

    let s:session_exist = 1
    let lines = []

    call s:undo_dir()
    call xolox#session#save_session(lines, l:file)
    if filereadable(l:file)
        call writefile(lines, l:file)
        echom "session updated:" l:file
    else
        call writefile(lines, l:file, "s")
        echom "session saved:" l:file
    endif
    redrawstatus!
endfunction

function! g:GitSessionUpdate(...)
    let l:show_msg = a:0 > 0 ? a:1 : 1
    let l:file = s:session_file(0)

    if s:session_exist && filereadable(l:file)
        call s:undo_dir()
        let lines = []
        call xolox#session#save_session(lines, l:file)
        call writefile(lines, l:file)
        if l:show_msg
            echom "session updated:" l:file
        endif
    endif
endfunction

function! g:GitSessionLoad(...)
    if argc() != 0
        return
    endif

    let l:show_msg = a:0 > 0 ? a:1 : 0
    let l:file = s:session_file(1)

    if filereadable(l:file)
        call s:undo_dir()
        let s:session_exist = 1
        execute 'source' l:file
        if g:gitsessions_reload_vimrc
          execute 'source' $MYVIMRC
        endif
        echom "session loaded:" l:file
    elseif l:show_msg
        echom "session not found:" l:file
    endif
    redrawstatus!
endfunction

function! g:GitSessionDelete()
    " Delete is a tricky case, we still need to use cached version if any.
    " This version was used and saved by GitSessionUpdate(), however
    " we should ensure that session cached variable is cleared.
    let l:file = s:session_file(1)
    let s:session_exist = 0
    if exists('s:cached_session_file')
        unlet s:cached_session_file
    endif
    if filereadable(l:file)
        call delete(l:file)
        echom "session deleted:" l:file
    endif
endfunction

augroup gitsessions
    autocmd!
    if ! exists("g:gitsessions_disable_auto_load")
        if exists("g:gitsessions_use_nested_load")
            autocmd VimEnter * nested :call g:GitSessionLoad()
        else
            autocmd VimEnter * :call g:GitSessionLoad()
        endif
    endif
    " autocmd BufEnter * :call g:GitSessionUpdate(0)
    autocmd VimLeave * :call g:GitSessionUpdate()
augroup END

command GitSessionSave call g:GitSessionSave()
command GitSessionLoad call g:GitSessionLoad(1)
command GitSessionDelete call g:GitSessionDelete()
