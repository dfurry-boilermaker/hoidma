# Firebase Connectivity Verification Guide

## How to Verify Firebase Requests Are Working

### Step 1: Check Xcode Console Logs

When you run the app, you should see these logs in Xcode's console:

#### On App Launch:
```
✅ Firebase configured successfully
✅ Firebase app initialized: __FIRAPP_DEFAULT
✅ Bundle ID: danielfurry.Hoidma
✅ Project ID: hoidma
✅ Firestore persistence enabled
```

#### When Signing In:
```
✅ AuthManager: Verification successful, user signed in
   User UID: [unique-user-id]
   Phone Number: +15742166565
✅ AuthManager: User authentication state updated
   Check Firebase Console > Authentication > Users to see this user
```

#### When Adding a Stock:
```
📤 FirebaseManager: Committing stock AAPL to Firestore...
   User ID: [your-user-id]
   Path: portfolios/[user-id]/stocks/AAPL
📤 FirebaseManager: Encoding stock data...
📤 FirebaseManager: Sending data to Firestore...
   Data keys: ticker, companyName, purchasePrice, shares, isMaritalStatus, lots
✅ FirebaseManager: Successfully committed stock AAPL to Firestore
   Check Firebase Console > Firestore Database to see the data
```

#### When Listening to Data:
```
📡 FirebaseManager: Starting data listener for user [user-id]...
   Listening to: portfolios/[user-id]/stocks
📡 FirebaseManager: Firestore settings:
   Host: firestore.googleapis.com
   IsSSLEnabled: true
📥 FirebaseManager: Received snapshot from Firestore
   Snapshot metadata: fromCache=false, hasPendingWrites=false
```

### Step 2: Check Firebase Console

#### Authentication Tab:
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **hoidma**
3. Go to **Authentication** > **Users**
4. **You should see:**
   - Your phone number listed as a user
   - UID (unique identifier)
   - Provider: "phone"
   - Creation date

**If you don't see your user:**
- Sign-in didn't complete successfully
- Check Xcode console for authentication errors
- Verify Phone Auth is enabled in Firebase Console

#### Firestore Database Tab:
1. Go to **Firestore Database**
2. **You should see:**
   - Collection: `portfolios`
   - Document: `{your-user-id}`
   - Subcollection: `stocks`
   - Documents: `{ticker}` (e.g., "AAPL")

**If you don't see data:**
- Check if you're signed in (look for user in Authentication tab)
- Check Xcode console for commit errors
- Verify Firestore is enabled in Firebase Console

### Step 3: Verify You're Signed In

**In Xcode Console, look for:**
```
✅ AuthManager: Firebase Auth initialized
📡 FirebaseManager: Starting data listener for user [user-id]...
```

**If you see:**
```
❌ FirebaseManager: No user ID, cannot commit stock
   User must be authenticated to save data to Firestore
```

**This means:**
- You're not signed in
- Complete phone authentication first
- Then try adding a stock

### Step 4: Test the Flow

1. **Sign In:**
   - Enter phone number: `+15742166565`
   - Click "Send Code"
   - Enter verification code
   - Check console for: `✅ AuthManager: Verification successful`

2. **Add a Stock:**
   - Click the "+" button
   - Enter ticker: `AAPL`
   - Enter price: `150.00`
   - Enter shares: `10`
   - Click "Add"
   - Check console for: `✅ FirebaseManager: Successfully committed stock AAPL`

3. **Check Firebase Console:**
   - Go to Firestore Database
   - Navigate: `portfolios` → `{your-user-id}` → `stocks` → `AAPL`
   - You should see the stock data

### Step 5: Common Issues

#### Issue: "No user ID, cannot commit stock"
**Solution:** You must sign in first. Complete phone authentication.

#### Issue: "Error committing stock: Permission denied"
**Solution:** Check Firestore security rules. They should allow authenticated users:
```javascript
match /portfolios/{userId}/stocks/{stockId} {
  allow read, write: if request.auth != null && request.auth.uid == userId;
}
```

#### Issue: "fromCache=true" in snapshot metadata
**Solution:** This means you're reading from local cache. This is normal for offline support, but if you want to see it in Firebase Console immediately, ensure you have internet connection.

#### Issue: No activity in Firebase Console
**Possible causes:**
1. **Not signed in** - Check Authentication tab for your user
2. **No stocks added** - Add a stock and check console logs
3. **Offline mode** - Check if `fromCache=true` in logs
4. **Wrong project** - Verify you're looking at the correct Firebase project
5. **Network issue** - Check internet connection

### Step 6: Force Online Mode (For Testing)

If you want to ensure data syncs immediately:

1. **Disable offline persistence temporarily:**
   - In `HoidmaApp.swift`, the code enables persistence
   - For testing, you can disable it to force online-only mode

2. **Check network connection:**
   - Ensure your iPhone has internet (WiFi or cellular)
   - Firestore needs internet to sync with Firebase servers

### Step 7: Verify Data Structure

**Expected Firestore structure:**
```
portfolios/
  └── {firebase-auth-uid}/     ← Your user ID from Firebase Auth
      └── stocks/
          └── {TICKER}/         ← Stock ticker (e.g., "AAPL")
              ├── ticker: "AAPL"
              ├── companyName: "Apple Inc."
              ├── purchasePrice: 150.0
              ├── shares: 10
              ├── isMaritalStatus: true
              └── lots: [...]
```

**To find your user ID:**
- Check Xcode console: `User UID: [this-is-your-user-id]`
- Or Firebase Console > Authentication > Users > Click your user > Copy UID

## Quick Test Checklist

- [ ] App launches without Firebase errors
- [ ] Can sign in with phone number
- [ ] See user in Firebase Console > Authentication > Users
- [ ] Can add a stock in the app
- [ ] See commit success message in Xcode console
- [ ] See stock data in Firebase Console > Firestore Database
- [ ] Stock appears in app after adding

## Still No Activity?

1. **Check Xcode console** - Look for error messages
2. **Verify you're signed in** - Check Authentication tab
3. **Try adding a stock** - Watch console for commit messages
4. **Check Firestore rules** - Ensure they allow writes
5. **Verify internet connection** - Firestore needs network access

The enhanced logging will show exactly what's happening at each step!
