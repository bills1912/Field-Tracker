// lib/screens/chat/chat_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
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
  final ScrollController _scrollController = ScrollController();

  List<Message> _messages = [];
  List<Message> _broadcastMessages = [];
  List<FAQ> _faqs = [];
  bool _isLoading = true;
  bool _isSending = false;

  // For editing
  Message? _editingMessage;

  @override
  void initState() {
    super.initState();

    // Initialize Gemini AI Service
    _initializeAI();

    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadMessages();
      }
    });
    _loadMessages();
    _loadFAQs();
    _loadBroadcasts();
  }

  Future<void> _initializeAI() async {
    try {
      GeminiAIService.instance.initialize();
      GeminiAIService.instance.startChat();
      debugPrint('✅ AI Service initialized');
    } catch (e) {
      debugPrint('⚠️ Failed to initialize AI: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);

    try {
      String? messageType;
      if (_tabController.index == 0) {
        messageType = 'ai';
      } else if (_tabController.index == 1) {
        messageType = 'supervisor';
      }

      if (messageType != null) {
        _messages = await ApiService.instance.getMessages(messageType: messageType);
        debugPrint('✅ Loaded ${_messages.length} messages');
      }
    } catch (e) {
      debugPrint('❌ Error loading messages: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading messages: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadFAQs() async {
    try {
      _faqs = await ApiService.instance.getFAQs();
      debugPrint('✅ Loaded ${_faqs.length} FAQs');
    } catch (e) {
      debugPrint('⚠️ Error loading FAQs: $e');
    }
  }

  Future<void> _loadBroadcasts() async {
    try {
      _broadcastMessages = await ApiService.instance.getBroadcastMessages();
      if (mounted) setState(() {});
      debugPrint('✅ Loaded ${_broadcastMessages.length} broadcasts');
    } catch (e) {
      debugPrint('⚠️ Error loading broadcasts: $e');
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    _messageController.clear();

    // If editing, update instead of create
    if (_editingMessage != null) {
      await _updateMessage(_editingMessage!.id!, content);
      return;
    }

    setState(() => _isSending = true);

    try {
      final user = context.read<AuthProvider>().user;
      if (user == null) {
        throw Exception('User not logged in');
      }

      final messageType = _tabController.index == 0 ? MessageType.ai : MessageType.supervisor;
      debugPrint('📤 Sending ${messageType.name} message: $content');

      final message = Message(
        senderId: user.id,
        messageType: messageType,
        content: content,
        timestamp: DateTime.now(),
      );

      // Try to send to server
      Message newMessage;
      try {
        newMessage = await ApiService.instance.createMessage(message);
        debugPrint('✅ Message created on server: ${newMessage.id}');
      } catch (e) {
        debugPrint('⚠️ Server error, using local message: $e');
        // Use local message if server fails
        newMessage = message.copyWith(
          id: 'local_${DateTime.now().millisecondsSinceEpoch}',
        );
      }

      setState(() {
        _messages.insert(0, newMessage);
      });

      // Handle AI response
      if (messageType == MessageType.ai) {
        await _getAIResponse(newMessage);
      } else {
        // Supervisor message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Pesan terkirim ke supervisor. Menunggu balasan...'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Send message error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengirim pesan: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _getAIResponse(Message userMessage) async {
    final messageId = userMessage.id;

    try {
      debugPrint('🤖 Getting AI response for message: $messageId');

      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                SizedBox(width: 12),
                Text('AI sedang berpikir...'),
              ],
            ),
            duration: Duration(seconds: 30),
            backgroundColor: Color(0xFF2196F3),
          ),
        );
      }

      // Get AI response
      String aiResponseText;
      try {
        aiResponseText = await GeminiAIService.instance.sendMessage(userMessage.content);
        debugPrint('✅ AI response received: ${aiResponseText.substring(0, aiResponseText.length.clamp(0, 100))}...');
      } catch (e) {
        debugPrint('❌ Gemini AI error: $e');
        aiResponseText = 'Maaf, terjadi kesalahan saat memproses pertanyaan Anda. Silakan coba lagi.\n\nError: $e';
      }

      // Hide loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      // Try to save response to server
      if (messageId != null && !messageId.startsWith('local_')) {
        try {
          await ApiService.instance.respondToMessage(messageId, aiResponseText);
          debugPrint('✅ AI response saved to server');
        } catch (e) {
          debugPrint('⚠️ Failed to save AI response to server: $e');
        }
      }

      // Update UI
      if (mounted) {
        setState(() {
          final index = _messages.indexWhere((m) => m.id == messageId);
          if (index != -1) {
            _messages[index] = _messages[index].copyWith(
              response: aiResponseText,
              isAnswered: true,
            );
          }
        });
      }
    } catch (e) {
      debugPrint('❌ AI response error: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        setState(() {
          final index = _messages.indexWhere((m) => m.id == messageId);
          if (index != -1) {
            _messages[index] = _messages[index].copyWith(
              response: 'Maaf, terjadi kesalahan: $e',
              isAnswered: true,
            );
          }
        });
      }
    }
  }

  Future<void> _updateMessage(String messageId, String newContent) async {
    try {
      final updatedMessage = await ApiService.instance.updateMessage(messageId, newContent);

      setState(() {
        final index = _messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          _messages[index] = updatedMessage;
        }
        _editingMessage = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pesan berhasil diubah'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengubah pesan: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Pesan'),
        content: const Text('Apakah Anda yakin ingin menghapus pesan ini?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiService.instance.deleteMessage(messageId);
      setState(() {
        _messages.removeWhere((m) => m.id == messageId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pesan berhasil dihapus'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menghapus pesan: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _startEditing(Message message) {
    // Check if within 15 minutes
    final timeDiff = DateTime.now().difference(message.timestamp);
    if (timeDiff.inMinutes > 15) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pesan hanya dapat diubah dalam 15 menit setelah dikirim'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _editingMessage = message;
      _messageController.text = message.content;
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingMessage = null;
      _messageController.clear();
    });
  }

  void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pesan disalin'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asisten Lapangan'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.smart_toy), text: 'AI'),
            Tab(icon: Icon(Icons.person), text: 'Supervisor'),
            Tab(icon: Icon(Icons.campaign), text: 'Broadcast'),
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
                _buildBroadcastView(),
              ],
            ),
          ),
          if (_tabController.index != 2) _buildMessageInput(),
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
              _tabController.index == 0
                  ? 'Tanyakan sesuatu kepada AI'
                  : 'Kirim pesan ke supervisor',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Ketik pesan di bawah untuk memulai',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMessages,
      child: ListView.builder(
        controller: _scrollController,
        reverse: true,
        padding: const EdgeInsets.all(16),
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final message = _messages[index];
          return _buildMessageBubble(message);
        },
      ),
    );
  }

  Widget _buildBroadcastView() {
    if (_broadcastMessages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.campaign_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('Belum ada broadcast', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadBroadcasts,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _broadcastMessages.length,
        itemBuilder: (context, index) {
          final message = _broadcastMessages[index];
          return _buildBroadcastBubble(message);
        },
      ),
    );
  }

  Widget _buildBroadcastBubble(Message message) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.campaign, color: Colors.amber.shade700, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Broadcast dari Admin',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade700,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                Text(
                  DateFormat('dd/MM/yyyy HH:mm').format(message.timestamp),
                  style: TextStyle(color: Colors.grey[600], fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(message.content),
          ],
        ),
      ),
    );
  }

  Widget _buildFAQList() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          child: const Column(
            children: [
              Icon(Icons.lightbulb_outline, size: 48, color: Color(0xFF2196F3)),
              SizedBox(height: 16),
              Text(
                'Pertanyaan Umum',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                'Atau ketik pertanyaan Anda sendiri di bawah',
                style: TextStyle(color: Colors.grey, fontSize: 14),
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
    final user = context.read<AuthProvider>().user;
    final isMyMessage = message.senderId == user?.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // User's message bubble
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onLongPress: isMyMessage ? () => _showMessageOptions(message) : null,
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
                  Text(message.content, style: const TextStyle(color: Colors.white)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.isEdited)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Text('(diedit)', style: TextStyle(color: Colors.white70, fontSize: 10)),
                        ),
                      Text(
                        DateFormat('HH:mm').format(message.timestamp),
                        style: const TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // Response bubble
        if (message.response != null && message.response!.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onLongPress: () => _copyMessage(message.response!),
              child: Container(
                margin: const EdgeInsets.only(bottom: 16, right: 48),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
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
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _copyMessage(message.response!),
                          child: Icon(Icons.copy, size: 14, color: Colors.grey[400]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      message.response!,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (!message.isAnswered)
        // Loading indicator while waiting for response
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 16, right: 48),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.grey[400],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    message.messageType == MessageType.ai ? 'AI sedang mengetik...' : 'Menunggu supervisor...',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _showMessageOptions(Message message) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Salin Pesan'),
              onTap: () {
                Navigator.pop(context);
                _copyMessage(message.content);
              },
            ),
            if (message.id != null && !message.id!.startsWith('local_')) ...[
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit Pesan'),
                onTap: () {
                  Navigator.pop(context);
                  _startEditing(message);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Hapus Pesan', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(message.id!);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_editingMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit, size: 16, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Mengedit pesan',
                      style: TextStyle(color: Colors.blue.shade700, fontSize: 12),
                    ),
                  ),
                  GestureDetector(
                    onTap: _cancelEditing,
                    child: const Icon(Icons.close, size: 18, color: Colors.grey),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: _editingMessage != null
                        ? 'Edit pesan...'
                        : (_tabController.index == 0 ? 'Tanya AI...' : 'Tulis pesan ke supervisor...'),
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
                  maxLines: null,
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: _isSending
                    ? Colors.grey
                    : (_editingMessage != null ? Colors.green : const Color(0xFF2196F3)),
                child: IconButton(
                  icon: _isSending
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                      : Icon(
                    _editingMessage != null ? Icons.check : Icons.send,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: _isSending ? null : _sendMessage,
                ),
              ),
            ],
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
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Optionally send the question to AI
              _messageController.text = faq.question;
            },
            child: const Text('Tanya AI'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }
}