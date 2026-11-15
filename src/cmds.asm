; =============================================================================
;  ZiggyDOS - built-in commands
; =============================================================================

; ---------------------------------------------------------------------------
;  cmd_ver
; ---------------------------------------------------------------------------
cmd_ver:
    mov si, msg_version
    call puts
    ret

; ---------------------------------------------------------------------------
;  cmd_cls
; ---------------------------------------------------------------------------
cmd_cls:
    mov ax, 0x0003
    int 0x10
    ret

; ---------------------------------------------------------------------------
;  cmd_echo
; ---------------------------------------------------------------------------
cmd_echo:
    call skip_spaces
    cmp byte [si], 0
    je .blank
    call puts
    call newline
    ret
.blank:
    call newline
    ret

; ---------------------------------------------------------------------------
;  cmd_vol
; ---------------------------------------------------------------------------
cmd_vol:
    mov si, msg_vol_line
    call puts
    ret

; ---------------------------------------------------------------------------
;  cmd_date / cmd_time
; ---------------------------------------------------------------------------
cmd_date:
    call rtc_get_date
    push cx
    push dx
    mov si, msg_date_prefix
    call puts
    pop dx
    pop cx
    mov al, dh                    ; month
    xor ah, ah
    call put2
    mov al, '-'
    call putchar
    mov al, dl                    ; day
    xor ah, ah
    call put2
    mov al, '-'
    call putchar
    mov ax, cx
    call put_number_free
    call newline
    ret

cmd_time:
    call rtc_get_time
    push cx
    push dx
    mov si, msg_time_prefix
    call puts
    pop dx
    pop cx
    mov al, ch                    ; hour
    xor ah, ah
    call put2
    mov al, ':'
    call putchar
    mov al, cl                    ; minute
    xor ah, ah
    call put2
    mov al, ':'
    call putchar
    mov al, dh                    ; second
    xor ah, ah
    call put2
    call newline
    ret

; ---------------------------------------------------------------------------
;  cmd_mem
; ---------------------------------------------------------------------------
cmd_mem:
    mov si, msg_mem1
    call puts
    mov si, msg_mem2
    call puts
    mov si, msg_mem3
    call puts
    mov ax, [fat_clusters]
    call put_number_free
    call newline
    ret

; ---------------------------------------------------------------------------
;  cmd_help
; ---------------------------------------------------------------------------
cmd_help:
    mov si, msg_help
    call puts
    ret

; ---------------------------------------------------------------------------
;  cmd_exit
; ---------------------------------------------------------------------------
cmd_exit:
    mov si, msg_reboot
    call puts
    int 0x19
    ret

; ---------------------------------------------------------------------------
;  cmd_dir
; ---------------------------------------------------------------------------
cmd_dir:
    call skip_spaces
    cmp byte [si], 0
    je .current
    call resolve_path
    jc .not_found
    cmp byte [rp_self], 1
    je .is_dir
    mov al, [rp_attr]
    test al, ATTR_DIR
    jnz .is_dir
    ; single file
    mov si, msg_dir_of
    call puts
    mov si, cur_dir_path
    call puts
    call newline
    call newline
    ; reload parent directory and print just that entry
    mov ax, [rp_dir]
    call load_dir
    mov bx, [rp_entry_off]
    mov ax, BUF_SEG
    mov es, ax
    call print_entry_line
    call newline
    ret
.is_dir:
    mov ax, [rp_cluster]
    call load_dir
    jmp .list
.current:
    mov ax, [cur_dir_cluster]
    call load_dir
.list:
    mov si, msg_vol_line
    call puts
    mov si, msg_dir_of
    call puts
    mov si, cur_dir_path
    call puts
    call newline
    call newline

    mov ax, BUF_SEG
    mov es, ax
    mov bx, [dir_buf_off]
    mov cx, [dir_count]
    mov word [dir_files], 0
    mov word [dir_dirs], 0
    mov word [dir_bytes_lo], 0
    mov word [dir_bytes_hi], 0
.scan:
    test cx, cx
    jz .summary
    mov al, [es:bx]
    test al, al
    jz .summary
    cmp al, 0xE5
    je .skip
    mov al, [es:bx+11]
    cmp al, ATTR_LFN
    je .skip
    test al, ATTR_VOLUME
    jnz .skip
    push bx
    call print_entry_line
    call newline
    pop bx
    ; --- accumulate statistics -------------------------------------------
    mov al, [es:bx+11]
    test al, ATTR_DIR
    jnz .stat_dir
    inc word [dir_files]
    mov ax, [es:bx+28]
    add [dir_bytes_lo], ax
    jnc .stat_done
    inc word [dir_bytes_hi]
    jmp .stat_done
