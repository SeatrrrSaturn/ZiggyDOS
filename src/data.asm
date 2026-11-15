; =============================================================================
;  ZiggyDOS - messages and static data
; =============================================================================

msg_banner db "ZiggyDOS 0.10  -  a real 16-bit DOS for the IBM PC", 10
           db "(C) 2026 ZiggyDOS Project", 10, 10, 0

msg_ready  db "Ready.", 10, 0
msg_no_fs  db "Error: no usable FAT12 volume found on A:", 10, 0
msg_crlf   db 0

msg_version db "ZiggyDOS version 0.10", 10
            db "Kernel: 16-bit real mode, built from source with NASM", 10
            db "DOS API: INT 21h / INT 20h compatible subset", 10, 0

msg_vol_line db " Volume in drive A is ZIGGYDOS", 10, 0
msg_date_prefix db "Current date is ", 0
msg_time_prefix db "Current time is ", 0

msg_mem1 db "Conventional memory: 640K total, 256K program area", 10, 0
msg_mem2 db "Disk: 1.44MB FAT12, 512 bytes/sector, 1 sector/cluster", 10, 0
msg_mem3 db "Clusters on volume: ", 0

msg_help db "Available commands:", 10
         db 10
         db "  DIR      list the current directory", 10
         db "  TYPE     display a text file", 10
         db "  COPY     copy a file", 10
         db "  DEL      delete a file", 10
         db "  REN      rename a file", 10
         db "  MD       create a directory", 10
         db "  RD       remove an empty directory", 10
         db "  CD       change directory", 10
         db "  CLS      clear the screen", 10
         db "  VER      show the version", 10
         db "  DATE     show the system date", 10
         db "  TIME     show the system time", 10
         db "  ECHO     print text", 10
         db "  VOL      show the volume label", 10
         db "  MEM      show memory and disk information", 10
         db "  EXIT     reboot the machine", 10
         db 10
         db "Any other name is run as a .COM program from the current", 10
         db "directory. Type HELLO to see a program that uses INT 21h.", 10, 0

msg_reboot db "Rebooting...", 10, 0

msg_dir_of db " Directory of A:", 0
msg_files_count db "  file(s): ", 0
msg_dirs_count  db "   dir(s): ", 0
msg_bytes_count db "   bytes: ", 0
msg_bytes_tail  db 10, 0
msg_file_not_found db "File not found", 10, 0
msg_is_dir db "Is a directory", 10, 0
msg_bad_path db "Path not found", 10, 0
msg_bad_name db "Invalid file name", 10, 0
msg_exists db "Already exists", 10, 0
msg_disk_full db "Insufficient disk space", 10, 0
msg_dir_full db "Directory full", 10, 0
msg_dir_not_empty db "Directory not empty", 10, 0
msg_read_error db "Read error", 10, 0
msg_one_file db "        1 file(s) copied", 10, 0
msg_dir_attr db "<DIR>", 0

msg_syntax_type db "Usage: TYPE <file>", 10, 0
msg_syntax_del  db "Usage: DEL <file>", 10, 0
msg_syntax_ren  db "Usage: REN <old> <new>", 10, 0
msg_syntax_md   db "Usage: MD <directory>", 10, 0
msg_syntax_rd   db "Usage: RD <directory>", 10, 0
msg_syntax_copy db "Usage: COPY <source> <target>", 10, 0

env_string db "PATH=A:\", 0, 0

%ifdef DEBUG
test_name db "README  TXT", 0
%endif

; --- screen cursor state ------------------------------------------------------
cur_row db 0
cur_col db 0
