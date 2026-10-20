	device zxspectrum48

;	DEFINE testing

	MACRO BREAK:dw $01DD:ENDM

	IFDEF testing
	org $6000
start
	ELSE
	org	$2000
start
	ENDIF

			ld a,h:or l:jr z,.skp
		
			ld bc,$303b:xor a:out (c),a
			ld de,$4000:ld hl,$ff00
			ld bc,$5b
.lp			out (c),e:inc e:jr nz,.lp:dec d:jr nz,.lp

.skp
			ld bc,$243b:ld a,21:out (c),a:inc b:ld a,3:out (c),a
			nextreg	21,3
			
			ld bc,$303b:xor a:out (c),a
			ld	hl,sprbuf:ld b,64:ld de,0
.l1			push bc:halt:ld a,r:ld c,a:ld a,(de):inc de:xor c:xor l:and 63:add a,24:ld (hl),a:inc hl:ld b,a
.l2			djnz .l2:ld a,r:ld c,a:ld a,(de):inc de:xor c:xor l:and 127:add a,24:ld (hl),a:inc hl:ld (hl),1:inc hl:pop bc:push bc:push af:ld a,b:and 15:add a,a:add a,a:add a,a:add a,a:inc a:ld (hl),a:pop af:inc hl:ld b,a
.l3			djnz .l3:ld a,r:and 7:sub 4:ld (hl),a:inc hl:ld b,a
.l4			djnz .l4:ld a,r:and 7:sub 4:ld (hl),a:inc hl:pop bc:djnz .l1

.lo			halt

			ld	bc,$303b:xor a:out (c),a
			ld	h,64:ld de,6:ld ix,sprbuf:ld bc,$57
.lz			ld	a,(ix+00):add a,(ix+04):ld (ix+00),a:cp 8:jr c,.s1:cp $94:jr c,.n1
.s1			ld	a,(ix+04):cpl:inc a:ld (ix+04),a
.n1			ld	a,(ix+01):add a,(ix+05):ld (ix+01),a:cp 8:jr c,.s2:cp $F8:jr c,.n2
.s2			ld	a,(ix+05):cpl:inc a:ld (ix+05),a
.n2			ld	a,(ix+00):add a,a:out (c),a:ld a,(ix+01):out (c),a:ld a,$00:adc a,0:out (c),a:ld a,128+64:sub h:out (c),a
			add ix,de:dec h:jr nz,.lz
			ld	a,127:in a,(254):rra:jp c,.lo
			nextreg 21,0
			xor a:ret

sprbuf

	IFDEF testing
	savesna "testspr.sna",start
	ELSE
.last
	savebin "TESTSPR",start,.last-start
	ENDIF
