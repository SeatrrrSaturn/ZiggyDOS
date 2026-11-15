; =============================================================================
;  ZiggyDOS - path handling
;  Turns "DOC\README.TXT", "\SUB", ".." or "." into a directory entry, and
;  parses 8.3 file names exactly the way DOS does.
; =============================================================================

; ---------------------------------------------------------------------------
;  upper_char - fold AL to upper case
; ---------------------------------------------------------------------------
upper_char:
    cmp al, 'a'
    jb .done
    cmp al, 'z'
    ja .done
    sub al, 32
.done:
    ret

; ---------------------------------------------------------------------------
;  name_to_83
;    in : DS:SI -> name like "readme.txt"
;    out: chi_name filled with 11 upper case bytes, CF = 1 when invalid
; ---------------------------------------------------------------------------
name_to_83:
    cld
    push ax
    push bx
    push cx
    push di
    push es
    push ds
    pop es                       ; STOSB writes through ES:DI
    mov di, chi_name
    mov cx, 11
    mov al, ' '                   ; FAT names are padded with spaces
    rep stosb
    mov bx, chi_name
    xor di, di
.name_loop:
    mov al, [si]
    test al, al
    jz .after_name
    cmp al, '.'
    je .ext_begin
    cmp al, 0x5C
    je .invalid
    cmp al, '/'
    je .invalid
    cmp al, ' '
    je .after_name
    cmp di, 8
    jae .invalid
    inc si
    call upper_char
    mov [bx+di], al
    inc di
    jmp .name_loop
.ext_begin:
    inc si
    mov bx, chi_name+8
    xor di, di
.ext_loop:
    mov al, [si]
    test al, al
    jz .after_name
    cmp al, 0x5C
    je .invalid
    cmp al, '/'
    je .invalid
    cmp al, ' '
    je .after_name
    cmp di, 3
    jae .invalid
    inc si
    call upper_char
    mov [bx+di], al
    inc di
    jmp .ext_loop
.after_name:
    cmp byte [chi_name], ' '
    je .invalid                   ; empty file name
    clc
    jmp .done
.invalid:
    stc
.done:
    pop es
    pop di
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
;  resolve_path
;    in : DS:SI -> path string
;    out: CF = 0 on success, with
;           rp_dir        cluster of the directory that owns the entry
;           rp_entry_off  entry offset inside the loaded directory buffer
;                         (0xFFFF when the path names the directory itself)
;           rp_cluster    cluster of the target (file or directory)
;           rp_attr       attribute byte
;           rp_size       size in bytes
;           rp_self       1 when the path resolves to a directory itself
; ---------------------------------------------------------------------------
resolve_path:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    mov byte [rp_self], 0
    mov byte [rp_attr], 0
    mov word [rp_size], 0
    mov word [rp_entry_off], 0xFFFF
    mov word [rp_cluster], 0

    ; --- starting directory ------------------------------------------------
    cmp byte [si], '\'
    jne .relative
    inc si
    xor ax, ax
    jmp .have_start
.relative:
    mov ax, [cur_dir_cluster]
.have_start:
    mov [rp_dir], ax
    call load_dir
    jc .fail

; --- walk the path components ----------------------------------------------
.component:
.skip_sep:
    cmp byte [si], '\'
    jne .sep_done
    inc si
    jmp .skip_sep
.sep_done:
    cmp byte [si], 0
    je .path_is_dir

    ; --- copy the component into comp_buf ---------------------------------
    mov di, comp_buf
    xor cx, cx
.copy:
    mov al, [si]
    test al, al
    jz .copied
    cmp al, '\'
    je .copied
    cmp cx, 11
    jae .copy_skip
    mov [di], al
    inc di
    inc cx
.copy_skip:
    inc si
    jmp .copy
.copied:
    mov byte [di], 0

    ; --- is anything left after this component? ---------------------------
    push si
