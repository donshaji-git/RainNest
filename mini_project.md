ABSTRACT

Unpredictable weather patterns often catch urban commuters unprepared, leading to significant inconvenience and an over-reliance on disposable plastic umbrellas that contribute to environmental waste. This project, RainNest, aims to solve this problem by developing an IoT-based Smart Umbrella Rental System that provides automated, real-time access to high-quality umbrellas at public locations. An IoT-enabled station, powered by the NodeMCU ESP8266 microcontroller, utilizes a high-precision analog sensing network to measure internal resistance values for umbrella identification. Whenever a user interacts with the station, the device sends instantaneous status updates through a secure HiveMQ MQTT cloud broker using the high-speed and efficient MQTT protocol, ensuring sub-second response times for every transaction.

On the software side, the system is backed by a robust Firebase infrastructure integrated with a dedicated Flutter-based Middleware. This bridge service receives hardware readings via the MQTT broker, verifies umbrella IDs, and synchronizes the data with Firestore and Realtime Databases. It automatically handles complex logic such as calculating rental durations, verifying wallet balances, and tracking inventory across stations. The system ensures that data refreshes instantly as soon as a physical removal or return is detected, providing a seamless link between the mechanical hardware and the digital cloud database.

The system supports two distinct user types. Administrators have a complete view of the network nodes, allowing them to track station health across regions, monitor revenue, manage station inventory, and send remote hardware commands. General Users utilize a mobile interface to scan QR codes at stations, rent umbrellas, and manage a digital wallet. The app displays their active rental status, nearest available stations, and a coin-reward system for successful returns. Both user types are guided by useful information such as station availability maps and precautionary rental status alerts (locked / processing / success).

The mobile interface is developed using Flutter and follows the modern Material 3 design system. The app's structure uses a clean, visually clear design with intuitive alert colors (Red for locked / Orange for processing / Green for success). Using the Provider state management pattern, the system brings the rental flow to life by updating wallet balances instantly and refreshing station maps without requiring manual reloads. The frontend organizes information smoothly using data models such as Umbrella, User, and Transaction, ensuring a high-performance experience for both admins and users.

By combining high-speed cloud messaging with precise analog sensing and a user-focused mobile design, this project serves as a sophisticated urban mobility solution for smart cities. It enables quicker access to weather protection, encourages sustainable usage through its circular economy model, and improves the daily experience of urban commuters — ultimately helping to build smarter, more convenient, and more resilient urban environments.

---

CHAPTER 1: INTRODUCTION
 
1.1 PROJECT OVERVIEW

The RainNest project is a technologically advanced response to a common yet overlooked urban problem: the lack of timely access to weather protection. In many fast-growing smart cities, commuters frequently encounter sudden rainfall, forcing them into one of two inconvenient choices: waiting out the storm, which leads to lost productive time, or purchasing a low-quality "emergency" umbrella from a nearby vendor. These cheap umbrellas are often designed for single-use, leading to significant plastic waste and environmental degradation when they are discarded shortly after use. 

RainNest introduces an IoT-driven **Umbrella-as-a-Service (UaaS)** ecosystem that automates the entire lifecycle of an umbrella rental. By deploying automated kiosks at strategic locations such as bus stops, metro stations, and office complexes, the system ensures that high-quality, reusable umbrellas are always within reach. The core of the system is the RainNest IoT Station, which performs high-precision hardware verification to track inventory. This hardware is seamlessly linked to a cross-platform mobile application that manages user authentication, electronic payments, and real-time navigation to the nearest available kiosk. By leveraging modern cloud technologies like HiveMQ for high-speed messaging and Firebase for secure data persistence, RainNest sets a new standard for automated urban service delivery.

1.2 PROJECT SPECIFICATION

The RainNest system is specified to operate within a high-performance, low-latency environment to ensure a fluid user experience. The technical specifications of the project are as follows:

