import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/common.dart';
import '../users/users_screen.dart';
import 'bins_tab.dart';
import 'roles_tab.dart';
import 'settings_tab.dart';
import 'stores_tab.dart';

/// Administración: usuarios, tiendas, canastas, roles y parámetros.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this)
    ..addListener(() {
      if (mounted) setState(() {});
    });

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScreenHeader(
          eyebrow: 'Administración',
          title: 'Configuración del sistema',
          subtitle: 'Usuarios, tiendas, canastas del almacén, roles y parámetros. Todo lo que se parametriza se administra aquí.',
        ),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Usuarios'),
            Tab(text: 'Tiendas'),
            Tab(text: 'Canastas'),
            Tab(text: 'Roles'),
            Tab(text: 'Parámetros'),
          ],
        ),
        const SizedBox(height: 16),
        switch (_tabs.index) {
          0 => const UsersScreen(),
          1 => const StoresTab(),
          2 => const BinsTab(),
          3 => const RolesTab(),
          _ => const SettingsTab(),
        },
      ],
    );
  }
}
