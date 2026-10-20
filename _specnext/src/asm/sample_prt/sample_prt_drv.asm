; ***************************************************************************
; * Example NextZXOS printer driver file                                    *
; ***************************************************************************
;
; This file generates the actual sample_prt.drv file which can be installed or
; uninstalled using the .install/.uninstall commands.
;
; The driver itself (sample_prt.asm) must first be built.
;
; Assemble this file with: pasmo sample_prt_drv.asm sample_prt.drv
;
; GENERAL NOTES ON PRINTER/AUX DRIVERS:
;
; A printer driver should use "P" as its driver id. This allows the user
; to install whatever printer driver is appropriate for them, and for
; software to use it in a standardised way.
;
; In particular, NextBASIC will automatically send data LPRINT/LLISTed
; (or PRINTed to #3, or any other stream that has been opened to
; BASIC channel "P") to any installed driver with id "P".
;
; Similarly, if a "P" driver has been installed, CP/M will use this for
; output to its logical LST: device (also referred to as the physical
; LPT device).
;
; In order to support NextBASIC and CP/M, a printer driver only needs to
; support the standard calls $f7 (return output status) and $fb (output
; character). You may of course support any other standard calls that
; you like (or additional driver-specific calls, for example to set the
; communications parameters for a serial printer).
;
; CP/M also supports an AUX physical device (with default input/output
; through the logical AUXIN: and AUXOUT: devices). This will
; automatically be routed to any installed driver with id "X".
; An AUX driver can be written in the same way as a printer driver, but
; should additionally support standard calls $f8 (return input status)
; and $fc (input character).
;
; See the example border.asm/border_drv.asm driver if your driver needs to
; be run on the IM1 interrupt, or if it needs additional 8K DivMMC/ZX RAM
; banks. This sample printer driver (and probably most printer drivers) do not
; require these, so discussion of them is not present in the example
; printer driver.


; ***************************************************************************
; * Definitions                                                             *
; ***************************************************************************
; Pull in the symbol file for the driver itself and calculate the number of
; relocations used.

        include "sample_prt.sym"

relocs  equ     (reloc_end-reloc_start)/2


; ***************************************************************************
; * .DRV file header                                                        *
; ***************************************************************************

        org     $0000

        defm    "NDRV"          ; .DRV file signature

        defb    "P"             ; standard driver id for printer device.

        defb    relocs          ; number of relocation entries (0..255)

        defb    0               ; number of 8K DivMMC RAM banks needed
        defb    0               ; number of 8K Spectrum RAM banks needed


; ***************************************************************************
; * Driver binary                                                           *
; ***************************************************************************
; The driver + relocation table should now be included.

        incbin  "sample_prt.bin"

