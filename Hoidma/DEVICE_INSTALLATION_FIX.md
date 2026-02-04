# Fixing Device Installation Issues

## Quick Fix Steps (Do These in Order)

### Step 1: Stop All Installation Attempts
1. In Xcode, click the **Stop button** (⏹) in the toolbar
2. Wait for all spinning tasks to stop
3. If they don't stop, **force quit Xcode** (`Cmd+Q`)

### Step 2: Delete App from Your Phone
**CRITICAL - This fixes most installation issues:**

1. On your iPhone, find the **Hoidma** app
2. **Long press** the app icon
3. Tap **Remove App** > **Delete App**
4. Confirm deletion
5. This removes the old version that's blocking installation

### Step 3: Clean Xcode Build
1. In Xcode: **Product > Clean Build Folder** (`Shift+Cmd+K`)
2. Wait for it to complete

### Step 4: Disconnect and Reconnect Your Phone
1. Unplug your iPhone from your Mac
2. Wait 5 seconds
3. Plug it back in
4. **Trust the computer** if prompted on your phone
5. Unlock your phone and keep it unlocked

### Step 5: Verify Device in Xcode
1. In Xcode, click the **device dropdown** (next to the scheme)
2. Your phone should appear: **"Daniel's 17 Pro Max"**
3. If it shows "Preparing..." or is grayed out:
   - Wait for it to finish preparing
   - Or unplug/replug your phone

### Step 6: Check Code Signing
1. Click the **blue project icon** in navigator
2. Select **Hoidma** project
3. Select **Hoidma** target
4. Go to **Signing & Capabilities** tab
5. Verify:
   - ✅ **Automatically manage signing** is checked
   - **Team:** Should show "Daniel Furry (2DBY9B53R4)"
   - **Bundle Identifier:** `danielfurry.Hoidma`
6. If there are errors, click **"Try Again"** or **"Download Manual Profiles"**

### Step 7: Update Bundle Version (Force New Install)
1. Still in **Signing & Capabilities** tab
2. Scroll down to **Identity** section
3. Change **Version** from `1.0` to `1.1` (or increment it)
4. Change **Build** from `1` to `2` (or increment it)
5. This forces Xcode to treat it as a new version

### Step 8: Build and Install
1. Select your phone as the destination: **"Daniel's 17 Pro Max"**
2. Press **⌘ + R** (or click Run button)
3. **Wait patiently** - first install can take 1-2 minutes
4. **Keep your phone unlocked** during installation
5. If prompted on phone, tap **Trust** or **Allow**

### Step 9: If Still Failing - Reset Provisioning
1. In Xcode: **Xcode > Settings** (or Preferences)
2. Go to **Accounts** tab
3. Select your Apple ID
4. Click **Download Manual Profiles**
5. Wait for it to complete
6. Go back to project settings
7. In **Signing & Capabilities**, click **"Try Again"** if there are errors

### Step 10: Last Resort - Manual Cleanup
If nothing works:

1. **On your Mac:**
   ```bash
   # Clean Xcode caches
   rm -rf ~/Library/Developer/Xcode/DerivedData/Hoidma-*
   
   # Clean provisioning profiles (optional)
   rm -rf ~/Library/MobileDevice/Provisioning\ Profiles/*
   ```

2. **On your iPhone:**
   - Settings > General > VPN & Device Management
   - Find "Daniel Furry" developer profile
   - Tap it and **Remove** if it exists
   - Then reinstall

3. **In Xcode:**
   - Close Xcode completely
   - Reopen Xcode
   - Open your project
   - Try installing again

## Common Issues

### "App installation failed"
- **Solution:** Delete the app from your phone first (Step 2)

### "Unable to install Hoidma"
- **Solution:** Check code signing (Step 6), make sure team is selected

### "Device not available" or "Preparing..."
- **Solution:** Unplug/replug phone, keep it unlocked, wait for "Preparing" to finish

### "A valid provisioning profile for this executable was not found"
- **Solution:** Step 6 - verify signing, or Step 9 - reset provisioning

### Installation keeps spinning
- **Solution:** Stop all tasks, delete app from phone, clean build, try again

## Prevention

To avoid this in the future:
1. Always **delete the app from your phone** before installing a new version
2. **Increment the Build number** in project settings for each new install
3. Keep your phone **unlocked** during installation
4. Don't start multiple installation attempts at once
