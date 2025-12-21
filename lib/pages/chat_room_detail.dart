import 'package:flutter/material.dart';
import '../services/api.dart';
import 'messages.dart';

class ChatRoomDetailPage extends StatefulWidget {
  final ChatThread thread;
  final String token;

  const ChatRoomDetailPage({
    super.key,
    required this.thread,
    required this.token,
  });

  @override
  State<ChatRoomDetailPage> createState() => _ChatRoomDetailPageState();
}

class _ChatRoomDetailPageState extends State<ChatRoomDetailPage> {
  // Color theme
  final Color darkGreen = const Color(0xFF456028);
  final Color mediumGreen = const Color(0xFF94A65E);
  final Color lightGreen = const Color(0xFFDDDDA1);
  final Color userMessageBg = const Color(0xFFF5F5F5);

  // Controllers
  late TextEditingController _replyController;
  bool _isReplying = false;
  bool _isLoadingMessages = false;

  @override
  void initState() {
    super.initState();
    _replyController = TextEditingController();
    _loadReplies();
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _loadReplies() async {
    if (widget.thread.lastMessageId == null) return;

    setState(() => _isLoadingMessages = true);

    try {
      final replies = await ApiService.getMessageReplies(
        widget.token,
        widget.thread.lastMessageId!,
      );

      if (replies.isNotEmpty) {
        setState(() {
          // Clear existing admin replies to avoid duplicates
          widget.thread.messages.removeWhere((m) => m.isAdmin);

          // Add fresh replies from server
          for (var reply in replies) {
            widget.thread.messages.add(
              ChatMessage(
                id: reply.id,
                content: reply.content,
                senderId: reply.isAdmin ? 0 : widget.thread.senderId,
                isAdmin: reply.isAdmin,
                timestamp: reply.timestamp,
                isRead: true,
              ),
            );
          }

          // Sort by timestamp
          widget.thread.messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

          // Update last message time
          if (widget.thread.messages.isNotEmpty) {
            widget.thread.lastMessageTime = widget.thread.messages.last.timestamp;
          }
        });
      }
    } catch (e) {
      print('❌ Error loading replies: $e');
    } finally {
      setState(() => _isLoadingMessages = false);
    }
  }

  Future<void> _sendReply() async {
    final replyText = _replyController.text.trim();

    if (replyText.isEmpty) return;
    if (widget.thread.lastMessageId == null) return;

    try {
      setState(() => _isReplying = true);

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
        widget.thread.messages.add(optimisticReply);
        widget.thread.lastMessageTime = DateTime.now();
      });

      _replyController.clear();

      // Send to server
      final success = await ApiService.sendReply(
        widget.token,
        widget.thread.lastMessageId!,
        replyText,
      );

      if (success) {
        // Mark all user messages as read
        for (var msg in widget.thread.messages.where((m) => !m.isAdmin && !m.isRead)) {
          msg.isRead = true;
          if (msg.id != null) {
            await ApiService.markAdminMessageAsRead(widget.token, msg.id!);
          }
        }

        // Update unread count
        setState(() {
          widget.thread.unreadCount = 0;
        });

        // Reload to get server ID
        await _loadReplies();

        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reply sent'), backgroundColor: Colors.green),
        );
      } else {
        // Remove optimistic reply
        setState(() {
          widget.thread.messages.remove(optimisticReply);
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
      setState(() => _isReplying = false);
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      // Find unread user messages
      final unreadMessages = widget.thread.messages
          .where((m) => !m.isAdmin && !m.isRead)
          .toList();

      for (var msg in unreadMessages) {
        if (msg.id != null) {
          await ApiService.markAdminMessageAsRead(widget.token, msg.id!);
          msg.isRead = true;
        }
      }

      setState(() {
        widget.thread.unreadCount = 0;
      });

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

  @override
  Widget build(BuildContext context) {
    final messages = widget.thread.messages;
    final hasUnread = widget.thread.unreadCount > 0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          widget.thread.senderName,
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: darkGreen,
        iconTheme: IconThemeData(color: Colors.white),
        actions: [
          if (hasUnread)
            IconButton(
              icon: Icon(Icons.mark_email_read),
              onPressed: _markAllAsRead,
              tooltip: 'Mark all as read',
            ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadReplies,
            tooltip: 'Refresh chat',
          ),
        ],
      ),
      body: Column(
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
                    widget.thread.senderName.substring(0, 1).toUpperCase(),
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
                        widget.thread.senderName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: darkGreen,
                        ),
                      ),
                      Text(
                        widget.thread.senderEmail,
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                if (hasUnread)
                  ElevatedButton.icon(
                    onPressed: _markAllAsRead,
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

          // Loading indicator
          if (_isLoadingMessages)
            Container(
              padding: EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: darkGreen,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Loading messages...',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
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
                      return _buildChatBubble(msg);
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
                            controller: _replyController,
                            decoration: InputDecoration(
                              hintText: 'Type your reply...',
                              border: InputBorder.none,
                            ),
                            maxLines: 3,
                            minLines: 1,
                            onSubmitted: (_) {
                              if (!_isReplying) _sendReply();
                            },
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.attach_file, color: Colors.grey),
                          onPressed: () {
                            // TODO: Implement file attachment
                          },
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
                    icon: _isReplying
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(Icons.send, color: Colors.white),
                    onPressed: _isReplying ? null : _sendReply,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage msg) {
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
                widget.thread.senderName.substring(0, 1).toUpperCase(),
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
                      widget.thread.senderName,
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

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}