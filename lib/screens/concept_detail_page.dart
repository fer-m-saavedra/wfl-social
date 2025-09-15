import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/data_service.dart';
import '../services/storage_service.dart';

class ConceptDetailPage extends StatefulWidget {
  final String conceptName;
  final String logoUrl;
  final int empId;
  final int tipoId;
  final int conceptoId;

  /// Índice de aplicaciones del concepto (viene de la estructura indexada).
  /// {
  ///   "123": { "Aplicacion": "Mi App", ... },
  ///   "124": { "Aplicacion": "Otra App", ... }
  /// }
  final Map<String, dynamic> aplicacionesIndex;

  /// URL del concepto (p. ej. cData['UrlConcepto']).
  /// Si se provee, al tocar el círculo de cabecera se abre en el navegador.
  final String? conceptUrl;

  const ConceptDetailPage({
    super.key,
    required this.conceptName,
    required this.logoUrl,
    required this.empId,
    required this.tipoId,
    required this.conceptoId,
    required this.aplicacionesIndex,
    this.conceptUrl,
  });

  @override
  State<ConceptDetailPage> createState() => _ConceptDetailPageState();
}

class _ConceptDetailPageState extends State<ConceptDetailPage> {
  final _data = DataService(storageService: StorageService());
  final _dateFmt = DateFormat('dd-MM-yyyy HH:mm');

  bool _loading = true;
  bool _madeChanges = false; // para avisar al Home

  /// Eventos crudos del concepto (ya marcados leídos en UI).
  List<Map<String, dynamic>> _events = [];

  /// Grupos por aplicación (llenos luego de _load()).
  List<_AppGroup> _groups = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Devuelve el nombre de la app si el id existe en el índice; si no, null.
  String? _appNameIfKnown(String id) {
    final node = widget.aplicacionesIndex[id] as Map<String, dynamic>?;
    if (node == null) return null;
    final raw = (node['Aplicacion'] ?? node['Nombre'])?.toString();
    if (raw == null || raw.trim().isEmpty) return 'Aplicación $id';
    return raw;
  }

  Future<void> _load() async {
    try {
      final rows = await _data.getEventsByConcept(
        empId: widget.empId,
        tipoId: widget.tipoId,
        conceptoId: widget.conceptoId,
      );

      // marcar como leídos en BD
      final affected = await _data.markConceptEventsRead(
        empId: widget.empId,
        tipoId: widget.tipoId,
        conceptoId: widget.conceptoId,
      );

      // Preparar UI
      final uiRows = rows.map((e) => {...e, 'isRead': 1}).toList();
      final groups = _buildGroups(uiRows);

      if (!mounted) return;
      setState(() {
        _events = uiRows;
        _groups = groups;
        _loading = false;
        _madeChanges = affected > 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando eventos: $e')),
      );
    }
  }

  /// Construye grupos **solo** para eventos cuya app exista en `aplicacionesIndex`.
  /// Los eventos sin `aplicacionId` o con id inexistente se DESCARTAN.
  List<_AppGroup> _buildGroups(List<Map<String, dynamic>> events) {
    final byId = <String, List<Map<String, dynamic>>>{};

    for (final e in events) {
      final raw = e['aplicacionId'];
      final id = raw?.toString().trim() ?? '';
      if (id.isEmpty) continue; // descarta sin id
      if (!widget.aplicacionesIndex.containsKey(id)) continue; // descarta desconocidos

      byId.putIfAbsent(id, () => []).add(e);
    }

    final groups = <_AppGroup>[];
    byId.forEach((id, list) {
      // ordenar eventos del grupo por fecha DESC
      list.sort((a, b) {
        final da = DateTime.tryParse((a['fecha'] ?? '').toString());
        final db = DateTime.tryParse((b['fecha'] ?? '').toString());
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da); // desc
      });

      final appName = _appNameIfKnown(id);
      if (appName == null) return; // seguridad extra (no debería pasar)
      groups.add(_AppGroup(appId: id, appName: appName, events: list));
    });

    // ordenar grupos por nombre
    groups.sort((a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));
    return groups;
  }

  // ===== Navegación a URLs =====

