# .DISPLAYEDGE dot command

It lets you visually edit display margins - the visible area of your display in particular
video mode - and store that in the config file "sys/env.cfg".

Any SW aware of this config file can then read it upon start, and shrink the playfield to
display everything important within the area of screen which is visible on your display.

Use the controls (F and T) to switch to the video mode you want to edit margins for (the
machine type/timing can be switched only in VGA mode, VGA<->HDMI switch must be done
while restarting machine by user).

Then edit the values (screen corners) until the "green frame" is visible well on your
display, then save the config.

## Usage

`.displayedge` entered in command line will launch the tool and read current config.

Once inside the tool, the controls are:

    SPACE  : select active corner of display (top left vs bottom right)
    arrows : edit visible position of the active corner ("cursor joystick")
    (also Kempston/MD controller can be used, fire then selects corner)
    Q      : exit back to NextZXOS
    R      : reload the cfg file currently stored on disk (discards any changes)
    S      : save the currently modified values to cfg file
    F      : change between 50Hz/60Hz mode (also regular "F3" key works)
    T      : in VGA modes you can switch between different video-mode timings
    (Q/R/S/F/T usually requires confirmation by pressing "Y" after)

## Software with support

`.guide`

(and lot more tools in development have support planned)
