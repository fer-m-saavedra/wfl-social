class CompanyEvent {
  final int companyId;
  final int typeId;
  final int communityId;
  final int applicationId;
  final int contentId;
  final String content;
  final DateTime date;
  final String? link;
  bool isRead;

  CompanyEvent({
    required this.companyId,
    required this.typeId,
    required this.communityId,
    required this.applicationId,
    required this.contentId,
    required this.content,
    required this.date,
    this.link,
    this.isRead = false,
  });

  factory CompanyEvent.fromJson(Map<String, dynamic> json) {
    return CompanyEvent(
      companyId: json['EmpId'],
      typeId: json['TipoId'],
      communityId: json['ComunidadId'],
      applicationId: json['AplicacionId'],
      contentId: json['ContenidoId'],
      content: json['Contenido'],
      date: DateTime.parse(json['Fecha']),
      link: json['Link'],
      isRead: json['isRead'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'EmpId': companyId,
      'TipoId': typeId,
      'ComunidadId': communityId,
      'AplicacionId': applicationId,
      'ContenidoId': contentId,
      'Contenido': content,
      'Fecha': date.toIso8601String(),
      'Link': link,
      'isRead': isRead,
    };
  }
}
