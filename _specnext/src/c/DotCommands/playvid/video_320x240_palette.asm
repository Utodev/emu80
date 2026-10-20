;;
;; VIDEO FORMAT
;;
;; 320 x 240 L2 palette per frame
;; 50/3 frame rate, 933 stereo samples ~15kHz sample rate
;;
;; frame size = 79360 bytes (155 sectors)
;;   ( 1866 bytes) 933 stereo samples (left then right) 
;;   (  182 bytes) padding
;;   (  512 bytes) frame palette
;;   (76800 bytes) 320x240 pixels (column major order)
;;
;; MEMORY MAP
;;
;; divmmc  0x0000 - 0x3fff : common area including stack
;; mmu2    0x4000 - 0x5fff : audio buffer
;; mmu3    0x6000 - 0x7fff : L2 window (set by player)
;; mmu4    0x8000 - 0x92ff : interrupts + common vars
;; mmu4-7  0x9300 - 0xffff : video player code & vars (27904 bytes)
;;
;; (memory map set before call)
;;

org 0x9300

INCLUDE "playvidp.dfc"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; PLAYER SPECIFIC DATA @ 0x9300
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_vc_text       :   defw text_about  ; text description
_vc_frame_sz   :   defb 155         ; frame size in sectors

_vc_l2_mode    :   defb 0x10        ; L2 mode

_vc_scroll_y   :   defb -8          ; vertical scroll amount for display
_vc_scroll_x   :   defw 0           ; horizontal scroll amount for display

_vc_clip       :   defb 0, 159, 8, 247  ; X1, X2, Y1, Y2

defs 0x10 - ASMPC

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; COMMON BLOCK @ 0x9310
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

INCLUDE "video_stream_jump_table.asm"

text_about:

   defm "320 x 240 L2 palette per frame\n"
   defm "16.7 fps, 15 kHz stereo audio\n"
   defm "vga 50 Hz is native format\n"
   defm "(60 Hz slower + audio approx)\n"
   defb 0

;;

MACRO INI_512_DE

LOCAL l1, l2

   REPT 512
      ini
   ENDR

      in a,(c)                  ; skip crc
      nop
      in a,(c)
      dec de                    ; remaining sector count

   l1:

      in a,(0xeb)
      inc a
      jr z, l1

      ;inc a                    ; token check removed
      ;ret nz                   ; token error

      ld a,d
      or e
   
      jp nz, l2

      ld a,iyh
      or iyl
   
      dec iy
   
      call z, next_file_fragment

   l2:

ENDM


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; JUMP TABLE ENTRY POINTS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; a = error code = 0 if successful, 0-30 if key pressed, 255 if stream error
; external variable _v_frame_count = 0 if completed


video_init_60:

   ; hl = address of audio buffer

   ld a,4
   ld (smc_frame_count_0),a    ; change frame rate from 50/3 to 60/4
   ld (smc_frame_count_1),a
   
   call isr_install_60

video_init:

   ld hl,0x474a                ; second half of audio buffer
   ld (_w_audio_buffer),hl     ; audio write address
   
   ld a,10
   ld (_w_layer2_page_count),a
   
   ld de,(_v_fragment_remaining)
   ld iy,(_v_fragment_remaining + 2)
   
   ; sectors are counted by decrement of lsw before zero check
   
   ld a,d
   or e
   ret nz
   
   dec iy
   ret


play_vga_50_silent:
play_hdmi_50_silent:

   push ix
   push iy

   call video_init

   ; de = LSW of sector count
   ; iy = MSW of sector count

   halt
   call video_play             ; must be a call!

   pop iy
   pop ix
   
   ld l,a
   ret


play_vga_60_silent:
play_hdmi_60_silent:

   push ix
   push iy

   call video_init_60

   ; de = LSW of sector count
   ; iy = MSW of sector count

   halt
   call video_play             ; must be a call!

   pop iy
   pop ix
   
   ld l,a
   ret


