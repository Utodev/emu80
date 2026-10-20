;; code in this section is inserted just before main() is run
;; there must be no RET as code falls through to main()

SECTION code_crt_init

   ;; remember page currently mapped to mmu4 (0x8000 - 0x9fff)
   
   ld bc,$243B
   ld a,$50 + 4
   
   out (c),a                              ; select mmu4 register
   inc b
   in a,(c)                               ; read mmu4 register
   
   ld (var_restore_page),a

   ;; allocate an 8K page

   EXTERN __nextos_rc_banktype_zx
   EXTERN asm_esx_ide_bank_alloc
   EXTERN __Exit
   
   ld l,__nextos_rc_banktype_zx           ; mmu ram page (not divmmc)
   call asm_esx_ide_bank_alloc            ; carry flag indicates failure
   
   ld a,l                                 ; allocated page
   
   ld hl,str_error_out_of_memory          ; error string printed by basic
   jp c, __Exit                           ; exit if allocation failed

   ld (var_allocated_page),a              ; save page for freeing later
   mmu4 a                                 ; place page at address 0x8000 (z88dk nextreg shortcut)

   ;; decompress the data section into ram

   EXTERN __CODE_END_tail
   EXTERN __DATA_head, __DATA_END_tail
   EXTERN asm_dzx0_standard

   ld hl,__CODE_END_tail                  ; compressed data is appended to dot command
   ld de,__DATA_head                      ; decompress target address
   ld bc,__DATA_END_tail - __DATA_head    ; size of decompressed block

   ld a,b
   or c

   call nz, asm_dzx0_standard

   ;; zero the bss section
   
   EXTERN asm_memset
   EXTERN __BSS_head, __BSS_UNINITIALIZED_head

   ld hl,__BSS_head
   ld bc,__BSS_UNINITIALIZED_head - __BSS_head
         
   ld e,0
   call asm_memset                        ; memset deals with zero length case

   ;; fall through to main()


;; code in this section appears after:
;;   - main() returns
;;   - the exit stack has been run (functions registered with atexit)
;;   - the __Exit label (allocation failure above jumps to __Exit)
;; there must be no RET as code falls through to return to basic

SECTION code_crt_exit

   EXTERN __nextos_rc_banktype_zx         ; done above already but makes things clear
   EXTERN asm_esx_ide_bank_free

   ld a,(var_allocated_page)

   ld h,a
   ld l,__nextos_rc_banktype_zx
   
   or a
   call nz, asm_esx_ide_bank_free         ; free page but only if one was allocated

   ld a,(var_restore_page)
   mmu4 a                                 ; restore basic's memory page (z88dk nextreg shortcut)

   ;; fall through to return to basic


;; stuff in this section will be inside the dot command (the 8K)
;; not being in data / bss ensures it's available even if the allocation fails

SECTION code_user
PUBLIC _errno, _errbuf

var_allocated_page:   defb 0              ; zero indicates no allocated page

var_restore_page:     defb 4              ; basic's original page in mmu4

str_error_out_of_memory:
   defm "4 Out of Memor", 'y' + 0x80      ; basic strings end with msb set

_errno:               defw 0              ; insidious potential bug - create here so it is not created in bss_clib
                                          ; errors in called library functions will fill in errno

_errbuf:              defs 48             ; space to hold error string in divmmc memory when returning to basic
