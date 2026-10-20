SECTION code_user

PUBLIC _extract_get_mmu

_extract_get_mmu:

   ; When loading pages, a particular page must be brought
   ; into a specific mmu slot.  However that mmu slot must
   ; not be occupied by the stack.  This subroutine chooses
   ; a suitable mmu slot to do this paging.
   
   ; exit : hl = mmu slot to use
   ;
   ; used : af, hl
   
   ld hl,0xa000

   xor a
   sbc hl,sp
   
   ld l,7
   ld h,a
   
   ret nc
   
   ld l,4
   ret

PUBLIC _page_present

EXTERN error_znc, error_onc
EXTERN asm_zxn_page_from_addr
EXTERN _mmu_reg, _mmu_addr

_page_present:

   ; extern unsigned char page_present(unsigned long address)
   
   ; enter : dehl = unsigned long address
   ; exit  : l = 0 for fail
   
   ; check if page is present and page into memory

   call asm_zxn_page_from_addr   ; l = page number
   jp c, error_znc               ; memory address out of range
   
   ld a,l
   
   cp 224
   jp nc, error_znc              ; memory page out of range
   
   ld bc,$243b
   
   ld a,(_mmu_reg)
   out (c),a
   
   inc b
   out (c),l                     ; map destination page to memory
   
   ld hl,(_mmu_addr)

   ld c,(hl)
   
   ld (hl),0x55
   
   ld a,(hl)
   ld (hl),0xaa
   
   cpl
   cp (hl)
   
   ld (hl),c
   
   jp nz, error_znc
   jp error_onc