.stat_dir:
    inc word [dir_dirs]
.stat_done:
.skip:
    add bx, DIRENT_SIZE
    dec cx
    jmp .scan
.summary:
    call newline
    mov si, msg_files_count
    call puts
    mov ax, [dir_files]
    call put_number_free
    mov si, msg_dirs_count
    call puts
    mov ax, [dir_dirs]
    call put_number_free
    mov si, msg_bytes_count
    call puts
    mov ax, [dir_bytes_lo]
    call put_number_free
    mov si, msg_bytes_tail
    call puts
    ret
.not_found:
    mov si, msg_file_not_found
    call puts
    ret

; ---------------------------------------------------------------------------
;  cmd_type
; ---------------------------------------------------------------------------
cmd_type:
    call skip_spaces
    cmp byte [si], 0
    je .usage
    call resolve_path
    jc .not_found
    mov al, [rp_attr]
    test al, ATTR_DIR
    jnz .is_dir
    mov ax, [rp_cluster]
    mov [ty_cluster], ax
    mov ax, [rp_size]
    mov [ty_rem], ax
.loop:
    cmp word [ty_rem], 0
    je .done
    mov cx, 512
    mov ax, [ty_rem]
    cmp ax, 512
    jae .full
    mov cx, ax
.full:
    mov ax, [ty_cluster]
    mov bx, BUF_SEG
    mov es, bx
    mov bx, SEC_OFF
    call file_read
    ; --- display the bytes -----------------------------------------------
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
    cmp al, 0x1A
    je .stop
    push cx
    push si
    push es
    call putchar
    pop es
    pop si
    pop cx
    dec cx
    jmp .out
.out_done:
    pop es
    mov ax, [ty_cluster]
    call fat_get
    mov [ty_cluster], ax
    mov ax, [ty_rem]
    sub ax, 512
    jnc .store
    xor ax, ax
.store:
    mov [ty_rem], ax
    jmp .loop
.stop:
    pop es
.done:
    mov si, msg_crlf
    call puts
    ret
.usage:
    mov si, msg_syntax_type
    call puts
    ret
.is_dir:
    mov si, msg_is_dir
    call puts
    ret
.not_found:
    mov si, msg_file_not_found
    call puts
    ret

; ---------------------------------------------------------------------------
;  cmd_cd
; ---------------------------------------------------------------------------
cmd_cd:
    call skip_spaces
    cmp byte [si], 0
    je .show
    push si
    call resolve_path
    jc .bad
    mov al, [rp_attr]
    test al, ATTR_DIR
    jz .bad
    mov ax, [rp_cluster]
    mov [cur_dir_cluster], ax
    pop si
    call update_path
    ret
.bad:
    pop si
    mov si, msg_bad_path
    call puts
    ret
.show:
    mov si, cur_dir_path
    call puts
    call newline
    ret

; ---------------------------------------------------------------------------
;  update_path - rewrite cur_dir_path after a successful CD
;    in : DS:SI = the argument that was given to CD
; ---------------------------------------------------------------------------
update_path:
    push ax
    push di
.wait:
    cmp byte [si], ' '
    jne .go
    inc si
    jmp .wait
.go:
    cmp byte [si], 0
    je .done
    cmp byte [si], '.'
    jne .not_dot
    cmp byte [si+1], 0
    je .done
    cmp byte [si+1], '.'
    jne .not_dot
    cmp byte [si+2], 0
    je .to_parent
.not_dot:
    cmp byte [si], '\'
    je .absolute
    ; --- append ---------------------------------------------------------
    mov di, cur_dir_path
.find_end:
    cmp byte [di], 0
    je .at_end
    inc di
    jmp .find_end
.at_end:
    cmp di, cur_dir_path
    je .no_sep
    cmp byte [di-1], '\'
    je .no_sep
    mov byte [di], '\'
    inc di
.no_sep:
    jmp .copy_rel
.absolute:
    mov di, cur_dir_path
.copy_abs:
    mov al, [si]
    test al, al
    jz .abs_end
    call upper_char
    mov [di], al
    inc si
    inc di
    jmp .copy_abs
.abs_end:
    mov byte [di], 0
    jmp .done
