/*
 Control relay actived PSU by monitoring ignition and oil pressure state. 
 
 created 2011
 by Kyle Gordon <kyle@lodge.glasgownet.com>
 
 http://lodge.glasgownet.com
*/

#include <Ports.h>
#include <RF12.h>

Port relays (2);
Port optoIn (3);

// has to be defined because we're using the watchdog for low-power waiting
ISR(WDT_vect) { Sleepy::watchdogEvent(); }

boolean DEBUG = 1;

// set pin numbers:
const byte stateLED =  7;      // State LED hooked into DIO on Port 4 (should be PD7)

// variables will change:

int ontimeout = 5000;        // time to wait before turning on
int offtimeout = 15000;      // time to wait before turning off
int timetogo = 0;
long flashtarget = 0;	     // Used for flashing the LED to indicate what is happening
boolean flasher = 0;	     // LED state level

long previousMillis = 0;      // last update time
long elapsedMillis = 0;       // elapsed time
long storedMillis = 0;  

boolean timestored = 0;
boolean ignitionState = 0;         // variable for reading the pushbutton status
boolean active = false;
boolean countingdown = false;

void setup() {
  if (DEBUG) {           // If we want to see the pin values for debugging...
    Serial.begin(57600);  // ...set up the serial ouput on 0004 style
    Serial.println("\n[cartracker]");
  }

  // Initialize the RF12 module. Node ID 30, 868MHZ, Network group 5
  rf12_initialize(30, RF12_868MHZ, 5);

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
    delay(250);
    flasher = !flasher;
  }
  if (DEBUG) { Serial.println("Ready"); }
}

void loop(){
  unsigned long currentMillis = millis();

  if (rf12_recvDone() && rf12_crc == 0 && rf12_len == 1) {
    if (DEBUG == 1) { Serial.print("Recieved : "); Serial.println(rf12_data[0]); }
  }
  
  // read the state of the ignition
  ignitionState = !optoIn.digiRead2();
  // if (DEBUG) { Serial.print("Ign state : "); Serial.println(ignitionState); }

  if (active == false) {
    if (ignitionState == 1) { 
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
	  digitalWrite(stateLED, flasher);
	  flasher = !flasher; 
	  flashtarget = elapsedMillis + 100;
	}
      }
    } else {
      // Everything is off
      digitalWrite(stateLED, LOW);
      relays.digiWrite(LOW);
      timestored = 0;
      storedMillis = 0;
    }
  }

  if (active == true) {
    // We're active, so we have to count down now as well
    if (ignitionState == 0) {
      if (countingdown == 0) {
        storedMillis = currentMillis; // Store the time the button was pressed
        if (DEBUG) {Serial.print("Storing time : "); Serial.println(storedMillis);}
        countingdown = 1;
      }
      if (countingdown == 1) {
        timetogo = (offtimeout + storedMillis) - currentMillis; // Time left is the current time
        if (DEBUG) {Serial.print("Runtime left : "); Serial.println(timetogo);}
	if (timetogo <= flashtarget - 50) {
	  digitalWrite(stateLED, flasher);
	  flasher = !flasher;
	  flashtarget = timetogo;
	}
      }
      if (timetogo <= 0 && countingdown == 1) {
        // That's us at the end. Reset some variables for reactivation and power off
        if (DEBUG) {Serial.println("Power off"); }
        active = false;
        timetogo = 0;
        countingdown = 0;
        digitalWrite(stateLED, LOW);
	relays.digiWrite(0);
      }
    }
    if (ignitionState == 1) {
      // What do we do when the ignition comes back on during the countdown?
      // This is also the normal state for when the countup has completed and the ignition is on and running
      countingdown = 0;
      flashtarget = offtimeout;
      digitalWrite(stateLED, HIGH);
      relays.digiWrite(1);
    }
  }
}

