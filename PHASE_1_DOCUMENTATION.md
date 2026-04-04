# Phase 1: Authentication & Database Setup
## Personal Health Diary App

---

## Overview
Phase 1 establishes the foundation for the application with Firebase Authentication and Firestore database setup.

---

## 1. Project Architecture

### Technology Stack
- **Frontend**: Flutter 3.10+ with Riverpod state management
- **Backend**: Firebase (Auth, Firestore, Storage)
- **API Integration**: Go Router for navigation
- **UI Framework**: Material Design 3

### Folder Structure
```
lib/
├── main.dart                    # App entry point
├── firebase_options.dart        # Firebase configuration
├── src/
│   ├── config/
│   │   └── router.dart         # Go Router configuration
│   ├── models/
│   │   ├── user.dart           # User data model
│   │   └── auth_exception.dart # Error handling
│   ├── providers/
│   │   └── auth_provider.dart  # Riverpod providers for auth
│   ├── services/
│   │   └── auth_service.dart   # Firebase auth logic
│   ├── screens/
│   │   └── auth/
│   │       ├── login_screen.dart
│   │       ├── signup_screen.dart
│   │       └── forgot_password_screen.dart
│   └── widgets/
│       └── auth_widgets.dart   # Reusable auth UI components
```

---

## 2. Database Schema (Firestore)

### Collections Structure

#### 2.1 Users Collection
```
Collection: users/
Document: {userId}
{
  email: string,          // User's email address
  firstName: string,      // First name
  lastName: string,       // Last name
  createdAt: timestamp,   // Account creation date
  photoUrl: string,       // Profile picture URL (optional)
  emailVerified: boolean, // Email verification status
  
  // Phase 2+ fields:
  // height: number,
  // weight: number,
  // age: number,
  // gender: string,
}
```

#### 2.2 Activities Collection (Phase 2)
```
Collection: activities/{userId}/{date}/
Document: {activityId}
{
  type: string,          // walking, running, gym, etc.
  duration: number,      // Duration in minutes
  calories: number,      // Estimated calories burned
  distance: number,      // Distance in kilometers (optional)
  timestamp: timestamp,  // When activity occurred
}
```

#### 2.3 Nutrition Collection (Phase 2)
```
Collection: nutrition/{userId}/{date}/
Document: {mealId}
{
  mealType: string,      // breakfast, lunch, dinner, snack
  food: string,          // Food name/description
  calories: number,      // Estimated calories
  imageUrl: string,      // Image from Firebase Storage (optional)
  timestamp: timestamp,  // When meal was consumed
}
```

#### 2.4 Vitals Collection (Phase 3)
```
Collection: vitals/{userId}/{date}/
Document: {vitalId}
{
  weight: number,        // Weight in kg
  heartRate: number,     // BPM
  bloodPressure: string, // Format: "120/80"
  timestamp: timestamp,  // When measured
}
```

#### 2.5 Sleep Collection (Phase 4)
```
Collection: sleep/{userId}/{date}/
Document: sleep
{
  startTime: timestamp,  // When user went to bed
  endTime: timestamp,    // When user woke up
  quality: number,       // 1-5 sleep quality rating
  duration: number,      // Duration in hours
}
```

#### 2.6 Habits Collection (Phase 4)
```
Collection: habits/{userId}/
Document: {habitId}
{
  name: string,          // e.g., "Morning Run", "Drink Water"
  frequency: string,     // daily, weekly, etc.
  streakDays: number,    // Current streak count
  completedDates: array, // Array of completed dates
  createdAt: timestamp,  // When habit was created
}
```

#### 2.7 Emergency Contacts Collection (Phase 5)
```
Collection: emergencyContacts/{userId}/
Document: {contactId}
{
  name: string,          // Contact name
  phone: string,         // Phone number
  relation: string,      // Relationship (Mother, Friend, etc.)
}
```

#### 2.8 Social Feed Collection (Phase 6)
```
Collection: socialFeed/
Document: {postId}
{
  userId: string,        // Who posted
  content: string,       // Post content
  timestamp: timestamp,  // When posted
  likes: number,         // Number of likes
  likedBy: array,        // Array of user IDs who liked
}
```

---

## 3. Firebase Security Rules