play_vga_50_mono:
play_vga_50_stereo:

   push ix
   push iy

   ; ctc interrupt audio pointers
   
   ld hl,0x4000                ; hl' = audio source address
   ld de,0x4e93                ; de' = last byte of audio buffer (933 stereo samples * 2)
   ld c,l
   ld b,h                      ; bc' = start of audio buffer
   
   exx
   
   call video_init             ; clear audio buffer

   ; de = LSW of sector count
   ; iy = MSW of sector count

   ; enable audio interrupt on ctc channel 2
   
   ld bc,0x1a3b                ; i/o address ctc channel 2
   ld a,0x03
   out (c),a
   out (c),a                   ; reset ctc channel

   ld a,0x85
   out (c),a                   ; int en, timer, /16, time const follows

   halt

   ld a,114
   out (c),a                   ; freq = 28 MHz / 16 / 114 = 15.351 kHz

   call video_play
   
   push af                     ; save error
   
   ; disable audio interrupt
   
   ld bc,0x1a3b                ; i/o address ctc channel 2
   ld a,3
   out (c),a
   out (c),a                   ; reset ctc channel

   pop af                      ; a = error
   
   pop iy
   pop ix
   
   ld l,a
   ret


play_vga_60_mono:
play_vga_60_stereo:

   push ix
   push iy

   ; ctc interrupt audio pointers
   
   ld hl,0x4000                ; hl' = audio source address
   ld de,0x4eb2                ; de' = one byte past end of audio buffer (912 stereo samples * 2 * fraction)
   ld bc,0x0042                ;  c  = 1.2 (2.6 fixed point)
   
   exx
   
   ld hl,0x4000                ; address of audio buffer
   call video_init_60          ; clear audio buffer

   ; de = LSW of sector count
   ; iy = MSW of sector count

   ; enable audio interrupt on ctc channel 2
   
   ld bc,0x1a3b                ; i/o address ctc channel 2
   ld a,0x03
   out (c),a
   out (c),a                   ; reset ctc channel

   ld a,0x85
   out (c),a                   ; int en, timer, /16, time const follows

   halt

   ld a,132
   out (c),a                   ; freq = 28 MHz / 16 / 132

   call video_play
   
   push af                     ; save error
   
   ; disable audio interrupt
   
   ld bc,0x1a3b                ; i/o address ctc channel 2
   ld a,3
   out (c),a
   out (c),a                   ; reset ctc channel

   pop af                      ; a = error
   
   pop iy
   pop ix
   
   ld l,a
   ret


play_hdmi_50_mono:
play_hdmi_50_stereo:

   push ix
   push iy

   ; ctc interrupt audio pointers
   
   ld hl,0x4000                ; hl' = audio source address
   ld de,0x4e9f                ; de' = last byte of audio buffer (936 stereo samples * 2)
   ld c,l
   ld b,h                      ; bc' = start of audio buffer
   
   exx
   
   call video_init             ; clear audio buffer

   ; de = LSW of sector count
   ; iy = MSW of sector count

   ; enable audio interrupt on ctc channel 2
   
   ld bc,0x1a3b                ; i/o address ctc channel 2
   ld a,0x03
   out (c),a
   out (c),a                   ; reset ctc channel

   ld a,0x85
   out (c),a                   ; int en, timer, /16, time const follows

   halt

   ld a,108
   out (c),a                   ; freq = 27 MHz / 16 / 108 = 15.625 kHz

   call video_play
   
   push af                     ; save error
   
   ; disable audio interrupt
   
   ld bc,0x1a3b                ; i/o address ctc channel 2
   ld a,3
   out (c),a
   out (c),a                   ; reset ctc channel

   pop af                      ; a = error
   
   pop iy
   pop ix
   
   ld l,a
   ret