.copy_rel:
    mov al, [si]
    test al, al
    jz .rel_end
    call upper_char
    mov [di], al
    inc si
    inc di
    jmp .copy_rel
.rel_end:
    mov byte [di], 0
    jmp .done
.to_parent:
    mov di, cur_dir_path
.find_e:
    cmp byte [di], 0
    je .trim
    inc di
    jmp .find_e
.trim:
    cmp di, cur_dir_path+1
    jbe .root
.trim_loop:
    cmp di, cur_dir_path
    jbe .root
    cmp byte [di], '\'
    je .cut
    dec di
    jmp .trim_loop
.cut:
    cmp di, cur_dir_path
    je .root
    mov byte [di], 0
    jmp .done
.root:
    mov byte [cur_dir_path], '\'
    mov byte [cur_dir_path+1], 0
.done:
    pop di
    pop ax
    ret

; ---------------------------------------------------------------------------
;  cmd_del
; ---------------------------------------------------------------------------
cmd_del:
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
    call fat_free_chain
    ; --- mark the directory entry as deleted ------------------------------
    mov ax, [rp_dir]
    call load_dir
    mov ax, BUF_SEG
    mov es, ax
    mov bx, [rp_entry_off]
    mov byte [es:bx], 0xE5
    mov ax, [rp_dir]
    call dir_flush
    call fat_flush
    ret
.usage:
    mov si, msg_syntax_del
    call puts
    ret
.is_dir:
    mov si, msg_is_dir
    call puts
    ret
.not_found:
    mov si, msg_file_not_found
    call puts
    ret

; ---------------------------------------------------------------------------
;  cmd_ren - rename OLD NEW
; ---------------------------------------------------------------------------
cmd_ren:
    cld
    call skip_spaces
    cmp byte [si], 0
    je .usage
    push si
    call resolve_path
    jc .not_found_pop
    pop si
    ; --- get the new name -------------------------------------------------
.skip_old:
    mov al, [si]
    test al, al
    jz .usage
    cmp al, ' '
    je .after_old
    inc si
    jmp .skip_old
.after_old:
    call skip_spaces
    cmp byte [si], 0
    je .usage
    call name_to_83
    jc .bad_name
    mov ax, [rp_dir]
    call load_dir
    mov ax, BUF_SEG
    mov es, ax
    mov bx, [rp_entry_off]
    mov si, chi_name
    mov di, bx
    mov cx, 11
.copy:
    mov al, [si]
    mov [es:di], al
    inc si
    inc di
    dec cx
    jnz .copy
    mov ax, [rp_dir]
    call dir_flush
    ret
.usage:
    mov si, msg_syntax_ren
    call puts
    ret
.bad_name:
    mov si, msg_bad_name
    call puts
    ret
.not_found_pop:
    pop si
    mov si, msg_file_not_found
    call puts
    ret

; ---------------------------------------------------------------------------
;  cmd_md - make a directory
; ---------------------------------------------------------------------------
cmd_md:
    cld
    call skip_spaces
    cmp byte [si], 0
    je .usage
    call split_path
    mov si, split_dir
    call resolve_path
    jc .bad_path
    mov al, [rp_attr]
    test al, ATTR_DIR
    jz .bad_path
    mov ax, [rp_cluster]
    mov [md_parent], ax
    call load_dir
    ; --- does it already exist? ------------------------------------------
    mov si, split_name
    call name_to_83
    jc .bad_name
    mov si, chi_name
    call find_entry
    jnc .exists
    ; --- allocate the first cluster of the new directory ------------------
    call fat_alloc
    jc .disk_full
    mov [md_cluster], ax
    ; --- build the "." and ".." entries in the scratch sector -------------
    call build_empty_dir
    ; --- write it out -----------------------------------------------------
    mov ax, [md_cluster]
    mov bx, BUF_SEG
    mov es, bx
    mov bx, SEC_OFF
    call cluster_write
    ; --- add the entry to the parent --------------------------------------
    mov ax, [md_parent]
    call load_dir
    call dir_find_free
    jc .dir_full
    mov bx, [md_cluster]
    xor cx, cx
    mov dl, ATTR_DIR
    mov si, chi_name
    call dir_set_entry
    mov ax, [md_parent]
    call dir_flush
    call fat_flush
    ret
.usage:
    mov si, msg_syntax_md
    call puts
    ret
.exists:
    mov si, msg_exists
    call puts
    ret
