import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:gal/gal.dart';

class PhotoItem {
  final File image;
  final String location;
  final String address;
  final LatLng? latLng;
  final String dateTime;
  final GlobalKey key = GlobalKey();

  PhotoItem({
    required this.image,
    required this.location,
    required this.address,
    this.latLng,
    required this.dateTime,
  });
}

class PhotoLocationPage extends StatefulWidget {
  const PhotoLocationPage({super.key});

  @override
  State<PhotoLocationPage> createState() => _PhotoLocationPageState();
}

class _PhotoLocationPageState extends State<PhotoLocationPage> {
  final List<PhotoItem> _photoItems = [];
  bool _isLoading = false;

  final ImagePicker _picker = ImagePicker();
  final PageController _pageController = PageController(viewportFraction: 0.9);

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);

      if (photo != null) {
        setState(() {
          _isLoading = true;
        });

        // 2. Ambil data lokasi (Handle error terpisah)
        String location = 'Lokasi tidak tersedia';
        String address = 'Alamat tidak tersedia';
        LatLng? latLng;

        try {
          final locationData = await _getLocationData();
          location = locationData['location'] as String;
          address = locationData['address'] as String;
          latLng = locationData['latLng'] as LatLng?;
        } catch (e) {
          debugPrint('Gagal ambil lokasi: $e');
          // Lanjut tanpa lokasi jika gagal
        }

        final now = DateTime.now();
        final dateTime =
            '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

        final newItem = PhotoItem(
          image: File(photo.path),
          location: location,
          address: address,
          latLng: latLng,
          dateTime: dateTime,
        );

        if (mounted) {
          setState(() {
            _photoItems.add(newItem);
            _isLoading = false;
          });

          // Otomatis scroll ke item baru dan simpan setelah render
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (_pageController.hasClients) {
              _pageController.jumpToPage(_photoItems.length - 1);
            }
            // Tunggu peta render (2 detik) agar tidak kosong saat disimpan
            await Future.delayed(const Duration(seconds: 2));
            if (mounted) {
              await _captureAndSave(newItem.key);
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Gagal: $e')));
        });
      }
    }
  }

  Future<void> _captureAndSave(GlobalKey key) async {
    try {
      // Pastikan izin akses diberikan sebelum menyimpan
      if (!await Gal.hasAccess()) {
        await Gal.requestAccess();
      }
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      // Capture image dengan pixel ratio tinggi agar tajam
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final bytes = byteData.buffer.asUint8List();
        await Gal.putImageBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Foto dengan info peta berhasil disimpan!'),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Gagal capture: $e');
    }
  }

  Future<Map<String, dynamic>> _getLocationData() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Cek apakah layanan lokasi aktif
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Layanan lokasi tidak aktif.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Izin lokasi ditolak.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Izin lokasi ditolak secara permanen.');
    }

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

    return {
      'location': 'Lat: ${position.latitude}, Long: ${position.longitude}',
      'address': fullAddress,
      'latLng': LatLng(position.latitude, position.longitude),
    };
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
            ElevatedButton.icon(
              onPressed: _takePhoto,
              icon: const Icon(Icons.camera),
              label: const Text('Ambil Foto'),
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(),
                ),
              ),
            SizedBox(
              height: 450,
              child:
                  _photoItems.isEmpty
                      ? Container(
                        color: Colors.grey[300],
                        child: const Center(
                          child: Icon(
                            Icons.camera_alt,
                            size: 100,
                            color: Colors.grey,
                          ),
                        ),
                      )
                      : PageView.builder(
                        itemCount: _photoItems.length,
                        controller: _pageController,
                        itemBuilder: (context, index) {
                          final item = _photoItems[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4.0,
                            ),
                            child: RepaintBoundary(
                              key: item.key,
                              child: Stack(
                                children: [
                                  Image.file(
                                    item.image,
                                    height: 450,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                  if (item.latLng != null)
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
                                                  initialCenter: item.latLng!,
                                                  initialZoom: 15.0,
                                                  interactionOptions:
                                                      const InteractionOptions(
                                                        flags:
                                                            InteractiveFlag
                                                                .none,
                                                      ),
                                                ),
                                                children: [
                                                  TileLayer(
                                                    urlTemplate:
                                                        'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                                                    subdomains: const [
                                                      'a',
                                                      'b',
                                                      'c',
                                                    ],
                                                    userAgentPackageName:
                                                        'com.example.imageapp',
                                                  ),
                                                  MarkerLayer(
                                                    markers: [
                                                      Marker(
                                                        point: item.latLng!,
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
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    item.dateTime,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    item.address,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                    ),
                                                    maxLines: 3,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    item.location,
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
                                  Positioned(
                                    top: 10,
                                    right: 10,
                                    child: GestureDetector(
                                      onTap: () => _captureAndSave(item.key),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.5),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Image.asset(
                                              'lib/assets/logo-ni.png',
                                              width: 50,
                                              height: 40,
                                              fit: BoxFit.contain,
                                            ),
                                            const SizedBox(width: 8),
                                            const Text(
                                              'foto Ini adalah milik KSPPS Nurinsani',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
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
        ),
      ),
    );
  }
}
