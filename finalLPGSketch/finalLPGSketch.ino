// --- Core ESP32 Libraries ---
#include <WiFi.h>           // For Wi-Fi connectivity
#include <WebServer.h>      // For running a web server in SoftAP mode
#include <Preferences.h>    // For Non-Volatile Storage (NVS) to save Wi-Fi credentials
#include <ArduinoJson.h>    // For parsing and creating JSON data (Install via Library Manager)
#include <time.h>           // Required for NTP time synchronization

// --- Firebase Library ---
// You MUST install "Firebase ESP32 Client" by Mobizt (latest stable version, e.g., v4.4.17 or higher).
// Ensure you are using the library from "https://github.com/mobizt/Firebase-ESP-Client"
#include <Firebase_ESP_Client.h>

// Provide the token generation process info (included in Mobizt's library examples)
// This header defines tokenStatusCallback, so we do NOT define it again in this sketch.
#include <addons/TokenHelper.h>

// --- Load Cell (HX711) Library ---
// You MUST install "HX711 by Bogde"
#include <HX711.h>

// --- OLED Display Libraries ---
#include <Wire.h>           // Required for I2C communication (for OLED)
#include <Adafruit_GFX.h>   // Core graphics library
#include <Adafruit_SSD1306.h> // Library for SSD1306 OLED display

// --- Firebase Configuration ---
// IMPORTANT: Replace with your actual Firebase Project ID and Web API KEY!
// Use the values you've configured in your Firebase Console.
#define FIREBASE_PROJECT_ID "lpggasmonitor-e811a"
#define FIREBASE_WEB_API_KEY "AIzaSyAvRLZ1UVdmVZMSdC0DIHxqt1clBGcqBNM"
#define FIREBASE_HOST "firestore.googleapis.com"
#define FIREBASE_DATABASE_URL "https://lpggasmonitor-e811a.firebaseio.com"

// --- Device Specifics ---
String deviceId; // Unique ID for this ESP32 (MAC address based)
const float CALIBRATION_FACTOR = 21.38;

// --- Hardware Pin Definitions (Adjust for your wiring) ---
const int LOADCELL_DOUT_PIN = 25; // HX711 Data pin (DO)
const int LOADCELL_SCK_PIN = 26;  // HX711 Clock pin (SCK)
HX711 scale; // HX711 instance

#define OLED_SDA_PIN 19 // SDA pin (common for ESP32 DevKitC)
#define OLED_SCL_PIN 22 // SCL pin (common for ESP32 DevKitC)
#define OLED_RESET_PIN -1 // Reset pin (often -1 for shared reset with ESP32)
#define SCREEN_WIDTH 128 // OLED display width, in pixels
#define SCREEN_HEIGHT 64 // OLED display height, in pixels
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET_PIN); // OLED instance

const int BUZZER_PIN = 23; // Example pin for buzzer
const int LED_PIN = 27; // Example pin for blue LED (often onboard LED on some ESP32 boards)
const int BUTTON_PIN = 5; // Example pin for push button (e.g., flash button or custom button) - Using GPIO 5

// --- WebServer for SoftAP Provisioning ---
WebServer server(80);
const char* softAP_ssid_prefix = "LPG_ESP_"; // SoftAP SSID will be LPG_ESP_XXXX
const char* softAP_password = "password"; // Default password for SoftAP, can be empty string for open AP

// --- Non-Volatile Storage (NVS) ---
Preferences preferences;
const char* NVS_NAMESPACE = "lpg-config"; // Namespace for NVS storage
const char* NVS_SSID_KEY = "ssid";
const char* NVS_PASS_KEY = "password";
const char* NVS_DEV_NAME_KEY = "dev_name"; // For storing friendly name from app
const char* NVS_FIREBASE_EMAIL_KEY = "fb_email"; // Key for Firebase email
const char* NVS_FIREBASE_PASS_KEY = "fb_pass"; // Key for Firebase password

// --- Firebase Configuration Objects ---
FirebaseConfig config;
FirebaseAuth auth;
FirebaseData fbdo;

// --- Global Variables for WiFi, Sensor Loop, and Firebase Updates ---
String storedSSID = "";
String storedPassword = "";
String storedDeviceName = "Unnamed Device"; // Default friendly name
String storedFirebaseEmail = "";
String storedFirebasePassword = "";

// For live weight display (updated frequently)
unsigned long lastDisplayUpdateTime = 0;
const long displayUpdateInterval = 500; // Update OLED display every 500 ms (0.5 seconds)

