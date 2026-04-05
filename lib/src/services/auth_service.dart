import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user.dart';
import '../models/auth_exception.dart';

class AuthService {
  final fb.FirebaseAuth _firebaseAuth = fb.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // Stream of auth state changes
  Stream<User?> get authStateChanges {
    return _firebaseAuth.authStateChanges().asyncExpand((fbUser) {
      if (fbUser == null) return Stream.value(null);
      return _watchUserProfile(fbUser);
    });
  }

  // Get current user
  User? get currentUser {
    final fbUser = _firebaseAuth.currentUser;
    if (fbUser == null) return null;
    return User(
      id: fbUser.uid,
      email: fbUser.email ?? '',
      photoUrl: fbUser.photoURL,
      emailVerified: fbUser.emailVerified,
    );
  }

  // Get Firebase UID
  String? get currentUserId => _firebaseAuth.currentUser?.uid;

  // Email/Password Sign Up
  Future<User> signUpWithEmail({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    try {
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = User(
        id: credential.user!.uid,
        email: credential.user!.email ?? '',
        firstName: firstName,
        lastName: lastName,
        createdAt: DateTime.now(),
        emailVerified: false,
      );

      // Save user profile to Firestore
      await _firestore.collection('users').doc(user.id).set(user.toFirestore());

      // Send email verification
      await credential.user!.sendEmailVerification();

      return user;
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException.fromFirebaseException(e);
    } catch (e) {
      throw AuthException(
        message: 'Không thể tạo tài khoản lúc này. Vui lòng thử lại sau.',
        code: 'signup_error',
      );
    }
  }

  // Email/Password Login
  Future<User> loginWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      return await _getUserFromFirestore(credential.user!.uid) ??
          User(id: credential.user!.uid, email: credential.user!.email ?? '');
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException.fromFirebaseException(e);
    } catch (e) {
      throw AuthException(
        message: 'Không thể đăng nhập lúc này. Vui lòng thử lại sau.',
        code: 'login_error',
      );
    }
  }

  // Google Sign-In
  Future<User> signInWithGoogle() async {
    try {
      // Reset stale Google session to ensure login flow opens reliably.
      await _googleSignIn.signOut();
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw AuthException(
          message: 'Bạn đã hủy đăng nhập Google',
          code: 'google_signin_cancelled',
        );
      }

      final googleAuth = await googleUser.authentication;
      final credential = fb.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _firebaseAuth.signInWithCredential(
        credential,
      );
      final fbUser = userCredential.user;

      // Check if user exists in Firestore
      var userDoc = await _firestore.collection('users').doc(fbUser!.uid).get();

      if (!userDoc.exists) {
        // Create new user profile
        final newUser = User(
          id: fbUser.uid,
          email: fbUser.email ?? '',
          firstName: fbUser.displayName?.split(' ').first,
          lastName: fbUser.displayName?.split(' ').skip(1).join(' '),
          photoUrl: fbUser.photoURL,
          createdAt: DateTime.now(),
        );
        await _firestore
            .collection('users')
            .doc(fbUser.uid)
            .set(newUser.toFirestore());
        return newUser;
      }

      return await _getUserFromFirestore(fbUser.uid) ??
          User(id: fbUser.uid, email: fbUser.email ?? '');
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException.fromFirebaseException(e);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(
        message: 'Đăng nhập Google chưa thành công. Vui lòng thử lại.',
        code: 'google_signin_error',
      );
    }
  }

  // Password Reset
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email.trim());
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException.fromFirebaseException(e);
    } catch (e) {
      throw AuthException(
        message: 'Không thể gửi email đặt lại mật khẩu lúc này.',
        code: 'reset_email_error',
      );
    }
  }

  // Sign Out
  Future<void> signOut() async {
    try {
      try {
        await _googleSignIn.disconnect();
      } catch (_) {
        // Ignore disconnect errors when no active Google session.
      }
      await _googleSignIn.signOut();
      await _firebaseAuth.signOut();
    } catch (e) {
      throw AuthException(
        message: 'Không thể đăng xuất lúc này. Vui lòng thử lại.',
        code: 'signout_error',
      );
    }
  }

  // Email Verification
  Future<void> sendEmailVerification() async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
      }
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException.fromFirebaseException(e);
    }
  }

  // Refresh email verification status
  Future<void> reloadUser() async {
    try {
      await _firebaseAuth.currentUser?.reload();
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException.fromFirebaseException(e);
    }
  }

  // Helper: Get user from Firestore
  Future<User?> _getUserFromFirestore(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return User.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Stream<User> _watchUserProfile(fb.User fbUser) {
    final userRef = _firestore.collection('users').doc(fbUser.uid);

    return userRef.snapshots().map((doc) {
      if (!doc.exists) {
        return User(
          id: fbUser.uid,
          email: fbUser.email ?? '',
          photoUrl: fbUser.photoURL,
          emailVerified: fbUser.emailVerified,
        );
      }

      final profile = User.fromFirestore(doc);
      return profile.copyWith(
        email: fbUser.email ?? profile.email,
        photoUrl: fbUser.photoURL ?? profile.photoUrl,
        emailVerified: fbUser.emailVerified,
      );
    });
  }

  // Delete account
  Future<void> deleteAccount() async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user != null) {
        final uid = user.uid;
        await user.delete();
        // Delete user data from Firestore
        await _firestore.collection('users').doc(uid).delete();
      }
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException.fromFirebaseException(e);
    }
  }
}
