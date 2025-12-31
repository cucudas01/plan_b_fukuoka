import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '후쿠오카 플랜B',
      debugShowCheckedModeBanner: false, // 오른쪽 위 'Debug' 띠 제거
      theme: ThemeData(
        // 깔끔한 화이트/블루 테마
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6), // 세련된 블루
          background: const Color(0xFFF8F9FA), // 아주 연한 회색 배경
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white, // 스크롤 시 색 변함 방지
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
              color: Colors.black87,
              fontSize: 20,
              fontWeight: FontWeight.bold
          ),
          iconTheme: IconThemeData(color: Colors.black87),
        ),
      ),
      home: const RestaurantListScreen(),
    );
  }
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

class RestaurantListScreen extends StatefulWidget {
  const RestaurantListScreen({super.key});

  @override
  State<RestaurantListScreen> createState() => _RestaurantListScreenState();
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

  // --- 데이터 로딩 로직 ---
  Future<void> _loadDataAndLocation() async {
    try {
      final rawData = await rootBundle.loadString("assets/restaurants.csv");
      List<List<dynamic>> listData = const CsvToListConverter().convert(rawData);
      List<Restaurant> parsedList = [];

      for (var i = 1; i < listData.length; i++) {
        var row = listData[i];
        double? lat, lng;
        if (row.length > 12) {
          lat = double.tryParse(row[11].toString());
          lng = double.tryParse(row[12].toString());
        }
        parsedList.add(Restaurant(
          region: row[0].toString(),
          category: row[1].toString(),
          name: row[2].toString(),
          lat: lat,
          lng: lng,
          tips: row[9].toString(),
          waiting: row[10].toString(),
        ));
      }

      setState(() => statusMessage = "위치를 확인하고 있습니다...");
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

      setState(() {
        restaurants = parsedList;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        statusMessage = "위치 권한을 허용해주세요.\n(설정 > 앱 > 권한)";
        isLoading = false;
      });
    }
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return Future.error('GPS가 꺼져 있습니다.');
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return Future.error('권한 거부됨');
    }
    return await Geolocator.getCurrentPosition();
  }

  Future<void> _launchMap(Restaurant res) async {
    Uri url;
    if (res.lat != null && res.lng != null) {
      url = Uri.parse("google.navigation:q=${res.lat},${res.lng}");
    } else {
      url = Uri.parse("https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(res.name)}");
    }
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) throw 'err';
    } catch (e) {
      await launchUrl(url, mode: LaunchMode.platformDefault);
    }
  }

  // 아이콘 선택
  IconData _getCategoryIcon(String category) {
    if (category.contains("라멘") || category.contains("면")) return Icons.ramen_dining_rounded;
    if (category.contains("스시") || category.contains("해산물")) return Icons.set_meal_rounded;
    if (category.contains("카페") || category.contains("디저트") || category.contains("빵")) return Icons.coffee_rounded;
    if (category.contains("고기") || category.contains("스테이크")) return Icons.dining_rounded;
    if (category.contains("술") || category.contains("이자카야")) return Icons.local_bar_rounded;
    return Icons.restaurant_rounded;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const CircularProgressIndicator(strokeWidth: 2), // 로딩바도 얇게
          const SizedBox(height: 20),
          Text(statusMessage, style: const TextStyle(color: Colors.grey)),
        ])),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Plan B Fukuoka"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDataAndLocation,
          )
        ],
      ),
      body: restaurants.isEmpty
          ? const Center(child: Text("주변 맛집 데이터가 없습니다."))
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
                BoxShadow(
                  color: Colors.grey.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
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
                          // 1. 심플한 아이콘 박스
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(_getCategoryIcon(res.category), color: Colors.blue[600], size: 24),
                          ),
                          const SizedBox(width: 16),

                          // 2. 이름 및 정보
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  res.name,
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "${res.category} · ${res.region}",
                                  style: TextStyle(color: Colors.grey[500], fontSize: 13),
                                ),
                              ],
                            ),
                          ),

                          // 3. 거리 표시 (강조)
                          if (res.distance != null)
                            Text(
                              "${res.distance! < 1000 ? res.distance!.toStringAsFixed(0) : (res.distance! / 1000).toStringAsFixed(1)}${res.distance! < 1000 ? 'm' : 'km'}",
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueAccent,
                                  fontSize: 15
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // 4. 정보 칩 (웨이팅, 꿀팁)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          // 웨이팅 정보
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Text(res.waiting, style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                              ],
                            ),
                          ),

                          // 꿀팁 (있으면 노란색으로 강조)
                          if (res.tips.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.orange[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.lightbulb_outline, size: 14, color: Colors.orange),
                                  const SizedBox(width: 4),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 200),
                                    child: Text(
                                        res.tips,
                                        style: TextStyle(color: Colors.orange[800], fontSize: 12),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      )
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