.skip_more:
    cmp byte [si], '\'
    jne .more_done
    inc si
    jmp .skip_more
.more_done:
    mov al, [si]
    pop si
    test al, al
    jz .last_component
    cmp al, ' '
    je .last_component

    ; --- intermediate component: it has to be a directory -----------------
    call lookup_component
    jc .fail
    mov al, [rp_attr]
    test al, ATTR_DIR
    jz .fail
    mov ax, [rp_cluster]
    mov [rp_dir], ax
    call load_dir
    jc .fail
    jmp .component

.last_component:
    call lookup_component
    jc .fail
    clc
    jmp .done

.path_is_dir:
    mov byte [rp_self], 1
    mov ax, [rp_dir]
    mov [rp_cluster], ax
    mov byte [rp_attr], ATTR_DIR
    mov word [rp_entry_off], 0xFFFF
    clc
    jmp .done

.fail:
    stc
.done:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
;  lookup_component - resolve comp_buf against the loaded directory
;    updates rp_entry_off / rp_cluster / rp_attr / rp_size
;    out: CF = 1 when not found
; ---------------------------------------------------------------------------
lookup_component:
    push si
    mov si, comp_buf
    cmp byte [si], '.'
    jne .normal
    cmp byte [si+1], 0
    je .this_dir
    cmp byte [si+1], '.'
    jne .normal
    cmp byte [si+2], 0
    je .parent_dir
.normal:
    call name_to_83
    jc .notfound
    mov si, chi_name
    call find_entry
    jc .notfound
    mov [rp_entry_off], ax
    call entry_attr
    mov [rp_attr], al
    test al, ATTR_DIR
    jz .file
    mov ax, [rp_entry_off]
    call entry_cluster
    mov [rp_cluster], ax
    clc
    jmp .done
.file:
    mov ax, [rp_entry_off]
    call entry_cluster
    mov [rp_cluster], ax
    mov ax, [rp_entry_off]
    call entry_size
    mov [rp_size], ax
    clc
    jmp .done
.this_dir:
    mov ax, [rp_dir]
    mov [rp_cluster], ax
    mov byte [rp_attr], ATTR_DIR
    clc
    jmp .done
.parent_dir:
    mov ax, [rp_dir]
    test ax, ax
    jz .this_dir
    mov si, name_dotdot
    call find_entry
    jc .this_dir
    call entry_cluster
    mov [rp_cluster], ax
    mov byte [rp_attr], ATTR_DIR
    clc
    jmp .done
.notfound:
    stc
.done:
    pop si
    ret

; ---------------------------------------------------------------------------
;  build_83_from_entry - turn a directory entry into "NAME.EXT" text
;    in : ES:BX -> entry
;    out: di_name_formatted filled
; ---------------------------------------------------------------------------
format_entry_name:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es
    mov si, bx
    mov di, di_name_formatted
    xor cx, cx
.name:
    cmp cx, 8
    jae .name_done
    mov al, [es:si]
    inc si
    cmp al, ' '
    je .name_done
    mov [di], al
    inc di
    inc cx
    jmp .name
.name_done:
    mov si, bx
    add si, 8
    cmp byte [es:si], ' '
    je .ext_done
    mov byte [di], '.'
    inc di
    xor cx, cx
.ext:
    cmp cx, 3
    jae .ext_done
    mov al, [es:si]
    inc si
    cmp al, ' '
    je .ext_done
    mov [di], al
    inc di
    inc cx
    jmp .ext
.ext_done:
    mov byte [di], 0
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
;  state
; ---------------------------------------------------------------------------
rp_dir         dw 0
rp_cluster     dw 0
rp_entry_off   dw 0xFFFF
rp_attr        db 0
rp_size        dw 0
rp_self        db 0

comp_buf       times 13 db 0
chi_name       times 11 db 0
di_name_formatted times 14 db 0
name_dotdot    db ".          ", 0
