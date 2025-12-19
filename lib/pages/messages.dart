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
  final Color darkGreen = const Color(0xFF456028);
  final Color mediumGreen = const Color(0xFF94A65E);
  final Color lightGreen = const Color(0xFFDDDDA1);

  List<AdminMessage> _messages = [];
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  String? _token;
  String _filter = 'all'; // 'all', 'unread', 'read'
  int _unreadCount = 0;

  // Chat room variables
  Map<int, List<ChatMessage>> _chatThreads = {};
  Map<int, TextEditingController> _replyControllers = {};
  Map<int, bool> _isReplying = {};
  int? _selectedThreadId;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    // Dispose all controllers
    _replyControllers.values.forEach((controller) => controller.dispose());
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
        _errorMessage = null;
      });

      _token = await SharedService.getToken();
      if (_token == null || _token!.isEmpty) {
        throw Exception('No authentication token found');
      }

      // Load messages
      final messages = await ApiService.getAdminMessages(_token!);

      // Calculate unread count from messages
      final unreadCount = messages.where((msg) => !msg.isRead).length;

      // Initialize chat threads and controllers
      for (var message in messages) {
        if (!_chatThreads.containsKey(message.id)) {
          _chatThreads[message.id!] = [];
          // Add original message as first in thread
          _chatThreads[message.id!]!.add(
            ChatMessage(
              id: message.id,
              content: message.message ?? '',
              senderName: message.sender?.name ?? 'Unknown',
              senderEmail: message.sender?.email ?? '',
              isAdmin: false,
              timestamp: message.timestamp ?? DateTime.now(),
            ),
          );

          // Initialize reply controller
          _replyControllers[message.id!] = TextEditingController();
          _isReplying[message.id!] = false;
        }

        // Load replies for each message
        await _loadReplies(message.id!);
      }

      setState(() {
        _messages = messages;
        _unreadCount = unreadCount;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading messages: $e');
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Failed to load messages: ${e.toString()}';
        _messages = [];
        _unreadCount = 0;
      });
    }
  }

  Future<void> _loadReplies(int messageId) async {
    try {
      if (_token != null) {
        final replies = await ApiService.getMessageReplies(_token!, messageId);
        if (replies.isNotEmpty) {
          setState(() {
            _chatThreads[messageId]!.addAll(
              replies.map(
                (reply) => ChatMessage(
                  id: reply.id,
                  content: reply.content,
                  senderName: reply.senderName,
                  senderEmail: reply.senderEmail,
                  isAdmin: reply.isAdmin,
                  timestamp: reply.timestamp,
                ),
              ),
            );
          });
        }
      }
    } catch (e) {
      print('Error loading replies for message $messageId: $e');
    }
  }

  Future<void> _sendReply(int messageId) async {
    final controller = _replyControllers[messageId];
    final replyText = controller?.text.trim() ?? '';

    if (replyText.isEmpty) return;

    try {
      setState(() {
        _isReplying[messageId] = true;
      });

      if (_token != null) {
        // Add local message first for instant feedback
        final newReply = ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch, // Temporary ID
          content: replyText,
          senderName: 'Admin',
          senderEmail: 'admin@hydroponic.com',
          isAdmin: true,
          timestamp: DateTime.now(),
        );

        setState(() {
          _chatThreads[messageId]!.add(newReply);
        });

        // Clear text field
        controller?.clear();

        // Send to server
        final success = await ApiService.sendReply(
          _token!,
          messageId,
          replyText,
        );

        if (success) {
          // Reload replies to get server ID
          await _loadReplies(messageId);

          // Mark as read if it was unread
          final message = _messages.firstWhere(
            (msg) => msg.id == messageId,
            orElse: () => AdminMessage(),
          );

          if (!message.isRead) {
            await _markAsRead(messageId);
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Reply sent successfully'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          // Remove the local message if failed
          setState(() {
            _chatThreads[messageId]!.removeLast();
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to send reply'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('Error sending reply: $e');
      // Remove the local message
      if (_chatThreads[messageId]!.isNotEmpty) {
        setState(() {
          _chatThreads[messageId]!.removeLast();
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send reply: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isReplying[messageId] = false;
      });
    }
  }

  Future<void> _markAsRead(int messageId) async {
    try {
      if (_token != null) {
        final success = await ApiService.markAdminMessageAsRead(
          _token!,
          messageId,
        );
        if (success) {
          // Update local message state
          setState(() {
            final index = _messages.indexWhere((msg) => msg.id == messageId);
            if (index != -1) {
              _messages[index] = _messages[index].copyWith(isRead: true);
              // Update unread count
              _unreadCount = _messages.where((msg) => !msg.isRead).length;
            }
          });

          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Message marked as read'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print('Error marking as read: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to mark message as read'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteMessage(int messageId) async {
    try {
      if (_token != null) {
        final success = await ApiService.deleteAdminMessage(_token!, messageId);
        if (success) {
          // Remove message from local list
          final removedMessage = _messages.firstWhere(
            (msg) => msg.id == messageId,
            orElse: () => AdminMessage(),
          );

          setState(() {
            _messages.removeWhere((msg) => msg.id == messageId);
            // Remove chat thread
            _chatThreads.remove(messageId);
            _replyControllers.remove(messageId)?.dispose();
            _isReplying.remove(messageId);

            // Update unread count if the message was unread
            if (!removedMessage.isRead) {
              _unreadCount = _unreadCount > 0 ? _unreadCount - 1 : 0;
            }

            // Close chat if it was open
            if (_selectedThreadId == messageId) {
              _selectedThreadId = null;
            }
          });

          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Message deleted'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print('Error deleting message: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete message'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<AdminMessage> get _filteredMessages {
    switch (_filter) {
      case 'unread':
        return _messages.where((msg) => !msg.isRead).toList();
      case 'read':
        return _messages.where((msg) => msg.isRead).toList();
      default:
        return _messages;
    }
  }

  void _openChatRoom(AdminMessage message) {
    setState(() {
      _selectedThreadId = message.id;
    });
    // Mark as read when opening chat
    if (!message.isRead) {
      _markAsRead(message.id!);
    }
  }

  void _closeChatRoom() {
    setState(() {
      _selectedThreadId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(
              _selectedThreadId != null ? 'Chat Room' : 'Messages',
              style: TextStyle(color: Colors.white),
            ),
            if (_unreadCount > 0 && _selectedThreadId == null) ...[
              SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$_unreadCount',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: darkGreen,
        iconTheme: IconThemeData(color: Colors.white),
        leading: _selectedThreadId != null
            ? IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: _closeChatRoom,
              )
            : null,
        actions: _buildAppBarActions(),
      ),
      body: _buildBody(),
    );
  }

  List<Widget> _buildAppBarActions() {
    if (_selectedThreadId != null) {
      return [
        IconButton(
          icon: Icon(Icons.refresh),
          onPressed: () {
            if (_selectedThreadId != null) {
              _loadReplies(_selectedThreadId!);
            }
          },
        ),
      ];
    }

    return [
      PopupMenuButton<String>(
        onSelected: (value) {
          setState(() => _filter = value);
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'all',
            child: Row(
              children: [
                Icon(Icons.all_inbox, color: darkGreen),
                SizedBox(width: 8),
                Text('All Messages'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'unread',
            child: Row(
              children: [
                Icon(Icons.mark_email_unread, color: Colors.blue),
                SizedBox(width: 8),
                Text('Unread Only'),
                if (_unreadCount > 0) ...[
                  SizedBox(width: 8),
                  Container(
                    padding: EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$_unreadCount',
                      style: TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ],
              ],
            ),
          ),
          PopupMenuItem(
            value: 'read',
            child: Row(
              children: [
                Icon(Icons.mark_email_read, color: Colors.grey),
                SizedBox(width: 8),
                Text('Read Only'),
              ],
            ),
          ),
        ],
        icon: Icon(Icons.filter_list, color: Colors.white),
      ),
      IconButton(
        icon: Icon(Icons.refresh, color: Colors.white),
        onPressed: _loadMessages,
      ),
    ];
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(darkGreen),
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text(
                'Failed to Load Messages',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                _errorMessage ?? 'Unknown error occurred',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              SizedBox(height: 16),
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

    return _buildMessageList();
  }

  Widget _buildMessageList() {
    if (_filteredMessages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.message_outlined, size: 64, color: Colors.grey.shade400),
            SizedBox(height: 16),
            Text(
              _filter == 'all'
                  ? 'No messages yet'
                  : _filter == 'unread'
                  ? 'No unread messages'
                  : 'No read messages',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'All messages from users will appear here',
              style: TextStyle(color: Colors.grey.shade500),
            ),
            SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadMessages,
              icon: Icon(Icons.refresh),
              label: Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: darkGreen,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMessages,
      color: darkGreen,
      child: ListView.builder(
        padding: EdgeInsets.all(16),
        itemCount: _filteredMessages.length,
        itemBuilder: (context, index) {
          final message = _filteredMessages[index];
          final isUnread = !message.isRead;
          final thread = _chatThreads[message.id];
          final replyCount = thread?.where((msg) => msg.isAdmin).length ?? 0;

          return Card(
            margin: EdgeInsets.only(bottom: 12),
            color: isUnread ? Colors.blue.shade50 : null,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              contentPadding: EdgeInsets.all(16),
              leading: Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isUnread ? Colors.blue.shade100 : Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isUnread ? Icons.mark_email_unread : Icons.mark_email_read,
                  color: isUnread ? Colors.blue : Colors.grey,
                  size: 20,
                ),
              ),
              title: Text(
                message.message ?? 'No Message',
                style: TextStyle(
                  fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                  color: isUnread ? darkGreen : Colors.grey.shade700,
                  fontSize: 16,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 14, color: Colors.grey),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          message.sender?.name ?? 'Unknown User',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (replyCount > 0) ...[
                        SizedBox(width: 8),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.reply, size: 10, color: Colors.green),
                              SizedBox(width: 2),
                              Text(
                                '$replyCount',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green.shade800,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.email_outlined, size: 14, color: Colors.grey),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          message.sender?.email ?? 'No Email',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 14, color: Colors.grey),
                      SizedBox(width: 4),
                      Text(
                        _formatDate(message.timestamp),
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      Spacer(),
                      if (isUnread)
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'UNREAD',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue.shade800,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'reply') {
                    _openChatRoom(message);
                  } else if (value == 'read' && isUnread) {
                    _markAsRead(message.id!);
                  } else if (value == 'delete') {
                    _showDeleteConfirmation(message);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'reply',
                    child: Row(
                      children: [
                        Icon(Icons.reply, color: darkGreen),
                        SizedBox(width: 8),
                        Text('Reply'),
                      ],
                    ),
                  ),
                  if (isUnread)
                    PopupMenuItem(
                      value: 'read',
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('Mark as Read'),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete'),
                      ],
                    ),
                  ),
                ],
                icon: Icon(Icons.more_vert, color: Colors.grey),
              ),
              onTap: () {
                _openChatRoom(message);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildChatRoom(int messageId) {
    final message = _messages.firstWhere(
      (msg) => msg.id == messageId,
      orElse: () => AdminMessage(),
    );
    final thread = _chatThreads[messageId] ?? [];
    final controller = _replyControllers[messageId] ?? TextEditingController();
    final isReplying = _isReplying[messageId] ?? false;

    return Column(
      children: [
        // Header with message info
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.blue.shade100,
                    child: Icon(
                      Icons.person,
                      color: Colors.blue.shade800,
                      size: 20,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.sender?.name ?? 'Unknown User',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: darkGreen,
                          ),
                        ),
                        Text(
                          message.sender?.email ?? 'No email',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'delete') {
                        _showDeleteConfirmation(message);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete Conversation'),
                          ],
                        ),
                      ),
                    ],
                    icon: Icon(Icons.more_vert, color: Colors.grey),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Text(
                'Original Message',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 4),
              Text(
                message.message ?? 'No message content',
                style: TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),

        // Chat messages
        Expanded(
          child: thread.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 64,
                        color: Colors.grey.shade300,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No replies yet',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Be the first to reply',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: EdgeInsets.all(16),
                  itemCount: thread.length,
                  itemBuilder: (context, index) {
                    final chatMessage = thread[thread.length - 1 - index];
                    return _buildChatBubble(chatMessage);
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
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: 'Type your reply...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.attach_file),
                      onPressed: () {
                        // TODO: Add attachment functionality
                      },
                    ),
                  ),
                  maxLines: 3,
                  minLines: 1,
                  onSubmitted: (_) {
                    if (!isReplying) {
                      _sendReply(messageId);
                    }
                  },
                ),
              ),
              SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  color: darkGreen,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: darkGreen.withOpacity(0.3),
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
                  onPressed: isReplying
                      ? null
                      : () {
                          _sendReply(messageId);
                        },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatBubble(ChatMessage message) {
    final isAdmin = message.isAdmin;
    final isOriginal = !isAdmin && message.id == _selectedThreadId;

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isAdmin) Expanded(child: SizedBox()),
          if (!isAdmin && !isOriginal)
            CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              radius: 16,
              child: Icon(Icons.person, size: 16, color: Colors.blue.shade800),
            ),
          Expanded(
            flex: 8,
            child: Column(
              crossAxisAlignment: isAdmin
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isOriginal && !isAdmin) ...[
                  Padding(
                    padding: EdgeInsets.only(left: 8, bottom: 4),
                    child: Text(
                      message.senderName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isAdmin ? darkGreen : Colors.grey.shade100,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: isAdmin
                          ? Radius.circular(16)
                          : Radius.circular(4),
                      bottomRight: !isAdmin
                          ? Radius.circular(16)
                          : Radius.circular(4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.content,
                        style: TextStyle(
                          color: isAdmin ? Colors.white : Colors.black87,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        _formatTime(message.timestamp),
                        style: TextStyle(
                          fontSize: 10,
                          color: isAdmin
                              ? Colors.white.withOpacity(0.8)
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isAdmin && !isOriginal)
            CircleAvatar(
              backgroundColor: darkGreen.withOpacity(0.1),
              radius: 16,
              child: Icon(
                Icons.admin_panel_settings,
                size: 16,
                color: darkGreen,
              ),
            ),
          if (!isAdmin) Expanded(child: SizedBox()),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(AdminMessage message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Message'),
        content: Text(
          'Are you sure you want to delete this message and all replies?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMessage(message.id!);
            },
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown date';

    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inSeconds < 60) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    if (difference.inDays == 1) return 'Yesterday';
    if (difference.inDays < 7) return '${difference.inDays}d ago';

    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class ChatMessage {
  final int? id;
  final String content;
  final String senderName;
  final String senderEmail;
  final bool isAdmin;
  final DateTime timestamp;

  ChatMessage({
    this.id,
    required this.content,
    required this.senderName,
    required this.senderEmail,
    required this.isAdmin,
    required this.timestamp,
  });
}
