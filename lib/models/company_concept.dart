import 'package:comunidades/models/company_application.dart';

class CompanyConcept {
  final int typeId;
  final int conceptId;
  final String concept;
  final String? iconUrl;
  final String? conceptUrl;
  final List<CompanyApplication> applications;

  CompanyConcept({
    required this.typeId,
    required this.conceptId,
    required this.concept,
    this.iconUrl,
    this.conceptUrl,
    this.applications = const [],
  });

  factory CompanyConcept.fromJson(Map<String, dynamic> json) {
    return CompanyConcept(
      typeId: json['TipoId'],
      conceptId: json['ConceptoId'],
      concept: json['Concepto'],
      iconUrl: json['UrlIcoConcepto'],
      conceptUrl: json['UrlConcepto'],
      applications: (json['Aplicaciones'] as List<dynamic>?)
              ?.map((app) => CompanyApplication.fromJson(app))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'TipoId': typeId,
      'ConceptoId': conceptId,
      'Concepto': concept,
      'UrlIcoConcepto': iconUrl,
      'UrlConcepto': conceptUrl,
      'Aplicaciones': applications.map((app) => app.toJson()).toList(),
    };
  }
}
