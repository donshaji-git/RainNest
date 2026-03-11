/*
 * RainNest NodeMCU Firmware - Stable Version
 * High-stability sensing and precise state machine logic for HiveMQ.
 */

#include <Arduino.h>
#include <ESP8266WiFi.h>
#include <PubSubClient.h>
#include <WiFiClientSecure.h>

// ============== CONFIGURATION ==============
#define WIFI_SSID "Don Shaji"
#define WIFI_PASSWORD "12345678901"

#define MQTT_HOST "5dcff0a40cde4433b2338f804ba753cf.s1.eu.hivemq.cloud"
#define MQTT_PORT 8883
#define MQTT_USER "rainnest"
#define MQTT_PASS "Rainnest123"

#define STATION_ID "machine1"

// Pin Definitions
#define PIN_RED D5
#define PIN_GREEN D6
#define PIN_LOCK D1
#define PIN_ADC A0

// Sensing Constants
#define R_FIXED 10000.0 
#define V_REF 3.3       
#define NOISE_THRESHOLD 100.0 // 100 Ohm threshold to ignore noise
#define STABLE_REQUIRED 5     // Must be stable for 5 loops (approx 2.5s)

// MQTT Topics
const char* TOPIC_RENT = "rainnest/" STATION_ID "/rent";
const char* TOPIC_RETURN = "rainnest/" STATION_ID "/return";
const char* TOPIC_STATUS = "rainnest/" STATION_ID "/status";
const char* TOPIC_COMMAND = "rainnest/" STATION_ID "/command";

// ============== GLOBALS ==============
WiFiClientSecure espClient;
PubSubClient client(espClient);

float currentStableResistance = 0.0;
float candidateResistance = 0.0;
int stableCounter = 0;

enum SystemState {
  STATE_IDLE,        // Red Solid, Locked
  STATE_WAITING,     // Orange Blink (App scanned)
  STATE_RENTING,     // Solenoid ON, Orange Blink
  STATE_REMOVED,     // Solenoid OFF, Waiting for app confirmation
  STATE_CONFIRMED,   // Green Solid (Success)
  STATE_RETURNING    // Green Blink (Umbrella inserted, waiting app)
};

SystemState currentState = STATE_IDLE;

// ============== FUNCTION PROTOTYPES ==============
void setup_wifi();
void callback(char* topic, byte* payload, unsigned int length);
void reconnect();
float readResistance();
void updateLEDs();
void triggerSolenoid(bool on);

// ============== SETUP ==============
void setup() {
  Serial.begin(115200);
  pinMode(PIN_RED, OUTPUT);
  pinMode(PIN_GREEN, OUTPUT);
  pinMode(PIN_LOCK, OUTPUT);
  pinMode(PIN_ADC, INPUT);

  triggerSolenoid(false);
  
  setup_wifi();
  espClient.setInsecure(); 
  client.setServer(MQTT_HOST, MQTT_PORT);
  client.setCallback(callback);

  currentStableResistance = readResistance();
  candidateResistance = currentStableResistance;
  Serial.println("Initial stable resistance: " + String(currentStableResistance));
}

