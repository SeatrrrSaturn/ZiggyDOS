; =============================================================================
;  ZiggyDOS - FAT12 filesystem
;  Reads the BPB out of the boot sector, keeps one FAT and the root directory
;  resident in memory, and implements cluster chains, directory scanning and
;  file creation / deletion / rename on a real FAT12 volume.
; =============================================================================

; ---------------------------------------------------------------------------
;  fat_init - read the BPB and cache the FAT and root directory
;    out: CF = 1 if the volume cannot be used
; ---------------------------------------------------------------------------
fat_init:
    xor ax, ax
    mov cx, 1
    mov bx, BUF_SEG
    mov es, bx
    mov bx, SEC_OFF
    call disk_read
    jc .fail

    mov ax, BUF_SEG
    mov es, ax
    mov si, SEC_OFF

    mov ax, [es:si+0x0B]          ; bytes per sector
    mov [fat_bps], ax
    mov al, [es:si+0x0D]          ; sectors per cluster
    xor ah, ah
    mov [fat_sec_per_clu], ax
    mov ax, [es:si+0x0E]          ; reserved sectors
    mov [fat_reserved], ax
    mov al, [es:si+0x10]          ; number of FATs
    xor ah, ah
    mov [fat_num_fats], ax
    mov ax, [es:si+0x11]          ; root directory entries
    mov [fat_root_ents], ax
    mov ax, [es:si+0x13]          ; total sectors
    mov [fat_total], ax
    mov ax, [es:si+0x16]          ; sectors per FAT
    mov [fat_fat_secs], ax
    mov ax, [es:si+0x18]          ; sectors per track
    mov [disk_spt], ax
    mov ax, [es:si+0x1A]          ; heads
    mov [disk_heads], ax

    ; --- volume layout ---------------------------------------------------
    mov ax, [fat_reserved]
    mov [fat_start_lba], ax

    mov ax, [fat_num_fats]
    mov bx, [fat_fat_secs]
    mul bx
    add ax, [fat_reserved]
    mov [fat_root_lba], ax

    mov ax, [fat_root_ents]
    mov cl, 5                     ; 32 bytes per entry
    shl ax, cl
    xor dx, dx
    mov bx, [fat_bps]
    div bx
    mov [fat_root_secs], ax

    mov ax, [fat_root_lba]
    add ax, [fat_root_secs]
    mov [fat_data_lba], ax

    mov ax, [fat_total]
    sub ax, [fat_data_lba]
    xor dx, dx
    mov bx, [fat_sec_per_clu]
    div bx
    mov [fat_clusters], ax

    ; --- cache the first FAT and the root directory -----------------------
    mov ax, [fat_start_lba]
    mov cx, [fat_fat_secs]
    mov bx, BUF_SEG
    mov es, bx
    mov bx, FAT_OFF
    call disk_read
    jc .fail

    mov ax, [fat_root_lba]
    mov cx, [fat_root_secs]
    mov bx, BUF_SEG
    mov es, bx
    mov bx, ROOT_OFF
    call disk_read
    jc .fail

    mov ax, [fat_root_lba]
    mov [dir_start_lba], ax
    mov ax, [fat_root_secs]
    mov [dir_secs], ax
    mov word [dir_buf_off], ROOT_OFF
    mov ax, [fat_root_ents]
    mov [dir_count], ax

    mov word [fat_dirty], 0
    clc
    ret
.fail:
    stc
    ret

; ---------------------------------------------------------------------------
;  fat_flush - write the cached FAT back to both copies if it was modified
; ---------------------------------------------------------------------------
fat_flush:
    cmp word [fat_dirty], 0
    je .done
    mov ax, [fat_start_lba]
    mov cx, [fat_fat_secs]
    mov bx, BUF_SEG
    mov es, bx
    mov bx, FAT_OFF
    call disk_write
    jc .done
    mov ax, [fat_start_lba]
    add ax, [fat_fat_secs]
    mov cx, [fat_fat_secs]
    mov bx, BUF_SEG
    mov es, bx
    mov bx, FAT_OFF
    call disk_write
    mov word [fat_dirty], 0
.done:
    ret

; ---------------------------------------------------------------------------
;  fat_get - next cluster of a chain
;    in : AX = cluster
;    out: AX = next cluster (0xFF8..0xFFF marks end of chain)
; ---------------------------------------------------------------------------
fat_get:
    push bx
    push cx
    push dx
    push es
    mov cx, ax
    mov bx, 3
    mul bx                        ; DX:AX = 3 * cluster
    shr ax, 1                     ; AX = 1.5 * cluster
    mov bx, ax
    mov ax, BUF_SEG
    mov es, ax
    mov ax, [es:bx+FAT_OFF]
    test cl, 1
    jz .even
    shr ax, 4
    jmp .done