  Uri? _safeParseUrl(String? maybe) {
    if (maybe == null) return null;
    final trimmed = maybe.trim();
    if (trimmed.isEmpty) return null;

    // Si no trae esquema, asumimos https
    final hasScheme = trimmed.startsWith(RegExp(r'^[a-zA-Z][a-zA-Z0-9+\-.]*://'));
    final candidate = hasScheme ? trimmed : 'https://$trimmed';

    try {
      final uri = Uri.parse(candidate);
      if (uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https')) {
        return uri;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _tryLaunchUrl(String? urlStr) async {
    final uri = _safeParseUrl(urlStr);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL inválida o no disponible.')),
      );
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el enlace.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = (widget.conceptName.isNotEmpty
            ? widget.conceptName.characters.first
            : '•')
        .toUpperCase();

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _madeChanges);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.conceptName, overflow: TextOverflow.ellipsis),
          leading: BackButton(
            onPressed: () => Navigator.pop(context, _madeChanges),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Cabecera con logo grande — tap abre UrlConcepto si existe
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => _tryLaunchUrl(widget.conceptUrl),
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey.shade200,
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.3),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: (widget.logoUrl.isNotEmpty)
                            ? Image.network(
                                widget.logoUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _InitialBig(initial: initial),
                              )
                            : _InitialBig(initial: initial),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Lista de grupos (acordeón por aplicación)
                  Expanded(
                    child: _groups.isEmpty
                        ? const Center(
                            child: Text(
                              'No hay eventos para este concepto.',
                              style: TextStyle(color: Colors.black54),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                            itemCount: _groups.length,
                            itemBuilder: (context, idx) {
                              final g = _groups[idx];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                                clipBehavior: Clip.antiAlias,
                                child: Theme(
                                  data: Theme.of(context).copyWith(
                                    dividerColor: Colors.transparent,
                                  ),
                                  child: ExpansionTile(
                                    maintainState: true,
                                    tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                                    childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                                    leading: _AppBullet(name: g.appName),
                                    title: Text(
                                      g.appName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                    subtitle: Text(
                                      '${g.events.length} evento(s)',
                                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                                    ),
                                    children: [
                                      ListView.separated(
                                        shrinkWrap: true,
                                        physics: const NeverScrollableScrollPhysics(),
                                        itemCount: g.events.length,
                                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                                        itemBuilder: (_, i) {
                                          final e = g.events[i];
                                          final contenido = (e['contenido'] ?? '').toString();
                                          final fechaIso = (e['fecha'] ?? '').toString();
                                          final dt = DateTime.tryParse(fechaIso);
                                          final fechaFmt = dt != null ? _dateFmt.format(dt) : fechaIso;
                                          final isRead = (e['isRead'] == 1);
                                          final link =
                                              (e['link'] ?? e['Link'])?.toString().trim();

                                          return InkWell(
                                            borderRadius: BorderRadius.circular(12),
                                            onTap: (link != null && link.isNotEmpty)
                                                ? () => _tryLaunchUrl(link)
                                                : null,
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(12),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withOpacity(0.04),
                                                    blurRadius: 6,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                                border: Border.all(
                                                  color: isRead
                                                      ? Colors.grey.shade300
                                                      : Theme.of(context)
                                                          .colorScheme
                                                          .primary
                                                          .withOpacity(0.25),
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          contenido,
                                                          style: const TextStyle(fontSize: 14),
                                                        ),
                                                      ),
                                                      if (link != null && link.isNotEmpty)
                                                        const Padding(
                                                          padding: EdgeInsets.only(left: 8.0),
                                                          child: Icon(Icons.link, size: 18),
                                                        ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    fechaFmt,
                                                    style: const TextStyle(
                                                      color: Colors.black54,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _AppGroup {
  final String appId;
  final String appName;
  final List<Map<String, dynamic>> events;
  _AppGroup({required this.appId, required this.appName, required this.events});
}

class _AppBullet extends StatelessWidget {
  final String name;
  const _AppBullet({required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '•';
    return CircleAvatar(
      radius: 16,
      backgroundColor: Colors.white,
      child: Text(
        initial,
        style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.grey),
      ),
    );
  }
}

class _InitialBig extends StatelessWidget {
  final String initial;
  const _InitialBig({required this.initial});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          color: Colors.grey,
        ),
      ),
    );
  }
}