play_hdmi_60_mono:
play_hdmi_60_stereo:

   push ix
   push iy

   ; ctc interrupt audio pointers
   
   ld hl,0x4000                ; hl' = audio source address
   ld de,0x4ea8                ; de' = one byte past end of audio buffer (858 stereo samples * 2 * fraction)
   ld bc,0x0046                ;  c  = 1.6 (2.6 fixed point)
   
   exx
   
   ld hl,0x4000                ; address of audio buffer
   call video_init_60          ; clear audio buffer

   ; de = LSW of sector count
   ; iy = MSW of sector count

   ; enable audio interrupt on ctc channel 2
   
   ld bc,0x1a3b                ; i/o address ctc channel 2
   ld a,0x03
   out (c),a
   out (c),a                   ; reset ctc channel

   ld a,0x85
   out (c),a                   ; int en, timer, /16, time const follows

   halt

   ld a,131
   out (c),a                   ; freq = 28 MHz / 16 / 131

   call video_play
   
   push af                     ; save error
   
   ; disable audio interrupt
   
   ld bc,0x1a3b                ; i/o address ctc channel 2
   ld a,3
   out (c),a
   out (c),a                   ; reset ctc channel

   pop af                      ; a = error
   
   pop iy
   pop ix
   
   ld l,a
   ret


;; DMA PROGRAM FOR FUTURE REFERENCE
;
;   ld hl,dma_prog
;   ld bc,+((dma_prog_end - dma_prog) * 256) + 0x6b
;   otir
;   
;   halt
;   
;   ld a,0x87                   ; ENABLE
;   out (0x6b),a
;
;   call video_play
;   
;   push af                     ; save error
;   
;   ; disable dma
;   
;   ld a,0x83                   ; DISABLE
;   out (0x6b),a
;   
;   ld a,0xc3                   ; RESET
;   out (0x6b),a
;
;   pop af                      ; a = error
;   ret
; 
;dma_prog:
;
;   defb 0x83                   ; DISABLE
;   defb 0xc3                   ; RESET
;
;   defb 0x7d                   ; WR0  A->B transfer
;      defb 0x00
;      defb 0x40                ; A start address
;      defb 0x94
;      defb 0x0e                ; transfer length
;      
;   defb 0x54                   ; WR1  A is auto-increment memory
;      defb 0x02                ; cycle time = 2
;   
;   defb 0x68                   ; WR2  B is fixed i/o
;      defb 0x22                ; cycle time = 2
;      defb 28                  ;;; does not work with current dma implementation <= 3.01.10
;   
;   defb 0xc5                   ; WR4  burst mode
;      defb 0xdf                ; mono dac
;   
;   defb 0xa2                   ; WR5  restart at end
;   
;   defb 0xcf                   ; LOAD
;   
;dma_prog_end:


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; VIDEO PLAYER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

video_play:

   ; de = LSW of sector count
   ; iy = MSW of sector count

   xor a
   ld (_vbi_counter),a
   
   ld c,0xeb

video_loop:

   ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
   ; exit early on keypress
   ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
   
   xor a
   in a,(0xfe)
   
   and $1f
   cp $1f
   
   ret nz

   ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
   ; stereo audio (2048 bytes)
   ; 933 stereo samples + padding
   ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
   
   ;  c = 0xeb
   ; de = LSW of sector count
   ; iy = MSW of sector count
   
   ; 1866 bytes of samples
   
   ld hl,(_w_audio_buffer)

REPT 3
   INI_512_DE
ENDR

   ; 1866 - 1536 = 330 bytes to go
   
REPT 330
   ini
ENDR

   ld a,l
   
   cp 0x94                     ; hl = 0x4e94 (end of audio buffer) ?
   jp nz, audio_ptr
   
   ld hl,0x4000

audio_ptr:

   ; pad to 2048 bytes for sector alignment
   ; skip 2048 - 1866 = 182 bytes

   in a,(c)
   ld (_w_audio_buffer),hl

REPT 181
   in a,(c)
   nop
ENDR

   in a,(c)                    ; skip crc
   nop
   in a,(c)
   dec de                      ; remaining sector count

