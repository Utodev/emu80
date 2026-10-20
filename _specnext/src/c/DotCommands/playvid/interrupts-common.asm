;;
;; ISR & VECTOR TABLE @ 0x8000
;; COMMON AREAS FOLLOW ENDING IN 256 BYTE STACK @ 0X9200
;;

SECTION code_crt_init

EXTERN _state_register_i

   ld a,i
   ld (_state_register_i),a
   
   ld a,vectors/256
   ld i,a

SECTION code_crt_exit

   ld a,(_state_register_i)
   ld i,a

SECTION INTERRUPT

vectors:

   defw isr_error
   defw isr_error
   defw isr_error
   defw isr_error

isr_mono:

   defw isr_ctc_mono           ; ctc channel 1

isr_stereo:

   defw isr_ctc_stereo         ; ctc channel 2
   defw isr_error
   defw isr_error

   defw isr_error
   defw isr_error
   defw isr_error
   defw isr_ula                ; ula

   defw isr_error
   defw isr_error
   defw isr_error
   defw isr_error

;;
;; change audio isrs for 60 Hz versions
;;

PUBLIC isr_install_60

isr_install_60:

   ; hl = address of audio buffer

   ld (isr_audio_buffer),hl

   ld hl,isr_ctc_mono_60
   ld (isr_mono),hl
   
   ld hl,isr_ctc_stereo_60
   ld (isr_stereo),hl
   
   ret

isr_audio_buffer:  defw 0

;;
;; catch unintended interrupts if there are any
;;

isr_error:

   push af
   
   ld a,4
   out (0xfe),a
   
   pop af
   
   ei
   reti

;;
;; count time passed in frames (video player)
;;

isr_ula:

   push af
   
   ld a,(_vbi_counter)

   inc a
   jr z, no_count

   ld (_vbi_counter),a

no_count:

   pop af
   
   ei
   reti

;;
;; digital mono audio using ctc
;; exx set is allocated to this isr
;;

isr_ctc_mono:

   exx
   ex af,af'
   
   ; hl = audio src address
   ; bc = audio buffer address
   ; de = last byte of audio buffer
   
   ld a,(hl)
   out (0xdf),a                ; mono dac

   ; check if at end of audio buffer
   
   ld a,l
   
   cp e
   jr z, mono_isr_msb
   
   inc hl
   
   ex af,af'
   exx
   
   ei
   reti

mono_isr_msb:

   ld a,h

   cp d
   jr z, mono_isr_loop
   
   inc hl
   
   ex af,af'
   exx
   
   ei
   reti

mono_isr_loop:

   ld l,c
   ld h,b
   
   ex af,af'
   exx
   
   ei
   reti

;;
;; digital mono audio using ctc for 60Hz playback
;; 60Hz playback requires fractional movement of audio pointer
;; exx set is allocated to this isr
;;

isr_ctc_mono_60:

   exx
   ex af,af'
   
   ; hl = audio src address
   ;  b = 2.6 fractional update of src address
   ;  c = 2.6 increment to accumulated fractional update pointer
   ; de = one byte past end of audio buffer
   ; (isr_audio_buffer) = audio buffer address
   
   ld a,(hl)
   out (0xdf),a                ; mono dac
   
   ; update address pointer by fraction
   ; additions must land on de
   
   ld a,c
   add a,b
   ld b,a
   
   rlca
   rlca
   and $03
   add hl,a
   
   ; check if at end of audio buffer
   
   ld a,l
   
   cp e
   jr z, mono_60_isr_msb
   
   ld a,b
   and $3f
   ld b,a

   ex af,af'
   exx
   
   ei
   reti

mono_60_isr_msb:

   ld a,h

   cp d
   jr z, mono_60_isr_loop
   
   ld a,b
   and $3f
   ld b,a
   
   ex af,af'
   exx
   
   ei
   reti

mono_60_isr_loop:

   ld hl,(isr_audio_buffer)
   ld b,0
   
   ex af,af'
   exx
   
   ei
   reti

;;
;; digital stereo audio using ctc
;; exx set is allocated to this isr
;;

isr_ctc_stereo:

   exx
   ex af,af'
   
   ; hl = audio src address
   ; bc = audio buffer address
   ; de = last byte of audio buffer
   
   ld a,(hl)
   inc l                       ; to odd address
   
   out (0xf3),a                ; left dac B
   
   ld a,(hl)
   
   out (0xf9),a                ; right dac C
   
   ; check if at end of audio buffer
   
   ld a,l
   
   cp e
   jr z, stereo_isr_msb
   
   inc hl
   
   ex af,af'
   exx
   
   ei
   reti

stereo_isr_msb:

   ld a,h

   cp d
   jr z, stereo_isr_loop
   
   inc hl
   
   ex af,af'
   exx
   
   ei
   reti

