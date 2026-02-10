import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class PhotoLocationPage extends StatefulWidget {
  const PhotoLocationPage({super.key});

  @override
  State<PhotoLocationPage> createState() => _PhotoLocationPageState();
}

class _PhotoLocationPageState extends State<PhotoLocationPage> {
  File? _image;
  String _location = 'Lokasi belum tersedia';
  String _address = 'Alamat belum tersedia';
  bool _isLoading = false;
  LatLng? _currentLatLng;

  final ImagePicker _picker = ImagePicker();

  Future<void> _takePhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);

      if (photo != null) {
        setState(() {
          _image = File(photo.path);
          _isLoading = true;
          _location = 'Sedang mencari lokasi...';
          _address = 'Sedang mencari alamat...';
          _currentLatLng = null;
        });
        await _getLocationAndAddress();
      }
    } catch (e) {
      setState(() {
        _location = 'Gagal mengambil foto: $e';
      });
    }
  }

  Future<void> _getLocationAndAddress() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Cek apakah layanan lokasi aktif
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _isLoading = false);
      return Future.error('Layanan lokasi tidak aktif.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _isLoading = false);
        return Future.error('Izin lokasi ditolak.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => _isLoading = false);
      return Future.error('Izin lokasi ditolak secara permanen.');
    }

    try {
      // Ambil posisi saat ini
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Ambil alamat dari koordinat
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      Placemark place = placemarks[0];
      String fullAddress = [
        place.street,
        place.subLocality,
        place.locality,
        place.subAdministrativeArea,
        place.administrativeArea,
        place.postalCode,
        place.country,
      ].where((e) => e != null && e.isNotEmpty).join(', ');

      setState(() {
        _location = 'Lat: ${position.latitude}, Long: ${position.longitude}';
        _address = fullAddress;
        _currentLatLng = LatLng(position.latitude, position.longitude);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _location = 'Gagal mendapatkan lokasi/alamat';
        _address = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Foto & Lokasi GPS')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                if (_image != null)
                  Image.file(
                    _image!,
                    height: 450,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  )
                else
                  Container(
                    height: 450,
                    color: Colors.grey[300],
                    child: const Center(
                      child: Icon(
                        Icons.camera_alt,
                        size: 100,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                if (_currentLatLng != null)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      color: Colors.black.withOpacity(0.6),
                      padding: const EdgeInsets.all(8.0),
                      height: 140,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 120,
                            child: FlutterMap(
                              options: MapOptions(
                                initialCenter: _currentLatLng!,
                                initialZoom: 15.0,
                                interactionOptions: const InteractionOptions(
                                  flags: InteractiveFlag.none,
                                ),
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'com.example.imageapp',
                                ),
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: _currentLatLng!,
                                      width: 40,
                                      height: 40,
                                      child: const Icon(
                                        Icons.location_on,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _address,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _location,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_isLoading)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black45,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _takePhoto,
              icon: const Icon(Icons.camera),
              label: const Text('Ambil Foto'),
            ),
          ],
        ),
      ),
    );
  }
}
