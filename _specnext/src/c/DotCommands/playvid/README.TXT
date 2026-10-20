PLAYVID ABOUT
=============

This is an alpha version of a video player for the zx spectrum next. Currently six video formats are supported:

// 0 = 320x240 with palette 16.7fps 933 stereo samples @ 15.6kHz (frame size = 155) (layer 2)
// 1 = 320x240 no palette 16.7fps 933 stereo samples @ 15.6kHz (frame size = 154) (layer 2)
// 2 = 256x240 with palette 16.7 fps 1866 stereo samples @ 31.1kHz (frame size = 129) (layer 2)
// 3 = 256x240 no palette 17fps 1866 stereo samples @ 31.1kHz (frame size = 128) (layer 2)
// 4 = 256x192 with palette 25fps 933 mono samples @ 23.3kHz (frame size = 99) (layer 2)
// 5 = 256x192 no palette 25fps 933 mono samples @ 23.3kHz (frame size = 98) (layer 2)

A video file is a simple binary file consisting of individial frames of video data.  Each frame contains audio samples, an optional palette and a graphical image.  The specific format is described at the top of the video_*.asm files in this directory.

For example, format (1) above has player code in video_320x240.asm which contains video information near the beginning:

;; frame size = 78848 bytes (154 sectors)
;;   ( 1866 bytes) 933 stereo samples (left then right) 
;;   (  182 bytes) padding
;;   (76800 bytes) 320x240 pixels (column major order)

The player is currently classifying the video format solely based on file size in priority order of formats (0) - (5).  If your video is misclassified due to it being a multiple of the file size of another format, append a blank frame to the end.  You can also force the player to use a specific format by adding "-0" through "-5" in the invocation.

The video formats so far are designed for vga/rgb 50 Hz.  The player will make an effort to play back on other video settings:

HMDI 50 Hz -- correct frame rate, might be some slight popping in audio
VGA 60 Hz -- slower frame rate, popping in audio
HDMI 60 Hz -- slower frame rate, reduced audio quality with popping in audio

The step to 60 Hz considerably slows the playback frame rate.  A format designed to run at 50/3 = 16.7 fps will instead be played back at 60/4 = 15 fps.  To retain the sync between audio and video, the same set of audio samples has to be spread across the 60/4 time.  To do this, sometimes samples are skipped and due to binary fraction imprecision, sometimes a small sequence of zero samples must be played to fill time which leads to popping.

The player has also been written to handle file fragmentation which is unusual for these types of players.  Too much fragmentation can still lead to playback glitches so if any of that is seen, try defragmenting the video file.  While a video is playing, pausing and unpausing the video will restore the playback.

Future plans:

- 60 Hz formats in addition to 50 Hz
- other display surfaces supported like the standard ula
- additional playback controls like ffwd, rwd, seek, loop, etc


PLAYVID USAGE
=============

.playvid on its own displays help.

-q           = don't print messages
-50 or -60   = change to 50 Hz or 60 Hz for playback
-a           = play without audio
-iq          = classify video and quit without playback
-f=s[,e]     = play back frame range
-m=[s][e][l] = loop, pause on start frame, pause on end frame of every loop

Negative numbers used in the frame range are distance from the end of the file.  -1 corresponds to the last frame.

-0, -1, -2, -3, -4, -5 = force the indicated video format for playback

FAT32 has a 4GB file size limit.  This corresponds to an hour or more of video depending on the format.  To get around this limit, playvid can be given more than one file to play on the command line:

.playvid one.vid two.vid

Multiple files are treated as part of a single video file and will be classified as a whole.  This is not the same as playing multiple video files in a row as all files listed must be the same format.

During playback, BREAK or Q will quit.  Any other key will pause and unpause.


BRIEF TECHNICAL
===============

This is a brute force player in that uncompressed video and audio is read off the sd card as fast as possible to generate the video.  Audio is interrupt driven by the CTC (counter timer circuit).  The initial formats are designed for vga 50 Hz playback which has a certain number of CPU T states in a frame.  The divider for the CTC timer has to divide exactly into the frame time to retain audio and video lock.

sd.c -- creates a map of the video file's distribution on sd card.  Mapping returns sectors allocated to a file which may be larger than the occupied portion of the file so excess sectors must be stripped off.

mem.c -- takes care of memory allocation for the audio and two L2 buffers.  As this is a dot command, it must be able to run and exit without interfering with the basic system.  This must include allocating memory from NextZXOS so that an existing basic program is not wiped out by the player.  The playback is double buffered so regions for two L2 buffers are needed; that is 80K * 2 = 160K.  Further, each 80K buffer needs to be contiguous and to simplify the video player code, the two buffers need to be separated by 16 pages.

state.c -- on exit, all hardware settings have to be restored to what they were when the dot command was started.  The main idea behind accomplishing this is an array holding affected registers and original values.  On exit, the original values are restored.  The original L2 palette also has to be saved.

main.c -- handles initialization, cleanup and the playback sequence.  Hardware im2 mode is used for the ctc interrupts.  This places the zx next in a real im2 mode with interrupting peripherals assigned their own vectors.

interrupts-common.asm -- Interrupt vector table and ISRs for the ctc (audio playback) + ula (frame counter).  As the dot command runs under hardware im2 mode, the vector table only has to be 32 bytes long.

The dot command is built as a dotn.  Options in zpragma.inc use a standard Z80 memory map meaning everything gets placed into divmmc memory by default just like a normal dot command.  Another setting there specifies that pages should also be allocated for memory 0x8000+.  This means when the dot command starts, 0x8000 and above have already had allocated pages assigned.

The default memory map is extended by mmap.inc:

SECTION INTERRUPT
org 0x8000
SECTION COMMON
SECTION CODE1
SECTION VARS1
SECTION VARS2
SECTION STACK
org 0x9200

The interrupt vector table and ISRs will be located at 0x8000.  The common area is used for variables shared between the dot command and video player.  code1/vars1 contains code specifically compiled to that area.  vars2 and stack extend to 0x9300 which is the start address of the video player.

During the compilation, code and data are placed in divmmc by default but the files listed in zproject-ram.lst are placed in code1/vars1.  This stuff will be automatically loaded as part of the dot command.

What is not automatically loaded is the video players.  The video players are ORGed to 0x9300 and are fixed size.  Code is found in the video_*.asm files.  These video players are appended to the dot command.  main.c classifies the video and then loads the appropriate player to 0x9300 from the dot command binary itself.

During playback, mmu2 (0x4000-0x5fff) is used as the audio buffer and mmu3 (0x6000-0x7fff) is used as the window on L2 memory.
