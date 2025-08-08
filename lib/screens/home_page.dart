import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Importa la librería intl para formatear la fecha
import '../models/session.dart';
import 'communities_page.dart';
import 'applications_page.dart';
import 'login_page.dart'; // Importa la página de inicio de sesión
import '../services/data_service.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../models/community.dart';
import '../models/application.dart';
import '../models/event.dart';

class MyHomePage extends StatefulWidget {
  final String title;

  const MyHomePage({super.key, required this.title});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;
  List<Community> _communities = [];
  List<Application> _applications = [];
  List<Event> _events = [];
  bool _isLoading = true;
  final StorageService _storageService = StorageService();
  Session? _session;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    final AuthService authService =
        AuthService(DataService(storageService: _storageService));
    final DataService dataService =
        DataService(storageService: _storageService);

    final session = await authService.getSession();
    setState(() {
      _session = session;
    });

    if (session != null) {
      final token = session.token;
      if (token != null) {
        final data = await dataService.fetchData(session.username);

        setState(() {
          _communities = data['communities'];
          _applications = data['applications'];
          _events = data['events'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    final AuthService authService =
        AuthService(DataService(storageService: _storageService));
    await authService.logout();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
    );
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> _pages = <Widget>[
      CommunitiesPage(
        communities: _communities,
        events: _events,
        onRefresh: _fetchData,
        onUpdateUnread: (String communityName) {
          setState(() {
            for (var community in _communities) {
              if (community.name == communityName) {
                // Actualiza el estado de la comunidad según tu lógica
              }
            }
          });
        },
        storageService: _storageService,
      ),
      ApplicationsPage(
        applications: _applications,
        events: _events,
        onRefresh: _fetchData,
        storageService: _storageService,
        onUpdateUnread: (String applicationName) {
          setState(() {
            for (var app in _applications) {
              if (app.name == applicationName) {
                // Actualiza el estado de la comunidad según tu lógica
              }
            }
          });
        },
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        toolbarHeight: 100,
        title: Row(
          children: [
            Image.asset('images/logo_wf-sin-fondo.png', height: 80),
            const SizedBox(width: 30),
            if (_session != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Usuario: ${_session!.username}",
                    style: TextStyle(
                      color: Color.fromRGBO(33, 149, 243, 0.641),
                      fontSize: 14.0,
                    ),
                  ),
                  Text(
                    "Ult. Fecha: ${DateFormat('dd-MM-yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(_session!.loginTime))}",
                    style: TextStyle(
                      color: Color.fromRGBO(33, 149, 243, 0.641),
                      fontSize: 14.0,
                    ),
                  ),
                ],
              ),
          ],
        ),
        actions: <Widget>[
          PopupMenuButton<String>(
            onSelected: (String result) {
              if (result == 'logout') {
                _logout();
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'logout',
                child: Text('Logout'),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Comunidades',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications),
            label: 'Aplicaciones',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        onTap: _onItemTapped,
      ),
    );
  }
}
