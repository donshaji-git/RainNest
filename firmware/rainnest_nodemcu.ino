/*
 * RainNest NodeMCU Firmware
 * Controls the physical umbrella station and syncs with Firebase Firestore.
 * 
 * Required Library: Firebase-ESP-Client by Mobizt
 * Board: NodeMCU 1.0 (ESP-12E Module)
 */

#include <Arduino.h>
#if defined(ESP8266)
  #include <ESP8266WiFi.h>
#elif defined(ESP32)
  #include <WiFi.h>
#endif

#include <Firebase_ESP_Client.h>
#include <addons/TokenHelper.h>
#include "config.h"

// Firebase Objects
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

unsigned long lastUpdate = 0;
const int updateInterval = 10000; // 10 seconds

// Slot Pins (Solenoids/Locks)
const int slotPins[] = {D1, D2, D3, D4}; // Pins for 4 slots
const int numSlots = 4;

void setup() {
  Serial.begin(115200);
  
  // Setup Pins
  for(int i=0; i<numSlots; i++) {
    pinMode(slotPins[i], OUTPUT);
    digitalWrite(slotPins[i], LOW); // Ensure locked by default
  }

  // WiFi Connectivity
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    Serial.print(".");
    delay(300);
  }
  Serial.println("\nConnected to WiFi");

  // Firebase Configuration
  config.api_key = FIREBASE_API_KEY;
  config.token_status_callback = tokenStatusCallback;
  
  // Assign Anonymous User for simplest access (Ensure Anonymous Auth is enabled in Firebase Console)
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);
}

void loop() {
  // 1. Monitor Station document in Firestore
  // 2. Control Solenoids based on 'queueOrder' or 'locks' command
  // 3. Update 'availableCount' and 'freeSlotsCount' in real-time
  
  if (Firebase.ready() && (millis() - lastUpdate > updateInterval || lastUpdate == 0)) {
    lastUpdate = millis();
    
    String path = "stations/" + String(STATION_ID);
    Serial.print("Checking station: ");
    Serial.println(STATION_ID);

    if (Firebase.Firestore.getDocument(&fbdo, FIREBASE_PROJECT_ID, "", path.c_str(), "")) {
      Serial.println(fbdo.payload());
      // TODO: Parse JSON payload to extract queueOrder and command locks
    } else {
      Serial.println(fbdo.errorReason());
    }
  }
}
