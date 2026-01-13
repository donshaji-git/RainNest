class WeatherData {
  final double temperature;
  final String condition;
  final String description;
  final int weatherCode;
  final String icon;
  final double feelsLike;
  final int humidity;
  final double windSpeed;
  final String cityName;
  final List<HourlyForecast> hourlyForecasts;

  WeatherData({
    required this.temperature,
    required this.condition,
    required this.description,
    required this.weatherCode,
    required this.icon,
    required this.feelsLike,
    required this.humidity,
    required this.windSpeed,
    required this.cityName,
    required this.hourlyForecasts,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    final current = json['current'];
    final hourly = json['hourly'] as List;

    return WeatherData(
      temperature: (current['temp'] as num).toDouble(),
      condition: current['weather'][0]['main'] as String,
      description: current['weather'][0]['description'] as String,
      weatherCode: current['weather'][0]['id'] as int,
      icon: current['weather'][0]['icon'] as String,
      feelsLike: (current['feels_like'] as num).toDouble(),
      humidity: current['humidity'] as int,
      windSpeed: (current['wind_speed'] as num).toDouble(),
      cityName: '', // Will be set from reverse geocoding if needed
      hourlyForecasts: hourly
          .take(24)
          .map((h) => HourlyForecast.fromJson(h))
          .toList(),
    );
  }

  /// Rain alert logic:
  /// - Rain expected within 15 minutes (checking the first hourly forecast as proxy)
  /// - Rain probability today > 40%
  bool get hasRainAlert {
    if (hourlyForecasts.isEmpty) return false;

    // Condition 1: Short-term rain (next hour)
    final nextHour = hourlyForecasts.first;
    if (nextHour.condition == 'Rain') return true;

    // Condition 2: Probability-based rain (> 40% in any of the next 12 hours)
    for (var i = 0; i < 12 && i < hourlyForecasts.length; i++) {
      if (hourlyForecasts[i].rainProbability >= 0.40) {
        return true;
      }
    }

    return false;
  }
}

class HourlyForecast {
  final DateTime time;
  final double temperature;
  final String condition;
  final String description;
  final String icon;
  final double rainProbability;

  HourlyForecast({
    required this.time,
    required this.temperature,
    required this.condition,
    required this.description,
    required this.icon,
    required this.rainProbability,
  });

  factory HourlyForecast.fromJson(Map<String, dynamic> json) {
    return HourlyForecast(
      time: DateTime.fromMillisecondsSinceEpoch((json['dt'] as int) * 1000),
      temperature: (json['temp'] as num).toDouble(),
      condition: json['weather'][0]['main'] as String,
      description: json['weather'][0]['description'] as String,
      icon: json['weather'][0]['icon'] as String,
      rainProbability: (json['pop'] as num).toDouble(),
    );
  }
}
