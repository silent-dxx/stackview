if !has("python")
    echo "vim has to be compiled with +python3 to run this"
    finish
endif

if exists('g:loaded_stackview_plugin')
    finish
endif

" the rest of plugin VimL code goes here
let g:loaded_stackview_plugin = 1

let s:plugin_root_dir = fnamemodify(resolve(expand('<sfile>:p')), ':h')

python << EOF
import sys
from os.path import normpath, join
import vim
plugin_root_dir = vim.eval('s:plugin_root_dir')
python_root_dir = normpath(join(plugin_root_dir, '..', 'python'))
sys.path.insert(0, python_root_dir)
from gdbmi_utils import *
EOF

let StackView_title = "__StackView_List__"
let s:StackView_bufnum = 0

"FUNCTION: s:bufInWindows(bnum)
"Determine the number of windows open to this buffer number.
"Care of Yegappan Lakshman.  Thanks!
"
"Args:
"bnum: the subject buffers buffer number
function! s:bufInWindows(bnum)
    let cnt = 0
    let winnum = 1
    while 1
        let bufnum = winbufnr(winnum)
        if bufnum < 0
            break
        endif
        if bufnum == a:bnum
            let cnt = cnt + 1
        endif
        let winnum = winnum + 1
    endwhile

    return cnt
endfunction

"FUNCTION: s:isWindowUsable(winnumber)
"Returns 1 if opening a file from the tree in the given window requires it to
"be split
"
"Args:
"winnumber: the number of the window in question
function! s:isWindowUsable(winnumber)
    "gotta split if theres only one window (i.e. the NERD tree)
    if winnr("$") == 1
        return 0
    endif

    let oldwinnr = winnr()
    exec a:winnumber . "wincmd p"
    let specialWindow = getbufvar("%", '&buftype') != '' || getwinvar('%', '&previewwindow')
    let modified = &modified
    exec oldwinnr . "wincmd p"

    "if its a special window e.g. quickfix or another explorer plugin then we
    "have to split
    if specialWindow
        return 0
    endif

    if &hidden
        return 1
    endif

    return !modified || s:bufInWindows(winbufnr(a:winnumber)) >= 2
endfunction

"FUNCTION: s:firstNormalWindow()
"find the window number of the first normal window
function! s:firstNormalWindow()
    let i = 1
    while i <= winnr("$")
        let bnum = winbufnr(i)
        if bnum != -1 && getbufvar(bnum, '&buftype') == ''
                    \ && !getwinvar(i, '&previewwindow')
            return i
        endif

        let i += 1
    endwhile
    return -1
endfunction

" StackView_Open_Window
" Create a new window. If it is already open, clear it
function! s:StackView_Open_Window()

    " Cleanup the window listing, if the window is open
    let winnum = bufwinnr(g:StackView_title)
    if winnum != -1
        " Jump to the existing window
        if winnr() != winnum
            exe winnum . 'wincmd w'
        endif
    else
        " If the tag listing temporary buffer already exists, then reuse it.
        " Otherwise create a new buffer
        let bufnum = bufnr(g:StackView_title)
        if bufnum == -1
            " Create a new buffer
            let wcmd = g:StackView_title
        else
            " Edit the existing buffer
            let wcmd = '+buffer' . bufnum
        endif

        let s:StackView_bufnum = bufnum

        " Create the window
        exe 'silent! ' . 'topleft vertical 30 new ' . wcmd

    endif
endfunction

" StackView_Cleanup()
" Cleanup all the window variables.
function! s:StackView_Cleanup()
    if has('syntax')
        silent! syntax clear StackViewTitle
    endif
    match none

    if exists('b:tlist_wp_count') && b:tlist_wp_count != ''
        let line_num = 0
        while line_num < b:tlist_wp_count
            let item_index = 0
            while item_index < b:tlist_fp_{line_num}_count
                unlet! b:tlist_fp_{line_num}_{item_index}_fullname
                unlet! b:tlist_fp_{line_num}_{item_index}_line
                let item_index = item_index + 1
            endwhile
            unlet! b:tlist_fp_{line_num}_list
            let line_num = line_num + 1
        endwhile
    endif

    unlet! b:tlist_wp_start
    unlet! b:tlist_wp_count
    unlet! b:tlist_wp_list
