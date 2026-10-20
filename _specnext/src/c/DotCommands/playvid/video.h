#ifndef _VIDEO_H
#define _VIDEO_H

#include <stdint.h>
#include "sd.h"

#define VIDEO_PLAYER_CODE_SIZE (0x10000 - 0x9300)

// video player information - valid after player is loaded

struct vpi
{
   unsigned char *description;    // text description of player
   unsigned char frame_size;      // size of each video frame in sectors
   unsigned char mode;            // nextreg 0x70 l2 mode for playback
   unsigned char scroll_y;        // y scroll setting for playback
   unsigned char scroll_x_lsb;    // x scroll lsb setting for playback
   unsigned char scroll_x_msb;    // x scroll msb setting for playback
   unsigned char clip_x1;         // clip rectangle for playback
   unsigned char clip_x2;
   unsigned char clip_y1;
   unsigned char clip_y2;
};

extern struct vpi video_player_info;
extern void *video_player_jump_table[];  // video player playback functions

// video playback miscellaneous

extern unsigned char _esx_stream_card_flags;
extern unsigned char vbi_counter; // time passage in 50 / 60 Hz frames

// video player controls

extern uint32_t v_sector_start;   // sector number within video file to start playing from
extern uint32_t v_frame_count;    // number of video frames to play

extern struct sd_filemap *v_file_fragment;   // file fragment following current one
extern uint32_t v_fragment_remaining;        // sectors remaining in current file fragment

// video player variables

struct vpv
{
   unsigned char  w_layer2_page_count;   // number of pages in L2 screen (player managed)
   unsigned char  w_layer2_page;         // destination L2 page
   unsigned char  w_layer2_palette;      // destination palette
   unsigned char *w_audio_buffer;        // destination audio buffer (player managed)
};

extern struct vpv video_player_vars;

#endif
