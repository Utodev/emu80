; ***************************************************************************
; * Dot command for installing loadable drivers:                            *
; * .install filename.drv                                                   *
; ***************************************************************************
; Assemble with: pasmo install.asm install
; Place in C:/DOT directory and execute with:  .install filename.drv

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

; Constants
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
        jr      nc,install_start        ; okay if not
show_usage:
        ld      hl,msg_help
        call    printmsg
        and     a                       ; Fc=0, successful
        ret


; ***************************************************************************
; * Open file and validate header                                           *
; ***************************************************************************

install_start:
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
        jp      nc,out_of_memory        ; on if error
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
        inc     h                       ; HL=address for preload buffer
        ld      (preload_addr),hl
        inc     h
        inc     h                       ; HL=address to load driver+reloc
        ld      (driver_addr),hl


; ***************************************************************************
; * Read the driver into newly-allocated workspace                          *
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
; * Attempt to allocate requested memory banks                              *
; ***************************************************************************

        ld      a,1
        ld      (mmcbanksvalid),a       ; mark MMC banklist as valid
        ld      a,(fileheader+6)
        and     $7f                     ; A=# MMC banks to allocate
        ld      hl,(mmcbanklist_addr)
        ld      d,1                     ; rc_banktype_mmc
        call    allocate_banks

        ld      a,1
        ld      (zxbanksvalid),a        ; mark ZX banklist as valid
        ld      a,(fileheader+7)        ; A=# ZX banks to allocate
        ld      hl,(zxbanklist_addr)
        ld      d,0                     ; rc_banktype_zx
        call    allocate_banks


; ***************************************************************************
; * Preload data and patch driver for DivMMC banks                          *
; ***************************************************************************

        ld      hl,(mmcbanklist_addr)
        ld      de,divmmc_copy
        ld      bc,divmmc_copy_end-divmmc_copy
        call    preload_and_patch_banks
        ld      hl,(zxbanklist_addr)
        ld      de,zx_copy
        ld      bc,zx_copy_end-zx_copy
        call    preload_and_patch_banks


; ***************************************************************************
; * Attempt to install the driver                                           *
; ***************************************************************************

        ld      de,(fileheader+4)       ; E=id, D=#relocs
        ld      hl,(driver_addr)        ; HL=address of driver
        ld      bc,$0100                ; C=0, driver API. B=1, install.
        callesx m_drvapi                ; install the driver
        jr      c,translate_drvapi_err


; ***************************************************************************
; * Initialise the driver                                                   *
; ***************************************************************************

        ld      a,(fileheader+6)
        bit     7,a
        jr      z,install_success       ; on if initialise not needed
        ld      a,(fileheader+4)
        and     $7f
        ld      c,a                     ; C=driver id
        ld      b,$80                   ; B=$80, initialise
        ld      hl,(zxbanklist_addr)    ; HL=number and list of ZX banks
        ld      de,(mmcbanklist_addr)   ; DE=number and list of MMC banks
        callesx m_drvapi                ; initialise the driver
        jr      nc,install_success      ; on if successfully initialised
        ld      de,(fileheader+4)       ; E=id
        ld      bc,$0200                ; C=0, driver API. B=2, uninstall.
        callesx m_drvapi                ; uninstall the driver again
        ld      hl,msg_initfail
        jr      err_custom


; ***************************************************************************
; * Successful installation                                                 *
; ***************************************************************************

install_success:
        call    close_and_deallocate    ; close file, free workspace bank
        xor     a                       ; Fc=0, success
        ei                              ; re-enable interrupts
        ret


; ***************************************************************************
; * Translate esxDOS error codes from driver API to more meaningful errors  *
; ***************************************************************************

translate_drvapi_err:
        cp      esx_eexist              ; "exists" means already installed
        ld      hl,msg_installed
        jr      z,err_custom

        cp      esx_einuse              ; "in use" means out of driver slots
        ld      hl,msg_noslots
        jr      z,err_custom

        cp      esx_eloadingko          ; "sys file load error" means bad
        ld      hl,msg_badreloc         ; relocation table
        jr      z,err_custom

        scf                             ; shouldn't be any other errors,
                                        ; but fall through just in case

; ***************************************************************************
; * Close file, deallocate banks and exit with any error condition          *
; ***************************************************************************

