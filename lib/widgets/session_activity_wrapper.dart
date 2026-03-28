// lib/widgets/session_activity_wrapper.dart
//
// Widget pembungkus yang mendeteksi aktivitas pengguna (tap, scroll, swipe)
// dan meneruskannya ke SessionExpiryService untuk auto-renew sesi.
// Dipasang langsung di dalam MaterialApp sebagai builder atau di atas
// widget tree utama di MainScreen / HomeScreen.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/session_expiry_provider.dart';

class SessionActivityWrapper extends StatelessWidget {
  final Widget child;

  const SessionActivityWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Gunakan Listener (lebih ringan dari GestureDetector) untuk menangkap
      // semua pointer events tanpa mengganggu gesture handler di bawahnya.
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        // Catat aktivitas tanpa await agar tidak memblokir UI thread
        context.read<SessionExpiryProvider>().recordActivity();
      },
      child: child,
    );
  }
}