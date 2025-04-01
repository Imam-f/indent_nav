" Prevent loading mappings multiple times
if exists('g:loaded_indent_nav_mappings')
    finish
endif
let g:loaded_indent_nav_mappings = 1
