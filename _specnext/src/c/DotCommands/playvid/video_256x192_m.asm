;;
;; VIDEO FORMAT
;;
;; 256 x 192 L2 fixed palette
;; 50/2 frame rate, 933 mono samples ~23kHz sample rate
;;
;; frame size = 50176 bytes (98 sectors)
;;   (  933 bytes) 933 mono samples 
;;   (   91 bytes) padding
;;   (49152 bytes) 256x192 pixels (row major order)
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
_vc_frame_sz   :   defb 98          ; frame size in sectors

_vc_l2_mode    :   defb 0           ; L2 mode

_vc_scroll_y   :   defb 0           ; vertical scroll amount for display
_vc_scroll_x   :   defw 0           ; horizontal scroll amount for display

_vc_clip       :   defb 0, 255, 0, 191  ; X1, X2, Y1, Y2

defs 0x10 - ASMPC

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; COMMON BLOCK @ 0x9310
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

INCLUDE "video_stream_jump_table.asm"

text_about:

   defm "256 x 192 L2 fixed palette\n"
   defm "25 fps, 23 kHz mono audio\n"
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

   ld a,3
   ld (smc_frame_count_0),a    ; change frame rate from 50/2 to 60/3
   ld (smc_frame_count_1),a

   call isr_install_60

video_init:

   ld hl,0x43a5                ; second half of audio buffer
   ld (_w_audio_buffer),hl     ; audio write address
   
   ld a,6
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
   ld de,0x4749                ; de' = last byte of audio buffer (933 mono samples * 2)
   ld c,l
   ld b,h                      ; bc' = start of audio buffer
   
   exx
   
   call video_init
   
   ; de = LSW of sector count
   ; iy = MSW of sector count
   
   ; enable audio interrupt on ctc channel 1
   
   ld bc,0x193b                ; i/o address ctc channel 1
   ld a,0x03
   out (c),a
   out (c),a                   ; reset ctc channel

   ld a,0x85
   out (c),a                   ; int en, timer, /16, time const follows

   halt

   ld a,76
   out (c),a                   ; freq = 28 MHz / 16 / 76 = 23.026 kHz

   call video_play
   
   push af                     ; save error
   
   ; disable audio interrupt
   
   ld bc,0x193b                ; i/o address ctc channel 1
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
   ld de,0x4759                ; de' = one byte past end of audio buffer (912 mono samples * 2 * fraction)
   ld bc,0x0042                ;  c  = 1.2 (2.6 fixed point)
   
   exx

   ld hl,0x4000                ; address of audio buffer
   call video_init_60
   
   ; de = LSW of sector count
   ; iy = MSW of sector count
   
   ; enable audio interrupt on ctc channel 1
   
   ld bc,0x193b                ; i/o address ctc channel 1
   ld a,0x03
   out (c),a
   out (c),a                   ; reset ctc channel

   ld a,0x85
   out (c),a                   ; int en, timer, /16, time const follows

   halt

   ld a,99
   out (c),a                   ; freq = 28 MHz / 16 / 99

   call video_play
   
   push af                     ; save error
   
   ; disable audio interrupt
   
   ld bc,0x193b                ; i/o address ctc channel 1
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
   ld de,0x474f                ; de' = last byte of audio buffer (936 mono samples * 2)
   ld c,l
   ld b,h                      ; bc' = start of audio buffer
   
   exx
   
   call video_init
   
   ; de = LSW of sector count
   ; iy = MSW of sector count
   
   ; enable audio interrupt on ctc channel 1
   
   ld bc,0x193b                ; i/o address ctc channel 1
   ld a,0x03
   out (c),a
   out (c),a                   ; reset ctc channel

   ld a,0x85
   out (c),a                   ; int en, timer, /16, time const follows

   halt

   ld a,72
   out (c),a                   ; freq = 27 MHz / 16 / 72

   call video_play
   
   push af                     ; save error
   
   ; disable audio interrupt
   
   ld bc,0x193b                ; i/o address ctc channel 1
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
   ld de,0x4761                ; de' = one byte past end of audio buffer (1703 mono samples * fraction)
   ld bc,0x0047                ;  c  = 1.7 (2.6 fixed point)
   
   exx

   ld hl,0x4000                ; address of audio buffer
   call video_init_60
   
   ; de = LSW of sector count
   ; iy = MSW of sector count
   
   ; enable audio interrupt on ctc channel 1
   
   ld bc,0x193b                ; i/o address ctc channel 1
   ld a,0x03
   out (c),a
   out (c),a                   ; reset ctc channel

   ld a,0x85
   out (c),a                   ; int en, timer, /16, time const follows

   halt

   ld a,99
   out (c),a                   ; freq = 28 MHz / 16 / 99

   call video_play
   
   push af                     ; save error
   
   ; disable audio interrupt
   
   ld bc,0x193b                ; i/o address ctc channel 1
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
;      defb 0x4a
;      defb 0x07                ; transfer length
;      
;   defb 0x54                   ; WR1  A is auto-increment memory
;      defb 0x02                ; cycle time = 2
;   
;   defb 0x68                   ; WR2  B is fixed i/o
;      defb 0x22                ; cycle time = 2
;      defb 38                   ;;; does not work with current dma implementation <= 3.01.10
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
   ; mono audio (1024 bytes)
   ; 933 mono samples samples + padding
   ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
   
   ;  c = 0xeb
   ; de = LSW of sector count
   ; iy = MSW of sector count

   ld hl,(_w_audio_buffer)

   INI_512_DE

   ; 933 - 512 = 421 bytes to go
   
REPT 421
   ini
ENDR

   ld a,l
   
   cp 0x4a                     ; hl = 0x474a (end of audio buffer) ?
   jp nz, audio_ptr
   
   ld hl,0x4000

audio_ptr:

   ; pad to 1024 bytes for sector alignment
   ; skip 1024 - 933 = 91 bytes

   in a,(c)
   ld (_w_audio_buffer),hl

REPT 90
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
   ; video (49152 bytes)
   ;;;;;;;;;;;;;;;;;;;;;;;;;;;;

   ;  c = 0xeb
   ; de = LSW of sector count
   ; iy = MSW of sector count

   ; layer 2 - 256 x 192

   ld ix,(_w_layer2_page_count)  ; ixh = dst layer 2 page, ixl = 6 (6 * 8K = 48K for L2)

loop_8k:

   ld a,ixh
   inc ixh
   
   mmu3 a
   
   ld hl,0x6000                ; write address for L2 page

   ; 8K = 256 x 32 = 512 x 16

REPT 16
   INI_512_DE
ENDR

   ; loop 8k

   dec ixl
   jp nz, loop_8k

   ;;;;;;;;;;;;;;;;;;;;;;;;;;;;
   ; frame
   ;;;;;;;;;;;;;;;;;;;;;;;;;;;;

   ;  c = 0xeb
   ; de = LSW of sector count
   ; iy = MSW of sector count

   ; wait for two 50 Hz frames
   
frame_wait:

   ld a,(_vbi_counter)

defc smc_frame_count_0 = $ + 1

   cp 2
   jr c, frame_wait
   
   xor a
   ld (_vbi_counter),a

   ; change active layer 2 page
   
   ld a,(_w_layer2_page)
   rra
   
   nextreg 0x12,a
   
   add a,a
   xor 0x10
   
   ld (_w_layer2_page),a

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

   cp 2
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
