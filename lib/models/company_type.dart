import 'package:comunidades/models/company_concept.dart';

class CompanyType {
  final int companyId;
  final int typeId;
  final String type;
  final String? logoUrl;
  final List<CompanyConcept> concepts;

  CompanyType({
    required this.companyId,
    required this.typeId,
    required this.type,
    this.logoUrl,
    this.concepts = const [],
  });

  factory CompanyType.fromJson(Map<String, dynamic> json) {
    return CompanyType(
      companyId: json['EmpId'],
      typeId: json['TipoId'],
      type: json['Tipo'],
      logoUrl: json['Logo'],
      concepts: (json['Conceptos'] as List<dynamic>?)
              ?.map((concept) => CompanyConcept.fromJson(concept))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'EmpId': companyId,
      'TipoId': typeId,
      'Tipo': type,
      'Logo': logoUrl,
      'Conceptos': concepts.map((c) => c.toJson()).toList(),
    };
  }
}