exit_error:
        push    af                      ; save error status
        push    hl
        ld      hl,(mmcbanklist_addr)
        ld      d,1                     ; rc_banktype_mmc
        ld      a,(mmcbanksvalid)
        and     a
        call    nz,deallocate_banks     ; deallocate if valid
        ld      hl,(zxbanklist_addr)
        ld      d,0                     ; rc_banktype_zx
        ld      a,(zxbanksvalid)
        and     a
        call    nz,deallocate_banks     ; deallocate if valid
        call    close_and_deallocate    ; close file, free workspace bank
        pop     hl                      ; restore error status
        pop     af
        ei                              ; re-enable interrupts
        ret


; ***************************************************************************
; * Close file and free workspace bank                                      *
; ***************************************************************************

close_and_deallocate:
        ld      a,(filehandle)
        callesx f_close                 ; close the file
        ld      hl,(workspace_mmubank)  ; get previous bank & MMU id
        ld      a,h
        and     a
        ret     z                       ; nothing to do if MMU id not valid
        ld      bc,next_reg_select
        out     (c),h
        inc     b
        out     (c),l                   ; restore MMU binding
        ld      a,(workspace_bank)
        ld      e,a                     ; E=allocated workspace bank
        ld      hl,$0003                ; free ZX bank
        callp3d ide_bank,7
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
; * Attempt to allocate banks                                               *
; ***************************************************************************
; Entry: A=number of banks to allocate
;        D=rc_banktype_mmc (1) or rc_banktype_zx (0)
;        HL=(mmcbanklist_addr) or (zxbanklist_addr)
; Does not return if banks could not be allocated.

allocate_banks:
        ld      (hl),0                  ; set banks allocated to zero
        and     a
        ret     z                       ; Fc=0, success, if none requested
        ld      e,1                     ; rc_bank_alloc
        push    hl                      ; save address of number allocated
allocate_banks_loop:
        push    af                      ; save number still to allocate
        push    de                      ; save allocation reasons
        inc     hl
        push    hl                      ; save address to place next bank
        ex      de,hl                   ; H=banktype, L=alloc
        callp3d ide_bank,7
        jr      nc,alloc_failed         ; on if error
        pop     hl
        ld      (hl),e                  ; store bank id
        pop     de
        pop     af
        ex      (sp),hl
        inc     (hl)                    ; increment number allocated
        ex      (sp),hl
        dec     a
        jr      nz,allocate_banks_loop  ; back for more
        pop     hl                      ; discard address of number
        and     a                       ; Fc=0, success
        ret

alloc_failed:
        pop     hl                      ; discard address to store bank
        pop     hl                      ; discard allocation reasons
        pop     hl                      ; discard number to allocate
        pop     hl                      ; discard address of number
        pop     hl                      ; discard return address
out_of_memory:
        ld      hl,msg_allocerror
        jr      err_custom


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
deallocate_banks_loop:
        push    af                      ; save number still to deallocate
        push    de                      ; save allocation reasons
        inc     hl
        push    hl                      ; save address of next bank
        ld      l,(hl)                  ; L=bank id
        ex      de,hl                   ; H=banktype, L=alloc, E=bank id
        callp3d ide_bank,7
        pop     hl
        pop     de
        pop     af
        dec     a
        jr      nz,deallocate_banks_loop; back for more
        ret


; ***************************************************************************
; * Preload bank data and patch driver with bank ids                        *
; ***************************************************************************
; Entry: HL=(mmcbanklist_addr) or (zxbanklist_addr)
;        DE=copy routine address
;        BC=copy routine length

preload_and_patch_banks:
        ld      a,(hl)
        and     a
        ret     z                       ; exit if no banks allocated
        ld      (saved_sp),sp           ; save current SP
        ld      (saved_hl),hl
        ld      hl,0
        add     hl,sp
        and     a
        sbc     hl,bc
        ld      sp,hl                   ; move SP down for copy routine
        ld      (preload_copy_call+1),hl; patch call routine
        ex      de,hl                   ; HL=routine source,DE=dest,BC=size
        ldir                            ; install copy routine
        ld      hl,(saved_hl)
        ld      b,(hl)                  ; B=number of banks
preload_and_patch_bank_loop:
        push    bc                      ; save remaining banks
        inc     hl
        push    hl                      ; save address of current bank id
        ld      hl,bank_patches
        ld      bc,3
        ld      a,(filehandle)
        callesx f_read                  ; read #patches & size of preload
        jp      c,preload_error         ; exit with any error
        ld      a,(bank_patches)
        and     a                       ; if 0, A=0 (custom error)
        scf
        ld      hl,msg_need1patch
        jp      z,preload_error         ; exit if zero bank patches
        ld      hl,(bank_preloadsize)
        ld      bc,8193
        xor     a                       ; A=0, custom error; Fc=0
        sbc     hl,bc
        ccf
        ld      hl,msg_badpreloadsize
        jp      c,preload_error         ; exit if preload size > 8192
        ld      b,8192/512              ; fill bank in 512-byte chunks
        ld      de,$2000                ; start address to fill
        pop     hl                      ; HL=address of bank id
        push    hl