.even:
    and ax, 0x0FFF
.done:
    pop es
    pop dx
    pop cx
    pop bx
    ret

; ---------------------------------------------------------------------------
;  fat_set - write a cluster entry
;    in : AX = cluster, DX = value
; ---------------------------------------------------------------------------
fat_set:
    push ax
    push bx
    push cx
    push dx
    push si
    push es
    mov cx, ax
    mov si, dx
    and si, 0x0FFF
    mov ax, cx
    mov bx, 3
    mul bx
    shr ax, 1
    mov bx, ax
    mov ax, BUF_SEG
    mov es, ax
    mov dx, [es:bx+FAT_OFF]
    test cl, 1
    jz .even
    and dx, 0x000F
    shl si, 4
    or dx, si
    jmp .store
.even:
    and dx, 0xF000
    or dx, si
.store:
    mov [es:bx+FAT_OFF], dx
    mov word [fat_dirty], 1
    pop es
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
;  fat_alloc - allocate one free cluster and terminate its chain
;    out: AX = cluster, CF = 1 when the disk is full
; ---------------------------------------------------------------------------
fat_alloc:
    push bx
    push cx
    push dx
    mov cx, 2
.loop:
    mov dx, [fat_clusters]
    inc dx
    cmp cx, dx
    ja .full
    mov ax, cx
    call fat_get
    test ax, ax
    jnz .next
    mov ax, cx
    mov dx, 0x0FFF
    call fat_set
    mov ax, cx
    clc
    jmp .done
.next:
    inc cx
    jmp .loop
.full:
    stc
.done:
    pop dx
    pop cx
    pop bx
    ret

; ---------------------------------------------------------------------------
;  fat_free_chain - release every cluster of a chain
;    in : AX = first cluster
; ---------------------------------------------------------------------------
fat_free_chain:
    push bx
    push cx
    push dx
    mov bx, ax
.loop:
    cmp bx, 0x0FF8
    jae .done
    cmp bx, 2
    jb .done
    mov ax, bx
    call fat_get
    push ax
    mov ax, bx
    xor dx, dx
    call fat_set
    pop ax
    mov bx, ax
    jmp .loop
.done:
    pop dx
    pop cx
    pop bx
    ret

; ---------------------------------------------------------------------------
;  fat_cluster_lba - turn a cluster number into its first LBA
;    in : AX = cluster
;    out: AX = LBA
; ---------------------------------------------------------------------------
fat_cluster_lba:
    push bx
    push dx
    sub ax, 2
    mov bx, [fat_sec_per_clu]
    mul bx
    add ax, [fat_data_lba]
    pop dx
    pop bx
    ret

; ---------------------------------------------------------------------------
;  load_dir - bring a directory into the cache
;    in : AX = cluster (0 for the root directory)
;    out: dir_buf_off / dir_start_lba / dir_secs / dir_count updated
; ---------------------------------------------------------------------------
load_dir:
    cld
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es
    test ax, ax
    jnz .subdir
    mov word [dir_buf_off], ROOT_OFF
    mov ax, [fat_root_lba]
    mov [dir_start_lba], ax
    mov ax, [fat_root_secs]
    mov [dir_secs], ax
    mov ax, [fat_root_ents]
    mov [dir_count], ax
    clc
    jmp .done
.subdir:
    mov si, ax                    ; cluster walker
    mov ax, [fat_sec_per_clu]
    shl ax, 9
    mov [ld_cluster_bytes], ax
    mov word [dir_buf_off], DIR_OFF
    mov ax, si
    call fat_cluster_lba
    mov [dir_start_lba], ax
    mov di, 0                     ; bytes transferred
    mov bx, DIR_OFF               ; destination offset
.read_cluster:
    mov ax, si
    call fat_cluster_lba
    push ax
    mov ax, BUF_SEG
    mov es, ax
    mov bx, [dir_buf_off]
    add bx, di
    mov cx, [fat_sec_per_clu]
    pop ax
    call disk_read
    jc .done
    mov ax, [ld_cluster_bytes]
    add di, ax
    cmp di, DIR_SIZE
    jae .stop
    mov ax, si
    call fat_get
    mov si, ax
    cmp si, 0x0FF8
    jb .read_cluster
