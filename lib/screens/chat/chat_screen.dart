import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/network_provider.dart';
import '../../services/api_service.dart';
import '../../services/gemini_ai_service.dart';
import '../../models/message.dart';
import '../../models/faq.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _messageController = TextEditingController();
  List<Message> _messages = [];
  List<FAQ> _faqs = [];
  bool _isLoading = true;
  bool _isSending = false;

  // HAPUS: _aiChatHistory tidak lagi diperlukan karena ditangani oleh SDK

  @override
  void initState() {
    super.initState();

    // Inisialisasi Service AI & Session Chat
    GeminiAIService.instance.initialize();
    GeminiAIService.instance.startChat();

    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _loadMessages();
      }
    });
    _loadMessages();
    _loadFAQs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);

    try {
      final messageType = _tabController.index == 0 ? 'ai' : 'supervisor';
      _messages = await ApiService.instance.getMessages(messageType: messageType);

      // HAPUS: _buildAIChatHistory() tidak perlu dipanggil
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading messages: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadFAQs() async {
    try {
      _faqs = await ApiService.instance.getFAQs();
    } catch (e) {
      debugPrint('Error loading FAQs: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final content = _messageController.text.trim();
    _messageController.clear();

    setState(() => _isSending = true);

    try {
      final user = context.read<AuthProvider>().user;
      final messageType = _tabController.index == 0 ? MessageType.ai : MessageType.supervisor;

      final message = Message(
        senderId: user!.id, // Pastikan user tidak null
        messageType: messageType,
        content: content,
        timestamp: DateTime.now(),
      );

      // 1. Simpan pesan User ke Database Backend
      final newMessage = await ApiService.instance.createMessage(message);

      setState(() {
        _messages.insert(0, newMessage);
      });

      // 2. Jika chat AI, minta respons dari Gemini
      if (messageType == MessageType.ai) {
        await _getAIResponse(newMessage.id!, content);
      } else {
        // Pesan Supervisor
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Pesan terkirim ke supervisor. Menunggu balasan...'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengirim pesan: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSending = false);
    }
  }

  // Logic AI yang sudah disederhanakan
  Future<void> _getAIResponse(String messageId, String userMessage) async {
    try {
      debugPrint('🤖 Sedang meminta respons AI...');

      // Indikator loading kecil di bawah
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                ),
                SizedBox(width: 12),
                Text('AI sedang berpikir...'),
              ],
            ),
            duration: Duration(seconds: 60), // Set lama agar tidak hilang sendiri
            backgroundColor: Color(0xFF2196F3),
          ),
        );
      }

      // 1. Panggil Service Baru (History sudah otomatis diurus SDK)
      final aiResponseText = await GeminiAIService.instance.sendMessage(userMessage);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      debugPrint('✅ Respons AI diterima: $aiResponseText');

      // 2. Simpan Respons AI ke Database Backend (agar tersimpan di server Anda)
      try {
        await ApiService.instance.respondToMessage(messageId, aiResponseText);
      } catch (e) {
        debugPrint('⚠️ Gagal menyimpan respons AI ke database: $e');
        // Lanjut saja, tampilkan di UI lokal
      }

      // 3. Update UI Lokal
      setState(() {
        final index = _messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          _messages[index] = _messages[index].copyWith(
            response: aiResponseText,
            isAnswered: true,
          );
        }
      });

    } catch (e) {
      debugPrint('❌ Error getting AI response: $e');

      // Tampilkan error di UI pesan
      setState(() {
        final index = _messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          _messages[index] = _messages[index].copyWith(
            response: "Maaf, terjadi kesalahan: $e", // Tampilkan pesan error
            isAnswered: true,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asisten Lapangan'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.smart_toy), text: 'AI Assistant'),
            Tab(icon: Icon(Icons.person), text: 'Supervisor'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildChatView(showFAQs: true),
                _buildChatView(showFAQs: false),
              ],
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildChatView({required bool showFAQs}) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_messages.isEmpty && showFAQs && _faqs.isNotEmpty) {
      return _buildFAQList();
    }

    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'Belum ada pesan',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return _buildMessageBubble(message);
      },
    );
  }

  Widget _buildFAQList() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.lightbulb_outline, size: 48, color: Color(0xFF2196F3)),
              const SizedBox(height: 16),
              const Text(
                'Pertanyaan Umum',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _faqs.length,
            itemBuilder: (context, index) {
              final faq = _faqs[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.help_outline, color: Color(0xFF2196F3)),
                  title: Text(faq.question),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showFAQAnswer(faq),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(Message message) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Bubble User
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8, left: 48),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2196F3),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  message.content,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('HH:mm').format(message.timestamp),
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ],
            ),
          ),
        ),

        // Bubble Response (AI/Supervisor)
        if (message.response != null && message.response!.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 16, right: 48),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        message.messageType == MessageType.ai ? Icons.smart_toy : Icons.person,
                        size: 14,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        message.messageType == MessageType.ai ? 'AI Assistant' : 'Supervisor',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Menggunakan SelectableText agar user bisa copy jawaban AI
                  SelectableText(message.response!),
                ],
              ),
            ),
          )
        else if (!message.isAnswered)
        // Indikator Loading / Menunggu
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16, left: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    message.messageType == MessageType.ai ? 'AI sedang mengetik...' : 'Menunggu supervisor...',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: _tabController.index == 0 ? 'Tanya AI...' : 'Tulis pesan...',
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              enabled: !_isSending,
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: const Color(0xFF2196F3),
            child: IconButton(
              icon: _isSending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send, color: Colors.white, size: 20),
              onPressed: _isSending ? null : _sendMessage,
            ),
          ),
        ],
      ),
    );
  }

  void _showFAQAnswer(FAQ faq) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(faq.question),
        content: SingleChildScrollView(child: Text(faq.answer)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup')),
        ],
      ),
    );
  }
}