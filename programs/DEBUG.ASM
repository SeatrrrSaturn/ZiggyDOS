; =============================================================================
;  DEBUG.COM - memory inspection, as in MS-DOS 3.x (a cut-down version)
;
;  Commands:  D [seg:off]   dump 128 bytes
;             E seg:off b    poke bytes
;             ?              help
;             Q              quit
;  A bare D repeats from the last address; the default segment is CS.
; =============================================================================
[BITS 16]
[ORG 0x100]

start:
    mov [def_seg], cs
    mov word [def_off], 0x0100
    mov dx, msg_banner
    call puts

.prompt:
    mov dx, msg_prompt
    call puts
    mov dx, inbuf
    mov ah, 0x0A
    int 0x21
    call crlf
    mov cl, [inbuf+1]
    mov ch, 0
    mov si, inbuf+2
    test cx, cx
    jz .prompt
.skipsp:
    cmp byte [si], ' '
    jne .cmd
    inc si
    dec cx
    jz .prompt
    jmp .skipsp
.cmd:
    mov al, [si]
    cmp al, 'a'
    jb .uc
    cmp al, 'z'
    ja .uc
    sub al, 32
.uc:
    inc si
    dec cx
    cmp al, 'D'
    je .dump
    cmp al, 'E'
    je .edit
    cmp al, 'G'
    je .go
    cmp al, 'Q'
    je .quit
    cmp al, '?'
    je .help
.bad:
    mov dx, msg_err
    call puts
    jmp .prompt
.help:
    mov dx, msg_help
    call puts
    jmp .prompt
.quit:
    mov ax, 0x4C00
    int 0x21

.go:                                   ; show the registers we can see
    mov dx, msg_regs
    call puts
    mov ax, cs
    call puthex16
    mov al, ':'
    call putchar
    mov ax, [def_off]
    call puthex16
    call crlf
    jmp .prompt

; ----------------------------------------------------------------- dump -----
.dump:
    call parse_addr
    jc .bad
    mov byte [rows], 8
.row:
    mov ax, [addr_seg]
    call puthex16
    mov al, ':'
    call putchar
    mov ax, [addr_off]
    call puthex16
    mov al, ' '
    call putchar
    push ds
    mov ax, [addr_seg]
    mov ds, ax
    mov si, [addr_off]
    mov di, linebuf
    mov cx, 16
.cap:
    lodsb
    stosb
    loop .cap
    pop ds
    mov si, linebuf
    mov cx, 16
.hex:
    lodsb
    call puthex8
    mov al, ' '
    call putchar
    loop .hex
    mov al, ' '
    call putchar
    mov si, linebuf
    mov cx, 16
.asc:
    lodsb
    cmp al, 0x20
    jb .dot
    cmp al, 0x7E
    ja .dot
    jmp .emit
.dot:
    mov al, '.'
.emit:
    call putchar
    loop .asc
    call crlf
    add word [addr_off], 16
    dec byte [rows]
    jnz .row
    jmp .prompt

; ----------------------------------------------------------------- poke -----
.edit:
    call parse_addr
    jc .bad
.skipval:
    cmp cx, 0
    je .prompt
    cmp byte [si], ' '
    jne .val
    inc si
    dec cx
    jmp .skipval
.val:
    call read_hex
    push ds
    mov bx, [addr_seg]
    mov ds, bx
    mov bx, [addr_off]
    mov [bx], al
    pop ds
    inc word [addr_off]
    jmp .skipval

; ------------------------------------------------------------------ parse ---
;  Optional "seg:off" / "off" argument.  No argument = reuse the last address.
;  Returns CF=1 on a syntax error.
parse_addr:
    cmp cx, 0
    je .def
.skipsp:
    cmp byte [si], ' '
    jne .start
    inc si
    dec cx
    jz .def
    jmp .skipsp
.start:
    call read_hex
    push ax
    cmp byte [si], ':'
    je .colon
    pop ax
    mov [addr_off], ax
    mov ax, [def_seg]
    mov [addr_seg], ax
    clc
    ret
.colon:
    pop bx
    inc si
    dec cx
    call read_hex
    mov [addr_off], ax
    mov [addr_seg], bx
    clc
    ret
.def:
    mov ax, [def_seg]
    mov [addr_seg], ax
    mov ax, [def_off]
    mov [addr_off], ax
    clc
    ret

;  read_hex: parse 1-4 hex digits at [si] -> AX, consuming them from CX
read_hex:
    push bx
    push dx
    xor ax, ax
    xor bx, bx
.loop:
    cmp cx, 0
    je .done
    mov dl, [si]
    cmp dl, '0'
    jb .done
    cmp dl, '9'
    jbe .digit
    cmp dl, 'A'
    jb .lower
    cmp dl, 'F'
    ja .lower
    sub dl, 'A'-10
    jmp .acc
.lower:
    cmp dl, 'a'
    jb .done
    cmp dl, 'f'
    ja .done
    sub dl, 'a'-10
    jmp .acc
.digit:
    sub dl, '0'
.acc:
    shl ax, 1
    shl ax, 1
    shl ax, 1
    shl ax, 1
    or al, dl
    inc si
    dec cx
    inc bx
    jmp .loop
.done:
    pop dx
    pop bx
    ret

; ----------------------------------------------------------------- output ---
putchar:
    push ax
    push dx
    mov ah, 0x02
    mov dl, al
    int 0x21
    pop dx
    pop ax
    ret

puts:
    mov ah, 0x09
    int 0x21
    ret

crlf:
    mov dx, msg_crlf
    call puts
    ret

puthex4:                              ; one nibble
    push ax
    and al, 0x0F
    add al, '0'
    cmp al, '9'
    jbe .p
    add al, 7
.p:
    call putchar
    pop ax
    ret

puthex8:                              ; one byte
    push ax
    mov ah, al
    shr al, 1
    shr al, 1
    shr al, 1
    shr al, 1
    call puthex4
    mov al, ah
    call puthex4
    pop ax
    ret

puthex16:                             ; one word
    push ax
    mov al, ah
    call puthex8
    pop ax
    call puthex8
    ret

; ----------------------------------------------------------------- data -----
def_seg   dw 0
def_off   dw 0
addr_seg  dw 0
addr_off  dw 0
rows      db 0
linebuf   times 16 db 0
inbuf     db 40, 0
          times 44 db 0

msg_prompt db "-", "$"
msg_crlf   db 13, 10, "$"
msg_banner db "ZiggyDOS DEBUG - memory dump and patch", 13, 10, "$"
msg_err    db "error - use D [seg:off], E seg:off byte, ? for help", 13, 10, "$"
msg_help   db "D [seg:off]  dump 128 bytes   E seg:off b  poke a byte", 13, 10
           db "G  address   Q  quit", 13, 10, "$"
msg_regs   db "CS:", "$"
