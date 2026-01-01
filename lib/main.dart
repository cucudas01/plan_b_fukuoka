import 'dart:convert'; // JSON 파싱용
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http; // HTTP 요청용
import 'package:flutter_dotenv/flutter_dotenv.dart'; // [추가 1] .env 패키지 임포트

// [추가 2] main 함수를 비동기(async)로 바꾸고 .env 로드
void main() async {
  // 비동기 작업을 위해 필수
  WidgetsFlutterBinding.ensureInitialized();

  // .env 파일 불러오기 (혹시 파일이 없으면 에러 방지)
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("오류: .env 파일을 찾을 수 없습니다. ($e)");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Plan B Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          surface: const Color(0xFFF8F9FA),
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
// 1. 메인 화면
// ---------------------------------------------------------------------------
class FileListScreen extends StatefulWidget {
  const FileListScreen({super.key});

  @override
  State<FileListScreen> createState() => _FileListScreenState();
}

class _FileListScreenState extends State<FileListScreen> {
  List<String> filePaths = [];
  List<String> fileNames = [];
  bool isLocationLoading = false;

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
    });
  }

  Future<void> _saveFiles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('saved_file_paths', filePaths);
    await prefs.setStringList('saved_file_names', fileNames);
  }

  Future<void> _pickAndAddCsv() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result != null) {
      if (result.files.single.path != null) {
        String originalPath = result.files.single.path!;
        String fileName = result.files.single.name;

        if (fileName.toLowerCase().endsWith(".csv")) {
          fileName = fileName.substring(0, fileName.length - 4);
        }

        String newPath = await _convertToAppFormat(originalPath, fileName);

        setState(() {
          filePaths.insert(0, newPath);
          fileNames.insert(0, fileName);
        });
        _saveFiles();
      }
    }
  }

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

    int openIdx = header.indexWhere((h) => h.contains('opentime') || h.contains('운영시간') || h.contains('영업시간'));
    int tipsIdx = header.indexWhere((h) => h.contains('tips') || h.contains('비고') || h.contains('팁') || h.contains('특이사항'));
    int waitIdx = header.indexWhere((h) => h.contains('waiting') || h.contains('대기') || h.contains('웨이팅'));
    int ratingIdx = header.indexWhere((h) => h.contains('rating') || h.contains('평점') || h.contains('별점'));
    int reviewIdx = header.indexWhere((h) => h.contains('reviews') || h.contains('리뷰'));
    int priceIdx = header.indexWhere((h) => h.contains('price') || h.contains('가격') || h.contains('예산'));

    if (nameIdx == -1) return path;

    List<List<dynamic>> newRows = [];
    newRows.add(['region', 'category', 'name', 'rating', 'reviews', 'price', 'link', 'image', 'opentime', 'tips', 'waiting', 'lat', 'lng']);

    for (int i = 1; i < rows.length; i++) {
      var row = rows[i];
      if (row.isEmpty) continue;

      String name = (nameIdx != -1 && row.length > nameIdx) ? row[nameIdx].toString() : '이름없음';
      String region = (regionIdx != -1 && row.length > regionIdx) ? row[regionIdx].toString() : (row.isNotEmpty ? row[0].toString() : '기타');
      String category = (catIdx != -1 && row.length > catIdx) ? row[catIdx].toString() : '맛집';
      String lat = (latIdx != -1 && row.length > latIdx) ? row[latIdx].toString() : '';
      String lng = (lngIdx != -1 && row.length > lngIdx) ? row[lngIdx].toString() : '';

      String opentime = (openIdx != -1 && row.length > openIdx) ? row[openIdx].toString() : '정보없음';
      String tips = (tipsIdx != -1 && row.length > tipsIdx) ? row[tipsIdx].toString() : '추가된 파일';
      String waiting = (waitIdx != -1 && row.length > waitIdx) ? row[waitIdx].toString() : '정보없음';
      String rating = (ratingIdx != -1 && row.length > ratingIdx) ? row[ratingIdx].toString() : '0.0';
      String reviews = (reviewIdx != -1 && row.length > reviewIdx) ? row[reviewIdx].toString() : '0';
      String price = (priceIdx != -1 && row.length > priceIdx) ? row[priceIdx].toString() : '0';

      newRows.add([
        region, category, name,
        rating, reviews, price, 'link', 'img',
        opentime, tips, waiting,
        lat, lng
      ]);
    }

    String csvData = const ListToCsvConverter().convert(newRows);
    final directory = await getApplicationDocumentsDirectory();
    final newFile = File('${directory.path}/converted_$fileName.csv');
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

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final String itemPath = filePaths.removeAt(oldIndex);
      final String itemName = fileNames.removeAt(oldIndex);
      filePaths.insert(newIndex, itemPath);
      fileNames.insert(newIndex, itemName);
    });
    _saveFiles();
  }

  Future<void> _navigateToGooglePlaces() async {
    setState(() => isLocationLoading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw 'GPS가 꺼져있습니다.';

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw '위치 권한이 거부되었습니다.';
      }

      Position position = await Geolocator.getCurrentPosition();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GooglePlacesListScreen(
              lat: position.latitude,
              lng: position.longitude,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("오류: $e")));
      }
    } finally {
      if (mounted) setState(() => isLocationLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Plan B Manager")),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              onPressed: isLocationLoading ? null : _navigateToGooglePlaces,
              icon: isLocationLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.map_outlined, color: Colors.white),
              label: Text(
                  isLocationLoading ? "위치 확인 중..." : "구글 맵에서 실시간 맛집 찾기 (3.8↑)",
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 3,
              ),
            ),
          ),

          const Divider(height: 1, thickness: 1),

          Expanded(
            child: filePaths.isEmpty
                ? const Center(child: Text("등록된 리스트가 없습니다.\n+ 버튼을 눌러 CSV 파일을 추가하세요.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
                : ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filePaths.length,
              onReorder: _onReorder,
              proxyDecorator: (child, index, animation) {
                return Material(elevation: 0, color: Colors.transparent, child: child);
              },
              itemBuilder: (context, index) {
                String displayName = fileNames[index].replaceAll(".csv", "");
                return Card(
                  key: ValueKey(filePaths[index]),
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.list_alt_rounded, color: Colors.black54),
                    ),
                    title: Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text("저장된 목록 보기", style: TextStyle(fontSize: 12, color: Colors.grey)),
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
                            title: displayName,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
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
// 2. 구글 플레이스 API 리스트 화면
// ---------------------------------------------------------------------------
class GooglePlacesListScreen extends StatefulWidget {
  final double lat;
  final double lng;

  const GooglePlacesListScreen({super.key, required this.lat, required this.lng});

  @override
  State<GooglePlacesListScreen> createState() => _GooglePlacesListScreenState();
}

class _GooglePlacesListScreenState extends State<GooglePlacesListScreen> {
  // [추가 3] .env 파일에서 GOOGLE_API_KEY를 안전하게 가져옵니다.
  final String _apiKey = dotenv.env['GOOGLE_API_KEY'] ?? "";

  List<dynamic> _places = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchNearbyPlaces();
  }

  Future<void> _fetchNearbyPlaces() async {
    // 키가 비어있는지 확인
    if (_apiKey.isEmpty) {
      setState(() {
        _errorMessage = ".env 파일에서 GOOGLE_API_KEY를 찾지 못했습니다.\n.env 파일을 확인해주세요.";
        _isLoading = false;
      });
      return;
    }

    final String url =
        "https://maps.googleapis.com/maps/api/place/nearbysearch/json"
        "?location=${widget.lat},${widget.lng}"
        "&radius=1500" // 반경 1.5km
        "&type=restaurant"
        "&language=ko" // 한국어 응답
        "&key=$_apiKey";

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK') {
          List<dynamic> results = data['results'];

          List<dynamic> filtered = results.where((place) {
            final rating = place['rating'];
            return rating != null && (rating is num) && rating >= 3.8;
          }).toList();

          filtered.sort((a, b) {
            double ratingA = (a['rating'] as num).toDouble();
            double ratingB = (b['rating'] as num).toDouble();
            return ratingB.compareTo(ratingA);
          });

          setState(() {
            _places = filtered;
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = "구글 API 오류: ${data['status']}\n(${data['error_message'] ?? ''})";
            _isLoading = false;
          });
        }
      } else {
        throw "서버 연결 실패";
      }
    } catch (e) {
      setState(() {
        _errorMessage = "데이터를 불러오지 못했습니다: $e";
        _isLoading = false;
      });
    }
  }

  Future<void> _openGoogleMaps(String placeId) async {
    final Uri url = Uri.parse("https://www.google.com/maps/search/?api=1&query=Google&query_place_id=$placeId");
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw '앱을 열 수 없습니다.';
      }
    } catch (e) {
      await launchUrl(url, mode: LaunchMode.platformDefault);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("주변 맛집 (평점 3.8↑)")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(child: Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)))
          : _places.isEmpty
          ? const Center(child: Text("조건에 맞는 맛집이 없습니다."))
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _places.length,
        itemBuilder: (context, index) {
          final place = _places[index];
          final name = place['name'] ?? "이름 없음";
          final rating = place['rating']?.toString() ?? "0.0";
          final userRatingsTotal = place['user_ratings_total']?.toString() ?? "0";
          final vicinity = place['vicinity'] ?? "";
          final isOpen = place['opening_hours']?['open_now'] == true;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.storefront, color: Colors.blue),
              ),
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.star_rounded, size: 16, color: Colors.amber[700]),
                      const SizedBox(width: 4),
                      Text("$rating ($userRatingsTotal)", style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 10),
                      if (isOpen)
                        const Text("영업중", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12))
                      else
                        const Text("영업종료", style: TextStyle(color: Colors.red, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(vicinity, style: TextStyle(color: Colors.grey[600], fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
              onTap: () => _openGoogleMaps(place['place_id']),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. 기존 CSV 상세 화면 (기존과 동일)
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
  final String opentime;
  final String tips;
  final String waiting;
  final double rating;
  double? distance;

  Restaurant({
    required this.region,
    required this.category,
    required this.name,
    this.lat,
    this.lng,
    required this.opentime,
    required this.tips,
    required this.waiting,
    required this.rating,
  });
}

class _RestaurantListScreenState extends State<RestaurantListScreen> {
  List<Restaurant> restaurants = [];
  bool isLoading = true;
  String statusMessage = "데이터를 불러오는 중입니다...";
  bool _isSortByOpenActive = false;

  @override
  void initState() {
    super.initState();
    _loadDataAndLocation();
  }

  bool _checkIsOpen(String opentime) {
    if (opentime.contains("24시간")) return true;
    if (!opentime.contains("-")) return true;
    try {
      final now = DateTime.now();
      final currentMinutes = now.hour * 60 + now.minute;
      final parts = opentime.split("-");
      if (parts.length != 2) return true;
      final startPart = parts[0].trim().split(":");
      final endPart = parts[1].trim().split(":");
      final startMinutes = int.parse(startPart[0]) * 60 + int.parse(startPart[1]);
      final endMinutes = int.parse(endPart[0]) * 60 + int.parse(endPart[1]);
      if (endMinutes < startMinutes) {
        return currentMinutes >= startMinutes || currentMinutes <= endMinutes;
      } else {
        return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
      }
    } catch (e) {
      return true;
    }
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

        String region = (row.isNotEmpty) ? row[0].toString() : "";
        String category = row.length > 1 ? row[1].toString() : "";
        double rating = row.length > 3 ? (double.tryParse(row[3].toString()) ?? 0.0) : 0.0;
        String opentime = row.length > 8 ? row[8].toString() : "";
        String tips = row.length > 9 ? row[9].toString() : "";
        String waiting = row.length > 10 ? row[10].toString() : "";

        parsedList.add(Restaurant(
          region: region,
          category: category,
          name: currentName,
          lat: lat,
          lng: lng,
          opentime: opentime,
          tips: tips,
          waiting: waiting,
          rating: rating,
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
        _isSortByOpenActive = false;
      });
    } catch (e) {
      setState(() {
        statusMessage = "파일을 읽을 수 없습니다.\n형식이 올바르지 않거나 손상된 파일입니다.";
        isLoading = false;
      });
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

  void _onSortToggle() {
    setState(() {
      _isSortByOpenActive = !_isSortByOpenActive;

      if (_isSortByOpenActive) {
        restaurants.sort((a, b) {
          bool isOpenA = _checkIsOpen(a.opentime);
          bool isOpenB = _checkIsOpen(b.opentime);
          if (isOpenA && !isOpenB) return -1;
          if (!isOpenA && isOpenB) return 1;
          if (a.distance != null && b.distance != null) {
            return a.distance!.compareTo(b.distance!);
          }
          return 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("영업 중인 식당을 상단으로 정렬했습니다."), duration: Duration(seconds: 1)),
        );
      } else {
        restaurants.sort((a, b) {
          if (a.distance == null) return 1;
          if (b.distance == null) return -1;
          return a.distance!.compareTo(b.distance!);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("거리순(기본) 정렬로 돌아왔습니다."), duration: Duration(seconds: 1)),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: Icon(Icons.sort_rounded, color: _isSortByOpenActive ? Colors.blue : Colors.black87),
            tooltip: "영업 중인 식당 우선 정렬",
            onPressed: _onSortToggle,
          ),
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadDataAndLocation
          ),
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
          final isOpen = _checkIsOpen(res.opentime);

          return RestaurantTile(
            restaurant: res,
            isOpen: isOpen,
            onTap: () => _launchMap(res),
          );
        },
      ),
    );
  }
}

class RestaurantTile extends StatefulWidget {
  final Restaurant restaurant;
  final bool isOpen;
  final VoidCallback onTap;

  const RestaurantTile({
    super.key,
    required this.restaurant,
    required this.isOpen,
    required this.onTap,
  });

  @override
  State<RestaurantTile> createState() => _RestaurantTileState();
}

class _RestaurantTileState extends State<RestaurantTile> {
  bool _isExpanded = false;

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
    final res = widget.restaurant;
    final isOpen = widget.isOpen;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isOpen ? Colors.white : Colors.grey[200],
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withOpacity(isOpen ? 0.08 : 0.0),
              blurRadius: 10,
              offset: const Offset(0, 4)
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.onTap,
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
                      decoration: BoxDecoration(
                          color: isOpen ? Colors.blue[50] : Colors.grey[300],
                          borderRadius: BorderRadius.circular(12)
                      ),
                      child: Icon(
                          _getCategoryIcon(res.category),
                          color: isOpen ? Colors.blue[600] : Colors.grey[600],
                          size: 24
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                    res.name,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: isOpen ? Colors.black : Colors.grey[600],
                                    )
                                ),
                              ),
                              if (!isOpen) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: Colors.red[50],
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.red[200]!)
                                  ),
                                  child: const Text("영업종료", style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
                                )
                              ]
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.star_rounded, size: 16, color: Colors.amber[700]),
                              const SizedBox(width: 2),
                              Text(
                                res.rating > 0 ? res.rating.toString() : "-",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                  "${res.category} · ${res.region}",
                                  style: TextStyle(color: Colors.grey[500], fontSize: 13)
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (res.distance != null)
                      Text(
                        "${res.distance! < 1000 ? res.distance!.toStringAsFixed(0) : (res.distance! / 1000).toStringAsFixed(1)}${res.distance! < 1000 ? 'm' : 'km'}",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isOpen ? Colors.blueAccent : Colors.grey,
                            fontSize: 15
                        ),
                      ),
                  ],
                ),

                if (res.waiting.isNotEmpty || res.opentime.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (res.waiting.isNotEmpty && res.waiting != '정보없음')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: isOpen ? Colors.grey[100] : Colors.grey[300], borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                              const SizedBox(width: 4),
                              Text(res.waiting, style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                            ],
                          ),
                        ),
                      if (res.opentime.isNotEmpty && res.opentime != '정보없음')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                              color: isOpen ? Colors.blueGrey[50] : Colors.red[50],
                              borderRadius: BorderRadius.circular(8)
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.schedule, size: 14, color: isOpen ? Colors.blueGrey[600] : Colors.red[400]),
                              const SizedBox(width: 4),
                              Text(res.opentime, style: TextStyle(color: isOpen ? Colors.blueGrey[700] : Colors.red[900], fontSize: 12)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],

                if (res.tips.isNotEmpty && res.tips != '추가된 파일') ...[
                  const SizedBox(height: 12),
                  GestureDetector(
                    onLongPress: () {
                      setState(() {
                        _isExpanded = !_isExpanded;
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                          color: isOpen ? Colors.orange[50] : Colors.orange[50]!.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8)
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lightbulb_outline, size: 16, color: isOpen ? Colors.orange : Colors.orange[300]),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              res.tips,
                              style: TextStyle(color: isOpen ? Colors.orange[900] : Colors.orange[900]!.withOpacity(0.5), fontSize: 13, height: 1.3),
                              maxLines: _isExpanded ? null : 1,
                              overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}