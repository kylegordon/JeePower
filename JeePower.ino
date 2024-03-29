// vim :ts=3:sw=4:sts=4
/*
	Control relay actived PSU by monitoring ignition and oil pressure state. 

	created 2011
	by Kyle Gordon <kyle@lodge.glasgownet.com>

http://lodge.glasgownet.com
 */

/*                 JeeNode / JeeNode USB / JeeSMD 
						 -------|-----------------------|----|-----------------------|----       
						 |       |D3  A1 [Port2]  D5     |    |D3  A0 [port1]  D4     |    |
						 |-------|IRQ AIO +3V GND DIO PWR|    |IRQ AIO +3V GND DIO PWR|    |
						 | D1|TXD|                                           ---- ----     |
						 | A5|SCL|                                       D12|MISO|+3v |    |
						 | A4|SDA|   Atmel Atmega 328                    D13|SCK |MOSI|D11 |
						 |   |PWR|   JeeNode / JeeNode USB / JeeSMD         |RST |GND |    |
						 |   |GND|                                       D8 |BO  |B1  |D9  |
						 | D0|RXD|                                           ---- ----     |
						 |-------|PWR DIO GND +3V AIO IRQ|    |PWR DIO GND +3V AIO IRQ|    |
						 |       |    D6 [Port3]  A2  D3 |    |    D7 [Port4]  A3  D3 |    |
						 -------|-----------------------|----|-----------------------|----
 */


#include <JeeLib.h>

Port optoIn (1);		// Port 1 : Optoisolator inputs
PortI2C myI2C (2);		// Port 2 : I2C driven LCD display for debugging
// Port 3 : Buzzer on DIO and LED on AIO
Port relays (4);		// Port 4 : Output relays

// has to be defined because we're using the watchdog for low-power waiting
ISR(WDT_vect) { Sleepy::watchdogEvent(); }

boolean DEBUG = 1;

// set pin numbers:
const byte stateLED =  16;      // State LED hooked onto Port 3 AIO (PC2)
const int buzzPin = 6;			  // State LED hooked into Port 3 DIO (PD6)

// variables will change:

int ontimeout = 30000;			  // time to wait before turning on (30 seconds)
int offtimeout = 90000;			  // time to wait before turning off (15 minutes)
int gpiotimeout = 10000;		  // time to give the Bifferboard to shut down (10 minutes)
int startcounttimeout = 5000;	  // time to wait before starting the countdown (5 seconds)
int timetogo = 0;
long flashtarget = 0;			  // Used for flashing the LED to indicate what is happening
boolean flasher = 0;				  // LED state level
byte buzzTone = 196;				  // Buzzer tone

long previousMillis = 0;		  // last update time
long elapsedMillis = 0;			  // elapsed time
long storedMillis = 0;  

boolean timestored = 0;
boolean ignitionState = 0;      // variable for reading the pushbutton status
boolean oilState = 0;			  // variable for oil pressure state
boolean active = false;
boolean countingdown = false;
boolean gpiorelay = 0;			  // Used to store the state of the GPIO indicator relay. Usually on when all is well.
boolean ignitionoverride = 0;	  // Used to override the ignition state.

void setup() {
	 if (DEBUG) {					  // If we want to see the pin values for debugging...
		  Serial.begin(57600);	  // ...set up the serial ouput on 0004 style
		  Serial.println("\n[cartracker]");
	 }

	 // Initialize the RF12 module. Node ID 30, 868MHZ, Network group 5
	 // rf12_initialize(30, RF12_868MHZ, 5);

	 // This calls rf12_initialize() with settings obtained from EEPROM address 0x20 .. 0x3F.
	 // These settings can be filled in by the RF12demo sketch in the RF12 library
	 rf12_config();

	 // Set up the easy transmission mechanism
	 rf12_easyInit(0);

	 // Set up the relays as digital output devices
	 relays.digiWrite(0);
	 relays.mode(OUTPUT);
	 relays.digiWrite2(0);
	 relays.mode2(OUTPUT);

	 // connect to opto-coupler plug as inputs with pull-ups enabled
	 optoIn.digiWrite(1);
	 optoIn.mode(INPUT);
	 optoIn.digiWrite2(1);
	 optoIn.mode2(INPUT);

	 // initialize the LED pins as outputs:
	 pinMode(stateLED, OUTPUT);

	 for (byte i = 0; i <= 10; ++i) {
		  digitalWrite(stateLED, flasher);
		  if (flasher) {tone(buzzPin,buzzTone,1000); }
		  delay(250);
		  if (flasher) {noTone(buzzPin); }
		  flasher = !flasher;
	 }
	 if (DEBUG) { Serial.println("Ready"); }
	 if (DEBUG) {
		  int val = 100;
		  rf12_easyPoll();
		  rf12_easySend(&val, sizeof val);
		  rf12_easyPoll();
	 }
}

