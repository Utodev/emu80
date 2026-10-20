; ***************************************************************************
; * Create .P3D file                                                        *
; ***************************************************************************
; Requires fragmentation.asm.
; Before including, define BUFFER_SIZE to the size of a buffer
; provided at the address to be stored in buffer_addr. BUFFER_SIZE must divide
; into 16K and be divisible by 4 (suggest: 4K).
; Also define MKDATA to 1 if require creating a data image, 0 for a swap image.


; ***************************************************************************
; * Create an unfragmented .P3D file                                        *
; ***************************************************************************
; Creates a .P3D file, name must be stored at "filename".
; A=pre-validated size in MB: 1-16 for data images, 1-30 for swap images
; A buffer of size BUFFER_SIZE must be allocated at the address stored in
; "bufferaddr".
; BUFFER_SIZE must divide into 16K and be divisible by (32*4). Suggest 4K.

createp3d:
        ld      (drivesize),a           ; save size for later
        ld      l,a
        ld      h,0                     ; HL=size required in MB
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl                   ; HL00=size required in bytes
        ld      (file_size+2),hl
        ld      hl,512                  ; add 512 bytes for P3D header
        ld      (file_size),hl
        call    create_unfrag_file      ; create an unfragmented file

; ***************************************************************************
; * Generate the P3D header                                                 *
; ***************************************************************************

        ld      hl,msg_okay
        call    printmsg
        ld      hl,msg_formatting
        call    printmsg                ; "Formatting image..."