preload_fill_loop:
        push    bc
        push    hl
        push    de
        ld      hl,(preload_addr)
        ld      d,h
        ld      e,l
        inc     de
        ld      bc,511
        ld      (hl),0
        ldir                            ; erase preload buffer
        ld      bc,(bank_preloadsize)
        ld      a,b
        or      c
        jr      z,preload_noload        ; skip file read if none left
        ld      hl,512
        sbc     hl,bc
        jr      nc,preload_bc           ; if BC<=512, read it all
        ld      bc,512                  ; otherwise use 512
preload_bc:
        push    bc                      ; save size being read
        ld      hl,(preload_addr)
        ld      a,(filehandle)
        callesx f_read                  ; read the preload data
        jr      c,preload_error
        pop     bc
        ld      hl,(bank_preloadsize)
        sbc     hl,bc
        ld      (bank_preloadsize),hl   ; update remaining size
preload_noload:
        pop     de                      ; DE=current bank load address
        pop     hl
        pop     bc                      ; B=chunk counter, 8192/512-->0
        push    bc
;        call    preload_fixup           ; fix up any known driver issues
        ld      a,(hl)                  ; A=bank id
        push    hl
        ld      hl,(preload_addr)
        ld      bc,512
preload_copy_call:
        call    0                       ; copy the data into the bank
        pop     hl
        pop     bc
        djnz    preload_fill_loop
        ld      hl,(bank_patches)
        ld      h,0
        add     hl,hl                   ; size of patch list
        ld      b,h
        ld      c,l
        ld      hl,(preload_addr)
        ld      a,(filehandle)
        callesx f_read                  ; read the patch data
        jr      c,preload_error
        ld      a,(bank_patches)
        ld      b,a
        pop     hl
        ld      c,(hl)                  ; C=bank id
        push    hl
        ld      hl,(preload_addr)
preload_patch_loop:
        push    bc                      ; save remaining patches
        ld      c,(hl)
        inc     hl
        ld      b,(hl)                  ; BC=offset of next patch
        inc     hl
        ld      a,b
        and     $fe
        jr      nz,bad_bank_patch
        ex      de,hl
        ld      hl,(driver_addr)
        add     hl,bc                   ; address of byte to patch
        pop     bc                      ; B=remaining patches, C=bank id
        ld      (hl),c                  ; patch bank id in
        ex      de,hl
        djnz    preload_patch_loop
        pop     hl                      ; address in bank list
        pop     bc
        dec     b
        jp      nz,preload_and_patch_bank_loop
        ld      sp,(saved_sp)           ; restore SP
        ret

bad_bank_patch:
        xor     a                       ; A=0, custom error
        scf                             ; error
        ld      hl,msg_badbankpatch
preload_error:
        ld      sp,(saved_sp)           ; restore SP
        pop     de                      ; discard return address
        jp      exit_error


; ***************************************************************************
; * Copy preload data into DivMMC bank                                      *
; ***************************************************************************
; Entry: HL=source data (>=$4000)
;        DE=dest data in bank ($2000..$3fff)
;        BC=length
;        A=bank id
; Exit:  DE=dest+length

divmmc_copy:
        ex      af,af'
        in      a,(div_memctl)          ; save dot command's paging value
        ex      af,af'
        set     7,a
        out     (div_memctl),a          ; page in DivMMC bank
        ldir                            ; copy preload/erased data
        ex      af,af'
        out     (div_memctl),a          ; page back dot command
        ret
divmmc_copy_end:


; ***************************************************************************
; * Copy preload data into ZX bank                                          *
; ***************************************************************************
; Entry: HL=source data (>=$4000)
;        DE=dest data in bank ($2000..$3fff)
;        BC=length
;        A=bank id
; Exit:  DE=dest+length

zx_copy:
        nxtrega nxr_mmu1                ; page ZX RAM to $2000
        ex      af,af'
        in      a,(div_memctl)          ; save dot command's paging value
        ex      af,af'
        xor     a
        out     (div_memctl),a          ; disable DivMMC
        ldir                            ; copy preload/erased data
        nxtregn nxr_mmu1,$ff            ; page ROM to $2000
        ex      af,af'
        out     (div_memctl),a          ; page back dot command
        ret
zx_copy_end:


if 0

