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
        if (token.isNotEmpty) {
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

  // Indica si una empresa tiene ANY no leído en cualquiera de sus conceptos
  bool _empresaHasUnread(Map<String, dynamic> empresa) {
    final tipos = (empresa['tipos'] as Map<String, dynamic>?) ?? {};
    for (final t in tipos.values) {
      final conceptos =
          ((t as Map<String, dynamic>)['conceptos'] as Map<String, dynamic>?) ??
              {};
      for (final c in conceptos.values) {
        final unread = (c is Map && c['totalNoLeidos'] is int)
            ? (c['totalNoLeidos'] as int)
            : 0;
        if (unread > 0) return true;
      }
    }
    return false;
  }

  // Indica si un TIPO tiene ANY no leído en cualquiera de sus conceptos
  bool _tipoHasUnread(Map<String, dynamic> tipo) {
    final conceptos = (tipo['conceptos'] as Map<String, dynamic>?) ?? {};
    for (final c in conceptos.values) {
      final unread =
          (c is Map && c['totalNoLeidos'] is int) ? (c['totalNoLeidos'] as int) : 0;
      if (unread > 0) return true;
    }
    return false;
  }

  // --------------------------
  // STORIES “GRANDES” (Instagram-like)
  // --------------------------
  Widget _buildStoriesEmpresas() {
    final empresasMap = _fullDataEmpresas;

    if (empresasMap.isEmpty) {
      return const Center(child: Text('No hay empresas disponibles'));
    }

    final items = empresasMap.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    // Mostrar badge solo si hay más de una empresa
    final showBadges = items.length > 1;

    // Tamaños “grandes”
    const double ringSize = 76; // tamaño del contenido (imagen) aprox 72px
    const double ringPadding = 4; // grosor aro
    const double outerSize = ringSize + ringPadding * 2; // total ≈ 84

    return SizedBox(
      height: outerSize + 16, // algo de respiración
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final entry = items[index];
          final empId = entry.key;
          final data = entry.value as Map<String, dynamic>;
          final nombre = (data['Empresa'] ?? '').toString();
          final logoUrl = (data['LogoEmp'] ?? '').toString();
          final initial = (nombre.isNotEmpty ? nombre[0] : 'R').toUpperCase();

          final isSelected = empId == _selectedEmpId;
          final hasUnread = showBadges && _empresaHasUnread(data);

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
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      width: outerSize,
                      height: outerSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: isSelected
                              ? [
                                  Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.85),
                                  Theme.of(context).colorScheme.primary,
                                ]
                              : [
                                  Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.45),
                                  Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.75),
                                ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.10),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(ringPadding),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: ClipOval(
                            child: SizedBox(
                              width: ringSize,
                              height: ringSize,
                              child: _StoryAvatarImage(
                                logoUrl: logoUrl,
                                placeholderInitial: initial,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (hasUnread)
                      Positioned(
                        right: -1,
                        top: -1,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
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
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(
        children: [
          Text(
            _selectedEmpName,
            style: const TextStyle(
              fontSize: 20, // un poquito más grande
              fontWeight: FontWeight.w700,
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
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF24224B),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        tipoNombre,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
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
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      itemCount: conceptosList.length,
      itemBuilder: (context, index) {
        final conceptoId = conceptosList[index].key;
        final cData = conceptosList[index].value as Map<String, dynamic>;
        final nombre = (cData['Concepto'] ?? 'Concepto $conceptoId').toString();
        final logo = (cData['UrlIcoConcepto'] ?? '').toString();
        final conceptUrl = cData['UrlConcepto'] as String?;
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
                conceptUrl: conceptUrl,
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

        // TILE estilo WhatsApp
        return InkWell(
          onTap: _openConceptDetail,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                // Avatar grande ~56px
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: (logo.isNotEmpty)
                      ? Image.network(
                          logo,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _InitialCircle(
                            placeholderInitial: initial,
                            fontSize: 20,
                          ),
                        )
                      : _InitialCircle(
                          placeholderInitial: initial,
                          fontSize: 20,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (unread > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$unread',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
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

    // Mostrar badge solo si hay más de un tipo (más de una pestaña)
    final showBadges = sorted.length > 1;

    for (final e in sorted) {
      final tipoId = e.key;
      final data = e.value as Map<String, dynamic>;
      final label = (data['Tipo'] ?? 'Tipo $tipoId').toString();
      final logoUrl = (data['Logo'] ?? '').toString();
      final hasUnread = showBadges && _tipoHasUnread(data);

      final baseIcon = (logoUrl.isNotEmpty)
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

      // Apilar badge rojo si corresponde
      final iconWithBadge = Stack(
        clipBehavior: Clip.none,
        children: [
          baseIcon,
          if (hasUnread)
            Positioned(
              right: -1,
              top: -2,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
        ],
      );

      items.add(BottomNavigationBarItem(icon: iconWithBadge, label: label));
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
        toolbarHeight: 60,
        title: Row(
          children: [
            Image.asset('images/wflw-letras-laterales.png', height: 50),
          ],
        ),
        actions: <Widget>[
          PopupMenuButton<String>(
            onSelected: (String result) {
              if (result == 'logout') _logout();
              if (result == 'clean') _confirmAndClean();
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Usuario conectado',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(username),
                    Text(
                      'Último login: $lastLoginText',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'clean',
                child: Text('🧹 Clean all'),
              ),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Text('🚪 Logout'),
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
                _buildStoriesEmpresas(), // fijo (más grande + badge)
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
      return _InitialCircle(placeholderInitial: placeholderInitial, fontSize: 24);
    }

    return Image.network(
      logoUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          _InitialCircle(placeholderInitial: placeholderInitial, fontSize: 24),
    );
  }
}

class _InitialCircle extends StatelessWidget {
  final String placeholderInitial;
  final double fontSize;

  const _InitialCircle({
    required this.placeholderInitial,
    this.fontSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: Text(
        placeholderInitial,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: Colors.grey,
        ),
      ),
    );
  }
}
