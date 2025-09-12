import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/session.dart';
import 'login_page.dart';
import '../services/data_service.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../services/event_sqlite_service.dart';
import 'concept_detail_page.dart';

class MyHomePage extends StatefulWidget {
  final String title;

  const MyHomePage({super.key, required this.title});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;
  Map<String, dynamic> _fullDataEmpresas = {};
  String? _selectedEmpId;
  String _selectedEmpName = '';
  String? _selectedTypeId;

  bool _isLoading = true;
  final StorageService _storageService = StorageService();
  Session? _session;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    // Guardamos la selección previa para preservarla tras el refresh
    final prevEmpId = _selectedEmpId;
    final prevTypeId = _selectedTypeId;

    try {
      final authService =
          AuthService(DataService(storageService: _storageService));
      final dataService = DataService(storageService: _storageService);

      final session = await authService.getSession();
      setState(() {
        _session = session;
      });

      if (session != null) {
        final token = session.token;
        if (token != null) {
          final data = await dataService.fetchData2(session.username);
          final empresas = (data as Map<String, dynamic>);

          // 1) Obtener primera empresa (ordenada) por si toca fallback
          String? firstEmpId;
          String firstEmpName = '';
          String? firstTypeId;

          if (empresas.isNotEmpty) {
            final sortedEmp = empresas.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key));
            firstEmpId = sortedEmp.first.key;
            final firstData = sortedEmp.first.value as Map<String, dynamic>;
            firstEmpName = (firstData['Empresa'] ?? '').toString();

            final firstTipos =
                (firstData['tipos'] ?? {}) as Map<String, dynamic>;
            if (firstTipos.isNotEmpty) {
              final sortedTypes = firstTipos.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key));
              firstTypeId = sortedTypes.first.key;
            }
          }

          // 2) Preservar empresa seleccionada (si existe); si no, usar primera
          String? selEmpId;
          String selEmpName = '';
          String? selTypeId;
          int selIndex = 0;

          if (prevEmpId != null && empresas.containsKey(prevEmpId)) {
            // Mantener empresa previa
            selEmpId = prevEmpId;
            final empData = empresas[selEmpId] as Map<String, dynamic>;
            selEmpName = (empData['Empresa'] ?? '').toString();

            final tipos = (empData['tipos'] ?? {}) as Map<String, dynamic>;
            if (tipos.isNotEmpty) {
              // Mantener tipo previo si existe, sino tomar el primero
              final sortedTypes = tipos.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key));
              if (prevTypeId != null && tipos.containsKey(prevTypeId)) {
                selTypeId = prevTypeId;
                // Calcular índice del tipo para el BottomNavigationBar
                selIndex = sortedTypes.indexWhere((e) => e.key == selTypeId);
                if (selIndex < 0) selIndex = 0;
              } else {
                selTypeId = sortedTypes.first.key;
                selIndex = 0;
              }
            } else {
              selTypeId = null;
              selIndex = 0;
            }
          } else {
            // Fallback: primera empresa/tipo
            selEmpId = firstEmpId;
            selEmpName = firstEmpName;
            selTypeId = firstTypeId;
            selIndex = 0;
          }

          setState(() {
            _fullDataEmpresas = empresas;
            _selectedEmpId = selEmpId;
            _selectedEmpName = selEmpName;
            _selectedTypeId = selTypeId;
            _selectedIndex = selIndex;
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
        }
      } else {
        setState(() => _isLoading = false);
      }
    } on UnauthorizedException {
      // Si la API devolvió 401, forzamos logout y navegamos al login
      try {
        final authService =
            AuthService(DataService(storageService: _storageService));
        await authService.logout();
      } catch (_) {}
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar datos: $e')),
        );
      }
    }
  }

  Future<void> _logout() async {
    final authService =
        AuthService(DataService(storageService: _storageService));
    await authService.logout();

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
    );
  }

  // Confirmación y limpieza total de historial local
  Future<void> _confirmAndClean() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clean all'),
        content: const Text('You will delete all history in the App'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        setState(() => _isLoading = true);

        final evDb = EventSqliteService();
        await evDb.init();
        await evDb.clearAll();

        await _fetchData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('History deleted.')),
          );
        }
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cleaning history: $e')),
        );
      }
    }
  }

  /// Refresca el total de no leídos de un concepto (tras volver del detalle)
  Future<void> _refreshUnreadForConcept({
    required int empId,
    required int tipoId,
    required int conceptoId,
  }) async {
    final ds = DataService(storageService: _storageService);
    final newCount = await ds.getUnreadCountForConcept(
      empId: empId,
      tipoId: tipoId,
      conceptoId: conceptoId,
    );

    final emp = _fullDataEmpresas['$empId'] as Map<String, dynamic>?;
    final tipo = (emp?['tipos'] as Map<String, dynamic>?)?['$tipoId']
        as Map<String, dynamic>?;
    final concepto = (tipo?['conceptos']
        as Map<String, dynamic>?)?['$conceptoId'] as Map<String, dynamic>?;

    if (concepto != null) {
      setState(() {
        concepto['totalNoLeidos'] = newCount;
      });
    }
  }

  Widget _buildStoriesEmpresas() {
    final empresasMap = _fullDataEmpresas;

    if (empresasMap.isEmpty) {
      return const Center(child: Text('No hay empresas disponibles'));
    }

    final items = empresasMap.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return SizedBox(
      height: 84,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final entry = items[index];
          final empId = entry.key;
          final data = entry.value as Map<String, dynamic>;
          final nombre = (data['Empresa'] ?? '').toString();
          final logoUrl = (data['LogoEmp'] ?? '').toString();
          final initial = (nombre.isNotEmpty ? nombre[0] : 'R').toUpperCase();

          final isSelected = empId == _selectedEmpId;
          const baseSize = 26.0;
          final circleSize = isSelected ? baseSize + 10 : baseSize;

          return GestureDetector(
            onTap: () {
              final tipos = ((data['tipos'] ?? {}) as Map<String, dynamic>);
              String? primerTipoId;
              if (tipos.isNotEmpty) {
                final sortedTypes = tipos.entries.toList()
                  ..sort((a, b) => a.key.compareTo(b.key));
                primerTipoId = sortedTypes.first.key;
              }
              setState(() {
                _selectedEmpId = empId;
                _selectedEmpName = nombre;
                _selectedTypeId = primerTipoId;
                _selectedIndex = 0;
              });
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  width: circleSize + 18,
                  height: circleSize + 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.primary.withOpacity(0.6),
                        Theme.of(context).colorScheme.primary,
                      ],
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.22),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            )
                          ]
                        : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: ClipOval(
                        child: SizedBox(
                          width: circleSize,
                          height: circleSize,
                          child: _StoryAvatarImage(
                            logoUrl: logoUrl,
                            placeholderInitial: initial,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmpresaSubtitle() {
    if (_selectedEmpId == null || _selectedEmpName.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Text(
            _selectedEmpName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(width: 8)
        ],
      ),
    );
  }

  Widget _buildSelectedTypeHeader() {
    if (_selectedEmpId == null || _selectedTypeId == null) {
      return const SizedBox.shrink();
    }
    final emp = _fullDataEmpresas[_selectedEmpId] as Map<String, dynamic>?;
    final tipo = (emp?['tipos'] as Map<String, dynamic>?)?[_selectedTypeId!]
        as Map<String, dynamic>?;
    final tipoNombre = tipo?['Tipo']?.toString() ?? '';

    if (tipoNombre.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF24224B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        tipoNombre,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// Devuelve SIEMPRE un ListView scrolleable (solo esta sección scrollea).
  Widget _buildConceptListView() {
    if (_selectedEmpId == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
            child: Text(
              'Selecciona una empresa para ver sus tipos.',
              style: TextStyle(color: Colors.black54),
            ),
          ),
        ],
      );
    }

    final emp = _fullDataEmpresas[_selectedEmpId] as Map<String, dynamic>?;
    final tipos = (emp?['tipos'] ?? {}) as Map<String, dynamic>;
    if (emp == null || tipos.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
            child: Text(
              'Esta empresa no tiene tipos o conceptos disponibles.',
              style: TextStyle(color: Colors.black54),
            ),
          ),
        ],
      );
    }

    if (_selectedTypeId == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
            child: Text(
              'Selecciona un tipo para ver sus conceptos.',
              style: TextStyle(color: Colors.black54),
            ),
          ),
        ],
      );
    }

    final tData = (tipos[_selectedTypeId] as Map<String, dynamic>?) ??
        <String, dynamic>{};
    final conceptos = (tData['conceptos'] ?? {}) as Map<String, dynamic>;
    if (conceptos.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
            child: Text(
              'Este tipo no tiene conceptos disponibles.',
              style: TextStyle(color: Colors.black54),
            ),
          ),
        ],
      );
    }

    // Orden por no leídos desc, luego alfabético
    final conceptosList = conceptos.entries.toList()
      ..sort((a, b) {
        final unreadA = (a.value['totalNoLeidos'] as int?) ?? 0;
        final unreadB = (b.value['totalNoLeidos'] as int?) ?? 0;
        final cmpUnread = unreadB.compareTo(unreadA);
        if (cmpUnread != 0) return cmpUnread;
        final nombreA = (a.value['Concepto'] ?? '').toString().toLowerCase();
        final nombreB = (b.value['Concepto'] ?? '').toString().toLowerCase();
        return nombreA.compareTo(nombreB);
      });

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: conceptosList.length,
      itemBuilder: (context, index) {
        final conceptoId = conceptosList[index].key;
        final cData = conceptosList[index].value as Map<String, dynamic>;
        final nombre = (cData['Concepto'] ?? 'Concepto $conceptoId').toString();
        final logo = (cData['UrlIcoConcepto'] ?? '').toString();
        final conceptUrl = cData['UrlConcepto'] as String?; // <<< NUEVO
        final unread = (cData['totalNoLeidos'] as int?) ?? 0;
        final initial =
            (nombre.isNotEmpty ? nombre.characters.first : '•').toUpperCase();

        final conceptoIdInt = int.tryParse(conceptoId) ?? 0;
        final empIdInt = int.tryParse(_selectedEmpId ?? '') ?? 0;
        final tipoIdInt = int.tryParse(_selectedTypeId ?? '') ?? 0;

        // Índice de aplicaciones de ESTE concepto (para el detalle)
        final aplicacionesIndex =
            (cData['aplicaciones'] ?? {}) as Map<String, dynamic>;

        Future<void> _openConceptDetail() async {
          final changed = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => ConceptDetailPage(
                conceptName: nombre,
                logoUrl: logo,
                empId: empIdInt,
                tipoId: tipoIdInt,
                conceptoId: conceptoIdInt,
                aplicacionesIndex: aplicacionesIndex,
                conceptUrl: conceptUrl, // <<< NUEVO
              ),
            ),
          );

          if (changed == true) {
            await _refreshUnreadForConcept(
              empId: empIdInt,
              tipoId: tipoIdInt,
              conceptoId: conceptoIdInt,
            );
          }
        }

        return InkWell(
          onTap: _openConceptDetail,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.white,
                  backgroundImage:
                      (logo.isNotEmpty) ? NetworkImage(logo) : null,
                  child: (logo.isEmpty)
                      ? Text(
                          initial,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.grey,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                if (unread > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$unread',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<BottomNavigationBarItem> _buildDynamicBottomItems() {
    final items = <BottomNavigationBarItem>[];

    if (_selectedEmpId == null) return items;

    final emp = _fullDataEmpresas[_selectedEmpId] as Map<String, dynamic>?;
    final tipos = (emp?['tipos'] ?? {}) as Map<String, dynamic>;

    if (tipos.isEmpty) {
      _selectedTypeId = null;
      _selectedIndex = 0;
      return items;
    }

    final sorted = tipos.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    for (final e in sorted) {
      final tipoId = e.key;
      final data = e.value as Map<String, dynamic>;
      final label = (data['Tipo'] ?? 'Tipo $tipoId').toString();
      final logoUrl = (data['Logo'] ?? '').toString();

      final iconWidget = (logoUrl.isNotEmpty)
          ? ClipOval(
              child: SizedBox(
                width: 24,
                height: 24,
                child: Image.network(
                  logoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.category_outlined, size: 22),
                ),
              ),
            )
          : const Icon(Icons.category_outlined, size: 22);

      items.add(BottomNavigationBarItem(icon: iconWidget, label: label));
    }

    // Sincronizar _selectedIndex con _selectedTypeId (por si cambió tras refresh)
    if (_selectedTypeId != null) {
      final idx = sorted.indexWhere((e) => e.key == _selectedTypeId);
      if (idx >= 0) {
        _selectedIndex = idx;
      } else {
        _selectedIndex = 0;
        _selectedTypeId = sorted.first.key;
      }
    } else {
      _selectedIndex = 0;
      _selectedTypeId = sorted.first.key;
    }

    return items;
  }

  void _onBottomItemTapped(int index) {
    setState(() {
      _selectedIndex = index;

      if (_selectedEmpId != null) {
        final emp = _fullDataEmpresas[_selectedEmpId] as Map<String, dynamic>?;
        final tipos = (emp?['tipos'] ?? {}) as Map<String, dynamic>;
        if (tipos.isNotEmpty) {
          final sorted = tipos.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key));
          if (index < sorted.length) {
            _selectedTypeId = sorted[index].key;
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final username = _session?.username ?? '—';
    final loginTimeMillis = _session?.loginTime;
    final lastLoginText = (loginTimeMillis != null)
        ? DateFormat('dd-MM-yyyy HH:mm')
            .format(DateTime.fromMillisecondsSinceEpoch(loginTimeMillis))
        : '—';

    final bottomItems = _buildDynamicBottomItems();

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
                    "Usuario: $username",
                    style: const TextStyle(
                      color: Color.fromRGBO(33, 149, 243, 0.641),
                      fontSize: 14.0,
                    ),
                  ),
                  Text(
                    "Ult. Fecha: $lastLoginText",
                    style: const TextStyle(
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
              if (result == 'logout') _logout();
              if (result == 'clean') _confirmAndClean();
            },
            itemBuilder: (BuildContext context) =>
                const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'clean',
                child: Text('Clean all'),
              ),
              PopupMenuItem<String>(
                value: 'logout',
                child: Text('Logout'),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStoriesEmpresas(), // fijo
                _buildEmpresaSubtitle(), // fijo
                _buildSelectedTypeHeader(), // fijo
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _fetchData,
                    child: _buildConceptListView(), // SOLO esto scrollea
                  ),
                ),
              ],
            ),
      bottomNavigationBar: (bottomItems.length >= 2)
          ? BottomNavigationBar(
              items: bottomItems,
              currentIndex:
                  (_selectedIndex < bottomItems.length) ? _selectedIndex : 0,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: Theme.of(context).colorScheme.primary,
              onTap: _onBottomItemTapped,
            )
          : null,
    );
  }
}

class _StoryAvatarImage extends StatelessWidget {
  final String logoUrl;
  final String placeholderInitial;

  const _StoryAvatarImage({
    required this.logoUrl,
    required this.placeholderInitial,
  });

  @override
  Widget build(BuildContext context) {
    final hasUrl = logoUrl.isNotEmpty;

    if (!hasUrl) {
      return _InitialCircle(placeholderInitial: placeholderInitial);
    }

    return Image.network(
      logoUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          _InitialCircle(placeholderInitial: placeholderInitial),
    );
  }
}

class _InitialCircle extends StatelessWidget {
  final String placeholderInitial;

  const _InitialCircle({required this.placeholderInitial});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: Text(
        placeholderInitial,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: Colors.grey,
        ),
      ),
    );
  }
}
