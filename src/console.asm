; =============================================================================
;  ZiggyDOS - console output / keyboard input
;  All text goes through the BIOS teletype service, so it works on any VGA
;  (or MDA) adapter in 80x25 text mode.  When built with -DDEBUG every
;  character is also mirrored to port 0xE9 for headless QEMU testing.
; =============================================================================

; ---------------------------------------------------------------------------
;  putchar_raw - emit AL straight into VGA text memory (0xB800)
;  The kernel keeps its own cursor, exactly like DOS does.
; ---------------------------------------------------------------------------
putchar_raw:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es
%ifdef DEBUG
    push dx
    out 0xE9, al
    pop dx
%endif
    mov si, ax                    ; char in SI: .offset uses MUL, which clobbers DX
    mov ax, 0xB800
    mov es, ax
    call .offset                  ; DI = byte offset of the cursor
    mov ax, si
    cmp al, 13
    je .do_cr
    cmp al, 10
    je .do_lf
    cmp al, 8
    je .do_bs
    mov [es:di], al
    mov byte [es:di+1], 0x07
    call sb_putc
    inc byte [cur_col]
    cmp byte [cur_col], 80
    jb .done
    mov byte [cur_col], 0
    inc byte [cur_row]
    call sb_newline
    cmp byte [cur_row], 25
    jb .done
    call scroll_screen
    jmp .done
.do_cr:
    mov byte [cur_col], 0
    jmp .done
.do_lf:
    inc byte [cur_row]
    call sb_newline
    cmp byte [cur_row], 25
    jb .done
    call scroll_screen
    jmp .done
.do_bs:
    cmp byte [cur_col], 0
    je .bs_prev
    dec byte [cur_col]
    mov al, ' '
    call sb_putc
    jmp .done
.bs_prev:
    cmp byte [cur_row], 0
    je .done
    dec byte [cur_row]
    mov byte [cur_col], 79
.done:
    call update_cursor
%ifdef DEBUG
    ; headless QEMU only refreshes its VGA surface when the BIOS touches it
    mov ah, 0x02
    mov bh, 0
    mov dh, [cur_row]
    mov dl, [cur_col]
    int 0x10
%endif
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; --- DI = (cur_row * 80 + cur_col) * 2 --------------------------------------
.offset:
    mov al, [cur_row]
    mov ah, 80
    mul ah                        ; 8-bit multiply: AX = row*80, DX untouched
    xor ch, ch
    mov cl, [cur_col]
    add ax, cx
    shl ax, 1
    mov di, ax
    ret

; ---------------------------------------------------------------------------
;  update_cursor - program the VGA CRTC so the hardware cursor follows us
; ---------------------------------------------------------------------------
update_cursor:
    push ax
    push bx
    push dx
    mov al, [cur_row]
    xor ah, ah
    mov bx, 80
    mul bx
    xor ch, ch
    mov cl, [cur_col]
    add ax, cx
    mov bx, ax
    mov dx, 0x3D4
    mov al, 0x0F
    out dx, al
    inc dx
    mov al, bl
    out dx, al
    dec dx
    mov al, 0x0E
    out dx, al
    inc dx
    mov al, bh
    out dx, al
    pop dx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
;  scroll_screen - move rows 1..24 up by one line and clear the last row
; ---------------------------------------------------------------------------
scroll_screen:
    push ax
    push cx
    push si
    push di
    push ds
    push es
    mov ax, 0xB800
    mov ds, ax
    mov es, ax
    mov si, 160
    xor di, di
    mov cx, 24*80
.copy:
    mov ax, [si]
    mov [es:di], ax
    add si, 2
    add di, 2
    loop .copy
    mov di, 24*160
    mov cx, 80
.clr:
    mov word [es:di], 0x0720
    add di, 2
    loop .clr
    pop es
    pop ds
    pop di
    pop si
    pop cx
    pop ax
    mov byte [cur_row], 24
    ret

; ---------------------------------------------------------------------------
;  putchar - emit AL, expanding LF into CR+LF
; ---------------------------------------------------------------------------
putchar:
    push ax
    cmp al, 10
    jne .emit
    mov al, 13
    call putchar_raw
    mov al, 10
.emit:
    call putchar_raw
    pop ax
    ret

; ---------------------------------------------------------------------------
;  puts - write the zero terminated string at DS:SI
; ---------------------------------------------------------------------------
puts:
    push ax
    push si
.loop:
    lodsb
    test al, al
    jz .done
    call putchar
    jmp .loop
.done:
    pop si
    pop ax
    ret

; ---------------------------------------------------------------------------
;  newline
; ---------------------------------------------------------------------------
newline:
    mov al, 10
    jmp putchar

; ---------------------------------------------------------------------------
;  getkey - blocking read, returns ASCII in AL (AL=0 for extended keys)
; ---------------------------------------------------------------------------
getkey:
    xor ah, ah
    int 0x16
    ret

; ---------------------------------------------------------------------------
;  keypressed - ZF set when no key is waiting
; ---------------------------------------------------------------------------
keypressed:
    mov ah, 0x01
    int 0x16
    ret

; ---------------------------------------------------------------------------
;  readline
;    in : DI = buffer, CX = maximum characters
;    out: buffer NUL terminated, BX = length
;  Supports backspace editing and ignores control/extended keys.
; ---------------------------------------------------------------------------
readline:
    push ax
    push cx
    push dx
    push si
    push es                      ; the caller has set ES:DI to the target buffer
    mov si, di
    xor bx, bx
.loop:
    call getkey
    cmp al, 13
    je .enter
    cmp al, 8
    je .backspace
    test al, al
    jnz .char
    cmp ah, 0x49                 ; Page Up   - page back through history
    je .page_up
    cmp ah, 0x51                 ; Page Down - page forward to live output
    je .page_down
    call sb_view_exit
    jmp .loop
.page_up:
    call sb_page_up
    jmp .loop
.page_down:
    call sb_page_down
    jmp .loop
.char:
    cmp byte [sb_view], 0
    je .accept
    call sb_view_exit
.accept:
    cmp al, 32
    jb .loop                     ; other control characters, ignore
    cmp bx, cx
    jae .loop                    ; buffer full
    stosb
    inc bx
    call putchar
    jmp .loop
.backspace:
    call sb_view_exit
    test bx, bx
    jz .loop
    dec bx
    dec di
    mov byte [di], 0
    mov al, 8
    call putchar_raw
    mov al, ' '
    call putchar_raw
    mov al, 8
    call putchar_raw
    jmp .loop
.enter:
    call sb_view_exit
    mov byte [di], 0
    call newline
    pop es
    pop si
    pop dx
    pop cx
    pop ax
    ret
