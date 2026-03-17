/*
 RainNest NodeMCU Firmware
 Direct Firebase Version
*/

#include <Arduino.h>
#include <ESP8266WiFi.h>
#include <WiFiClientSecure.h>
#include <Firebase_ESP_Client.h>

// ================= WIFI =================

#define WIFI_SSID "Don Shaji"
#define WIFI_PASSWORD "12345678901"

// ================= FIREBASE =================

#define API_KEY "AIzaSyAyGmgcjhFLKw4YZ1er_VyffBojnw_hCD8"
#define DATABASE_URL "https://rainnest-aab0f-default-rtdb.asia-southeast1.firebasedatabase.app/"

// Station ID
#define STATION_ID "machine1"

// ================= PIN DEFINITIONS =================

#define PIN_RED D5
#define PIN_GREEN D6
#define PIN_LOCK D1
#define PIN_ADC A0

// ================= SENSOR CONSTANTS =================

#define R_FIXED 10000.0
#define V_REF 3.3
#define NOISE_THRESHOLD 100.0
#define STABLE_REQUIRED 5

// ================= FIREBASE OBJECTS =================

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

// ================= SENSOR VARIABLES =================

float currentStableResistance = 0.0;
float candidateResistance = 0.0;
int stableCounter = 0;

// ================= SYSTEM STATES =================

enum SystemState {
  STATE_IDLE_LOCKED,        // Red Slow blink, Locked
  STATE_WAITING_CONFIRMATION, // Orange Fast blink (App scanned)
  STATE_RENTAL_SUCCESS,     // Green Solid ON
  STATE_WAITING_RETURN,     // Green Slow blink
  STATE_VERIFYING_RETURN,   // Orange Medium blink
  STATE_RETURN_SUCCESS      // Green Double blink
};

SystemState currentState = STATE_IDLE_LOCKED;

// ================= LED TIMING =================

unsigned long lastBlinkTime = 0;
bool blinkState = false;

// ================= FUNCTION DECLARATIONS =================

void setup_wifi();
float readResistance();
void updateLEDs();
void triggerSolenoid(bool on);
void sendFirebase(String path, String value);
void readCommand();

// ================= SETUP =================

void setup() {

  Serial.begin(115200);

  pinMode(PIN_RED, OUTPUT);
  pinMode(PIN_GREEN, OUTPUT);
  pinMode(PIN_LOCK, OUTPUT);
  pinMode(PIN_ADC, INPUT);

  triggerSolenoid(false);

  setup_wifi();

  // Firebase config
  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;

  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  Serial.println("Firebase Connected");

  currentStableResistance = readResistance();
  candidateResistance = currentStableResistance;

  Serial.println("Initial Resistance: " + String(currentStableResistance));
}

// ================= LOOP =================

void loop() {

  readCommand();

  static unsigned long lastSenseTime = 0;

  if (millis() - lastSenseTime > 500) {

    float instantaneousRes = readResistance();

    if (abs(instantaneousRes - candidateResistance) < 50.0) {
      stableCounter++;
    } else {
      candidateResistance = instantaneousRes;
      stableCounter = 0;
    }

    if (stableCounter >= STABLE_REQUIRED) {

      float delta = abs(candidateResistance - currentStableResistance);

      if (delta > NOISE_THRESHOLD) {

        bool increased = (candidateResistance > currentStableResistance);

        Serial.printf("CHANGE | Current %.2f | New %.2f | Delta %.2f\n",
                      currentStableResistance,
                      candidateResistance,
                      delta);

        if (increased) {

          // RETURN DETECTED
          currentState = STATE_VERIFYING_RETURN;

          String msg = "returned_" + String(delta,1);

          sendFirebase("/machines/" STATION_ID "/return", msg);
        }

        else if (!increased && currentState == STATE_WAITING_RETURN) {

          // RENT DETECTED
          currentState = STATE_RETURN_SUCCESS;

          triggerSolenoid(false);

          String msg = "rented_" + String(delta,1);

          sendFirebase("/machines/" STATION_ID "/status", msg);
        }

        currentStableResistance = candidateResistance;
      }

      stableCounter = 0;
    }

    lastSenseTime = millis();
  }

  updateLEDs();

  // Debug heartbeat
  static unsigned long lastHeartbeat = 0;

  if (millis() - lastHeartbeat > 2000) {

    Serial.printf("SENSE | Stable %.1f | Candidate %.1f | Count %d | STATE %d\n",
                  currentStableResistance,
                  candidateResistance,
                  stableCounter,
                  currentState);

    lastHeartbeat = millis();
  }
}

// ================= FIREBASE SEND =================

void sendFirebase(String path, String value) {

  if (Firebase.RTDB.setString(&fbdo, path, value)) {

    Serial.println("Firebase Updated: " + path + " -> " + value);

  } else {

    Serial.println("Firebase Error: " + fbdo.errorReason());
  }
}

