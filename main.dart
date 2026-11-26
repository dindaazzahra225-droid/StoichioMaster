import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/supabase_config.dart';
import 'core/services/auth_service.dart';
import 'core/services/supabase_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
    );
    try {
      await AuthService().ensureSession();
    } catch (_) {
      // Tetap lanjut agar fitur offline & cache lokal bisa dipakai
    }
  }

  runApp(
    StoichioMasterApp(
      repository: StoichioRepository(),
      authService: AuthService(),
    ),
  );
}
