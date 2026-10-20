; ***************************************************************************
; * CP/M loader dot command                                                 *
; * .cpm                                                                    *
; ***************************************************************************

include "macros.def"
include "nexthw.def"
include "rom48.def"
include "esxapi.def"
include "p3dos.def"
include "nextzxos.def"
include "cpm.def"


; ***************************************************************************
; * Definitions                                                             *
; ***************************************************************************

LOADER_VERSION          equ     $0180   ; v1.8
LOADER_HI               equ     '0'+((LOADER_VERSION/$100)&$0f)
LOADER_MID              equ     '0'+((LOADER_VERSION/$10)&$0f)
LOADER_LOW              equ     '0'+((LOADER_VERSION)&$0f)

FILESPEC_LENGTH         equ     32
CAT_ENTRIES             equ     64
CATENTRY_SIZE           equ     13      ; 8+3 name, 2-byte size
WORKSPACE_SIZE          equ     BIOSHDR_LENGTH+MAX_BIOS_EXT_SIZE
BUFFER_SIZE             equ     4096    ; .P3D buffer, must divide
                                        ; into 16K and be divisible by (32*4)


if (WORKSPACE_SIZE < (16384/8))
.ERROR WORKSPACE_SIZE not large enough for bitmap of a 16K file
endif

if (WORKSPACE_SIZE < (FILESPEC_LENGTH+(CAT_ENTRIES*CATENTRY_SIZE)))
.ERROR WORKSPACE_SIZE not large enough for catalog + filespec
endif

if (WORKSPACE_SIZE < BUFFER_SIZE)
.ERROR WORKSPACE_SIZE for large enough for createp3d buffer
endif


; ***************************************************************************
; * Initialisation                                                          *
; ***************************************************************************
; Dot commands always start at $2000, with HL=address of command tail
; (terminated by $00, $0d or ':').

        org     $2000

        ld      (entry_sp),sp           ; save initial SP
        ld      hl,msg_help
        call    printmsg                ; show loader info
        ld      bc,WORKSPACE_SIZE
        call48k BC_SPACES_r3            ; reserve some workspace
        ld      (bufferaddr),de         ; and save its address
        ld      hl,WORKSPACE_SIZE
        add     hl,de
        ld      a,h
        cp      $c0                     ; ensure entire area lies below $c000
        ld      hl,msg_oom
        jr      nc,err_custom
        ld      bc,next_reg_select
        ld      a,nxr_turbo
        out     (c),a
        inc     b
        in      a,(c)                   ; get current turbo setting
        ld      (saved_speed),a         ; save it
        ld      a,turbo_max
        out     (c),a                   ; and increase to maximum
        ld      a,$80                   ; set do not erase with truncate
        callesx m_setcaps
        ld      a,e
        ld      (old_caps),a            ; save old capabilities for restoring
        callesx m_dosversion
        jr      c,bad_nextzxos          ; must be esxDOS if error
        jr      nz,bad_nextzxos         ; need to be in NextZXOS mode
        ld      hl,'N'<<8+'X'
        sbc     hl,bc                   ; check NextZXOS signature
        jr      nz,bad_nextzxos
        ld      hl,$0202
        ex      de,hl
        sbc     hl,de                   ; check version number >= 2.02
        jr      nc,main_program         ; on if okay
        ; else fall through to bad_nextzxos

; ***************************************************************************
; * Custom error generation                                                 *
; ***************************************************************************
; Entry: HL=error message (bit7-terminated)

bad_nextzxos:
        ld      hl,msg_badnextzxos
err_custom:
        xor     a                       ; A=0, custom error
        scf                             ; Fc=1, error condition
        ; fall through to exit_error

; ***************************************************************************
; * Clean up and exit with any error condition                              *
; ***************************************************************************

exit_error:
        ld      sp,(entry_sp)           ; restore original stack
        push    af
        push    hl
        ld      a,(old_caps)
        callesx m_setcaps               ; restore original caps
        ld      a,(saved_speed)
        nxtrega nxr_turbo               ; restore original speed
        pop     hl
        pop     af
        ret


; ***************************************************************************
; * Abort CP/M loading with information                                     *
; ***************************************************************************
; Entry: HL=informational message to print (0/$ff-terminated)
;        DE=error message (bit7-terminated)

cpm_abort:
        push    de
        call    printmsg
        pop     hl
        jr      err_custom              ; cause error


; ***************************************************************************
; * Main program                                                            *
; ***************************************************************************

main_program:
        call    unmount_images          ; unmount RAMdisk and images
        call    mount_drives            ; mount CP/M drive images
        ld      a,(map_table)
        and     a
        jr      nz,cpm_start            ; start if A: (system) drive present
        ld      a,16
        call    createp3d               ; else attempt to create one
        jr      main_program            ; and try again

cpm_start:
        call    load_init_biosext       ; load and initialise BIOS extension
        ld      b,16                    ; 16 files to close
close_file_loop:
        push    bc
        dec     b                       ; B=file number
        callp3d dos_close,7             ; ensure file is closed
        pop     bc
        push    bc
        dec     b                       ; B=file number
        callp3d dos_abandon,7           ; abandon it for good measure
        pop     bc
        djnz    close_file_loop         ; back for remaining files

        ; This is now the point of no return. The BIOS extension has been
        ; loaded and initialised.
        ld      hl,$8000
        ld      (bufferaddr),hl         ; relocate buffer away from BIOS extension
        call    init_cpmdrives          ; initialise DPBs, drive & XDPB tables

        ld      hl,msg_vthelp
        call    printmsg                ; re-show loader info
        call    load_font_files         ; load the real font files
        ld      de,msg_biosfile
        ld      b,0                     ; BIOS is file 0
        call    open_relfile
        ld      (bios_size),bc          ; store size of BIOS in bytes
        addbc_N 255                     ; B=size of BIOS in pages (rounded up)
