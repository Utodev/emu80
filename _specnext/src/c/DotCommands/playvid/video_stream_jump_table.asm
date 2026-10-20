;; COMMON BLOCK CONSISTING OF JUMP TABLE

;; JUMP TABLE AT 0x9310

_video_player_jump_table:

   defw play_vga_50_silent    ; vga 50 Hz silent player
   defw play_vga_50_mono      ; vga 50 Hz mono player
   defw play_vga_50_stereo    ; vga 50 Hz stereo player
   
   defw play_vga_60_silent    ; vga 60 Hz silent player
   defw play_vga_60_mono      ; vga 60 Hz mono player
   defw play_vga_60_stereo    ; vga 60 Hz stereo player
   
   defw play_hdmi_50_silent   ; hdmi 50 Hz silent player
   defw play_hdmi_50_mono     ; hdmi 50 Hz mono player
   defw play_hdmi_50_stereo   ; hdmi 50 Hz stereo player
   
   defw play_hdmi_60_silent   ; hdmi 60 Hz silent player
   defw play_hdmi_60_mono     ; hdmi 60 Hz mono player
   defw play_hdmi_60_stereo   ; hdmi 60 Hz stereo player
