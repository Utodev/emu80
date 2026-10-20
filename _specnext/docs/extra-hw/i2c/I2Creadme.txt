I2C Bus
-------

The ZX Spectrum Next does not really have an i2c bus, but, it does have some
pins wired up to the PI header, the Real Time Clock (RTC) and Connector J15 on
the right of the board.

This supports any 3.3v i2c device at upto the nominal 100Mhz (the slower bus).
All the work has to be done in software to read and write these devices and the
best source of examples is the RTC ASM files - these are based on the work
originally done by Victor and Velosoft - the most accurate timing code is in the
I2CSCAN.ASM (which is the basis of the later RTCACK.ASM) which also handles Bus
acknowledgments so actually checking the chip is really answering.

The system uses the following port allocations for controling the signals on D0

	defc PORT = 0x3B
	defc PORT_CLOCK = 0x10 			;0x103b
	defc PORT_DATA = 0x11 			;0x113b

Supplied Utility
----------------

Supplied as part of the RTC bit of the PlusPACK is a DOT command called I2CSCAN

This will search the i2c bus for any devices found which can help in seeing what
is connected.

You should see at least one device at 0x68 if the RTC chip is connected.

Devices like a DS3231 module may have a fan out extender so you may also see a
device at 0x57.  If you see others when you have nothing on J15 then make sure
you have the latest TBU, any Capacitor mod etc - if so and you still have others
detected then please contribute to the RTC posts on Facebook or the Forum.

Other information
-----------------

See also the documentation on the PI to understand how it can communicate using
the i2c pins.

This also includes some DOT commands which use the software i2c bus.


Tim Gilberts
Feb 2019
