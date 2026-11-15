; =============================================================================
;  ZiggyDOS - additional commands
;    PWD   TREE   ATTRIB   MORE   LABEL   SHUTDOWN   REBOOT
; =============================================================================

; ---------------------------------------------------------------------------
;  cmd_pwd - print the current directory
; ---------------------------------------------------------------------------
cmd_pwd:
    mov si, msg2_drive_prefix
    call puts
    mov si, cur_dir_path
    call puts
    call newline
    ret

; ---------------------------------------------------------------------------
;  print_tree_name - print an 8.3 name from a directory entry
;    in : BX = entry offset, ES = BUF_SEG
; ---------------------------------------------------------------------------
print_tree_name:
    push ax
    push bx
    push cx
    push si
    mov si, bx
    mov cx, 8
.nm:
    mov al, [es:si]
    inc si
    cmp al, ' '
    je .nm_end
    push cx
    call putchar
    pop cx
    dec cx
    jnz .nm
.nm_end:
    cmp byte [es:bx+8], ' '
    je .no_ext
    mov al, '.'
    call putchar
    mov si, bx
    add si, 8
    mov cx, 3
.ex:
    mov al, [es:si]
    inc si
    cmp al, ' '
    je .no_ext
    push cx
    call putchar
    pop cx
    dec cx
    jnz .ex
.no_ext:
    mov al, [es:bx+11]
    test al, ATTR_DIR
    jz .nl
    mov al, 0x5C                   ; '\'
    call putchar
.nl:
    call newline
    pop si
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
;  cmd_tree - show the current directory and one level of subdirectories
; ---------------------------------------------------------------------------
cmd_tree:
    cld
    mov si, msg2_tree_head
    call puts
    mov si, cur_dir_path
    call puts
    call newline
    call newline

    mov ax, [cur_dir_cluster]
    mov [tr_dir], ax
    call load_dir
    mov ax, BUF_SEG
    mov es, ax
    mov bx, [dir_buf_off]
    mov cx, [dir_count]

.loop:
    test cx, cx
    jz .done
    mov al, [es:bx]
    test al, al
    jz .done
    cmp al, 0xE5
    je .next
    cmp byte [es:bx], '.'
    je .next
    mov al, [es:bx+11]
    cmp al, ATTR_LFN
    je .next
    test al, ATTR_VOLUME
    jnz .next

    ; --- print the entry, indented by two ---------------------------------
    mov al, ' '
    call putchar
    mov al, ' '
    call putchar
    call print_tree_name
    mov ax, BUF_SEG
    mov es, ax

    mov al, [es:bx+11]
    test al, ATTR_DIR
    jz .next

    ; --- expand one level -------------------------------------------------
    push bx
    push cx
    mov ax, [es:bx+26]
    call load_dir
    mov ax, BUF_SEG
    mov es, ax
    mov bx, [dir_buf_off]
    mov cx, [dir_count]
.child:
    test cx, cx
    jz .child_done
    mov al, [es:bx]
    test al, al
    jz .child_done
    cmp al, 0xE5
    je .child_next
    cmp byte [es:bx], '.'
    je .child_next
    mov al, [es:bx+11]
    cmp al, ATTR_LFN
    je .child_next
    mov al, ' '
    call putchar
    mov al, ' '
    call putchar
    mov al, ' '
    call putchar
    mov al, ' '
    call putchar
    call print_tree_name
    mov ax, BUF_SEG
    mov es, ax
.child_next:
    add bx, 32
    dec cx
    jmp .child
.child_done:
    mov ax, [tr_dir]
    call load_dir
    mov ax, BUF_SEG
    mov es, ax
    pop cx
    pop bx
.next:
    add bx, 32
    dec cx
    jmp .loop
.done:
    ret

; ---------------------------------------------------------------------------
;  print_attr_line - "R H S A  NAME.EXT"
;    in : BX = entry offset, ES = BUF_SEG
; ---------------------------------------------------------------------------
print_attr_line:
    push ax
    push bx
    push cx
    push si
    mov al, [es:bx+11]
    mov [at_tmp], al
    mov al, 'R'
    test byte [at_tmp], ATTR_READONLY
    jnz .r_show
    mov al, ' '
.r_show:
    call putchar
    mov al, 'H'
    test byte [at_tmp], ATTR_HIDDEN
    jnz .h_show
    mov al, ' '
.h_show:
    call putchar
    mov al, 'S'
    test byte [at_tmp], ATTR_SYSTEM
    jnz .s_show
    mov al, ' '
.s_show:
    call putchar
    mov al, 'A'
    test byte [at_tmp], ATTR_ARCHIVE
    jnz .a_show
    mov al, ' '