// For smart Firebase history updates (less frequent, based on change or max interval)
float _lastSentHistoryWeight = -9999.0; // Initialize with an improbable value to force first history send
const float WEIGHT_CHANGE_THRESHOLD_GRAMS = 250.0; // Send history if weight changes by 250 grams
unsigned long lastHistorySendTimestamp = 0;
const long MAX_FIREBASE_HISTORY_INTERVAL_MS = 300000; // Send history at least once every 5 minutes (300000 ms)

// For frequent current weight updates to the main device document
unsigned long lastCurrentWeightUpdateTimestamp = 0;
const long CURRENT_WEIGHT_UPDATE_INTERVAL_MS = 10000; // Update current weight in main document every 10 seconds

// Flag to track if Firebase has been initialized for the current connection
bool _isFirebaseInitialized = false;

// --- Function Prototypes ---
void handleRoot();
void handleSaveConfig();
void handleNotFound();
void startSoftAP();
bool connectToWiFi();
void displayStatus(String status);
void displayWeight(float weight);
void displayConnecting(String ssid);
void displayProvisioning();
void buzz(int duration_ms);
void updateMainDeviceDocument(float weightToSend);
void addHistoryEntryToFirebase(float weightToSend);
String getMacAddress();
void clearNVS();
String getISOTime();

void setup() {
  Serial.begin(115200);
  delay(100);
  Serial.println("\nESP32 LPG Monitor - Booting...");

  WiFi.mode(WIFI_AP_STA);
  delay(100);

  deviceId = "LPG_" + WiFi.macAddress();
  deviceId.replace(":", "");
  Serial.print("Device ID: ");
  Serial.println(deviceId);

  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(LED_PIN, OUTPUT);
  pinMode(BUTTON_PIN, INPUT_PULLDOWN);

  Wire.begin(OLED_SDA_PIN, OLED_SCL_PIN);
  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println(F("SSD1306 allocation failed"));
    displayStatus("OLED Fail!");
    for (;;);
  }

  display.setRotation(2);
  display.display();
  delay(2000);
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  displayStatus("Booting...");
  Serial.println("OLED initialized.");

  Serial.print("Initializing HX711... ");
  displayStatus("Init HX711...");
  scale.begin(LOADCELL_DOUT_PIN, LOADCELL_SCK_PIN);
  scale.set_scale(CALIBRATION_FACTOR);
  scale.tare();
  delay(1000);
  if (scale.is_ready()) {
    Serial.println("Ready!");
    displayStatus("HX711 Ready!");
    _lastSentHistoryWeight = scale.get_units(10);
  } else {
    Serial.println("Error!");
    displayStatus("HX711 Error!");
  }
  delay(1000);

  Serial.print("Checking button for force provisioning (hold for 5s)...");
  displayStatus("Check Button");

  bool forceProvisioning = true;
  unsigned long bootCheckDuration = 5000;
  unsigned long startTime = millis();

  while (millis() - startTime < bootCheckDuration) {
    int buttonState = digitalRead(BUTTON_PIN);
    Serial.print("Button state: "); Serial.println(buttonState);
    
    if (buttonState == LOW) {
      forceProvisioning = false;
      digitalWrite(LED_PIN, LOW);
      break;
    }
    digitalWrite(LED_PIN, HIGH);
    delay(50);
  }
  digitalWrite(LED_PIN, LOW);

  if (forceProvisioning) {
    Serial.println("\nButton held consistently HIGH! Forcing SoftAP mode and clearing saved credentials...");
    displayStatus("Force AP: Clear");
    delay(1000);
    clearNVS();
    startSoftAP();
  } else {
    Serial.println("Button not held for sufficient duration (or went LOW), proceeding with saved config.");
    preferences.begin(NVS_NAMESPACE, false);
    storedSSID = preferences.getString(NVS_SSID_KEY, "");
    storedPassword = preferences.getString(NVS_PASS_KEY, "");
    storedDeviceName = preferences.getString(NVS_DEV_NAME_KEY, "Unnamed Device");
    storedFirebaseEmail = preferences.getString(NVS_FIREBASE_EMAIL_KEY, "");
    storedFirebasePassword = preferences.getString(NVS_FIREBASE_PASS_KEY, "");
    preferences.end();

    if (storedSSID != "" && storedPassword != "") {
      Serial.print("Attempting to connect to stored WiFi: ");
      Serial.println(storedSSID);
      displayConnecting(storedSSID);
      if (!connectToWiFi()) {
        Serial.println("Failed to connect to stored WiFi. Starting SoftAP.");
        startSoftAP();
      }
    } else {
      Serial.println("No saved WiFi credentials. Starting SoftAP.");
      startSoftAP();
    }
  }

  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  Serial.println("NTP time synchronization initiated.");

  config.api_key = FIREBASE_WEB_API_KEY;
  config.database_url = FIREBASE_DATABASE_URL;
  config.host = FIREBASE_HOST;

  auth.user.email = storedFirebaseEmail.c_str();
  auth.user.password = storedFirebasePassword.c_str();
  
  config.token_status_callback = tokenStatusCallback;
  Firebase.reconnectNetwork(true);
  fbdo.setBSSLBufferSize(4096, 1024);
  fbdo.setResponseSize(2048);

  Serial.println("Setup complete (Firebase config prepared).");
  lastHistorySendTimestamp = millis();
  lastCurrentWeightUpdateTimestamp = millis();
}

