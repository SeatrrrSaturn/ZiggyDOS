; =============================================================================
;  ZiggyDOS - command interpreter
; =============================================================================

; ---------------------------------------------------------------------------
;  shell - read a line and execute it, forever
; ---------------------------------------------------------------------------
shell:
.loop:
    call print_prompt
    mov di, cmd_line
    mov cx, 120
    call readline
    call execute_line
    jmp .loop

; ---------------------------------------------------------------------------
;  print_prompt - "A:\DOC>"
; ---------------------------------------------------------------------------
print_prompt:
    push si
    mov si, msg_drive_letter
    call puts
    mov si, cur_dir_path
    call puts
    mov al, '>'
    call putchar
    pop si
    ret

; ---------------------------------------------------------------------------
;  execute_line
; ---------------------------------------------------------------------------
execute_line:
    push si
    mov si, cmd_line
.skip_leading:
    cmp byte [si], ' '
    jne .scan
    inc si
    jmp .skip_leading
.scan:
    cmp byte [si], 0
    je .empty
    mov di, cmd_name
    xor cx, cx
.token:
    mov al, [si]
    test al, al
    jz .token_done
    cmp al, ' '
    je .token_done
    cmp cx, 11
    jae .token_skip
    call upper_char
    mov [di], al
    inc di
    inc cx
.token_skip:
    inc si
    jmp .token
.token_done:
    mov byte [di], 0
.skip_args_space:
    cmp byte [si], ' '
    jne .dispatch
    inc si
    jmp .skip_args_space
.dispatch:
    mov bx, cmd_table
.search:
    mov di, [bx]
    test di, di
    jz .unknown
    push si
    mov si, cmd_name
    call strcmp_z
    pop si
    je .found
    add bx, 4
    jmp .search
.found:
    mov ax, [bx+2]
    call ax
    jmp .end
.unknown:
    cmp byte [si], 0
    jne .have_arg
    mov si, cmd_name             ; the name itself is the program
.have_arg:
    call run_program
    jnc .end
    mov si, msg_bad_cmd
    call puts
    mov si, cmd_name
    call puts
    mov si, msg_bad_cmd2
    call puts
    jmp .end
.empty:
.end:
    pop si
    ret

; ---------------------------------------------------------------------------
;  strcmp_z - compare two NUL terminated strings, ZF set when equal
;    in : DS:SI, DS:DI
; ---------------------------------------------------------------------------
strcmp_z:
    push si
    push di
.loop:
    mov al, [si]
    cmp al, [di]
    jne .done
    test al, al
    jz .done
    inc si
    inc di
    jmp .loop
.done:
    pop di
    pop si
    ret

; ---------------------------------------------------------------------------
;  strlen - CX = length of the string at DS:SI
; ---------------------------------------------------------------------------
strlen:
    push si
    xor cx, cx
.loop:
    cmp byte [si], 0
    je .done
    inc si
    inc cx
    jmp .loop
.done:
    pop si
    ret

; ---------------------------------------------------------------------------
;  skip_spaces - advance SI past blanks
; ---------------------------------------------------------------------------
skip_spaces:
    cmp byte [si], ' '
    jne .done
    inc si
    jmp skip_spaces
.done:
    ret

; ---------------------------------------------------------------------------
;  cmd_set / collect - split the argument list
;    collect copies characters of the first argument into arg_buf (upper case)
;    and returns the pointer to the next argument in SI
; ---------------------------------------------------------------------------
collect_arg:
    push di
    mov di, arg_buf
    xor cx, cx
.loop:
    mov al, [si]
    test al, al
    jz .done
    cmp al, ' '
    je .done
    cmp cx, 12
    jae .skip
    call upper_char
    mov [di], al
    inc di
    inc cx
.skip:
    inc si
    jmp .loop
.done:
    mov byte [di], 0
    call skip_spaces
    pop di
    ret

; ---------------------------------------------------------------------------
cmd_line        times 128 db 0
cmd_name        times 14 db 0
arg_buf         times 14 db 0
arg_buf2        times 14 db 0

msg_drive_letter db "A:", 0
msg_bad_cmd      db "Bad command or file name: ", 0
msg_bad_cmd2     db 10, 0

cmd_table:
    dw t_dir,   cmd_dir
    dw t_type,  cmd_type
    dw t_copy,  cmd_copy
    dw t_del,   cmd_del
    dw t_ren,   cmd_ren
    dw t_md,    cmd_md
    dw t_rd,    cmd_rd
    dw t_cd,    cmd_cd
    dw t_cls,   cmd_cls
    dw t_ver,   cmd_ver
    dw t_date,  cmd_date
    dw t_time,  cmd_time
    dw t_echo,  cmd_echo
    dw t_mem,   cmd_mem
    dw t_help,  cmd_help
    dw t_exit,  cmd_exit
    dw t_vol,   cmd_vol
    dw t_pwd,    cmd_pwd
    dw t_tree,   cmd_tree
    dw t_attrib, cmd_attrib
    dw t_more,   cmd_more
    dw t_label,  cmd_label
    dw t_shut,   cmd_shutdown
    dw t_off,    cmd_shutdown
    dw t_halt,   cmd_shutdown
    dw t_reboot, cmd_reboot
    dw t_restart, cmd_reboot
    dw t_echo2, cmd_echo
    dw 0

t_dir   db "DIR", 0
t_type  db "TYPE", 0
t_copy  db "COPY", 0
t_del   db "DEL", 0
t_ren   db "REN", 0
t_md    db "MD", 0
t_rd    db "RD", 0
t_cd    db "CD", 0
t_cls   db "CLS", 0
t_ver   db "VER", 0
t_date  db "DATE", 0
t_time  db "TIME", 0
t_echo  db "ECHO", 0
t_echo2 db "ECHO.", 0
t_mem   db "MEM", 0
t_help  db "HELP", 0
t_exit  db "EXIT", 0
t_vol   db "VOL", 0
t_pwd   db "PWD", 0
t_tree  db "TREE", 0
t_attrib db "ATTRIB", 0
t_more  db "MORE", 0
t_label db "LABEL", 0
t_shut  db "SHUTDOWN", 0
t_off   db "OFF", 0
t_halt  db "HALT", 0
t_reboot db "REBOOT", 0
t_restart db "RESTART", 0
