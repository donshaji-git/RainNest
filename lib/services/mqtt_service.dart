import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;

  MqttService._internal();

  MqttServerClient? _client;
  bool _isConnected = false;

  final String _host = '5dcff0a40cde4433b2338f804ba753cf.s1.eu.hivemq.cloud';
  final int _port = 8883;
  final String _username = 'rainnest';
  final String _password = 'Rainnest123';
  final String _clientId = 'RainNestApp_${DateTime.now().millisecondsSinceEpoch}';

  bool get isConnected => _isConnected;

  final StreamController<MqttReceivedMessage<MqttMessage>> _messageController =
      StreamController<MqttReceivedMessage<MqttMessage>>.broadcast();

  Stream<MqttReceivedMessage<MqttMessage>> get messageStream =>
      _messageController.stream;

  Future<bool> connect() async {
    if (_isConnected) return true;

    _client = MqttServerClient.withPort(_host, _clientId, _port);
    _client!.logging(on: false);
    _client!.useWebSocket = false;
    _client!.secure = true;
    _client!.keepAlivePeriod = 20;
    _client!.port = _port;
    _client!.onDisconnected = _onDisconnected;
    _client!.onConnected = _onConnected;
    _client!.onSubscribed = _onSubscribed;

    final connMess = MqttConnectMessage()
        .withClientIdentifier(_clientId)
        .authenticateAs(_username, _password)
        .withWillTopic('willtopic')
        .withWillMessage('My Will message')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    debugPrint('MqttService: Connecting to HiveMQ...');
    _client!.connectionMessage = connMess;

    try {
      await _client!.connect();
    } on NoConnectionException catch (e) {
      debugPrint('MqttService: client exception - $e');
      _client!.disconnect();
    } on SocketException catch (e) {
      debugPrint('MqttService: socket exception - $e');
      _client!.disconnect();
    }

    if (_client!.connectionStatus!.state == MqttConnectionState.connected) {
      debugPrint('MqttService: HiveMQ client connected');
      _isConnected = true;

      // Listen for messages
      _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
        final recMess = c[0];
        _messageController.add(recMess);
      });
    } else {
      debugPrint(
          'MqttService: ERROR HiveMQ client connection failed - disconnecting, state is ${_client!.connectionStatus!.state}');
      _client!.disconnect();
      _isConnected = false;
    }

    return _isConnected;
  }

  void subscribe(String topic) {
    if (_isConnected) {
      debugPrint('MqttService: Subscribing to $topic');
      _client?.subscribe(topic, MqttQos.atLeastOnce);
    }
  }

  void _onConnected() {
    debugPrint('MqttService: Connected');
    _isConnected = true;
  }

  void _onDisconnected() {
    debugPrint('MqttService: Disconnected');
    _isConnected = false;
  }

  void _onSubscribed(String topic) {
    debugPrint('MqttService: Subscribed topic: $topic');
  }

  Future<void> publish(String topic, String message) async {
    if (!_isConnected) {
      bool connected = await connect();
      if (!connected) {
        debugPrint('MqttService: Cannot publish, not connected');
        return;
      }
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(message);

    debugPrint('MqttService: Publishing $message to $topic');
    _client?.publishMessage(topic, MqttQos.exactlyOnce, builder.payload!);
  }

  void disconnect() {
    _client?.disconnect();
    _isConnected = false;
  }
}
