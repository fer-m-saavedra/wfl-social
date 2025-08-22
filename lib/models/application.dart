class Application {
  final int id;
  final String name;
  final String? iconUrl;

  Application({
    required this.id,
    required this.name,
    this.iconUrl,
  });

  factory Application.fromJson(Map<String, dynamic> json) {
    return Application(
      id: json['AplicacionId'],
      name: json['Aplicacion'],
      iconUrl: json['UrlIcoAplicacion'],
    );
  }
}
