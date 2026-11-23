# Project Specification: Local-First Personal Tracker (Obsidian-Style Architecture)

## 1. Project Overview & Vibe Coding Directives
Build a clean, fast, minimalist Flutter application for personal tracking, starting with **Food & Calorie Tracking**, architected to easily scale into **Habit Tracking**, **Running Distance**, and other custom metrics later. 

**Core Philosophy:** 
- **Local-First & Portable (Obsidian-Style):** All data and configurations are stored in human-readable local files (JSON/Markdown) inside a user-accessible folder (e.g., `Documents/PersonalTracker/`), NOT hidden internal app databases (like SQLite/SharedPreferences). This allows users to easily back up, sync (via Syncthing/iCloud/Drive), or manually inspect their data.
- **Zero-Lag Startup (Write-Through Cache):** Configurations and pre-made templates are loaded into memory *once* on app launch (or cached in fast memory/state) so subsequent UI transitions don't block on disk I/O. Any mutation updates memory immediately and asynchronously flushes to the local file.
- **Modular / Extensible Schema:** While Phase 1 focuses on Food, the data layer and UI must be decoupled enough that adding a "Running" or "Habits" module later requires adding a new tracker module rather than rewriting the core storage engine.

---

## 2. Tech Stack & Recommended Packages
Keep dependencies minimal and rock-solid for easy AI code generation:
Environment & Version Constraints
- **Flutter SDK:** 3.24.3 (Stable)
- **Dart SDK:** 3.5.3
- **Package Compatibility:** Ensure all dependencies in `pubspec.yaml` (`fl_chart`, `file_picker`, `path_provider`, `shared_preferences`, `intl`) resolve cleanly with Dart `^3.5.3` and Android Gradle Plugin 8.x (do NOT use AGP 9.0 or Flutter 3.38+ / 3.50+ APIs).
- **Framework:** Flutter (Latest Stable, Material 3)
- **State Management:** `flutter_riverpod` or `provider` (Use `ChangeNotifier` + `Provider` for maximum simplicity and zero boilerplate during vibe coding).
- **Local File Access:** `path_provider` + `permission_handler` (or `file_picker` to let the user choose their vault folder, just like Obsidian!).
- **Charts / Trends:** `fl_chart` (for Day/Week/Month calorie bar/line charts).
- **Date Formatting:** `intl`

---

## 3. Data Architecture & File System Design (The "Vault")