### Firestore Rules (in firebase.rules file)
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Users can only read/write their own data
    match /users/{userId} {
      allow read, write: if request.auth.uid == userId;
    }
    
    // Activities, nutrition, vitals, sleep - user-specific
    match /activities/{userId}/{document=**} {
      allow read, write: if request.auth.uid == userId;
    }
    
    match /nutrition/{userId}/{document=**} {
      allow read, write: if request.auth.uid == userId;
    }
    
    match /vitals/{userId}/{document=**} {
      allow read, write: if request.auth.uid == userId;
    }
    
    match /sleep/{userId}/{document=**} {
      allow read, write: if request.auth.uid == userId;
    }
    
    match /habits/{userId}/{document=**} {
      allow read, write: if request.auth.uid == userId;
    }
    
    match /emergencyContacts/{userId}/{document=**} {
      allow read, write: if request.auth.uid == userId;
    }
    
    // Public social feed
    match /socialFeed/{postId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.resource.data.userId == request.auth.uid;
    }
  }
}
```

---

## 4. Authentication Flows

### 4.1 Sign Up Flow
1. User enters email, password, firstName, lastName
2. `AuthService.signUpWithEmail()` creates Firebase Auth user
3. User document is created in Firestore
4. Verification email is sent
5. User is prompted to check email before login

### 4.2 Login Flow
1. User enters email and password
2. `AuthService.loginWithEmail()` authenticates with Firebase
3. User data is fetched from Firestore
4. App redirects to Home screen

### 4.3 Google Sign-In Flow
1. User taps "Sign in with Google"
2. `AuthService.signInWithGoogle()` handles OAuth flow
3. If new user, profile is created in Firestore
4. App redirects to Home screen

### 4.4 Password Reset Flow
1. User enters email
2. `AuthService.sendPasswordResetEmail()` sends reset link
3. Firebase handles reset link
4. User returns to login after reset

---

## 5. API Integration Points

### 5.1 Cloudflare Workers AI (Future - Phase 2+)
**Endpoint**: `https://api.cloudflare.com/client/v4/accounts/{ACCOUNT_ID}/ai/run`

**Use Cases**:
- Food recognition from images (Vision model)
- Generate diet recommendations (LLM)
- Personalized workout suggestions

**Authentication**: Bearer token with Cloudflare API key

---

## 6. Implementation Checklist

### ✅ Completed
- [x] Project structure setup
- [x] Dependencies installed
- [x] User model created
- [x] Auth exception handling
- [x] Firebase Auth Service
- [x] Riverpod providers
- [x] Auth UI widgets
- [x] Login & Sign-Up screens
- [x] Password reset flow
- [x] Router configuration
- [x] Main app entry point

### 📋 Next Steps (Phase 2)
- [ ] Create Home screen layout
- [ ] Build Physical State Tracking UI
- [ ] Implement Activity logging
- [ ] Add nutrition logging interface
- [ ] Integrate health kit/Google Fit
- [ ] Create chart visualization library

---

## 7. Configuration Steps

### 7.1 Firebase Setup
1. Create Firebase project at https://console.firebase.google.com
2. Enable Authentication (Email/Password, Google)
3. Create Firestore database
4. Download google-services.json (Android) and GoogleService-Info.plist (iOS)
5. Update `firebase_options.dart` with your credentials
6. Deploy Firestore security rules

### 7.2 Flutter Pub Get
```bash
flutter pub get
flutter pub run build_runner build
```

### 7.3 Run the App
```bash
flutter run
```

---

## 8. Key Dependencies

- `firebase_core: ^3.1.0` - Firebase initialization
- `firebase_auth: ^5.1.0` - Authentication
- `cloud_firestore: ^5.1.0` - Database
- `flutter_riverpod: ^2.5.1` - State management
- `go_router: ^14.0.0` - Navigation
- `google_sign_in: ^6.2.1` - OAuth
- `google_fonts: ^6.1.0` - Typography

---

## 9. Testing Phase 1

### Manual Test Cases
1. **Sign Up**: Create account with valid email and password
2. **Login**: Sign in with created credentials
3. **Email Verification**: Verify email link works
4. **Google Sign-In**: Test OAuth flow
5. **Forgot Password**: Test password reset email
6. **Error Handling**: Test invalid inputs and network errors

---

## 10. Security Considerations

- ✅ Passwords never exposed in logs
- ✅ Firebase Security Rules enforce user data isolation
- ✅ Email verification required
- ✅ Password reset via email
- ✅ Session managed by Firebase automatically
- ✅ Google OAuth handled securely by Firebase

---

**Status**: Phase 1 Complete - Ready for Phase 2 Approval

**Next Phase**: Physical State Tracking (Activity & Nutrition Logging)