endfunction

" StackView_Init_Window
" Set the default options for the window
function! s:StackView_Init_Window(filename)
    " Set report option to a huge value to prevent informations messages
    " while deleting the lines
    let old_report = &report
    set report=99999

    " Mark the buffer as modifiable
    setlocal modifiable

    " Delete the contents of the buffer to the black-hole register
    silent! %delete _

    " Mark the buffer as not modifiable
    setlocal nomodifiable

    " Restore the report option
    let &report = old_report

    " Clean up all the old variables used for the last filetype
    call <SID>StackView_Cleanup()

    " Mark the buffer as modifiable
    setlocal modifiable

    call append(0, '" StackView')
    let txt = fnamemodify(a:filename, ':t') . ' (' .
                \ fnamemodify(a:filename, ':p:h') . ')'
    silent! put! =txt

    " Mark the buffer as not modifiable
    setlocal nomodifiable

    " Highlight the comments
    if has('syntax')
        syntax match StackViewComment '^" .*'
        syntax match StackViewFileName '^[^" ].*$'

        " Colors to highlight comments and titles
        highlight clear StackViewComment
        highlight link StackViewComment Comment
        highlight clear StackViewTitle
        highlight link StackViewTitle Title
        if hlexists('MyStackViewFileName')
            highlight link StackViewFileName MyStackViewFileName
        else
            highlight clear StackViewFileName
            highlight default StackViewFileName guibg=Grey ctermbg=darkgray
                        \ guifg=white ctermfg=white
        endif
    endif

    " Folding related settings
    if has('folding')
        setlocal foldenable
        setlocal foldmethod=manual
        setlocal foldcolumn=2
        setlocal foldtext=v:folddashes.getline(v:foldstart)
    endif

    " Mark buffer as scratch
    silent! setlocal buftype=nofile
    silent! setlocal bufhidden=delete
    silent! setlocal noswapfile
    " Due to a bug in Vim 6.0, the winbufnr() function fails for unlisted
    " buffers. So if the list buffer is unlisted, multiple list
    " windows will be opened. This bug is fixed in Vim 6.1 and above
    if v:version >= 601
        silent! setlocal nobuflisted
    endif

    silent! setlocal nowrap

    " If the 'number' option is set in the source window, it will affect the
    " list window. So forcefully disable 'number' option for the list
    " window
    silent! setlocal nonumber

    silent! setlocal winfixwidth

    silent! setlocal nospell
    iabc <buffer>

    nnoremap <buffer> <silent> <2-LeftMouse> :call <SID>StackView_Jump_To_Tag(0)<CR>
endfunction

function! s:StackView_Window_Refresh(bkfile)
    " Mark the buffer as modifiable
    setlocal modifiable
    normal! ggdG
    " Mark the buffer as not modifiable
    setlocal nomodifiable

    " Initialize the list window
    call s:StackView_Init_Window(a:bkfile)

    " List the tags defined in a file
    call s:StackView_Explore_File(a:bkfile)
endfunction

