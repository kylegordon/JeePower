/*
 Control relay actived PSU by monitoring ignition and oil pressure state. 
 
 created 2011
 by Kyle Gordon <kyle@lodge.glasgownet.com>
 
 http://lodge.glasgownet.com
*/

#include <Ports.h>
#include <RF12.h>

Port relays (1);
Port optoIn (2);

// has to be defined because we're using the watchdog for low-power waiting
ISR(WDT_vect) { Sleepy::watchdogEvent(); }

int DEBUG = 1;
int optostate1 = 0;
int optostate2 = 0;

// constants won't change. They're used here to 
// set pin numbers:
const byte buttonPin = 2;     // the number of the pushbutton pin
const byte stateLED =  13;      // the number of the LED pin
const byte outputLED = 12;

// variables will change:

int ontimeout = 5000;        // time to wait before turning on
int offtimeout = 15000;      // time to wait before turning off
int timetogo = 0;

long previousMillis = 0;      // last update time
long elapsedMillis = 0;       // elapsed time
long storedMillis = 0;  

boolean timestored = 0;
boolean buttonState = 0;         // variable for reading the pushbutton status
boolean active = false;
boolean countingdown = false;

void setup() {
  if (DEBUG) {           // If we want to see the pin values for debugging...
    Serial.begin(57600);  // ...set up the serial ouput on 0004 style
    Serial.println("\n[cartracker]");
  }

  rf12_initialize(30, RF12_868MHZ, 5);

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

  delay(500);
}

void loop(){
  unsigned long currentMillis = millis();
  // Serial.print("Time is ");
  // Serial.println(currentMillis);
  // delay(10);

  if (rf12_recvDone() && rf12_crc == 0 && rf12_len == 1) {
    if (DEBUG == 1) {
      Serial.print("Recieved : ");
      Serial.println(rf12_data[0]);
    }
  }
  
  // read the state of the pushbutton value:
  buttonState = digitalRead(buttonPin);
  // check if the pushbutton is pressed.
  // if it is, the buttonState is HIGH:
  if (active == false) {
    if (buttonState == HIGH) { 
      digitalWrite(stateLED, HIGH);
      if (timestored == 0) {
        timestored = 1;
        storedMillis = currentMillis;
        Serial.print("Storing time : ");
        Serial.println(currentMillis);
      }
      if (timestored == 1) {
        elapsedMillis = currentMillis - storedMillis;
        if (elapsedMillis > ontimeout) {
          active = 1;
        }
        Serial.print("Elapsed time : ");
        Serial.println(elapsedMillis);
      }

    } else {
      digitalWrite(stateLED, LOW);
      timestored = 0;
      storedMillis = 0;
    }
  }

  if (active == true) {
    // We're active, so we have to count down now as well
    digitalWrite(outputLED, HIGH);
    if (buttonState == LOW) {
      if (countingdown == 0) {
        storedMillis = currentMillis; // Store the time the button was pressed
        Serial.print("Storing time : ");
        Serial.println(storedMillis);
        countingdown = 1;
      }
      if (countingdown == 1) {
        timetogo = (offtimeout + storedMillis) - currentMillis; // Time left is the current time
        Serial.print("Runtime left : ");
        Serial.println(timetogo);
      }
      if (timetogo <= 0 && countingdown == 1) {
        // That's us at the end. Reset some variables for reactivation and power off
        Serial.println("Power off");
        active = false;
        timetogo = 0;
        countingdown = 0;
        digitalWrite(outputLED, LOW);
      }
    }
    if (buttonState == HIGH) {
      // What do we do when the ignition comes back on during the countdown?
      countingdown = 0;
    }
  }
}

