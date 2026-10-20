
;; Simple implementation of Fletcher-16 checksum from wikipedia
;;
;; uint16_t fletcher16(uint16_t checksum, uint16_t size, void *buffer)
;; {
;;    uint16_t sum1;
;;    uint16_t sum2;
;;   
;;    int index;
;;   
;;    sum1 = checksum & 0xff;
;;    sum2 = checksum >> 8;
;;   
;;    for (index = 0; index < size; ++index)
;;    {
;;       sum1 = (sum1 + buffer[index]) % 255;
;;       sum2 = (sum2 + sum1) % 255;
;;    }
;;   
;;    return (sum2 << 8) | sum1;
;; }

SECTION code_user

PUBLIC _fletcher16, asm_fletcher16

_fletcher16:

   ; C entry point callee linkage r2l parameter order

   pop hl       ; return address
   pop de       ; de = current checksum
   pop bc       ; bc = size
   ex (sp),hl   ; hl = buffer

asm_fletcher16:

   ; asm entry point

loop:

   ; hl = unsigned char *buffer
   ; bc = length remaining
   ;  d = sum2 of checksum
   ;  e = sum1 of checksum

sum1:

   ld a,(hl)

mod_sum1:

   add a,e
   adc a,0
   
   cp 255
   jr nz, sum2
   
   xor a

sum2:

   ld e,a

mod_sum2:

   add a,d
   adc a,0

   cp 255
   jr nz, end_loop
   
   xor a

end_loop:

   ld d,a
   
   cpi                         ; hl++, bc--
   jp pe, loop

   ; return fletcher16 checksum in HL
   
   ex de,hl
   ret