void loop() {
  server.handleClient();

  if (WiFi.status() == WL_CONNECTED) {
    if (!_isFirebaseInitialized) {
      Serial.println("WiFi connected. Initializing Firebase...");
      displayStatus("Init Firebase...");
      Firebase.begin(&config, &auth);
      _isFirebaseInitialized = true;
      Serial.println("Firebase initialization attempt complete.");
    }

    if (Firebase.ready()) {
      if (millis() - lastDisplayUpdateTime >= displayUpdateInterval) {
        float liveWeight = scale.get_units(1);
        displayWeight(liveWeight);
        lastDisplayUpdateTime = millis();
      }

      if (millis() - lastCurrentWeightUpdateTimestamp >= CURRENT_WEIGHT_UPDATE_INTERVAL_MS) {
        Serial.println("Updating main device document (10 sec interval)...");
        float currentWeightForMainDoc = scale.get_units(5);
        updateMainDeviceDocument(currentWeightForMainDoc);
        lastCurrentWeightUpdateTimestamp = millis();
      }

      float currentStableWeightForHistory = scale.get_units(10);

      if (abs(currentStableWeightForHistory - _lastSentHistoryWeight) >= WEIGHT_CHANGE_THRESHOLD_GRAMS ||
          (millis() - lastHistorySendTimestamp >= MAX_FIREBASE_HISTORY_INTERVAL_MS)) {
        
        Serial.println("Adding history entry (significant change or hourly interval)...");
        addHistoryEntryToFirebase(currentStableWeightForHistory);
        _lastSentHistoryWeight = currentStableWeightForHistory;
        lastHistorySendTimestamp = millis();
      }
    } else {
      displayStatus("Firebase Auth...");
      Serial.print("Firebase not ready. Waiting for token/connection. Error: ");
      Serial.println(fbdo.errorReason());
      delay(500);
    }
  } else {
    if (_isFirebaseInitialized) {
      _isFirebaseInitialized = false;
      Serial.println("WiFi disconnected or changed mode. Firebase initialization reset.");
    }

    if (WiFi.getMode() == WIFI_STA && storedSSID != "") {
      Serial.println("WiFi disconnected. Reconnecting...");
      displayConnecting(storedSSID);
      delay(1000);
      if (!connectToWiFi()) {
        Serial.println("Failed to reconnect to home WiFi. Restarting SoftAP.");
        startSoftAP();
      }
    }
    else if (WiFi.getMode() == WIFI_AP) {
      displayProvisioning();
    } else {
      displayStatus("Waiting for WiFi");
      delay(1000);
    }
  }
}

// --- SoftAP and WebServer Functions ---
void startSoftAP() {
  WiFi.mode(WIFI_AP);
  String softAP_mac_suffix = WiFi.macAddress();
  softAP_mac_suffix.replace(":", "");
  softAP_mac_suffix = softAP_mac_suffix.substring(softAP_mac_suffix.length() - 4);
  String softAP_ssid = String(softAP_ssid_prefix) + softAP_mac_suffix;

  Serial.print("Starting SoftAP with SSID: ");
  Serial.println(softAP_ssid);
  displayProvisioning();
  WiFi.softAP(softAP_ssid.c_str(), softAP_password);
  Serial.print("SoftAP IP address: ");
  Serial.println(WiFi.softAPIP());

  server.on("/", handleRoot);
  // Change to HTTP_POST to receive form data
  server.on("/save_config", HTTP_POST, handleSaveConfig); 
  server.onNotFound(handleNotFound);
  server.begin();
  Serial.println("Web server started.");
}

// Minimal HTML for the root to indicate connection instructions
void handleRoot() {
  String html = "<!DOCTYPE html><html lang='en'><head><meta charset='UTF-8'><meta name='viewport' content='width=device-width, initial-scale=1.0'><title>ESP32 Info</title></head><body><h1>ESP32 Active</h1><p>This ESP32 is in provisioning mode.</p><p>Connect via the mobile app to configure.</p><p>Device ID: " + deviceId + "</p><p>IP: " + WiFi.softAPIP().toString() + "</p></body></html>";
  server.send(200, "text/html", html);
}

