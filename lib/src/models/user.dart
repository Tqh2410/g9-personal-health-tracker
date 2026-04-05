import 'package:cloud_firestore/cloud_firestore.dart';

class User {
  final String id;
  final String email;
  final String? firstName;
  final String? lastName;
  final DateTime? createdAt;
  final String? photoUrl;
  final bool emailVerified;

  User({
    required this.id,
    required this.email,
    this.firstName,
    this.lastName,
    this.createdAt,
    this.photoUrl,
    this.emailVerified = false,
  });

  factory User.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return User(
      id: doc.id,
      email: data['email'] ?? '',
      firstName: data['firstName'],
      lastName: data['lastName'],
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
      photoUrl: data['photoUrl'],
      emailVerified: data['emailVerified'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'firstName': firstName,
      'lastName': lastName,
      'createdAt': createdAt,
      'photoUrl': photoUrl,
      'emailVerified': emailVerified,
    };
  }

  User copyWith({
    String? id,
    String? email,
    String? firstName,
    String? lastName,
    DateTime? createdAt,
    String? photoUrl,
    bool? emailVerified,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      createdAt: createdAt ?? this.createdAt,
      photoUrl: photoUrl ?? this.photoUrl,
      emailVerified: emailVerified ?? this.emailVerified,
    );
  }

  String get fullName => '${firstName ?? ''} ${lastName ?? ''}'.trim();

  @override
  String toString() => 'User(id: $id, email: $email, name: $fullName)';
}
