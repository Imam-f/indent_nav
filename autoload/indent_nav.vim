" --- Helper Functions (Script-Local) ---
" Get the effective indent, handling empty lines by looking forward
" for the next non-empty line.
function! s:GetEffectiveIndent(lnum) abort
    let max_lines = line('$')
    if a:lnum < 1 || a:lnum > max_lines
        return -1 " Invalid line number
    endif

    let current_line_content = getline(a:lnum)

    if current_line_content !~ '^\s*$'
        " Current line is not empty, use its indent directly
        return indent(a:lnum)
    else
        " Current line IS empty. Find the next non-empty line's indent.
        let next_lnum = a:lnum + 1
        while next_lnum <= max_lines
            let next_line_content = getline(next_lnum)
            if next_line_content !~ '^\s*$'
                " Found a non-empty line, use its indent
                return indent(next_lnum)
            endif
            let next_lnum += 1
        endwhile
        " Reached EOF without finding a non-empty line below the empty one
        return 0
    endif
endfunction

" Find the start line of the block containing start_lnum.
" A block includes lines with effective indent >= target_indent.
" Searches upwards.
function! s:FindBlockStartLine(start_lnum, target_indent) abort
    let block_start_lnum = a:start_lnum
    let search_lnum = a:start_lnum
    while search_lnum >= 1
        let effective_indent_check = s:GetEffectiveIndent(search_lnum)
        " MODIFIED: Check if indent is GREATER THAN OR EQUAL TO target
        if effective_indent_check >= a:target_indent && effective_indent_check >= 0 " Ensure valid indent
            let block_start_lnum = search_lnum
            let search_lnum -= 1
        else
            " Found line before the block (indent < target_indent or invalid line)
            break
        endif
    endwhile
    return block_start_lnum
endfunction

" Find the end line of the block containing start_lnum.
" A block includes lines with effective indent >= target_indent.
" Searches downwards.
function! s:FindBlockEndLine(start_lnum, target_indent) abort
    let max_lines = line('$')
    let block_end_lnum = a:start_lnum
    let search_lnum = a:start_lnum
    while search_lnum <= max_lines
        let effective_indent_check = s:GetEffectiveIndent(search_lnum)
         " MODIFIED: Check if indent is GREATER THAN OR EQUAL TO target
        if effective_indent_check >= a:target_indent && effective_indent_check >= 0 " Ensure valid indent
            let block_end_lnum = search_lnum
            let search_lnum += 1
        else
            " Found line after the block (indent < target_indent or invalid line)
            break
        endif
    endwhile
    return block_end_lnum
endfunction

" Find the first non-empty line in a range
function! s:FindFirstNonEmpty(start_lnum, end_lnum) abort
    for lnum in range(a:start_lnum, a:end_lnum)
        if getline(lnum) !~ '^\s*$'
            return lnum
        endif
    endfor
    return -1 " No non-empty line found
endfunction

" Find the last non-empty line in a range
function! s:FindLastNonEmpty(start_lnum, end_lnum) abort
    for lnum in range(a:end_lnum, a:start_lnum, -1)
        if getline(lnum) !~ '^\s*$'
            return lnum
        endif
    endfor
    return -1 " No non-empty line found
endfunction

" --- Public API Functions (Autoloaded) ---

function! indent_nav#MoveToBlockStart() abort
    let current_lnum = line('.')
    let target_indent = s:GetEffectiveIndent(current_lnum)

    " Do nothing if not in an indented block (target indent must be > 0)
    if target_indent <= 0
        return
    endif

    " Find the actual start line of the block (using modified helper)
    let block_start_lnum = s:FindBlockStartLine(current_lnum, target_indent)

    " Calculate the target line (line before the block start)
    let final_target_lnum = block_start_lnum

    if final_target_lnum >= 1
        call cursor(final_target_lnum, 1)
        normal! ^ " Move to first non-blank
    else
        call cursor(1, 1)
        normal! ^
    endif
endfunction

