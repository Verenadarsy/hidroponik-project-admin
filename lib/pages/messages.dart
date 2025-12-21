import 'package:flutter/material.dart';
import '../services/shared.dart';
import '../services/api.dart';
import '../models/message_model.dart';
import 'chat_room_detail.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  // Color theme
  final Color darkGreen = const Color(0xFF456028);
  final Color mediumGreen = const Color(0xFF94A65E);
  final Color lightGreen = const Color(0xFFDDDDA1);

  // State
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  String? _token;

  // Thread management
  final Map<int, ChatThread> _chatThreads = {}; // Key: sender_id

  // Filter
  String _filter = 'all'; // 'all', 'unread', 'replied'
  int _totalUnread = 0;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    try {
      setState(() => _isLoading = true);

      _token = await SharedService.getToken();
      if (_token == null) {
        throw Exception('Please login again');
      }

      // Load semua messages untuk admin
      final messages = await ApiService.getAdminMessages(_token!);

      // Process messages into threads
      await _processMessagesIntoThreads(messages);

      setState(() {
        _isLoading = false;
        _hasError = false;
      });
    } catch (e) {
      print('❌ Error loading messages: $e');
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Failed to load messages';
        _chatThreads.clear();
      });
    }
  }

  Future<void> _processMessagesIntoThreads(List<AdminMessage> messages) async {
    // Reset threads
    _chatThreads.clear();
    _totalUnread = 0;

    // Group messages by sender
    final Map<int, List<AdminMessage>> messagesBySender = {};

    for (var msg in messages) {
      if (msg.senderId == null) continue;

      final senderId = msg.senderId!;
      if (!messagesBySender.containsKey(senderId)) {
        messagesBySender[senderId] = [];
      }
      messagesBySender[senderId]!.add(msg);

      // Count unread
      if (!msg.isRead) _totalUnread++;
    }

    // Create thread for each sender
    for (var senderId in messagesBySender.keys) {
      final senderMessages = messagesBySender[senderId]!;
      senderMessages.sort(
        (a, b) => (a.timestamp ?? DateTime.now()).compareTo(
          b.timestamp ?? DateTime.now(),
        ),
      );

      // Get sender info from first message
      final firstMsg = senderMessages.first;
      final senderName = firstMsg.sender?.name ?? 'User $senderId';
      final senderEmail = firstMsg.sender?.email ?? 'user@email.com';

      // Calculate unread for this thread
      final threadUnread = senderMessages.where((m) => !m.isRead).length;

      // Last message time
      final lastMsg = senderMessages.last;

      // Create thread
      final thread = ChatThread(
        senderId: senderId,
        senderName: senderName,
        senderEmail: senderEmail,
        lastMessageTime: lastMsg.timestamp ?? DateTime.now(),
        lastMessageId: lastMsg.id,
        unreadCount: threadUnread,
      );

      // Add all messages to thread
      for (var msg in senderMessages) {
        thread.messages.add(
          ChatMessage(
            id: msg.id,
            content: msg.message ?? '',
            senderId: msg.senderId!,
            isAdmin: false, // Message from user
            timestamp: msg.timestamp ?? DateTime.now(),
            isRead: msg.isRead,
          ),
        );
      }

      _chatThreads[senderId] = thread;

      // Load replies for this thread
      await _loadRepliesForThread(senderId);
    }
  }

  Future<void> _loadRepliesForThread(int senderId) async {
    try {
      if (_token == null) return;

      final thread = _chatThreads[senderId];
      if (thread == null || thread.lastMessageId == null) return;

      // Load replies for the last message (as thread starter)
      final replies = await ApiService.getMessageReplies(
        _token!,
        thread.lastMessageId!,
      );

      if (replies.isNotEmpty) {
        setState(() {
          // Add replies to thread
          for (var reply in replies) {
            thread.messages.add(
              ChatMessage(
                id: reply.id,
                content: reply.content,
                senderId: reply.isAdmin ? 0 : senderId, // 0 for admin
                isAdmin: reply.isAdmin,
                timestamp: reply.timestamp,
                isRead: true,
              ),
            );
          }

          // Sort by timestamp
          thread.messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

          // Update last message time
          if (thread.messages.isNotEmpty) {
            thread.lastMessageTime = thread.messages.last.timestamp;
          }
        });
      }
    } catch (e) {
      print('❌ Error loading replies for thread $senderId: $e');
    }
  }

  void _updateUnreadCounts() {
    int total = 0;

    for (var thread in _chatThreads.values) {
      thread.unreadCount = thread.messages
          .where((m) => !m.isAdmin && !m.isRead)
          .length;
      total += thread.unreadCount;
    }

    setState(() => _totalUnread = total);
  }

  Future<void> _markThreadAsRead(int senderId) async {
    try {
      final thread = _chatThreads[senderId];
      if (thread == null || _token == null) return;

      // Find unread user messages
      final unreadMessages = thread.messages
          .where((m) => !m.isAdmin && !m.isRead)
          .toList();

      for (var msg in unreadMessages) {
        if (msg.id != null) {
          await ApiService.markAdminMessageAsRead(_token!, msg.id!);
          msg.isRead = true;
        }
      }

      _updateUnreadCounts();

      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Marked as read'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      print('❌ Error marking as read: $e');
    }
  }

  List<ChatThread> get _filteredThreads {
    final threads = _chatThreads.values.toList();

    // Sort by last message time (newest first)
    threads.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));

    return threads.where((thread) {
      switch (_filter) {
        case 'unread':
          return thread.unreadCount > 0;
        case 'replied':
          return thread.messages.any((m) => m.isAdmin);
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Messages',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: darkGreen,
        iconTheme: IconThemeData(color: Colors.white),
        actions: _buildAppBarActions(),
      ),
      body: _buildBody(),
    );
  }

  List<Widget> _buildAppBarActions() {
    return [
      // Filter dropdown
      PopupMenuButton<String>(
        onSelected: (value) => setState(() => _filter = value),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'all',
            child: Row(
              children: [
                Icon(Icons.all_inbox, color: darkGreen),
                SizedBox(width: 8),
                Text('All Threads'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'unread',
            child: Row(
              children: [
                Icon(Icons.mark_email_unread, color: Colors.blue),
                SizedBox(width: 8),
                Text('Unread'),
                if (_totalUnread > 0) ...[
                  SizedBox(width: 8),
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: Colors.blue,
                    child: Text(
                      '$_totalUnread',
                      style: TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ),
          PopupMenuItem(
            value: 'replied',
            child: Row(
              children: [
                Icon(Icons.reply, color: Colors.green),
                SizedBox(width: 8),
                Text('Replied'),
              ],
            ),
          ),
        ],
        icon: Icon(Icons.filter_list, color: Colors.white),
      ),
      // Refresh button
      IconButton(
        icon: Icon(Icons.refresh, color: Colors.white),
        onPressed: _loadMessages,
        tooltip: 'Refresh messages',
      ),
    ];
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: darkGreen),
            SizedBox(height: 16),
            Text('Loading messages...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text(
                'Failed to load',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              SizedBox(height: 8),
              Text(
                _errorMessage ?? 'Please try again',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadMessages,
                icon: Icon(Icons.refresh),
                label: Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: darkGreen,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _buildInbox();
  }

  Widget _buildInbox() {
    final threads = _filteredThreads;

    if (threads.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _filter == 'unread'
                  ? Icons.mark_email_unread_outlined
                  : Icons.forum_outlined,
              size: 80,
              color: Colors.grey.shade300,
            ),
            SizedBox(height: 16),
            Text(
              _filter == 'all'
                  ? 'No messages yet'
                  : _filter == 'unread'
                  ? 'No unread messages'
                  : 'No replied threads',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Messages from users will appear here',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMessages,
      color: darkGreen,
      child: ListView.builder(
        padding: EdgeInsets.all(8),
        itemCount: threads.length,
        itemBuilder: (context, index) {
          final thread = threads[index];
          return _buildThreadTile(thread);
        },
      ),
    );
  }

  Widget _buildThreadTile(ChatThread thread) {
    final hasUnread = thread.unreadCount > 0;
    final hasReplied = thread.messages.any((m) => m.isAdmin);
    final lastMessage = thread.messages.isNotEmpty
        ? thread.messages.last
        : null;

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: hasUnread ? 2 : 1,
      color: hasUnread ? Colors.blue.shade50 : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: hasUnread
              ? Colors.blue.shade100
              : Colors.grey.shade200,
          child: Text(
            thread.senderName.substring(0, 1).toUpperCase(),
            style: TextStyle(
              color: hasUnread ? Colors.blue.shade800 : Colors.grey.shade700,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                thread.senderName,
                style: TextStyle(
                  fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                  color: hasUnread ? darkGreen : Colors.grey.shade800,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasUnread)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${thread.unreadCount}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            Text(
              thread.senderEmail,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 4),
            if (lastMessage != null)
              Text(
                lastMessage.content.length > 60
                    ? '${lastMessage.content.substring(0, 60)}...'
                    : lastMessage.content,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                  fontStyle: lastMessage.isAdmin ? FontStyle.italic : null,
                ),
              ),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.access_time, size: 12, color: Colors.grey),
                SizedBox(width: 4),
                Text(
                  _formatTimeAgo(thread.lastMessageTime),
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                Spacer(),
                if (hasReplied)
                  Row(
                    children: [
                      Icon(Icons.reply, size: 12, color: Colors.green),
                      SizedBox(width: 2),
                      Text(
                        'Replied',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'mark_read' && hasUnread) {
              _markThreadAsRead(thread.senderId);
            } else if (value == 'delete') {
              _showDeleteThreadDialog(thread);
            }
          },
          itemBuilder: (context) => [
            if (hasUnread)
              PopupMenuItem(
                value: 'mark_read',
                child: Row(
                  children: [
                    Icon(Icons.mark_email_read, size: 18, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Mark as Read'),
                  ],
                ),
              ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Delete Thread'),
                ],
              ),
            ),
          ],
        ),
        onTap: () async {
          // Navigate to chat room detail
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatRoomDetailPage(
                thread: thread,
                token: _token!,
              ),
            ),
          );

          // Refresh if needed
          if (result == true) {
            _loadMessages();
          }
        },
      ),
    );
  }

  void _showDeleteThreadDialog(ChatThread thread) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Conversation?'),
        content: Text(
          'Delete all messages with ${thread.senderName}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteThread(thread.senderId);
            },
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _deleteThread(int senderId) async {
    try {
      // TODO: Implement delete all messages with this sender
      // For now, just remove from UI
      setState(() {
        _chatThreads.remove(senderId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Conversation deleted'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('❌ Error deleting thread: $e');
    }
  }

  String _formatTimeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${date.day}/${date.month}/${date.year}';
  }
}

class ChatThread {
  final int senderId;
  final String senderName;
  final String senderEmail;
  List<ChatMessage> messages = [];
  DateTime lastMessageTime;
  int? lastMessageId;
  int unreadCount;

  ChatThread({
    required this.senderId,
    required this.senderName,
    required this.senderEmail,
    required this.lastMessageTime,
    this.lastMessageId,
    this.unreadCount = 0,
  });
}

class ChatMessage {
  final int? id;
  final String content;
  final int senderId;
  final bool isAdmin;
  final DateTime timestamp;
  bool isRead;

  ChatMessage({
    this.id,
    required this.content,
    required this.senderId,
    required this.isAdmin,
    required this.timestamp,
    this.isRead = true,
  });
}