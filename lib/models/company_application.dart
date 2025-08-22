class CompanyApplication {
  final int conceptId;
  final int applicationId;
  final String application;
  final String? iconUrl;

  CompanyApplication({
    required this.conceptId,
    required this.applicationId,
    required this.application,
    this.iconUrl,
  });

  factory CompanyApplication.fromJson(Map<String, dynamic> json) {
    return CompanyApplication(
      conceptId: json['ConceptoId'],
      applicationId: json['AplicacionId'],
      application: json['Aplicacion'],
      iconUrl: json['UrlIcoAplicacion'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ConceptoId': conceptId,
      'AplicacionId': applicationId,
      'Aplicacion': application,
      'UrlIcoAplicacion': iconUrl,
    };
  }
}
