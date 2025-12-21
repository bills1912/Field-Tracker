// lib/screens/chat/admin_chat_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../models/message.dart';

class AdminChatScreen extends StatefulWidget {
  const AdminChatScreen({super.key});

  @override
  State<AdminChatScreen> createState() => _AdminChatScreenState();
}

class _AdminChatScreenState extends State<AdminChatScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Message> _allMessages = [];
  ChatStats? _chatStats;
  bool _isLoading = true;
  String? _selectedMessageType;
  int _offset = 0;
  int _total = 0;
  static const int _limit = 50;

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
    setState(() => _isLoading = true);

    try {
      final stats = await ApiService.instance.getChatStats();
      final messagesResult = await ApiService.instance.getAllMessages(
        messageType: _selectedMessageType,
        limit: _limit,
        offset: _offset,
      );

      setState(() {
        _chatStats = stats;
        _allMessages = messagesResult['messages'] as List<Message>;
        _total = messagesResult['total'] as int;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.campaign),
            tooltip: 'Kirim Broadcast',
            onPressed: _showBroadcastDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.analytics), text: 'Statistik'),
            Tab(icon: Icon(Icons.message), text: 'Semua Pesan'),
            Tab(icon: Icon(Icons.campaign), text: 'Broadcast'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStatsView(),
          _buildAllMessagesView(),
          _buildBroadcastHistoryView(),
        ],
      ),
      floatingActionButton: _tabController.index == 2
          ? FloatingActionButton.extended(
        onPressed: _showBroadcastDialog,
        icon: const Icon(Icons.campaign),
        label: const Text('Kirim Broadcast'),
      )
          : null,
    );
  }

  Widget _buildStatsView() {
    if (_isLoading || _chatStats == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary Cards
            Row(
              children: [
                Expanded(child: _buildStatCard('Total Pesan', _chatStats!.totalMessages, Colors.blue, Icons.message)),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCard('Belum Dijawab', _chatStats!.unansweredMessages, Colors.orange, Icons.hourglass_empty)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildStatCard('Chat AI', _chatStats!.aiMessages, Colors.purple, Icons.smart_toy)),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCard('Chat Supervisor', _chatStats!.supervisorMessages, Colors.green, Icons.person)),
              ],
            ),
            const SizedBox(height: 12),
            _buildStatCard('Broadcast Terkirim', _chatStats!.broadcastMessages, Colors.amber, Icons.campaign),

            const SizedBox(height: 24),

            // Daily Chart
            const Text(
              'Aktivitas 7 Hari Terakhir',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildDailyChart(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, int value, Color color, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    value.toString(),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyChart() {
    if (_chatStats == null || _chatStats!.dailyStats.isEmpty) {
      return Container(
        height: 150,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: Text('Tidak ada data')),
      );
    }

    final maxCount = _chatStats!.dailyStats.map((e) => e.count).reduce((a, b) => a > b ? a : b);

    return Container(
      height: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: _chatStats!.dailyStats.map((stat) {
          final height = maxCount > 0 ? (stat.count / maxCount) * 100 : 0.0;
          final date = DateTime.tryParse(stat.date);

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    stat.count.toString(),
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: height.clamp(10, 100).toDouble(),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    date != null ? DateFormat('dd/MM').format(date) : stat.date,
                    style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAllMessagesView() {
    return Column(
      children: [
        // Filter
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  value: _selectedMessageType,
                  decoration: const InputDecoration(
                    labelText: 'Filter Tipe',
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Semua')),
                    DropdownMenuItem(value: 'ai', child: Text('AI')),
                    DropdownMenuItem(value: 'supervisor', child: Text('Supervisor')),
                    DropdownMenuItem(value: 'broadcast', child: Text('Broadcast')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedMessageType = value;
                      _offset = 0;
                    });
                    _loadData();
                  },
                ),
              ),
              const SizedBox(width: 16),
              Text('Total: $_total', style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),

        // Messages List
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _allMessages.isEmpty
              ? const Center(child: Text('Tidak ada pesan'))
              : RefreshIndicator(
            onRefresh: _loadData,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _allMessages.length,
              itemBuilder: (context, index) => _buildMessageItem(_allMessages[index]),
            ),
          ),
        ),

        // Pagination
        if (_total > _limit)
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _offset > 0
                      ? () {
                    setState(() => _offset = (_offset - _limit).clamp(0, _total));
                    _loadData();
                  }
                      : null,
                ),
                Text('${_offset + 1} - ${(_offset + _limit).clamp(0, _total)} dari $_total'),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _offset + _limit < _total
                      ? () {
                    setState(() => _offset += _limit);
                    _loadData();
                  }
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMessageItem(Message message) {
    final senderName = message.sender?['username'] ?? message.sender?['email'] ?? 'Unknown';
    final receiverName = message.receiver?['username'] ?? message.receiver?['email'];

    Color typeColor;
    IconData typeIcon;
    String typeLabel;

    switch (message.messageType) {
      case MessageType.ai:
        typeColor = Colors.purple;
        typeIcon = Icons.smart_toy;
        typeLabel = 'AI';
        break;
      case MessageType.supervisor:
        typeColor = Colors.green;
        typeIcon = Icons.person;
        typeLabel = 'Supervisor';
        break;
      case MessageType.broadcast:
        typeColor = Colors.amber;
        typeIcon = Icons.campaign;
        typeLabel = 'Broadcast';
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: typeColor.withOpacity(0.2),
          child: Icon(typeIcon, color: typeColor, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                senderName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: typeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                typeLabel,
                style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
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
                if (receiverName != null) ...[
                  Text('Kepada: $receiverName', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  const SizedBox(height: 8),
                ],
                const Text('Pesan:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      message.isAnswered ? Icons.check_circle : Icons.hourglass_empty,
                      size: 14,
                      color: message.isAnswered ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      message.isAnswered ? 'Sudah dijawab' : 'Belum dijawab',
                      style: TextStyle(
                        fontSize: 11,
                        color: message.isAnswered ? Colors.green : Colors.orange,
                      ),
                    ),
                    const Spacer(),
                    if (message.isEdited)
                      Text(
                        '(diedit)',
                        style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBroadcastHistoryView() {
    final broadcastMessages = _allMessages.where((m) => m.messageType == MessageType.broadcast).toList();

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (broadcastMessages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.campaign_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('Belum ada broadcast', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Kirim Broadcast Pertama'),
              onPressed: _showBroadcastDialog,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: broadcastMessages.length,
        itemBuilder: (context, index) {
          final message = broadcastMessages[index];
          return _buildBroadcastItem(message);
        },
      ),
    );
  }

  Widget _buildBroadcastItem(Message message) {
    final targetRoles = message.targetRoles ?? ['enumerator', 'supervisor'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.campaign, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    DateFormat('dd MMMM yyyy, HH:mm').format(message.timestamp),
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(message.content, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: targetRoles.map((role) {
                return Chip(
                  label: Text(
                    role == 'enumerator' ? 'Enumerator' : 'Supervisor',
                    style: const TextStyle(fontSize: 11),
                  ),
                  backgroundColor: role == 'enumerator' ? Colors.blue[50] : Colors.green[50],
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
            if (message.targetUserIds != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Dikirim ke ${message.targetUserIds!.length} pengguna',
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showBroadcastDialog() {
    final contentController = TextEditingController();
    final selectedRoles = <String>{'enumerator', 'supervisor'};

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Kirim Broadcast'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pesan ini akan dikirim ke semua pengguna yang dipilih.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: contentController,
                  decoration: const InputDecoration(
                    labelText: 'Isi Pesan',
                    hintText: 'Ketik pesan broadcast...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 5,
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                const Text('Kirim ke:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: const Text('Enumerator'),
                  value: selectedRoles.contains('enumerator'),
                  onChanged: (value) {
                    setDialogState(() {
                      if (value == true) {
                        selectedRoles.add('enumerator');
                      } else {
                        selectedRoles.remove('enumerator');
                      }
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  title: const Text('Supervisor'),
                  value: selectedRoles.contains('supervisor'),
                  onChanged: (value) {
                    setDialogState(() {
                      if (value == true) {
                        selectedRoles.add('supervisor');
                      } else {
                        selectedRoles.remove('supervisor');
                      }
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
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
                if (contentController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Pesan tidak boleh kosong')),
                  );
                  return;
                }

                if (selectedRoles.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Pilih minimal satu target')),
                  );
                  return;
                }

                Navigator.pop(context);

                try {
                  final result = await ApiService.instance.sendBroadcastMessage(
                    content: contentController.text.trim(),
                    targetRoles: selectedRoles.toList(),
                  );

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Broadcast terkirim ke ${result['recipients_count']} pengguna'),
                      backgroundColor: Colors.green,
                    ),
                  );

                  _loadData();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}