token_ap:

   in a,(0xeb)
   inc a
   jr z, token_ap

   ;inc a                      ; token check removed
   ;ret nz                     ; token error

   ld a,d
   or e
   
   jp nz, join_ap

   ld a,iyh
   or iyl
   
   dec iy
   
   call z, next_file_fragment

join_ap:

   ;;;;;;;;;;;;;;;;;;;;;;;;;;;;
   ; palette (512 bytes)
   ;;;;;;;;;;;;;;;;;;;;;;;;;;;;

   ;  c = 0xeb
   ; de = LSW of sector count
   ; iy = MSW of sector count

REPT 512
   in a,(0xeb)
   nextreg 0x44,a              ; 9-bit palette value
ENDR
 
   in a,(c)
   nop
   in a,(c)
   dec de                      ; remaining sector count
 
token_p:
 
   in a,(0xeb)
   inc a
   jr z, token_p

   ;inc a                      ; token check removed
   ;ret nz                     ; token error

   ld a,d
   or e
   
   jp nz, join_p

   ld a,iyh
   or iyl
   
   dec iy
   
   call z, next_file_fragment

join_p:

   ;;;;;;;;;;;;;;;;;;;;;;;;;;;;
   ; video (76800 bytes)
   ;;;;;;;;;;;;;;;;;;;;;;;;;;;;

   ;  c = 0xeb
   ; de = LSW of sector count
   ; iy = MSW of sector count

   ; layer 2 - 320 x 240

   ld ix,(_w_layer2_page_count)  ; ixh = dst layer 2 page, ixl = 10 (10 * 8K = 80K for L2)

