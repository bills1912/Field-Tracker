// lib/screens/chat/chat_router.dart
// Router untuk mengarahkan ke screen chat yang sesuai berdasarkan role user

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import 'chat_screen.dart';
import 'supervisor_chat_screen.dart';
import 'admin_chat_screen.dart';

class ChatRouter extends StatelessWidget {
  const ChatRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    if (user == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    debugPrint('🔀 ChatRouter: User role = ${user.role}');

    // Route berdasarkan role
    switch (user.role.name.toLowerCase()) {
      case 'admin':
        return const AdminChatScreen();
      case 'supervisor':
        return const SupervisorChatScreen();
      case 'enumerator':
      default:
        return const ChatScreen();
    }
  }
}