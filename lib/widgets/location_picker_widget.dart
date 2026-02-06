import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/place_service.dart';

/// 🗺️ Location Picker Widget - เลือกสถานที่บนแผนที่
///
/// Features:
/// - แสดงแผนที่ OpenStreetMap (ฟรี)
/// - ค้นหาสถานที่
/// - แสดง markers สถานที่ที่บันทึกไว้
/// - เลือกตำแหน่งโดยการแตะ

class LocationPickerWidget extends StatefulWidget {
  final LatLng? initialLocation;
  final Function(LatLng location, String? placeName)? onLocationSelected;
  final bool showSearch;
  final bool showSavedPlaces;
  final double height;

  const LocationPickerWidget({
    super.key,
    this.initialLocation,
    this.onLocationSelected,
    this.showSearch = true,
    this.showSavedPlaces = true,
    this.height = 300,
  });

  @override
  State<LocationPickerWidget> createState() => _LocationPickerWidgetState();
}

class _LocationPickerWidgetState extends State<LocationPickerWidget> {
  final PlaceService _placeService = PlaceService();
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  LatLng? _selectedLocation;
  String? _selectedPlaceName;
  List<PlaceResult> _searchResults = [];
  bool _isSearching = false;
  bool _isLoading = true;

  // Default to Bangkok
  static const LatLng _defaultLocation = LatLng(13.7563, 100.5018);

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    await _placeService.initialize();

    if (_selectedLocation == null) {
      // Try to get current location
      final position = await _placeService.getCurrentPosition();
      if (position != null) {
        _selectedLocation = LatLng(position.latitude, position.longitude);
      }
    }

    setState(() {
      _isLoading = false;
    });

    // Move map to selected location
    if (_selectedLocation != null) {
      _mapController.move(_selectedLocation!, 15);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Column(
      children: [
        // Search bar
        if (widget.showSearch) _buildSearchBar(theme),

        // Map
        SizedBox(
          height: widget.height,
          child: Stack(
            children: [
              // Map
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _selectedLocation ?? _defaultLocation,
                    initialZoom: 15,
                    onTap: _onMapTap,
                  ),
                  children: [
                    // OpenStreetMap tiles
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.haku.app',
                    ),

                    // Markers
                    MarkerLayer(
                      markers: _buildMarkers(),
                    ),
                  ],
                ),
              ),

              // Current location button
              Positioned(
                right: 8,
                bottom: 8,
                child: FloatingActionButton.small(
                  onPressed: _goToCurrentLocation,
                  backgroundColor: theme.colorScheme.surface,
                  child: Icon(
                    Icons.my_location,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),

              // Selected location info
              if (_selectedLocation != null && _selectedPlaceName != null)
                Positioned(
                  left: 8,
                  right: 56,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.place, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _selectedPlaceName!,
                            style: theme.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Search results
        if (_searchResults.isNotEmpty) _buildSearchResults(theme),
      ],
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'ค้นหาสถานที่...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _isSearching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchResults = [];
                        });
                      },
                    )
                  : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onSubmitted: _searchPlaces,
      ),
    );
  }

  Widget _buildSearchResults(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          final place = _searchResults[index];
          return ListTile(
            leading: Text(
              place.typeIcon,
              style: const TextStyle(fontSize: 24),
            ),
            title: Text(place.name),
            subtitle: place.address != null
                ? Text(
                    place.address!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : null,
            trailing: place.rating != null
                ? Text(place.displayRating)
                : null,
            onTap: () => _selectSearchResult(place),
          );
        },
      ),
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // Selected location marker
    if (_selectedLocation != null) {
      markers.add(
        Marker(
          point: _selectedLocation!,
          width: 40,
          height: 40,
          child: const Icon(
            Icons.location_pin,
            color: Colors.red,
            size: 40,
          ),
        ),
      );
    }

    // Saved places markers
    if (widget.showSavedPlaces) {
      for (final place in _placeService.savedPlaces) {
        if (_selectedLocation != null &&
            place.latitude == _selectedLocation!.latitude &&
            place.longitude == _selectedLocation!.longitude) {
          continue; // Skip if same as selected
        }

        markers.add(
          Marker(
            point: LatLng(place.latitude, place.longitude),
            width: 30,
            height: 30,
            child: GestureDetector(
              onTap: () => _selectSavedPlace(place),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(place.icon, style: const TextStyle(fontSize: 18)),
                ),
              ),
            ),
          ),
        );
      }
    }

    return markers;
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _selectedLocation = point;
      _selectedPlaceName = '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
      _searchResults = [];
    });

    widget.onLocationSelected?.call(point, _selectedPlaceName);
  }

  Future<void> _searchPlaces(String query) async {
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
    });

    try {
      // Get current map center for nearby search
      final center = _mapController.camera.center;

      final results = await _placeService.searchPlaces(
        query,
        nearLat: center.latitude,
        nearLng: center.longitude,
      );

      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
    }
  }

  void _selectSearchResult(PlaceResult place) {
    final location = LatLng(place.latitude, place.longitude);

    setState(() {
      _selectedLocation = location;
      _selectedPlaceName = place.name;
      _searchResults = [];
      _searchController.clear();
    });

    _mapController.move(location, 17);
    widget.onLocationSelected?.call(location, place.name);
  }

  void _selectSavedPlace(SavedPlace place) {
    final location = LatLng(place.latitude, place.longitude);

    setState(() {
      _selectedLocation = location;
      _selectedPlaceName = place.name;
    });

    _mapController.move(location, 17);
    widget.onLocationSelected?.call(location, place.name);
  }

  Future<void> _goToCurrentLocation() async {
    final position = await _placeService.getCurrentPosition();
    if (position != null) {
      final location = LatLng(position.latitude, position.longitude);

      setState(() {
        _selectedLocation = location;
        _selectedPlaceName = 'ตำแหน่งปัจจุบัน';
      });

      _mapController.move(location, 17);
      widget.onLocationSelected?.call(location, _selectedPlaceName);
    }
  }
}

/// 🗺️ Full Screen Location Picker
class LocationPickerScreen extends StatelessWidget {
  final LatLng? initialLocation;

  const LocationPickerScreen({
    super.key,
    this.initialLocation,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('เลือกสถานที่'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
        ],
      ),
      body: LocationPickerWidget(
        initialLocation: initialLocation,
        height: MediaQuery.of(context).size.height - 150,
        onLocationSelected: (location, name) {
          Navigator.pop(context, {
            'location': location,
            'name': name,
          });
        },
      ),
    );
  }
}

/// 🗺️ Mini Map Preview
class MiniMapPreview extends StatelessWidget {
  final double latitude;
  final double longitude;
  final String? placeName;
  final double height;
  final VoidCallback? onTap;

  const MiniMapPreview({
    super.key,
    required this.latitude,
    required this.longitude,
    this.placeName,
    this.height = 150,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final location = LatLng(latitude, longitude);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCenter: location,
                  initialZoom: 15,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.haku.app',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: location,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.location_pin,
                          color: Colors.red,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (placeName != null)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.place, size: 16),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            placeName!,
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
