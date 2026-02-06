import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'services/database_service.dart';
import 'presentation/pages/login_page.dart';
import 'presentation/pages/umbrella_map_page.dart';
import 'presentation/pages/login_details_page.dart';
import 'presentation/widgets/rainfall_loading.dart';
import 'presentation/pages/home_page.dart';
import 'presentation/constants/admin_constants.dart';

import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'providers/location_provider.dart';
import 'providers/weather_provider.dart';
import 'providers/station_provider.dart';
import 'providers/map_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await dotenv.load(fileName: ".env");

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocationProvider()),
        ChangeNotifierProvider(create: (_) => WeatherProvider()),
        ChangeNotifierProvider(create: (_) => StationProvider()),
        ChangeNotifierProvider(create: (_) => MapProvider()),
      ],
      child: const RainNestApp(),
    ),
  );
}

class RainNestApp extends StatelessWidget {
  const RainNestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RainNest',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Outfit', // A modern font would be better
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  String? _lastUid;
  bool? _userExists;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const RainfallLoading();
        }

        final User? user = snapshot.data;

        if (user == null) {
          _lastUid = null;
          _userExists = null;
          return const LoginPage();
        }

        // Handle Admin Bypass
        if (AdminConstants.isAdmin(user.email)) {
          return const UmbrellaMapPage();
        }

        // For regular users, check/cache existence
        if (_lastUid != user.uid) {
          _lastUid = user.uid;
          _userExists = null;
          _checkUserExists(user.uid);
        }

        if (_isLoading || _userExists == null) {
          return const RainfallLoading();
        }

        if (_userExists == true) {
          return const HomePage();
        } else {
          return const LoginDetailsPage();
        }
      },
    );
  }

  Future<void> _checkUserExists(String uid) async {
    // Avoid multiple concurrent checks
    if (_isLoading) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _isLoading = true);
    });

    try {
      final exists = await DatabaseService().userExists(uid);
      if (!mounted) return;
      setState(() {
        _userExists = exists;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _userExists = false; // Default to registration on error
        _isLoading = false;
      });
    }
  }
}
