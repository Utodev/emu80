; ***************************************************************************
; * Dot command for uninstalling loadable drivers:                          *
; * .uninstall filename.drv                                                 *
; ***************************************************************************
; Assemble with: pasmo uninstall.asm uninstall
; Place in C:/DOT directory and execute with:  .uninstall filename.drv

include "nexthw.def"
include "macros.def"
include "esxapi.def"
include "nextzxos.def"


; ***************************************************************************
; * .DRV file format                                                        *
; ***************************************************************************
; A valid .DRV file is laid out as:
;
;       defm    "NDRV"          ; .DRV file signature
;
;       defb    id              ; 7-bit unique driver id in bits 0..6
;                               ; bit 7=1 if to be called on IM1 interrupts
;
;       defb    relocs          ; number of relocation entries (0..255)
;
;       defb    mmcbanks        ; number of additional 8K DivMMC RAM banks
;                               ; required (0..8)
;
;       Additionally if bit 7 of mmcbanks is set:
;       .INSTALL will call driver function $80
;       .UNINSTALL will call driver function $81
;       Entry parameters:
;         HL=address of: byte 0: # allocated ZX RAM banks
;                        bytes 1+: list of ZX RAM bank ids
;         DE=address of: byte 0: # allocated DivMMC RAM banks
;                        bytes 1+: list of DivMMC RAM bank ids
;       If carry is set on exit, .INSTALL/.UNINSTALL will be aborted.
;
;       defb    zxbanks         ; number of additional 8K Spectrum RAM banks
;                               ; required (0..200)
;
;       defs    512             ; 512-byte driver code, assembed at ORG 0
;
;       defs    relocs*2        ; for each relocation, a 2-byte offset (0..511)
;                               ; of the high byte of the address to be relocated
;
;       Then, for each mmcbank requested:
;
;       defb    bnk_patches     ; number of driver patches for this bank id
;       defw    bnk_size        ; size of data to pre-load into bank (0..8191)
;       defs    bnk_size        ; data to pre-load into bank
;       defs    bnk_patches*2   ; for each patch, a 2-byte offset (0..511) in
;                               ; the 512-byte driver to write the bank id to
;       NOTE: The first patch for each mmcbank should never be changed, as
;             .uninstall will use the value for deallocating.
;
;       Then, for each zxbank requested:
;
;       defb    bnk_patches     ; number of driver patches for this bank id
;       defw    bnk_size        ; size of data to pre-load into bank (0..8191)
;       defs    bnk_size        ; data to pre-load into bank
;       defs    bnk_patches*2   ; for each patch, a 2-byte offset (0..511) in
;                               ; the 512-byte driver to write the bank id to
;       NOTE: The first patch for each zxbank should never be changed, as
;             .uninstall will use the value for deallocating.
;


; ***************************************************************************
; * Internal definitions                                                    *
; ***************************************************************************

drv_header_len          equ     8               ; size of .DRV header


; ***************************************************************************
; * Initialisation                                                          *
; ***************************************************************************
; Dot commands always start at $2000, with HL=address of command tail
; (terminated by $00, $0d or ':').

        org     $2000

        ld      a,h
        or      l
        jr      z,show_usage            ; no tail provided if HL=0
        ld      de,filename
        call    get_sizedarg            ; get first argument to filename
        jr      nc,show_usage           ; if none, just go to show usage
        ld      de,0                    ; further args to ROM
        call    get_sizedarg            ; check if any further args
        jr      nc,uninstall_start      ; okay if not
show_usage:
        ld      hl,msg_help
        call    printmsg
        and     a                       ; Fc=0, successful
        ret


; ***************************************************************************
; * Open file and validate header                                           *
; ***************************************************************************

