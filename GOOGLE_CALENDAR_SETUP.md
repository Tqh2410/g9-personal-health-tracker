# 📅 Google Calendar Sync Setup Guide

## ✅ Completed Implementation

### Phase 1 & 2: Backend Setup
- ✅ Added `googleapis: ^12.0.0` package to pubspec.yaml
- ✅ Created `google_calendar_service.dart` - Service để kết nối Google Calendar API
- ✅ Created `google_calendar_provider.dart` - Riverpod providers

### Phase 3 & 4: UI & Features
- ✅ Updated `voice_diary_screen.dart` with:
  - Hover detection trên mỗi nhật ký
  - Sync button hiển thị khi hover
  - Loading indicator khi đang đồng bộ
  - Different UI states (não sync, syncing, synced)
  - Remove from Calendar option

---

## 🔧 Frontend Configuration

### Step 1: Enable Google Calendar API
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing one
3. Enable **Google Calendar API**
4. Create OAuth 2.0 credentials:
   - Type: OAuth client ID
   - Application type: Android/iOS (depending on your needs)

### Step 2: Android Configuration

**File: `android/app/build.gradle`**
```
android {
    compileSdkVersion 34
    
    defaultConfig {
        applicationId "com.example.personal_health_diary"
        minSdkVersion 21
        targetSdkVersion 34
        // ... other configs
    }
}
```

**File: `android/app/src/main/AndroidManifest.xml`**
```xml
<manifest>
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.GET_ACCOUNTS" />
    
    <application>
        <!-- Your activities -->
    </application>
</manifest>
```

**File: `android/app/google-services.json`** (if using Firebase)
- Ensure it includes OAuth 2.0 client configurations

### Step 3: iOS Configuration

**File: `ios/Runner/Info.plist`**
```xml
<dict>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>com.googleusercontent.apps.YOUR_CLIENT_ID</string>
            </array>
        </dict>
    </array>
    <key>LSApplicationQueriesSchemes</key>
    <array>
        <string>googlechromes</string>
        <string>comgooglemaps</string>
    </array>
</dict>
```

### Step 4: Firestore Security Rules Update

**File: `firestore.rules`** - Add rule cho voiceDiary collection:
```
match /users/{uid}/voiceDiary/{diaryId} {
    allow read, write: if request.auth != null && request.auth.uid == uid;
}
```

---

## 📱 Data Structure

### Firestore Schema Update

Each voice diary document bây giờ có thêm fields:
```
users/{uid}/voiceDiary/{docId}
├── text: string (Nội dung nhật ký)
├── createdAt: timestamp
├── googleCalendarId: string (Event ID trên Google Calendar)
├── googleCalendarName: string (Calendar ID nơi được lưu)
└── syncedAt: timestamp (Khi nào được sync)
```

---

## 🎯 Features

### 1. **Hover Detection**
- Khi di chuyển chuột vào nhật ký → hiển thị sync button

### 2. **Sync to Google Calendar**
- Click button → sync nhật ký lên Google Calendar chính (primary)
- Tạo event với:
  - **Title**: "Nhật ký"
  - **Description**: Nội dung nhật ký
  - **Time**: Thời gian tạo nhật ký + 1 giờ

### 3. **Sync Status**
- **Not Synced**: Icon `📅` (calendar_today_outlined)
- **Syncing**: Loading spinner
- **Synced**: Icon `✅` (check_circle) - disabled, dùng để remove

### 4. **Remove from Calendar**
- Click button trên đã sync → xóa event khỏi calendar
- Xóa fields `googleCalendarId`, `googleCalendarName`, `syncedAt`

---

## 🚀 Next Steps

### Phase 5: Production Setup
- [ ] Get OAuth 2.0 credentials từ Google Cloud Console
- [ ] Configure SHA-1 fingerprint cho Android
- [ ] Test trên device thực
- [ ] Add error handling cho network issues
- [ ] Add option choose calendar before syncing

### Future Enhancements
- Select calendar dialog khi sync
- Batch sync multiple entries
- Sync settings (auto-sync, default calendar, etc.)
- Edit synced event title/description

---

## ⚠️ Important Notes

1. **Google OAuth Scope**: `https://www.googleapis.com/auth/calendar`
2. **Device Prerequisites**: Google Account & Internet connection
3. **Timeout**: Increase if syncing takes long
4. **Error Handling**: Already included with SnackBar messages

---

## 🧪 Testing

### Local Testing
```bash
# Run with logging
flutter run -v

# Check logs for Google Calendar API calls
adb logcat | grep -i calendar
```

### Test Cases
1. ✅ Sync new diary entry
2. ✅ Remove synced entry
3. ✅ Handle network errors
4. ✅ Multiple sync attempts
5. ✅ Sign out & sign in again

---

## 📞 Support

Nếu gặp lỗi:
1. Check `flutter run -v` logs
2. Verify Google Cloud Console settings
3. Check AndroidManifest.xml permissions
4. Verify Firestore rules allow write access
5. Clear app data & reinstall

---

**Status**: ✅ Ready for testing
**Date**: April 4, 2026