" StackView_Explore_File()
" List the tags defined in the specified file in a Vim window
function! s:StackView_Explore_File(filename)
    let bufnum = s:StackView_bufnum

    let ftype = fnamemodify(a:filename, ':e')

    " Check for valid filename and valid filetype
    if a:filename == '' || !filereadable(a:filename) || ftype == ''
        return
    endif

    " Set report option to a huge value to prevent informational messages
    " while adding lines to the list window
    let old_report = &report
    set report=99999

    " Mark the buffer as modifiable
    setlocal modifiable

    if !exists('b:curr_wp_select')
        let b:curr_wp_select = 0
    endif

    call LoadConfig(a:filename)

    silent! put ='focus'
    let b:tlist_wp_start = line('.')
    silent! put = b:tlist_wp_list

    " create a fold for focus
    if has('folding')
        let fold_start = b:tlist_wp_start
        let fold_end = fold_start + b:tlist_wp_count
        exe fold_start . ',' . fold_end  . 'fold'
    endif

    " Syntax highlight the focus names
    if has('syntax')
        exe 'syntax match StackViewTitle /\%' . b:tlist_wp_start . 'l.*/'
    endif

    silent! put =''

    let b:tlist_fp_start = line('.') + 1
    silent! put ='stack_list'
    silent! put = b:tlist_fp_{b:curr_wp_select}_list

    " create a fold for stack_list
    if has('folding')
        let fold_start = b:tlist_fp_start
        let fold_end = fold_start + b:tlist_fp_{b:curr_wp_select}_count
        exe fold_start . ',' . fold_end  . 'fold'
    endif

    " Syntax highlight the stack_list names
    if has('syntax')
        exe 'syntax match StackViewTitle /\%' . b:tlist_fp_start . 'l.*/'
    endif

    normal! Gdd

    " Mark the buffer as not modifiable
    setlocal nomodifiable

    " Restore the report option
    let &report = old_report

    " Initially open all the folds
    if has('folding')
        silent! %foldopen!
    endif

    " Goto the first line in the buffer
    go

    return
endfunction

" StackView_Toggle_Window()
" Open a StackView window
function! s:StackView_Toggle_Window(bkfile)
    if a:bkfile == ""
        echo 'Please specify a file[*.bkpt] path!'
        return
    endif

    let curline = line('.')

    " If list window is open then close it.
    let winnum = bufwinnr(g:StackView_title)
    if winnum != -1
        if winnr() == winnum
            " Already in the list window. Close it and return
            close
        else
            " Goto the list window, close it and then come back to the
            " original window
            let curbufnr = bufnr('%')
            exe winnum . 'wincmd w'
            close
            " Need to jump back to the original window only if we are not
            " already in that window
            let winnum = bufwinnr(curbufnr)
            if winnr() != winnum
                exe winnum . 'wincmd w'
            endif
        endif
        return
    endif

    " Open the list window
    call s:StackView_Open_Window()

    " Initialize the list window
    call s:StackView_Init_Window(a:bkfile)

    " List the tags defined in a file
    call s:StackView_Explore_File(a:bkfile)
endfunction

" StackView_Jump_To_Tag()
" Jump to the location of the current tag
function! s:StackView_Jump_To_Tag(new_window)
    " Do not process comment lines and empty lines
    let curline = line('.') - 1

    if curline >= b:tlist_fp_start
        let l:tag_num = curline - b:tlist_fp_start
        let l:tag_fullname = b:tlist_fp_{b:curr_wp_select}_{l:tag_num}_fullname
        let l:tag_line = b:tlist_fp_{b:curr_wp_select}_{l:tag_num}_line

        if !s:isWindowUsable(winnr("#"))
            exec s:firstNormalWindow() . "wincmd w"
        else
            wincmd p
        endif

        exec ("edit " . l:tag_fullname)

        " Jump to the tag
        silent call cursor(l:tag_line, 0)
    elseif curline >= b:tlist_wp_start && curline < b:tlist_wp_start + b:tlist_wp_count
        let b:curr_wp_select = curline - b:tlist_wp_start
        call s:StackView_Window_Refresh(s:stackview_config_path)
    else
        return
    endif

endfunction

function! LoadConfig(filename)
    let s:stackview_config_path = a:filename
    python load_config()
endfunction

command! -n=? -complete=file StackView :call s:StackView_Toggle_Window('<args>')
