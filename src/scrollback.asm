; =============================================================================
;  ZiggyDOS - scrollback buffer
;
;  The VGA text screen only holds 25 rows. This module keeps the last 100
;  printed rows in RAM and lets the user page back through them with PgUp /
;  PgDn while the shell is waiting for input. The screen is treated as a
;  window onto the buffer: the last 25 rows of the buffer are exactly what
;  the screen shows.
; =============================================================================

%define SB_LINES 100
%define SB_COLS  80
%define SB_ROWS  25
%define SB_SIZE  (SB_LINES*SB_COLS)

; --- state --------------------------------------------------------------
sb_count dw 0                 ; rows written so far (capped at SB_LINES)
sb_top   dw 0                 ; first row of the live window
sb_vtop  dw 0                 ; first row of the window being shown
sb_view  db 0                 ; 1 while the user is browsing history
sb_tmp   db 0

; ---------------------------------------------------------------------------
;  sb_reset - clear the buffer and go back to the live view
; ---------------------------------------------------------------------------
sb_reset:
    push ax
    push cx
    push di
    push es
    mov ax, cs
    mov es, ax
    mov di, sb_buf
    mov cx, SB_SIZE
    mov al, ' '
    cld
    rep stosb
    mov word [sb_count], 0
    mov word [sb_top], 0
    mov word [sb_vtop], 0
    mov byte [sb_view], 0
    pop es
    pop di
    pop cx
    pop ax
    call sb_cursor_on
    ret

; ---------------------------------------------------------------------------
;  sb_putc - store the character in AL at the current cursor position
;  (called from putchar_raw before the cursor advances)
; ---------------------------------------------------------------------------
sb_putc:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es
    mov [sb_tmp], al
    call .offset
    add ax, sb_buf
    mov di, ax
    mov ax, cs
    mov es, ax
    mov al, [sb_tmp]
    mov [es:di], al
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret
.offset:
    mov al, [cur_row]
    mov ah, SB_COLS
    mul ah                      ; AX = row*80
    xor ch, ch
    mov cl, [cur_col]
    add ax, cx
    mov bx, ax
    mov ax, [sb_top]
    mov dx, SB_COLS
    mul dx                      ; DX:AX = top*80
    add ax, bx
    ret

; ---------------------------------------------------------------------------
;  sb_newline - a new row has appeared on the screen
; ---------------------------------------------------------------------------
sb_newline:
    push ax
    inc word [sb_count]
    cmp word [sb_count], SB_LINES
    jb .free
    call sb_shift
    mov word [sb_count], SB_LINES
.free:
    mov ax, [sb_count]
    cmp ax, SB_ROWS
    jbe .zero
    sub ax, SB_ROWS
    jmp .store
.zero:
    xor ax, ax
.store:
    mov [sb_top], ax
    pop ax
    ret

; ---------------------------------------------------------------------------
;  sb_shift - scroll the buffer up by one row (history is full)
; ---------------------------------------------------------------------------
sb_shift:
    push ax
    push cx
    push si
    push di
    push ds
    push es
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov si, sb_buf+SB_COLS
    mov di, sb_buf
    mov cx, (SB_LINES-1)*SB_COLS
    cld
    rep movsb
    mov di, sb_buf+(SB_LINES-1)*SB_COLS
    mov cx, SB_COLS
    mov al, ' '
    rep stosb
    pop es
    pop ds
    pop di
    pop si
    pop cx
    pop ax
    ret

; ---------------------------------------------------------------------------
;  sb_redraw - paint rows sb_vtop..sb_vtop+24 onto the VGA screen
; ---------------------------------------------------------------------------
sb_redraw:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es
    mov ax, cs
    mov ds, ax
    mov ax, [sb_vtop]
    mov bx, SB_COLS
    mul bx
    add ax, sb_buf
    mov si, ax
    mov ax, 0xB800
    mov es, ax
    xor di, di
    mov cx, SB_ROWS*SB_COLS
.loop:
    mov al, [si]
    cmp al, ' '
    jae .put
    mov al, ' '
.put:
    mov [es:di], al
    mov byte [es:di+1], 0x07
    inc si
    add di, 2
    loop .loop
    pop es
    pop ds
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
;  sb_cursor_on / sb_cursor_off - hide the cursor while browsing history
; ---------------------------------------------------------------------------
sb_cursor_off:
    push ax
    push dx
    mov dx, 0x3D4
    mov al, 0x0A
    out dx, al
    inc dx
    in al, dx
    or al, 0x20
    out dx, al
    pop dx
    pop ax
    ret

sb_cursor_on:
    push ax
    push dx
    mov dx, 0x3D4
    mov al, 0x0A
    out dx, al
    inc dx
    in al, dx
    and al, 0xDF
    out dx, al
    pop dx
    pop ax
    call update_cursor
    ret

; ---------------------------------------------------------------------------
;  sb_page_up / sb_page_down - one row at a time
; ---------------------------------------------------------------------------
sb_page_up:
    cmp byte [sb_view], 0
    jne .dec
    mov byte [sb_view], 1
    mov ax, [sb_top]
    mov [sb_vtop], ax
.dec:
    cmp word [sb_vtop], 0
    je .draw
    dec word [sb_vtop]
.draw:
    call sb_redraw
    call sb_cursor_off
    ret

sb_page_down:
    cmp byte [sb_view], 0
    je .ret
    mov ax, [sb_vtop]
    inc ax
    mov bx, [sb_top]
    cmp ax, bx
    jbe .ok
    mov byte [sb_view], 0
    mov [sb_vtop], bx
    call sb_redraw
    call sb_cursor_on
.ret:
    ret
.ok:
    mov [sb_vtop], ax
    call sb_redraw
    call sb_cursor_off
    ret

; ---------------------------------------------------------------------------
;  sb_view_exit - back to the live view (any key other than PgUp/PgDn)
; ---------------------------------------------------------------------------
sb_view_exit:
    cmp byte [sb_view], 0
    je .ret
    mov byte [sb_view], 0
    mov ax, [sb_top]
    mov [sb_vtop], ax
    call sb_redraw
    call sb_cursor_on
.ret:
    ret

; --- the buffer itself ------------------------------------------------------
sb_buf times SB_SIZE db 32