// ================= FIREBASE COMMAND READ =================

void readCommand() {

  String path = "/machines/" STATION_ID "/command";

  if (Firebase.RTDB.getString(&fbdo, path)) {

    String cmd = fbdo.stringData();

    if (cmd == "rent") {

      currentState = STATE_WAITING_RETURN;
      triggerSolenoid(true);

      sendFirebase(path, "none");
    }

    if (cmd == "waiting") {

      currentState = STATE_WAITING_CONFIRMATION;

      sendFirebase(path, "none");
    }

    if (cmd == "confirmed") {

      currentState = STATE_RENTAL_SUCCESS;

      delay(3000);

      currentState = STATE_IDLE_LOCKED;

      sendFirebase(path, "none");
    }

    if (cmd == "reset") {

      currentState = STATE_IDLE_LOCKED;

      triggerSolenoid(false);

      sendFirebase(path, "none");
    }
  }
}

// ================= LED CONTROL =================

void updateLEDs() {

  unsigned long now = millis();

  switch(currentState) {

    case STATE_IDLE_LOCKED:
      // RED Slow blink (1s ON / 1s OFF)
      if (now - lastBlinkTime > 1000) {
        blinkState = !blinkState;
        digitalWrite(PIN_RED, blinkState ? HIGH : LOW);
        digitalWrite(PIN_GREEN, LOW);
        lastBlinkTime = now;
      }
      break;

    case STATE_WAITING_CONFIRMATION:
      // ORANGE Fast blink (200ms ON / 200ms OFF)
      if (now - lastBlinkTime > 200) {
        blinkState = !blinkState;
        digitalWrite(PIN_RED, blinkState ? HIGH : LOW);
        digitalWrite(PIN_GREEN, blinkState ? HIGH : LOW);
        lastBlinkTime = now;
      }
      break;

    case STATE_RENTAL_SUCCESS:
      // GREEN Solid ON
      digitalWrite(PIN_RED, LOW);
      digitalWrite(PIN_GREEN, HIGH);
      break;

    case STATE_WAITING_RETURN:
      // GREEN Slow blink (1s ON / 1s OFF)
      if (now - lastBlinkTime > 1000) {
        blinkState = !blinkState;
        digitalWrite(PIN_RED, LOW);
        digitalWrite(PIN_GREEN, blinkState ? HIGH : LOW);
        lastBlinkTime = now;
      }
      break;

    case STATE_VERIFYING_RETURN:
      // ORANGE Medium blink (500ms ON / 500ms OFF)
      if (now - lastBlinkTime > 500) {
        blinkState = !blinkState;
        digitalWrite(PIN_RED, blinkState ? HIGH : LOW);
        digitalWrite(PIN_GREEN, blinkState ? HIGH : LOW);
        lastBlinkTime = now;
      }
      break;

    case STATE_RETURN_SUCCESS:
      // GREEN Double blink (2 quick blinks, then pause)
      static unsigned long patternStart = 0;
      if (patternStart == 0) patternStart = now;
      unsigned long elapsed = now - patternStart;
      if (elapsed < 200) {
        digitalWrite(PIN_RED, LOW);
        digitalWrite(PIN_GREEN, HIGH);
      } else if (elapsed < 400) {
        digitalWrite(PIN_RED, LOW);
        digitalWrite(PIN_GREEN, LOW);
      } else if (elapsed < 600) {
        digitalWrite(PIN_RED, LOW);
        digitalWrite(PIN_GREEN, HIGH);
      } else if (elapsed < 800) {
        digitalWrite(PIN_RED, LOW);
        digitalWrite(PIN_GREEN, LOW);
      } else if (elapsed < 2800) {
        digitalWrite(PIN_RED, LOW);
        digitalWrite(PIN_GREEN, LOW);
      } else {
        patternStart = now;
      }
      break;
  }
}

// ================= SOLENOID =================

void triggerSolenoid(bool on) {

  digitalWrite(PIN_LOCK, on ? HIGH : LOW);

  Serial.println(on ? "LOCK OPEN" : "LOCK CLOSED");
}

// ================= WIFI =================

void setup_wifi() {

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  Serial.print("Connecting WiFi");

  while (WiFi.status() != WL_CONNECTED) {

    delay(500);
    Serial.print(".");
  }

  Serial.println();
  Serial.println("WiFi Connected");

  Serial.println(WiFi.localIP());
}

// ================= SENSOR =================

float readResistance() {

  long sum = 0;

  for (int i = 0; i < 20; i++) {

    sum += analogRead(PIN_ADC);
    delay(5);
  }

  float v = ((sum / 20.0) / 1023.0) * V_REF;

  if (v >= (V_REF - 0.1) || v <= 0.05)
    return -1.0;

  return R_FIXED * (v / (V_REF - v));
}