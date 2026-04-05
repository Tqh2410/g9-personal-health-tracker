# Firebase Setup Guide - Personal Health Diary App

## Step 1: Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click **"Create a project"**
3. Enter project name: `personal-health-diary`
4. Click **"Continue"**
5. Disable Google Analytics (optional) and click **"Create project"**
6. Wait for project to be created, then click **"Continue"**

---

## Step 2: Setup Authentication

### Enable Email/Password Authentication
1. In Firebase Console, go to **Authentication** → **Sign-in method**
2. Click on **Email/Password**
3. Enable **Email/Password** toggle
4. Enable **Email link (passwordless sign-in)** (optional)
5. Click **"Save"**

### Enable Google Sign-In
1. In **Sign-in method**, click on **Google**
2. Enable the **Google** toggle
3. Enter your support email
4. Click **"Save"**

---

## Step 3: Setup Firestore Database

1. Go to **Firestore Database**
2. Click **"Create database"**
3. Choose **"Start in production mode"** (we'll set rules)
4. Select your region (choose closest to your users)
5. Click **"Enable"**

### Create Firestore Security Rules
1. Go to **Firestore Database** → **Rules**
2. Replace default rules with rules from `PHASE_1_DOCUMENTATION.md`
3. Click **"Publish"**

---

## Step 4: Setup Cloud Storage

1. Go to **Storage**
2. Click **"Get Started"**
3. Click **"Next"**
4. Keep default location and click **"Done"**

---

## Step 5: Get Firebase Configuration

### For Android
1. Go to **Project Settings** (gear icon)
2. Under **Your apps**, click Android icon
3. Register app with package name: `com.example.personal_health_diary`
4. Download `google-services.json`
5. Move to `android/app/` directory

### For iOS
1. In **Project Settings**, click iOS icon
2. Register app with bundle ID: `com.example.personal_health_diary`
3. Download `GoogleService-Info.plist`
4. In Xcode, open `ios/Runner.xcworkspace`
5. Drag `GoogleService-Info.plist` to project
6. Make sure "Copy items if needed" is checked
7. Click **"Finish"**

### For Web (if needed)
1. In **Project Settings**, click Web icon `</>`
2. Register app
3. Copy the Firebase config
4. Update `web/index.html` with config

---

## Step 6: Update Flutter Project

### 1. Update Dependencies
```bash
cd personal_health_diary
flutter pub get
```

### 2. Update firebase_options.dart
1. Open `firebase_options.dart`
2. Get your API keys from **Project Settings** → **Your apps**
3. Update each platform's configuration:
   - `apiKey`: From Firebase console
   - `appId`: From Firebase console
   - `messagingSenderId`: Sender ID from Firebase
   - `projectId`: Your project ID

---

## Step 7: Initialize Flutter Firebase CLI (OPTIONAL)

If you want to use Firebase CLI:
```bash
# Install Firebase CLI
npm install -g firebase-tools

# Login to Firebase
firebase login

# Initialize project
firebase init
```

---

## Step 8: Run the App

### Android
```bash
flutter run -d android
```

### iOS
```bash
flutter run -d ios
```

### Web
```bash
flutter run -d chrome
```

---

## Troubleshooting

### "Plugin 'com.google.gms.google-services' not found"
- Make sure `google-services.json` is in `android/app/` directory
- Rebuild: `flutter clean && flutter pub get && flutter run`

### "GoogleService-Info.plist not recognized"
- In Xcode, make sure `GoogleService-Info.plist` is added to Bundle Resources
- Go to **Runner** → **Build Phases** → **Copy Bundle Resources**
- Click `+` and add the file if missing

### Firebase not initializing
- Check internet connection
- Verify `firebase_options.dart` has correct credentials
- Check app bundle ID/package name matches Firebase configuration

### Email verification not working
- Go to **Firebase Console** → **Authentication** → **Templates**
- Customize email template if needed
- Check spam folder

---

## Next: Deploy Firestore Rules

Create `firestore.rules` file in root:

```bash
firebase deploy --only firestore:rules
```

Or manually update rules in Firebase Console:
- Go to **Firestore** → **Rules** tab
- Paste rules from `PHASE_1_DOCUMENTATION.md`
- Click **"Publish"**

---

## Verification Checklist

- [ ] Firebase project created
- [ ] Authentication enabled (Email/Password + Google)
- [ ] Firestore database created
- [ ] Cloud Storage enabled
- [ ] `google-services.json` added (Android)
- [ ] `GoogleService-Info.plist` added (iOS)
- [ ] `firebase_options.dart` updated
- [ ] Dependencies installed (`flutter pub get`)
- [ ] App runs without Firebase errors
- [ ] Can sign up and login successfully

---

## Environment Configuration

### Development Firebase Project (Optional)
For testing without affecting production:

1. Create a separate Firebase project: `personal-health-diary-dev`
2. Follow same steps above
3. Update `firebase_options.dart` with dev credentials
4. Use for testing and development

**Note**: Currently using single Firebase project for all environments.

---

## Security Best Practices

✅ **DO**:
- Keep Firebase config in `firebase_options.dart`
- Never commit API keys directly
- Use environment variables for sensitive keys
- Enable Firestore Security Rules
- Use strong rules that validate user data

❌ **DON'T**:
- Expose API keys in version control
- Use development credentials in production
- Have overly permissive Firestore rules
- Store sensitive data in Cloud Storage without encryption

---

For more information, visit:
- [Firebase Documentation](https://firebase.google.com/docs)
- [Flutter Firebase Plugin](https://firebase.flutter.dev/)
- [Firebase Security Rules](https://firebase.google.com/docs/firestore/security/start)