.disk_full:
    mov si, msg_disk_full
    call puts
    ret
.dir_full:
    mov si, msg_dir_full
    call puts
    ret
.bad_path:
    mov si, msg_bad_path
    call puts
    ret
.bad_name:
    mov si, msg_bad_name
    call puts
    ret

; ---------------------------------------------------------------------------
;  build_empty_dir - fill the scratch sector with "." and ".." entries
; ---------------------------------------------------------------------------
build_empty_dir:
    push ax
    push cx
    push di
    push es
    mov ax, BUF_SEG
    mov es, ax
    mov di, SEC_OFF
    mov cx, 256
    xor ax, ax
    rep stosw
    ; --- "." --------------------------------------------------------------
    mov di, SEC_OFF
    mov al, '.'
    mov [es:di], al
    ; --- ".."  ------------------------------------------------------------
    mov di, SEC_OFF+DIRENT_SIZE
    mov al, '.'
    mov [es:di], al
    mov [es:di+1], al
    ; --- names are padded with blanks ------------------------------------
    mov di, SEC_OFF
    mov cx, 10
    mov al, ' '
.pad1:
    mov [es:di+1], al
    inc di
    dec cx
    jnz .pad1
    mov di, SEC_OFF+DIRENT_SIZE
    mov cx, 9
.pad2:
    mov [es:di+2], al
    inc di
    dec cx
    jnz .pad2
    ; --- attributes and clusters -----------------------------------------
    mov byte [es:SEC_OFF+11], ATTR_DIR
    mov ax, [md_cluster]
    mov [es:SEC_OFF+26], ax
    mov byte [es:SEC_OFF+DIRENT_SIZE+11], ATTR_DIR
    mov ax, [md_parent]
    mov [es:SEC_OFF+DIRENT_SIZE+26], ax
    pop es
    pop di
    pop cx
    pop ax
    ret

; ---------------------------------------------------------------------------
;  cmd_rd - remove a directory
; ---------------------------------------------------------------------------
cmd_rd:
    call skip_spaces
    cmp byte [si], 0
    je .usage
    push si
    call resolve_path
    jc .not_found_pop
    pop si
    cmp byte [rp_self], 1
    je .bad
    mov al, [rp_attr]
    test al, ATTR_DIR
    jz .bad
    ; --- refuse to remove the current directory ---------------------------
    mov ax, [rp_cluster]
    cmp ax, [cur_dir_cluster]
    je .bad
    mov [rd_cluster], ax
    ; --- is it empty? -----------------------------------------------------
    call load_dir
    mov ax, BUF_SEG
    mov es, ax
    mov bx, [dir_buf_off]
    mov cx, [dir_count]
.scan:
    test cx, cx
    jz .empty
    mov al, [es:bx]
    test al, al
    jz .empty
    cmp al, 0xE5
    je .next
    mov al, [es:bx+11]
    cmp al, ATTR_LFN
    je .next
    ; "." and ".." are allowed
    cmp byte [es:bx], '.'
    jne .not_empty
.next:
    add bx, DIRENT_SIZE
    dec cx
    jmp .scan
.empty:
    ; --- free the cluster chain and drop the entry ------------------------
    mov ax, [rd_cluster]
    call fat_free_chain
    mov ax, [rp_dir]
    call load_dir
    mov ax, BUF_SEG
    mov es, ax
    mov bx, [rp_entry_off]
    mov byte [es:bx], 0xE5
    mov ax, [rp_dir]
    call dir_flush
    call fat_flush
    ret
.not_empty:
    mov si, msg_dir_not_empty
    call puts
    ret
.usage:
    mov si, msg_syntax_rd
    call puts
    ret
.bad:
    mov si, msg_bad_path
    call puts
    ret
.not_found_pop:
    pop si
    mov si, msg_file_not_found
    call puts
    ret

; ---------------------------------------------------------------------------
;  cmd_copy - copy SRC DST
; ---------------------------------------------------------------------------
cmd_copy:
    cld
    call skip_spaces
    cmp byte [si], 0
    je .usage
    push si
    call resolve_path
    jc .not_found_pop
    mov al, [rp_attr]
    test al, ATTR_DIR
    jnz .is_dir_pop
    mov ax, [rp_cluster]
    mov [cp_src_cluster], ax
    mov ax, [rp_size]
    mov [cp_size], ax
    mov [cp_rem], ax
    pop si
    ; --- destination name -------------------------------------------------