function! indent_nav#MoveToBlockEnd() abort
    let current_lnum = line('.')
    let target_indent = s:GetEffectiveIndent(current_lnum)

    " Do nothing if not in an indented block (target indent must be > 0)
    if target_indent <= 0
        return
    endif

    " Set the jump mark before moving
    normal! m'

    " Find the full boundaries of the block the cursor is in (using modified helpers)
    let block_start_lnum = s:FindBlockStartLine(current_lnum, target_indent)
    let block_end_lnum = s:FindBlockEndLine(current_lnum, target_indent)

    " Find the last non-empty line within those boundaries
    let last_non_empty_match = s:FindLastNonEmpty(block_start_lnum, block_end_lnum)

    " Move to the last non-empty line found, if it's valid and not the current line
    if last_non_empty_match != -1 && last_non_empty_match != current_lnum
        call cursor(last_non_empty_match, 1)
        normal! ^ " Move to first non-blank
    elseif last_non_empty_match == -1
        " Block contains only empty lines. Move to the end of the block.
        if block_end_lnum != current_lnum
             call cursor(block_end_lnum, 1)
             normal! ^
        endif
    endif
    " If already on the last non-empty line, do nothing.
endfunction

function! indent_nav#IndentBlockTextObject(type) abort
    " Get current cursor position
    let current_lnum = line('.')
    let target_indent = s:GetEffectiveIndent(current_lnum)

    " Do nothing if not in an indented block
    if target_indent <= 0
        return
    endif

    " Find the block boundaries
    let block_start_lnum = s:FindBlockStartLine(current_lnum, target_indent)
    let block_end_lnum = s:FindBlockEndLine(current_lnum, target_indent)

    let block_start_lnum -= 1
    let final_start_lnum = block_start_lnum
    let final_end_lnum = block_end_lnum

    if a:type == 'i' " Inside block
        let block_start_lnum = block_start_lnum + 1
        let first_non_empty = s:FindFirstNonEmpty(block_start_lnum, block_end_lnum)
        let last_non_empty = s:FindLastNonEmpty(block_start_lnum, block_end_lnum)

        if first_non_empty != -1 && last_non_empty != -1
            let final_start_lnum = first_non_empty
            let final_end_lnum = last_non_empty
        endif
        " If only empty lines, use the whole block (already set)
    endif

    " Convert to character positions - start of first line to end of last line
    let start_pos = [0, final_start_lnum, 1, 0]
    let end_pos = [0, final_end_lnum, len(getline(final_end_lnum)) + 1, 0]
    
    " Set the `'<` and `'>` marks directly
    call setpos("'<", start_pos)
    call setpos("'>", end_pos)
    
    " Enter visual line mode
    normal! `<V`>
endfunction
" vim: sw=4 et ts=4
" --- End Movement Functions ---


" --- Optional Mappings ---
" Place these after the function definitions

" Map <Leader>bb to move to block start
" nnoremap <silent> <leader>bb :call MoveToBlockStart()<CR>

" Map <Leader>be to move to block end
" nnoremap <silent> <leader>be :call MoveToBlockEnd()<CR>




" Use <silent> to prevent the command from being echoed
" Use noremap to avoid recursive mapping issues

" Operator-pending mode mappings (for d, c, y, etc.)
" onoremap <silent> ii :<C-U>call IndentBlockTextObject('i')<CR>
" onoremap <silent> ai :<C-U>call IndentBlockTextObject('a')<CR>

" Visual mode mappings (for v)
" xnoremap <silent> ii :<C-U>call IndentBlockTextObject('i')<CR>
" xnoremap <silent> ai :<C-U>call IndentBlockTextObject('a')<CR>

" Optional: Normal mode mappings (e.g., vii, vai directly)
" These are less standard but possible if you prefer them over v i i
" nnoremap vii <Cmd>call IndentBlockTextObject('i')<CR>
" nnoremap vai <Cmd>call IndentBlockTextObject('a')<CR>