if MKDATA
        ; Block size is chosen to ensure: 256 <= #blocks <= 2048
        ; If <256, extent masks would differ
        ; If >2048, allocation bitmaps would need to be >256 bytes
        ld      a,(drivesize)
        ld      d,a
        ld      e,0                     ; DE=size*256 (# of 4K blocks)
        cp      5
        jr      c,blk2k                 ; move on for 2K blocks (1-4MB)
        cp      9
        jr      c,blk4k                 ; move on for 4K blocks (5-8MB)
blk8k:
        srl     d                       ; DE=size*128 (# of 8K blocks)
        rr      e
        ld      hl,$3f06                ; HL=block mask & shift for 8K blocks
        ld      b,3                     ; B=extent mask for 8K blocks
        ld      a,%11000000             ; A=AL0 for 8K blocks
        jr      setxdpb
blk4k:
        ld      hl,$1f05                ; HL=block mask & shift for 4K blocks
        ld      b,1                     ; B=extent mask for 4K blocks
        ld      a,%11110000             ; A=AL0 for 4K blocks
        jr      setxdpb
blk2k:
        sla     d                       ; DE=size*512 (# of 2K blocks)
        ld      hl,$0f04                ; HL=block mask & shift for 2K blocks
        ld      b,0                     ; B=extent mask for 2K blocks
        ld      a,%11111111             ; A=AL0 for 2K blocks
setxdpb:
        ld      (default_xdpb+2),hl     ; set block mask & shift
        ld      (default_xdpb+9),a      ; set AL0
        ld      a,b
        ld      (default_xdpb+4),a      ; set extent mask
        dec     de                      ; DE=maximum block number
        ld      (default_xdpb+5),de     ; set last block number
        ld      a,(drivesize)
        add     a,a                     ; calculate A=16*size in MB
        add     a,a                     ; ie A=16*(size in sectors/2048)
        add     a,a                     ; so A=#tracks, since:
        add     a,a                     ; tracksize=128 sectors
        ld      (default_xdpb+18),a     ; set tracks
endif ; MKDATA
        ld      hl,(drivesize)
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl                   ; HL=8*size in MB so HL0=#sectors
        dec     hl                      ; HL$ff=max logical sector number
        ld      a,$ff
        ld      (default_phandle+7),a
        ld      (default_phandle+8),hl
        ld      de,(bufferaddr)         ; address to place header
        push    de
        ld      hl,default_p3dhdr
        ld      bc,48
        ldir                            ; copy signature, XDPB & phandle
        pop     hl
        inc     hl
        inc     hl
        inc     hl
        inc     hl                      ; HL=address after signature
        ld      b,44
        xor     a                       ; initialise checksum
calc_checksum:
        add     a,(hl)                  ; add in next byte
        inc     hl
        djnz    calc_checksum
        ld      d,h
        ld      e,l
        inc     de
        ld      bc,462
        ld      (hl),0                  ; erase byte 48
        ldir                            ; erase bytes 49..510
        ld      (de),a                  ; store checksum in byte 511
        ; drop through to write_p3d

; ***************************************************************************
; * Write the P3D file                                                      *
; ***************************************************************************

write_p3d:
        ld      a,(tmpfilehandle)
        ld      bc,0
        ld      de,0
        ld      l,esx_seek_set
        callesx f_seek                  ; seek to start of dest file
        ld      a,(tmpfilehandle)
        ld      hl,(bufferaddr)
        ld      bc,512
        push    bc
        callesx f_write                 ; write the P3D header
        pop     hl
        jp      c,unfrag_failed_write
        and     a
        sbc     hl,bc                   ; were all bytes written?
        scf
        ld      a,esx_eio
        jp      nz,unfrag_failed_wrsize ; error if not
if MKDATA
        ld      hl,(bufferaddr)
        ld      d,h
        ld      e,l
        inc     de
        ld      (hl),$e5
        ld      bc,BUFFER_SIZE-1
        ldir                            ; fill 4K buffer with $e5
        ld      hl,label_entry
        ld      de,(bufferaddr)
        ld      bc,32
        ldir                            ; copy in a label as the first entry
        ld      b,BUFFER_SIZE/(32*4)    ; number of datestamp entries
        ld      de,(bufferaddr)
        addde_N 32*3                    ; starting with entry 3
copy_datestamp_loop:
        push    bc
        push    de
        ld      hl,datestamp_entry
        ld      bc,32
        ldir                            ; copy in a datestamp entry
        pop     de
        pop     bc
        addde_N 32*4
        djnz    copy_datestamp_loop
        ld      b,16384/BUFFER_SIZE     ; 16K=512 directory entries
write_dir_loop:
        push    bc
        ld      a,(tmpfilehandle)
        ld      hl,(bufferaddr)
        ld      bc,BUFFER_SIZE
        push    bc
        callesx f_write                 ; write the P3D header
        pop     hl                      ; HL=BUFFER_SIZE
        pop     de                      ; D=loop counter
        jp      c,unfrag_failed_write
        and     a
        sbc     hl,bc                   ; were all bytes written?
        scf
        ld      a,esx_eio
        jp      nz,unfrag_failed_wrsize ; error if not
        push    de                      ; save loop counter
        ld      hl,(bufferaddr)
        ld      d,h
        ld      e,l
        ld      bc,32
        add     hl,bc
        ldir                            ; overwrite label with 2nd entry ($E5s)
        pop     bc                      ; B=loop counter
        djnz    write_dir_loop          ; back for more iterations
endif ; MKDATA
        ld      a,(tmpfilehandle)
        callesx f_close                 ; close the new file
        jp      c,unfrag_failed_newclose
        ld      a,'*'
        ld      hl,msg_tmpfilename
        ld      de,filename
        callesx f_rename                ; rename temp to original
        jp      c,unfrag_failed_rename
        ld      hl,msg_okay
        call    printmsg
        jp      delete_tmps             ; delete remaining temp files & exit


; ***************************************************************************
; * Default P3D header                                                      *
; ***************************************************************************

default_p3dhdr:
default_p3dsig:
        ; signature (4 bytes)
        defm    "P3D",$1a
if MKDATA
default_xdpb:
        ; XDPB (28 bytes)
        defw    512             ; SPT: records per track (128 sectors x 4 recs)
        defb    0               ; BSH: log2(blocksize/128)      TO FILL IN
        defb    0               ; BLM: blocksize/128-1          TO FILL IN
        defb    0               ; EXM: extent mask              TO FILL IN
        defw    0               ; DSM: last block number        TO FILL IN
        defw    511             ; DRM: last directory entry
        defb    0               ; AL0: directory bitmap         TO FILL IN
        defb    0               ; AL1: directory bitmap
        defw    $8000           ; CKS: checksum - fixed disk
        defw    0               ; OFF: reserved tracks
        defb    2               ; PSH: log2(sectorsize/128)
        defb    3               ; PSM: sectorsize/128-1
        defb    0               ; sidedness
        defb    0               ; tracks per side               TO FILL IN
                                ; NOTE: Gets set to $00 for 16MB partitions.
                                ;       Okay, as unused on non-floppy drives
                                ;       if sidedness=0.
        defb    128             ; sectors per track
        defb    0               ; 1st sector
        defw    512             ; sector size
        defw    0               ; partition handle
        defb    0               ; multitrack
        defb    0               ; freeze flag
        defb    $10             ; flags: bit 4=mounted image
else ; MKDATA
        defs    28              ; no XDPB for swap partitions
endif ; MKDATA
default_phandle:
        ; partition handle (16 bytes)
if MKDATA
        defb    $03             ; partition type (ptype_p3dos)
else
        defb    $02             ; partition type (ptype_swap)
endif
        defw    0,0             ; starting LBA
        defw    0               ; unused
        defw    0,0             ; largest logical sector        TO FILL IN
        defs    5               ; type-specific data


; ***************************************************************************
; * Messages                                                                *
; ***************************************************************************

msg_formatting:
        defm    "Formatting image...",0


; ***************************************************************************
; * Directory entry templates                                               *
; ***************************************************************************

label_entry:
        defb    $20                     ; label type
        ;        12345678
        defm    "LABEL   "              ; name
        defm    "   "                   ; extension
        defb    %00110001               ; timestamps on create & update
        defb    0,0,0                   ; PB,RR,RR
        defs    8                       ; password
        defs    8                       ; create, update stamps for label

datestamp_entry:
        defb    $21                     ; datestamp type
        defs    31                      ; all initialised to zeros


; ***************************************************************************
; * Data                                                                    *
; ***************************************************************************

drivesize:
        defb    0                       ; size in MB of image to create (1-31)
