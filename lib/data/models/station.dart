class Station {
  final String stationId;
  final String name;
  final String description;
  final int totalSlots;
  final int availableCount;
  final int freeSlotsCount;
  final List<String> queueOrder; // FIFO: array of umbrella IDs
  final String machineQrCode;
  final double latitude;
  final double longitude;

  Station({
    required this.stationId,
    required this.name,
    required this.description,
    required this.totalSlots,
    required this.availableCount,
    required this.freeSlotsCount,
    required this.queueOrder,
    required this.machineQrCode,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toMap() {
    return {
      'stationId': stationId,
      'name': name,
      'description': description,
      'totalSlots': totalSlots,
      'availableCount': availableCount,
      'freeSlotsCount': freeSlotsCount,
      'queueOrder': queueOrder,
      'machineQrCode': machineQrCode,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory Station.fromMap(Map<String, dynamic> data, String id) {
    return Station(
      stationId: id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      totalSlots: data['totalSlots'] ?? 0,
      availableCount: data['availableCount'] ?? 0,
      freeSlotsCount: data['freeSlotsCount'] ?? 0,
      queueOrder: List<String>.from(data['queueOrder'] ?? []),
      machineQrCode: data['machineQrCode'] ?? '',
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