*   **Hardware Architecture:** The system utilizes a NodeMCU ESP8266 as the primary controller, interfacing with a 12V solenoid locking mechanism and a multi-stage analog resistor sensing network.
*   **Communication Protocol:** The system implements the Message Queuing Telemetry Transport (MQTT) protocol, specifically using a TLS-secured connection to a HiveMQ Cloud broker. This ensures that commands such as "Unlock" are executed in under one second.
*   **Backend & Storage:** A serverless architecture is utilized via Google Firebase. Firestore manages the persistent document database for users and transactions, while the Firebase Realtime Database handles live "Heartbeat" data from the IoT kiosks.
*   **Mobile Platform:** Developed using the Flutter framework (Dart), providing a unified experience across Android and iOS platforms. It includes features such as QR code scanning, Google Maps integration for kiosk location, and a digital coin-wallet system.
*   **Security:** Cross-platform security is handled via Firebase Authentication (Phone OTP and Google Sign-In) and TLS-encrypted MQTT packets.

---

CHAPTER 2: SYSTEM STUDY
 
2.1 INTRODUCTION

The system study for RainNest involves a rigorous analysis of the current landscape of public rental services and urban convenience. The primary objective is to evaluate how existing manual methods fail to meet the demands of a fast-paced smart city and to define the technical requirements for a fully automated alternative. This phase explores the feasibility of integrating physical hardware with cloud-based software, ensuring that the system can operate autonomously without human supervision. The study emphasizes the transition from human-centric management to data-driven automation, focusing on reliability, speed, and cost-effectiveness.

2.2 EXISTING SYSTEM

The traditional methods for obtaining rain protection in urban environments are predominantly manual and fragmented. Current options include:

*   **Manual Counter Rentals:** Certain hospitality venues or commercial buildings offer umbrella loans. This requires a human staff member to record personal details manually, usually in a physical logbook, and collect a cash deposit. 
*   **Convenience Store Purchases:** The most common "emergency" system involves purchasing a generic umbrella from a nearby retailer. This is a one-way transaction with no tracking once the user leaves the store.
*   **Public Loan Stands:** In some advanced cities, communal umbrella stands exist but operate on an "honor system" with no locking or tracking. These systems frequently suffer from 100% inventory loss within days.

2.2.1 NATURAL SYSTEM STUDIED

The "Natural System" refers to the spontaneous human behaviors and informal methods utilized when an individual is caught in unexpected rain without a designated piece of equipment. 

*   **Shelter Seeking:** The most common natural reaction is to seek temporary cover under building eaves, bus stops, or metro entrances. This leads to overcrowding of public walkways and significant delays in a commuter's schedule.
*   **Improvised Protection:** Commuters often use secondary items such as newspapers, bags, or jackets to cover their heads, which provides minimal protection and results in damage to the personal items used.
*   **Peer Sharing:** In some social contexts, individuals may share an umbrella with a friend or colleague, which is a limited solution based purely on proximity and chance.
*   **Constant Portability:** Many individuals choose to carry a personal umbrella at all times "just in case." This is inconvenient, adds weight to daily carry, and leads to umbrellas being frequently forgotten in public transport or restaurants once the rain stops.

2.2.2 DESIGNED SYSTEM STUDIED

The "Designed System" encompasses the existing engineered or commercial solutions currently available in the market. 

*   **Hospitality & Commercial Loan Systems:** High-end hotels and shopping malls often provide "loaner" umbrellas to their guests. These systems require a physical service desk, human verification of ID, and often a manual log entry. While reliable, they are limited to a specific building's footprint and business hours.
*   **Retail Vending:** Some airports and large malls feature umbrella vending machines. However, these are strictly "one-way" purchase machines. They do not allow for rental or return, meaning the user still ends up with a product they have to carry and eventually dispose of.
*   **Traditional Rental Startups:** Some existing app-based systems use manual verification where a user scans a code, but a human attendant must physically hand the umbrella. These lack the "drop-off anywhere" flexibility of a fully automated IoT network.
*   **Honor-System Stands:** Free-standing communal stands located in some "green" cities allow users to take an umbrella and return it voluntarily. Study shows these systems suffer from nearly 100% loss of inventory within the first week due to a lack of a tracking or locking mechanism.
