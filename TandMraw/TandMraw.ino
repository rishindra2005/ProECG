// Improved Arduino code for AD8232 Heart Monitor
// With enhanced sensitivity and diagnostic features

// Pin definitions
const int LO_POS = 10;  // Lead-off detection positive - digital pin
const int LO_NEG = 11;  // Lead-off detection negative - digital pin
const int OUTPUT_PIN = A0;  // Analog output from AD8232
const int SDN_PIN = 4;  // Shutdown pin (active high)

// Variables for signal processing
int rawValue = 0;
const int SAMPLES = 5;
int sampleBuffer[SAMPLES];
int sampleIndex = 0;
unsigned long lastReading = 0;
const int SAMPLE_INTERVAL = 10; // 10ms interval = 100Hz

void setup() {
  // Initialize serial communication at high baud rate for smoother data
  Serial.begin(115200);
  
  // Set up lead-off detection pins as inputs
  pinMode(LO_POS, INPUT);
  pinMode(LO_NEG, INPUT);
  
  // Set up SDN pin as output and ensure the device is on (SDN low)
  pinMode(SDN_PIN, OUTPUT);
  digitalWrite(SDN_PIN, LOW);  // Active low - turn on the device
  
  // Initialize sample buffer
  for(int i=0; i<SAMPLES; i++) {
    sampleBuffer[i] = 0;
  }
  
  // Send header information to Processing
  Serial.println("ECG Monitoring Started");
  delay(1000); // Give the sensor time to stabilize
}

void loop() {
  unsigned long currentTime = millis();
  
  // Check if it's time for a new reading
  if (currentTime - lastReading >= SAMPLE_INTERVAL) {
    lastReading = currentTime;
    
    // Check if leads are connected
    if((digitalRead(LO_POS) == 1) || (digitalRead(LO_NEG) == 1)) {
      // Leads are not connected properly
      Serial.println("!");  // Send a special character to indicate leads off
    }
    else {
      // Leads are connected, read the ECG value
      rawValue = analogRead(OUTPUT_PIN);
      
      // Add to rolling buffer for signal processing
      sampleBuffer[sampleIndex] = rawValue;
      sampleIndex = (sampleIndex + 1) % SAMPLES;
      
      // Send the raw value first for maximum sensitivity
      Serial.println(rawValue);
      
      // Every 100 readings, send a diagnostic line with min/max values
      static int readingCounter = 0;
      if(++readingCounter >= 100) {
        readingCounter = 0;
        
        // Calculate min and max values in the recent readings
        int minVal = 1023, maxVal = 0;
        for(int i=0; i<SAMPLES; i++) {
          if(sampleBuffer[i] < minVal) minVal = sampleBuffer[i];
          if(sampleBuffer[i] > maxVal) maxVal = sampleBuffer[i];
        }
        
        // Send diagnostic information prefixed with # so Processing can identify it
        Serial.print("#RANGE:");
        Serial.print(minVal);
        Serial.print(",");
        Serial.println(maxVal);
      }
    }
  }
}
