; =============================================================================
;  ZiggyDOS - .COM program loader
; =============================================================================

; ---------------------------------------------------------------------------
;  setup_environment - build a minimal environment block for child programs
; ---------------------------------------------------------------------------
setup_environment:
    push ax
    push si
    push di
    push es
    mov ax, ENV_SEG
    mov es, ax
    mov si, env_string
    xor di, di
.copy:
    lodsb
    stosb
    test al, al
    jnz .copy
    mov byte [es:di], 0
    pop es
    pop di
    pop si
    pop ax
    ret

; ---------------------------------------------------------------------------
;  run_program - execute a .COM file
;    in : DS:SI = argument line (program name then parameters)
;    out: CF = 1 when the name cannot be run (silent, the caller reports it)
; ---------------------------------------------------------------------------
run_program:
    cld
    push si
    call skip_spaces
    cmp byte [si], 0
    je .fail
    mov [prog_arg], si

    ; --- copy the program name into a scratch buffer ----------------------
    mov di, prog_name
    xor cx, cx
.bcopy:
    mov al, [si]
    test al, al
    jz .bdone
    cmp al, ' '
    je .bdone
    cmp cx, 12
    jae .bdone
    mov [di], al
    inc di
    inc si
    inc cx
    jmp .bcopy
.bdone:
    mov byte [di], 0

    ; --- append .COM when the name carries no extension -------------------
    mov si, prog_name
.scan_dot:
    mov al, [si]
    test al, al
    jz .add_com
    cmp al, '.'
    je .resolve
    inc si
    jmp .scan_dot
.add_com:
    mov si, prog_name
.find_end:
    lodsb
    test al, al
    jnz .find_end
    dec si
    mov byte [si], '.'
    mov byte [si+1], 'C'
    mov byte [si+2], 'O'
    mov byte [si+3], 'M'
    mov byte [si+4], 0
.resolve:
    mov si, prog_name
    call resolve_path
    jc .fail
    mov al, [rp_attr]
    test al, ATTR_DIR
    jnz .fail
    mov si, chi_name+8
    cmp byte [si], 'C'
    jne .fail
    cmp byte [si+1], 'O'
    jne .fail
    cmp byte [si+2], 'M'
    jne .fail
    mov ax, [rp_size]
    cmp ax, 0xFC00
    ja .fail
    mov [prog_size], ax

    ; --- build the program segment prefix ---------------------------------
    mov ax, PSP_SEG
    mov es, ax
    xor di, di
    mov cx, 128
    xor ax, ax
    rep stosw                     ; ES:DI, 256 bytes from DS

    mov ax, PSP_SEG
    mov es, ax
    mov word [es:0x00], 0x20CD    ; INT 20h
    mov word [es:0x02], MEM_TOP_SEG
    mov ax, ENV_SEG
    mov [es:0x2C], ax

    ; --- command tail -----------------------------------------------------
    mov si, [prog_arg]
.scan_name:
    mov al, [si]
    test al, al
    jz .tail_empty
    cmp al, ' '
    je .tail_start
    inc si
    jmp .scan_name
.tail_start:
    call skip_spaces
    mov di, 0x81
    xor cx, cx
.tail_copy:
    mov al, [si]
    test al, al
    jz .tail_done
    cmp cx, 126
    jae .tail_done
    mov [es:di], al
    inc si
    inc di
    inc cx
    jmp .tail_copy
.tail_done:
    mov byte [es:di], 0
    mov [es:0x80], cl
    jmp .load
.tail_empty:
    mov byte [es:0x80], 0

.load:
    ; --- load the image at PSP:0100 ---------------------------------------
    mov ax, [rp_cluster]
    mov cx, [prog_size]
    mov bx, PSP_SEG
    mov es, bx
    mov bx, 0x0100
    call file_read

    ; --- save the shell context -------------------------------------------
    mov [saved_ss], ss
    mov [saved_sp], sp
    mov ax, cs
    mov [saved_cs], ax
    mov word [saved_ip], .after

    ; --- transfer control -------------------------------------------------
    mov ax, PSP_SEG
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0xFFFE
    push word 0x0000              ; return IP for the program's RET
    push ax                       ; return CS for the program's RET
    push ax                       ; entry CS
    push word 0x0100              ; entry IP
    retf
.after:
    mov ax, KERNEL_SEG
    mov ds, ax
    mov es, ax
    call fat_flush
    pop si
    clc
    ret
.fail:
    pop si
    stc
    ret

; ---------------------------------------------------------------------------
prog_arg   dw 0
prog_size  dw 0
prog_name  times 20 db 0
