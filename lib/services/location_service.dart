import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class SearchResult {
  final String name;
  final LatLng location;

  SearchResult({required this.name, required this.location});
}

class LocationService {
  static Future<List<SearchResult>> searchPlaces(String query) async {
    if (query.isEmpty) return [];

    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=5',
    );

    try {
      final response = await http.get(
        url,
        headers: {'User-Agent': 'RainNest-Admin-App'},
      );

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        return data.map((item) {
          return SearchResult(
            name: item['display_name'],
            location: LatLng(
              double.parse(item['lat']),
              double.parse(item['lon']),
            ),
          );
        }).toList();
      }
    } catch (e) {
      print('Search Error: $e');
    }
    return [];
  }
}
