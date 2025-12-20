class AdminMessage {
  final int? id;
  final int? senderId;
  final int? receiverId;
  final String? message; // Field dari backend: 'message'
  final bool isRead;
  final DateTime? timestamp; // Field dari backend: 'timestamp'
  final Sender? sender;

  AdminMessage({
    this.id,
    this.senderId,
    this.receiverId,
    this.message,
    this.isRead = false,
    this.timestamp,
    this.sender,
  });

  factory AdminMessage.fromJson(Map<String, dynamic> json) {
    try {
      return AdminMessage(
        id: json['id'] is int
            ? json['id']
            : int.tryParse(json['id'].toString()),
        senderId: json['sender_id'] is int
            ? json['sender_id']
            : int.tryParse(json['sender_id'].toString()),
        receiverId: json['receiver_id'] is int
            ? json['receiver_id']
            : int.tryParse(json['receiver_id'].toString()),
        message: json['message']?.toString(), // Field: 'message'
        isRead:
            json['is_read']?.toString() == 'true' ||
            json['is_read'] == true ||
            json['is_read'] == 1,
        timestamp:
            json['timestamp'] != null && json['timestamp'].toString().isNotEmpty
            ? DateTime.parse(json['timestamp'].toString())
            : null,
        sender: json['sender'] != null
            ? Sender.fromJson(Map<String, dynamic>.from(json['sender']))
            : null,
      );
    } catch (e) {
      print('❌ Error parsing AdminMessage: $e');
      print('❌ JSON data: $json');
      rethrow;
    }
  }

  AdminMessage copyWith({
    int? id,
    int? senderId,
    int? receiverId,
    String? message,
    bool? isRead,
    DateTime? timestamp,
    Sender? sender,
  }) {
    return AdminMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      message: message ?? this.message,
      isRead: isRead ?? this.isRead,
      timestamp: timestamp ?? this.timestamp,
      sender: sender ?? this.sender,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'message': message,
      'is_read': isRead,
      'timestamp': timestamp?.toIso8601String(),
      'sender': sender?.toJson(),
    };
  }
}

class Sender {
  final int? id;
  final String? name;
  final String? email;

  Sender({this.id, this.name, this.email});

  factory Sender.fromJson(Map<String, dynamic> json) {
    return Sender(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()),
      name: json['name']?.toString(),
      email: json['email']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'email': email};
  }
}