loop_8k:

   ld a,ixh
   inc ixh
   
   mmu3 a
   
   ld hl,0x6000                ; write address for L2 page

   ; this is annoying because only 240 bytes are read per vertical column and
   ; the sd card needs to be read 512 bytes at a time so there are fifteen cases
   ; within each 8K block read
   
	case_0:

         xor a

	REPT 240
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 240
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 32
	   ini
	ENDR
	
	   in a,(c)
	   nop
	   in a,(c)
	   dec de
	   
	token_0:
	
	   in a,(0xeb)
	   inc a
	   jr z, token_0

         ;inc a                ; token check removed
         ;ret nz               ; token error

         ld a,d
         or e
  
         jp nz, case_1

         ld a,iyh
         or iyl
   
         dec iy
   
         call z, next_file_fragment
         
	case_1:
	
	   xor a
	   
	REPT 208
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 240
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 64
	   ini
	ENDR
	
	   in a,(c)
	   nop
	   in a,(c)
	   dec de
	
	token_1:
	
	   in a,(0xeb)
	   inc a
	   jr z, token_1

         ;inc a                ; token check removed
         ;ret nz               ; token error

         ld a,d
         or e
  
         jp nz, case_2

         ld a,iyh
         or iyl
   
         dec iy
   
         call z, next_file_fragment

	case_2:

         xor a

	REPT 176
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 240
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 96
	   ini
	ENDR
	
	   in a,(c)
	   nop
	   in a,(c)
	   dec de
	
	token_2:
	
	   in a,(0xeb)
	   inc a
	   jr z, token_2

         ;inc a                ; token check removed
         ;ret nz               ; token error

         ld a,d
         or e
  
         jp nz, case_3

         ld a,iyh
         or iyl
   
         dec iy
   
         call z, next_file_fragment

	case_3:

         xor a

	REPT 144
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 240
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 128
	   ini
	ENDR
	
	   in a,(c)
	   nop
	   in a,(c)
	   dec de
	
	token_3:
	
	   in a,(0xeb)
	   inc a
	   jr z, token_3

         ;inc a                ; token check removed
         ;ret nz               ; token error

         ld a,d
         or e
  
         jp nz, case_4

         ld a,iyh
         or iyl
   
         dec iy
   
         call z, next_file_fragment

	case_4:
	
	   xor a
	
	REPT 112
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 240
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 160
	   ini
	ENDR
	
	   in a,(c)
	   nop
	   in a,(c)
	   dec de
	
	token_4:
	
	   in a,(0xeb)
	   inc a
	   jr z, token_4

         ;inc a                ; token check removed
         ;ret nz               ; token error

         ld a,d
         or e
  
         jp nz, case_5

         ld a,iyh
         or iyl
   
         dec iy
   
         call z, next_file_fragment

	case_5:

         xor a

	REPT 80
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 240
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 192
	   ini
	ENDR
	
	   in a,(c)
	   nop
	   in a,(c)
	   dec de
	
	token_5:
	
	   in a,(0xeb)
	   inc a
	   jr z, token_5

         ;inc a                ; token check removed
         ;ret nz               ; token error

         ld a,d
         or e
  
         jp nz, case_6

         ld a,iyh
         or iyl
   
         dec iy
   
         call z, next_file_fragment

	case_6:

         xor a

	REPT 48
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 240
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 224
	   ini
	ENDR
	
	   in a,(c)
	   nop
	   in a,(c)
	   dec de
	
	token_6:
	
	   in a,(0xeb)
	   inc a
	   jr z, token_6

         ;inc a                ; token check removed
         ;ret nz               ; token error

         ld a,d
         or e
  
         jp nz, case_7

         ld a,iyh
         or iyl
   
         dec iy
   
         call z, next_file_fragment

	case_7:

         xor a

	REPT 16
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 240
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 240
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 16
	   ini
	ENDR
	
	   in a,(c)
	   nop
	   in a,(c)
	   dec de
	
	token_7:
	
	   in a,(0xeb)
	   inc a
	   jr z, token_7

         ;inc a                ; token check removed
         ;ret nz               ; token error

         ld a,d
         or e
  
         jp nz, case_8

         ld a,iyh
         or iyl
   
         dec iy
   
         call z, next_file_fragment
         
	case_8:

         xor a

	REPT 224
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 240
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 48
	   ini
	ENDR
	
	   in a,(c)
	   nop
	   in a,(c)
	   dec de
	
	token_8:
	
	   in a,(0xeb)
	   inc a
	   jr z, token_8

         ;inc a                ; token check removed
         ;ret nz               ; token error

         ld a,d
         or e
  
         jp nz, case_9

         ld a,iyh
         or iyl
   
         dec iy
   
         call z, next_file_fragment

	case_9:

         xor a

	REPT 192
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 240
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 80
	   ini
	ENDR
	
	   in a,(c)
	   nop
	   in a,(c)
	   dec de
	
	token_9:
	
	   in a,(0xeb)
	   inc a
	   jr z, token_9

         ;inc a                ; token check removed
         ;ret nz               ; token error

         ld a,d
         or e
  
         jp nz, case_10

         ld a,iyh
         or iyl
   
         dec iy
   
         call z, next_file_fragment

	case_10:

         xor a

	REPT 160
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 240
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 112
	   ini
	ENDR
	
	   in a,(c)
	   nop
	   in a,(c)
	   dec de
	
	token_10:
	
	   in a,(0xeb)
	   inc a
	   jr z, token_10

         ;inc a                ; token check removed
         ;ret nz               ; token error

         ld a,d
         or e
  
         jp nz, case_11
         
         ld a,iyh
         or iyl
   
         dec iy
   
         call z, next_file_fragment

	case_11:

         xor a

	REPT 128
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 240
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 144
	   ini
	ENDR
	
	   in a,(c)
	   nop
	   in a,(c)
	   dec de
	
	token_11:
	
	   in a,(0xeb)
	   inc a
	   jr z, token_11

         ;inc a                ; token check removed
         ;ret nz               ; token error

         ld a,d
         or e
  
         jp nz, case_12

         ld a,iyh
         or iyl
   
         dec iy
   
         call z, next_file_fragment

	case_12:

         xor a

	REPT 96
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 240
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 176
	   ini
	ENDR
	
	   in a,(c)
	   nop
	   in a,(c)
	   dec de
	
	token_12:
	
	   in a,(0xeb)
	   inc a
	   jr z, token_12

         ;inc a                ; token check removed
         ;ret nz               ; token error

         ld a,d
         or e
  
         jp nz, case_13

         ld a,iyh
         or iyl
   
         dec iy
   
         call z, next_file_fragment

	case_13:

         xor a

	REPT 64
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 240
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 208
	   ini
	ENDR
	
	   in a,(c)
	   nop
	   in a,(c)
	   dec de
	
	token_13:
	
	   in a,(0xeb)
	   inc a
	   jr z, token_13

         ;inc a                ; token check removed
         ;ret nz               ; token error

         ld a,d
         or e
  
         jp nz, case_14

         ld a,iyh
         or iyl
   
         dec iy
   
         call z, next_file_fragment

	case_14:

         xor a

	REPT 32
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 240
	   ini
	ENDR
	   ld l,a
	   inc h
	REPT 240
	   ini
	ENDR
	   ld l,a
	   inc h
	
	   in a,(c)
	   nop
	   in a,(c)
	   dec de
	
	token_14:
	
	   in a,(0xeb)
	   inc a
	   jr z, token_14

         ;inc a                ; token check removed
         ;ret nz               ; token error

         ld a,d
         or e
  
         jp nz, case_15

         ld a,iyh
         or iyl
   
         dec iy
   
         call z, next_file_fragment
         
	case_15:
	
   ; loop 8k

   dec ixl
   jp nz, loop_8k

   ;;;;;;;;;;;;;;;;;;;;;;;;;;;;
   ; frame
   ;;;;;;;;;;;;;;;;;;;;;;;;;;;;

   ;  c = 0xeb
   ; de = LSW of sector count
   ; iy = MSW of sector count

   ; wait for three 50 Hz frames
   
