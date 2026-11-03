import 'dart:math';

import '../models/app_user.dart';
import '../state/app_state.dart';

/// Estado compartido que viaja del servidor a los clientes: el contenido de data.json más
/// usuarios (sin hash de PIN), presets de roles y avisos de archivos dañados.
///
/// Cada clave de primer nivel es una "colección": el servidor solo reenvía las que cambian.
Map<String, dynamic> encodeWireState(AppState s) => {
  ...s.toDataJson(),
  'users': [for (final u in s.users) publicUserJson(u)],
  'userSeq': s.userSeq,
  'rolePresets': {
    for (final e in s.rolePresets.entries)
      e.key: [
        for (final a in Area.values)
          if (e.value[a] ?? false) a.name,
      ],
  },
  'autoLogoutMinutes': s.settings.autoLogoutMinutes,
  'userStoreError': s.userStoreError,
  'dataStoreError': s.dataStoreError,
};

/// Usuario sin sal ni hash: el PIN solo se comprueba en el servidor.
Map<String, dynamic> publicUserJson(AppUser u) {
  final j = u.toJson()
    ..remove('pinSalt')
    ..remove('pinHash');
  if (u.hasPin) j['hasPin'] = true;
  return j;
}

/// Marca de "tiene PIN" en el cliente; nunca coincide con un PIN real.
const _noPin = '-';

AppState decodeWireState(Map<String, dynamic> w) {
  final s = AppState.fromDataJson(w);
  for (final raw in (w['users'] as List? ?? const [])) {
    final j = Map<String, dynamic>.from(raw as Map);
    final u = AppUser.fromJson(j);
    if (j['hasPin'] == true) {
      u
        ..pinSalt = _noPin
        ..pinHash = _noPin;
    }
    s.users.add(u);
  }
  final rp = w['rolePresets'];
  if (rp is Map) {
    for (final e in rp.entries) {
      final on = (e.value as List).toSet();
      s.rolePresets['${e.key}'] = {for (final a in Area.values) a: on.contains(a.name)};
    }
  }
  final maxId = s.users.map((u) => int.tryParse(u.id.replaceFirst('u', '')) ?? 0).fold(0, max);
  s.userSeq = max((w['userSeq'] as num?)?.toInt() ?? 1, maxId + 1);
  s.settings.autoLogoutMinutes = (w['autoLogoutMinutes'] as num?)?.toInt() ?? s.settings.autoLogoutMinutes;
  s.userStoreError = w['userStoreError'] as String?;
  s.dataStoreError = w['dataStoreError'] as String?;
  return s;
}

/// Lo que ve un dispositivo antes de iniciar sesión (pantalla de PIN).
Map<String, dynamic> encodePublicState(AppState s) => {
  'companyName': s.settings.companyName,
  'warehouseName': s.settings.warehouseName,
  'userStoreError': s.userStoreError,
  'dataStoreError': s.dataStoreError,
};

AppState decodePublicState(Map<String, dynamic> j) {
  final s = AppState.empty();
  s.settings
    ..companyName = '${j['companyName'] ?? s.settings.companyName}'
    ..warehouseName = '${j['warehouseName'] ?? s.settings.warehouseName}';
  s.userStoreError = j['userStoreError'] as String?;
  s.dataStoreError = j['dataStoreError'] as String?;
  return s;
}

/// Copia a [to] lo que es de este dispositivo y no viene del servidor.
void copySessionFields(AppState from, AppState to) {
  to
    ..currentUserId = from.currentUserId
    ..currentView = from.currentView
    ..simulatedUserId = from.simulatedUserId
    ..logoutReason = from.logoutReason
    ..transferPrefill = from.transferPrefill
    ..prefillSeq = from.prefillSeq;
}
