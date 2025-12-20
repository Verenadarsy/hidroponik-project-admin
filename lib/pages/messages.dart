import 'package:flutter/material.dart';
import '../services/shared.dart';
import '../services/api.dart';
import '../models/message_model.dart';

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
  final Color adminMessageBg = const Color(0xFFE3F2FD);
  final Color userMessageBg = const Color(0xFFF5F5F5);

  // State
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  String? _token;

  // Thread management
  final Map<int, ChatThread> _chatThreads = {}; // Key: sender_id
  final Map<int, TextEditingController> _replyControllers = {};
  final Map<int, bool> _isReplying = {};
  int? _selectedThreadId; // sender_id yang dipilih

  // Filter
  String _filter = 'all'; // 'all', 'unread', 'replied'
  int _totalUnread = 0;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _replyControllers.values.forEach((c) => c.dispose());
    super.dispose();
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

      // Initialize controller if not exists
      if (!_replyControllers.containsKey(senderId)) {
        _replyControllers[senderId] = TextEditingController();
        _isReplying[senderId] = false;
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

  Future<void> _sendReply(int senderId) async {
    final controller = _replyControllers[senderId];
    final replyText = controller?.text.trim() ?? '';

    if (replyText.isEmpty || _token == null) return;

    try {
      setState(() => _isReplying[senderId] = true);

      final thread = _chatThreads[senderId];
      if (thread == null || thread.lastMessageId == null) return;

      // Add optimistic reply
      final optimisticReply = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch,
        content: replyText,
        senderId: 0, // Admin ID
        isAdmin: true,
        timestamp: DateTime.now(),
        isRead: true,
      );

      setState(() {
        thread.messages.add(optimisticReply);
        thread.lastMessageTime = DateTime.now();
      });

      controller?.clear();

      // Send to server
      final success = await ApiService.sendReply(
        _token!,
        thread.lastMessageId!,
        replyText,
      );

      if (success) {
        // Mark all user messages as read
        for (var msg in thread.messages.where((m) => !m.isAdmin && !m.isRead)) {
          msg.isRead = true;
        }

        // Update unread counts
        _updateUnreadCounts();

        // Reload to get server ID
        await _loadRepliesForThread(senderId);

        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reply sent'), backgroundColor: Colors.green),
        );
      } else {
        // Remove optimistic reply
        setState(() {
          thread.messages.remove(optimisticReply);
        });

        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send reply'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('❌ Error sending reply: $e');
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isReplying[senderId] = false);
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
          _selectedThreadId != null
              ? _chatThreads[_selectedThreadId]?.senderName ?? 'Chat'
              : 'Messages',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: darkGreen,
        iconTheme: IconThemeData(color: Colors.white),
        leading: _selectedThreadId != null
            ? IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: () => setState(() => _selectedThreadId = null),
                tooltip: 'Back to inbox',
              )
            : null,
        actions: _buildAppBarActions(),
      ),
      body: _buildBody(),
    );
  }

  List<Widget> _buildAppBarActions() {
    if (_selectedThreadId != null) {
      final thread = _chatThreads[_selectedThreadId];
      final hasUnread = (thread?.unreadCount ?? 0) > 0;

      return [
        if (hasUnread)
          IconButton(
            icon: Icon(Icons.mark_email_read),
            onPressed: () => _markThreadAsRead(_selectedThreadId!),
            tooltip: 'Mark all as read',
          ),
        IconButton(
          icon: Icon(Icons.refresh),
          onPressed: () {
            if (_selectedThreadId != null) {
              _loadRepliesForThread(_selectedThreadId!);
            }
          },
          tooltip: 'Refresh chat',
        ),
      ];
    }

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

    if (_selectedThreadId != null) {
      return _buildChatRoom(_selectedThreadId!);
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
        onTap: () {
          setState(() => _selectedThreadId = thread.senderId);
        },
      ),
    );
  }

  Widget _buildChatRoom(int senderId) {
    final thread = _chatThreads[senderId];
    if (thread == null) {
      return Center(child: Text('Thread not found'));
    }

    final controller = _replyControllers[senderId] ?? TextEditingController();
    final isReplying = _isReplying[senderId] ?? false;
    final messages = thread.messages;

    return Column(
      children: [
        // Thread header
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.blue.shade100,
                child: Text(
                  thread.senderName.substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    color: Colors.blue.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      thread.senderName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: darkGreen,
                      ),
                    ),
                    Text(
                      thread.senderEmail,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              if (thread.unreadCount > 0)
                ElevatedButton.icon(
                  onPressed: () => _markThreadAsRead(senderId),
                  icon: Icon(Icons.mark_email_read, size: 16),
                  label: Text('Mark Read'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    elevation: 0,
                  ),
                ),
            ],
          ),
        ),

        // Chat messages
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.forum_outlined,
                        size: 64,
                        color: Colors.grey.shade300,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Start a conversation',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[messages.length - 1 - index];
                    return _buildChatBubble(msg, thread.senderName);
                  },
                ),
        ),

        // Reply input
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          decoration: InputDecoration(
                            hintText: 'Type your reply...',
                            border: InputBorder.none,
                          ),
                          maxLines: 3,
                          minLines: 1,
                          onSubmitted: (_) {
                            if (!isReplying) _sendReply(senderId);
                          },
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.attach_file, color: Colors.grey),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [darkGreen, mediumGreen],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: darkGreen.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: isReplying
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(Icons.send, color: Colors.white),
                  onPressed: isReplying ? null : () => _sendReply(senderId),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatBubble(ChatMessage msg, String userName) {
    final isAdmin = msg.isAdmin;

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isAdmin
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isAdmin)
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue.shade100,
              child: Text(
                userName.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  color: Colors.blue.shade800,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

          SizedBox(width: 8),

          Flexible(
            child: Column(
              crossAxisAlignment: isAdmin
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isAdmin)
                  Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text(
                      userName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),

                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.7,
                  ),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isAdmin ? darkGreen : userMessageBg,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        msg.content,
                        style: TextStyle(
                          color: isAdmin ? Colors.white : Colors.black87,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatTime(msg.timestamp),
                            style: TextStyle(
                              fontSize: 10,
                              color: isAdmin
                                  ? Colors.white.withValues(alpha: 0.8)
                                  : Colors.grey.shade600,
                            ),
                          ),
                          SizedBox(width: 8),
                          if (isAdmin)
                            Icon(
                              Icons.done_all,
                              size: 12,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          SizedBox(width: 8),

          if (isAdmin)
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white,
              child: Icon(
                Icons.admin_panel_settings,
                size: 16,
                color: darkGreen,
              ),
            ),
        ],
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
        _replyControllers.remove(senderId)?.dispose();
        _isReplying.remove(senderId);
        if (_selectedThreadId == senderId) {
          _selectedThreadId = null;
        }
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

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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