if ((BIOS_TOP&$ff) != 0)
.ERROR BIOS_TOP should be page-aligned
endif
        ld      a,BIOS_TOP/$100
        sub     b                       ; A=BIOS start page
        ld      (bios_page),a           ; store BIOS start page
        dec     a
        ld      (scb_page),a            ; store SCB page (last in resident BDOS)

        ld      de,msg_resfile
        ld      b,1                     ; resident BDOS is file 1
        call    open_relfile
        ld      (res_size),bc           ; store size of resident BDOS in bytes
        addbc_N 255                     ; B=size of resident BDOS in pages
        ld      a,(bios_page)
        sub     b                       ; A=start resident BDOS page
        ld      (res_page),a            ; store resident BDOS start page

        ld      de,msg_bnkfile
        ld      b,2                     ; banked BDOS is file 2
        call    open_relfile
        ld      (bnk_size),bc           ; store size of banked BDOS in bytes
        addbc_N 255                     ; B=size of banked BDOS in pages
        ld      a,COMMON_PAGE
        sub     b                       ; A=start resident BDOS page
        ld      (bnk_page),a            ; store resident BDOS start page

        ld      a,(bios_page)           ; A=relocation offset
        ld      ixh,a
        ld      ixl,0                   ; IX=BIOS start address
        dec     a                       ; account for .PRL file origin of $0100
        ld      de,(bios_size)          ; DE=size of BIOS in bytes
        ld      b,0                     ; file 0
        ld      c,COMMON_RAMPAGE        ; common memory at top
        ld      hl,msg_biosfile
        call    load_and_relocate       ; load and relocate the BIOS

        ld      a,(res_page)            ; A=relocation offset
        ld      ixh,a
        ld      ixl,0                   ; IX=resident BDOS start address
        ld      de,(res_size)           ; DE=size of resident BDOS in bytes
        ld      b,1                     ; file 1
        ld      c,COMMON_RAMPAGE        ; common memory at top
        ld      hl,msg_resfile
        call    load_and_relocate       ; load and relocate the resident BDOS

        ld      a,(bnk_page)
        push    af
        or      $c0                     ; make load address in top 16K
        ld      ixh,a
        ld      ixl,0                   ; IX=banked BDOS start address
        pop     af                      ; A=relocation offset
        ld      de,(bnk_size)           ; DE=size of banked BDOS in bytes
        ld      b,2                     ; file 2
        ld      c,BANK0TOP_RAMPAGE      ; page of top memory for bank 0
        ld      hl,msg_bnkfile
        call    load_and_relocate       ; load and relocate the banked BDOS

        ld      hl,msg_crlf
        call    printmsg                ; ensure "Loading A:CCP.COM" on new line

        nxtregn nxr_mmu4,CCP_BANKL      ; bind in banks to hold CCP
        nxtregn nxr_mmu5,CCP_BANKU
        ld      hl,msg_ccp_file
        ld      de,$8002
        ld      bc,$3ffe
        push    bc
        push    de
        push    hl
        call    load_file               ; try and load CCP.COM from the drive
        pop     hl
        pop     de
        pop     bc
        ld      a,'C'
        call    nc,load_drive_file      ; if failed, load dummy from system dir
        jp      nc,cpm_halt_readerr
        ld      ($8000),bc              ; store loaded size
        nxtregn nxr_mmu4,MMU4_DEFAULT   ; restore normal bindings for MMU4/5
        nxtregn nxr_mmu5,MMU5_DEFAULT

        ; Print some copyright and informational messages.
        nxtregn nxr_mmu6,COMMON_BANKL   ; ensure common memory is at top
        nxtregn nxr_mmu7,COMMON_BANKU
        ld      hl,msg_signon
        call    printmsg                ; show "CP/M Plus"
        ld      a,(res_page)
        ld      d,a
        ld      e,$4a                   ; copyright message is normally here
        push    de
        ld      hl,msg_checkcopyright
        ld      b,msg_checkcopyright_end-msg_checkcopyright
check_copyright_loop:
        ld      a,(de)
        and     $df                     ; capitalise
        cp      (hl)
        jr      nz,bad_copyright
        inc     de
        inc     hl
        djnz    check_copyright_loop
        pop     hl
        push    hl
        call    printmsg                ; print the copyright message
bad_copyright:
        pop     hl                      ; discard message address
        ld      hl,(bios_hdr+BIOSHDR_COPYRIGHT)
        call    printmsg                ; show the BIOS's copyright message
        ld      a,(res_page)            ; A=number of pages in TPA
        push    af
        rra
        rra
        and     $3f                     ; A=size of TPA in K
        ld      b,$ff
calc_tpa_10s:
        inc     b                       ; calculate B=size/10
        sub     10
        jr      nc,calc_tpa_10s
        add     a,10+'0'                ; A=units, ASCII-fied
        ld      hl,msg_tpa_num+1
        ld      (hl),a
        ld      a,b
        add     a,'0'                   ; A=tens, ASCII-fied
        dec     hl
        ld      (hl),a
        call    printmsg                ; print value
        pop     af
        ld      hl,msg_k_tpa
        and     3                       ; any partial K?
        jr      z,show_tpa              ; on if not
        dec     hl                      ; at "5K TPA"
        dec     hl                      ; at "25K TPA"
        cp      2
        jr      z,show_dot_tpa          ; if 0.5K, on to replace 7 with .
        jr      c,tpa_point_25          ; on if .25K
        ld      (hl),'7'                ; else change to .75
tpa_point_25:
        dec     hl                      ; at ".x5K"
show_dot_tpa:
        ld      (hl),'.'
show_tpa:
        call    printmsg                ; show rest of TPA message

        ; Everything is now prepared to exit the dot command and start CP/M.
        ld      a,(bios_page)
        ld      h,a
        ld      l,0                     ; HL=BIOS base (cold start address)
        exit_dot_to_hl()                ; exit dot command and jump to HL


