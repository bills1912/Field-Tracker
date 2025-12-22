// lib/screens/chat/supervisor_chat_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../models/message.dart';

class SupervisorChatScreen extends StatefulWidget {
  const SupervisorChatScreen({super.key});

  @override
  State<SupervisorChatScreen> createState() => _SupervisorChatScreenState();
}

class _SupervisorChatScreenState extends State<SupervisorChatScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Map<String, dynamic>> _conversations = [];
  List<Message> _unansweredMessages = [];
  List<Message> _allMessages = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_conversations.isEmpty && _unansweredMessages.isEmpty) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      debugPrint('📥 Loading supervisor chat data...');

      // Load conversations
      try {
        final conversations = await ApiService.instance.getSupervisorConversations();
        _conversations = conversations.map((c) => {
          'enumerator': c.enumeratorId,
          'enumerator_name': c.enumeratorName,
          'latest_message': c.latestMessage,
          'unread_count': c.unreadCount,
          'unanswered_count': c.unansweredCount,
        }).toList();
        debugPrint('✅ Loaded ${_conversations.length} conversations');
      } catch (e) {
        debugPrint('⚠️ Error loading conversations: $e');
        // Try loading messages directly
        await _loadMessagesDirectly();
      }

      // Load unanswered messages
      try {
        _unansweredMessages = await ApiService.instance.getUnansweredMessages();
        debugPrint('✅ Loaded ${_unansweredMessages.length} unanswered messages');
      } catch (e) {
        debugPrint('⚠️ Error loading unanswered: $e');
      }

      // Load all supervisor messages
      try {
        _allMessages = await ApiService.instance.getMessages(messageType: 'supervisor');
        debugPrint('✅ Loaded ${_allMessages.length} supervisor messages');
      } catch (e) {
        debugPrint('⚠️ Error loading all messages: $e');
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('❌ Error loading data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _loadMessagesDirectly() async {
    // Fallback: load all supervisor messages and group by sender
    try {
      final messages = await ApiService.instance.getMessages(messageType: 'supervisor');
      _allMessages = messages;

      // Group by sender
      final Map<String, List<Message>> grouped = {};
      for (var msg in messages) {
        final senderId = msg.senderId;
        if (!grouped.containsKey(senderId)) {
          grouped[senderId] = [];
        }
        grouped[senderId]!.add(msg);
      }

      // Convert to conversations format
      _conversations = grouped.entries.map((entry) {
        final msgs = entry.value;
        final unanswered = msgs.where((m) => !m.isAnswered).length;
        return {
          'enumerator': entry.key,
          'enumerator_name': msgs.first.sender?['username'] ?? msgs.first.sender?['email'] ?? 'Enumerator',
          'latest_message': msgs.first,
          'unread_count': unanswered,
          'unanswered_count': unanswered,
        };
      }).toList();

      // Filter unanswered
      _unansweredMessages = messages.where((m) => !m.isAnswered).toList();

      debugPrint('✅ Loaded ${_conversations.length} conversations from messages');
    } catch (e) {
      debugPrint('❌ Error loading messages directly: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Enumerator'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: Badge(
                label: Text('${_unansweredMessages.length}'),
                isLabelVisible: _unansweredMessages.isNotEmpty,
                child: const Icon(Icons.question_answer),
              ),
              text: 'Belum Dijawab',
            ),
            Tab(
              icon: Badge(
                label: Text('${_conversations.length}'),
                isLabelVisible: _conversations.isNotEmpty,
                child: const Icon(Icons.people),
              ),
              text: 'Enumerator',
            ),
            Tab(
              icon: Badge(
                label: Text('${_allMessages.length}'),
                isLabelVisible: _allMessages.isNotEmpty,
                child: const Icon(Icons.history),
              ),
              text: 'Semua Chat',
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildErrorView()
          : TabBarView(
        controller: _tabController,
        children: [
          _buildUnansweredList(),
          _buildConversationsList(),
          _buildAllMessagesList(),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
          const SizedBox(height: 16),
          Text('Error: $_errorMessage', style: TextStyle(color: Colors.red[600])),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            label: const Text('Coba Lagi'),
          ),
        ],
      ),
    );
  }

  Widget _buildUnansweredList() {
    if (_unansweredMessages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green[300]),
            const SizedBox(height: 16),
            Text('Semua pesan sudah dijawab! 🎉', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _unansweredMessages.length,
        itemBuilder: (context, index) => _buildUnansweredMessageTile(_unansweredMessages[index]),
      ),
    );
  }

  Widget _buildUnansweredMessageTile(Message message) {
    final senderName = message.sender?['username'] ?? message.sender?['email'] ?? 'Enumerator';

    return Card(
      color: Colors.orange.shade50,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _showQuickResponseDialog(message),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.orange,
                    child: Text(
                      senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          senderName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          DateFormat('dd/MM/yyyy HH:mm').format(message.timestamp),
                          style: TextStyle(color: Colors.grey[600], fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'BELUM DIJAWAB',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Text(message.content),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.reply, size: 18),
                    label: const Text('Jawab Sekarang'),
                    style: TextButton.styleFrom(foregroundColor: Colors.orange),
                    onPressed: () => _showQuickResponseDialog(message),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConversationsList() {
    if (_conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('Belum ada percakapan', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 8),
            Text('Pesan dari enumerator akan muncul di sini', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _conversations.length,
        itemBuilder: (context, index) {
          final conv = _conversations[index];
          return _buildConversationTile(conv);
        },
      ),
    );
  }

  Widget _buildConversationTile(Map<String, dynamic> conv) {
    final name = conv['enumerator_name'] ?? 'Enumerator';
    final unansweredCount = conv['unanswered_count'] ?? 0;
    final latestMessage = conv['latest_message'] as Message?;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: unansweredCount > 0 ? Colors.orange : Colors.blue,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            if (unansweredCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$unansweredCount baru',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
          ],
        ),
        subtitle: latestMessage != null
            ? Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              latestMessage.content,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: unansweredCount > 0 ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              DateFormat('dd/MM HH:mm').format(latestMessage.timestamp),
              style: TextStyle(color: Colors.grey[400], fontSize: 11),
            ),
          ],
        )
            : const Text('Belum ada pesan', style: TextStyle(color: Colors.grey)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openEnumeratorChat(conv['enumerator'], name),
      ),
    );
  }

  Widget _buildAllMessagesList() {
    if (_allMessages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('Belum ada riwayat chat', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _allMessages.length,
        itemBuilder: (context, index) {
          final message = _allMessages[index];
          return _buildMessageTile(message);
        },
      ),
    );
  }

  Widget _buildMessageTile(Message message) {
    final senderName = message.sender?['username'] ?? message.sender?['email'] ?? 'Unknown';
    final isAnswered = message.isAnswered;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: isAnswered ? Colors.green : Colors.orange,
          child: Icon(
            isAnswered ? Icons.check : Icons.hourglass_empty,
            color: Colors.white,
            size: 18,
          ),
        ),
        title: Text(senderName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              message.content,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 2),
            Text(
              DateFormat('dd/MM/yyyy HH:mm').format(message.timestamp),
              style: TextStyle(fontSize: 10, color: Colors.grey[400]),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pertanyaan:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(message.content),
                ),
                if (message.response != null && message.response!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Jawaban:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Text(message.response!),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => _showQuickResponseDialog(message),
                    icon: const Icon(Icons.reply, size: 18),
                    label: const Text('Jawab'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openEnumeratorChat(String enumeratorId, String enumeratorName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EnumeratorChatDetailScreen(
          enumeratorId: enumeratorId,
          enumeratorName: enumeratorName,
        ),
      ),
    ).then((_) => _loadData());
  }

  void _showQuickResponseDialog(Message message) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Balas Pesan'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          message.sender?['username'] ?? message.sender?['email'] ?? 'Enumerator',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(message.content),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Jawaban Anda',
                  hintText: 'Ketik jawaban...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 4,
                autofocus: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.send, size: 18),
            label: const Text('Kirim'),
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Jawaban tidak boleh kosong')),
                );
                return;
              }

              Navigator.pop(context);

              final previousUnanswered = List<Message>.from(_unansweredMessages);

              setState(() {
                // A. Hapus dari list 'Belum Dijawab'
                // PENTING: Gunakan List.from agar Flutter mendeteksi perubahan referensi list
                _unansweredMessages = List.from(_unansweredMessages)..removeWhere((m) => m.id == message.id);

                // B. Update di list 'Semua Chat' (ubah status jadi answered)
                final indexAll = _allMessages.indexWhere((m) => m.id == message.id);
                if (indexAll != -1) {
                  _allMessages[indexAll] = _allMessages[indexAll].copyWith(
                    response: text,
                    isAnswered: true,
                  );
                }

                // C. Update Counter/Badge di Tab 'Enumerator' (Conversations)
                // Cari conversation milik pengirim ini
                final convIndex = _conversations.indexWhere((c) => c['enumerator'] == message.senderId);
                if (convIndex != -1) {
                  // Kurangi jumlah unanswered_count secara manual
                  int currentCount = _conversations[convIndex]['unanswered_count'] ?? 0;
                  if (currentCount > 0) {
                    _conversations[convIndex]['unanswered_count'] = currentCount - 1;

                    // Update juga snippet pesan terakhir agar terlihat sudah dibalas
                    _conversations[convIndex]['latest_message'] = _allMessages[indexAll];
                  }
                }
              });

              try {
                await ApiService.instance.respondToMessage(
                  message.id!,
                  text,
                );

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Jawaban terkirim!'),
                      backgroundColor: Colors.green,
                      duration: Duration(milliseconds: 1000), // Durasi pendek saja
                    ),
                  );
                }

              } catch (e) {
                if (mounted) {
                  setState(() {
                    _unansweredMessages = previousUnanswered;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

// ==================== ENUMERATOR CHAT DETAIL SCREEN ====================

class EnumeratorChatDetailScreen extends StatefulWidget {
  final String enumeratorId;
  final String enumeratorName;

  const EnumeratorChatDetailScreen({
    super.key,
    required this.enumeratorId,
    required this.enumeratorName,
  });

  @override
  State<EnumeratorChatDetailScreen> createState() => _EnumeratorChatDetailScreenState();
}

class _EnumeratorChatDetailScreenState extends State<EnumeratorChatDetailScreen> {
  final TextEditingController _responseController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Message> _messages = [];
  bool _isLoading = true;
  Message? _replyingTo;

  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _responseController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);

    try {
      // Try to get enumerator messages
      try {
        final result = await ApiService.instance.getEnumeratorMessages(widget.enumeratorId);
        _messages = result['messages'] as List<Message>;
      } catch (e) {
        // Fallback: filter from all messages
        debugPrint('⚠️ Fallback to filtering messages: $e');
        final allMessages = await ApiService.instance.getMessages(messageType: 'supervisor');
        _messages = allMessages.where((m) =>
        m.senderId == widget.enumeratorId || m.receiverId == widget.enumeratorId
        ).toList();
      }

      debugPrint('✅ Loaded ${_messages.length} messages for ${widget.enumeratorName}');
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('❌ Error loading messages: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _sendResponse() async {
    if (_responseController.text.trim().isEmpty || _replyingTo == null) return;

    final response = _responseController.text.trim();
    _responseController.clear();

    try {
      await ApiService.instance.respondToMessage(_replyingTo!.id!, response);

      setState(() {
        final index = _messages.indexWhere((m) => m.id == _replyingTo!.id);
        if (index != -1) {
          _messages[index] = _messages[index].copyWith(
            response: response,
            isAnswered: true,
          );
        }
        _replyingTo = null;
        _hasChanges = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Jawaban terkirim! ✅'), backgroundColor: Colors.green, duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _onBack() {
    Navigator.pop(context, _hasChanges);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
        canPop: false,
        onPopInvoked: (didPop) {
          if (didPop) return;
          _onBack();
        },
        child:Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.enumeratorName),
                Text(
                  'Enumerator',
                  style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8)),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadMessages,
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _messages.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text('Belum ada pesan', style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                )
                    : RefreshIndicator(
                  onRefresh: _loadMessages,
                  child: ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) => _buildMessageItem(_messages[index]),
                  ),
                ),
              ),
              _buildResponseInput(),
            ],
          ),
        )
    );
  }

  Widget _buildMessageItem(Message message) {
    final isFromEnumerator = message.senderId == widget.enumeratorId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Enumerator's question
        if (isFromEnumerator)
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8, right: 48),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message.content),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat('HH:mm').format(message.timestamp),
                        style: TextStyle(color: Colors.grey[600], fontSize: 10),
                      ),
                      if (!message.isAnswered) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => setState(() => _replyingTo = message),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Jawab',
                              style: TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),

        // Response (if any)
        if (message.response != null && message.response!.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(bottom: 16, left: 48),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 14, color: Colors.green.shade700),
                      const SizedBox(width: 4),
                      Text(
                        'Anda',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(message.response!),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildResponseInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyingTo != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Membalas:',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _replyingTo!.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _replyingTo = null),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _responseController,
                  decoration: InputDecoration(
                    hintText: _replyingTo != null ? 'Ketik jawaban...' : 'Pilih pesan untuk dijawab',
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  enabled: _replyingTo != null,
                  maxLines: null,
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: _replyingTo != null ? Colors.green : Colors.grey,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 20),
                  onPressed: _replyingTo != null ? _sendResponse : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}