.a_show:
    call putchar
    mov al, ' '
    call putchar
    mov al, ' '
    call putchar
    call print_tree_name
    pop si
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
;  cmd_attrib - show or change attributes
;    ATTRIB                     list everything here
;    ATTRIB <file>              show one entry
;    ATTRIB +r|-r [+h|-h] ...   set / clear flags
; ---------------------------------------------------------------------------
cmd_attrib:
    cld
    call skip_spaces
    cmp byte [si], 0
    je .list_all
    mov al, [si]
    cmp al, '+'
    je .set
    cmp al, '-'
    je .set
    jmp .show_one

.set:
    mov [at_sign], al
    inc si
    mov al, [si]
    cmp al, 'a'
    jb .up
    cmp al, 'z'
    ja .up
    sub al, 32
.up:
    cmp al, 'R'
    je .flag_r
    cmp al, 'H'
    je .flag_h
    cmp al, 'S'
    je .flag_s
    cmp al, 'A'
    je .flag_a
    mov si, msg2_bad_attr
    call puts
    ret
.flag_r:
    mov byte [at_mask], ATTR_READONLY
    jmp .apply
.flag_h:
    mov byte [at_mask], ATTR_HIDDEN
    jmp .apply
.flag_s:
    mov byte [at_mask], ATTR_SYSTEM
    jmp .apply
.flag_a:
    mov byte [at_mask], ATTR_ARCHIVE
.apply:
    inc si
    call skip_spaces
    cmp byte [si], 0
    je .usage
    call resolve_path
    jc .not_found
    mov ax, [rp_dir]
    call load_dir
    mov ax, BUF_SEG
    mov es, ax
    mov bx, [rp_entry_off]
    mov al, [es:bx+11]
    cmp byte [at_sign], '-'
    je .clear
    or al, [at_mask]
    jmp .store
.clear:
    mov dl, [at_mask]
    not dl
    and al, dl
.store:
    mov [es:bx+11], al
    mov ax, [rp_dir]
    call dir_flush
    ret

.show_one:
    call resolve_path
    jc .not_found
    mov ax, [rp_dir]
    call load_dir
    mov ax, BUF_SEG
    mov es, ax
    mov bx, [rp_entry_off]
    call print_attr_line
    ret

.list_all:
    mov ax, [cur_dir_cluster]
    call load_dir
    mov ax, BUF_SEG
    mov es, ax
    mov bx, [dir_buf_off]
    mov cx, [dir_count]
.la:
    test cx, cx
    jz .la_done
    mov al, [es:bx]
    test al, al
    jz .la_done
    cmp al, 0xE5
    je .la_next
    mov al, [es:bx+11]
    test al, ATTR_VOLUME
    jnz .la_next
    push cx
    push bx
    call print_attr_line
    pop bx
    pop cx
    mov ax, BUF_SEG
    mov es, ax
.la_next:
    add bx, 32
    dec cx
    jmp .la
.la_done:
    ret

.not_found:
    mov si, msg_file_not_found
    call puts
    ret
.usage:
    mov si, msg2_syntax_attrib
    call puts
    ret

; ---------------------------------------------------------------------------
;  cmd_more - display a file, 23 lines at a time
; ---------------------------------------------------------------------------
cmd_more:
    cld
    call skip_spaces
    cmp byte [si], 0
    je .usage
    call resolve_path
    jc .not_found
    mov al, [rp_attr]
    test al, ATTR_DIR
    jnz .is_dir
    mov ax, [rp_cluster]
    mov [mo_clus], ax
    mov ax, [rp_size]
    mov [mo_rem], ax
    mov byte [mo_line], 0
.loop:
    cmp word [mo_rem], 0
    je .done
    mov cx, 512
    mov ax, [mo_rem]
    cmp ax, 512
    jae .go
    mov cx, ax
.go:
    mov ax, [mo_clus]
    mov bx, BUF_SEG
    mov es, bx
    mov bx, SEC_OFF
    call file_read
    push es
    mov cx, ax
    mov ax, BUF_SEG
    mov es, ax
    mov si, SEC_OFF
.out:
    test cx, cx
    jz .out_done
    mov al, [es:si]
    inc si
    mov [mo_chr], al
    cmp al, 0x1A
    je .stop
    push cx
    push si
    push es
    cmp al, 10
    jne .plain
    inc byte [mo_line]
    cmp byte [mo_line], 23
    jb .plain
    mov byte [mo_line], 0
    mov si, msg2_more_prompt
    call puts
    call getkey
    call newline
.plain:
    mov al, [mo_chr]
    call putchar
    pop es
    pop si
    pop cx
    dec cx
    jmp .out
.stop:
    pop es
    jmp .done
.out_done:
    pop es
    mov ax, [mo_clus]
    call fat_get
    mov [mo_clus], ax
    mov ax, [mo_rem]
    sub ax, 512
    jnc .store
    xor ax, ax
.store:
    mov [mo_rem], ax
    jmp .loop
