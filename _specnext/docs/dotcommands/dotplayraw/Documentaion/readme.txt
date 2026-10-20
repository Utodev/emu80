NextBASIC PCM Player
By Chris Taylor / taylorza

https://taylorza.itch.io/nextbasic-raw-pcm-player

Using this library has three steps to it

Install the player
Load the samples (up to 8 samples, you can replace a sample at any time)
Send the player commands to start/stop playback and get the current status of the player
Install the player
Installing the player is as simple as executing the .playraw DOT command. This will install the player and setup the environment ready to start playing

10 .playraw
Executing .playraw multiple times will not cause any issues, however you will need to reload your samples.

Load samples
Next we need to load some samples to play. This is done using the .loadraw DOT command. This command will check that the player is installed and give an error if not. The loader will allocate banks from NextOS and load the sound data into the banks. You can load audio data into one of 8 slots (0..7). Slots can be reused simply by loading a new sample into the target slot, this will replace the previous audio data with the newly loaded data.

20 .loadraw 0 "andnow.raw" : REM Load sample into slot 0
30 .loadraw 1 "problem.raw" : REM Load sample into slot 1
Start/Stop Playback
Starting and stopping playback is done by sending commands to the player.

There are 3 addresses used to trigger the actions in the player

Command         Address         Arguments            Description
Start Playback  23768   ($5cd8) slot number (0..7)   Starts the playback of the audio in the specified slot.
NOTE:If the high bit of the slot number is set, the sample will loop until stopped.
Stop Playback   23771   ($5cdb)	N/A                  Stops the current playback
Get Status      23774   ($5cde)	N/A                  Returns 1 if the player is currently playing audio, 0 if not
To make this easier to use, you can use the following code

    1000 DEFPROC StartPlayback(slot)
    1010   RANDOMIZE USR (23768,slot)
    1020 ENDPROC
    1030 DEFPROC StopPlayback()
    1040   RANDOMIZE USR 23771
    1050 ENDPROC
    1060 DEF FN IsPlaying()= USR 23774
Create your own audio files
The downloadable zip file contains 4 sample audio clips. Using Audcity you can load an audio clip and export it using the following setting

Option	Setting
Format	Other uncompressed files
Channels	Mono
Sample Rate	4000 Hz (Custom)
Header	RAW (header-less)
Encoding	Unsigned 8-bit PCM
Exporting using the above settings will give you a file that can be directly loaded using .loadraw.

NOTE:The file must not be larger than 64K (65535 bytes)