// Handles POST request from Flutter app to save config
void handleSaveConfig() {
  // Ensure the request method is POST
  if (server.method() != HTTP_POST) {
    server.send(405, "text/plain", "Method Not Allowed");
    return;
  }

  // Check if all expected arguments are present
  if (!server.hasArg("ssid") || !server.hasArg("pass") || 
      !server.hasArg("fb_email") || !server.hasArg("fb_pass") || !server.hasArg("dev_name")) {
    
    // Respond with a JSON error if arguments are missing
    StaticJsonDocument<200> jsonErrorDoc;
    jsonErrorDoc["status"] = "error";
    jsonErrorDoc["message"] = "Missing required configuration parameters.";
    String jsonResponse;
    serializeJson(jsonErrorDoc, jsonResponse);
    server.send(400, "application/json", jsonResponse);
    return;
  }

  String newSSID = server.arg("ssid");
  String newPassword = server.arg("pass");
  String newFirebaseEmail = server.arg("fb_email");
  String newFirebasePassword = server.arg("fb_pass");
  String newDeviceName = server.arg("dev_name"); // Added dev_name argument

  preferences.begin(NVS_NAMESPACE, false);
  preferences.putString(NVS_SSID_KEY, newSSID);
  preferences.putString(NVS_PASS_KEY, newPassword);
  preferences.putString(NVS_FIREBASE_EMAIL_KEY, newFirebaseEmail);
  preferences.putString(NVS_FIREBASE_PASS_KEY, newFirebasePassword);
  preferences.putString(NVS_DEV_NAME_KEY, newDeviceName); // Save friendly name
  preferences.end();

  Serial.println("Configuration saved to NVS (from app):");
  Serial.print("SSID: "); Serial.println(newSSID);
  Serial.print("Device Name: "); Serial.println(newDeviceName);
  Serial.print("Firebase Email: "); Serial.println(newFirebaseEmail);

  // Prepare JSON response with status and deviceId
  StaticJsonDocument<200> jsonDoc;
  jsonDoc["status"] = "success";
  jsonDoc["message"] = "Configuration received and saved. Attempting to connect.";
  jsonDoc["deviceId"] = deviceId; // Include the deviceId in the response

  String jsonResponse;
  serializeJson(jsonDoc, jsonResponse);
  server.send(200, "application/json", jsonResponse); // Send JSON response

  Serial.println("Attempting to connect to new WiFi (from app config)...");
  displayStatus("Connecting Home");
  displayConnecting(newSSID);

  // Delay briefly to ensure JSON response is sent before changing WiFi mode
  delay(100); 
  server.stop();
  WiFi.softAPdisconnect(true); // Disconnect SoftAP
  WiFi.mode(WIFI_STA); // Switch to Station mode

  // Update global stored variables (optional, as they're also loaded from NVS in setup)
  storedSSID = newSSID;
  storedPassword = newPassword;
  storedDeviceName = newDeviceName;
  storedFirebaseEmail = newFirebaseEmail;
  storedFirebasePassword = newFirebasePassword;

  _isFirebaseInitialized = false; // Reset Firebase init flag to re-initialize with new credentials

  // Update Firebase auth object with new credentials
  auth.user.email = storedFirebaseEmail.c_str();
  auth.user.password = storedFirebasePassword.c_str();

  // Attempt to connect to the home WiFi
  if (!connectToWiFi()) {
    Serial.println("Failed to connect to home WiFi after app config. Restarting SoftAP.");
    startSoftAP(); // If connection fails, restart SoftAP for re-provisioning
  }
}

void handleNotFound() {
  server.send(404, "text/plain", "Not found");
}

// --- WiFi Connection Function ---
bool connectToWiFi() {
  // Ensure mode is set to STA if it's not already
  if (WiFi.getMode() != WIFI_STA) {
    WiFi.mode(WIFI_STA);
  }
  WiFi.begin(storedSSID.c_str(), storedPassword.c_str());
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 40) { // Max 40 seconds (40 attempts * 1s delay)
    delay(1000);
    Serial.print(".");
    displayConnecting(storedSSID); // Update OLED with connecting status
    attempts++;
  }
  Serial.println();
  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("Connected to WiFi! IP: ");
    Serial.println(WiFi.localIP());
    displayStatus("Connected!");
    digitalWrite(LED_PIN, HIGH); // Turn on LED on successful connection
    return true;
  } else {
    Serial.println("WiFi connection failed.");
    displayStatus("WiFi Failed!");
    digitalWrite(LED_PIN, LOW); // Turn off LED on failed connection
    return false;
  }
}

