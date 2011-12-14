#!/usr/bin/python -i
## Toggles the RTS pin that cheap CP2102 devices bring out, instead of the DTR pin used by Arduinos
## Use with Scons - scons upload RST_TRIGGER=./reset.py

import serial

#sp="/dev/ttyUSB0"
#sp="/dev/tty.PL2303-0000101D"
sp="/dev/tty.SLAB_USBtoUART"

s=serial.Serial(sp)
s.setRTS(0)
