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

int DEBUG = 0;
int optostate1 = 0;
int optostate2 = 0;

// constants won't change. They're used here to 
// set pin numbers:
const byte buttonPin = 2;     // the number of the pushbutton pin
const byte stateLED =  7;      // State LED hooked into DIO on Port 4 (should be PD7)
const byte outputLED = 12;

// variables will change:

int ontimeout = 5000;        // time to wait before turning on
int offtimeout = 15000;      // time to wait before turning off
int timetogo = 0;
int modresult = 0;		// The modulo result
int flasher = 0;

long previousMillis = 0;      // last update time
long elapsedMillis = 0;       // elapsed time
long storedMillis = 0;  

boolean timestored = 0;
// boolean ignitionState = 0;         // variable for reading the pushbutton status
int ignitionState = 0;
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
  pinMode(outputLED, OUTPUT);;  
  // initialize the pushbutton pin as an input:
  pinMode(buttonPin, INPUT);     

  byte state = 0;  
  for (byte i = 0; i <= 10; ++i) {
    digitalWrite(stateLED, state);
    delay(250);
    state = !state;
  }
  if (DEBUG) { Serial.println("Ready"); }
}

void loop(){
  unsigned long currentMillis = millis();

  if (rf12_recvDone() && rf12_crc == 0 && rf12_len == 1) {
    if (DEBUG == 1) { Serial.print("Recieved : "); Serial.println(rf12_data[0]); }
  }
  
  // read the state of the pushbutton value:
  // ignitionState = digitalRead(buttonPin);
  ignitionState = !optoIn.digiRead2();
  // if (DEBUG) { Serial.print("Ign state : "); Serial.println(ignitionState); }

  if (active == false) {
    if (ignitionState == 1) { 
      if (timestored == 0) {
        // Ignition has just been turned on, and time has to be stored and made ready for counting up.
        timestored = 1;
        storedMillis = currentMillis;
        if (DEBUG) { Serial.print("Storing time : "); Serial.println(currentMillis); }
      }
      if (timestored == 1) {
        // Ignition is on and we're counting up until time to turn on
        elapsedMillis = currentMillis - storedMillis;
        if (elapsedMillis > ontimeout) { active = 1; }
        if (DEBUG) { Serial.print("Elapsed time : "); Serial.println(elapsedMillis); }
	modresult = elapsedMillis % 200;
	if (modresult == 0) { 
	  digitalWrite(stateLED, flasher);
	  flasher = !flasher; 
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
        modresult = timetogo % 50;
        if (modresult == 0) {
          digitalWrite(stateLED, flasher);
          flasher = !flasher;
	}
	relays.digiWrite(1);
      }
      if (timetogo <= 0 && countingdown == 1) {
        // That's us at the end. Reset some variables for reactivation and power off
        if (DEBUG) {Serial.println("Power off"); }
        active = false;
        timetogo = 0;
        countingdown = 0;
        digitalWrite(outputLED, LOW);
	relays.digiWrite(0);
      }
    }
    if (ignitionState == 1) {
      // What do we do when the ignition comes back on during the countdown?
      // This is also the normal state for when the countup has completed and the ignition is on and running
      countingdown = 0;
      digitalWrite(stateLED, HIGH);
      relays.digiWrite(1);
    }
  }
}

