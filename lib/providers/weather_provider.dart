import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../data/models/weather_models.dart';
import '../services/weather_service.dart';
import '../services/notification_service.dart';

class WeatherProvider with ChangeNotifier {
  WeatherData? _currentWeather;
  bool _isLoading = false;
  String? _errorMessage;
  DateTime? _lastUpdate;
  bool _hasShownRainAlert = false;
  double? _previousTemperature;

  WeatherData? get currentWeather => _currentWeather;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  DateTime? get lastUpdate => _lastUpdate;
  bool get hasWeather => _currentWeather != null;
  bool get hasRainAlert => _currentWeather?.hasRainAlert ?? false;

  String get greeting {
    if (_currentWeather == null) return 'Welcome back 👋';

    final condition = _currentWeather!.condition.toLowerCase();
    // Check key conditions first
    if (condition.contains('rain') ||
        condition.contains('drizzle') ||
        condition.contains('thunder')) {
      return 'Carry an umbrella ☔';
    } else if (condition.contains('cloud') || condition.contains('overcast')) {
      return 'Cloudy skies ahead ☁️';
    } else if (condition.contains('clear') || condition.contains('sunny')) {
      return 'Perfect weather today ☀️';
    } else if (condition.contains('wind') || _currentWeather!.windSpeed > 10) {
      return 'Windy outside 💨';
    } else if (condition.contains('snow')) {
      return 'Snowy day ahead ❄️';
    }

    return 'Have a great day! ✨';
  }

  /// Fetch weather for given location
  Future<void> fetchWeather(LatLng location) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final weather = await WeatherService.fetchWeather(
        location.latitude,
        location.longitude,
      );

      if (weather != null) {
        _currentWeather = weather;
        _lastUpdate = DateTime.now();
        _errorMessage = null;

        // Check and send notifications
        await _checkAndNotify(weather);
      } else {
        _errorMessage = 'Unable to fetch weather data';
      }
    } catch (e) {
      _errorMessage = 'Error fetching weather: $e';
      debugPrint(_errorMessage);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Check weather conditions and send notifications
  Future<void> _checkAndNotify(WeatherData weather) async {
    // Rain alert
    if (weather.hasRainAlert && !_hasShownRainAlert) {
      await NotificationService.sendRainAlert(
        title: '🌧️ Rain Alert!',
        body: 'Rain expected near you. Carry an umbrella.',
      );
      _hasShownRainAlert = true;
    } else if (!weather.hasRainAlert) {
      _hasShownRainAlert = false; // Reset when no rain
    }

    // Severe weather
    if (WeatherService.isSevereWeather(weather)) {
      await NotificationService.sendWeatherWarning(
        title: '⚠️ Severe Weather Warning',
        body: '${weather.condition}: ${weather.description}. Stay safe!',
      );
    }

    // Temperature change
    if (_previousTemperature != null) {
      if (WeatherService.hasSignificantTempChange(
        weather.temperature,
        _previousTemperature!,
      )) {
        final change = weather.temperature - _previousTemperature!;
        final direction = change > 0 ? 'risen' : 'dropped';
        await NotificationService.sendTemperatureAlert(
          title: '🌡️ Temperature Change',
          body:
              'Temperature has $direction by ${change.abs().toStringAsFixed(1)}°C',
        );
      }
    }
    _previousTemperature = weather.temperature;
  }

  /// Refresh weather data
  Future<void> refreshWeather(LatLng location) async {
    await fetchWeather(location);
  }

  /// Clear weather data
  void clearWeather() {
    _currentWeather = null;
    _lastUpdate = null;
    _errorMessage = null;
    _hasShownRainAlert = false;
    notifyListeners();
  }
}
