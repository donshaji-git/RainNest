# RainNest NodeMCU Firmware

This directory contains the source code for the NodeMCU (ESP8266) that controls the physical umbrella station.

## Prerequisites

1.  **Arduino IDE**: [Download here](https://www.arduino.cc/en/software)
2.  **ESP8266 Board Core**: Add `http://arduino.esp8266.com/stable/package_esp8266com_index.json` to Additional Boards Manager URLs in Preferences.
3.  **Required Library**:
    - `Firebase-ESP-Client` by Mobizt (Install via Library Manager)

## Setup Instructions

1.  Open `rainnest_nodemcu.ino` in Arduino IDE.
2.  Edit `config.h` to include your:
    - **WiFi SSID**
    - **WiFi Password**
3.  Select Board: `NodeMCU 1.0 (ESP-12E Module)`.
4.  Connect your NodeMCU via USB and click **Upload**.

## Hardware Mapping

- **D1 - D4**: Connected to the solenoid locks for individual slots.
- **Baud Rate**: 115200

## Firebase Integration

The firmware uses the **Firestore REST API** provided by the `Firebase-ESP-Client` library. It listens for updates to the station document to know when to unlock a slot for a user.