Create a `VaultService` class that manages a root directory (e.g., `/PersonalTrackerVault/`). On first launch, prompt the user to pick a directory (or default to the app's external documents directory) and initialize the default files if they don't exist.

### Directory Structure:
```text
PersonalTrackerVault/
├── config.json               # App settings, categories, active modules
├── food_presets.json         # User's saved pre-made foods
└── logs/
    └── food/
        ├── 2026-11.json      # Monthly partitioned log files (keeps reads/writes fast)
        └── 2026-12.json
```

### File Schemas:

#### A. `config.json` (Loaded once at startup, written on change)
```json
{
  "vaultVersion": 1,
  "dailyCalorieGoal": 2200,
  "junkFoodCategories": ["Junk", "Fast Food", "Sweets"],
  "foodCategories": [
    "Healthy",
    "Junk",
    "Protein",
    "Snacks",
    "Beverages"
  ],
  "enabledModules": ["food"] 
}
```
*Note: `enabledModules` allows future expansion to `["food", "habits", "running"]`.*

#### B. `food_presets.json` (Loaded once at startup, written when new preset added)
```json
[
  {
    "id": "preset_1",
    "name": "Oatmeal with Banana",
    "calories": 320,
    "defaultCategory": "Healthy"
  },
  {
    "id": "preset_2",
    "name": "Double Cheeseburger",
    "calories": 650,
    "defaultCategory": "Junk"
  }
]
```

#### C. `logs/food/YYYY-MM.json` (Partitioned by Month)
Partitioning by month prevents loading years of data on startup while making Weekly and Monthly trend queries ultra-fast.
```json
{
  "month": "2026-11",
  "entries": [
    {
      "id": "uuid-1234",
      "foodName": "Oatmeal with Banana",
      "calories": 320,
      "category": "Healthy",
      "timestamp": "2026-11-23T08:30:00.000Z"
    }
  ]
}
```

---

## 4. State Management & Caching Strategy
Implement a central `TrackerState` (`ChangeNotifier`):
1. **App Launch (`init()`):**
   - Check if vault path is saved in lightweight storage (only store the *folder path string* in `SharedPreferences` so the app knows where the vault is).
   - Read `config.json`, `food_presets.json`, and the current month's log (`logs/food/YYYY-MM.json`) into memory.
   - Notify UI. App is now 100% in-memory.
2. **Reading Data:**
   - UI reads exclusively from `TrackerState` memory lists. Zero file reads during normal navigation.
3. **Updating Config / Presets / Entries:**
   - Update the in-memory list/object immediately (`notifyListeners()`).
   - Fire an async background write (`_saveConfigToFile()`, `_savePresetsToFile()`, or `_saveCurrentMonthLog()`) so the UI never stutters.

---

## 5. UI / UX Screens & Component Breakdown

Use a clean, modern Material 3 dark/light adaptive theme with high contrast and large touch targets.

### Screen 1: Home Dashboard (`HomeScreen`)
- **Top App Bar:**
  - Title: "Today's Tracker" (or Module Switcher dropdown for future Habits/Running).
  - Action Icons: **Trends Icon** (Bar chart) & **Settings Icon** (Gear).
- **Hero Summary Card (Top):**
  - Displays **Total Calories Eaten Today** (e.g., `1,450 / 2,200 kcal`) with a clean progress bar.
  - Displays **Junk Food Calories Today** highlighted in an amber/red badge (calculated dynamically by summing today's entries where `category` is in `config.junkFoodCategories`, or specifically `"Junk"`).
- **Primary Action Button:**
  - Prominent full-width button: **`+ Add Food Entry`** (placed right below the Hero Summary Card).
- **Recent Entries List (Below Add Button):**
  - Chronological list (newest first) of today's (and recent) entries.
  - Each list tile shows:
    - **Food Name** (Bold) & **Category Chip** (Color-coded: e.g., Red/Orange for Junk, Green for Healthy).
    - **Timing** (Formatted nicely, e.g., `08:30 AM` or `Today, 1:15 PM`).
    - **Calorie Count** on the trailing right (e.g., `320 kcal`).
    - Swipe-to-delete or tap-to-edit support.

### Modal / Bottom Sheet: Add Food Entry (`AddFoodSheet`)
Triggered by the `+ Add Food Entry` button.
- **Mode Toggle / Quick Select:**
  - **Searchable Dropdown / Horizontal Chips of Pre-Made Foods:** Tapping a pre-made food auto-fills `Name`, `Calories`, and `Category`.
  - Or type directly into the fields for a custom one-off food.
- **Form Fields:**
  - `Food Name` (Text input)
  - `Calories` (Numeric input)
  - `Category` (Dropdown populated from `config.foodCategories`)
  - `Timing` (Defaults to `DateTime.now()`, tappable chip to open TimePicker/DatePicker)
- **Checkbox / Toggle:**
  - `[ ] Save as Pre-Made Food` (If checked, saves this item to `food_presets.json` simultaneously when logging!).
- **Submit Button:** `Save Entry`

### Screen 2: Trends & Analytics (`TrendsScreen`)
Triggered by the Trends icon in the App Bar.
- **Segmented Control (Timeframe Selector):**
  - `[ Day ]` | `[ Week ]` | `[ Month ]`
- **Chart Visualization (`fl_chart`):**
  - **Day View:** Hourly breakdown or comparison of today vs. daily average, split by Total vs. Junk calories.
  - **Week View:** 7-day bar chart (Mon–Sun) showing daily total calories (with stacked bar or secondary bar for Junk calories).
  - **Month View:** Daily bar/line chart across the selected month (1st–30th/31st), plus a month selector (`< Nov 2026 >`) that lazy-loads historical `YYYY-MM.json` files on demand.
- **Summary Metrics Below Chart:**
  - Average Daily Calories, Total Junk Calories in period, Highest Calorie Day.

### Screen 3: Settings & Vault Management (`SettingsScreen`)
Triggered by the Settings icon in the App Bar.
- **Vault Info Section:**
  - Displays current local folder path (e.g., `/storage/emulated/0/Documents/PersonalTrackerVault`).
  - Button: `Change Vault Folder` (Allows picking a new directory).
- **Manage Food Categories:**
  - List of current categories from `config.foodCategories`.
  - Text field + `Add` button to add a new category (immediately updates `config.json`).
  - Delete icon next to each category to remove it (immediately updates `config.json`).
  - Toggle switch next to each category: *"Count as Junk Food"* (updates `config.junkFoodCategories`).
- **Manage Pre-Made Foods:**
  - View, add, or delete items in `food_presets.json`.

---

## 6. Future-Proofing for Habits & Running (Extensibility Rules)
To ensure this app can easily grow into a multi-tracker later:
1. **Folder Isolation:** Keep food logs in `logs/food/`. Future trackers will simply use `logs/habits/` and `logs/running/`.
2. **Generic Log Interface:** Define an abstract class `TrackerEntry` with `id`, `timestamp`, and `toJson()`. `FoodEntry` implements `TrackerEntry`.
3. **Config Modularity:** Keep `config.json` structured with module-specific keys (e.g., `"foodConfig": { ... }`, `"habitConfig": { ... }`) or top-level extensible maps so adding new settings never breaks existing parsing.

---

## 7. Step-by-Step Vibe Coding Execution Plan
*Instruct the AI assistant to build the app iteratively in these exact 4 prompts:*

1. **Prompt 1 (Core Storage & Models):** *"Create the data models (`AppConfig`, `FoodPreset`, `FoodEntry`) and `VaultService` using `path_provider` and `file_picker`. Ensure `config.json`, `food_presets.json`, and `logs/food/YYYY-MM.json` are created in a local directory, loaded into a `ChangeNotifier` state provider once at startup, and written asynchronously whenever updated."*
2. **Prompt 2 (Home UI & Add Food Flow):** *"Build the `HomeScreen` with the Today's Total Calories & Junk Food summary card, the `+ Add Food Entry` button, and the Recent Entries list. Create the `AddFoodBottomSheet` supporting pre-made food selection, custom entry, timing picker, category dropdown, and a 'Save to Pre-made Foods' checkbox."*
3. **Prompt 3 (Settings & Category Management):** *"Build the `SettingsScreen` allowing users to view/change their local Vault directory, add/remove food categories, mark categories as 'Junk Food', and manage their saved pre-made foods list, syncing all changes to `config.json` and `food_presets.json`."*
4. **Prompt 4 (Trends Screen):** *"Build the `TrendsScreen` using `fl_chart` with a Day / Week / Month toggle. Aggregate data from the local monthly JSON files to display calorie trends and junk food breakdowns."*