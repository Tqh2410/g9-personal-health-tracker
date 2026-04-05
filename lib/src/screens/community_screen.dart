// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../utils/user_friendly_error.dart';

class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});

  Future<bool> _confirmDeletePost(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa bài đăng'),
        content: const Text('Bạn có chắc muốn xóa bài đăng này không?'),
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

    return result ?? false;
  }

  String _todayKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  String _dailyChallengeDocId() => 'daily-10k-${_todayKey()}';

  List<String> _extractParticipantIds(Map<String, dynamic>? data) {
    if (data == null) return const <String>[];

    final ids = <String>{};

    final rawArray = data['participantIds'];
    if (rawArray is List) {
      for (final item in rawArray) {
        final id = (item ?? '').toString().trim();
        if (id.isNotEmpty) ids.add(id);
      }
    }

    final rawMap = data['participants'];
    if (rawMap is Map<String, dynamic>) {
      ids.addAll(rawMap.keys.where((e) => e.trim().isNotEmpty));
    }

    return ids.toList(growable: false);
  }

  Future<int> _getTodaySteps(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('dailyStats')
          .doc(_todayKey())
          .get();

      return ((snap.data()?['steps'] ?? 0) as num).toInt();
    } catch (_) {
      return 0;
    }
  }

  Future<List<MapEntry<String, int>>> _buildLeaderboard(
    List<String> participantIds,
  ) async {
    if (participantIds.isEmpty) {
      return const <MapEntry<String, int>>[];
    }

    final entries = await Future.wait(
      participantIds.map((uid) async {
        final steps = await _getTodaySteps(uid);
        return MapEntry(uid, steps);
      }),
    );

    // Keep all joined participants (including 0 steps) to avoid UI flipping
    // between "no participants" and "has leaderboard" states.
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  String _shortId(String uid) {
    if (uid.length <= 6) return uid;
    return '${uid.substring(0, 3)}...${uid.substring(uid.length - 3)}';
  }

  String _displayNameFromUserData(Map<String, dynamic>? data, String uid) {
    final firstName = (data?['firstName'] as String? ?? '').trim();
    final lastName = (data?['lastName'] as String? ?? '').trim();
    final fullName = '$firstName $lastName'.trim();
    if (fullName.isNotEmpty) return fullName;

    final email = (data?['email'] as String? ?? '').trim();
    if (email.isNotEmpty) return email.split('@').first;

    return _shortId(uid);
  }

  Future<String> _getAuthorDisplayName(String uid) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    return _displayNameFromUserData(snap.data(), uid);
  }

  Future<void> _addPost(BuildContext context, WidgetRef ref) async {
    final scheme = Theme.of(context).colorScheme;
    final uid = ref.read(authStateProvider).valueOrNull?.id;
    if (uid == null) return;

    final steps = await _getTodaySteps(uid);
    final title = TextEditingController();
    final text = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: scheme.surfaceContainerLow,
        title: const Text('Đăng bài viết'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: title,
              maxLines: 1,
              decoration: const InputDecoration(hintText: 'Tiêu đề bài đăng'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: text,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Chia sẻ thành tích hôm nay...',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Số bước hôm nay: $steps bước',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () async {
              final postTitle = title.text.trim();
              final content = text.text.trim();
              if (postTitle.isEmpty || content.isEmpty) {
                return;
              }

              try {
                final authorName = await _getAuthorDisplayName(uid);
                await FirebaseFirestore.instance.collection('posts').add({
                  'authorId': uid,
                  'authorName': authorName,
                  'title': postTitle,
                  'content': content,
                  'steps': steps,
                  'likes': 0,
                  'comments': 0,
                  'createdAt': FieldValue.serverTimestamp(),
                });
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      UserFriendlyError.message(
                        e,
                        fallback:
                            'Không thể đăng bài lúc này. Vui lòng thử lại.',
                      ),
                    ),
                  ),
                );
              }
            },
            child: const Text('Đăng'),
          ),
        ],
      ),
    );
  }

  Future<bool> _toggleLikePost(
    DocumentReference<Map<String, dynamic>> refDoc,
    String uid,
  ) async {
    final likeRef = refDoc.collection('likes').doc(uid);

    return FirebaseFirestore.instance.runTransaction((tx) async {
      final likeSnap = await tx.get(likeRef);
      final snap = await tx.get(refDoc);
      final likes = ((snap.data()?['likes'] ?? 0) as num).toInt();

      if (likeSnap.exists) {
        tx.delete(likeRef);
        tx.update(refDoc, {'likes': likes <= 0 ? 0 : likes - 1});
        return false;
      }

      tx.set(likeRef, {
        'userId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.update(refDoc, {'likes': likes + 1});
      return true;
    });
  }

  Future<void> _joinChallenge(
    BuildContext context,
    WidgetRef ref,
    List<String> participantIds,
    int target,
  ) async {
    final uid = ref.read(authStateProvider).valueOrNull?.id;
    if (uid == null) return;

    final alreadyJoined = participantIds.contains(uid);

    final challengeRef = FirebaseFirestore.instance
        .collection('challenges')
        .doc(_dailyChallengeDocId());
    try {
      await challengeRef.set({
        'name': '10,000 bước/ngày',
        'dateKey': _todayKey(),
        'target': 10000,
        'participantIds': FieldValue.arrayUnion([uid]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            alreadyJoined
                ? 'Bạn đã tham gia thử thách. Đây là bảng xếp hạng mới nhất.'
                : 'Đã tham gia thử thách thành công.',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFriendlyError.message(
              e,
              fallback:
                  'Không thể tham gia thử thách lúc này. Vui lòng thử lại.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _leaveChallenge(
    BuildContext context,
    WidgetRef ref,
    bool hasJoined,
  ) async {
    final uid = ref.read(authStateProvider).valueOrNull?.id;
    if (uid == null || !hasJoined) return;

    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hủy tham gia thử thách'),
        content: const Text(
          'Bạn có chắc muốn hủy tham gia thử thách hôm nay không?',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Không'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hủy tham gia'),
          ),
        ],
      ),
    );

    if (shouldLeave != true) return;

    final challengeRef = FirebaseFirestore.instance
        .collection('challenges')
        .doc(_dailyChallengeDocId());

    try {
      await challengeRef.set({
        'participantIds': FieldValue.arrayRemove([uid]),
        'participants.$uid': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bạn đã hủy tham gia thử thách hôm nay.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFriendlyError.message(
              e,
              fallback:
                  'Không thể hủy tham gia thử thách lúc này. Vui lòng thử lại.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _showLeaderboardDialog(
    BuildContext context,
    List<String> participantIds,
    int target,
    String? currentUid,
  ) async {
    final scheme = Theme.of(context).colorScheme;
    final leaderboardFuture = _buildLeaderboard(participantIds);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: scheme.surface,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.arrow_back_ios_new),
                      tooltip: 'Quay lại',
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: Text(
                        'Bảng xếp hạng số bước',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: FutureBuilder<List<MapEntry<String, int>>>(
                    future: leaderboardFuture,
                    builder: (context, rankSnap) {
                      if (rankSnap.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (participantIds.isEmpty) {
                        return Center(
                          child: Text(
                            'Chưa có ai tham gia thử thách hôm nay.',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        );
                      }

                      final ranks =
                          rankSnap.data ?? const <MapEntry<String, int>>[];
                      if (ranks.isEmpty) {
                        return Center(
                          child: Text(
                            'Chưa tải được dữ liệu bảng xếp hạng.',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        );
                      }

                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: ranks.length,
                        separatorBuilder: (_, index) =>
                            Divider(color: scheme.outlineVariant),
                        itemBuilder: (context, index) {
                          final entry = ranks[index];
                          final rank = index + 1;
                          final value = entry.value;
                          final progress = target == 0 ? 0.0 : value / target;
                          final userStream = FirebaseFirestore.instance
                              .collection('users')
                              .doc(entry.key)
                              .snapshots();

                          final rankColor = rank == 1
                              ? Colors.amber.shade700
                              : rank == 2
                              ? Colors.blueGrey
                              : rank == 3
                              ? Colors.brown.shade400
                              : scheme.primary;

                          return StreamBuilder<
                            DocumentSnapshot<Map<String, dynamic>>
                          >(
                            stream: userStream,
                            builder: (context, userSnap) {
                              final displayName = _displayNameFromUserData(
                                userSnap.data?.data(),
                                entry.key,
                              );
                              final isCurrentUser =
                                  currentUid != null && entry.key == currentUid;

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                tileColor: isCurrentUser
                                    ? scheme.primaryContainer.withValues(
                                        alpha: 0.35,
                                      )
                                    : null,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: rankColor.withValues(
                                    alpha: 0.12,
                                  ),
                                  child: Text(
                                    '$rank',
                                    style: TextStyle(
                                      color: rankColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  isCurrentUser
                                      ? '$displayName (Bạn)'
                                      : displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text('$value bước'),
                                trailing: SizedBox(
                                  width: 84,
                                  child: LinearProgressIndicator(
                                    value: progress > 1 ? 1 : progress,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final postStream = FirebaseFirestore.instance
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .snapshots();

    final challengeStream = FirebaseFirestore.instance
        .collection('challenges')
        .doc(_dailyChallengeDocId())
        .snapshots();
    final currentUid = ref.watch(authStateProvider).valueOrNull?.id;
    final myStepsStream = currentUid == null
        ? const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty()
        : FirebaseFirestore.instance
              .collection('users')
              .doc(currentUid)
              .collection('dailyStats')
              .doc(_todayKey())
              .snapshots();

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surface,
        scrolledUnderElevation: 0,
        title: const Text('Cộng đồng'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'community-fab',
        onPressed: () => _addPost(context, ref),
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('Đăng bài'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              const Text(
                'Thử thách',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: myStepsStream,
            builder: (context, myStepsSnap) {
              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: challengeStream,
                builder: (context, snap) {
                  final data = snap.data?.data();
                  final target = ((data?['target'] ?? 10000) as num).toInt();
                  final participantIds = _extractParticipantIds(data);
                  final hasJoined =
                      currentUid != null && participantIds.contains(currentUid);

                  return Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.7),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (data?['name'] ?? '10,000 steps/day') as String,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Cùng nhau theo dõi và tăng số bước mỗi ngày.',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: hasJoined
                                ? null
                                : () => _joinChallenge(
                                    context,
                                    ref,
                                    participantIds,
                                    target,
                                  ),
                            icon: Icon(
                              hasJoined
                                  ? Icons.check_circle_outline
                                  : Icons.group_add_outlined,
                            ),
                            label: Text(
                              hasJoined ? 'Đã tham gia' : 'Tham gia thử thách',
                            ),
                          ),
                          if (hasJoined) ...[
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _leaveChallenge(context, ref, hasJoined),
                              icon: const Icon(Icons.person_remove_outlined),
                              label: const Text('Hủy tham gia'),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            'Bảng xếp hạng sẽ sắp xếp theo số bước từ cao xuống thấp.',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () => _showLeaderboardDialog(
                              context,
                              participantIds,
                              target,
                              currentUid,
                            ),
                            icon: const Icon(Icons.leaderboard_outlined),
                            label: const Text('Xem bảng xếp hạng'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.forum_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              const Text(
                'Bảng tin',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: postStream,
            builder: (context, snap) {
              if (!snap.hasData) return const LinearProgressIndicator();
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Chưa có bài viết nào. Hãy đăng bài đầu tiên của bạn.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                );
              }
              return Column(
                children: docs
                    .map((d) {
                      final p = d.data();
                      final authorId = (p['authorId'] ?? '') as String;
                      final isMine =
                          currentUid != null && authorId == currentUid;
                      final likes = ((p['likes'] ?? 0) as num).toInt();
                      final title = ((p['title'] ?? '') as String).trim();
                      final steps = ((p['steps'] ?? 0) as num).toInt();
                      final likeDocStream = currentUid == null
                          ? const Stream<
                              DocumentSnapshot<Map<String, dynamic>>
                            >.empty()
                          : d.reference
                                .collection('likes')
                                .doc(currentUid)
                                .snapshots();
                      final authorName = ((p['authorName'] ?? '') as String)
                          .trim();
                      final card = Container(
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.7),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (authorName.isNotEmpty)
                                Row(
                                  children: [
                                    Icon(
                                      Icons.person_outline,
                                      size: 18,
                                      color: scheme.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        authorName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              if (authorName.isNotEmpty)
                                const SizedBox(height: 8),
                              if (title.isNotEmpty)
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              if (title.isNotEmpty) const SizedBox(height: 6),
                              Text(
                                (p['content'] ?? '') as String,
                                style: const TextStyle(height: 1.35),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Bước chân hôm nay: $steps bước',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 10),
                              StreamBuilder<
                                DocumentSnapshot<Map<String, dynamic>>
                              >(
                                stream: likeDocStream,
                                builder: (context, likeSnap) {
                                  final liked = likeSnap.data?.exists ?? false;
                                  return Row(
                                    children: [
                                      Icon(
                                        liked
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        size: 18,
                                        color: scheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '$likes lượt thích',
                                        style: TextStyle(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const Spacer(),
                                      FilledButton.tonalIcon(
                                        onPressed: currentUid == null
                                            ? null
                                            : () async {
                                                try {
                                                  await _toggleLikePost(
                                                    d.reference,
                                                    currentUid,
                                                  );
                                                } catch (e) {
                                                  if (!context.mounted) return;
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        UserFriendlyError.message(
                                                          e,
                                                          fallback:
                                                              'Không thể cập nhật lượt thích lúc này. Vui lòng thử lại.',
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                }
                                              },
                                        icon: Icon(
                                          liked
                                              ? Icons.thumb_up_alt
                                              : Icons.thumb_up_alt_outlined,
                                        ),
                                        label: Text(
                                          liked ? 'Bỏ thích' : 'Thích',
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      );

                      if (!isMine) {
                        return card;
                      }

                      return Dismissible(
                        key: ValueKey('post-${d.id}'),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) => _confirmDeletePost(context),
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
                        onDismissed: (_) async {
                          try {
                            await d.reference.delete();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Đã xóa bài đăng')),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  UserFriendlyError.message(
                                    e,
                                    fallback:
                                        'Không thể xóa bài đăng lúc này. Vui lòng thử lại.',
                                  ),
                                ),
                              ),
                            );
                          }
                        },
                        child: card,
                      );
                    })
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }
}
