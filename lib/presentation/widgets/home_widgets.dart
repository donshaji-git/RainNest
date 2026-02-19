import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../../services/location_service.dart';
import '../../data/models/station.dart';

class HomeHeader extends StatelessWidget {
  final String username;
  const HomeHeader({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome back',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
          ),
          Text(
            username.isEmpty ? 'Friend' : username,
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class HomeSearch extends StatelessWidget {
  final Function(LatLng) onLocationSelected;

  const HomeSearch({super.key, required this.onLocationSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: TextField(
        onSubmitted: (value) async {
          final results = await LocationService.searchPlaces(value);
          if (results.isNotEmpty) {
            onLocationSelected(results.first.location);
          }
        },
        decoration: InputDecoration(
          hintText: 'Search for a location...',
          hintStyle: GoogleFonts.inter(color: Colors.grey[400], fontSize: 14),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFF0066FF),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }
}

class NearbyNestsSection extends StatelessWidget {
  final List<Station> machines;
  final LatLng? userLocation;
  final Function(Station) onKioskTapped;

  const NearbyNestsSection({
    super.key,
    required this.machines,
    this.userLocation,
    required this.onKioskTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Text(
            'Nearby Nests',
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: machines.length,
            itemBuilder: (context, index) {
              final loc = machines[index];
              return GestureDetector(
                onTap: () => onKioskTapped(loc),
                child: Container(
                  width: 250,
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.location_on,
                          color: Color(0xFF0066FF),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              loc.name,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              loc.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class AvailabilityGrid extends StatelessWidget {
  final int umbrellas;
  final int slots;

  const AvailabilityGrid({
    super.key,
    required this.umbrellas,
    required this.slots,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Row(
        children: [
          Expanded(
            child: _buildCard(
              'Available',
              umbrellas.toString(),
              Icons.umbrella,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildCard(
              'Free Slots',
              slots.toString(),
              Icons.grid_view_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF0066FF)),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}
