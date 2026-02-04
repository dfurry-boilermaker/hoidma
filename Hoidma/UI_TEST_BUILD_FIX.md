# Fixing UI Test Build Failures

## Quick Fix Steps (Do These in Order)

### Step 1: Clean Build Folder
1. In Xcode: **Product > Clean Build Folder** (or press `Shift+Cmd+K`)
2. Wait for it to complete

### Step 2: Close and Reopen Xcode
1. Press `Cmd+Q` to quit Xcode completely
2. Reopen Xcode and your project

### Step 3: Verify Test Target Settings
1. Click the **blue project icon** in the navigator
2. Select the **Hoidma project** (not target)
3. Select the **HoidmaUITests** target
4. Go to **General** tab
5. Verify:
   - **Target to be Tested**: Should be `Hoidma`
   - **Bundle Identifier**: `danielfurry.HoidmaUITests`

### Step 4: Verify Test Files Are Included
1. Still in **HoidmaUITests** target
2. Go to **Build Phases** tab
3. Expand **Compile Sources**
4. You should see (or they should be auto-synced):
   - `HoidmaUITests.swift`
   - `PhoneAuthUITests.swift`
   - `HoidmaUITestsLaunchTests.swift`
5. If files are missing, the folder sync should add them automatically

### Step 5: Check Build Settings
1. Still in **HoidmaUITests** target
2. Go to **Build Settings** tab
3. Search for `TEST_TARGET_NAME`
4. Should be set to `Hoidma`
5. Search for `SWIFT_VERSION`
6. Should be `5.0` (or match your app target)

### Step 6: Verify Scheme Settings
1. Click the **scheme dropdown** next to the stop button (top left)
2. Select **Edit Scheme...**
3. Select **Test** in the left sidebar
4. Under **Tests**, make sure **HoidmaUITests** is checked
5. Click **Close**

### Step 7: Build the App Target First
1. Select **Hoidma** scheme (not HoidmaUITests)
2. Select a simulator (e.g., iPhone 15)
3. Press `Cmd+B` to build
4. Wait for build to succeed
5. **This is critical** - UI tests need the app to build first!

### Step 8: Now Build Tests
1. Select **Hoidma** scheme (still)
2. Press `Cmd+U` to test (this builds tests + app)
3. Or: **Product > Test** (or `Cmd+U`)

### Step 9: If Still Failing - Check Specific Errors
Look at the **Issue Navigator** (`Cmd+5`) and check:

**Common Errors:**

1. **"No such module 'XCTest'"**
   - Go to **HoidmaUITests** target > **Build Settings**
   - Search for `FRAMEWORK_SEARCH_PATHS`
   - Should include `$(PLATFORM_DIR)/Developer/Library/Frameworks`

2. **"Cannot find 'XCUIApplication' in scope"**
   - Make sure `import XCTest` is at the top of test files
   - Clean build folder and rebuild

3. **"Undefined symbol" errors**
   - The app target might not be building
   - Build the app target first (Step 7)

4. **"Test target 'HoidmaUITests' is not configured for testing"**
   - Go to **HoidmaUITests** target > **General**
   - Set **Target to be Tested** to `Hoidma`

5. **File not found errors**
   - The test files should be auto-synced
   - If not, manually add them:
     - Right-click **HoidmaUITests** folder
     - **Add Files to "Hoidma"...**
     - Select the test files
     - Make sure **HoidmaUITests** target is checked

### Step 10: Reset Package Caches (If Using Packages)
1. **File > Packages > Reset Package Caches**
2. **File > Packages > Resolve Package Versions**

### Step 11: Delete Derived Data (Last Resort)
1. Close Xcode
2. In Terminal:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/Hoidma-*
   ```
3. Reopen Xcode
4. Build again

## Verification Checklist

After following steps above, verify:
- ✅ App target builds successfully (`Cmd+B` on Hoidma scheme)
- ✅ Test target appears in Test Navigator (`Cmd+6`)
- ✅ Test methods are visible (not grayed out)
- ✅ Can run individual tests (play button works)
- ✅ No red errors in Issue Navigator (`Cmd+5`)

## Running Tests

Once builds succeed:
1. Press `Cmd+U` to run all tests
2. Or click play button next to test in Test Navigator
3. Tests will launch simulator and run automatically
