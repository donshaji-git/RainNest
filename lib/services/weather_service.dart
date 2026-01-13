import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../data/models/weather_models.dart';

class WeatherService {
  static final String _apiKey = dotenv.env['OPEN_WEATHER_API_KEY'] ?? '';
  static const String _baseUrl =
      'https://api.openweathermap.org/data/3.0/onecall';

  /// Fetch weather data using OpenWeather One Call API 3.0
  static Future<WeatherData?> fetchWeather(double lat, double lon) async {
    if (_apiKey.isEmpty) {
      debugPrint('Weather Error: API key not found in .env file');
      return null;
    }

    final url = Uri.parse(
      '$_baseUrl?lat=$lat&lon=$lon&appid=$_apiKey&units=metric&exclude=minutely,daily,alerts',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return WeatherData.fromJson(data);
      } else {
        debugPrint(
          'Weather API Error: ${response.statusCode} - ${response.body}',
        );
        return null;
      }
    } catch (e) {
      debugPrint('Weather Error: $e');
      return null;
    }
  }

  /// Get weather icon based on condition
  static String getWeatherIcon(String condition) {
    switch (condition.toLowerCase()) {
      case 'rain':
      case 'drizzle':
        return '🌧️';
      case 'clear':
        return '☀️';
      case 'clouds':
        return '☁️';
      case 'snow':
        return '❄️';
      case 'thunderstorm':
        return '⛈️';
      case 'mist':
      case 'fog':
      case 'haze':
        return '🌫️';
      default:
        return '🌤️';
    }
  }

  /// Check if severe weather conditions exist
  static bool isSevereWeather(WeatherData weather) {
    // Weather codes for severe conditions
    // 200-299: Thunderstorm
    // 500-531: Rain (heavy rain 502-504, 511, 521-531)
    // 600-622: Snow
    // 771: Squalls
    // 781: Tornado

    if (weather.weatherCode >= 200 && weather.weatherCode < 300) {
      return true; // Thunderstorm
    }
    if (weather.weatherCode >= 502 && weather.weatherCode <= 531) {
      return true; // Heavy rain
    }
    if (weather.weatherCode >= 600 && weather.weatherCode < 700) {
      return true; // Snow
    }
    if (weather.weatherCode == 771 || weather.weatherCode == 781) {
      return true; // Squalls or Tornado
    }
    if (weather.windSpeed > 15.0) {
      return true; // High winds (>54 km/h)
    }

    return false;
  }

  /// Check for significant temperature change
  static bool hasSignificantTempChange(
    double currentTemp,
    double previousTemp,
  ) {
    final diff = (currentTemp - previousTemp).abs();
    return diff >= 5.0; // 5°C or more change
  }
}