// ============== LOOP ==============
void loop() {
  if (!client.connected()) reconnect();
  client.loop();

  // 1. Precise Stable Sensing Logic
  static unsigned long lastSenseTime = 0;
  if (millis() - lastSenseTime > 500) { 
    float instantaneousRes = readResistance();
    
    // Check if the reading is near our "candidate"
    if (abs(instantaneousRes - candidateResistance) < 50.0) {
      stableCounter++;
    } else {
      candidateResistance = instantaneousRes;
      stableCounter = 0;
    }

    // committing to a new stable value
    if (stableCounter >= STABLE_REQUIRED) {
      float delta = abs(candidateResistance - currentStableResistance);
      
      if (delta > NOISE_THRESHOLD) {
        bool increased = (candidateResistance > currentStableResistance);
        Serial.printf("STABLE CHANGE | Current: %.2f | New: %.2f | Delta: %.2f | %s\n", 
                      currentStableResistance, candidateResistance, delta, increased ? "ADDED" : "REMOVED");

        if (increased) {
          // --- RETURN DETECTED ---
          currentState = STATE_RETURNING;
          String msg = "returned_" + String(delta, 1);
          client.publish(TOPIC_RETURN, msg.c_str());
        } 
        else if (!increased && currentState == STATE_RENTING) {
          // --- RENT DETECTED (PHYSICAL REMOVAL) ---
          currentState = STATE_REMOVED;
          triggerSolenoid(false);
          String msg = "rented_" + String(delta, 1);
          client.publish(TOPIC_STATUS, msg.c_str());
        }
        
        currentStableResistance = candidateResistance;
      }
      stableCounter = 0;
    }
    lastSenseTime = millis();
  }

  // Debug Heartbeat
  static unsigned long lastHeartbeat = 0;
  if (millis() - lastHeartbeat > 2000) {
    Serial.printf("SENSE | Stable: %.1f | Candidate: %.1f | Count: %d | STATE: %d\n", 
                  currentStableResistance, candidateResistance, stableCounter, currentState);
    lastHeartbeat = millis();
  }

  // 2. LED Animation Logic
  updateLEDs();
}

// ============== MQTT CALLBACK ==============
void callback(char* topic, byte* payload, unsigned int length) {
  String msg = "";
  for (int i = 0; i < length; i++) msg += (char)payload[i];
  String t = String(topic);

  Serial.println("MQTT ["+t+"] -> " + msg);

  if (t == TOPIC_RENT && msg == "request") {
    currentState = STATE_RENTING;
    triggerSolenoid(true);
  } 
  else if (t == TOPIC_COMMAND) {
    if (msg == "waiting") {
      currentState = STATE_WAITING;
    } else if (msg == "confirmed") {
      currentState = STATE_CONFIRMED;      
      delay(3000); // Hold green for 3s
      currentState = STATE_IDLE;
    } else if (msg == "reset" || msg == "error") {
      currentState = STATE_IDLE;
      triggerSolenoid(false);
    }
  }
}

// ============== HELPERS ==============
void updateLEDs() {
  static unsigned long lastBlink = 0;
  static bool toggle = false;
  unsigned long now = millis();

  switch(currentState) {
    case STATE_IDLE:
      digitalWrite(PIN_RED, HIGH);
      digitalWrite(PIN_GREEN, LOW);
      break;

    case STATE_WAITING:
    case STATE_RENTING:
      // Orange Blink (Red + Green)
      if (now - lastBlink > 300) {
        toggle = !toggle;
        digitalWrite(PIN_RED, toggle);
        digitalWrite(PIN_GREEN, toggle);
        lastBlink = now;
      }
      break;

    case STATE_REMOVED:
    case STATE_RETURNING:
      // Green Blink
      if (now - lastBlink > 300) {
        toggle = !toggle;
        digitalWrite(PIN_RED, LOW);
        digitalWrite(PIN_GREEN, toggle);
        lastBlink = now;
      }
      break;

    case STATE_CONFIRMED:
      digitalWrite(PIN_RED, LOW);
      digitalWrite(PIN_GREEN, HIGH);
      break;
  }
}

void triggerSolenoid(bool on) {
  digitalWrite(PIN_LOCK, on ? HIGH : LOW);
  Serial.println(on ? "LOCK OPEN" : "LOCK CLOSED");
}

void setup_wifi() {
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }
  Serial.println("\nWiFi IP: " + WiFi.localIP().toString());
}

void reconnect() {
  while (!client.connected()) {
    if (client.connect(STATION_ID, MQTT_USER, MQTT_PASS)) {
      client.subscribe(TOPIC_RENT);
      client.subscribe(TOPIC_COMMAND);
      Serial.println("MQTT CONNECTED");
    } else { delay(5000); }
  }
}

float readResistance() {
  long sum = 0;
  for (int i = 0; i < 20; i++) { sum += analogRead(PIN_ADC); delay(5); }
  float v = ( (sum / 20.0) / 1023.0) * V_REF;
  if (v >= (V_REF - 0.1) || v <= 0.05) return -1.0;
  return R_FIXED * (v / (V_REF - v));
}