uninstall_start:
        di                              ; ensure interrupts disabled
                                        ; for remainder of command
        ld      a,'*'                   ; default drive
        ld      hl,filename
        ld      b,esx_mode_read+esx_mode_open_exist
        callesx f_open                  ; attempt to open the file
        ret     c                       ; exit with any error

        ld      (filehandle),a          ; store the filehandle for later
        ld      hl,fileheader
        ld      bc,8
        callesx f_read                  ; read the 8-byte header
        jp      c,exit_error            ; exit with any error

        ld      hl,(fileheader)         ; validate signature
        ld      de,(filesig)
        and     a
        sbc     hl,de
        jp      nz,err_badsig
        ld      hl,(fileheader+2)
        ld      de,(filesig+2)
        and     a
        sbc     hl,de
        jp      nz,err_badsig


; ***************************************************************************
; * Allocate workspace memory in main RAM                                   *
; ***************************************************************************

        ld      hl,$0001                ; allocate a ZX bank
        callp3d ide_bank,7
        ld      hl,msg_allocerror
        jp      nc,err_custom           ; on if error
        ld      a,e
        ld      (workspace_bank),a      ; save bank id
        ld      hl,0
        add     hl,sp
        ld      a,h
        cp      $c0
        ld      d,nxr_mmu7              ; use MMU7 for workspace if SP<$c000
        ld      hl,$e000
        jr      c,use_mmu
        ld      d,nxr_mmu4              ; use MMU4 if SP>=$c000
        ld      hl,$8000
use_mmu:
        ld      bc,next_reg_select
        out     (c),d
        inc     b
        in      a,(c)
        out     (c),e                   ; page in allocated bank for workspace
        ld      e,a                     ; E=previously-paged bank
        ld      (workspace_mmubank),de  ; save previous bank & MMU id
                                        ; HL=address for list of MMC banks
        ld      (mmcbanklist_addr),hl
        inc     h                       ; HL=address of list of ZX banks
        ld      (zxbanklist_addr),hl
        inc     h                       ; HL=address to load driver+reloc
        ld      (driver_addr),hl


; ***************************************************************************
; * Read driver from the file into newly-allocated workspace                *
; ***************************************************************************

        ld      hl,(fileheader+5)       ; L=#relocs
        ld      h,0
        add     hl,hl                   ; HL=size of relocations
        inc     h                       ; +512 for driver
        inc     h
        ld      b,h                     ; BC=size of driver+relocs
        ld      c,l
        ld      hl,(driver_addr)
        ld      a,(filehandle)
        callesx f_read                  ; read the driver+relocs
        jp      c,exit_error            ; exit with any error reading the file


; ***************************************************************************
; * Read installed driver image                                             *
; ***************************************************************************

        ld      hl,(driver_addr)        ; buffer for driver
        ld      a,(fileheader+4)
        ld      e,a                     ; E=id
        ld      bc,$0400                ; C=0, driver API. B=4, get driver.
        callesx m_drvapi                ; get the driver image
        jr      c,exit_error            ; exit if there is an error


; ***************************************************************************
; * Obtain the banklists from the driver image                              *
; ***************************************************************************

        ld      hl,(mmcbanklist_addr)
        ld      a,(fileheader+6)
        and     $7f                     ; A=# MMC banks
        call    generate_banklist       ; get the allocated MMC banks
        ld      hl,(zxbanklist_addr)
        ld      a,(fileheader+7)        ; A=# ZX banks
        call    generate_banklist       ; get the allocated ZX banks


; ***************************************************************************
; * Shutdown the driver                                                     *
; ***************************************************************************

        ld      a,(fileheader+6)
        bit     7,a
        jr      z,shutdown_success      ; on if shutdown not needed
        ld      a,(fileheader+4)
        and     $7f
        ld      c,a                     ; C=driver id
        ld      b,$81                   ; B=$81, shutdown
        ld      hl,(zxbanklist_addr)    ; HL=number and list of ZX banks
        ld      de,(mmcbanklist_addr)   ; DE=number and list of MMC banks
        callesx m_drvapi                ; uninitialise the driver
