; =============================================================================
;  ZiggyDOS - DOS interrupt services (INT 20h / INT 21h)
;
;  Register preservation contract: every service saves and restores all
;  registers except the documented return values in AX (and DX where DOS
;  says so).  The carry flag is returned through the interrupted FLAGS image.
; =============================================================================

; ---------------------------------------------------------------------------
;  install_vectors
; ---------------------------------------------------------------------------
install_vectors:
    push ax
    push es
    xor ax, ax
    mov es, ax
    cli
    mov word [es:0x80], int20_handler
    mov word [es:0x82], KERNEL_SEG
    mov word [es:0x84], int21_handler
    mov word [es:0x86], KERNEL_SEG
    mov word [es:0x90], int24_handler
    mov word [es:0x92], KERNEL_SEG
    sti
    pop es
    pop ax
    ret

; ---------------------------------------------------------------------------
;  int24_handler - critical error: fail the operation
; ---------------------------------------------------------------------------
int24_handler:
    mov al, 3
    iret

; ---------------------------------------------------------------------------
;  int20_handler - terminate the current program
; ---------------------------------------------------------------------------
int20_handler:
    cli
    mov ax, [cs:saved_ss]
    mov ss, ax
    mov sp, [cs:saved_sp]
    mov ax, [cs:saved_cs]
    push ax
    mov ax, [cs:saved_ip]
    push ax
    mov ax, KERNEL_SEG
    mov ds, ax
    mov es, ax
    sti
    retf

; ---------------------------------------------------------------------------
;  int21_handler
; ---------------------------------------------------------------------------
int21_handler:
    cld
    mov [cs:dos_ah], ah
    mov [cs:dos_al], al
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es
    mov ax, KERNEL_SEG
    mov ds, ax
    mov es, ax
    mov bp, sp

    mov al, [dos_ah]
    cmp al, 0x00
    je .terminate
    cmp al, 0x01
    je .read_char
    cmp al, 0x02
    je .write_char
    cmp al, 0x06
    je .direct_io
    cmp al, 0x07
    je .read_char_nf
    cmp al, 0x08
    je .read_char_nf
    cmp al, 0x09
    je .write_string
    cmp al, 0x0A
    je .buffered_input
    cmp al, 0x0B
    je .check_input
    cmp al, 0x0C
    je .flush_input
    cmp al, 0x19
    je .current_drive
    cmp al, 0x1A
    je .set_dta
    cmp al, 0x25
    je .set_vector
    cmp al, 0x2A
    je .get_date
    cmp al, 0x2C
    je .get_time
    cmp al, 0x2F
    je .get_dta
    cmp al, 0x30
    je .get_version
    cmp al, 0x35
    je .get_vector
    cmp al, 0x36
    je .disk_free
    cmp al, 0x3B
    je .chdir
    cmp al, 0x47
    je .get_cwd
    cmp al, 0x48
    je .alloc_mem
    cmp al, 0x49
    je .free_mem
    cmp al, 0x4A
    je .resize_mem
    cmp al, 0x4C
    je .terminate
    cmp al, 0x3C
    je .create
    cmp al, 0x3D
    je .open
    cmp al, 0x3E
    je .close
    cmp al, 0x3F
    je .read
    cmp al, 0x40
    je .write
    cmp al, 0x41
    je .delete
    cmp al, 0x42
    je .seek
    jmp .unsupported

.terminate:
    jmp int20_handler

.read_char:
    call getkey
    cmp al, 13
    je .rc_done
    call putchar
.rc_done:
    jmp .exit_ax
.read_char_nf:
    call getkey
    jmp .exit_ax
.write_char:
    mov al, dl
    call putchar
    xor ax, ax
    jmp .exit_ax
.direct_io:
    cmp dl, 0xFF
    jne .direct_write
    call keypressed
    jnz .direct_none
    call getkey
    jmp .exit_ax
.direct_none:
    xor ax, ax
    jmp .exit_ax
.direct_write:
    mov al, dl
    call putchar
    jmp .exit_ax
.write_string:
    push ds
    mov ax, [bp+2]                ; the caller's DS holds the string
    mov ds, ax
    push si
    mov si, dx
    call dos_puts
    pop si
    pop ds
    xor ax, ax
    jmp .exit_ax
.buffered_input:
    push di
    mov di, dx
    mov cl, [di]
    mov ch, 0
    cmp cx, 1
    jae .bi_ok
    mov cx, 1
.bi_ok:
    inc di
    call readline
    mov [di-1], bl
    pop di
    xor ax, ax
    jmp .exit_ax
