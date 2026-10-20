NextSID 1.0 by em00k 
---------------------------
NextSID engine by 9bitcolor 

With NextSID, you can play back regular PT3 files and apply a 
customizable duty cycle to any of the channels, producing a SID-like 
synth lead. It only handles 3-channel songs, with a handful included. 

There are a selection of .PT3s supplied with this software inside the 
"pt3files" folder that will be displayed when you first click "Load PT3"

With thanks to Niko for Creep, Megus for Robocop, z00m for the chiptunes, 
and the opening song is a mini conversion of the Hybris in-game tune on 
the Amiga by Paul van der Valk.

You will require a mouse to use this software. 

How to use:
---------------------------

The top part of the screen with the horizontal VU meters controls 
the following:

>> = The amount of divisions to apply to the byte mask
Chan A, Chan B, Chan C clicking will toggle the synth effect. 
The pen icon with the title "EDIT" will display that channel's 
byte mask in the wave display below.

On the right, under the word "Detune" you will see a - + and 
a value. The value is the amount of detune applied to the duty cycle.
Click + to increase and - to decrease. 

DETUNE 

- + 000C Will apply a detune of $C to channel A
- + 000A Will apply a detune of $A to channel A
- + 0000 No detune applied. 

In the middle of the screen is shown a 32-byte representation of the 
byte mask that is used to generate the duty cycle. There are 3 byte 
masks, one for channel A, B, and C. 

WAVE A 

Selecting a wave is done by clicking on the pen icon above. When a wave 
is selected, you can use the mouse to "draw" the values. The values are 
stepped in steps of 16 vertically. An alternating pattern of 128,0 will 
produce the default duty. On the right, you will see: 

LEN 
- + 0F 

This sets the length of the current wave. Multiples of 8 work best. The 
default is $0F.

Below the wave area are the control buttons:

Load PT3  - Launches the internal browser to load a PT3 file. You will 
            need your mouse to select a PT3 with the left button, or 
            cancel with the right button to return to the main page. 

            When you load a PT3, NextSID will automatically look for an 
            .NT3 file of the same name that contains the parameters for 
            the NextSID config for that tune. 

Load NT3   - Lets you load an NT3 file and applies it to the current tune
Save NT3   - Saves the {filename}.NT3 to the SD card
Play       - Plays the tune
Stop       - Stops the tune, restarts with Play.
Pause      - Pauses, continue with Play. 
Reset      - Resets all the NextSID parameters 
AY/YM      - Toggles the AY chip to use AY8912 or YM2419
ABC/ACB    - Toggles between ABC stereo or ACB stereo
-500 +500  - Adjusts the PSG clock 
Mono/Stereo- Toggles if the tune plays in stereo or mono.
Quit       - Promise button for the future :D

You can use the following keyboard shortcuts: 

1,2,3      - Toggles the duty for each channel A,B, and C 
4,5,6      - Mutes channel A, B, and C, re-enable with keys 1, 2, or 3 
Space      - Pause, Play
N          - Play the next .PT3 in the folder. ( may be buggy!)