.stop:
    mov ax, di
    xor dx, dx
    mov bx, [fat_bps]
    div bx
    mov [dir_secs], ax            ; sectors actually present
    mov ax, di
    xor dx, dx
    mov bx, DIRENT_SIZE
    div bx
    mov [dir_count], ax
    clc
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
;  find_entry - look a name up inside the directory currently loaded
;    in : DS:SI -> 11 byte upper case name ("README  TXT")
;    out: AX = byte offset of the entry, CF = 1 when not found
; ---------------------------------------------------------------------------
find_entry:
    cld
    push bx
    push cx
    push dx
    push si
    push di
    push es
    mov ax, BUF_SEG
    mov es, ax
    mov bx, [dir_buf_off]
    mov cx, [dir_count]
.scan:
    test cx, cx
    jz .notfound
    mov al, [es:bx]
    test al, al
    jz .notfound
    cmp al, 0xE5
    je .next
    mov al, [es:bx+11]
    cmp al, ATTR_LFN
    je .next
    push cx
    mov si, chi_name
    mov di, bx
    mov cx, 11
    repe cmpsb                    ; DS:SI vs ES:DI
    pop cx
    jne .next
    mov ax, bx
    clc
    jmp .done
.next:
    add bx, DIRENT_SIZE
    dec cx
    jmp .scan
.notfound:
    stc
.done:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    ret

; ---------------------------------------------------------------------------
;  entry_cluster / entry_size / entry_attr helpers
;    in : AX = entry offset in the loaded directory buffer
; ---------------------------------------------------------------------------
entry_cluster:
    push bx
    push es
    mov bx, ax
    mov ax, BUF_SEG
    mov es, ax
    mov ax, [es:bx+26]
    pop es
    pop bx
    ret

entry_size:
    push bx
    push es
    mov bx, ax
    mov ax, BUF_SEG
    mov es, ax
    mov ax, [es:bx+28]
    pop es
    pop bx
    ret

entry_attr:
    push bx
    push es
    mov bx, ax
    mov ax, BUF_SEG
    mov es, ax
    mov al, [es:bx+11]
    xor ah, ah
    pop es
    pop bx
    ret

; ---------------------------------------------------------------------------
;  dir_flush - write the loaded directory back to disk
;    in : AX = cluster of the directory (0 = root)
; ---------------------------------------------------------------------------
dir_flush:
    cld
    push ax
    push bx
    push cx
    push dx
    test ax, ax
    jnz .subdir
    mov ax, [fat_root_lba]
    mov cx, [fat_root_secs]
    mov bx, BUF_SEG
    mov es, bx
    mov bx, ROOT_OFF
    call disk_write
    jmp .done
.subdir:
    mov si, ax
    mov di, 0
.write_cluster:
    mov ax, si
    call fat_cluster_lba
    push ax
    mov ax, BUF_SEG
    mov es, ax
    mov bx, [dir_buf_off]
    add bx, di
    mov cx, [fat_sec_per_clu]
    pop ax
    call disk_write
    jc .done
    mov ax, [fat_sec_per_clu]
    shl ax, 9
    add di, ax
    cmp di, DIR_SIZE
    jae .done
    mov ax, si
    call fat_get
    mov si, ax
    cmp si, 0x0FF8
    jb .write_cluster
.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
;  file_read - read part of a file into a buffer
;    in : AX = first cluster, CX = byte count, ES:BX = destination
;    out: AX = bytes actually transferred
; ---------------------------------------------------------------------------
file_read:
    cld
    push bx
    push cx
    push dx
    push si
    push di
    push es
    mov [fr_cluster], ax
    mov [fr_rem], cx
    mov [fr_dseg], es
    mov [fr_doff], bx
    mov word [fr_done], 0
.loop:
    cmp word [fr_rem], 0
    je .finish
    mov ax, [fr_cluster]
    cmp ax, 0x0FF8
    jae .finish
    cmp ax, 2
    jb .finish
    call fat_cluster_lba
    mov cx, 1
    mov bx, BUF_SEG
    mov es, bx
    mov bx, SEC_OFF
    call disk_read
    jc .finish

    mov cx, [fr_rem]
    cmp cx, 512
    jbe .have_len
    mov cx, 512
.have_len:
    push cx
    mov ax, [fr_dseg]
    mov es, ax
    mov di, [fr_doff]
    mov ax, BUF_SEG
    mov ds, ax
    mov si, SEC_OFF
    rep movsb
    mov ax, cs
    mov ds, ax
    pop cx
    mov ax, cs
    mov ds, ax

    mov ax, [fr_done]
    add ax, cx
    mov [fr_done], ax
    sub [fr_rem], cx
    mov ax, [fr_doff]
    add ax, cx
    mov [fr_doff], ax
    jnc .noseg
    mov ax, [fr_dseg]
    add ax, 0x1000
    mov [fr_dseg], ax
