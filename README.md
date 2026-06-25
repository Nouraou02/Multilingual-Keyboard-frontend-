# Multilingual Keyboard - Frontend

This repository contains the iOS custom keyboard user interface built using Swift and Xcode.

## Prerequisites
- A Mac running macOS
- **Xcode** (Version 15 or 16 recommended)
- An iOS Simulator or a physical iOS device

## How to Install and Run

1. **Clone or Download the Project:**
   - Click the green **Code** button above and select **Download ZIP**, or clone it using Git.
2. **Open in Xcode:**
   - Open Xcode, choose **Open an Existing Project**, and select the `KeybordUI` folder (or open the `.xcodeproj` file).
3. **Select a Target Device:**
   - In the top menu bar of Xcode, select an iOS Simulator (e.g., iPhone 15 or iPhone 16) as your build target.
4. **Build and Run:**
   - Press **`Command + R`** or click the **Play** button in the top-left corner of Xcode to compile and launch the host app.

## How to Enable the Keyboard in iOS
Once the app opens on the simulator, you must manually enable the keyboard extension in the iOS operating system:

1. On the simulated iPhone, go to the main **Settings** app.
2. Navigate to **General** -> **Keyboard** -> **Keyboards**.
3. Tap **Add New Keyboard...** and select **Multilingual Keyboard** from the list.
4. Tap on the newly added keyboard and toggle **Allow Full Access** to **On** (required for network communication/predictions if applicable).
5. Open any chat app (like Notes or Safari), click a text field, hold down the **Globe 🌐** icon on the stock keyboard, and select your keyboard!
