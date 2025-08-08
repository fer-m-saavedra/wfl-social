import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app_badge/flutter_app_badge.dart'; // Cambiamos el paquete por flutter_app_badge
import 'data_service.dart';
import 'auth_service.dart';
import 'package:comunidades/models/event.dart'; // Asegúrate de importar tu modelo de Event

class NotificationService {
  final DataService dataService;
  final AuthService authService;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  NotificationService({
    required this.dataService,
    required this.authService,
    required this.flutterLocalNotificationsPlugin,
  });

  // Este método se encargará de obtener los datos (incluyendo eventos)
  Future<void> checkForNewNotifications() async {
    try {
      // Obtén la sesión del usuario
      final session = await authService.getSession();

      // Si la sesión existe y contiene el username
      if (session != null && session.username != null) {
        final username = session.username;

        // Llama a fetchData para obtener la información, incluyendo eventos
        final data = await dataService.fetchData(username);

        // Extraer las notificaciones (eventos) de los datos obtenidos
        final List<Event> newEvents =
            data['newEvents']; // Usamos la lista de eventos nuevos

        if (newEvents.isNotEmpty) {
          // Mostrar notificación dependiendo de la cantidad de eventos
          if (newEvents.length > 5) {
            await _showBulkNotification(newEvents.length);
          } else {
            await _showIndividualNotifications(newEvents);
          }

          // Actualiza el badge en el ícono con la cantidad de nuevos eventos
          await FlutterAppBadge.count(newEvents.length);
        } else {
          // Si no hay eventos, elimina el badge
          await FlutterAppBadge.count(0);
          print('No hay nuevas notificaciones');
        }
      } else {
        print('No se encontró una sesión válida.');
      }
    } catch (e) {
      print('Error al obtener notificaciones: $e');
    }
  }

  // Método para mostrar una notificación con todos los eventos nuevos
  Future<void> _showBulkNotification(int eventCount) async {
    var androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'your_channel_id', // ID del canal
      'your_channel_name', // Nombre del canal
      channelDescription: 'your_channel_description', // Descripción del canal
      importance: Importance.max,
      priority: Priority.high,
    );
    var platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    // Notificación general si hay más de 5 eventos
    await flutterLocalNotificationsPlugin.show(
      0, // ID de la notificación
      'Nuevos eventos', // Título
      'Hay $eventCount nuevos eventos.', // Cuerpo
      platformChannelSpecifics,
    );
  }

  // Método para mostrar notificaciones individuales para cada evento
  Future<void> _showIndividualNotifications(List<Event> events) async {
    for (var i = 0; i < events.length; i++) {
      var event = events[i];

      var androidPlatformChannelSpecifics = AndroidNotificationDetails(
        'your_channel_id', // ID del canal
        'your_channel_name', // Nombre del canal
        channelDescription: 'your_channel_description', // Descripción del canal
        importance: Importance.max,
        priority: Priority.high,
      );
      var platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
      );

      // Generar el título en el formato "{Comunidad} - {Aplicación} - {fecha}"
      String title =
          '${event.communityName} - ${event.applicationName} - ${event.date.toLocal().toString().split(' ')[0]}';

      // Mostrar una notificación por cada evento nuevo
      await flutterLocalNotificationsPlugin.show(
        i, // ID de la notificación único para cada evento
        title, // Título personalizado
        event.content, // Cuerpo del evento
        platformChannelSpecifics,
      );
    }
  }
}
