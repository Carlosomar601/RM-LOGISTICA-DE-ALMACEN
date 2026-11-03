import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rm_core/models/tone.dart';
import 'package:rm_core/remote/discovery.dart';
import 'package:rm_core/remote/protocol.dart';
import 'package:rm_core/remote/remote_app_notifier.dart';
import 'package:rm_core/remote/remote_link.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'client_mode.dart';

/// Conexión con el servidor: se muestra hasta recibir sus datos, o para cambiar de servidor.
class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key, this.asPage = false});

  /// Abierta desde la pantalla de PIN («Cambiar servidor»): con botón de volver.
  final bool asPage;

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  late final TextEditingController _addr =
      TextEditingController(text: ref.read(clientModeProvider)?.address ?? '');
  bool _searching = false;
  List<FoundServer>? _found;
  String? _formError;

  @override
  void initState() {
    super.initState();
    // Primera vez sin dirección: se busca solo.
    if (_addr.text.trim().isEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _addr.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _found = null;
    });
    final r = await discoverServers();
    if (!mounted) return;
    setState(() {
      _searching = false;
      _found = r;
    });
  }

  Future<void> _connect(String address) async {
    final uri = serverWsUri(address);
    if (uri == null) {
      setState(() => _formError = 'Escribe la dirección del servidor, por ejemplo 192.168.1.20');
      return;
    }
    setState(() => _formError = null);
    final mode = ref.read(clientModeProvider);
    if (mode == null) return;
    if (widget.asPage && mounted) Navigator.of(context).pop();
    await mode.changeServer(serverLabel(uri));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final mode = ref.watch(clientModeProvider);
    final hasLink = ref.watch(remoteLinkProvider) != null;
    final info = hasLink ? ref.watch(connectionProvider) : null;
    final current = mode?.address;

    String? status;
    var tone = Tone.neutral;
    if (!widget.asPage && current != null && info != null) {
      switch (info.status) {
        case LinkStatus.connecting:
          status = 'Conectando con $current…';
        case LinkStatus.online:
          status = 'Conectado con $current. Cargando datos…';
          tone = Tone.good;
        case LinkStatus.offline:
          status = 'No se pudo conectar con $current. Se reintenta solo.'
              '${info.error == null ? '' : '\n${info.error}'}';
          tone = Tone.warn;
      }
    }

    return Scaffold(
      appBar: widget.asPage ? AppBar(title: const Text('Servidor')) : null,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!widget.asPage) ...[
                  const Center(child: AppLogo(height: 56)),
                  const SizedBox(height: 22),
                ],
                Text('CONECTAR CON EL SERVIDOR', style: T.th(context), textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text(
                  'Los datos del almacén están en el PC servidor. Este dispositivo trabaja conectado a él.',
                  textAlign: TextAlign.center,
                  style: T.muted(context, size: 13),
                ),
                const SizedBox(height: 18),
                if (status != null) ...[
                  NoteBox(status, tone: tone),
                  const SizedBox(height: 14),
                ],
                LabeledField(
                  label: 'Dirección del servidor',
                  child: TextField(
                    key: const ValueKey('server-address'),
                    controller: _addr,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: InputDecoration(hintText: '192.168.1.20 o servidor:$kDefaultServerPort'),
                    onSubmitted: _connect,
                  ),
                ),
                if (_formError != null) ...[
                  const SizedBox(height: 6),
                  Text(_formError!, style: T.body(context, size: 12.5, color: c.crit)),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(onPressed: () => _connect(_addr.text), child: const Text('Conectar')),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _searching ? null : _search,
                        icon: _searching
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.wifi_find_outlined, size: 18),
                        label: Text(_searching ? 'Buscando…' : 'Buscar en la red'),
                      ),
                    ),
                  ],
                ),
                if (info?.status == LinkStatus.offline && !widget.asPage) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => ref.read(remoteLinkProvider)?.retryNow(),
                    child: const Text('Reintentar ahora'),
                  ),
                ],
                if (_found != null) ...[
                  const SizedBox(height: 18),
                  if (_found!.isEmpty)
                    const NoteBox(
                      'No se encontró ningún servidor en esta red. Verifica que el servicio «RM Logistics Server» '
                      'esté corriendo y que este dispositivo esté en la misma red (Wi-Fi), o escribe la dirección.',
                      tone: Tone.warn,
                    )
                  else
                    for (final f in _found!)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.dns_outlined),
                          title: Text(f.name),
                          subtitle: Text(f.address, style: T.mono(context, size: 12.5)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            _addr.text = f.address;
                            _connect(f.address);
                          },
                        ),
                      ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
