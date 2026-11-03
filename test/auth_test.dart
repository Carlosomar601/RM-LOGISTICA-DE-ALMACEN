import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rm_core/auth/audit_log.dart';
import 'package:rm_core/auth/user_store.dart';
import 'package:rm_core/models/app_user.dart';
import 'package:rm_core/state/app_state.dart';

void main() {
  late Directory tmp;
  late File usersFile;
  late DateTime now;
  late ProviderContainer c;
  AppState s() => c.read(appProvider);
  AppNotifier n() => c.read(appProvider.notifier);

  ProviderContainer boot({UserStoreData? store}) => ProviderContainer(overrides: [
        userStoreFileProvider.overrideWithValue(usersFile),
        userStoreProvider.overrideWithValue(store ?? UserStoreData.load(usersFile)),
        auditProvider.overrideWithValue(AuditLog(file: File('${tmp.path}/audit.log'))),
        clockProvider.overrideWithValue(() => now),
      ]);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('piqueo_auth');
    usersFile = File('${tmp.path}/users.json');
    now = DateTime(2026, 10, 13, 9);
    c = boot();
  });
  tearDown(() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  group('PIN', () {
    test('se guarda con sal y hash, nunca en claro; el formato coincide con el del instalador', () {
      final u = AppUser(id: 'x', name: 'A', email: '', role: 'Piqueador', active: true, perms: {})..setPin('4321');
      expect(u.pinHash, isNot(contains('4321')));
      expect(u.checkPin('4321'), isTrue);
      expect(u.checkPin('4322'), isFalse);
      // SHA-256 en hex (64 caracteres); el del instalador puede venir en mayúsculas.
      expect(hashPin('sal', '1234'), hasLength(64));
      final inno = AppUser(id: 'y', name: 'B', email: '', role: 'Administrador', active: true, perms: {},
          pinSalt: 'sal', pinHash: hashPin('sal', '1234').toUpperCase());
      expect(inno.checkPin('1234'), isTrue);
    });

    test('nombre corto para los registros', () {
      AppUser u(String name) => AppUser(id: 'x', name: name, email: '', role: '', active: true, perms: {});
      expect(u('Carlos Omar').shortName, 'C. Omar');
      expect(u('maría del Mar Rivera').shortName, 'M. del Mar Rivera');
      expect(u('Juan').shortName, 'Juan');
    });
  });

  group('inicio y cierre de sesión', () {
    test('PIN correcto entra; incorrecto no; usuario inactivo no', () {
      expect(s().currentUser, isNull);
      expect(n().login('9999'), 'PIN incorrecto');
      expect(n().login('12'), contains('4 dígitos'));
      expect(n().login('4444'), contains('inactivo')); // Luis Cruz está inactivo
      expect(n().login('3333'), isNull);
      expect(s().currentUser!.name, 'Juan Nieves');
      n().logout();
      expect(s().currentUser, isNull);
    });

    test('5 intentos fallidos bloquean 30 s; después se puede entrar', () {
      for (var i = 0; i < 4; i++) {
        expect(n().login('9999'), 'PIN incorrecto');
      }
      expect(n().login('9999'), contains('Espera 30 s'));
      expect(n().login('1111'), contains('Demasiados intentos'), reason: 'bloqueado aunque el PIN sea correcto');
      now = now.add(const Duration(seconds: 29));
      expect(n().lockSecondsLeft(), 1);
      now = now.add(const Duration(seconds: 1));
      expect(n().login('1111'), isNull);
    });

    test('los permisos siguen al usuario que inició sesión', () {
      n().login('3333'); // Piqueador
      expect(s().allowed(AppView.picking), isTrue);
      expect(s().allowed(AppView.users), isFalse);
      expect(n().navigate(AppView.users), isFalse);
      n().logout();
      n().login('1111');
      expect(s().allowed(AppView.users), isTrue);
    });

    test('los registros llevan el nombre de quien tiene la sesión', () {
      n().login('2222'); // María Rivera
      final rec = s().pendingReceipts.firstWhere((r) => r.id == 'REC-3430');
      n().allocateReceiptItem(rec.id, 'p1', [('A-01-03', 5)]);
      expect(s().history.first.user, 'M. Rivera');
      final src = s().centralFifoRowsOf('p1').first;
      n().binTransfer(productId: 'p1', srcRowId: src.id, destBin: 'C-01-01', qty: 1);
      expect(s().binTransfers.first.user, 'M. Rivera');
      expect(s().history.first.user, 'M. Rivera');
    });

    test('auditoría: inicio, PIN incorrecto y cierre quedan en audit.log', () {
      n().login('0000');
      n().login('1111');
      n().logout(reason: 'inactividad');
      final lines = File('${tmp.path}/audit.log').readAsLinesSync();
      expect(lines.map((l) => l.split('\t')[1]),
          ['PIN incorrecto', 'inicio de sesión', 'cierre de sesión (inactividad)']);
      expect(lines[1].split('\t')[2], 'Carlos Omar');
      expect(s().logoutReason, 'Sesión cerrada por inactividad.');
      expect(c.read(auditProvider).recent.first.event, 'cierre de sesión (inactividad)');
    });
  });

  group('administración de PIN', () {
    test('único, 4 dígitos, y se guarda en users.json', () {
      expect(n().setPin('u3', '2222'), 'Ese PIN ya lo usa otro empleado.');
      expect(n().setPin('u3', '12a4'), contains('4 dígitos'));
      expect(n().setPin('u3', '5678'), isNull);
      expect(usersFile.existsSync(), isTrue);
      expect(usersFile.readAsStringSync(), isNot(contains('5678')));
      expect(n().login('5678'), isNull);
    });

    test('no se puede dejar al sistema sin administrador con PIN', () {
      expect(n().clearPin('u1'), contains('al menos un administrador'));
      n().setPerm('u2', Area.users, true); // María también administra
      expect(n().clearPin('u1'), isNull);
      expect(n().clearPin('u2'), contains('al menos un administrador'));
    });

    test('el usuario con sesión no se puede borrar a sí mismo', () {
      n().login('1111');
      n().setPerm('u2', Area.users, true);
      n().deleteUser('u1');
      expect(s().users.any((u) => u.id == 'u1'), isTrue);
    });
  });

  group('users.json', () {
    test('falta → demo; válido → se lee tal cual; dañado → error y nadie entra', () {
      expect(UserStoreData.load(usersFile).status, UserStoreStatus.demo);

      n().setPin('u3', '7777');
      n().updateUser('u3', name: 'Juan Nieves Ortiz');
      n().setAutoLogoutMinutes(5);
      c.dispose();
      c = boot(); // reinicio de la app
      expect(c.read(userStoreProvider).status, UserStoreStatus.ok);
      expect(s().users.firstWhere((u) => u.id == 'u3').name, 'Juan Nieves Ortiz');
      expect(s().settings.autoLogoutMinutes, 5);
      expect(n().login('7777'), isNull);

      c.dispose();
      usersFile.writeAsStringSync('{dañado');
      c = boot();
      expect(s().userStoreError, contains('No se pudo leer'));
      expect(s().users, isEmpty, reason: 'nunca vuelve a los usuarios demo');
      expect(n().login('1111'), contains('No se pudieron leer los usuarios'));
    });

    test('app instalada sin users.json: error, nunca usuarios demo', () {
      final d = UserStoreData.load(usersFile, installed: true);
      expect(d.status, UserStoreStatus.broken);
      expect(d.users, isEmpty);
      expect(d.error, contains('Vuelve a ejecutar el instalador'));
    });

    test('lee el users.json que escribe el instalador (un administrador)', () {
      usersFile.writeAsStringSync('{"version":1,"users":[{"id":"u1","name":"Ana Torres","email":"",'
          '"role":"Administrador","active":true,'
          '"perms":["dashboard","receiving","orders","picking","transfers","history","users"],'
          '"pinSalt":"a1b2","pinHash":"${hashPin('a1b2', '2468').toUpperCase()}"}],"autoLogoutMinutes":10}');
      c.dispose();
      c = boot();
      expect(s().users.single.name, 'Ana Torres');
      expect(n().login('2468'), isNull);
      expect(s().actor, 'A. Torres');
      expect(n().addUser(), 'u2', reason: 'los ids nuevos siguen después de los existentes');
    });
  });
}