ndrplayer_workaround:
        ; Work around a bug in the NDRPLAYER.DRV driver, which resets
        ; MMU segments 3/4/5 to what it thinks are the correct values (4/5/0).
        ; This will page out our list of banks if currently located in MMU4.
        ld      bc,next_reg_select
        ld      a,(workspace_mmuid)
        out     (c),a
        inc     b
        ld      a,(workspace_bank)
        out     (c),a                   ; re-page our bank
        ld      hl,msg_shutdownfail
        jr      c,err_custom            ; exit if failed


; ***************************************************************************
; * Attempt to uninstall the driver                                         *
; ***************************************************************************

shutdown_success:
        ld      a,(fileheader+4)
        ld      e,a                     ; E=id

        ld      bc,$0200                ; C=0, driver API. B=2, uninstall.
        callesx m_drvapi                ; uninstall the driver
        jr      c,exit_error            ; exit if there is an error


; ***************************************************************************
; * Deallocate the banks associated with the driver                         *
; ***************************************************************************

        ld      hl,(mmcbanklist_addr)
        ld      d,1                     ; rc_banktype_mmc
        call    deallocate_banks        ; deallocate
        ld      hl,(zxbanklist_addr)
        ld      d,0                     ; rc_banktype_zx
        call    deallocate_banks
        xor     a                       ; Fc=0, success!


; ***************************************************************************
; * Close file and exit with any error condition                            *
; ***************************************************************************

exit_error:
        push    af                      ; save error status
        push    hl
        ld      a,(filehandle)
        callesx f_close                 ; close the file
        ld      hl,(workspace_mmubank)  ; get previous bank & MMU id
        ld      a,h
        and     a
        jr      z,exit_noworkspace      ; on if MMU id not valid
        ld      bc,next_reg_select
        out     (c),h
        inc     b
        out     (c),l                   ; restore MMU binding
        ld      a,(workspace_bank)
        ld      e,a                     ; E=allocated workspace bank
        ld      hl,$0003                ; free ZX bank
        callp3d ide_bank,7
exit_noworkspace:
        pop     hl                      ; restore error status
        pop     af
        ei                              ; re-enable interrupts
        ret


; ***************************************************************************
; * Custom error generation                                                 *
; ***************************************************************************

err_badsig:
        ld      hl,msg_badsig
err_custom:
        xor     a                       ; A=0, custom error
        scf                             ; Fc=1, error condition
        jr      exit_error


; ***************************************************************************
; * Print a message                                                         *
; ***************************************************************************

include "printmsg.asm"


; ***************************************************************************
; * Deallocate banks                                                        *
; ***************************************************************************
; Entry: D=rc_banktype_mmc (1) or rc_banktype_zx (0)
;        HL=(mmcbanklist_addr) or (zxbanklist_addr)

deallocate_banks:
        ld      a,(hl)
        and     a
        ret     z                       ; exit if none to deallocate
        ld      e,3                     ; rc_bank_free
        ld      (hl),0                  ; clear number allocated
        ld      b,a                     ; B=# banks to free
deallocate_banks_loop:
        push    bc                      ; save number still to deallocate
        push    de                      ; save allocation reasons
        inc     hl
        push    hl                      ; save address of next bank
        ld      l,(hl)                  ; L=bank id
        ex      de,hl                   ; H=banktype, L=alloc, E=bank id
        callp3d ide_bank,7
        pop     hl
        pop     de
        pop     bc
        jr      nc,dealloc_error        ; exit if error
        djnz    deallocate_banks_loop   ; back for more
        ret

dealloc_error:
        pop     hl                      ; discard return address
        ld      hl,msg_baddealloc
        jr      err_custom


; ***************************************************************************
; * Generate list of allocated bank ids                                     *
; ***************************************************************************
; Entry: HL=(mmcbanklist_addr) or (zxbanklist_addr)
;        A=# banks