void loop(){

	 // Sleepy::loseSomeTime() screws up serial output
	 //if (!DEBUG) {Sleepy::loseSomeTime(30000);}		// Snooze for 30 seconds
	 unsigned long currentMillis = millis();

	 if (rf12_recvDone() && rf12_crc == 0 && rf12_len == 1) {
		  if (DEBUG == 1) { Serial.print("Recieved : "); Serial.println(rf12_data[0]); }
	 }

	 // read the state of the ignition and oil pressure to tell if engine is running
	 ignitionState = !optoIn.digiRead2();
	 oilState = !optoIn.digiRead();
	 // if (DEBUG) { Serial.print("Ign state : "); Serial.println(ignitionState); }
	 // if (DEBUG) { Serial.print("Oil state : "); Serial.println(oilState); }

	 //if (ignitionState == 0 && active == true) {
	//	  delay(1000);
	 //}

	 if (active == false) {
		  // active is when power is on. In this case, it's not yet
		  if (ignitionState == 1 && oilState == 0) { 
				if (timestored == 0) {
					 // Ignition has just been turned on, and time has to be stored and made ready for counting up.
					 timestored = 1;
					 flashtarget = 0;
					 storedMillis = currentMillis;
					 if (DEBUG) { Serial.print("Storing time : "); Serial.println(currentMillis); }
				}
				if (timestored == 1) {
					 // Ignition is on and we're counting up until time to turn on
					 elapsedMillis = currentMillis - storedMillis;
					 if (elapsedMillis > ontimeout) { active = 1; }
					 if (DEBUG) { Serial.print("Elapsed time : "); Serial.println(elapsedMillis); }
					 // Flash the LED as we're counting up
					 if (flashtarget <= elapsedMillis) {
						  for (byte i = 0; i <= 2; ++i) {
								digitalWrite(stateLED, flasher);
								//if (flasher) {tone(buzzPin,buzzTone,1000); }
								delay(100); // Can this not be avoided by using the flashtarget and using if (!flasher) below?
								//if (flasher) {noTone(buzzPin); }
								flasher = !flasher;
						  }
						  flashtarget = elapsedMillis + 100;
					 }
				}
		  } else {
				// Everything is off
				digitalWrite(stateLED, LOW);
				relays.digiWrite(LOW); // Turn off the ATX power
				relays.digiWrite2(LOW); // Turn off the GPIO indicator output
				gpiorelay = 0; // Take a note that we've turned off the relay that indicates the GPIO pin
				timestored = 0;
				storedMillis = 0;
		  }
	 }

	 if (active == true) {
		  // We're active, power is on, so we should be implementing any delays now.

		  //if (ignitionoverride == 1) { ignitionState = 0; }

		  //if (gpiorelay == 0 && ignitionState == 1 && countingdown == 1) {
				// Power restored whilst counting down and relay is off?
		  //}

		  if (ignitionState == 0) {
				if (countingdown == 0) {
					 // If we're not counting down, we will be now. The ignition has been lost.
					 storedMillis = currentMillis; // Store the time the button was pressed
					 if (DEBUG) {Serial.print("Storing time : "); Serial.println(storedMillis);}
					 countingdown = 1;
				}
				if (countingdown == 1) {
					 // Ignition is off and we're counting down to turning off
					 timetogo = (offtimeout + storedMillis) - currentMillis; // Time left is the current time
					 if (DEBUG) {Serial.print("Runtime left : "); Serial.println(timetogo);}
					 if (timetogo <= flashtarget - 50) {
						  for (byte i = 0; i <= 2; ++i) {
								digitalWrite(stateLED, flasher);
								//if (flasher) {tone(buzzPin,buzzTone,1000); }
								delay(100); // Can this not be avoided by using the flashtarget and using if (!flasher) below?
								//if (flasher) {noTone(buzzPin); }
								flasher = !flasher;
						  }
						  flashtarget = timetogo;
					 }
					 if (timetogo <= gpiotimeout) {
						  // Since we're turning off, we should tell the GPIO pin on the Bifferboard
						  if (DEBUG) {Serial.println("GPIO Relay off"); }
						  relays.digiWrite2(LOW);
						  gpiorelay = 0;
					 }

				}
				if (timetogo <= 0 && countingdown == 1) {
					 // That's us at the end. Reset some variables for reactivation and power off
					 if (DEBUG) {Serial.println("Power off"); }
					 active = false;
					 timetogo = 0;
					 countingdown = 0;
					 digitalWrite(stateLED, LOW);
					 relays.digiWrite(LOW); // Turn off the ATX supply
					 relays.digiWrite2(LOW); // Turn off the GPIO indicator output
					 gpiorelay = 0; // Take a note that we've turned off the relay that indicates the GPIO pin
				}
		  }

		  if (ignitionState == 1 && countingdown == 1 && gpiorelay == 0) {
				// The ignition is on, but we have to finish the countdown, as the gpio relay is off
				countingdown = 1; // This ovverides the check just a couple of lines above and forces us to keep counting
		  }

		  //if (ignitionState == 0 && ignitionoverride == 1) {
				// We know the ignition is being overridden...
				// ignitionState = !optoIn.digiRead2();
		  //}

		  if (ignitionState == 1) {
				// What do we do when the ignition comes back on during the countdown?
				// This is also the normal state for when the countup has completed and the ignition is on and running
				countingdown = 0;
				flashtarget = offtimeout;
				digitalWrite(stateLED, HIGH);
				relays.digiWrite(HIGH);

				relays.digiWrite2(HIGH);
				gpiorelay = 1;

				// if (DEBUG) {Serial.println("GPIO Relay going high"); }
				/*if (gpiorelay == 0) {
				// We're in a bad place. The ignition is back on, but we've already indicated to the Bifferboard 
				// that it should be shutting down.
				// Wait a couple of minutes for the Bifferboard to shut down, and then toggle the ATX PSU
				// Well, why not just complete the shutdown routine? The rest of it should power back up again...
				// May need to introduce a slight off delay
				if (DEBUG) {Serial.println("Shit, we're going off..."); }
				countingdown = 1;
				}*/
		  }

		  // if relay is off, if countdown hasn't reached timeout, and if ignition is on, then continue counting until timeout
	 }
}