; NOTE: It turns out this is insufficient to deal with all issues in the
;       NextDAW driver for uninitialised channels. Therefore the DivMMC ROM
;       is now patched to ensure a zero at address $0019, which is used as a
;       set of enable flags for uninitialised channels.

; ***************************************************************************
; * Detection of faulty NextDAW driver                                      *
; ***************************************************************************
; v1.40 (and possibly other versions) of nextdaw.drv has a bug where
; before a song is loaded, each voice patch is in an uninitialised state.
; However, the routine to update the voices is always called (as this is still
; needed when stopping a song). Before any song is loaded this routine ends
; up addressing voice data indexed by IY, with IY set to zero. Since DivMMC
; ROM is present at address $0000, this can lead to random sounds being
; generated, depending upon the version of NextZXOS.
; To fix this, if a song is not loaded we patch the code to skip the routine
; to update the voices. This change means that stopping a song must use
; a hard stop rather than relying on the ISR to decay the voices naturally.
; To do this, we also patch the jump block at the start of the driver.

nextdaw_140_block       equ     8192/512
nextdaw_140_offset      equ     $01da

nextdaw_140_skip_offset equ     $01df   ; changes:      jp z,$81e7
nextdaw_140_skip_data   equ     $ea     ; to:           jp z,$81ea

nextdaw_140_vector_dst  equ     $0a     ; patch 4th jump (stop song)
nextdaw_140_vector_src  equ     $0d     ; to match 5th jump (hard stop)

bad_next

nextdaw_140_data:
l_81da:
        ld      a,($806a)               ; checks if .NDR is loaded
        or      a
l_81de:
        jp      z,$81e7
        call    $8e71
        call    $8e44
l_81e7:
        call    $81f7                   ; this routine updates the voices
l_81ea:
nextdaw_140_data_end:


; ***************************************************************************
; * Fixup any known faulty drivers during install                           *
; ***************************************************************************

preload_fixup:
        ld      a,(fileheader+4)
        cp      $b2                     ; NextDAW driver?
        ret     nz                      ; no other drivers to patch
        ld      a,b
        cp      nextdaw_140_block       ; potential bad block of nextdaw.drv?
        ret     nz                      ; don't have any patches if not
        push    bc
        push    de
        push    hl
        ld      hl,(preload_addr)
        addhl_N nextdaw_140_offset
        ld      de,nextdaw_140_data
        ld      bc,nextdaw_140_data_end-nextdaw_140_data
preload_fixup_check_loop:
        ld      a,(de)                  ; check if the v1.40 code is present
        inc     de
        cp      (hl)
        inc     hl
        jr      nz,preload_fixup_done   ; exit if it isn't
        dec     bc
        ld      a,b
        or      c
        jr      nz,preload_fixup_check_loop
        ld      a,nextdaw_140_skip_data
        ld      hl,(preload_addr)
        push    hl
        addhl_N nextdaw_140_skip_offset
        ld      (hl),a                  ; patch to skip the voice update
        pop     hl
        push    hl
        addhl_N nextdaw_140_vector_src
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                  ; fetch address of hard stop routine
        pop     hl
        addhl_N nextdaw_140_vector_dst
        ld      (hl),e
        inc     hl
        ld      (hl),d                  ; patch standard stop routine
preload_fixup_done:
        pop     hl
        pop     de
        pop     bc
        ret

endif


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

mmcbanksvalid:
        defb    0

zxbanksvalid:
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

preload_addr:
        defw    0

saved_sp:
        defw    0

saved_hl:
        defw    0


; ***************************************************************************
; * Messages                                                                *
; ***************************************************************************

msg_badsig:
        defm    "Invalid .DRV fil",'e'+$80

msg_allocerror:
        defm    "Out of memory bank",'s'+$80

msg_installed:
        defm    "Driver already installe",'d'+$80

msg_noslots:
        defm    "Out of driver slot",'s'+$80

msg_badreloc:
        defm    "Bad relocation tabl",'e'+$80

msg_need1patch:
        defm    "Bank must have 1+ patche",'s'+$80

msg_badpreloadsize:
        defm    "Preload size > 8192 byte",'s'+$80

msg_badbankpatch:
        defm    "Bad bank patch offse",'t'+$80

msg_initfail:
        defm    "Driver init faile",'d'+$80

msg_help:
        defm    "INSTALL v1.5 by Garry Lancaster",$0d
        defm    "Installs a NextZXOS driver",$0d,$0d
        defm    "SYNOPSIS:",$0d
        defm    " .INSTALL NAME.DRV",$0d,0

