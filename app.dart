import 'package:flutter/material.dart';

import 'core/services/auth_service.dart';
import 'core/services/supabase_repository.dart';
import 'core/theme/app_theme.dart';
import 'features/shell/main_shell.dart';

class StoichioMasterApp extends StatelessWidget {
  const StoichioMasterApp({
    super.key,
    required this.repository,
    required this.authService,
  });

  final StoichioRepository repository;
  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StoichioMaster',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: MainShell(
        repository: repository,
        authService: authService,
      ),
    );
  }
}
