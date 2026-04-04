import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../providers/auth_provider.dart';
import '../providers/google_calendar_provider.dart';

class VoiceDiaryScreen extends ConsumerStatefulWidget {
  const VoiceDiaryScreen({super.key});

  @override
  ConsumerState<VoiceDiaryScreen> createState() => _VoiceDiaryScreenState();
}

class _VoiceDiaryScreenState extends ConsumerState<VoiceDiaryScreen> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final TextEditingController _textController = TextEditingController();
  bool _ready = false;
  bool _listening = false;
  String _text = '';
  DateTime _selectedDiaryDateTime = DateTime.now();
  final Map<String, bool> _syncingItems = {};
  final Map<String, bool> _editingItems = {};

  String get _uid => ref.read(authStateProvider).valueOrNull?.id ?? '';

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) {
            setState(() {
              _listening = false;
            });
          }
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _text = 'Lỗi speech-to-text: ${error.errorMsg}';
            _listening = false;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _ready = available;
      });
    }
  }

  Future<void> _startListening() async {
    if (!_ready) return;

    setState(() {
      _listening = true;
    });

    await _speech.listen(
      localeId: 'vi_VN',
      onResult: (result) {
        if (mounted) {
          setState(() {
            _text = result.recognizedWords;
            _textController.text = _text;
            _textController.selection = TextSelection.fromPosition(
              TextPosition(offset: _textController.text.length),
            );
          });
        }
      },
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    if (mounted) {
      setState(() {
        _listening = false;
      });
    }
  }

  Future<void> _saveDiary() async {
    final uid = _uid;
    final diaryText = _textController.text.trim();
    if (uid.isEmpty || diaryText.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('voiceDiary')
        .add({
          'text': diaryText,
          'diaryDateTime': Timestamp.fromDate(_selectedDiaryDateTime),
          'createdAt': FieldValue.serverTimestamp(),
        });

    if (mounted) {
      setState(() {
        _text = '';
        _textController.clear();
        _selectedDiaryDateTime = DateTime.now();
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã lưu nhật ký giọng nói')));
    }
  }

  Future<bool> _confirmDeleteDiary() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa nhật ký giọng nói'),
        content: const Text('Bạn có chắc muốn xóa mục nhật ký này không?'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    return shouldDelete ?? false;
  }

  Future<bool> _deleteVoiceDiaryWithCalendar({
    required String voiceDiaryId,
    required String? googleCalendarId,
    required String? googleCalendarName,
  }) async {
    final shouldDelete = await _confirmDeleteDiary();
    if (!shouldDelete) return false;

    try {
      if (googleCalendarId != null) {
        final service = ref.read(googleCalendarServiceProvider);
        final isSignedIn = await service.isSignedIn();

        if (!isSignedIn) {
          final account = await service.signIn();
          if (account == null) {
            throw Exception('Không thể đăng nhập Google để xóa sự kiện');
          }
        }

        await service.deleteEvent(
          calendarId: googleCalendarName ?? 'primary',
          eventId: googleCalendarId,
        );
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('voiceDiary')
          .doc(voiceDiaryId)
          .delete();

      if (mounted) {
        final message = googleCalendarId != null
            ? 'Đã xóa nhật ký và sự kiện trên Google Calendar'
            : 'Đã xóa nhật ký giọng nói';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }

      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Xóa thất bại: ${e.toString()}')),
        );
      }
      return false;
    }
  }

  Future<void> _syncToGoogleCalendar({
    required String voiceDiaryId,
    required String text,
    required DateTime eventDateTime,
  }) async {
    setState(() {
      _syncingItems[voiceDiaryId] = true;
    });

    try {
      final service = ref.read(googleCalendarServiceProvider);
      final isSignedIn = await service.isSignedIn();

      if (!isSignedIn) {
        final account = await service.signIn();
        if (account == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể đăng nhập Google')),
          );
          return;
        }
      }

      final eventTitle = text.trim().isEmpty
          ? 'Nhật ký giọng nói'
          : text.trim();

      final eventId = await service.createEvent(
        calendarId: 'primary',
        title: eventTitle,
        description: text,
        startTime: eventDateTime,
        duration: const Duration(hours: 1),
      );

      if (eventId != null) {
        final uid = _uid;
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('voiceDiary')
            .doc(voiceDiaryId)
            .update({
              'googleCalendarId': eventId,
              'googleCalendarName': 'primary',
              'syncedAt': FieldValue.serverTimestamp(),
            });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã thêm vào Google Calendar')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi đồng bộ: ${e.toString()}')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _syncingItems[voiceDiaryId] = false;
        });
      }
    }
  }

  Future<void> _removeFromGoogleCalendar({
    required String voiceDiaryId,
    required String? googleCalendarId,
    required String? googleCalendarName,
  }) async {
    if (googleCalendarId == null || googleCalendarName == null) return;

    setState(() {
      _syncingItems[voiceDiaryId] = true;
    });

    try {
      final service = ref.read(googleCalendarServiceProvider);
      await service.deleteEvent(
        calendarId: googleCalendarName,
        eventId: googleCalendarId,
      );

      final uid = _uid;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('voiceDiary')
          .doc(voiceDiaryId)
          .update({
            'googleCalendarId': FieldValue.delete(),
            'googleCalendarName': FieldValue.delete(),
            'syncedAt': FieldValue.delete(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa khỏi Google Calendar')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: ${e.toString()}')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _syncingItems[voiceDiaryId] = false;
        });
      }
    }
  }

  Future<void> _editVoiceDiary({
    required String voiceDiaryId,
    required String initialText,
    required DateTime initialDateTime,
    required String? googleCalendarId,
    required String? googleCalendarName,
  }) async {
    final textController = TextEditingController(text: initialText);
    var selectedDateTime = initialDateTime;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setDialogState) {
            Future<void> pickDate() async {
              final pickedDate = await showDatePicker(
                context: context,
                initialDate: selectedDateTime,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );

              if (pickedDate == null) return;

              setDialogState(() {
                selectedDateTime = DateTime(
                  pickedDate.year,
                  pickedDate.month,
                  pickedDate.day,
                  selectedDateTime.hour,
                  selectedDateTime.minute,
                );
              });
            }

            Future<void> pickTime() async {
              final pickedTime = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(selectedDateTime),
              );

              if (pickedTime == null) return;

              setDialogState(() {
                selectedDateTime = DateTime(
                  selectedDateTime.year,
                  selectedDateTime.month,
                  selectedDateTime.day,
                  pickedTime.hour,
                  pickedTime.minute,
                );
              });
            }

            return AlertDialog(
              title: const Text('Chỉnh sửa nhật ký'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: textController,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        hintText: 'Nhập nội dung nhật ký...',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: pickDate,
                          icon: const Icon(Icons.event_outlined),
                          label: Text(
                            DateFormat('dd/MM/yyyy').format(selectedDateTime),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: pickTime,
                          icon: const Icon(Icons.schedule_outlined),
                          label: Text(
                            DateFormat('HH:mm').format(selectedDateTime),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: () {
                    final updatedText = textController.text.trim();
                    if (updatedText.isEmpty) return;

                    Navigator.of(
                      dialogContext,
                    ).pop({'text': updatedText, 'dateTime': selectedDateTime});
                  },
                  child: const Text('Lưu thay đổi'),
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      textController.dispose();
    });

    if (result == null || !mounted) return;

    final updatedText = result['text'] as String;
    final updatedDateTime = result['dateTime'] as DateTime;

    setState(() {
      _editingItems[voiceDiaryId] = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('voiceDiary')
          .doc(voiceDiaryId)
          .update({
            'text': updatedText,
            'diaryDateTime': Timestamp.fromDate(updatedDateTime),
            'updatedAt': FieldValue.serverTimestamp(),
          });

      if (googleCalendarId != null) {
        final service = ref.read(googleCalendarServiceProvider);
        final isSignedIn = await service.isSignedIn();
        if (!isSignedIn) {
          await service.signIn();
        }

        await service.updateEvent(
          calendarId: googleCalendarName ?? 'primary',
          eventId: googleCalendarId,
          title: updatedText,
          description: updatedText,
          startTime: updatedDateTime,
          duration: const Duration(hours: 1),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã cập nhật nhật ký')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cập nhật thất bại: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _editingItems[voiceDiaryId] = false;
        });
      }
    }
  }

  DateTime _dayKey(DateTime dateTime) {
    return DateTime(dateTime.year, dateTime.month, dateTime.day);
  }

  DateTime _resolveDiaryDateTime(Map<String, dynamic> data) {
    return (data['diaryDateTime'] as Timestamp?)?.toDate() ??
        (data['createdAt'] as Timestamp?)?.toDate() ??
        DateTime.now();
  }

  Future<void> _pickDiaryDate() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDiaryDateTime,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (selectedDate == null || !mounted) return;

    setState(() {
      _selectedDiaryDateTime = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        _selectedDiaryDateTime.hour,
        _selectedDiaryDateTime.minute,
      );
    });
  }

  Future<void> _pickDiaryTime() async {
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDiaryDateTime),
    );

    if (selectedTime == null || !mounted) return;

    setState(() {
      _selectedDiaryDateTime = DateTime(
        _selectedDiaryDateTime.year,
        _selectedDiaryDateTime.month,
        _selectedDiaryDateTime.day,
        selectedTime.hour,
        selectedTime.minute,
      );
    });
  }

  String _dayHeaderLabel(DateTime day) {
    return DateFormat('dd/MM/yyyy').format(day);
  }

  Map<DateTime, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _groupVoiceDiaryByDay(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final grouped =
        <DateTime, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};

    for (final doc in docs) {
      final data = doc.data();
      final diaryDateTime = _resolveDiaryDateTime(data);
      final day = _dayKey(diaryDateTime);
      grouped.putIfAbsent(
        day,
        () => <QueryDocumentSnapshot<Map<String, dynamic>>>[],
      );
      grouped[day]!.add(doc);
    }

    for (final entry in grouped.entries) {
      entry.value.sort((a, b) {
        final timeA = _resolveDiaryDateTime(a.data());
        final timeB = _resolveDiaryDateTime(b.data());
        return timeB.compareTo(timeA);
      });
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final uid = _uid;
    final stream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('voiceDiary')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhật ký giọng nói'),
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surface,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nhật ký bằng văn bản hoặc giọng nói',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _textController,
                    minLines: 4,
                    maxLines: 6,
                    onChanged: (value) {
                      _text = value;
                    },
                    decoration: const InputDecoration(
                      hintText: 'Nhập nội dung hoặc bấm mic để nói...',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Thời gian:',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _pickDiaryDate,
                              icon: const Icon(Icons.event_outlined),
                              label: Text(
                                DateFormat(
                                  'dd/MM/yyyy',
                                ).format(_selectedDiaryDateTime),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _pickDiaryTime,
                              icon: const Icon(Icons.schedule_outlined),
                              label: Text(
                                DateFormat(
                                  'HH:mm',
                                ).format(_selectedDiaryDateTime),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _text.isEmpty
                          ? 'Bạn có thể nói để tự điền vào ô văn bản phía trên.'
                          : _text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _listening
                              ? _stopListening
                              : _startListening,
                          icon: Icon(_listening ? Icons.stop : Icons.mic),
                          label: Text(_listening ? 'Dừng' : 'Bắt đầu'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _saveDiary,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Lưu'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _text = '';
                          _textController.clear();
                        });
                      },
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Xóa nội dung'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _ready
                        ? 'Sẵn sàng ghi giọng nói và nhập văn bản'
                        : 'Đang khởi tạo nhận diện giọng nói...',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Lịch sử nhật ký giọng nói',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: stream,
            builder: (context, snap) {
              if (!snap.hasData) return const LinearProgressIndicator();
              final docs = snap.data!.docs;
              if (docs.isEmpty) return const Text('Chưa có nhật ký giọng nói');
              final grouped = _groupVoiceDiaryByDay(docs);
              final days = grouped.keys.toList()
                ..sort((a, b) => b.compareTo(a));

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final day in days) ...[
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _dayHeaderLabel(day),
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ...grouped[day]!.map((d) {
                      final data = d.data();
                      final diaryDateTime = _resolveDiaryDateTime(data);
                      final googleCalendarId =
                          (data['googleCalendarId'] as String?);
                      final isSynced = googleCalendarId != null;
                      final isSyncing = _syncingItems[d.id] ?? false;
                      final isEditing = _editingItems[d.id] ?? false;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Dismissible(
                          key: ValueKey('voice-diary-${d.id}'),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (_) => _deleteVoiceDiaryWithCalendar(
                            voiceDiaryId: d.id,
                            googleCalendarId: googleCalendarId,
                            googleCalendarName:
                                data['googleCalendarName'] as String?,
                          ),
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            decoration: BoxDecoration(
                              color: scheme.errorContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.delete_outline,
                              color: scheme.onErrorContainer,
                            ),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                            ),
                            child: Stack(
                              children: [
                                ListTile(
                                  leading: const Icon(
                                    Icons.record_voice_over_outlined,
                                  ),
                                  title: Text((data['text'] ?? '') as String),
                                  subtitle: Text(
                                    DateFormat(
                                      'HH:mm - dd/MM/yyyy',
                                    ).format(diaryDateTime),
                                  ),
                                ),
                                Positioned(
                                  right: 8,
                                  top: 0,
                                  bottom: 0,
                                  child: Center(
                                    child: (isSyncing || isEditing)
                                        ? SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    scheme.primary,
                                                  ),
                                            ),
                                          )
                                        : Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                tooltip: 'Chỉnh sửa nhật ký',
                                                onPressed: () => _editVoiceDiary(
                                                  voiceDiaryId: d.id,
                                                  initialText:
                                                      (data['text'] ?? '')
                                                          as String,
                                                  initialDateTime:
                                                      diaryDateTime,
                                                  googleCalendarId:
                                                      googleCalendarId,
                                                  googleCalendarName:
                                                      data['googleCalendarName']
                                                          as String?,
                                                ),
                                                icon: Icon(
                                                  Icons.edit_outlined,
                                                  color: scheme.primary,
                                                ),
                                              ),
                                              Tooltip(
                                                message: isSynced
                                                    ? 'Đã thêm vào Google Calendar'
                                                    : 'Thêm vào Google Calendar',
                                                child: IconButton(
                                                  icon: Icon(
                                                    isSynced
                                                        ? Icons.check_circle
                                                        : Icons
                                                              .calendar_today_outlined,
                                                    color: scheme.primary,
                                                  ),
                                                  onPressed: isSynced
                                                      ? () => _removeFromGoogleCalendar(
                                                          voiceDiaryId: d.id,
                                                          googleCalendarId:
                                                              googleCalendarId,
                                                          googleCalendarName:
                                                              data['googleCalendarName']
                                                                  as String?,
                                                        )
                                                      : () => _syncToGoogleCalendar(
                                                          voiceDiaryId: d.id,
                                                          text:
                                                              (data['text'] ??
                                                                      '')
                                                                  as String,
                                                          eventDateTime:
                                                              diaryDateTime,
                                                        ),
                                                  tooltip: isSynced
                                                      ? 'Xóa khỏi Google Calendar'
                                                      : 'Thêm vào Google Calendar',
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
