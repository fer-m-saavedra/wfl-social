import 'package:flutter/material.dart';
import 'event_page.dart';
import '../models/community.dart';
import '../models/event.dart';
import '../services/storage_service.dart';

class CommunitiesPage extends StatelessWidget {
  final List<Community> communities;
  final List<Event> events;
  final Future<void> Function() onRefresh;
  final void Function(String communityName) onUpdateUnread;
  final StorageService storageService;

  const CommunitiesPage({
    Key? key,
    required this.communities,
    required this.events,
    required this.onRefresh,
    required this.onUpdateUnread,
    required this.storageService,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Encabezado con borde redondeado y margen externo
          Container(
            margin: const EdgeInsets.symmetric(
                vertical: 0.0, horizontal: 5.0), // Margen exterior
            decoration: BoxDecoration(
              color: Color(0xFF88b9d9), // Color azul personalizado
              borderRadius: BorderRadius.circular(12), // Bordes redondeados
            ),
            padding: const EdgeInsets.all(10.0), // Padding interior
            width: double.infinity, // Ocupar todo el ancho posible
            child: const Text(
              'Comunidades',
              textAlign: TextAlign.left, // Alineación del texto
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // Lista de comunidades con colores alternados y bordes redondeados
          Expanded(
            child: ListView.builder(
              itemCount: communities.length,
              itemBuilder: (context, index) {
                final community = communities[index];
                final communityEvents = events
                    .where((event) => event.communityId == community.id)
                    .toList();

                // Construir el mapa de eventos para la comunidad
                final eventMap = {
                  for (var event in communityEvents)
                    '${event.communityId}-${event.applicationId}-${event.contentId}':
                        event
                };

                final unreadCount =
                    communityEvents.where((event) => !event.isRead).length;

                // Alternar los colores de fondo
                final backgroundColor = index % 2 == 0
                    ? Color(0xFFE0E0E0) // Gris claro
                    : Color(0xFFF5F5F5); // Gris más claro

                return Container(
                  margin: const EdgeInsets.symmetric(
                      vertical: 5.0,
                      horizontal: 10.0), // Margen para separación
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius:
                        BorderRadius.circular(12), // Bordes redondeados
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          Color(0xFFE0E0E0), // Fondo gris claro para el avatar
                      backgroundImage: community.iconUrl != null
                          ? NetworkImage(community.iconUrl!)
                          : null,
                      child: community.iconUrl == null
                          ? Text(
                              community.name[0],
                              style: const TextStyle(
                                  color: Color(
                                      0xFF88b9d9), // Azul personalizado para la letra si no hay imagen
                                  fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                    title: Text(
                      community.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    trailing: unreadCount > 0
                        ? CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.red,
                            child: Text(
                              unreadCount.toString(),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                          )
                        : null,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EventPage(
                            title: community.name,
                            eventMap: eventMap, // Pasar el mapa de eventos
                            image: community.iconUrl ?? '',
                            storageService: storageService,
                            onUpdateUnread: () => onUpdateUnread(community.name),
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
    );
  }
}
