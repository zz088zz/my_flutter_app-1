import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/station_service.dart';
import 'services/wallet_service.dart';
import 'services/vehicle_service.dart';
import 'services/payment_service.dart';
import 'services/refund_service.dart';
import 'services/transaction_history_service.dart';
import 'services/admin_service.dart';
import 'services/fine_service.dart';
import 'screens/home_screen.dart';
import 'pages/sign_in_page.dart';
import 'screens/map_screen.dart';
import 'screens/reservation_screen.dart';
import 'screens/account_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => StationService()),
        ChangeNotifierProvider(create: (_) => WalletService()),
        ChangeNotifierProvider(create: (_) => VehicleService()),
        ChangeNotifierProvider(create: (_) => PaymentService()),
        ChangeNotifierProxyProvider<WalletService, RefundService>(
          create: (context) => RefundService(context.read<WalletService>()),
          update: (context, walletService, previousRefundService) => 
              RefundService(walletService),
        ),
        ChangeNotifierProvider(create: (_) => TransactionHistoryService()),
        ChangeNotifierProxyProvider<TransactionHistoryService, FineService>(
          create: (context) => FineService(transactionHistoryService: context.read<TransactionHistoryService>()),
          update: (context, transactionHistoryService, previousFineService) => 
              FineService(transactionHistoryService: transactionHistoryService),
        ),
        ChangeNotifierProvider(create: (_) => AdminService()),
      ],
      child: MaterialApp(
        title: 'EV Charging App',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.indigo,
          visualDensity: VisualDensity.adaptivePlatformDensity,
          fontFamily: 'Roboto',
        ),
        home: Consumer<AuthService>(
          builder: (context, authService, _) {
            return authService.isLoggedIn ? MainScreen() : SignInPage();
          },
        ),
        // Add your routes here if needed
      ),
    );
  }
}

// MainScreen with BottomNavigationBar
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final List<Widget> _screens = const [
    HomeScreen(),
    MapScreen(),
    ReservationScreen(),
    AccountScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).primaryColor,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Reservations',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}