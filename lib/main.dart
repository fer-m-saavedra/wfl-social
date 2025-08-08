import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart'; // Importa workmanager
import 'screens/login_page.dart';
import 'services/config_service.dart';
import 'services/notification_service.dart'; // Importa tu servicio de notificaciones
import 'services/storage_service.dart'; // Importa StorageService
import 'services/data_service.dart'; // Importa DataService
import 'services/auth_service.dart'; // Importa AuthService

// Instancia global para notificaciones locales
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Función que se ejecuta en segundo plano
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // Inicializa el servicio de configuración
    await ConfigService.loadConfig();

    final storageService = StorageService();
    final dataService = DataService(storageService: storageService);
    final authService = AuthService(dataService);

    // Instancia de NotificationService con la notificación local
    final notificationService = NotificationService(
      dataService: dataService,
      authService: authService,
      flutterLocalNotificationsPlugin:
          flutterLocalNotificationsPlugin, // Agrega la instancia de notificaciones
    );

    // Llama a checkForNewNotifications
    await notificationService.checkForNewNotifications();

    return Future.value(true); // Indica que la tarea se completó con éxito
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa el servicio de configuración
  await ConfigService.loadConfig();

  // Inicializa el servicio de notificaciones locales
  var initializationSettingsAndroid = AndroidInitializationSettings('app_icon');
  var initializationSettingsDarwin = DarwinInitializationSettings(); 
  var initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsDarwin,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // Inicializa Workmanager para tareas en segundo plano
  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  // Registra la tarea periódica que se ejecuta cada 15 minutos
  Workmanager().registerPeriodicTask(
    "1", // ID de la tarea
    "notificacionesTask", // Nombre de la tarea
    frequency: Duration(minutes: 15), // Frecuencia de la tarea
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.white),
        useMaterial3: true,
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
              fontSize: 18.0, fontWeight: FontWeight.bold, color: Colors.black),
          bodyMedium: TextStyle(fontSize: 14.0, color: Colors.black),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueGrey,
            foregroundColor: Colors.white,
            textStyle: TextStyle(fontSize: 16),
            padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          ),
        ),
      ),
      debugShowCheckedModeBanner: false,
  home: const LoginPage(),
    );
  }
}
