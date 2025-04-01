" --- Helper Functions ---

" Get the effective indent, handling empty lines by looking at the next line
function! s:GetEffectiveIndent(lnum) abort
    let max_lines = line('$')
    if a:lnum < 1 || a:lnum > max_lines
        return -1 " Invalid line number
    endif

    let line_content = getline(a:lnum)
    if line_content =~ '^\s*$'
        " Empty line: check indent of the line below it
        if a:lnum < max_lines
            return indent(a:lnum + 1)
        else
            return 0 " Empty line at EOF
        endif
    else
        " Non-empty line: use its own indent
        return indent(a:lnum)
    endif
endfunction

" Find the start line of the block containing start_lnum with target_indent
function! s:FindBlockStartLine(start_lnum, target_indent) abort
    let block_start_lnum = a:start_lnum
    let search_lnum = a:start_lnum
    while search_lnum >= 1
        let effective_indent_check = s:GetEffectiveIndent(search_lnum)
        if effective_indent_check == a:target_indent
            let block_start_lnum = search_lnum
            let search_lnum -= 1
        else
            break " Found line before the block
        endif
    endwhile
    return block_start_lnum
endfunction

" Find the end line of the block containing start_lnum with target_indent
function! s:FindBlockEndLine(start_lnum, target_indent) abort
    let max_lines = line('$')
    let block_end_lnum = a:start_lnum
    let search_lnum = a:start_lnum
    while search_lnum <= max_lines
        let effective_indent_check = s:GetEffectiveIndent(search_lnum)
        if effective_indent_check == a:target_indent
            let block_end_lnum = search_lnum
            let search_lnum += 1
        else
            break " Found line after the block
        endif
    endwhile
    return block_end_lnum
endfunction

" Find the last non-empty line within a given range (inclusive)
function! s:FindLastNonEmpty(start_lnum, end_lnum) abort
    for lnum in range(a:end_lnum, a:start_lnum, -1)
        if getline(lnum) !~ '^\s*$'
            return lnum
        endif
    endfor
    return -1 " No non-empty line found
endfunction

" --- End Helper Functions ---

" --- Movement Functions ---

" Move to the line before the beginning of the current indented block
function! indent_nav#MoveToBlockStart() abort
    let current_lnum = line('.')
    let target_indent = s:GetEffectiveIndent(current_lnum)
    echo target_indent

    " Do nothing if not in an indented block
    if target_indent <= 0
        " echo "Not in an indented block."
        return
    endif

    " Set the jump mark before moving
    normal! m'

    " Find the actual start line of the block
    let block_start_lnum = s:FindBlockStartLine(current_lnum, target_indent)
    echo block_start_lnum

    " Calculate the target line (line before the block start)
    let final_target_lnum = block_start_lnum - 1

    if final_target_lnum >= 1
        " Move to the beginning of the target line
        call cursor(final_target_lnum, 1)
        normal! ^ " Move to first non-blank
    else
        " Block started on line 1, move to line 1 instead
        call cursor(1, 1)
        normal! ^
        " echo "Block starts on line 1. Moved to line 1."
    endif
endfunction

" Move to the last non-empty line of the current indented block
function! indent_nav#MoveToBlockEnd() abort
    let current_lnum = line('.')
    let target_indent = s:GetEffectiveIndent(current_lnum)

    " Do nothing if not in an indented block
    if target_indent <= 0
        " echo "Not in an indented block."
        return
    endif

    " Set the jump mark before moving
    normal! m'

    " Find the full boundaries of the block the cursor is in
    let block_start_lnum = s:FindBlockStartLine(current_lnum, target_indent)
    let block_end_lnum = s:FindBlockEndLine(current_lnum, target_indent)

    " Find the last non-empty line within those boundaries
    let last_non_empty_match = s:FindLastNonEmpty(block_start_lnum, block_end_lnum)

    " Move to the last non-empty line found, if it's valid and not the current line
    if last_non_empty_match != -1 && last_non_empty_match != current_lnum
        call cursor(last_non_empty_match, 1)
        normal! ^ " Move to first non-blank
    elseif last_non_empty_match == -1
        " Fallback: Should not happen if target_indent > 0, but just in case
        " echo "Could not find end of block (no non-empty lines?)."
    else
        " Already on the last non-empty line or beyond. Do nothing.
        " echo "Already at the last non-empty line of the block."
    endif
endfunction

" Main function called by mappings
function! indent_nav#IndentBlockTextObject(type) abort
    let current_lnum = line('.')
    let target_indent = s:GetEffectiveIndent(current_lnum)

    " Don't operate if not in an indented block
    if target_indent <= 0
        " echo "Not in an indented block."
        return
    endif

    " Find the full block boundaries
    let block_start_lnum = s:FindBlockStartLine(current_lnum, target_indent)
    let block_end_lnum = s:FindBlockEndLine(current_lnum, target_indent)

    let final_start_lnum = block_start_lnum
    let final_end_lnum = block_end_lnum

    if a:type == 'i' " Inside block
        let first_non_empty = s:FindFirstNonEmpty(block_start_lnum, block_end_lnum)
        let last_non_empty = s:FindLastNonEmpty(block_start_lnum, block_end_lnum)

        if first_non_empty != -1 && last_non_empty != -1
            " Found non-empty lines, use them as boundaries
            let final_start_lnum = first_non_empty
            let final_end_lnum = last_non_empty
        else
            " Block contains only empty lines, 'inside' selects them all
            let final_start_lnum = block_start_lnum
            let final_end_lnum = block_end_lnum
        endif

    elseif a:type == 'a' " Around block
        " Use the full block boundaries found earlier
        let final_start_lnum = block_start_lnum
        let final_end_lnum = block_end_lnum
    else
        echoerr "Invalid type for IndentBlockTextObject: " . a:type
        return
    endif

    " --- Select the range ---
    " Get current mode (visual or operator-pending)
    let current_mode = mode()

    if current_mode ==# 'v' || current_mode ==# 'V' || current_mode ==# "\<C-v>"
        " Visual mode: Adjust selection boundaries
        " Keep track of original visual start to handle direction
        let original_visual_start_line = line("'<")
        let original_visual_end_line = line("'>")

        " Set new visual marks
        execute final_start_lnum . "normal! m<"
        execute final_end_lnum . "normal! m>"

        " Reselect based on original direction
        if original_visual_start_line <= original_visual_end_line
            normal! `<V`>
        else
            normal! `>V`<
        endif

    elseif current_mode ==# 'o'
        " Operator-pending mode: Visually select the range for the operator
        " Set the marks Vim uses for the operator range
        execute final_start_lnum . "normal! m<"
        execute final_end_lnum . "normal! m>"
        " Enter linewise visual mode covering the desired lines
        normal! V
        " Note: Vim automatically applies the pending operator to the visual selection
    else
        " Should not happen if mappings are correct
        echoerr "IndentBlockTextObject called from unexpected mode: " . current_mode
    endif

endfunction

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
