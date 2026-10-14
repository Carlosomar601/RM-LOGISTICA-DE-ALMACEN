import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/rm_api.dart';
import '../state/app_state.dart';
import '../widgets/toast.dart';
import 'sync_settings.dart';

/// Resultado de una parte de la sincronización (recibos, facturas u órdenes de una tienda).
class SyncPart {
  const SyncPart(this.label, {required this.ok, required this.message, this.notAvailable = false, this.newItems = 0});
  final String label;
  final bool ok;
  final String message;

  /// El endpoint todavía no existe en la API de esa tienda (no es un error de la app).
  final bool notAvailable;
  final int newItems;
}

class SyncState {
  const SyncState({required this.settings, this.running = false, this.parts = const [], this.lastRun});
  final SyncSettings settings;
  final bool running;
  final List<SyncPart> parts;
  final DateTime? lastRun;

  SyncState copyWith({bool? running, List<SyncPart>? parts, DateTime? lastRun}) => SyncState(
        settings: settings,
        running: running ?? this.running,
        parts: parts ?? this.parts,
        lastRun: lastRun ?? this.lastRun,
      );
}

/// Temporizador inyectable (las pruebas lo sustituyen).
final tickerFactoryProvider =
    Provider<Timer Function(Duration, void Function(Timer))>((ref) => Timer.periodic);

/// Sincroniza recibos, facturas y órdenes con RM: a mano o según el intervalo de Parámetros.
/// Solo corre con la app abierta; revisa cada minuto si toca (resiste suspensión/hibernación).
class SyncService extends Notifier<SyncState> {
  Timer? _ticker;

  /// En esta sesión aún no se sincronizó: la primera vez se recupera `lookbackDays`.
  bool _sessionSynced = false;

  File? get _file {
    final dir = ref.read(userDataDirProvider);
    return dir == null ? null : File('${dir.path}\\settings.json');
  }

  @override
  SyncState build() {
    ref.onDispose(() => _ticker?.cancel());
    return SyncState(settings: SyncSettings.load(_file));
  }

  /// Arranca el temporizador; si el intervalo es automático sincroniza al abrir.
  void start() {
    _ticker ??= ref.read(tickerFactoryProvider)(const Duration(minutes: 1), (_) => tick());
    if (state.settings.interval != SyncInterval.manual) syncNow(auto: true);
  }

  bool isDue(DateTime now) {
    final period = state.settings.interval.period;
    if (period == null) return false;
    final last = state.settings.lastSync;
    return !_sessionSynced || last == null || now.difference(last) >= period;
  }

  Future<void> tick() async {
    if (!state.running && isDue(ref.read(clockProvider)())) await syncNow(auto: true);
  }

  void _save() {
    state.settings.save(_file);
    state = state.copyWith();
  }

  void setInterval(SyncInterval v) {
    state.settings.interval = v;
    _save();
  }

  void setLookbackDays(int days) {
    state.settings.lookbackDays = days.clamp(1, 366);
    _save();
  }

  void setSkipTransactions(Set<int> tx) {
    state.settings.skipTransactions = tx;
    _save();
  }

  /// Ejecuta una sincronización completa. Si ya hay una en curso, no lanza otra.
  Future<List<SyncPart>> syncNow({bool auto = false}) async {
    if (state.running) return state.parts;
    state = state.copyWith(running: true);
    final parts = <SyncPart>[];
    try {
      final now = ref.read(clockProvider)();
      final last = state.settings.lastSync;
      var from = (!_sessionSynced || last == null)
          ? now.subtract(Duration(days: state.settings.lookbackDays))
          : last.subtract(const Duration(days: 1));
      final minFrom = now.subtract(const Duration(days: 365));
      if (from.isBefore(minFrom)) from = minFrom;

      final app = ref.read(appProvider.notifier);
      final s = ref.read(appProvider);
      final central = s.centralStore;

      // 1) Recibos del almacén central.
      if (central.apiUrl.trim().isEmpty) {
        parts.add(const SyncPart('Recibos', ok: false, message: 'el almacén central no tiene dirección API'));
      } else {
        parts.add(await _part('Recibos', () async {
          final r = app.importReceiptLines(central.id, await app.fetchReceiptLines(central.id, from, now));
          return ('${r.lines} línea(s) nueva(s) en ${r.receiptsCreated + r.receiptsUpdated} recibo(s)', r.lines);
        }));
      }

      // 2) Facturas antes que órdenes: así una orden recién facturada se marca "Facturada" y no "Cerrada".
      final stores = s.activeStores.where((x) => x.apiUrl.trim().isNotEmpty).toList();
      for (final st in stores) {
        parts.add(await _part('Facturas · ${st.name}', () async {
          final r = app.importInvoices(st.id, await app.fetchInvoices(st.id, from, now),
              skipTransactions: state.settings.skipTransactions);
          return (r.summary, r.created);
        }));
      }
      // 3) Foto de órdenes abiertas.
      for (final st in stores) {
        parts.add(await _part('Órdenes · ${st.name}', () async {
          final r = app.importOpenOrders(st.id, await app.fetchOpenOrders(st.id));
          return (r.summary, r.created + r.updated);
        }));
      }

      _sessionSynced = true;
      state.settings.lastSync = now;
      state.settings.save(_file);
      final news = parts.fold(0, (a, p) => a + p.newItems);
      if (auto && news > 0) {
        ref.read(toastProvider.notifier).show('Sincronización con RM: $news elemento(s) nuevo(s)');
      }
      state = state.copyWith(parts: parts, lastRun: now);
      return parts;
    } finally {
      state = state.copyWith(running: false);
    }
  }

  Future<SyncPart> _part(String label, Future<(String, int)> Function() run) async {
    try {
      final (msg, n) = await run();
      return SyncPart(label, ok: true, message: msg, newItems: n);
    } on RmApiException catch (e) {
      return SyncPart(label,
          ok: false, notAvailable: e.notAvailable, message: e.notAvailable ? 'endpoint aún no disponible' : e.message);
    } catch (e) {
      return SyncPart(label, ok: false, message: 'error inesperado: $e');
    }
  }
}

final syncProvider = NotifierProvider<SyncService, SyncState>(SyncService.new);
