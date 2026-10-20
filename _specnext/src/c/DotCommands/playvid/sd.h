#ifndef _SD_H
#define _SD_H

#include <stdint.h>

#define FILEMAP_ENTRIES  209        // max number of contiguous fragments (1675 bytes / 8)

extern unsigned char fd;            // file handle

struct sd_filemap
{
   uint32_t length;
   uint32_t address;
};

extern struct sd_filemap fm_entries[FILEMAP_ENTRIES]; // complete filemap
extern uint16_t n_entries;                            // number of valid file fragments

extern uint32_t filesz;             // total video size in sectors

extern unsigned char video_format;  // video format

// 0 = 320x240 with palette 17fps 933 stereo samples (frame size = 155)
// 1 = 320x240 no palette 17fps 933 stereo samples (frame size = 154)
// 2 = 256x240 with palette 17 fps 1866 stereo samples (frame size = 129)
// 3 = 256x240 no palette 17fps 1866 stereo samples (frame size = 128)
// 4 = 256x192 with palette 25fps 933 mono samples (frame size = 99)
// 5 = 256x192 no palette 25fps 933 mono samples (frame size = 98)

//

extern void sd_enumerate_file_fragments(unsigned char *filename);
extern void sd_classify_video_format(void);
extern unsigned char sd_open_stream(void);

#endif