.skip_src:
    mov al, [si]
    test al, al
    jz .usage
    cmp al, ' '
    je .after_src
    inc si
    jmp .skip_src
.after_src:
    call skip_spaces
    cmp byte [si], 0
    je .usage
    call split_path
    mov si, split_dir
    call resolve_path
    jc .bad_path
    mov ax, [rp_cluster]
    mov [cp_dst_dir], ax
    call load_dir
    mov si, split_name
    call name_to_83
    jc .bad_name
    ; --- delete an existing target ---------------------------------------
    mov si, chi_name
    call find_entry
    jc .create
    push ax
    call entry_cluster
    call fat_free_chain
    mov ax, BUF_SEG
    mov es, ax
    pop bx
    mov byte [es:bx], 0xE5
    jmp .create
.create:
    call dir_find_free
    jc .dir_full
    mov word [cp_dst_first], 0
    mov word [cp_prev], 0
    ; --- create the entry with cluster 0, fill it in later ---------------
    mov bx, 0
    xor cx, cx
    mov dl, ATTR_ARCHIVE
    mov si, chi_name
    call dir_set_entry
    mov ax, [cp_dst_dir]
    call dir_flush
    ; --- copy the clusters ------------------------------------------------
    mov ax, [cp_src_cluster]
    mov [cp_src], ax
.copy_loop:
    cmp word [cp_rem], 0
    je .copy_end
    ; read a sector of the source
    mov ax, [cp_src]
    call fat_cluster_lba
    mov cx, 1
    mov bx, BUF_SEG
    mov es, bx
    mov bx, SEC_OFF
    call disk_read
    jc .read_error
    ; allocate the destination cluster
    call fat_alloc
    jc .disk_full
    mov [cp_new], ax
    ; link it into the chain
    cmp word [cp_prev], 0
    jne .link
    mov [cp_dst_first], ax
    jmp .write_it
.link:
    mov dx, ax
    mov ax, [cp_prev]
    call fat_set
.write_it:
    mov ax, [cp_new]
    mov bx, BUF_SEG
    mov es, bx
    mov bx, SEC_OFF
    call cluster_write
    ; advance
    mov ax, [cp_new]
    mov [cp_prev], ax
    mov ax, [cp_src]
    call fat_get
    mov [cp_src], ax
    mov ax, [cp_rem]
    sub ax, 512
    jnc .store_rem
    xor ax, ax
.store_rem:
    mov [cp_rem], ax
    jmp .copy_loop
.copy_end:
    ; --- patch the size and first cluster into the directory entry --------
    mov ax, [cp_dst_dir]
    call load_dir
    mov si, chi_name
    call find_entry
    jc .done
    mov bx, ax
    mov ax, BUF_SEG
    mov es, ax
    mov ax, [cp_dst_first]
    mov [es:bx+26], ax
    mov ax, [cp_size]
    mov [es:bx+28], ax
    mov word [es:bx+30], 0
    mov ax, [cp_dst_dir]
    call dir_flush
    call fat_flush
.done:
    mov si, msg_one_file
    call puts
    ret
.usage:
    mov si, msg_syntax_copy
    call puts
    ret
.is_dir_pop:
    pop si
    mov si, msg_is_dir
    call puts
    ret
.not_found_pop:
    pop si
    mov si, msg_file_not_found
    call puts
    ret
.read_error:
    mov si, msg_read_error
    call puts
    ret
.disk_full:
    mov si, msg_disk_full
    call puts
    ret
.dir_full:
    mov si, msg_dir_full
    call puts
    ret
.bad_path:
    mov si, msg_bad_path
    call puts
    ret
.bad_name:
    mov si, msg_bad_name
    call puts
    ret

; ---------------------------------------------------------------------------
;  split_path - divide an argument into directory part and file name
;    in : DS:SI = argument
;    out: split_dir (may be empty), split_name
; ---------------------------------------------------------------------------
split_path:
    push ax
    push bx
    push di
    mov bx, 0
    mov di, si
.scan:
    mov al, [di]
    test al, al
    jz .scanned
    cmp al, '\'
    jne .next
    mov bx, di
.next:
    inc di
    jmp .scan
.scanned:
    test bx, bx
    jz .no_dir
    mov di, split_dir
.copy_dir:
    cmp si, bx
    ja .dir_end
    mov al, [si]
    mov [di], al
    inc si
    inc di
    jmp .copy_dir
