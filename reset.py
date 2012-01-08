#!/usr/bin/python -i
## Toggles the RTS pin that cheap CP2102 devices bring out, instead of the DTR pin used by Arduinos
## Use with Scons - scons upload RST_TRIGGER=./reset.py

import time
import serial

sp="/dev/ttyUSB0"
s=serial.Serial(sp)
print "Raising"
s.setRTS(1)
s.setDTR(1)
time.sleep(10)
print "Lowering"
s.setRTS(0)
s.setDTR(0)
