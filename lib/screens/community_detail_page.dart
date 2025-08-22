import 'package:flutter/material.dart';
import '../models/event.dart';

class CommunityDetailPage extends StatelessWidget {
  final String communityName;
  final List<Event> events;
  final String image;

  const CommunityDetailPage({
    Key? key,
    required this.communityName,
    required this.events,
    required this.image,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(communityName),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: CircleAvatar(
              radius: 50,
              backgroundImage: NetworkImage(image),
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
                  onTap: () {
                    // Mark the event as read
                    event.isRead = true;
                    // Refresh the UI
                    (context as Element).markNeedsBuild();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