stereo_isr_loop:

   ld l,c
   ld h,b
   
   ex af,af'
   exx
   
   ei
   reti

;;
;; digital stereo audio using ctc for 60Hz playback
;; 60Hz playback requires fractional movement of audio pointer
;; exx set is allocated to this isr
;;

isr_ctc_stereo_60:

   exx
   ex af,af'
   
   ; hl = audio src address
   ;  b = 2.6 fractional update of src address
   ;  c = 2.6 increment to accumulated fractional update pointer
   ; de = one byte past end of audio buffer
   ; (isr_audio_buffer) = audio buffer address

   ld a,(hl)
   inc l                       ; to odd address
   
   out (0xf3),a                ; left dac B
   
   ld a,(hl)
   dec l                       ; back to initial address
   
   out (0xf9),a                ; right dac C

   ; update address pointer by fraction
   ; additions must land on de
   
   ld a,c
   add a,b
   ld b,a
   
   rlca
   rlca
   rlca
   and $06
   add hl,a
   
   ; check if at end of audio buffer
   
   ld a,l
   
   cp e
   jr z, stereo_60_isr_msb
   
   ld a,b
   and $3f
   ld b,a

   ex af,af'
   exx
   
   ei
   reti

stereo_60_isr_msb:

   ld a,h

   cp d
   jr z, stereo_60_isr_loop
   
   ld a,b
   and $3f
   ld b,a
   
   ex af,af'
   exx
   
   ei
   reti

stereo_60_isr_loop:

   ld hl,(isr_audio_buffer)
   ld b,0
   
   ex af,af'
   exx
   
   ei
   reti

;;
;; COMMON VARIABLES SHARED WITH VIDEO PLAYER
;;

SECTION COMMON

;;;;;;;;;
; video.h
;;;;;;;;;

PUBLIC _vbi_counter

_vbi_counter            :   defb 0    ; count 50 / 60 Hz frames

PUBLIC _video_player_vars
PUBLIC _w_layer2_page_count
PUBLIC _w_layer2_page
PUBLIC _w_layer2_palette
PUBLIC _w_audio_buffer

defc _video_player_vars = ASMPC

_w_layer2_page_count    :   defb 0    ; number of pages in L2 screen (local)  \  must be
_w_layer2_page          :   defb 0    ; destination L2 page                   |  sequential
_w_layer2_palette       :   defb 0    ; destination palette                   /  in memory
_w_audio_buffer         :   defw 0    ; destination audio buffer address (local)

PUBLIC _v_fragment_remaining
PUBLIC _v_file_fragment
PUBLIC _v_frame_count
PUBLIC _v_sector_start

_v_fragment_remaining   :   defw 0,0  ; sectors remaining in current file fragment (32-bit)
_v_file_fragment        :   defw 0    ; pointer to next file fragment (16-bit)
_v_frame_count          :   defw 0,0  ; number of video frames to play (32-bit)
_v_sector_start         :   defw 0,0  ; starting position of playback

; video player data stored in video player code
; *** must be consistent with video_stream player code

PUBLIC _video_player_info
PUBLIC _video_player_jump_table

defc _video_player_info = 0x9300
defc _video_player_jump_table = 0x9310

;;
;; VARS SPILL AT END OF AVAILABLE MEMORY
;;

SECTION VARS2

;;;;;;;;;;;;;;
; sd.c, main.c
;;;;;;;;;;;;;;

PUBLIC _state_l2_palette

_state_l2_palette       :   defs 1024 ; saved L2 palette unsigned char [1024]

PUBLIC _filemap
PUBLIC _entry

_filemap                :   defs 3    ; struct esx_filemap
_entry                  :   defs 6    ; struct esx_filemap_entry

PUBLIC _es

_es                     :   defs 11   ; struct esx_stat

; Give up all available space to the file fragments array.
; In order to save some memory overlap the dot's help text.

PUBLIC _main_help
PUBLIC _fm_entries 

_fm_entries:
_main_help:

   defm "\n"
   defm "%s alpha 0.3\n\n"
   defm "ZX Spectrum Next Video Player\n\n"
   defm "-a  audio disabled\n"
   defm "-i  extra video info\n"
   defm "-q  quiet messages\n\n"
   defm "-f=[start][,end] frame range\n"
   defm "-m=[s][e][l] pause s/e, loop\n\n"
   defm "-50 set display to 50 Hz\n"
   defm "-60 set display to 60 Hz\n\n"
   defm ".%s -ai -50 m1.vid ...\n\n"
   defm "\x7f 2022 Allen Albright\n\n"
   defb 0

; extends to 0x9200 sizeof fm_entries[] must agree with sd.h

;;
;; STACK
;;

   SECTION STACK

   defs 0x100
