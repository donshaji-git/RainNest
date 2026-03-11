import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'database_service.dart';
import 'mqtt_service.dart';
import 'package:firebase_database/firebase_database.dart';

class MqttBridgeService {
  static final MqttBridgeService _instance = MqttBridgeService._internal();
  factory MqttBridgeService() => _instance;

  MqttBridgeService._internal();

  final MqttService _mqtt = MqttService();
  final DatabaseService _db = DatabaseService();
  bool _isInitialized = false;

  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;

    debugPrint('MqttBridgeService: Initializing bridge...');
    _mqtt.connect().then((connected) {
      if (connected) {
        // Subscribe to return and status topics for all machines
        _mqtt.subscribe('rainnest/+/return');
        _mqtt.subscribe('rainnest/+/status');
        
        // Listen for incoming messages
        _mqtt.messageStream.listen((MqttReceivedMessage<MqttMessage> event) {
          final String topic = event.topic;
          final MqttPublishMessage recMess = event.payload as MqttPublishMessage;
          final String payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
          
          _handleMqttMessage(topic, payload);
        });
      }
    });
  }

  void _handleMqttMessage(String topic, String payload) {
    debugPrint("MqttBridge: Incoming -> $topic: $payload");
    
    // Pattern: rainnest/<machineID>/return or rainnest/<machineID>/status
    final segments = topic.split('/');
    if (segments.length >= 3 && segments[0] == 'rainnest') {
      final stationId = segments[1];
      final type = segments[2];
      
      if (type == 'return' && payload.startsWith('returned_')) {
        final umbrellaId = payload.substring(9);
        _processReturn(stationId, umbrellaId);
      } else if (type == 'status' && payload.startsWith('rented_')) {
        final umbrellaId = payload.substring(7);
        _processRentalStatus(stationId, umbrellaId);
      }
    }
  }

  Future<void> _processReturn(String stationId, String umbrellaId) async {
    try {
      debugPrint("MqttBridge: Detected return of Umbrella $umbrellaId at $stationId");
      final rentals = await _db.getActiveRentalsForUmbrella(umbrellaId);
            
      if (rentals.isNotEmpty) {
        final tx = rentals.first;
        // The return is valid for this umbrella
        await _db.processFullReturn(
          transactionId: tx.transactionId,
          userId: tx.userId,
          stationId: stationId,
          umbrellaId: umbrellaId,
        );
        // Send confirmation back to machine to signal success (Solid Green)
        _mqtt.publish('rainnest/$stationId/command', 'confirmed');
      } else {
        debugPrint("MqttBridge: WRONG UMBRELLA return detected for $umbrellaId at $stationId");
        // Update Firestore or notify user about wrong umbrella
        await _db.updateUmbrellaFromHardware(
          umbrellaId: umbrellaId,
          stationId: stationId,
          status: 'wrong_return_detected',
        );
        // Could send a 'reset' or 'error' message to machine
        _mqtt.publish('rainnest/$stationId/command', 'reset');
      }
    } catch (e) {
      debugPrint("MqttBridge: Error processing return: $e");
    }
  }

  Future<void> _processRentalStatus(String stationId, String umbrellaId) async {
    try {
      debugPrint("MqttBridge: Umbrella $umbrellaId rented from $stationId");
      
      // 1. Update Firebase to sync physical state
      await FirebaseDatabase.instance.ref('stations/$stationId').update({
        'last_rented_umbrella': umbrellaId,
        'physical_status': 'umbrella_removed',
        'last_sync': ServerValue.timestamp,
      });

      // 2. Feedback Loop: Send 'confirmed' to Machine to turn LED Solid Green
      _mqtt.publish('rainnest/$stationId/command', 'confirmed');
      
    } catch (e) {
      debugPrint("MqttBridge: Error processing rental status: $e");
    }
  }
}
