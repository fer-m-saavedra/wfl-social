import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/data_service.dart';
import '../services/storage_service.dart';

class ConceptDetailPage extends StatefulWidget {
  final String conceptName;
  final String logoUrl;
  final int empId;
  final int tipoId;
  final int conceptoId;

  /// Índice de aplicaciones del concepto (viene de la estructura indexada).
  /// Estructura esperada:
  /// {
  ///   "123": { "Aplicacion": "Mi App", ... },
  ///   "124": { "Aplicacion": "Otra App", ... }
  /// }
  final Map<String, dynamic> aplicacionesIndex;

  const ConceptDetailPage({
    super.key,
    required this.conceptName,
    required this.logoUrl,
    required this.empId,
    required this.tipoId,
    required this.conceptoId,
    required this.aplicacionesIndex,
  });

  @override
  State<ConceptDetailPage> createState() => _ConceptDetailPageState();
}

class _ConceptDetailPageState extends State<ConceptDetailPage> {
  final _data = DataService(storageService: StorageService());
  bool _loading = true;
  bool _madeChanges = false; // para avisar al Home
  List<Map<String, dynamic>> _events = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _resolveAppName(dynamic aplicacionIdRaw) {
    final idStr = aplicacionIdRaw?.toString() ?? '';
    if (idStr.isEmpty) return 'App';
    final appNode = widget.aplicacionesIndex[idStr] as Map<String, dynamic>?;
    final name = (appNode?['Aplicacion'] ?? appNode?['Nombre'] ?? 'App $idStr')
        .toString();
    return name;
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

      if (!mounted) return;
      setState(() {
        _events = rows
            .map((e) => {...e, 'isRead': 1}) // reflejar en UI
            .toList();
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
                  // Cabecera con logo grande
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 8),
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
                  const SizedBox(height: 8),

                  // Lista de eventos
                  Expanded(
                    child: _events.isEmpty
                        ? const Center(
                            child: Text(
                              'No hay eventos para este concepto.',
                              style: TextStyle(color: Colors.black54),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                            itemCount: _events.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final e = _events[i];
                              final appName =
                                  _resolveAppName(e['aplicacionId']);
                              final contenido =
                                  (e['contenido'] ?? '').toString();
                              final fechaIso = (e['fecha'] ?? '').toString();
                              final dt = DateTime.tryParse(fechaIso);
                              final fechaFmt = (dt != null)
                                  ? DateFormat('dd-MM-yyyy HH:mm').format(dt)
                                  : fechaIso;
                              final isRead = (e['isRead'] == 1);

                              return Container(
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
                                    Text(
                                      appName, // <<<<<< ahora muestra NOMBRE
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      contenido,
                                      style: const TextStyle(fontSize: 14),
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
