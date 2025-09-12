class Session {
  final String token;
  final String username;
  final int loginTime;
  final String? lastEventFetch; // Última conexión
  final bool isLoggedIn; // Indica si el usuario está logueado o no

  Session({
    required this.token,
    required this.username,
    required this.loginTime,
    this.lastEventFetch,
    required this.isLoggedIn,
  });

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'username': username,
      'loginTime': loginTime,
      'lastEventFetch': lastEventFetch,
      'isLoggedIn': isLoggedIn,
    };
  }

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      token: json['token'],
      username: json['username'],
      loginTime: json['loginTime'],
      lastEventFetch: json['lastEventFetch'],
      isLoggedIn:
          json['isLoggedIn'] ?? false, // Valor por defecto si no está presente
    );
  }

Session copyWith({
  String? token,
  String? username,
  int? loginTime,
  String? lastEventFetch,
  bool? isLoggedIn,
}) {
  return Session(
    token: token ?? this.token,
    username: username ?? this.username,
    loginTime: loginTime ?? this.loginTime,
    lastEventFetch: lastEventFetch ?? this.lastEventFetch,
    isLoggedIn: isLoggedIn ?? this.isLoggedIn,
  );
}
}
