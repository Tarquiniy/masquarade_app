import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:masquarade_app/models/carpet_chat_message_model.dart';
import 'package:masquarade_app/models/profile_model.dart';
import 'package:masquarade_app/services/firebase_chat_service.dart';
import 'package:masquarade_app/services/media_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:masquarade_app/utils/debug_telegram.dart';

class CarpetChatScreen extends StatefulWidget {
  final ProfileModel profile;
  const CarpetChatScreen({super.key, required this.profile});

  @override
  State<CarpetChatScreen> createState() => _Carpet_chat_screenState();
}

class _Carpet_chat_screenState extends State<CarpetChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FirebaseChatService _chatService = FirebaseChatService();
  late Stream<QuerySnapshot> _messagesStream;
  final ImagePicker _picker = ImagePicker();
  late MediaService _mediaService;
  bool _isUploading = false;
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  String? _currentPlayingUrl;

  @override
  void initState() {
    super.initState();
    _initChat();
    _mediaService = MediaService(Supabase.instance.client);
    _audioPlayer = AudioPlayer();
  }

  void _initChat() {
    try {
      _messagesStream = _chatService.getMessagesStream();
    } catch (e) {
      sendDebugToTelegram('❌ Ошибка инициализации чата: $e');
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    try {
      _chatService.sendMessage(
        senderId: widget.profile.id,
        text: text,
      );
      _messageController.clear();
    } catch (e) {
      sendDebugToTelegram('❌ Ошибка отправки сообщения: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибка отправки сообщения'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickAndSendImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      setState(() => _isUploading = true);

      final bytes = await image.readAsBytes();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${widget.profile.id}.jpg';

      final mediaUrl = await _mediaService.uploadMedia(
        bytes,
        fileName,
        fileType: 'image'
      );

      await _chatService.sendMessage(
        senderId: widget.profile.id,
        text: null,
        mediaUrl: mediaUrl,
        mediaType: 'image',
      );
    } catch (e) {
      sendDebugToTelegram('❌ Ошибка загрузки изображения: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _pickAndSendAudio() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      setState(() => _isUploading = true);

      Uint8List bytes;
      String fileName = result.files.first.name;

      if (kIsWeb) {
        bytes = result.files.first.bytes!;
      } else {
        final file = File(result.files.first.path!);
        bytes = await file.readAsBytes();
      }

      final mediaUrl = await _mediaService.uploadMedia(
        bytes,
        fileName,
        fileType: 'audio'
      );

      await _chatService.sendMessage(
        senderId: widget.profile.id,
        text: null,
        mediaUrl: mediaUrl,
        mediaType: 'audio',
      );
    } catch (e, stack) {
      sendDebugToTelegram('❌ Ошибка загрузки аудио: $e\n$stack');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки аудио: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _toggleAudioPlayback(String url) async {
    if (_isPlaying && _currentPlayingUrl == url) {
      await _audioPlayer.pause();
      setState(() {
        _isPlaying = false;
      });
    } else {
      if (_currentPlayingUrl != null) {
        await _audioPlayer.stop();
      }

      try {
        await _audioPlayer.play(UrlSource(url));
        setState(() {
          _isPlaying = true;
          _currentPlayingUrl = url;
        });

        _audioPlayer.onPlayerStateChanged.listen((state) {
          if (state == PlayerState.completed) {
            if (mounted) {
              setState(() {
                _isPlaying = false;
                _currentPlayingUrl = null;
              });
            }
          }
        });
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка воспроизведения аудио')),
        );
      }
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('КОВРОЧАТ'),
        backgroundColor: const Color(0xFF4A0000),
      ),
      backgroundColor: const Color(0xFF1a0000),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Ошибка загрузки чата',
                      style: TextStyle(color: Colors.red[300]),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFd4af37)),
                    ),
                  );
                }

                final messages = snapshot.data!.docs;

                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'Чат пуст\nБудьте первым, кто напишет сообщение!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 16,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final doc = messages[index];
                    final message = CarpetChatMessage.fromFirestore(doc);
                    return _buildMessageBubble(message);
                  },
                );
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(CarpetChatMessage message) {
  // Всегда показываем имя отправителя для администраторов
  final bool isAdminViewer = widget.profile.isAdmin || widget.profile.isStoryteller;

  final bool hasMedia = message.mediaUrl != null && message.mediaUrl!.isNotEmpty;
  final bool isAudio = message.mediaType == 'audio';

  return Align(
    alignment: Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.8,
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF2a0000).withOpacity(0.8),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Показываем имя для администраторов
            if (isAdminViewer)
              Text(
                message.senderName,
                style: TextStyle(
                  color: Colors.amber[200],
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            
            if (message.text != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: Text(
                  message.text!,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    height: 1.4,
                  ),
                ),
              ),

              if (hasMedia && !isAudio)
                GestureDetector(
                  onTap: () => _showFullScreenImage(context, message.mediaUrl!),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      constraints: const BoxConstraints(
                        maxWidth: 300,
                        maxHeight: 300,
                      ),
                      child: CachedNetworkImage(
                        imageUrl: message.mediaUrl!,
                        placeholder: (context, url) => Container(
                          color: Colors.grey[900],
                          child: const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFd4af37)),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.red),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),

              if (hasMedia && isAudio)
                _buildAudioPlayer(message.mediaUrl!),

              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _formatTime(message.timestamp.toDate()),
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAudioPlayer(String url) {
    final bool isPlaying = _isPlaying && _currentPlayingUrl == url;
    final double audioProgress = 0.0;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF3a0000),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.amber[200],
            ),
            onPressed: () => _toggleAudioPlayback(url),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Аудиосообщение',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                if (isPlaying)
                  LinearProgressIndicator(
                    value: audioProgress,
                    backgroundColor: Colors.grey[800],
                    color: const Color(0xFFd4af37),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        children: [
          IconButton(
            icon: _isUploading
                ? const CircularProgressIndicator(color: Colors.amber)
                : const Icon(Icons.image, color: Colors.amber),
            onPressed: _isUploading ? null : _pickAndSendImage,
            tooltip: 'Добавить изображение',
          ),
          IconButton(
            icon: const Icon(Icons.mic, color: Colors.amber),
            onPressed: _isUploading ? null : _pickAndSendAudio,
            tooltip: 'Добавить аудио',
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2a0000),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _messageController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Сообщение...',
                  hintStyle: TextStyle(color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                maxLines: 3,
                minLines: 1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: const Color(0xFF8b0000),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.amber),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Stack(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: CachedNetworkImage(
                imageUrl: url,
                placeholder: (context, url) => Container(
                  color: Colors.black,
                  child: const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFd4af37)),
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => const Center(
                  child: Icon(Icons.error, color: Colors.red, size: 48),
                ),
              ),
            ),
            Positioned(
              top: 20,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}