import 'company_type.dart';

class Company {
  final int id;
  final String name;
  final String? logoUrl;
  final List<CompanyType> types;

  Company({
    required this.id,
    required this.name,
    this.logoUrl,
    this.types = const [],
  });

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(
      id: json['EmpId'],
      name: json['Empresa'],
      logoUrl: json['LogoEmp'],
      types: (json['Tipos'] as List<dynamic>?)
              ?.map((type) => CompanyType.fromJson(type))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'EmpId': id,
      'Empresa': name,
      'LogoEmp': logoUrl,
      'Tipos': types.map((t) => t.toJson()).toList(),
    };
  }
}
