class Community {
  final int id;
  final String name;
  final String buttonText;
  final String? iconUrl;
  final bool isHome;

  Community({
    required this.id,
    required this.name,
    required this.buttonText,
    this.iconUrl,
    required this.isHome,
  });

  factory Community.fromJson(Map<String, dynamic> json) {
    return Community(
      id: json['ComunidadId'],
      name: json['Comunidad'],
      buttonText: json['TextoBoton'],
      iconUrl: json['UrlIcoComunidad'],
      isHome: json['EsHome'],
    );
  }
}
