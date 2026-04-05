import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_provider.dart';
import '../utils/user_friendly_error.dart';

class SosScreen extends ConsumerStatefulWidget {
  const SosScreen({super.key});

  @override
  ConsumerState<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends ConsumerState<SosScreen> {
  String _status = 'Sẵn sàng';
  bool _sending = false;

  String get _uid => ref.read(authStateProvider).valueOrNull?.id ?? '';

  Future<Position> _currentPosition() async {
    final service = await Geolocator.isLocationServiceEnabled();
    if (!service) {
      throw Exception('Dịch vụ vị trí đang tắt. Hãy bật GPS rồi thử lại.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      throw Exception('Không có quyền truy cập vị trí. Hãy cấp quyền vị trí.');
    }

    return Geolocator.getCurrentPosition();
  }

  Uri _buildMailtoUri({
    required List<String> recipients,
    required String subject,
    required String body,
  }) {
    return Uri(
      scheme: 'mailto',
      path: recipients.join(','),
      queryParameters: <String, String>{'subject': subject, 'body': body},
    );
  }

  Future<void> _openEmailComposer({
    required List<String> recipients,
    required String subject,
    required String body,
  }) async {
    final mailtoUri = _buildMailtoUri(
      recipients: recipients,
      subject: subject,
      body: body,
    );

    final launched = await launchUrl(
      mailtoUri,
      mode: LaunchMode.externalApplication,
    );

    if (launched) {
      return;
    }

    throw Exception('Không mở được ứng dụng email trên thiết bị.');
  }

  Future<void> _addEmergencyContact() async {
    final scheme = Theme.of(context).colorScheme;
    final uid = _uid;
    if (uid.isEmpty) return;

    final name = TextEditingController();
    final contactValue = TextEditingController();
    var preferEmail = true;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setModalState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        preferEmail
                            ? Icons.alternate_email_outlined
                            : Icons.contact_phone_outlined,
                        color: scheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Thêm liên hệ khẩn cấp',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Tên',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('Email'),
                      icon: Icon(Icons.email_outlined),
                    ),
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('Điện thoại'),
                      icon: Icon(Icons.call_outlined),
                    ),
                  ],
                  selected: <bool>{preferEmail},
                  onSelectionChanged: (selection) {
                    setModalState(() {
                      preferEmail = selection.first;
                      contactValue.clear();
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contactValue,
                  keyboardType: preferEmail
                      ? TextInputType.emailAddress
                      : TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: preferEmail ? 'Địa chỉ email' : 'Số điện thoại',
                    prefixIcon: Icon(
                      preferEmail
                          ? Icons.alternate_email_outlined
                          : Icons.call_outlined,
                    ),
                    hintText: preferEmail
                        ? 'example@gmail.com'
                        : 'VD: 0912345678',
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Hủy'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () async {
                        final contactName = name.text.trim();
                        final value = contactValue.text.trim();

                        if (contactName.isEmpty || value.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Vui lòng nhập đầy đủ thông tin.'),
                            ),
                          );
                          return;
                        }

                        final isEmail = preferEmail;
                        if (isEmail && !_isValidEmail(value)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Email không hợp lệ.'),
                            ),
                          );
                          return;
                        }

                        if (!isEmail && !_isValidPhone(value)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Số điện thoại không hợp lệ.'),
                            ),
                          );
                          return;
                        }

                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .collection('emergencyContacts')
                            .add({
                              'name': contactName,
                              'type': isEmail ? 'email' : 'phone',
                              'value': value,
                              'email': isEmail ? value : '',
                              'phone': isEmail ? '' : value,
                              'createdAt': FieldValue.serverTimestamp(),
                            });
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                      },
                      child: const Text('Lưu'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isValidEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  bool _isValidPhone(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+|-'), '');
    return RegExp(r'^\+?\d{8,15}$').hasMatch(normalized);
  }

  List<String> _extractEmailRecipients(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final recipients = <String>{};

    for (final doc in docs) {
      final data = doc.data();
      final type = (data['type'] ?? '').toString().trim().toLowerCase();
      final value = (data['value'] ?? '').toString().trim();
      final email = (data['email'] ?? '').toString().trim();

      if (type == 'email' && _isValidEmail(value)) {
        recipients.add(value.toLowerCase());
        continue;
      }
      if (_isValidEmail(email)) {
        recipients.add(email.toLowerCase());
      }
    }

    return recipients.toList(growable: false);
  }

  String _senderDisplayName() {
    final user = ref.read(currentUserProvider);
    final name = user?.fullName.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }

    final email = user?.email.trim();
    if (email != null && email.isNotEmpty) {
      return email;
    }

    return 'Người dùng';
  }

  Future<void> _triggerSos() async {
    final uid = _uid;
    if (uid.isEmpty) return;

    setState(() {
      _sending = true;
      _status = 'Đang lấy vị trí...';
    });

    try {
      final pos = await _currentPosition();
      final link =
          'https://maps.google.com/?q=${pos.latitude},${pos.longitude}';

      await FirebaseFirestore.instance.collection('sosLogs').add({
        'userId': uid,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'mapLink': link,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final contacts = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('emergencyContacts')
          .get();

      final recipients = _extractEmailRecipients(contacts.docs);
      if (recipients.isEmpty) {
        setState(
          () => _status =
              'Chưa có email khẩn cấp. Hãy thêm liên hệ loại email trước.',
        );
        return;
      }

      final subject = '[SOS] Tôi cần hỗ trợ khẩn cấp';
      final senderName = _senderDisplayName();
      final body =
          'SOS! Tôi cần hỗ trợ ngay.\n\n'
          'Vị trí hiện tại: $link\n\n'
          'Thời gian: ${DateTime.now()}\n'
          'Người gửi: $senderName';

      setState(() {
        _status = 'Đang mở Gmail để soạn sẵn email SOS...';
      });

      await _openEmailComposer(
        recipients: recipients,
        subject: subject,
        body: body,
      );

      setState(
        () => _status =
            'Đã mở Gmail/ứng dụng mail cho ${recipients.length} liên hệ',
      );
    } catch (e) {
      setState(() {
        _status = UserFriendlyError.message(
          e,
          fallback: 'Không thể gửi tín hiệu SOS lúc này. Vui lòng thử lại.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  String _contactType(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString().trim().toLowerCase();
    if (type == 'email' || type == 'phone') {
      return type;
    }

    final email = (data['email'] ?? '').toString().trim();
    if (_isValidEmail(email)) {
      return 'email';
    }

    return 'phone';
  }

  String _contactValue(Map<String, dynamic> data) {
    final value = (data['value'] ?? '').toString().trim();
    if (value.isNotEmpty) {
      return value;
    }

    final phone = (data['phone'] ?? '').toString().trim();
    final email = (data['email'] ?? '').toString().trim();
    return phone.isNotEmpty ? phone : (email.isNotEmpty ? email : '--');
  }

  Future<bool> _confirmDeleteContact(String name) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa liên hệ khẩn cấp'),
        content: Text('Bạn có chắc muốn xóa liên hệ $name không?'),
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

  Future<void> _removeEmergencyContact(String docId) async {
    final uid = _uid;
    if (uid.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('emergencyContacts')
        .doc(docId)
        .delete();

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đã xóa liên hệ khẩn cấp.')));
  }

  Widget _buildContactHeader(
    BuildContext context,
    String title,
    IconData icon,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final scheme = Theme.of(context).colorScheme;
    final data = doc.data();
    final name = ((data['name'] ?? '--') as String).trim();
    final value = _contactValue(data);
    final type = _contactType(data);

    final displayName = name.isEmpty ? '--' : name;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Dismissible(
        key: ValueKey('emergency-contact-${doc.id}'),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) => _confirmDeleteContact(displayName),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
        ),
        onDismissed: (_) {
          _removeEmergencyContact(doc.id);
        },
        child: ListTile(
          tileColor: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(displayName),
          subtitle: Text(value),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              type.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final uid = _uid;
    final contactsStream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('emergencyContacts')
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('SOS & Khẩn cấp'),
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surface,
        scrolledUnderElevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'sos-fab',
        onPressed: _addEmergencyContact,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Thêm liên hệ'),
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
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _status,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                const Text(
                  'NÚT SOS',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 180,
                  height: 180,
                  child: FilledButton(
                    onPressed: _sending ? null : _triggerSos,
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.error,
                      foregroundColor: scheme.onError,
                      shape: const CircleBorder(),
                    ),
                    child: Text(
                      _sending ? '...' : 'SOS',
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Liên hệ khẩn cấp',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 6),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: contactsStream,
            builder: (context, snap) {
              if (!snap.hasData) return const LinearProgressIndicator();
              final docs = snap.data!.docs;
              if (docs.isEmpty) return const Text('Chưa có liên hệ');

              final phoneDocs = docs
                  .where((d) => _contactType(d.data()) == 'phone')
                  .toList(growable: false);
              final emailDocs = docs
                  .where((d) => _contactType(d.data()) == 'email')
                  .toList(growable: false);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (phoneDocs.isNotEmpty) ...[
                    _buildContactHeader(
                      context,
                      'Số điện thoại',
                      Icons.call_outlined,
                    ),
                    ...phoneDocs.map(_buildContactTile),
                  ],
                  if (emailDocs.isNotEmpty) ...[
                    _buildContactHeader(
                      context,
                      'Email',
                      Icons.alternate_email_outlined,
                    ),
                    ...emailDocs.map(_buildContactTile),
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
