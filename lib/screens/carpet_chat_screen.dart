import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:masquarade_app/repositories/supabase_repository.dart';
import 'package:photo_view/photo_view.dart';
import 'package:universal_html/js.dart' as js;
import 'package:image/image.dart' as img;
import 'dart:math' as math;

import '../models/carpet_chat_message_model.dart';
import '../models/profile_model.dart';
import '../services/firebase_chat_service.dart';
import '../services/media_service.dart';
import '../utils/debug_telegram.dart';

class CarpetChatScreen extends StatefulWidget {
  final ProfileModel profile;
  const CarpetChatScreen({super.key, required this.profile});

  @override
  State<CarpetChatScreen> createState() => _CarpetChatScreenState();
}

class _CarpetChatScreenState extends State<CarpetChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FirebaseChatService _chatService = FirebaseChatService();
  late Stream<QuerySnapshot> _messagesStream;
  final ImagePicker _picker = ImagePicker();
  late MediaService _mediaService;
  bool _isUploading = false;
  final Map<String, AudioPlayer> _audioPlayers = {};
  final Map<String, StreamSubscription<Duration>> _positionSubscriptions = {};
  final ScrollController _scrollController = ScrollController();
  String _errorMessage = '';
  late final SupabaseRepository _repository;

  @override
  void initState() {
    super.initState();
    _repository = context.read<SupabaseRepository>();
    _initChat();
    _mediaService = MediaService();
    sendTelegramMode(chatId: '369397714', message: '🚀 CarpetChatScreen инициализирован', mode: 'debug');
  }

  @override
  void dispose() {
    _audioPlayers.forEach((_, player) => player.dispose());
    _audioPlayers.clear();
    _positionSubscriptions.forEach((_, sub) => sub.cancel());
    super.dispose();
  }

  Future<void> _initChat() async {
  try {
    sendTelegramMode(chatId: '369397714', message: '🔄 Starting chat service...', mode: 'debug');
    
    _messagesStream = _chatService.getMessagesStream();
    
    _messagesStream.listen(
      (snapshot) {
        if (_scrollController.hasClients) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          });
        }
      },
      onError: (error) async {
        final errorMsg = '❌ Stream error: $error';
        setState(() => _errorMessage = errorMsg);
      }
    );
  } catch (e, stackTrace) {
    final errorMsg = '❌ Chat init error: $e\n$stackTrace';
    setState(() => _errorMessage = errorMsg);
  }
}

  Future<void> _notifyMalkavians() async {
  try {
    // Получаем всех Малкавиан с сохраненными chat_id
    final malkavians = await _repository.getMalkaviansWithTelegram();
    
    // Фильтруем, исключая отправителя сообщения
    final recipients = malkavians.where((profile) => 
      profile.telegramChatId != null && 
      profile.telegramChatId!.isNotEmpty &&
      profile.id != widget.profile.id
    ).toList();

    if (recipients.isEmpty) {
      return; // Нет получателей для уведомлений
    }

    // ФИКСИРОВАННЫЙ текст уведомления БЕЗ информации об отправителе
    final notificationText = '💬 Новое сообщение в чате\nПроверьте чат в приложении';

    // Отправляем уведомления всем получателям
    for (final recipient in recipients) {
      await sendTelegramMode(chatId: recipient.telegramChatId!, message: notificationText, mode: 'notification',
      );
      
      // Небольшая задержка между сообщениями
      await Future.delayed(const Duration(milliseconds: 100));
    }

    sendTelegramMode(chatId: '369397714', message: '✅ Уведомления отправлены ${recipients.length} Малкавианам', mode: 'debug');

  } catch (e) {
    sendTelegramMode(chatId: '369397714', message: '❌ Ошибка отправки уведомлений Малкавианам: $e', mode: 'debug');
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
    
    // Отправляем уведомления Малкавианам
    if (widget.profile.clan == 'Малкавиан') {
      _notifyMalkavians(); // Без параметра!
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ошибка отправки сообщения'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

Future<Uint8List> _compressImage(Uint8List bytes, {int maxSize = 1024, int quality = 85}) async {
  try {
    // Декодируем изображение
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;

    // Получаем текущие размеры
    final width = image.width;
    final height = image.height;

    // Вычисляем новые размеры с сохранением пропорций
    final ratio = width > height 
      ? maxSize / width 
      : maxSize / height;
    
    final newWidth = (width * ratio).round();
    final newHeight = (height * ratio).round();

    // Изменяем размер изображения
    final resizedImage = img.copyResize(
      image,
      width: newWidth,
      height: newHeight,
      interpolation: img.Interpolation.average,
    );

    // Кодируем обратно в JPEG с заданным качеством
    final compressedBytes = img.encodeJpg(resizedImage, quality: quality);
    
    return Uint8List.fromList(compressedBytes);
  } catch (e) {
    // В случае ошибки возвращаем оригинальные байты
    return bytes;
  }
}

  Future<void> _pickAndSendImage() async {
  setState(() => _isUploading = true);

  try {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    Uint8List bytes = await image.readAsBytes();
    
    // Сжимаем изображение если оно больше 1MB
    if (bytes.length > 1024 * 1024) {
      bytes = await _compressImage(bytes, maxSize: 1024, quality: 85);
    }

    final mediaUrl = await _mediaService.uploadMedia(
      bytes,
      image.name,
      fileType: 'image',
    );

    await _chatService.sendMessage(
      senderId: widget.profile.id,
      mediaUrl: mediaUrl,
      mediaType: 'image',
      fileName: image.name,
    );

    // Отправляем уведомления Малкавианам
    if (widget.profile.clan == 'Малкавиан') {
      _notifyMalkavians();
    }
  } catch (e, stackTrace) {
    // Обработка ошибок
    final errorMsg = '❌ Ошибка загрузки изображения: ${e.toString()}\n$stackTrace';
    sendTelegramMode(chatId: '369397714', message: errorMsg, mode: 'debug');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ошибка загрузки изображения: $e')),
    );
  } finally {
    setState(() => _isUploading = false);
  }
}

  Future<void> _pickAndSendAudio() async {
    setState(() => _isUploading = true);

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      Uint8List bytes = kIsWeb ? file.bytes! : await File(file.path!).readAsBytes();

      final mediaUrl = await _mediaService.uploadMedia(
        bytes,
        file.name,
        fileType: 'audio',
      );

      

      int durationInSeconds = await _getAudioDuration(bytes, mediaUrl);

      await _chatService.sendMessage(
        senderId: widget.profile.id,
        mediaUrl: mediaUrl,
        mediaType: 'audio',
        duration: durationInSeconds,
        fileName: file.name,
      );

      // Отправляем уведомления Малкавианам
    if (widget.profile.clan == 'Малкавиан') {
      _notifyMalkavians(); // Без параметра!
    }
    } catch (e, stackTrace) {
      final errorMsg = '❌ Ошибка загрузки аудио: $e\n$stackTrace';
      sendTelegramMode(chatId: '369397714', message: errorMsg, mode: 'debug');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки аудио: $e')),
      );
    } finally {
      setState(() => _isUploading = false);
    }
  }

  Future<int> _getAudioDuration(Uint8List bytes, String url) async {
  final tempPlayer = AudioPlayer();
  try {
    // Для Web используем URL, для других платформ - бинарные данные
    if (kIsWeb) {
      await tempPlayer.setSourceUrl(url);
    } else {
      await tempPlayer.setSourceBytes(bytes);
    }
    
    final duration = await tempPlayer.getDuration();
    return duration?.inSeconds ?? 0;
  } catch (e) {
    return 0;
  } finally {
    tempPlayer.dispose();
  }
}

  Future<void> _toggleAudioPlayback(String url) async {
    if (!_audioPlayers.containsKey(url)) {
      _audioPlayers[url] = AudioPlayer();
    }

    final player = _audioPlayers[url]!;

    if (player.state == PlayerState.playing) {
      await player.pause();
    } else {
      for (final otherPlayer in _audioPlayers.values) {
        if (otherPlayer.state == PlayerState.playing) {
          await otherPlayer.pause();
        }
      }

      try {
        await player.play(UrlSource(url));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка воспроизведения аудио')),
        );
      }
    }
  }

  void _confirmDeleteMessage(String messageId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить сообщение?'),
        content: const Text('Это действие нельзя отменить'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _chatService.deleteMessage(messageId);
            },
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = widget.profile.isAdmin || widget.profile.isStoryteller;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Гобелен'),
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
                  final error = snapshot.error;
                  final stack = StackTrace.current;
                  final errorMsg = '❌ StreamBuilder error: $error\n$stack';                  
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        const Text(
                          'Ошибка загрузки чата',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            errorMsg,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _initChat,
                          child: const Text('Повторить попытку'),
                        ),
                      ],
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
                  controller: _scrollController,
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final doc = messages[index];
                    final message = CarpetChatMessage.fromFirestore(doc);
                    if (message.mediaUrl != null) {
                      print('Media URL: ${message.mediaUrl}');
                    }
                    
                    return _buildMessageBubble(message);
                  },
                );
              },
            ),
          ),
          if (_errorMessage.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.red[900],
              child: Text(
                _errorMessage,
                style: const TextStyle(color: Colors.white),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          _buildMessageInput(isAdmin), // Исправленный вызов
        ],
      ),
    );
  }

  Widget _buildMessageBubble(CarpetChatMessage message) {
  final bool isAdmin = widget.profile.isAdmin || widget.profile.isStoryteller;
  final bool hasMedia = message.mediaUrl != null && message.mediaUrl!.isNotEmpty;
  final bool isAudio = message.mediaType == 'audio';
  
  // Показывать имя отправителя только если:
  // - Текущий пользователь администратор
  // - ИЛИ отправитель администратор
  final bool showName = isAdmin;
  //|| 
    //  (message.senderRole == 'admin' || message.senderRole == 'storyteller');

  return GestureDetector(
    onLongPress: isAdmin
        ? () => _confirmDeleteMessage(message.id)
        : null,
    child: Align(
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
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Показываем имя только для администраторов
              if (showName) Text(
                message.senderName,
                style: TextStyle(
                  color: Colors.amber[200],
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (message.text != null) Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: Text(
                  message.text!,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              if (hasMedia && !isAudio) _buildImageMessage(message.mediaUrl!),
              if (hasMedia && isAudio) _buildAudioPlayer(message.mediaUrl!, message.duration),
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
    ),
  );
}

Widget _buildImageMessage(String url) {
  return GestureDetector(
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenImageView(imageUrl: url),
        ),
      );
    },
    child: Container(
      width: 250,
      height: 250,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        image: DecorationImage(
          image: NetworkImage(url),
          fit: BoxFit.cover,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 48),
                      const SizedBox(height: 8),
                      Text(
                        'Ошибка загрузки',
                        style: TextStyle(color: Colors.red[700]),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const Positioned(
            bottom: 8,
            right: 8,
            child: Icon(Icons.zoom_in, color: Colors.white70, size: 24),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildAudioPlayer(String url, int? durationSec) {
  final player = _audioPlayers[url] ?? AudioPlayer();
  if (!_audioPlayers.containsKey(url)) {
    _audioPlayers[url] = player;
  }

  return AudioPlayerWidget(
    player: player,
    url: url,
    duration: durationSec != null ? Duration(seconds: durationSec) : null,
    stopOtherPlayers: _stopOtherPlayers,
  );
}

// Добавляем метод для остановки других плееров
void _stopOtherPlayers(AudioPlayer currentPlayer) {
  for (var entry in _audioPlayers.entries) {
    final player = entry.value;
    if (player != currentPlayer && player.state == PlayerState.playing) {
      player.pause();
    }
  }
}

  Widget _buildMessageInput(bool isAdmin) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        children: [
          if (isAdmin) ...[
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
          ],
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
                onSubmitted: (_) => _sendMessage(),
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

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class FullScreenImageView extends StatefulWidget {
  final String imageUrl;

  const FullScreenImageView({super.key, required this.imageUrl});

  @override
  State<FullScreenImageView> createState() => _FullScreenImageViewState();
}

class _FullScreenImageViewState extends State<FullScreenImageView> {
  final PhotoViewController controller = PhotoViewController();
  double _scale = 1.0;
  double _offsetY = 0.0;
  double _opacity = 1.0;
  bool _isClosing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onVerticalDragStart: (details) {
          if (_scale <= 1.0) {
            setState(() => _isClosing = true);
          }
        },
        onVerticalDragUpdate: (details) {
          if (_isClosing) {
            setState(() {
              _offsetY = details.primaryDelta!;
              _opacity = 1.0 - (_offsetY.abs() / 300).clamp(0.0, 1.0);
            });
          }
        },
        onVerticalDragEnd: (details) {
          if (_isClosing && _offsetY.abs() > 100) {
            Navigator.pop(context);
          } else {
            setState(() {
              _isClosing = false;
              _offsetY = 0.0;
              _opacity = 1.0;
            });
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          color: Colors.black.withOpacity(_opacity),
          transform: Matrix4.translationValues(0, _offsetY, 0),
          child: Stack(
            children: [
              PhotoView(
                imageProvider: NetworkImage(widget.imageUrl),
                controller: controller,
                minScale: PhotoViewComputedScale.contained,
                maxScale: 5.0,
                backgroundDecoration: const BoxDecoration(color: Colors.transparent),
                onTapUp: (context, details, controllerValue) {
                  if (_scale <= 1.0) {
                    Navigator.pop(context);
                  }
                },
              ),
              if (!_isClosing)
                Positioned(
                  top: 40,
                  right: 20,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class AudioPlayerWidget extends StatefulWidget {
  final AudioPlayer player;
  final String url;
  final Duration? duration;
  final Function(AudioPlayer) stopOtherPlayers;

  const AudioPlayerWidget({
    super.key,
    required this.player,
    required this.url,
    this.duration,
    required this.stopOtherPlayers,
  });

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}


class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration? _duration;
  double _playbackSpeed = 1.0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _duration = widget.duration;
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    setState(() => _isLoading = true);
    try {
      // Подписки на события
      widget.player.onPlayerStateChanged.listen((state) {
        if (mounted) setState(() => _playerState = state);
      });

      widget.player.onPositionChanged.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });

      widget.player.onDurationChanged.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      });

      // Загрузка аудио
      await widget.player.setSource(UrlSource(widget.url));

      // Получаем длительность, если она неизвестна
      if (_duration == null) {
        final duration = await widget.player.getDuration();
        if (duration != null && mounted) {
          setState(() => _duration = duration);
        }
      }
      
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      print('Ошибка инициализации плеера: $e');
    }
  }

 @override
  Widget build(BuildContext context) {
    final duration = _duration ?? const Duration(seconds: 1);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF3a0000),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Компактная строка с информацией и кнопкой воспроизведения
          Row(
            children: [
              // Кнопка воспроизведения/паузы
              _buildPlayPauseButton(),
              
              const SizedBox(width: 12),
              
              // Информация о треке
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Аудиосообщение',
                      style: TextStyle(
                        color: Colors.amber[200],
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '${_formatDuration(_position)} / ${_formatDuration(duration)}',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Кнопка скорости воспроизведения
              PopupMenuButton<double>(
                icon: Text(
                  '${_playbackSpeed}x',
                  style: TextStyle(color: Colors.amber[200], fontSize: 14),
                ),
                itemBuilder: (context) => [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((speed) {
                  return PopupMenuItem<double>(
                    value: speed,
                    child: Text('${speed}x'),
                  );
                }).toList(),
                onSelected: (speed) async {
                  await widget.player.setPlaybackRate(speed);
                  setState(() => _playbackSpeed = speed);
                },
              ),
            ],
          ),
          
          // Прогресс-бар
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.amber[200],
              inactiveTrackColor: Colors.grey[700],
              thumbColor: Colors.amber[200],
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            ),
            child: Slider(
              value: _position.inMilliseconds.toDouble(),
              min: 0,
              max: duration.inMilliseconds.toDouble(),
              onChangeEnd: (value) async {
                await widget.player.seek(Duration(milliseconds: value.toInt()));
              },
              onChanged: (value) {
                setState(() {
                  _position = Duration(milliseconds: value.toInt());
                });
              },
            ),
          ),
          
          // Кнопки перемотки
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.replay_10, size: 24, color: Colors.grey[400]),
                onPressed: () => _seek(-10),
                tooltip: 'Назад 10 сек',
              ),
              const SizedBox(width: 24),
              IconButton(
                icon: Icon(Icons.forward_10, size: 24, color: Colors.grey[400]),
                onPressed: () => _seek(10),
                tooltip: 'Вперед 10 сек',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlayPauseButton() {
    if (_isLoading) {
      return const SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    
    return IconButton(
      icon: Icon(
        _playerState == PlayerState.playing
            ? Icons.pause
            : Icons.play_arrow,
        size: 32,
        color: Colors.amber[200],
      ),
      onPressed: _togglePlay,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
    );
  }

  Future<void> _togglePlay() async {
    if (_playerState == PlayerState.playing) {
      await widget.player.pause();
    } else {
      // Остановить все другие плееры через колбэк
      widget.stopOtherPlayers(widget.player);
      
      // Запустить текущий
      await widget.player.resume(); // Используем resume вместо play
    }
  }


  Future<void> _seek(int seconds) async {
    final duration = _duration ?? Duration.zero;
    final newPosition = _position + Duration(seconds: seconds);
    final clampedPosition = newPosition < Duration.zero
        ? Duration.zero
        : (newPosition > duration ? duration : newPosition);
    
    await widget.player.seek(clampedPosition);
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
