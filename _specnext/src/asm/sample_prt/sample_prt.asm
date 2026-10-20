; ***************************************************************************
; * Example NextZXOS printer driver                                         *
; ***************************************************************************
;
; This file is the 512-byte NextZXOS driver itself, plus relocation table.
;
; Assemble with: pasmo sample_prt.asm sample_prt.bin sample_prt.sym
;
; After this, sample_prt_drv.asm needs to be built to generate the actual
; driver file.
;
; GENERAL NOTES ON PRINTER/AUX DRIVERS:
;
; A printer driver should use "P" as its driver id. This allows the user
; to install whatever printer driver is appropriate for them, and for
; software to use it in a standardised way.
;
; NextZXOS contains a built-in "P" driver suitable for the ZX Printer,
; Alphacom 32 and Timex 2040. This will be overridden by any user-installed
; "P" driver for alternative printers.
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
; character).
;
; Optionally, you can support the COPY command which uses call $f6. The
; built-in ZX printer driver always copies the standard Spectrum screen
; in this case, even if other modes such as layer 2 are active. Drivers for
; more capable printers may want to support colour copies, layer2, hi-res,
; lo-res, tilemaps etc. Note that if you are doing this, you should use the
; state of the appropriate Next ports and registers to determine which screen
; is currently active (eg the Layer2 and Timex ports, and the Sprites/Layers
; and Tilemap next registers). Don't rely on system variable information,
; since this call may be made when system variables are not valid (eg from
; the Multiface).
;
; You may of course support any other standard calls that
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
; The port used by our hypothetical printer. Don't try and use this driver
; as it won't do anything!

printer_port    equ     $ff


; ***************************************************************************
; * Entry points                                                            *
; ***************************************************************************

        org     $0000

; At $0000 is the entry point for API calls directed to the printer
; driver.
; NOTE: If your printer driver needs to be called on the IM1 interrupt
;       you will need to provide an entry point at $0003 for this (see
;       border.asm example driver for full details).
;       This simple printer driver doesn't need interrupts so there is
;       no need to provide the $0003 entry point.

api_entry:

; On entry, B=call id with HL,DE other parameters.
; You may provide any standard or driver-specific calls that you wish.
; See the example border.asm driver for a description of the standard calls.
; However, a standard printer driver that supports NextBASIC and CP/M only
; needs to provide 2 standard calls:
;   B=$f7: return output status
;   B=$fb: output character

        ld      a,b
        cp      $fb                     ; "output character" call?
        jr      z,output_char           ; on if so
        cp      $f7                     ; "return output status" call?
        jr      z,return_status         ; on if so

api_error:
        xor     a                       ; A=0, unsupported call id
        scf                             ; Fc=1, signals error
        ret


; ***************************************************************************
; * Return output status ($f7)                                              *
; ***************************************************************************
; This call is entered with D=handle.
; CP/M always calls with D=1 (system handle) and a printer
; driver can generally ignore the handle id unless you support standard
; calls for opening/closing multiple different streams and wish them all
; to be handled independently.
; This call should return with carry clear to indicate success and
; BC=$ffff if the printer is ready to accept a character for output, or
; BC=$0000 if the printer is not ready.

; Our hypothetical printer interface has a BUSY signal connected to bit
; 0 of the input data on the printer port, so we will check this and
; return the status accordingly.

return_status:
        ld      bc,$ffff
        and     a                       ; clear carry to indicate success
        in      a,(printer_port)        ; get signals from printer
        bit     0,a                     ; check BUSY signal
        ret     z                       ; exit with BC=$ffff if not busy
        inc     bc
        ret                             ; exit with BC=$0000 if bust


; ***************************************************************************
; * Output character ($fb)                                                  *
; ***************************************************************************
; This call is entered with D=handle and E=character.
; NextBASIC and CP/M always call with D=1 (system handle) and a printer
; driver can generally ignore the handle id unless you support standard
; calls for opening/closing multiple different streams and wish them all
; to be handled independently.
; This call should return with carry clear to indicate success.
; If you return with carry set and A=$fe, the error "End of file" will be
; reported. If you return with carry set and A<$fe, the error
; "Invalid I/O device" will be reported.
; Do not return with A=$ff and carry set; this will be treated as a successful
; call.

output_char:
        ; It's good practice to allow the user to abort with BREAK if
        ; the printer is stuck in a busy loop.
        ld      a,$7f
        in      a,($fe)
        rra
        jr      c,check_printer         ; on if SPACE not pressed
        ld      a,$fe
        in      a,($fe)
        rra
        jr      c,check_printer         ; on if CAPS SHIFT not pressed
        ld      a,$fe                   ; exit with A=$fe and carry set
        scf                             ; so "End of file" reported
        ret
check_printer:
        ; Wait for the printer to become ready.
        in      a,(printer_port)        ; get signals from printer
        bit     0,a                     ; check BUSY signal
        jr      nz,output_char          ; loop back if printer is busy
        ld      a,e                     ; A=character to output
        out     (printer_port),a        ; send to the printer
        and     a                       ; clear carry to indicate success
        ret


; ***************************************************************************
; * Relocation table                                                        *
; ***************************************************************************
; This follows directly after the full 512 bytes of the driver.

if ($ > 512)
.ERROR Driver code exceeds 512 bytes
else
        defs    512-$
endif

; Each relocation is the offset of the high byte of an address to be relocated.
; This particular driver is so simple it doesn't contain any absolute addresses
; needing to be relocated. (border.asm is a slightly more complex driver that
; does have a relocation table).

reloc_start:
reloc_end:

