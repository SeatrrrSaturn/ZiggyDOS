; =============================================================================
;  HELLO.COM - a tiny DOS program, assembled as a .COM image
;  Loaded by ZiggyDOS at PSP:0100 and executed in real mode.
; =============================================================================
[BITS 16]
[ORG 0x100]

start:
    mov dx, msg_hello
    mov ah, 0x09
    int 0x21

    mov ah, 0x2A                  ; DOS: get the system date
    int 0x21
    mov [d_year], cx
    mov [d_month], dh
    mov [d_day], dl
    mov dx, msg_date
    mov ah, 0x09
    int 0x21
    mov al, [d_day]
    xor ah, ah
    call putnum
    mov al, '/'
    call putchar
    mov al, [d_month]
    xor ah, ah
    call putnum
    mov al, '/'
    call putchar
    mov ax, [d_year]
    xor dx, dx
    mov bx, 100
    div bx
    mov ax, dx
    call putnum

    mov dx, msg_bye
    mov ah, 0x09
    int 0x21

    mov ax, 0x4C00                ; DOS: terminate, exit code 0
    int 0x21

putchar:
    push ax
    mov ah, 0x02
    mov dl, al
    int 0x21
    pop ax
    ret

putnum:
    push ax
    push bx
    push cx
    push si
    xor ah, ah
    mov bl, 10
    div bl
    mov si, ax
    add al, '0'
    call putchar
    mov cl, 8
    shr si, cl
    mov ax, si
    add al, '0'
    call putchar
    pop si
    pop cx
    pop bx
    pop ax
    ret

msg_hello db "Hello from HELLO.COM - a real .COM program running under ZiggyDOS!", 13, 10, "$"
d_year  dw 0
d_month db 0
d_day   db 0
msg_date  db "Today is ", "$"
msg_bye   db 13, 10, "Loaded through the DOS program loader at PSP:0100.", 13, 10, "$"
