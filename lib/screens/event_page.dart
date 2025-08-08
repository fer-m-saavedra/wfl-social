import 'package:flutter/material.dart';
import '../models/event.dart';
import '../services/storage_service.dart';

class EventPage extends StatefulWidget {
  final String title;
  final Map<String, Event> eventMap;
  final String image;
  final StorageService storageService;
  final VoidCallback onUpdateUnread;

  const EventPage({
    Key? key,
    required this.title,
    required this.eventMap,
    required this.image,
    required this.storageService,
    required this.onUpdateUnread,
  }) : super(key: key);

  @override
  _EventPageState createState() => _EventPageState();
}

class _EventPageState extends State<EventPage> {
  late List<Event> events;

  @override
  void initState() {
    super.initState();
    events = widget.eventMap.values.toList();
    _markAllEventsAsRead(); // Marcar todos los eventos como leídos al cargar la página
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: CircleAvatar(
              radius: 50,
              backgroundImage: NetworkImage(widget.image),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: events.length,
              itemBuilder: (context, index) {
                final event = events[index];

                return ListTile(
                  title: Text(event.content),
                  subtitle: Text(event.date.toString()),
                  trailing: event.isRead
                      ? null
                      : Icon(Icons.new_releases, color: Colors.red),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Función para marcar todos los eventos como leídos
  Future<void> _markAllEventsAsRead() async {
    // Marcar los eventos como leídos en el local storage
    await widget.storageService.markEventsAsRead(events);

    // Actualizar la UI localmente
    setState(() {
      for (var event in events) {
        event.isRead = true;
      }
    });

    // Llamar a onUpdateUnread para refrescar el contador de no leídos en CommunitiesPage
    widget.onUpdateUnread();
  }
}
