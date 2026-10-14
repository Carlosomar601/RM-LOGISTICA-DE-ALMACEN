import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piqueo_fifo_centeno/api/rm_api.dart';
import 'package:piqueo_fifo_centeno/state/app_state.dart';
import 'package:piqueo_fifo_centeno/sync/sync_service.dart';
import 'package:piqueo_fifo_centeno/sync/sync_settings.dart';

import 'fake_rm_api.dart';

class _FakeTimer implements Timer {
  bool cancelled = false;
  @override
  void cancel() => cancelled = true;
  @override
  bool get isActive => !cancelled;
  @override
  int get tick => 0;
}

void main() {
  late Directory tmp;
  late DateTime now;
  late FakeRmApi api;
  late ProviderContainer c;
  void Function(Timer)? tickFn;

  SyncService sync() => c.read(syncProvider.notifier);
  SyncState st() => c.read(syncProvider);
  AppState s() => c.read(appProvider);

  ProviderContainer boot({String? apiUrl = 'http://srv:8180'}) {
    final cont = ProviderContainer(overrides: [
      userDataDirProvider.overrideWithValue(tmp),
      clockProvider.overrideWithValue(() => now),
      rmApiFactoryProvider.overrideWithValue((_) => api),
      tickerFactoryProvider.overrideWithValue((d, fn) {
        tickFn = fn;
        return _FakeTimer();
      }),
    ]);
    if (apiUrl != null) cont.read(appProvider.notifier).updateStore('s0', apiUrl: apiUrl);
    return cont;
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('piqueo_sync');
    now = DateTime(2026, 10, 13, 16);
    api = FakeRmApi(lines: [line('1', qty: 12)], orders: [oline('7001', 'MI-20565R15', 4)], invoices: [iline('F1', 'MI-20565R15', 2)]);
    tickFn = null;
    c = boot();
  });
  tearDown(() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  group('SyncSettings (archivo)', () {
    test('falta o dañado → valores por defecto; válido se lee', () {
      expect(SyncSettings.load(File('${tmp.path}/no.json')).interval, SyncInterval.manual);
      File('${tmp.path}/bad.json').writeAsStringSync('{roto');
      expect(SyncSettings.load(File('${tmp.path}/bad.json')).lookbackDays, 2);
      final f = File('${tmp.path}/ok.json');
      SyncSettings(interval: SyncInterval.every2h, lookbackDays: 5, lastSync: now).save(f);
      final back = SyncSettings.load(f);
      expect((back.interval, back.lookbackDays, back.lastSync), (SyncInterval.every2h, 5, now));
    });

    test('la frecuencia elegida sobrevive a un reinicio', () {
      sync().setInterval(SyncInterval.daily);
      sync().setLookbackDays(7);
      sync().setSkipTransactions({10, 19});
      c.dispose();
      c = boot();
      expect((st().settings.interval, st().settings.lookbackDays), (SyncInterval.daily, 7));
      expect(st().settings.skipTransactions, {10, 19});
    });

    test('transacciones excluidas: por defecto ventas en caja; el texto se valida', () {
      expect(SyncSettings().skipTransactions, {10, 11, 12, 19});
      expect(SyncSettings.parseTransactions('10, 11 12;19'), {10, 11, 12, 19});
      expect(SyncSettings.parseTransactions(''), <int>{});
      expect(SyncSettings.parseTransactions('10, caja'), isNull);
    });

    test('la sincronización respeta las transacciones excluidas', () async {
      api.invoices = [iline('C1', 'MI-20565R15', 1, transaction: 10)];
      await sync().syncNow();
      expect(s().orders.any((o) => o.id == 'FAC-C1'), isFalse);
      sync().setSkipTransactions({});
      await sync().syncNow();
      expect(s().orders.any((o) => o.id == 'FAC-C1'), isTrue);
    });
  });

  group('syncNow', () {
    test('trae recibos, facturas y órdenes y guarda la hora', () async {
      final parts = await sync().syncNow();
      expect(parts.map((p) => p.label), ['Recibos', 'Facturas · Almacén Central', 'Órdenes · Almacén Central']);
      expect(parts.every((p) => p.ok), isTrue);
      expect(s().receipts.any((r) => r.id == 'RM-5001'), isTrue);
      expect(s().orders.any((o) => o.id == 'ORD-7001'), isTrue);
      expect(s().orders.any((o) => o.id == 'FAC-F1'), isTrue);
      expect(st().settings.lastSync, now);
      expect(File('${tmp.path}\\settings.json').existsSync(), isTrue);
    });

    test('primera vez recupera lookbackDays; después desde la última menos 1 día', () async {
      sync().setLookbackDays(3);
      await sync().syncNow();
      expect(api.lastFrom, now.subtract(const Duration(days: 3)));
      final first = now;
      now = now.add(const Duration(hours: 2));
      await sync().syncNow();
      expect(api.lastFrom, first.subtract(const Duration(days: 1)));
    });

    test('un endpoint que aún no existe no impide el resto', () async {
      api.ordersError = RmApiException('x', notAvailable: true);
      api.invoicesError = RmApiException('HTTP 500');
      final parts = await sync().syncNow();
      expect(parts[0].ok, isTrue);
      expect((parts[1].ok, parts[1].notAvailable), (false, false));
      expect((parts[2].ok, parts[2].notAvailable), (false, true));
      expect(s().receipts.any((r) => r.id == 'RM-5001'), isTrue);
    });

    test('sin dirección API: lo informa sin fallar', () async {
      c.dispose();
      c = boot(apiUrl: null);
      final parts = await sync().syncNow();
      expect(parts.single.message, contains('no tiene dirección API'));
    });

    test('no corre dos sincronizaciones a la vez', () async {
      api = FakeRmApi(lines: [line('1')], delay: const Duration(milliseconds: 50));
      c.dispose();
      c = boot();
      final a = sync().syncNow();
      final b = sync().syncNow();
      await Future.wait([a, b]);
      expect(api.calls, 1);
    });
  });

  group('programación', () {
    test('manual nunca es automático', () {
      sync().start();
      expect(sync().isDue(now.add(const Duration(days: 10))), isFalse);
      expect(api.calls, 0, reason: 'manual no sincroniza al abrir');
    });

    test('cada intervalo vence a su tiempo', () async {
      for (final (interval, period) in [
        (SyncInterval.hourly, const Duration(hours: 1)),
        (SyncInterval.every2h, const Duration(hours: 2)),
        (SyncInterval.daily, const Duration(days: 1)),
        (SyncInterval.every2d, const Duration(days: 2)),
      ]) {
        sync().setInterval(interval);
        await sync().syncNow();
        final last = st().settings.lastSync!;
        expect(sync().isDue(last.add(period - const Duration(minutes: 1))), isFalse, reason: interval.name);
        expect(sync().isDue(last.add(period)), isTrue, reason: interval.name);
      }
    });

    test('al abrir con intervalo automático sincroniza, y el temporizador sincroniza al vencer', () async {
      sync().setInterval(SyncInterval.hourly);
      c.dispose();
      c = boot();
      sync().start();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(api.calls, 1, reason: 'sincronización al abrir');

      now = now.add(const Duration(minutes: 30));
      tickFn!(_FakeTimer());
      await Future<void>.delayed(Duration.zero);
      expect(api.calls, 1, reason: 'aún no vence');

      now = now.add(const Duration(minutes: 31));
      await sync().tick();
      expect(api.calls, 2, reason: 'venció la hora');
    });
  });
}
