class Event {
  final int communityId;
  final String communityName;
  final int applicationId;
  final String applicationName;
  final int contentId;
  final String content;
  final DateTime date;
  final String? link;
  bool isRead;

  Event({
    required this.communityId,
    required this.communityName,
    required this.applicationId,
    required this.applicationName,
    required this.contentId,
    required this.content,
    required this.date,
    this.link,
    this.isRead = false,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      communityId: json['ComunidadId'],
      communityName: json['Comunidad'],
      applicationId: json['AplicacionId'],
      applicationName: json['Aplicacion'],
      contentId: json['ContenidoId'],
      content: json['Contenido'],
      date: DateTime.parse(json['Fecha']),
      link: json['Link'],
      isRead: json['isRead'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ComunidadId': communityId,
      'Comunidad': communityName,
      'AplicacionId': applicationId,
      'Aplicacion': applicationName,
      'ContenidoId': contentId,
      'Contenido': content,
      'Fecha': date.toIso8601String(),
      'Link': link,
      'isRead': isRead,
    };
  }
}
