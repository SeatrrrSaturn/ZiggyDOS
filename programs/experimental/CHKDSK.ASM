; =============================================================================
;  CHKDSK.COM - report on the FAT12 volume in drive A:, as MS-DOS 6.22 does
;  Uses INT 25h (absolute disk read), the same API the original used.
; =============================================================================
[BITS 16]
[ORG 0x100]

start:
    mov dx, msg_head
    call puts

    mov cx, 1
    xor dx, dx
    xor ax, ax
    mov bx, bootbuf
    int 0x25
    popf

    cmp word [bootbuf+510], 0xAA55
    jne .nofs

    mov ax, [bootbuf+11]
    mov [secsize], ax
    mov al, [bootbuf+13]
    mov ah, 0
    mov [spc], ax
    mov ax, [bootbuf+14]
    mov [reserved], ax
    mov al, [bootbuf+16]
    mov ah, 0
    mov [nfats], ax
    mov ax, [bootbuf+17]
    mov [rootents], ax
    mov ax, [bootbuf+19]
    mov [total], ax
    mov ax, [bootbuf+22]
    mov [fatsecs], ax

    mov ax, [rootents]              ; root_secs = rootents*32 / secsize
    mov bx, 32
    mul bx
    add ax, 511
    adc dx, 0
    mov bx, [secsize]
    div bx
    mov [rootsecs], ax

    mov ax, [nfats]                 ; data_start = reserved + nfats*fatsecs + root
    mov bx, [fatsecs]
    mul bx
    add ax, [reserved]
    add ax, [rootsecs]
    mov [datastart], ax

    mov ax, [total]                 ; clusters = (total - data_start) / spc
    sub ax, [datastart]
    xor dx, dx
    mov bx, [spc]
    div bx
    mov [nclust], ax

    mov cx, [fatsecs]               ; read FAT #1
    mov dx, [reserved]
    xor ax, ax
    mov bx, fatbuf
    int 0x25
    popf

    mov word [freec], 0
    mov word [ci], 2
.scan:
    mov ax, [ci]
    mov bx, [nclust]
    inc bx
    cmp ax, bx
    ja .scandone
    mov bx, 3
    mul bx
    shr ax, 1
    mov si, ax
    mov ax, [ci]
    test ax, 1
    jnz .odd
    mov al, [fatbuf+si]
    mov dl, [fatbuf+si+1]
    and dl, 0x0F
    jmp .check
.odd:
    mov al, [fatbuf+si]
    mov cl, 4
    shr al, cl
    mov dl, [fatbuf+si+1]
.check:
    test al, al
    jnz .next
    test dl, dl
    jnz .next
    inc word [freec]
.next:
    inc word [ci]
    jmp .scan
.scandone:

    mov cx, 1                       ; just the first root sector, for the label
    mov dx, [datastart]
    sub dx, [rootsecs]
    xor ax, ax
    mov bx, dirbuf
    int 0x25
    popf

    mov dx, msg_vol
    call puts
    call show_label
    call crlf
    call crlf

    mov dx, msg_indent
    call puts
    mov ax, [total]
    mov bx, [secsize]
    mul bx
    call putdec32
    mov dx, msg_total_line
    call puts

    mov dx, msg_indent
    call puts
    mov ax, [spc]
    mov bx, [secsize]
    mul bx
    call putdec32
    mov dx, msg_unit_line
    call puts

    mov dx, msg_indent
    call puts
    mov ax, [nclust]
    xor dx, dx
    call putdec32
    mov dx, msg_clust_line
    call puts

    mov ax, 0x4C00
    int 0x21

.nofs:
    mov dx, msg_nofs
    call puts
    mov ax, 0x4C01
    int 0x21

; print the volume label, taken from root directory entry 0
show_label:
    mov si, dirbuf
    mov al, [si+11]
    test al, 0x08
    jz .none
    mov cx, 8
.p1:
    mov al, [si]
    cmp al, ' '
    je .sk1
    call putchar
.sk1:
    inc si
    loop .p1
    cmp byte [si], ' '
    je .done
    mov al, '.'
    call putchar
    mov cx, 3
.p2:
    mov al, [si]
    cmp al, ' '
    je .sk2
    call putchar
.sk2:
    inc si
    loop .p2
.done:
    ret
.none:
    mov dx, msg_none
    call puts
    ret

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

; DX:AX -> decimal
putdec32:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov cx, 0
.conv:
    mov bx, 10
    mov si, ax                ; low word
    mov ax, dx                ; high word / 10
    xor dx, dx
    div bx
    mov di, ax                ; quotient of the high word
    mov ax, si                ; (remainder):low / 10
    div bx
    push dx                   ; digit
    inc cx
    mov dx, di                ; new high word
    mov bx, ax
    or bx, dx
    jnz .conv
.out:
    pop ax
    add al, '0'
    call putchar
    loop .out
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

secsize   dw 0
spc       dw 0
reserved  dw 0
nfats     dw 0
rootents  dw 0
total     dw 0
fatsecs   dw 0
rootsecs  dw 0
datastart dw 0
nclust    dw 0
freec     dw 0
ci        dw 0
files     dw 0
dirs      dw 0
bootbuf   times 512 db 0
fatbuf    times 4608 db 0
dirbuf    times 512 db 0

msg_crlf   db 13, 10, "$"
msg_head   db "ZiggyDOS CHKDSK", 13, 10, "$"
msg_nofs   db "Not a FAT volume in drive A:", 13, 10, "$"
msg_vol    db "Volume label: ", "$"
msg_none   db "(no label)", "$"
msg_indent db "  ", "$"
msg_total_line db " bytes total disk space", 13, 10, "$"
msg_avail_line db " bytes available on disk", 13, 10, "$"
msg_unit_line  db " bytes in each allocation unit", 13, 10, "$"
msg_clust_line db " allocation units on disk", 13, 10, "$"
msg_cfree_line db " allocation units available on disk", 13, 10, "$"
msg_files_line db " files, ", "$"
msg_dirs_line  db " directories", 13, 10, "$"