.noseg:

    mov ax, [fr_cluster]
    call fat_get
    mov [fr_cluster], ax
    jmp .loop
.finish:
    mov ax, [fr_done]
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    ret

; ---------------------------------------------------------------------------
;  cluster_write_sector - write the 512 byte scratch sector to a cluster
;    in : AX = cluster, ES:BX = source buffer
; ---------------------------------------------------------------------------
cluster_write:
    push ax
    push cx
    push es
    mov [cw_srcseg], es
    mov [cw_srcoff], bx
    call fat_cluster_lba
    mov cx, 1
    mov es, [cw_srcseg]
    mov bx, [cw_srcoff]
    call disk_write
    pop es
    pop cx
    pop ax
    ret

; ---------------------------------------------------------------------------
;  dir_find_free - locate a free (or end-of-directory) entry slot
;    out: AX = offset, CF = 1 if the directory is full
; ---------------------------------------------------------------------------
dir_find_free:
    push bx
    push cx
    push es
    mov ax, BUF_SEG
    mov es, ax
    mov bx, [dir_buf_off]
    mov cx, [dir_count]
.scan:
    test cx, cx
    jz .full
    cmp byte [es:bx], 0x00
    je .found
    cmp byte [es:bx], 0xE5
    je .found
    add bx, DIRENT_SIZE
    dec cx
    jmp .scan
.full:
    stc
    jmp .done
.found:
    mov ax, bx
    clc
.done:
    pop es
    pop cx
    pop bx
    ret

; ---------------------------------------------------------------------------
;  dir_set_entry - fill in a brand new directory entry
;    in : AX = offset, DS:SI = 11 byte name, DL = attribute,
;         BX = first cluster, CX = size in bytes (low word)
; ---------------------------------------------------------------------------
dir_set_entry:
    cld
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es
    mov [dse_off], ax
    mov [dse_attr], dl
    mov [dse_clus], bx
    mov [dse_size], cx
    mov ax, BUF_SEG
    mov es, ax
    mov di, [dse_off]
    mov cx, 11
    rep movsb
    mov al, [dse_attr]
    mov [es:di], al
    mov byte [es:di+1], 0         ; NT reserved
    mov byte [es:di+2], 0         ; creation time, tenths
    mov word [es:di+3], 0         ; creation time
    mov word [es:di+5], 0         ; creation date
    mov word [es:di+7], 0         ; last access date
    mov word [es:di+9], 0         ; high cluster

    ; --- write time: ((hour << 6) | minute) << 5 | seconds / 2 -----------
    call rtc_get_time
    mov al, ch
    xor ah, ah
    shl ax, 6
    mov bl, cl
    xor bh, bh
    or ax, bx
    shl ax, 5
    mov bl, dh
    xor bh, bh
    shr bx, 1
    or ax, bx
    mov [es:di+11], ax

    ; --- write date: ((year - 1980) << 9) | (month << 5) | day -----------
    call rtc_get_date
    mov ax, cx
    sub ax, 1980
    mov cl, 9
    shl ax, cl
    mov bl, dh
    xor bh, bh
    shl bx, 5
    or ax, bx
    mov bl, dl
    xor bh, bh
    or ax, bx
    mov [es:di+13], ax

    mov ax, [dse_clus]
    mov [es:di+15], ax
    mov ax, [dse_size]
    mov [es:di+17], ax
    mov word [es:di+19], 0
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
fat_bps           dw 512
fat_sec_per_clu   dw 1
fat_reserved      dw 1
fat_num_fats      dw 2
fat_root_ents     dw 224
fat_total         dw 2880
fat_fat_secs      dw 9
fat_start_lba     dw 1
fat_root_lba      dw 19
fat_root_secs     dw 14
fat_data_lba      dw 33
fat_clusters      dw 2847
fat_dirty         dw 0

dir_buf_off       dw ROOT_OFF
dir_start_lba     dw 19
dir_secs          dw 14
dir_count         dw 224

ld_cluster_bytes  dw 512

dse_off           dw 0
dse_attr          db 0
dse_clus          dw 0
dse_size          dw 0

fr_cluster        dw 0
fr_rem            dw 0
fr_dseg           dw 0
fr_doff           dw 0
fr_done           dw 0

cw_srcseg         dw 0
cw_srcoff         dw 0

cur_dir_cluster   dw 0