; ***************************************************************************
; * Unmount drive images and RAMdisk                                        *
; ***************************************************************************
; The RAMdisk and all currently-mounted image files are unmounted.

unmount_images:
        ld      hl,msg_unmounting
        call    printmsg
        ld      l,'A'                   ; start with drive A
unmount_image_loop:
        push    hl
        ld      bc,(bufferaddr)         ; buffer for mapping text
        callp3d ide_dos_mapping,7       ; get the next drive mapping
        jr      nc,unmount_inuse        ; flag drive if error (shouldn't happen)
        jr      z,unmount_done          ; skip if not mapped
        cp      4                       ; RAMdisk?
        jr      z,unmount_dounmount
        cp      $ff                     ; mounted filesystem? ($ff)
        jr      nz,unmount_inuse        ; skip if other filesystem
unmount_dounmount:
        pop     hl
        push    hl
        callp3d ide_dos_unmap,7         ; unmap the RAMdisk/image
        jr      nc,unmount_inuse        ; if error, drive still in use
        pop     hl
        push    hl
        ld      a,l
        print_char()                    ; display drive just unmapped
        jr      unmount_done
unmount_inuse:
        pop     hl
        push    hl
        ld      a,l
        sub     'A'                     ; A=drive id, 0..15
        ld      hl,dos_table
        addhl_A_badFc()
        ld      (hl),$ff                ; mark as NextZXOS-specific
unmount_done:
        pop     hl
        inc     l
        ld      a,l
        cp      'A'+NUM_DRIVES
        jr      c,unmount_image_loop    ; back to unmount more
        ld      hl,msg_ok
        call    printmsg
        ret


; ***************************************************************************
; * Mount requested drives                                                  *
; ***************************************************************************

mount_drives:
        ld      hl,msg_mounting
        call    printmsg
        ld      hl,msg_mountfilespec
        call    get_image_cat           ; get list of matching files
        ret     nc                      ; exit if error
        dec     b                       ; B=# entries excluding preloaded
        ret     z                       ; or if no completed catalog entries
        push    bc
        ld      de,msg_mountcpm         ; first mount the CPM-d.DSK/P3D files
        call    do_automount
        ld      de,msg_mountdrv         ; then mount the DRV-d.DSK/P3D files
        pop     bc
        ; fall through to do_automount and then exit

; ***************************************************************************
; * Automount image files                                                   *
; ***************************************************************************
; Entry: B=# entries in catalog, loaded at (cat_addr)
;        DE=3-letter prefix to match
;        Wildcarded filespec has already been copied to (bufferaddr).

do_automount:
        ld      hl,(cat_addr)
        addhl_N CATENTRY_SIZE           ; start of catalog, after preloaded
automount_loop:
        push    bc                      ; save entry count
        push    hl                      ; save catalog address
        push    de                      ; save prefix address
        call    check3chars
        jp      nz,automount_skip       ; on if non-matching prefix
        inc     hl                      ; skip "-"
        ld      a,(hl)                  ; get drive letter
        inc     hl
        res     7,a                     ; clear any attribute bit
        cp      'A'
        jp      c,automount_skip        ; skip entry if not a letter
        cp      'A'+NUM_DRIVES
        jp      nc,automount_skip       ; A-P
        ld      c,a                     ; C=drive letter
        inc     hl
        inc     hl
        inc     hl                      ; HL now addresses extension
        ld      de,msg_mountp3d         ; allow P3D files
        push    hl
        push    de
        call    check3chars
        pop     de
        pop     hl
        jr      z,automount_map
        ld      de,msg_mountdsk         ; or DSK files
        push    hl
        push    de
        call    check3chars
        pop     de
        pop     hl
        jp      nz,automount_skip
automount_map:
        ld      hl,xdpb_table
        ld      a,c                     ; A=drive letter
        sub     'A'
        addhl_A_badFc()
        addhl_A_badFc()                 ; HL=address of XDPB
        ld      a,(hl)
        inc     hl
        or      (hl)
        jp      nz,automount_skip       ; ignore if CP/M drive already mapped
        ld      a,c
        ex      de,hl                   ; HL=extension
        ld      de,(bufferaddr)
        addde_N msg_mountfilespec_extn-msg_mountfilespec
        ld      c,3                     ; NOTE: B=0 from check3chars
        ldir                            ; copy extension into filespec
        pop     hl                      ; HL=prefix address
        push    hl
        ld      de,(bufferaddr)
        addde_N msg_mountfilespec_prefix-msg_mountfilespec
        ld      c,3
        ldir                            ; copy prefix into filespec
        ld      hl,(bufferaddr)
        addhl_N msg_mountfilespec_drive-msg_mountfilespec
        ld      (hl),a                  ; store drive letter into filespec
        ld      c,a                     ; C=CP/M drive letter
        call    allocate_dos_drive
        jr      nz,automount_skip       ; skip if none left
        push    bc                      ; save +3DOS & CP/M drive letters
        ld      a,b
        print_char()                    ; display CP/M drive letter
        ld      a,':'
        print_char()                    ; display ':'
        ld      a,' '
        print_char()                    ; display ' '
        ld      hl,(bufferaddr)
        call    printmsg                ; display image name
        pop     bc
        push    bc
        ld      l,b                     ; L=+3DOS drive letter
        ld      a,$ff                   ; image
        ld      bc,(bufferaddr)
        callp3d ide_dos_map,7           ; mount the image
        pop     bc                      ; B=+3DOS letter, C=CP/M letter
        jr      nc,automount_fail
        push    bc
        ld      a,b
        callp3d dos_ref_xdpb,7          ; get XDPB for mounted image
        exx                             ; NOTE: M_P3DOS returns IX values
        push    hl                      ;       in H'L', so transfer it
        exx
        pop     ix
        pop     bc                      ; C=CP/M letter, B=+3DOS letter
automount_fail:
        ld      hl,msg_fail
        ld      de,msg_badmount
        jp      nc,cpm_abort
        ld      a,c
        sub     'A'
        ld      hl,map_table
        addhl_A_badFc()
        ld      (hl),b                  ; insert mapping into table
        add     a,a
        ld      hl,xdpb_table
        addhl_A_badFc()
        ld      a,ixl
        ld      (hl),a                  ; store XDPB pointer for CP/M drive
        inc     hl
        ld      a,ixh
        ld      (hl),a
        ld      hl,msg_ok
        call    printmsg
automount_skip:
        pop     de                      ; restore prefix address
        pop     hl                      ; restore catalog address
        addhl_N CATENTRY_SIZE           ; advance to next entry
        pop     bc
        dec     b
        jp      nz,automount_loop       ; back for more catalog entries
        ret


; ***************************************************************************
; * Allocate a +3DOS drive letter for mounting a CP/M drive image           *
; ***************************************************************************
; Entry: C=CP/M drive letter
; Exit:  Fz=1, B=+3DOS drive letter
;        Fz=0, no drive letter available

allocate_dos_drive:
        ld      b,c                     ; assume can map to same letter
        ld      a,c
        sub     'A'
        ld      hl,dos_table
        addhl_A_badFc()
        ld      a,(hl)
        and     a                       ; is it available?
        jr      nz,alloc_fail_1to1
        ld      (hl),c                  ; if so, mark as mapped to CP/M drive
        ret                             ; & exit with Fz=1
alloc_fail_1to1:
        ld      hl,dos_table+NUM_DRIVES-1       ; start from end of table
        ld      b,NUM_DRIVES
alloc_drive_loop:
        ld      a,(hl)
        and     a
        jr      z,got_unused_drive
        dec     hl
        djnz    alloc_drive_loop
        ret                             ; exit with Fz=0 if none available
got_unused_drive:
        ld      (hl),c                  ; mark as mapped to CP/M drive
        ld      a,b
        add     a,'A'-1                 ; form drive letter
        ld      b,a                     ; B=+3DOS drive
        xor     a                       ; Fz=1, drive available
        ret


; ***************************************************************************
; * Get list of matching mountable disk image files                         *
; ***************************************************************************
; Entry:   HL=filespec to match
; Exit(s): Fc=1, B=# matching entries + 1
; Exit(f): Fc=0, A=error

get_image_cat:
        push    hl                      ; save filespec to catalog
        ld      hl,(bufferaddr)
        push    hl
        addhl_N FILESPEC_LENGTH         ; space for wildcarded filespec
        ld      (cat_addr),hl           ; store address for catalog
        ld      d,h
        ld      e,l
        inc     de
        ld      bc,CATENTRY_SIZE-1
        ld      (hl),b
        ldir                            ; zero entry 0 of catalog buffer
        pop     de                      ; DE=address for filespec in RAM
        pop     hl                      ; HL=filespec
        push    de
        ld      bc,FILESPEC_LENGTH
        ldir                            ; copy wildcarded filespec to RAM
        pop     hl                      ; HL=filespec in RAM
        ld      de,(cat_addr)
        ld      bc,CAT_ENTRIES<<8+$01   ; incl. sys files (in case marked as such)
        callp3d dos_catalog,7           ; perform the catalog
        ret


; ***************************************************************************
; * Check 3 prefix or extension characters                                  *
; ***************************************************************************
; Entry: HL=catalog entry at required position
;        DE=chars to match
; Exit:  Fz=1 if match
; Preserves C.

check3chars:
        ld      b,3                     ; 3 chars to check
check3_loop:
        res     7,(hl)                  ; clear any attribute bit
        ld      a,(de)
        cp      (hl)                    ; check characters
        ret     nz                      ; exit with Fz=0 if no match
        inc     de
        inc     hl
        djnz    check3_loop
        ret                             ; exit with Fz=1, match


; ***************************************************************************
; * Load and initialise BIOS extension                                      *
; ***************************************************************************

load_init_biosext:
        ld      hl,msg_biosext_file
        ld      de,bios_hdr
        ld      bc,BIOSHDR_LENGTH+MAX_BIOS_EXT_SIZE
        ld      a,'C'
        call    load_file_via_workspace ; load the BIOS extension
        jr      nc,load_support_failure
        ld      hl,(bios_hdr+BIOSHDR_SIZE)
        addhl_N BIOSHDR_LENGTH
        and     a
        sbc     hl,bc
        ld      hl,msg_invalid
        jr      nz,load_support_fail_hl ; error if size mismatch
        ld      a,(bios_hdr+BIOSHDR_SIGNATURE)
        cp      'B'
        jr      nz,load_support_fail_hl ; or if signature is wrong
        ld      a,(bios_hdr+BIOSHDR_SIGNATURE+1)
        cp      'X'
        jr      nz,load_support_fail_hl ; or if signature is wrong
        ld      hl,LOADER_VERSION
        ld      bc,(bios_hdr+BIOSHDR_LOADERVER)
        sbc     hl,bc                   ; NOTE: Fc=0 from previous CP
        jr      nc,init_biosext
        ld      hl,msg_oldloader
        ld      de,msg_badloader
        jp      cpm_abort

load_support_failure:
        ld      hl,msg_fail
load_support_fail_hl:
        ld      de,msg_unabletoload
        jp      cpm_abort

init_biosext:
        halt                            ; wait for an interrupt to avoid flicker
        di                              ; disable interrupts
        pop     hl                      ; HL=return address
        nxtregn nxr_mmu0,MMU0_DEFAULT   ; ensure standard memory layout in force
        nxtregn nxr_mmu1,MMU1_DEFAULT
        nxtregn nxr_mmu2,MMU2_DEFAULT
        nxtregn nxr_mmu3,MMU3_DEFAULT
        nxtregn nxr_mmu4,MMU4_DEFAULT
        nxtregn nxr_mmu5,MMU5_DEFAULT
        nxtregn nxr_mmu6,MMU6_DEFAULT
        nxtregn nxr_mmu7,MMU7_DEFAULT
        ld      sp,(bios_hdr+BIOSHDR_SP); relocate stack to within BIOS ext
        push    hl                      ; restack return address
        xor     a
        out     (ula_port),a            ; set border to black
        nxtrega nxr_transp_fallback     ; set fallback to black
        ld      bc,nxp_layer2
        out     (c),a                   ; disable layer2
        out     (timex_port),a          ; disable Timex modes
        nxtrega nxr_sprites             ; disable sprites and lo-res
        nxtrega nxr_tilemap_ctrl        ; disable tilemap output
        ld      a,%10000000
        nxtrega nxr_ula_ctrl            ; disable ULA output
        ld      a,transparency_default
        nxtrega nxr_transparency        ; ensure default global transparency
        ld      a,15
        nxtrega nxr_palette_format      ; set standard palette format
        ld      hl,bios_data
        ld      de,(bios_hdr+BIOSHDR_ORG)
        ld      bc,(bios_hdr+BIOSHDR_SIZE)
        ldir                            ; copy BIOS extension in place
        ld      hl,0                    ; to overwrite JR with NOPs
        ld      (printmsg),hl           ; printmsg now executes vterm_printmsg
        ld      hl,CHAR_SET_r3
        ld      de,(bios_hdr+BIOSHDR_FONTADDR_NORM)
        ld      bc,768
        call48k LDIR_RET_r3             ; copy in standard font for now
        ld      ix,(bios_hdr+BIOSHDR_VTERM_INIT)        ; vterm initialisation
jpix:
        jp      (ix)                    ; execute routine and return


; ***************************************************************************
; * Load the font files                                                     *
; ***************************************************************************

load_font_files:
        ld      hl,msg_font1norm_file
        ld      de,(bios_hdr+BIOSHDR_FONTADDR_NORM)
        call    load_font_file
        ld      hl,msg_font1und_file
        ld      de,(bios_hdr+BIOSHDR_FONTADDR_UNDR)
        call    load_font_file
        ld      hl,msg_font1ital_file
        ld      de,(bios_hdr+BIOSHDR_FONTADDR_ITAL)
        call    load_font_file
        ld      hl,msg_font1itun_file
        ld      de,(bios_hdr+BIOSHDR_FONTADDR_ITUN)
        call    load_font_file
        ld      hl,msg_fontgfx_file
        ld      de,(bios_hdr+BIOSHDR_FONTADDR_GFX)
        ld      bc,33*8
        jr      load_font_file_small


; ***************************************************************************
; * Load a font file via the workspace area                                 *
; ***************************************************************************
; Entry: HL=filename ($ff-terminated)
;        DE=destination address

load_font_file:
        ld      bc,768
load_font_file_small:
        push    bc
        ld      a,'C'
        call    load_drive_file         ; load font file
        jr      nc,load_font_failure
        pop     hl
        and     a
        sbc     hl,bc
        jr      nz,load_font_failure    ; bad if all bytes not loaded
        ld      hl,msg_ok_crlf
        jp      printmsg                ; print OK and exit

load_font_failure:
        ld      hl,msg_fail
        jp      cpm_halt


; ***************************************************************************
; * Load a file via the workspace area                                      *
; ***************************************************************************
; Entry: HL=filename ($ff-terminated)
;        DE=destination address
;        BC=max length
;        A=drive letter
; Exit:  Fc=1, success
;        BC=bytes actually read
;        Fc=0, error

; NOTE: This routine is used when loading files to a destination in dot
;       command memory. This memory cannot be seen by +3DOS calls, so the
;       file is loaded via the workspace area in main RAM.

load_file_via_workspace:
        push    de                      ; save ultimate destination
        ld      de,(bufferaddr)
        call    load_drive_file         ; load to workspace RAM
        pop     de
        ret     nc                      ; exit if error
        ld      a,b
        or      c
        scf
        ret     z                       ; nothing to do if no bytes read
        push    bc                      ; save bytes actually read
        ld      hl,(bufferaddr)
        ldir                            ; copy to final destination
        pop     bc                      ; restore bytes read
        ret


; ***************************************************************************
; * Load a file                                                             *
; ***************************************************************************
; Entry: HL=filename ($ff-terminated)
;        DE=destination address
;        BC=max length
;        A=drive letter (only if entering at load_drive_file)
; Exit:  Fc=1, success
;        BC=bytes actually read
;        Fc=0, error


load_file:
        ld      a,(map_table)           ; use +3DOS drive mapped to CP/M's A:
load_drive_file:
        push    de
        push    bc
        ex      de,hl                   ; DE=filename
        ld      b,0                     ; file 0
        ld      hl,msg_loading
        call    open_drive_file         ; open the file from the image
        pop     de                      ; DE=max length
        pop     hl                      ; HL=destination
        ret     nc                      ; exit if any error
        ld      bc,$0000                ; file 0, page 0
        push    de                      ; save max length
        callp3d dos_read,7              ; read the file data
        pop     hl                      ; HL=max length
        push    af                      ; save error condition
        jr      c,loaded_all            ; if no error, all bytes were read
        sbc     hl,de                   ; otherwise HL=max len-unread bytes
loaded_all:
        push    hl                      ; save bytes read
        ld      b,0
        callp3d dos_close,7             ; close the file
        pop     bc                      ; BC=bytes read
        pop     af                      ; AF=error condition from read
        ret     c                       ; exit if successful
        cp      rc_eof
        scf
        ret     z                       ; don't treat EOF as an error
        and     a
        ret                             ; otherwise exit with error


; ***************************************************************************
; * Open a file on the CP/M system drive image                              *
; ***************************************************************************
; Entry: HL=opening/loading message
;        DE=filename ($ff-terminated)
;        B=file number
;        A=drive letter
; Exit:  Fc=1, success
;        Fc=0, error opening

open_drive_file:
        push    bc
        push    af
        push    de
        call    printmsg                ; print opening/loading message
        pop     hl
        pop     af                      ; A=drive letter
        ld      de,(bufferaddr)
        push    de
        ld      (de),a
        inc     de
        and     $df
        cp      'C'                     ; Fz=1 if need system path
        ld      a,':'
        ld      (de),a
        inc     de
        jr      nz,odf_nopath
        push    hl
        ld      hl,msg_sysdir
        ld      bc,msg_sysdir_end-msg_sysdir
        ldir                            ; copy system path into RAM
        pop     hl
odf_nopath:
        ld      bc,FILESPEC_LENGTH-2
        ldir                            ; copy filespec into RAM
        pop     hl
        push    hl
        call    printmsg                ; print filename
        pop     hl
        pop     bc                      ; B=file number
        ld      c,$01                   ; exclusive-read
        ld      de,$0001                ; only open existing file, past any +3DOS header
        callp3d dos_open,7              ; open the file
        ret                             ; exit with the error condition


; ***************************************************************************
; * Open a relocatable system file                                          *
; ***************************************************************************
; Entry: DE=filespec ($ff-terminated)
;        B=file number
; Exit:  BC=program size

open_relfile:
        ld      a,'C'
        push    bc
        ld      hl,msg_opening          ; "Opening "
        call    open_drive_file
        ld      hl,msg_nofile
        jr      nc,cpm_halt             ; stop if couldn't
        pop     bc
        ld      c,0                     ; page 0 at top
        ld      de,$100                 ; SPR/REL header length
        ld      hl,(bufferaddr)
        push    hl
        callp3d dos_read,7              ; read the SPR/REL header
        jr      nc,cpm_halt_readerr     ; stop if couldn't
        pop     hl
        inc     hl
        ld      c,(hl)
        inc     hl
        ld      b,(hl)                  ; BC=psize
        ret


; ***************************************************************************
; * Halt CP/M loading with information                                      *
; ***************************************************************************
; Entry: HL=informational message to print (0/$ff-terminated)

cpm_halt_readerr:
        ld      hl,msg_readerr
cpm_halt:
        call    printmsg
        ld      hl,msg_halted
        call    printmsg
cpm_halt_loop:
        jr      cpm_halt_loop


; ***************************************************************************
; * Load and relocate a system file                                         *
; ***************************************************************************
; Entry: HL=file name
;        IX=start address
;        DE=size in bytes
;        B=file number
;        C=page for top 16K
;        A=load offset (H for SPR files, H-1 for REL files)

load_and_relocate:
        ld      (load_offset),a         ; store relocation offset
        push    bc
        push    de
        push    ix
        push    hl
        ld      hl,msg_relocating
        call    printmsg                ; "Relocating "
        pop     hl
        call    printmsg                ; display filename
        pop     hl
        pop     de
        pop     bc
        push    hl
        push    de
        push    bc
        callp3d dos_read,7              ; read the program data
        jr      nc,cpm_halt_readerr     ; stop if couldn't
        pop     bc
        pop     de
        push    de
        push    bc
        addde_N 7
        ld      b,3
        bsrl()                          ; DE=size of relocation bitmap
        ld      hl,(bufferaddr)
        pop     bc                      ; B=file, C=page for top 16K
        push    bc
        callp3d dos_read,7              ; read the relocation bitmap
        jr      nc,cpm_halt_readerr     ; stop if couldn't
        pop     bc                      ; B=file, C=page for top 16K
        push    bc
        callp3d dos_close,7             ; close the file
        jr      nc,cpm_halt_readerr
        pop     bc                      ; C=page for top 16K
        pop     de                      ; DE=program size
        pop     hl                      ; HL=start address
        ld      a,c
        add     a,a
        nxtrega nxr_mmu6                ; page in program data at top
        inc     a
        nxtrega nxr_mmu7
        ld      ix,(bufferaddr)         ; IX=relocation bitmap
reloc_newbyte:
        ld      c,(ix+0)                ; get next byte from relocation bitmap
        inc     ix
        ld      b,8                     ; bits left in current reloc byte
reloc_nextbit:
        rl      c                       ; check next bit
        jr      nc,reloc_skip           ; on if relocation not needed
        ld      a,(hl)                  ; get the byte to be relocated
        inc     a
        jr      nz,not_relff
        ld      a,(bios_page)           ; if $ff, use BIOS page
        jr      got_relbyte
not_relff:
        inc     a
        jr      nz,not_relfe
        dec     hl                      ; if $fe, add offset to low byte
        ld      a,(hl)
        add     a,SCB_LOW_OFFSET
        ld      (hl),a
        inc     hl
        ld      a,(scb_page)            ; and use SCB page
        jr      got_relbyte
not_relfe:
        inc     a
        jr      nz,not_relfd
        ld      a,(res_page)            ; if $fd, use resident BDOS page
        jr      got_relbyte
not_relfd:
        inc     a
        jr      nz,not_relfc
        ld      a,(bnk_page)            ; if $fc, use banked BDOS page
        jr      got_relbyte
not_relfc:
        inc     a
        jr      nz,not_relfb
        ld      a,(scb_page)            ; if $fb, use SCB page
        jr      got_relbyte
not_relfb:
        ld      a,(load_offset)
        add     a,(hl)                  ; otherwise, add load offset
got_relbyte:
        ld      (hl),a                  ; store relocated value
reloc_skip:
        inc     hl                      ; address next byte in program data
        dec     de
        ld      a,d
        or      e
        jr      z,reloc_done            ; exit when all bytes processed
        djnz    reloc_nextbit           ; back for more bits in bitmap byte
        jr      reloc_newbyte           ; get next bitmap byte when exhausted

reloc_done:
        nxtregn nxr_mmu6,MMU6_DEFAULT   ; restore normal bindings for MMU6/7
        nxtregn nxr_mmu7,MMU7_DEFAULT
        ret


; ***************************************************************************
; * Print a message                                                         *
; ***************************************************************************
; Entry: HL=message
; Messages may be terminated with $ff or 0.

printmsg:
; This instruction will be NOPped out once the CP/M terminal is available,
; so it instead falls through to vterm_printmsg.
        jr      rst10_printmsg


; ***************************************************************************
; * Print a message on the CP/M terminal                                    *
; ***************************************************************************
; Entry: HL=message
; Messages may be terminated with $ff or 0.

vterm_printmsg:
        ld      c,(hl)                  ; C=character
        inc     hl
        ld      a,c
        and     a
        ret     z                       ; exit if 0 terminator
        inc     a
        ret     z                       ; exit if $ff terminator
        push    hl
        ld      ix,(bios_hdr+BIOSHDR_VTERM_OUT)
        call    jpix                    ; output character C
        pop     hl
        jr      printmsg


; ***************************************************************************
; * Print a message on the NextBASIC screen                                 *
; ***************************************************************************
; Entry: HL=message
; Messages may be terminated with $ff or 0.

rst10_printmsg:
        ld      a,(hl)
        inc     hl
        and     a
        ret     z                       ; exit if 0 terminator
        inc     a
        ret     z                       ; exit if $ff terminator
        dec     a
        print_char()
        jr      printmsg


; ***************************************************************************
; * Initialise DPBs, drive table and XDPB table                             *
; ***************************************************************************

COMMON_OFFSET   equ     $4000           ; common mem normally in MMU7, not MMU5

init_cpmdrives:
        nxtregn nxr_mmu5,COMMON_BANKU   ; common memory upper bank
        nxtregn nxr_mmu6,P3DOS_BANKL    ; RAM7 (containing XDPBs) into MMU7/6
        nxtregn nxr_mmu7,P3DOS_BANKU
        ld      hl,dos_table
        ld      de,DOSTBL_BASE-COMMON_OFFSET
        ld      bc,NUM_DRIVES
        ldir                            ; copy +3DOS-only drives table
        ld      hl,map_table
        ld      de,MAPTBL_BASE-COMMON_OFFSET
        ld      bc,NUM_DRIVES
        ldir                            ; copy drive mapping table
        ld      hl,xdpb_table
        ld      de,(bios_hdr+BIOSHDR_DPHS)
        ld      bc,DPB_BASE-COMMON_OFFSET
        xor     a                       ; starting drive 0
init_drv_loop:
        push    bc                      ; save address of current DPB
        push    de                      ; save address of current DPH
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                  ; DE=pointer to XDPB in RAM7
        inc     hl
        ex      (sp),hl                 ; save address within table of XDPBs,
        push    hl                      ; HL=DPH address, re-save
        push    af                      ; save drive id
        ex      de,hl                   ; HL=XDPB address, DE=DPH address
        ld      a,h
        or      l
        jr      z,init_drv_null         ; if no XDPB, on to set zero pointers
        push    hl
        addhl_N dpb_dsm+1
        ld      a,(hl)
        pop     hl
        cp      MAX_BLOCKS/$100
        jr      nc,init_drv_null        ; ignore drives with too many blocks
        push    hl
        addhl_N dpb_drm+1
        ld      a,(hl)
        pop     hl
        cp      MAX_DIRENTS/$100
        jr      nc,init_drv_null        ; ignore drives with too many dir entries
        push    hl
        addhl_N dpb_cks+1
        ld      a,(hl)
        pop     hl
        cp      $80
        jr      nz,init_drv_null        ; ignore non-fixed drives
        push    hl                      ; save XDPB address
        push    de                      ; save DPH address
        ld      d,b
        ld      e,c
        ld      bc,DPB_SIZE
        ldir                            ; copy DPB contents
        pop     de                      ; DE=DPH address
        pop     bc                      ; BC=XDPB address
        jr      init_drv_setptrs        ; on to set the pointers
init_drv_null:
        ld      bc,0
        ld      d,b
        ld      e,c
init_drv_setptrs:                       ; Here: BC=XDPB address, DE=DPH address
        pop     af                      ; A=drive id
        push    af
        add     a,a                     ; A=2*drive id
        ld      hl,DRVTBL_BASE-COMMON_OFFSET
        addhl_A_badFc()
        ld      (hl),e                  ; store DPH pointer (or zero)
        inc     hl
        ld      (hl),d
        ld      hl,XDPBTBL_BASE-COMMON_OFFSET
        addhl_A_badFc()
        ld      (hl),c                  ; store XDPB pointer (or zero)
        inc     hl
        ld      (hl),b
        pop     af                      ; A=drive id
        pop     de                      ; DE=current DPH
        pop     hl                      ; HL=address within table of XDPBs
        pop     bc                      ; BC=current DPB
        addbc_N DPB_SIZE                ; advance to next DPB
        addde_N DPH_SIZE                ; advance to next DPH
        inc     a
        cp      NUM_DRIVES
        jr      c,init_drv_loop         ; back for more drives
        nxtregn nxr_mmu5,MMU5_DEFAULT   ; restore normal bindings for MMU5/6/7
        nxtregn nxr_mmu6,MMU6_DEFAULT
        nxtregn nxr_mmu7,MMU7_DEFAULT
        ret


; ***************************************************************************
; * Library files                                                           *
; ***************************************************************************

include "fragmentation.asm"

MKDATA  equ     1
include "createp3d.asm"


; ***************************************************************************
; * Messages                                                                *
; ***************************************************************************

msg_help:       ;12345678901234567890123456789012
        defm    "NextZXOS CP/M Loader v",LOADER_HI,".",LOADER_MID,$0d
        defm    "by Garry Lancaster",$0d,0

msg_vthelp:     ;12345678901234567890123456789012345678901234567890
        defm    "NextZXOS CP/M Loader v",LOADER_HI,".",LOADER_MID
        defm    " by Garry Lancaster",$0d,$0a,$0a,0

msg_oldloader:
        defm    $0d,$0d
        defm    "BIOS requires more recent",$0d
        defm    "version of .CPM loader.",$0d,0

msg_unmounting:
        defm    $0d,"Unmounting RAMdisk & images:",$0d,0

msg_mounting:
        defm    $0d,"Mounting drives for CP/M:",$0d,0

msg_loading:
        defm    $0d,"Loading ",0

msg_opening:
        defm    $0d,$0a,"Opening ",0

msg_relocating:
        defm    $0d,$0a,"Relocating ",0

msg_crlf:
        defm    $0d,$0a,0

msg_ok:
        defm    " - OK",$0d,0

msg_ok_crlf:
        defm    " - OK",$0d,$0a,0


msg_fail:
        defm    " - fail",$0d,0

msg_nofile:
        defm    " - unable to open file",$0d,0

msg_readerr:
        defm    " - error reading file",$0d,0

msg_invalid:
        defm    " - invalid",$0d,0

msg_halted:
        defm    $0d,$0a,$0a
                ;1234567890123456789012345678901234567890
        defm    "CP/M could not be started.",$0d,$0a
        defm    "Please ensure you have all the files "
        defm    "from the latest distribution in:",$0d,$0a
        defm    "  C:/NEXTZXOS/CPM",$0d,$0a
        defm    "  C:/NEXTZXOS/CPM/SYSTEM",$0d,$0a,0

; Filenames of CPM3 system files.
msg_sysdir:
        defm    "/NEXTZXOS/CPM/SYSTEM/"
msg_sysdir_end:

msg_biosfile:
        defm    "NEXTBIOS.PRL",$ff
msg_resfile:
        defm    "RESBDOS3.SPR",$ff
msg_bnkfile:
        defm    "BNKBDOS3.SPR",$ff
msg_font1norm_file:
        defm    "NORMAL.FNT",$ff
msg_font1und_file:
        defm    "UNDER.FNT",$ff
msg_font1ital_file:
        defm    "ITALIC.FNT",$ff
msg_font1itun_file:
        defm    "ITAL_UND.FNT",$ff
msg_fontgfx_file:
        defm    "GRAPHICS.FNT",$ff
msg_biosext_file:
        defm    "BIOSEXT.BIN",$ff
msg_ccp_file:
        defm    "CCP.COM",$ff

; Filespec for matching: CPM-d.P3D, CPM-d.DSK, DRV-d.DSK, DRV-d.P3D
; system drive images (where d=drive letter, 'A' to 'P')
msg_mountfilespec:
        defm    "C:/NEXTZXOS/"
msg_mountfilespec_prefix:
        defm    "???-"
msg_mountfilespec_drive:
        defm    "?."
msg_mountfilespec_extn:
        defm    "???",$ff
msg_mountfilespec_end:

if ((msg_mountfilespec_end-msg_mountfilespec) > FILESPEC_LENGTH)
.ERROR FILESPEC_LENGTH is too small
endif

; Prefixes and extensions for matching system images.
msg_mountdrv:
        defm    "DRV"
msg_mountcpm:
        defm    "CPM"
msg_mountp3d:
        defm    "P3D"
msg_mountdsk:
        defm    "DSK"

; Error reports (terminated with bit 7).
msg_badnextzxos:
        defm    "Requires NextZXOS v2.02",'+'+$80

msg_oom:
        defm    "Out of memor",'y'+$80

msg_unabletoload:
        defm    "Could not load fil",'e'+$80

msg_badmount:
        defm    "Unmountable imag",'e'+$80

msg_badloader:
        defm    ".CPM out of dat",'e'+$80

; Signon message
msg_signon:
        defm    27,'E'                  ; clear & home
        defm    "CP/M Plus ",$ff

; Sanity check for BDOS copyright message
msg_checkcopyright:
        defm    "COPYRIGHT"
msg_checkcopyright_end:

; TPA size messages
msg_tpa_num:
        defm    "00",$ff

        defm    ".25"
msg_k_tpa:
        defm    "K TPA",$0d,$0a,$0a,$ff

; Default image name, to create if not found
filename:
        defm    "c:/nextzxos/cpm-a.p3d",0


; ***************************************************************************
; * Data                                                                    *
; ***************************************************************************

entry_sp:
        defw    0                       ; entry stack pointer

saved_speed:
        defb    0                       ; original turbo mode

old_caps:
        defb    0                       ; original capabilities

bios_page:
        defb    0                       ; start page of BIOS

scb_page:
        defb    0                       ; page of SCB

res_page:
        defb    0                       ; start page of resident BDOS

bnk_page:
        defb    0                       ; start page of banked BDOS

bios_size:
        defw    0                       ; size of BIOS in bytes

res_size:
        defw    0                       ; size of resident BDOS in bytes

bnk_size:
        defw    0                       ; size of banked BDOS in bytes

load_offset:
        defb    0                       ; relocation page offset

cat_addr:
        defw    0                       ; catalog address

xdpb_table:
        defs    NUM_DRIVES*2            ; XDPBs mapped to CP/M drives A..P

map_table:
        defs    NUM_DRIVES              ; for each CP/M drive A..P, letter
                                        ; under which NextZXOS can access it
                                        ; (or 0=no such CP/M drive)

dos_table:
        defs    NUM_DRIVES              ; for each NextZXOS drive letter A..P,
                                        ; contains:
                                        ;   0=not mapped
                                        ;   A-P=CP/M drive mounted here
                                        ;   $ff=drive inaccessible to CP/M

bios_hdr:
        defs    BIOSHDR_LENGTH          ; BIOS extension header
bios_data:
if ($+MAX_BIOS_EXT_SIZE>$4000)
.WARNING bios_data overruns into ULA screen
endif
