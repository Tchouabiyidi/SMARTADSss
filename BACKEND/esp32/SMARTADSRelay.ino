#include <WiFi.h>
#include <WebServer.h>

// Fill these in on the ESP32. Keep DEVICE_TOKEN private and use the same
// value for ESP32_DEVICE_TOKEN in BACKEND/.env.
const char *WIFI_SSID = "YOUR_WIFI_NAME";
const char *WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";
const char *DEVICE_TOKEN = "REPLACE_WITH_A_LONG_RANDOM_TOKEN";

// Connect the relay module's IN pin to this GPIO. Change the active level if
// your relay board uses active-high instead of active-low logic.
const int RELAY_PIN = 26;
const bool RELAY_ACTIVE_LOW = true;

WebServer server(80);
const char *headerKeys[] = {"Authorization"};

void setRelay(bool on) {
  const bool outputHigh = RELAY_ACTIVE_LOW ? !on : on;
  digitalWrite(RELAY_PIN, outputHigh ? HIGH : LOW);
}

void handleRelay() {
  const String expected = String("Bearer ") + DEVICE_TOKEN;
  if (server.header("Authorization") != expected) {
    server.send(401, "application/json", "{\"error\":\"unauthorized\"}");
    return;
  }

  String command = server.arg("plain");
  command.trim();
  command.toUpperCase();
  if (command == "ON") {
    setRelay(true);
    server.send(200, "application/json", "{\"state\":\"on\"}");
  } else if (command == "OFF") {
    setRelay(false);
    server.send(200, "application/json", "{\"state\":\"off\"}");
  } else {
    server.send(400, "application/json", "{\"error\":\"send ON or OFF\"}");
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(RELAY_PIN, OUTPUT);
  setRelay(false);

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting to Wi-Fi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println();
  Serial.print("SMARTADS ESP32 address: http://");
  Serial.println(WiFi.localIP());

  server.collectHeaders(headerKeys, 1);
  server.on("/health", HTTP_GET, []() {
    server.send(200, "application/json", "{\"status\":\"ok\"}");
  });
  server.on("/relay", HTTP_POST, handleRelay);
  server.begin();
}

void loop() {
  server.handleClient();
}
