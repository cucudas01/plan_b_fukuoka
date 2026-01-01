import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Plan B Manager', // 앱 목록 이름
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          background: const Color(0xFFF8F9FA),
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
              color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold),
          iconTheme: IconThemeData(color: Colors.black87),
        ),
      ),
      home: const FileListScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. 메인 화면: CSV 파일 목록 관리
// ---------------------------------------------------------------------------
class FileListScreen extends StatefulWidget {
  const FileListScreen({super.key});

  @override
  State<FileListScreen> createState() => _FileListScreenState();
}

class _FileListScreenState extends State<FileListScreen> {
  List<String> filePaths = [];
  List<String> fileNames = [];

  @override
  void initState() {
    super.initState();
    _loadSavedFiles();
  }

  Future<void> _loadSavedFiles() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      filePaths = prefs.getStringList('saved_file_paths') ?? [];
      fileNames = prefs.getStringList('saved_file_names') ?? [];

      if (filePaths.isEmpty) {
        filePaths.add("assets/restaurants.csv");
        fileNames.add("기본: 후쿠오카 맛집");
        _saveFiles();
      }
    });
  }

  Future<void> _saveFiles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('saved_file_paths', filePaths);
    await prefs.setStringList('saved_file_names', fileNames);
  }

  // + 버튼 눌러서 CSV 파일 추가 (확장자 제거 로직 추가됨)
  Future<void> _pickAndAddCsv() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result != null) {
      if (result.files.single.path != null) {
        String originalPath = result.files.single.path!;
        String fileName = result.files.single.name;

        // ✨ [수정] 파일 이름에서 .csv 확장자 제거!
        if (fileName.toLowerCase().endsWith(".csv")) {
          fileName = fileName.substring(0, fileName.length - 4);
        }

        String newPath = await _convertToAppFormat(originalPath, fileName);

        setState(() {
          filePaths.insert(0, newPath);
          fileNames.insert(0, fileName); // 확장자 없는 깔끔한 이름 저장
        });
        _saveFiles();
      }
    }
  }

  // CSV 포맷 자동 변환
  Future<String> _convertToAppFormat(String path, String fileName) async {
    final file = File(path);
    final rawData = await file.readAsString();
    List<List<dynamic>> rows = const CsvToListConverter().convert(rawData);

    if (rows.isEmpty) return path;

    List<dynamic> header = rows[0].map((e) => e.toString().toLowerCase()).toList();

    int nameIdx = header.indexWhere((h) => h.contains('이름') || h.contains('name') || h.contains('가게'));
    int latIdx = header.indexWhere((h) => h.contains('lat') || h.contains('위도'));
    int lngIdx = header.indexWhere((h) => h.contains('lng') || h.contains('lon') || h.contains('경도'));
    int regionIdx = header.indexWhere((h) => h.contains('지역') || h.contains('region'));
    int catIdx = header.indexWhere((h) => h.contains('카테고리') || h.contains('분류') || h.contains('category'));

    if (nameIdx == -1) return path;

    List<List<dynamic>> newRows = [];
    newRows.add(['region', 'category', 'name', 'rating', 'reviews', 'price', 'link', 'image', 'opentime', 'tips', 'waiting', 'lat', 'lng']);

    for (int i = 1; i < rows.length; i++) {
      var row = rows[i];
      if (row.isEmpty) continue;

      String name = row.length > nameIdx ? row[nameIdx].toString() : '이름없음';
      String region = (regionIdx != -1 && row.length > regionIdx) ? row[regionIdx].toString() : '기타';
      String category = (catIdx != -1 && row.length > catIdx) ? row[catIdx].toString() : '맛집';
      String lat = (latIdx != -1 && row.length > latIdx) ? row[latIdx].toString() : '';
      String lng = (lngIdx != -1 && row.length > lngIdx) ? row[lngIdx].toString() : '';

      newRows.add([
        region, category, name,
        '0.0', '0', '0', 'link', 'img',
        '정보없음', '추가된 파일', '정보없음',
        lat, lng
      ]);
    }

    String csvData = const ListToCsvConverter().convert(newRows);
    final directory = await getApplicationDocumentsDirectory();
    final newFile = File('${directory.path}/converted_$fileName.csv'); // 파일명엔 확장자 붙여줌
    await newFile.writeAsString(csvData);

    return newFile.path;
  }

  void _deleteFile(int index) {
    setState(() {
      filePaths.removeAt(index);
      fileNames.removeAt(index);
    });
    _saveFiles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("내 맛집 리스트 관리")),
      body: filePaths.isEmpty
          ? const Center(child: Text("오른쪽 아래 + 버튼을 눌러 파일을 추가하세요"))
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filePaths.length,
        itemBuilder: (context, index) {
          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.map, color: Colors.blue),
              ),
              title: Text(fileNames[index], style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text("터치하여 지도 보기", style: TextStyle(fontSize: 12, color: Colors.grey)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _deleteFile(index),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RestaurantListScreen(
                      filePath: filePaths[index],
                      title: fileNames[index],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickAndAddCsv,
        backgroundColor: const Color(0xFF3B82F6),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. 상세 화면 (지도 및 리스트)
// ---------------------------------------------------------------------------
class RestaurantListScreen extends StatefulWidget {
  final String filePath;
  final String title;

  const RestaurantListScreen({
    super.key,
    required this.filePath,
    required this.title
  });

  @override
  State<RestaurantListScreen> createState() => _RestaurantListScreenState();
}

class Restaurant {
  final String region;
  final String category;
  final String name;
  final double? lat;
  final double? lng;
  final String tips;
  final String waiting;
  double? distance;

  Restaurant({
    required this.region,
    required this.category,
    required this.name,
    this.lat,
    this.lng,
    required this.tips,
    required this.waiting,
  });
}

class _RestaurantListScreenState extends State<RestaurantListScreen> {
  List<Restaurant> restaurants = [];
  bool isLoading = true;
  String statusMessage = "데이터를 불러오는 중입니다...";

  @override
  void initState() {
    super.initState();
    _loadDataAndLocation();
  }

  Future<void> _loadDataAndLocation() async {
    try {
      String rawData;
      if (widget.filePath.startsWith("assets/")) {
        rawData = await rootBundle.loadString(widget.filePath);
      } else {
        rawData = await File(widget.filePath).readAsString();
      }

      List<List<dynamic>> listData = const CsvToListConverter().convert(rawData);
      List<Restaurant> parsedList = [];
      Set<String> addedNames = {};

      for (var i = 1; i < listData.length; i++) {
        var row = listData[i];
        if (row.isEmpty) continue;

        String currentName = row.length > 2 ? row[2].toString() : "이름없음";

        if (addedNames.contains(currentName)) continue;
        addedNames.add(currentName);

        double? lat, lng;
        if (row.length > 12) {
          lat = double.tryParse(row[11].toString());
          lng = double.tryParse(row[12].toString());
        }

        String region = row.length > 0 ? row[0].toString() : "";
        String category = row.length > 1 ? row[1].toString() : "";
        String tips = row.length > 9 ? row[9].toString() : "";
        String waiting = row.length > 10 ? row[10].toString() : "";

        parsedList.add(Restaurant(
          region: region,
          category: category,
          name: currentName,
          lat: lat,
          lng: lng,
          tips: tips,
          waiting: waiting,
        ));
      }

      setState(() => statusMessage = "위치를 확인하고 있습니다...");

      try {
        Position position = await _determinePosition();
        for (var restaurant in parsedList) {
          if (restaurant.lat != null && restaurant.lng != null) {
            restaurant.distance = Geolocator.distanceBetween(
              position.latitude,
              position.longitude,
              restaurant.lat!,
              restaurant.lng!,
            );
          }
        }
        parsedList.sort((a, b) {
          if (a.distance == null) return 1;
          if (b.distance == null) return -1;
          return a.distance!.compareTo(b.distance!);
        });
      } catch (e) {
        statusMessage = "위치 권한이 없어 거리순 정렬이 안됩니다.";
      }

      setState(() {
        restaurants = parsedList;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        statusMessage = "파일을 읽을 수 없습니다.\n형식이 올바르지 않거나 손상된 파일입니다.";
        isLoading = false;
      });
      debugPrint("Error loading CSV: $e");
    }
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return Future.error('GPS 꺼짐');
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return Future.error('권한 거부');
    }
    return await Geolocator.getCurrentPosition();
  }

  Future<void> _launchMap(Restaurant res) async {
    String query = "${res.name} ${res.region}";
    Uri url = Uri.parse("https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}");
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) throw 'err';
    } catch (e) {
      await launchUrl(url, mode: LaunchMode.platformDefault);
    }
  }

  IconData _getCategoryIcon(String category) {
    if (category.contains("라멘") || category.contains("면")) return Icons.ramen_dining_rounded;
    if (category.contains("스시") || category.contains("회")) return Icons.set_meal_rounded;
    if (category.contains("카페") || category.contains("빵")) return Icons.coffee_rounded;
    if (category.contains("고기")) return Icons.dining_rounded;
    if (category.contains("술")) return Icons.local_bar_rounded;
    return Icons.restaurant_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadDataAndLocation)
        ],
      ),
      body: isLoading
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 20),
        Text(statusMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
      ]))
          : restaurants.isEmpty
          ? const Center(child: Text("표시할 맛집 데이터가 없습니다."))
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: restaurants.length,
        itemBuilder: (context, index) {
          final res = restaurants[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _launchMap(res),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12)),
                            child: Icon(_getCategoryIcon(res.category), color: Colors.blue[600], size: 24),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(res.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text("${res.category} · ${res.region}", style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                              ],
                            ),
                          ),
                          if (res.distance != null)
                            Text(
                              "${res.distance! < 1000 ? res.distance!.toStringAsFixed(0) : (res.distance! / 1000).toStringAsFixed(1)}${res.distance! < 1000 ? 'm' : 'km'}",
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent, fontSize: 15),
                            ),
                        ],
                      ),
                      if (res.tips.isNotEmpty || res.waiting.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (res.waiting.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                                    const SizedBox(width: 4),
                                    Text(res.waiting, style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                                  ],
                                ),
                              ),
                            if (res.tips.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(8)),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.lightbulb_outline, size: 14, color: Colors.orange),
                                    const SizedBox(width: 4),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 200),
                                      child: Text(res.tips, style: TextStyle(color: Colors.orange[800], fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        )
                      ]
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}