.done:
    ret
.usage:
    mov si, msg2_syntax_more
    call puts
    ret
.not_found:
    mov si, msg_file_not_found
    call puts
    ret
.is_dir:
    mov si, msg_is_dir
    call puts
    ret

; ---------------------------------------------------------------------------
;  cache_volume - copy the volume label from root entry 0 into vol_label
;    note: this reloads the root directory, call it before your own load_dir
; ---------------------------------------------------------------------------
cache_volume:
    push ax
    push bx
    push cx
    push si
    push di
    push es
    xor ax, ax
    call load_dir
    mov ax, BUF_SEG
    mov es, ax
    mov bx, [dir_buf_off]
    mov si, bx
    mov di, vol_label
    mov cx, 11
.cp:
    mov al, [es:si]
    mov [di], al
    inc si
    inc di
    dec cx
    jnz .cp
    mov byte [di], 0
    dec di
.trim:
    cmp di, vol_label
    jbe .done
    cmp byte [di], ' '
    jne .done
    mov byte [di], 0
    dec di
    jmp .trim
.done:
    pop es
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
;  cmd_label - show or set the volume label (root directory entry 0)
; ---------------------------------------------------------------------------
cmd_label:
    cld
    call skip_spaces
    cmp byte [si], 0
    je .show
    xor ax, ax
    call load_dir
    mov ax, BUF_SEG
    mov es, ax
    mov bx, [dir_buf_off]
    mov di, bx
    mov cx, 11
.fill:
    mov byte [es:di], ' '
    inc di
    dec cx
    jnz .fill
    mov di, bx
    mov cx, 11
.copy:
    mov al, [si]
    test al, al
    jz .padded
    cmp al, 'a'
    jb .up
    cmp al, 'z'
    ja .up
    sub al, 32
.up:
    mov [es:di], al
    inc si
    inc di
    dec cx
    jnz .copy
.padded:
    mov byte [es:bx+11], ATTR_VOLUME
    xor ax, ax
    call dir_flush
    ret
.show:
    call cache_volume
    cmp byte [vol_label], 0
    je .none
    mov si, msg2_label_is
    call puts
    mov si, vol_label
    call puts
    call newline
    ret
.none:
    mov si, msg2_no_label
    call puts
    ret

; ---------------------------------------------------------------------------
;  cmd_shutdown - power the machine off
;    ACPI first (this is what QEMU, Bochs and VirtualBox honour), then APM,
;    then a plain halt if the firmware does not support either.
; ---------------------------------------------------------------------------
cmd_shutdown:
    mov si, msg2_shutdown
    call puts

    ; --- ACPI PM1a control: SLP_TYP = 5 (soft off), SLP_EN set -------------
    mov dx, 0x0604
    mov ax, 0x2000
    out dx, ax
    mov dx, 0xB004                 ; older QEMU / Bochs
    mov ax, 0x2000
    out dx, ax

    ; --- APM: set system state to "off" -----------------------------------
    mov ax, 0x5307
    mov bx, 0x0001
    mov cx, 0x0003
    int 0x15

    ; --- nothing worked ----------------------------------------------------
    mov si, msg2_shutdown_failed
    call puts
    cli
.hang:
    hlt
    jmp .hang

; ---------------------------------------------------------------------------
;  cmd_reboot - restart the machine through the BIOS reset vector
; ---------------------------------------------------------------------------
cmd_reboot:
    mov si, msg2_reboot
    call puts
    mov word [0x0472], 0x1234      ; "warm boot" flag in the BIOS data area
    mov ax, 0xFFFF
    push ax
    mov ax, 0x0000
    push ax
    retf

; --- state ------------------------------------------------------------------
at_tmp    db 0
at_sign   db 0
at_mask   db 0
tr_dir    dw 0
mo_clus   dw 0
mo_rem    dw 0
mo_line   db 0
mo_chr    db 0

; --- messages ---------------------------------------------------------------
msg2_drive_prefix db "A:", 0
msg2_tree_head db "Directory tree of ", 0
msg2_more_prompt db " -- More -- press any key", 10, 0
msg2_bad_attr db "ATTRIB: unknown flag, use r/h/s/a", 10, 0
msg2_syntax_attrib db "Usage: ATTRIB [file] or ATTRIB +r|-r [+h|-h] <file>", 10, 0
msg2_syntax_more db "Usage: MORE <file>", 10, 0
msg2_label_is db "Volume in drive A is ", 0
msg2_no_label db "Volume has no label (set one with LABEL <name>)", 10, 0
msg2_shutdown db "Shutting down...", 10, 0
msg2_shutdown_failed db "ACPI power off is not available - it is safe to close the window", 10, 0
msg2_reboot db "Rebooting...", 10, 0

; --- volume label cache -----------------------------------------------------
vol_label times 12 db 0