// --- OLED Display Functions ---
void displayStatus(String status) {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0,0);
  display.print("Status:");
  display.setCursor(0,10);
  display.print(status);
  display.display();
}

void displayConnecting(String ssid) {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0,0);
  display.print("Connecting to:");
  display.setCursor(0,10);
  display.print(ssid);
  display.setCursor(0,20);
  display.print("Please wait...");
  display.display();
}

void displayProvisioning() {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0,0);
  display.print("Connect to WiFi:");
  display.setCursor(0,10);
  display.print("SSID: LPG_ESP_xxxx"); // Generic instruction as suffix changes
  display.setCursor(0,20);
  display.print("ID: ");
  display.println(deviceId); // Display the full device ID
  display.setCursor(0,30);
  display.print("Pass: ");
  display.println(softAP_password);
  display.setCursor(0,40);
  display.print("Then open app.");
  display.display();
}

void displayWeight(float weight) {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0,0);
  display.print("Device: ");
  display.println(storedDeviceName);
  display.setCursor(0,10);
  display.print("Weight: ");
  display.print(weight, 2);
  display.println("g");
  display.setCursor(0,20);
  display.print("Status: Online");
  display.display();
}

// --- Buzzer Function ---
void buzz(int duration_ms) {
  digitalWrite(BUZZER_PIN, HIGH);
  delay(duration_ms);
  digitalWrite(BUZZER_PIN, LOW);
}

// Helper function to get current time in ISO 8601 format (UTC)
String getISOTime() {
  time_t now;
  struct tm timeinfo;
  time(&now);
  gmtime_r(&now, &timeinfo);
  
  char isoTime[25];
  strftime(isoTime, sizeof(isoTime), "%Y-%m-%dT%H:%M:%SZ", &timeinfo);
  
  return String(isoTime);
}

// --- Firebase Functions ---
void updateMainDeviceDocument(float weightToSend) {
  Serial.print("Updating main device document with current weight: ");
  Serial.print(weightToSend, 2);
  Serial.println(" grams");

  String deviceDocPath = "devices/" + deviceId;
  String isoTimestamp = getISOTime();

  FirebaseJson content;
  content.set("fields/current_weight_grams/doubleValue", weightToSend);
  content.set("fields/timestamp/timestampValue", isoTimestamp);

  if (Firebase.Firestore.patchDocument(&fbdo, FIREBASE_PROJECT_ID, "", deviceDocPath.c_str(), content.raw(), "current_weight_grams,timestamp")) {
    Serial.printf("Main document updated ok\n%s\n\n", fbdo.payload().c_str());
  } else {
    Serial.println("Failed to update main device document: ");
    Serial.println(fbdo.errorReason());
    buzz(50);
  }
}

void addHistoryEntryToFirebase(float weightToSend) {
  Serial.print("Adding history entry for weight: ");
  Serial.print(weightToSend, 2);
  Serial.println(" grams");

  String deviceDocPath = "devices/" + deviceId;
  String historyCollectionPath = deviceDocPath + "/history";
  String isoTimestamp = getISOTime();

  FirebaseJson historyContent;
  historyContent.set("fields/weight_grams/doubleValue", weightToSend);
  historyContent.set("fields/timestamp/timestampValue", isoTimestamp);

  if (Firebase.Firestore.createDocument(&fbdo, FIREBASE_PROJECT_ID, "", historyCollectionPath.c_str(), historyContent.raw())) {
    Serial.printf("History entry added ok\n%s\n\n", fbdo.payload().c_str());
  } else {
    Serial.println("Failed to add history entry: ");
    Serial.println(fbdo.errorReason());
    buzz(100);
  }
}

// Helper to get MAC address for Device ID (not directly used for SoftAP SSID anymore, but good to keep)
String getMacAddress() {
  uint8_t mac[6];
  WiFi.macAddress(mac);
  String macStr = "";
  for (int i = 0; i < 6; ++i) {
    macStr += String(mac[i], HEX);
    if (i < 5) macStr += ":";
  }
  return macStr;
}

// Function to clear all stored NVS data
void clearNVS() {
  preferences.begin(NVS_NAMESPACE, false);
  preferences.clear();
  preferences.end();
  Serial.println("NVS cleared. All saved credentials removed.");
  storedSSID = "";
  storedPassword = "";
  storedDeviceName = "Unnamed Device";
  storedFirebaseEmail = "";
  storedFirebasePassword = "";
}