generate_banklist:
        ld      (hl),a                  ; store # banks
        and     a
        ret     z                       ; exit if no banks allocated
        ld      (saved_sp),sp           ; save current SP
        ld      b,a                     ; B=number of banks
generate_banklist_loop:
        push    bc                      ; save remaining banks
        inc     hl
        push    hl                      ; save address of current bank id
        ld      hl,bank_patches
        ld      bc,3
        ld      a,(filehandle)
        callesx f_read                  ; read #patches & size of preload
        jp      c,generate_error        ; exit with any error
        ld      a,(bank_patches)
        and     a                       ; if 0, A=0 (custom error)
        scf
        ld      hl,msg_need1patch
        jp      z,generate_error        ; exit if zero bank patches
        ld      hl,(bank_preloadsize)
        ld      bc,8193
        xor     a                       ; A=0, custom error; Fc=0
        sbc     hl,bc
        ccf
        ld      hl,msg_badpreloadsize
        jp      c,generate_error        ; exit if preload size > 8192
        ld      de,(bank_preloadsize)
        ld      a,d
        or      e
        jr      z,skipped_preload       ; nothing to do if zero
        ld      bc,0
        ld      l,esx_seek_fwd
        ld      a,(filehandle)
        callesx f_seek                  ; skip the preload data
skipped_preload:
        ld      hl,(bank_patches)
        ld      h,0
        add     hl,hl                   ; size of patch list
        ld      b,h
        ld      c,l
        ld      hl,(driver_addr)
        inc     h
        inc     h                       ; bank patch data overwrites relocs
        push    hl
        ld      a,(filehandle)
        callesx f_read                  ; read the patch data
        jr      c,generate_error
        pop     hl
        ld      c,(hl)
        inc     hl
        ld      b,(hl)                  ; BC=offset of first patch
        ld      hl,(driver_addr)
        add     hl,bc                   ; address of first patch
        ld      a,(hl)                  ; A=allocated bank id
        pop     hl
        ld      (hl),a                  ; store in bank list
        pop     bc
        djnz    generate_banklist_loop
        ret

generate_error:
        ld      sp,(saved_sp)           ; restore SP
        jp      exit_error


; ***************************************************************************
; * Argument parsing                                                        *
; ***************************************************************************

ARG_PARAMS_DEHL         equ     1
include "arguments.asm"


; ***************************************************************************
; * Data                                                                    *
; ***************************************************************************

filehandle:
        defb    0

filename:
        defs    256

fileheader:
        defs    8

filesig:
        defm    "NDRV"

workspace_mmubank:
        defb    0
workspace_mmuid:
        defb    0

workspace_bank:
        defb    0

mmcbanklist_addr:
        defw    0

zxbanklist_addr:
        defw    0

bank_patches:
        defb    0
bank_preloadsize:
        defw    0
if (bank_preloadsize != (bank_patches+1))
.ERROR Incorrect assumption: bank_preloadsize=bank_patches+1
endif

driver_addr:
        defw    0

saved_sp:
        defw    0


; ***************************************************************************
; * Messages                                                                *
; ***************************************************************************

msg_badsig:
        defm    "Invalid .DRV fil",'e'+$80

msg_need1patch:
        defm    "Bank must have 1+ patche",'s'+$80

msg_badpreloadsize:
        defm    "Preload size > 8192 byte",'s'+$80

msg_shutdownfail:
        defm    "Driver in us",'e'+$80

msg_baddealloc:
        defm    "Error deallocating ban",'k'+$80

msg_allocerror:
        defm    "Out of memory bank",'s'+$80

msg_help:
        defm    "UNINSTALLv1.4 by Garry Lancaster",$0d
        defm    "Uninstalls a NextZXOS driver",$0d,$0d
        defm    "SYNOPSIS:",$0d
        defm    " .UNINSTALL NAME.DRV",$0d,0