frame_wait:

   ld a,(_vbi_counter)

defc smc_frame_count_0 = $ + 1

   cp 3
   jr c, frame_wait
   
   xor a
   ld (_vbi_counter),a

   ld hl,(_w_layer2_page)      ; l = L2 page, h = L2 palette

   ; change active layer 2 page
   
   ld a,l
   rra
   
   nextreg 0x12,a
   
   add a,a
   xor 0x10
   
   ld l,a
   
   ; change active layer 2 palette

   ld a,h
   xor 0x44
   ld h,a
    
   nextreg 0x43,a              ; palette control

   ld (_w_layer2_page),hl      ; L2 page and palette must be sequential in memory

   ; repeat for number of frames
   ; frame count is negative and counting up to zero

   ld hl,(_v_frame_count)
   inc hl
   ld (_v_frame_count),hl
   
   ld a,h
   or l
   
   jp nz, video_loop
   
   ld hl,(_v_frame_count + 2)
   inc hl
   ld (_v_frame_count + 2),hl
   
   ld a,h
   or l
   
   jp nz, video_loop

   ;;;;;;;;;;;;;;;;;;;;;;;;;;;;
   ; frame sequence done
   ;;;;;;;;;;;;;;;;;;;;;;;;;;;;

   ; complete audio
   
   ; clear a few bytes in the audio back buffer
   ; because we are not being careful about cycles
   
   ld hl,(_w_audio_buffer)
   ld e,l
   ld d,h
   inc de
   ld (hl),0x80
   ld bc,16
   ldir

   ; wait for last frame to finish its time
   
video_done:

   ld a,(_vbi_counter)

defc smc_frame_count_1 = $ + 1

   cp 3
   jr c, video_done

   xor a                       ; indicate success
   ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; move sd card pointer to next file fragment
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

next_file_fragment:

   ; enter :  hl = must preserve
   ;          ix = must preserve
   ;
   ; exit  :   c = 0xeb
   ;          de = LSW of sector count
   ;          iy = MSW of sector count

INCLUDE "video_stream_postamble.asm"


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; pad to end of memory
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

defs 0x10000 - 0x9300 - ASMPC