.dir_end:
    mov byte [di], 0
    inc si
    jmp .copy_name
.no_dir:
    mov byte [split_dir], 0
.copy_name:
    mov di, split_name
.copy:
    mov al, [si]
    test al, al
    jz .name_end
    mov [di], al
    inc si
    inc di
    jmp .copy
.name_end:
    mov byte [di], 0
    pop di
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
;  output helpers
; ---------------------------------------------------------------------------
put2:
    push ax
    push bx
    push dx
    mov bl, 10
    xor ah, ah
    div bl
    mov dl, ah
    add al, '0'
    call putchar
    mov al, dl
    add al, '0'
    call putchar
    pop dx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
;  put_number_free - print AX as an unsigned decimal number
; ---------------------------------------------------------------------------
put_number_free:
    push ax
    push bx
    push cx
    push dx
    push di
    mov di, num_buf+12
    mov byte [di], 0
    mov bx, 10
.conv:
    dec di
    xor dx, dx
    div bx
    add dl, '0'
    mov [di], dl
    test ax, ax
    jnz .conv
    mov si, di
    call puts
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
;  print_entry_line - one DIR row
;    in : ES:BX -> directory entry
; ---------------------------------------------------------------------------
print_entry_line:
    push ax
    push bx
    push cx
    push dx
    push si
    push es
    call format_entry_name
    mov si, di_name_formatted
    call puts
    call strlen
    mov ax, 13
    sub ax, cx
    jle .no_pad
    mov cx, ax
.pad:
    mov al, ' '
    call putchar
    dec cx
    jnz .pad
.no_pad:
    ; --- attribute / size -------------------------------------------------
    mov al, [es:bx+11]
    test al, ATTR_DIR
    jz .file
    mov si, msg_dir_attr
    call puts
    jmp .date
.file:
    mov ax, [es:bx+28]
    call put_number_width9
.date:
    mov al, ' '
    call putchar
    mov ax, [es:bx+24]
    call print_fat_date
    mov al, ' '
    call putchar
    mov ax, [es:bx+22]
    call print_fat_time
    pop es
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
;  put_number_width9 - print AX right aligned in a 9 character field
; ---------------------------------------------------------------------------
put_number_width9:
    push ax
    push bx
    push cx
    push dx
    push di
    mov cx, 9
    mov di, num_buf+12
    mov byte [di], 0
    mov bx, 10
.conv:
    dec di
    xor dx, dx
    div bx
    add dl, '0'
    mov [di], dl
    test ax, ax
    jnz .conv
    ; padding length = cx - (num_buf+12 - di)
    mov ax, num_buf+12
    sub ax, di
    sub cx, ax
    jle .emit
.pad:
    mov al, ' '
    call putchar
    dec cx
    jnz .pad
.emit:
    mov si, di
    call puts
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
;  print_fat_date / print_fat_time
; ---------------------------------------------------------------------------
print_fat_date:
    push ax
    push bx
    push cx
    push dx
    mov bx, ax
    ; month
    mov ax, bx
    shr ax, 5
    and ax, 0x0F
    call put2
    mov al, '-'
    call putchar
    ; day
    mov ax, bx
    and ax, 0x1F
    call put2
    mov al, '-'
    call putchar
    ; year
    mov ax, bx
    shr ax, 9
    add ax, 1980
    xor dx, dx
    mov cx, 100
    div cx
    mov ax, dx
    call put2
    pop dx
    pop cx
    pop bx
    pop ax
    ret

print_fat_time:
    push ax
    push bx
    push dx
    mov bx, ax
    shr ax, 11
    call put2
    mov al, ':'
    call putchar
    mov ax, bx
    shr ax, 5
    and ax, 0x3F
    call put2
    pop dx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
;  state
; ---------------------------------------------------------------------------
cur_dir_path    db "\", 0
cur_path_tmp    times 64 db 0

split_dir       times 64 db 0
split_name      times 14 db 0

dir_files       dw 0
dir_dirs        dw 0
dir_bytes_lo    dw 0
dir_bytes_hi    dw 0

ty_cluster      dw 0
ty_rem          dw 0

md_parent       dw 0
md_cluster      dw 0
rd_cluster      dw 0

cp_src_cluster  dw 0
cp_src          dw 0
cp_size         dw 0
cp_rem          dw 0
cp_dst_dir      dw 0
cp_dst_first    dw 0
cp_prev         dw 0
cp_new          dw 0

num_buf         times 14 db 0
