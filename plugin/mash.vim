" mash.vim - jump around your code
" Maintainer: Max Zwerin
" Version:    1.1

if exists('g:loaded_mash') | finish | endif
let g:loaded_mash = 1

function! s:open_label_popup(text, row, col) abort
    if has('nvim')
        let buf = nvim_create_buf(0, 1)
        call nvim_buf_set_lines(buf, 0, -1, 1, [a:text])
        let id = nvim_open_win(buf, 0, {
            \ 'relative': 'editor',
            \ 'row':       a:row - 1,
            \ 'col':       a:col - 1,
            \ 'width':     1,
            \ 'height':    1,
            \ 'style':     'minimal',
            \ 'focusable': 0,
        \ })
        call nvim_win_set_option(id, 'winhl', 'Normal:MashLabel')
        return id
    else
        return popup_create(a:text, {
            \ 'line':      a:row,
            \ 'col':       a:col,
            \ 'highlight': 'MashLabel',
            \ 'zindex':    200,
            \ 'fixed':     1,
            \ 'wrap':      0,
        \ })
    endif
endfunction

function! s:close_popup(id) abort
    if has('nvim')
        call nvim_win_close(a:id, 1)
    else
        call popup_close(a:id)
    endif
endfunction

let s:labels = 'asdfghjklqwertyuiopzxcvbnmASDFGHJKLQWERTYUIOPZXCVBNM'

let s:st = {
    \ 'active':         0,
    \ 'search_text':    '',
    \ 'original_bufnr': 0,
    \ 'original_winid': 0,
    \ 'matches':        {},
    \ 'match_ids':      [],
    \ 'popup_ids':      [],
\ }

function! s:setup_hl() abort
    hi default link MashBackdrop Comment
    hi default link MashMatch    Search
    hi default link MashLabel    Substitute
endfunction

function! s:clear_visual() abort
    for id in s:st.match_ids
        try | call matchdelete(id) | catch | endtry
    endfor
    let s:st.match_ids = []

    for pid in s:st.popup_ids
        try | call s:close_popup(pid) | catch | endtry
    endfor
    let s:st.popup_ids = []
endfunction

function! s:apply_backdrop() abort
    call add(s:st.match_ids, matchadd('MashBackdrop', '.*', -1))
endfunction

function! s:visible_lines() abort
    let info = getwininfo(s:st.original_winid)
    return empty(info) ? [1, 1] : [info[0].topline, info[0].botline]
endfunction

function! s:search_and_highlight() abort
    call s:clear_visual()
    call s:apply_backdrop()

    if s:st.search_text ==# '' | return | endif

    " Highlight every match
    call add(s:st.match_ids,
        \ matchadd('MashMatch', '\V' . escape(s:st.search_text, '\'), 0))

    " Collect all match positions in the visible region
    let [top, bot] = s:visible_lines()
    let raw = []
    for lnum in range(top, bot)
        let txt = get(getbufline(s:st.original_bufnr, lnum), 0, '')
        if txt ==# '' | continue | endif
        let start = 0
        while 1
            let found = stridx(txt, s:st.search_text, start)
            if found < 0 | break | endif
            call add(raw, {
                \ 'line':      lnum,
                \ 'start_col': found,
                \ 'end_col':   found + len(s:st.search_text),
                \ 'line_text': txt,
            \ })
            let start = found + 1
        endwhile
    endfor

    " Collect the character immediately after each match
    " Labels that equal a duck are skipped to avoid mis-fires
    let ducks = []
    for m in raw
        if m.end_col < len(m.line_text)
            call add(ducks, tolower(m.line_text[m.end_col]))
        endif
    endfor

    " Assign one label per match and create a floating popup for it
    let s:st.matches = {}
    let lidx = 0

    for m in raw
        " Find the next label not shadowed by a duck
        let label = ''
        while lidx < len(s:labels)
            let c = s:labels[lidx]
            let lidx += 1
            if index(ducks, tolower(c)) < 0
                let label = c
                break
            endif
        endwhile
        if label ==# '' | break | endif

        let m.label = label
        let s:st.matches[label] = m

        " screenpos() gives the screen row/col for buffer lnum/col (1-based col)
        let sp = screenpos(s:st.original_winid, m.line, m.end_col + 1)
        if sp.row > 0 && sp.col > 0
            call add(s:st.popup_ids, s:open_label_popup(label, sp.row, sp.col))
        endif
    endfor
endfunction

function! s:jump_to_label(label) abort
    let m = s:st.matches[a:label]
    call win_gotoid(s:st.original_winid)
    call cursor(m.line, m.start_col + 1)
    call s:cleanup()
endfunction

function! s:cleanup() abort
    call s:clear_visual()
    let s:st.active      = 0
    let s:st.search_text = ''
    let s:st.matches     = {}
    echo ''
    redraw
endfunction

function! s:jump() abort
    if s:st.active | return | endif

    let s:st.active         = 1
    let s:st.original_bufnr = bufnr('%')
    let s:st.original_winid = win_getid()
    let s:st.search_text    = ''
    let s:st.matches        = {}

    call s:apply_backdrop()
    redraw
    echo '> '

    while 1
        let c = getcharstr()
        if c == "\<Esc>" || c == "\<C-c>" || c == "\<CR>"
            call s:cleanup()
            break
        elseif c == "\<Del>" || c == "\<BS>"
            if len(s:st.search_text) > 0
                let s:st.search_text = s:st.search_text[:-2]
                call s:search_and_highlight()
                redraw
                echo '> ' . s:st.search_text
            endif
            continue
        endif
            
        if s:st.search_text !=# '' && has_key(s:st.matches, c)
            call s:jump_to_label(c)
            break
        endif

        " Otherwise grow the search string
        let s:st.search_text .= c
        call s:search_and_highlight()

        " Auto-jump when exactly one match remains
        if len(s:st.matches) == 1
            call s:jump_to_label(keys(s:st.matches)[0])
            break
        endif

        redraw
        echo '> ' . s:st.search_text
    endwhile
endfunction

call s:setup_hl()
nnoremap <silent> <Plug>MashJump :call <SID>jump()<CR>

if !hasmapto('<Plug>MashJump') || maparg('<C-f>', 'n') ==# ''
    nmap <C-f> <Plug>MashJump
endif