.check_input:
    call keypressed
    jnz .ci_none
    mov ax, 1
    jmp .exit_ax
.ci_none:
    xor ax, ax
    jmp .exit_ax
.flush_input:
    call getkey
    jmp .exit_ax
.current_drive:
    xor ax, ax
    jmp .exit_ax
.set_dta:
    mov [dta_off], dx
    mov ax, [bp+2]                ; the caller's DS
    mov [dta_seg], ax
    xor ax, ax
    jmp .exit_ax
.get_dta:
    mov dx, [dta_off]
    xor ax, ax
    jmp .exit_ax
.set_vector:
    push es
    push di
    xor di, di
    mov es, di
    mov al, [dos_al]
    xor ah, ah
    shl ax, 1
    shl ax, 1
    mov di, ax
    mov ax, dx
    mov [es:di], ax
    mov ax, [bp+2]                ; saved DS
    mov [es:di+2], ax
    pop di
    pop es
    xor ax, ax
    jmp .exit_ax
.get_vector:
    push es
    push di
    xor ax, ax
    mov es, ax
    mov al, [dos_al]
    xor ah, ah
    shl ax, 1
    shl ax, 1
    mov di, ax
    mov ax, [es:di]
    mov dx, [es:di+2]
    pop di
    pop es
    mov [bp+10], dx               ; DX is part of the result
    jmp .exit_ax
.get_version:
    mov ax, (DOS_MAJOR * 256) + DOS_MINOR
    jmp .exit_ax
.get_date:
    call rtc_get_date
    mov [bp+12], cx
    mov [bp+10], dx
    xor ax, ax
    jmp .exit_ax
.get_time:
    call rtc_get_time
    mov [bp+12], cx
    mov [bp+10], dx
    xor ax, ax
    jmp .exit_ax
.disk_free:
    mov ax, [fat_sec_per_clu]
    mov bx, [fat_clusters]
    mov cx, [fat_bps]
    mov dx, bx
    jmp .exit_ax
.chdir:
    push si
    mov si, dx
    call resolve_path
    jc .err_path
    mov ax, [rp_cluster]
    mov [cur_dir_cluster], ax
    pop si
    xor ax, ax
    jmp .exit_ax
.err_path:
    pop si
    mov ax, 3
    jmp .exit_fail
.get_cwd:
    push si
    push di
    mov di, dx
    mov si, cur_dir_path
    ; DOS wants the path without the drive letter and without a leading '\'
.gc_skip:
    cmp byte [si], '\'
    jne .gc_copy
    inc si
    jmp .gc_skip
.gc_copy:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    test al, al
    jnz .gc_copy
    pop di
    pop si
    xor ax, ax
    jmp .exit_ax
.alloc_mem:
    mov ax, 8                     ; not enough memory
    jmp .exit_fail
.free_mem:
    xor ax, ax
    jmp .exit_ax
.resize_mem:
    xor ax, ax
    jmp .exit_ax
.create:
.open:
.close:
.read:
.write:
.delete:
.seek:
.unsupported:
    mov ax, 1                     ; invalid function
    jmp .exit_fail

; ---------------------------------------------------------------------------
;  exit paths
; ---------------------------------------------------------------------------
.exit_ax:
    mov [cs:dos_result], ax
    jmp .exit_common
.exit_fail:
    mov [cs:dos_result], ax
    mov word [cs:dos_carry], 1
.exit_common:
    mov ax, [cs:dos_result]
    mov [bp+16], ax               ; place the return value in the saved AX slot
    ; --- carry flag into the interrupted FLAGS image ---------------------
    cmp word [cs:dos_carry], 0
    je .ec_clear
    or word [bp+22], 0x0001
    jmp .ec_pops
.ec_clear:
    and word [bp+22], 0xFFFE
.ec_pops:
    mov word [cs:dos_carry], 0
    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    iret

; ---------------------------------------------------------------------------
;  dos_puts - write the '$' terminated string at DS:DX
; ---------------------------------------------------------------------------
dos_puts:
    push si
    mov si, dx
.loop:
    lodsb
    cmp al, '$'
    je .done
    test al, al
    jz .done
    call putchar
    jmp .loop
.done:
    pop si
    ret

; ---------------------------------------------------------------------------
dos_ah        db 0
dos_al        db 0
dos_result    dw 0
dos_carry     dw 0
dta_off       dw 0x80
dta_seg       dw PSP_SEG

saved_ss      dw STACK_SEG
saved_sp      dw 0xFFFE
saved_cs      dw KERNEL_SEG
saved_ip      dw 0
