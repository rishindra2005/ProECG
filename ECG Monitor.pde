// ECG monitor with filtering, heart rate calculation, and dynamic scaling
// Designed to receive data from Arduino with AD8232 heart monitor

import processing.serial.*;

// Constants
final int BUFFER_SIZE = 5000;  // Size of data buffer
final int DISPLAY_WIDTH = 1200;  // Width of display window
final int DISPLAY_HEIGHT = 800;  // Height of display window
final int GRAPH_HEIGHT = 400;    // Height of the main graph
final int SIDEBAR_WIDTH = 300;   // Width of sidebar
final int PADDING = 50;          // Padding around graph
final color BG_COLOR = color(10, 10, 25);  // Dark background
final color GRAPH_COLOR = color(0, 255, 150);  // Bright green for the ECG
final color FILTERED_COLOR = color(0, 150, 255);  // Blue for filtered data
final color TEXT_COLOR = color(220, 220, 220);  // Light gray for text
final color WARNING_COLOR = color(255, 50, 50);  // Red for warnings
boolean isFullScreen = false;  // Flag for full screen mode

// Data structures
float[] rawData;        // Buffer for raw ECG data
float[] filteredData;   // Buffer for filtered ECG data
int dataIndex = 0;      // Current position in circular buffer
float minValue = 0;     // Current minimum value for dynamic scaling
float maxValue = 1023;  // Current maximum value for dynamic scaling
boolean leadsConnected = true;  // Flag for lead connection status
int leadsDisconnectedCount = 0;  // Counter for disconnection events

// Heart rate calculation variables
float threshold = 550;  // Threshold for R peak detection (will be adjusted dynamically)
long lastPeakTime = 0;  // Time of last detected R peak
int heartRate = 0;      // Calculated heart rate in BPM
int[] rrIntervals = new int[5]; // Reduced from 10 to 5 for faster updates
int rrIndex = 0;        // Current index in R-R intervals array
int peakCount = 0;      // Counter for detected peaks
boolean isPeakDetected = false;  // Flag to avoid multiple detections of the same peak
int lastValidRRInterval = 0;     // Store the most recent valid R-R interval

// Serial communication
Serial myPort;  // Serial port object
String portName;  // Name of the serial port

// Advanced filtering
ECGFilters filters;  // ECG filtering object

// UI state variables
boolean showDebugInfo = false;
PGraphics ecgCanvas;  // For saving screenshots
boolean showRawFiltered = true;  // Toggle to show both raw and filtered data

void setup() {
  size(1200, 800);
  surface.setTitle("ProECG Monitor");
  surface.setResizable(true);  // Allow window resizing
  background(BG_COLOR);
  
  // Initialize data arrays
  rawData = new float[BUFFER_SIZE];
  filteredData = new float[BUFFER_SIZE];
  for (int i = 0; i < BUFFER_SIZE; i++) {
    rawData[i] = 0;
    filteredData[i] = 0;
  }
  
  // Initialize RR intervals
  for (int i = 0; i < rrIntervals.length; i++) {
    rrIntervals[i] = 0;
  }
  
  // Initialize filters with 200 samples history for statistics
  filters = new ECGFilters(200);
  
  // Initialize serial communication
  println("Available serial ports:");
  printArray(Serial.list());
  
  // Attempt to connect to the first available port
  if (Serial.list().length > 0) {
    portName = Serial.list()[0];
    myPort = new Serial(this, portName, 115200);
    myPort.bufferUntil('\n');
    println("Connected to port: " + portName);
  } else {
    println("No serial ports available!");
  }
  
  // Set up text rendering
  textSize(14);
  textAlign(LEFT, CENTER);
  
  // Create canvas for saving screenshots
  ecgCanvas = createGraphics(width, height);
}

void draw() {
  // Clear the screen
  background(BG_COLOR);
  
  // Draw sidebar
  drawSidebar();
  
  // Draw main ECG graph
  drawECGGraph();
  
  // Draw filtered data graph
  drawFilteredGraph();
  
  // Display warning if leads are disconnected
  if (!leadsConnected) {
    fill(WARNING_COLOR);
    textSize(32);
    text("LEADS DISCONNECTED", width/2 - 150, height/2);
    textSize(14);
  }
  
  // Show debug info if enabled
  if (showDebugInfo) {
    drawDebugInfo();
  }
}

void drawSidebar() {
  // Sidebar background
  fill(20, 20, 40);
  noStroke();
  rect(width - SIDEBAR_WIDTH, 0, SIDEBAR_WIDTH, height);
  
  // Title
  fill(TEXT_COLOR);
  textSize(24);
  text("ProECG Monitor", width - SIDEBAR_WIDTH + 20, 40);
  textSize(14);
  
  // Display heart rate
  int y = 100;
  text("Heart Rate:", width - SIDEBAR_WIDTH + 20, y);
  
  if (heartRate > 0) {
    textSize(48);
    fill(GRAPH_COLOR);
    text(heartRate + " BPM", width - SIDEBAR_WIDTH + 20, y + 50);
    textSize(14);
    fill(TEXT_COLOR);
  } else {
    text("Calculating...", width - SIDEBAR_WIDTH + 20, y + 50);
  }
  
  // Display statistics
  y = 200;
  text("Signal Statistics:", width - SIDEBAR_WIDTH + 20, y);
  text("Min value: " + nf(minValue, 0, 2), width - SIDEBAR_WIDTH + 20, y + 30);
  text("Max value: " + nf(maxValue, 0, 2), width - SIDEBAR_WIDTH + 20, y + 50);
  text("Range: " + nf(maxValue - minValue, 0, 2), width - SIDEBAR_WIDTH + 20, y + 70);
  
  // Display connection status
  y = 320;
  text("Connection Status:", width - SIDEBAR_WIDTH + 20, y);
  if (leadsConnected) {
    fill(0, 255, 0);
    text("CONNECTED", width - SIDEBAR_WIDTH + 20, y + 30);
  } else {
    fill(WARNING_COLOR);
    text("DISCONNECTED", width - SIDEBAR_WIDTH + 20, y + 30);
  }
  
  // Restore text color
  fill(TEXT_COLOR);
  
  // Display filter information
  y = 400;
  text("Filter Information:", width - SIDEBAR_WIDTH + 20, y);
  // Display filter info from the ECGFilters class
  String[] filterInfo = split(filters.getFilterInfo(), '\n');
  for (int i = 0; i < filterInfo.length; i++) {
    text(filterInfo[i], width - SIDEBAR_WIDTH + 20, y + 30 + (i * 20));
  }
  
  // Display port information
  y = 500;
  text("Serial Port:", width - SIDEBAR_WIDTH + 20, y);
  text(portName != null ? portName : "Not connected", width - SIDEBAR_WIDTH + 20, y + 30);
  
  // Help text
  y = height - 160;  // Adjusted to make room for new controls
  text("Controls:", width - SIDEBAR_WIDTH + 20, y);
  text("'r' - Reset data", width - SIDEBAR_WIDTH + 20, y + 20);
  text("'s' - Save data to CSV", width - SIDEBAR_WIDTH + 20, y + 40);
  text("'p' - Save screenshot", width - SIDEBAR_WIDTH + 20, y + 60);
  text("'d' - Toggle debug info", width - SIDEBAR_WIDTH + 20, y + 80);
  text("'f' - Toggle adaptive filtering mode", width - SIDEBAR_WIDTH + 20, y + 100);
  text("'t' - Toggle between showing raw+filtered or just raw data", width - SIDEBAR_WIDTH + 20, y + 120);
  text("'SPACE' - Toggle full screen mode", width - SIDEBAR_WIDTH + 20, y + 140);
}

void drawECGGraph() {
  int graphWidth = width - SIDEBAR_WIDTH - (2 * PADDING);
  int graphHeight = GRAPH_HEIGHT;
  int startX = PADDING;
  int startY = PADDING;
  
  // Draw graph background and border
  fill(15, 15, 30);
  stroke(50, 50, 70);
  rect(startX, startY, graphWidth, graphHeight);
  
  // Draw grid
  stroke(40, 40, 60);
  for (int x = 0; x < graphWidth; x += 50) {
    line(startX + x, startY, startX + x, startY + graphHeight);
  }
  for (int y = 0; y < graphHeight; y += 50) {
    line(startX, startY + y, startX + graphWidth, startY + y);
  }
  
  // Calculate local min/max for values currently in view
  float localMin = 1023;
  float localMax = 0;
  int visibleCount = 0;
  
  for (int i = 0; i < graphWidth; i++) {
    int dataPos = (dataIndex - graphWidth + i + BUFFER_SIZE) % BUFFER_SIZE;
    if (dataPos < 0) dataPos += BUFFER_SIZE;
    
    float value = rawData[dataPos];
    
    if (!Float.isNaN(value) && !Float.isInfinite(value)) {
      localMin = min(localMin, value);
      localMax = max(localMax, value);
      visibleCount++;
    }
  }
  
  // Use local range if we have enough values, otherwise use global range
  float displayMin = minValue;
  float displayMax = maxValue;
  
  if (visibleCount > graphWidth / 3) {  // Only use local range if we have enough valid points
    // Add some margin (10% of range) to prevent traces touching the edges
    float margin = (localMax - localMin) * 0.1;
    if (margin < 5) margin = 5;  // Ensure at least 5 units of margin
    
    displayMin = localMin - margin;
    displayMax = localMax + margin;
    
    // Ensure we have at least some range to display
    if (displayMax - displayMin < 10) {
      float mid = (displayMax + displayMin) / 2;
      displayMin = mid - 5;
      displayMax = mid + 5;
    }
  }
  
  // Ensure safe bounds to prevent drawing outside the box
  float safeStartY = startY + 10;  // 10px from top edge
  float safeEndY = startY + graphHeight - 10;  // 10px from bottom edge
  
  // Draw ECG trace
  stroke(GRAPH_COLOR);
  strokeWeight(2);
  noFill();
  
  boolean firstPoint = true;
  for (int i = 0; i < graphWidth; i++) {
    int dataPos = (dataIndex - graphWidth + i + BUFFER_SIZE) % BUFFER_SIZE;
    if (dataPos < 0) dataPos += BUFFER_SIZE;
    
    float value = rawData[dataPos];
    
    // Skip invalid values
    if (Float.isNaN(value) || Float.isInfinite(value)) {
      // If we encounter an invalid value, end the current shape and start a new one
      if (!firstPoint) endShape();
      firstPoint = true;
      continue;
    }
    
    // Map to graph coordinates with safe bounds
    float normalizedValue = map(value, displayMin, displayMax, safeEndY, safeStartY);
    normalizedValue = constrain(normalizedValue, safeStartY, safeEndY);
    
    if (firstPoint) {
      beginShape();
      firstPoint = false;
    }
    vertex(startX + i, normalizedValue);
  }
  if (!firstPoint) endShape();
  
  // Reset stroke weight
  strokeWeight(1);
  
  // Draw axis labels
  fill(TEXT_COLOR);
  text("Raw ECG Signal", startX, startY - 15);
  text("Time", startX + graphWidth/2, startY + graphHeight + 15);
  
  // Show scale (display the actual range shown in the view)
  text(nf(displayMax, 0, 0), startX - 35, safeStartY);
  text(nf(displayMin, 0, 0), startX - 35, safeEndY);
}

void drawFilteredGraph() {
  int graphWidth = width - SIDEBAR_WIDTH - (2 * PADDING);
  int graphHeight = GRAPH_HEIGHT / 2;
  int startX = PADDING;
  int startY = PADDING * 2 + GRAPH_HEIGHT;
  
  // Draw graph background and border
  fill(15, 15, 30);
  stroke(50, 50, 70);
  rect(startX, startY, graphWidth, graphHeight);
  
  // Draw grid
  stroke(40, 40, 60);
  for (int x = 0; x < graphWidth; x += 50) {
    line(startX + x, startY, startX + x, startY + graphHeight);
  }
  for (int y = 0; y < graphHeight; y += 50) {
    line(startX, startY + y, startX + graphWidth, startY + y);
  }
  
  // Calculate local min/max for values currently in view
  float localMin = 1023;
  float localMax = 0;
  int visibleCount = 0;
  
  for (int i = 0; i < graphWidth; i++) {
    int dataPos = (dataIndex - graphWidth + i + BUFFER_SIZE) % BUFFER_SIZE;
    if (dataPos < 0) dataPos += BUFFER_SIZE;
    
    float value = filteredData[dataPos];
    
    if (!Float.isNaN(value) && !Float.isInfinite(value)) {
      localMin = min(localMin, value);
      localMax = max(localMax, value);
      visibleCount++;
    }
  }
  
  // Use local range if we have enough values, otherwise use global range
  float displayMin = minValue;
  float displayMax = maxValue;
  
  if (visibleCount > graphWidth / 3) {  // Only use local range if we have enough valid points
    // Add some margin (10% of range) to prevent traces touching the edges
    float margin = (localMax - localMin) * 0.1;
    if (margin < 5) margin = 5;  // Ensure at least 5 units of margin
    
    displayMin = localMin - margin;
    displayMax = localMax + margin;
    
    // Ensure we have at least some range to display
    if (displayMax - displayMin < 10) {
      float mid = (displayMax + displayMin) / 2;
      displayMin = mid - 5;
      displayMax = mid + 5;
    }
  }
  
  // Ensure safe bounds to prevent drawing outside the box
  float safeStartY = startY + 10;  // 10px from top edge
  float safeEndY = startY + graphHeight - 10;  // 10px from bottom edge
  
  // Draw filtered ECG trace
  stroke(FILTERED_COLOR);
  strokeWeight(2);
  noFill();
  
  boolean firstPoint = true;
  for (int i = 0; i < graphWidth; i++) {
    int dataPos = (dataIndex - graphWidth + i + BUFFER_SIZE) % BUFFER_SIZE;
    if (dataPos < 0) dataPos += BUFFER_SIZE;
    
    float value = filteredData[dataPos];
    
    // Skip invalid values
    if (Float.isNaN(value) || Float.isInfinite(value)) {
      // If we encounter an invalid value, end the current shape and start a new one
      if (!firstPoint) endShape();
      firstPoint = true;
      continue;
    }
    
    // Map to graph coordinates with safe bounds
    float normalizedValue = map(value, displayMin, displayMax, safeEndY, safeStartY);
    normalizedValue = constrain(normalizedValue, safeStartY, safeEndY);
    
    if (firstPoint) {
      beginShape();
      firstPoint = false;
    }
    vertex(startX + i, normalizedValue);
  }
  if (!firstPoint) endShape();
  
  // Reset stroke weight
  strokeWeight(1);
  
  // Draw axis labels
  fill(TEXT_COLOR);
  text("Filtered ECG Signal", startX, startY - 15);
  
  // Show scale (display the actual range shown in the view)
  text(nf(displayMax, 0, 0), startX - 35, safeStartY);
  text(nf(displayMin, 0, 0), startX - 35, safeEndY);
}

void drawDebugInfo() {
  // Draw debug panel at the bottom
  fill(0, 0, 0, 180);
  rect(0, height - 120, width - SIDEBAR_WIDTH, 120);
  
  fill(255, 255, 0);
  textAlign(LEFT, TOP);
  
  // Count valid vs invalid samples
  int validRaw = 0;
  int validFiltered = 0;
  int totalSamples = min(dataIndex, BUFFER_SIZE);
  
  for (int i = 0; i < totalSamples; i++) {
    if (!Float.isNaN(rawData[i]) && !Float.isInfinite(rawData[i])) validRaw++;
    if (!Float.isNaN(filteredData[i]) && !Float.isInfinite(filteredData[i])) validFiltered++;
  }
  
  text("Debug Info:", 10, height - 115);
  text("Total samples: " + totalSamples, 10, height - 95);
  text("Valid raw samples: " + validRaw + " (" + nf(100.0 * validRaw / max(1, totalSamples), 0, 1) + "%)", 10, height - 75);
  text("Valid filtered samples: " + validFiltered + " (" + nf(100.0 * validFiltered / max(1, totalSamples), 0, 1) + "%)", 10, height - 55);
  text("Last 5 values - Raw: ", 10, height - 35);
  
  // Show last 5 raw and filtered values
  String rawValues = "";
  String filteredValues = "";
  
  for (int i = 0; i < 5; i++) {
    int idx = (dataIndex - i - 1 + BUFFER_SIZE) % BUFFER_SIZE;
    if (idx >= 0) {
      rawValues += nf(rawData[idx], 0, 1) + ", ";
      filteredValues += nf(filteredData[idx], 0, 1) + ", ";
    }
  }
  
  text(rawValues, 150, height - 35);
  text("Filtered: " + filteredValues, 350, height - 35);
  
  // Reset text alignment
  textAlign(LEFT, CENTER);
}

void serialEvent(Serial myPort) {
  try {
    // Read the serial data
    String inString = myPort.readStringUntil('\n');
    
    if (inString != null) {
      inString = trim(inString);
      
      // Check if this is a leads disconnected message
      if (inString.equals("!")) {
        leadsConnected = false;
        leadsDisconnectedCount++;
        return;
      } 
      // Check if this is a diagnostic message
      else if (inString.startsWith("#RANGE:")) {
        // Parse min and max values from Arduino
        String[] parts = split(inString.substring(7), ',');
        if (parts.length == 2) {
          float newMin = float(parts[0]);
          float newMax = float(parts[1]);
          
          // Update min/max with slow adaptation
          minValue = min(minValue, newMin);
          maxValue = max(maxValue, newMax);
          
          // Gradually adjust threshold for R peak detection
          threshold = minValue + (maxValue - minValue) * 0.7;
        }
        return;
      }
      
      // This is regular ECG data
      leadsConnected = true;  // Reset disconnection status
      
      float value;
      try {
        value = float(inString);
      } catch (Exception e) {
        // If conversion fails, skip this sample
        return;
      }
      
      // Skip invalid inputs
      if (Float.isNaN(value) || Float.isInfinite(value)) {
        return;
      }
      
      // Store raw data
      rawData[dataIndex] = value;
      
      // For debugging purposes, print high-amplitude signals
      if (abs(value) > 500) {
        println("High signal: " + value);
      }
      
      // Apply all filters using our filter class
      float filteredValue = filters.applyAllFilters(value);
      
      // Store filtered data (ensuring it's not NaN or Infinite)
      filteredData[dataIndex] = filteredValue;
      
      // Store original if we're in raw-only mode
      if (!showRawFiltered) {
        filteredData[dataIndex] = value;  // Use raw data instead of filtered
      }
      
      // Check for R peak for heart rate calculation
      if (filteredValue > threshold && !isPeakDetected && millis() - lastPeakTime > 200) {
        // R peak detected
        long currentTime = millis();
        int rrInterval = (int)(currentTime - lastPeakTime);
        
        // Only use reasonable RR intervals (between 300ms and 1500ms)
        // This corresponds to heart rates between 40 and 200 BPM
        if (rrInterval >= 300 && rrInterval <= 1500) {
          // Store this valid RR interval
          lastValidRRInterval = rrInterval;
          rrIntervals[rrIndex] = rrInterval;
          rrIndex = (rrIndex + 1) % rrIntervals.length;
          
          // Calculate heart rate after we have at least 3 valid intervals (reduced from 5)
          if (peakCount >= 3) {
            int sum = 0;
            int validIntervals = 0;
            
            for (int i = 0; i < rrIntervals.length; i++) {
              if (rrIntervals[i] > 0) {
                sum += rrIntervals[i];
                validIntervals++;
              }
            }
            
            if (validIntervals > 0) {
              float avgInterval = sum / (float)validIntervals;
              // Calculate new heart rate
              int newHeartRate = int(60000.0 / avgInterval);
              
              // Sanity check on heart rate
              if (newHeartRate >= 40 && newHeartRate <= 200) {
                // Apply weighted average to smooth transitions but respond quickly to changes
                // Use 70% of new reading and 30% of previous reading for smoother transition
                if (heartRate > 0) {
                  heartRate = int(0.3 * heartRate + 0.7 * newHeartRate);
                } else {
                  heartRate = newHeartRate;
                }
                
                // Debug output for heart rate updates
                if (showDebugInfo) {
                  println("Heart rate updated: " + heartRate + " BPM (from interval: " + avgInterval + "ms)");
                }
              }
            }
          } else {
            // For the first few beats, provide a preliminary heart rate based on the most recent interval
            if (lastValidRRInterval > 0) {
              heartRate = int(60000.0 / lastValidRRInterval);
            }
          }
          
          peakCount++;
        }
        
        lastPeakTime = currentTime;
        isPeakDetected = true;
      } 
      else if (filteredValue < threshold * 0.7) {
        // Reset peak detection when value drops significantly below threshold
        isPeakDetected = false;
      }
      
      // Update dynamic scaling (with smoothing)
      if (dataIndex % 100 == 0) {
        // Find min and max in recent data
        float recentMin = 1023;
        float recentMax = 0;
        int checkSamples = min(500, dataIndex + 1);
        int validSamples = 0;
        
        for (int i = 0; i < checkSamples; i++) {
          int idx = (dataIndex - i + BUFFER_SIZE) % BUFFER_SIZE;
          float val = rawData[idx];
          
          // Only use valid values for scaling
          if (!Float.isNaN(val) && !Float.isInfinite(val)) {
            recentMin = min(recentMin, val);
            recentMax = max(recentMax, val);
            validSamples++;
          }
        }
        
        // Only adjust scaling if we have enough valid samples
        if (validSamples > 50) {
          // Adjust scaling with smoothing
          minValue = minValue * 0.9 + recentMin * 0.1;
          maxValue = maxValue * 0.9 + recentMax * 0.1;
          
          // Ensure there's always some range to prevent division by zero
          if (maxValue - minValue < 10) {
            maxValue = minValue + 10;
          }
        }
      }
      
      // Move to next position in the buffer
      dataIndex = (dataIndex + 1) % BUFFER_SIZE;
    }
  } catch (Exception e) {
    println("Error processing serial data: " + e.getMessage());
  }
}

void keyPressed() {
  if (key == 'r' || key == 'R') {
    // Reset all data
    for (int i = 0; i < BUFFER_SIZE; i++) {
      rawData[i] = 0;
      filteredData[i] = 0;
    }
    dataIndex = 0;
    heartRate = 0;
    peakCount = 0;
    minValue = 0;
    maxValue = 1023;
    
    // Reset filters
    filters.reset();
    
    for (int i = 0; i < rrIntervals.length; i++) {
      rrIntervals[i] = 0;
    }
    
    println("Data reset");
  } else if (key == 's' || key == 'S') {
    // Save current data to a file
    saveData();
  } else if (key == 'p' || key == 'P') {
    // Save screenshot of ECG
    saveECGImage();
  } else if (key == 'd' || key == 'D') {
    // Toggle debug info
    showDebugInfo = !showDebugInfo;
  } else if (key == 'f' || key == 'F') {
    // Toggle adaptive filtering mode
    filters.toggleAdaptiveMode();
    println("Adaptive filtering mode toggled");
  } else if (key == 't' || key == 'T') {
    // Toggle between showing raw+filtered or just raw data
    showRawFiltered = !showRawFiltered;
    println("Showing " + (showRawFiltered ? "raw and filtered" : "raw data only"));
  } else if (key == ' ') {  // Space bar
    // Toggle full screen mode
    toggleFullScreen();
  }
}

void saveData() {
  String[] dataLines = new String[BUFFER_SIZE + 1];
  
  // Header
  dataLines[0] = "Raw,Filtered";
  
  // Data
  for (int i = 0; i < BUFFER_SIZE; i++) {
    int idx = (dataIndex + i) % BUFFER_SIZE;
    dataLines[i + 1] = nf(rawData[idx], 0, 2) + "," + nf(filteredData[idx], 0, 2);
  }
  
  // Generate filename with timestamp
  String timestamp = year() + nf(month(), 2) + nf(day(), 2) + "_" + 
                     nf(hour(), 2) + nf(minute(), 2) + nf(second(), 2);
  String filename = "ecg_data_" + timestamp + ".csv";
  
  // Save the file
  saveStrings(filename, dataLines);
  println("Data saved to: " + filename);
}

void saveECGImage() {
  // Render the current view to the canvas
  ecgCanvas.beginDraw();
  ecgCanvas.background(BG_COLOR);
  
  // Need to redraw everything to the canvas
  // Copy sidebar
  ecgCanvas.fill(20, 20, 40);
  ecgCanvas.noStroke();
  ecgCanvas.rect(width - SIDEBAR_WIDTH, 0, SIDEBAR_WIDTH, height);
  
  // Draw title
  ecgCanvas.fill(TEXT_COLOR);
  ecgCanvas.textSize(24);
  ecgCanvas.textAlign(LEFT, CENTER);
  ecgCanvas.text("ProECG Monitor", width - SIDEBAR_WIDTH + 20, 40);
  
  // Add timestamp
  String dateTime = year() + "/" + nf(month(), 2) + "/" + nf(day(), 2) + " " + 
                     nf(hour(), 2) + ":" + nf(minute(), 2) + ":" + nf(second(), 2);
  ecgCanvas.textSize(14);
  ecgCanvas.text("Captured: " + dateTime, width - SIDEBAR_WIDTH + 20, 70);
  
  // Add heart rate
  if (heartRate > 0) {
    ecgCanvas.textSize(48);
    ecgCanvas.fill(GRAPH_COLOR);
    ecgCanvas.text(heartRate + " BPM", width - SIDEBAR_WIDTH + 20, 150);
  }
  
  // Draw main ECG graph on canvas
  drawGraphToCanvas(ecgCanvas, rawData, GRAPH_COLOR, PADDING, PADDING, GRAPH_HEIGHT, "Raw ECG Signal");
  
  // Draw filtered ECG graph on canvas
  drawGraphToCanvas(ecgCanvas, filteredData, FILTERED_COLOR, PADDING, PADDING * 2 + GRAPH_HEIGHT, GRAPH_HEIGHT / 2, "Filtered ECG Signal");
  
  ecgCanvas.endDraw();
  
  // Generate filename with timestamp
  String captureTimestamp = year() + nf(month(), 2) + nf(day(), 2) + "_" + 
                     nf(hour(), 2) + nf(minute(), 2) + nf(second(), 2);
  String filename = "ecg_image_" + captureTimestamp + ".png";
  
  // Save the canvas as an image
  ecgCanvas.save(filename);
  println("Screenshot saved to: " + filename);
}

void drawGraphToCanvas(PGraphics canvas, float[] data, color graphColor, int startX, int startY, int graphHeight, String label) {
  int graphWidth = width - SIDEBAR_WIDTH - (2 * PADDING);
  
  // Draw graph background and border
  canvas.fill(15, 15, 30);
  canvas.stroke(50, 50, 70);
  canvas.rect(startX, startY, graphWidth, graphHeight);
  
  // Draw grid
  canvas.stroke(40, 40, 60);
  for (int x = 0; x < graphWidth; x += 50) {
    canvas.line(startX + x, startY, startX + x, startY + graphHeight);
  }
  for (int y = 0; y < graphHeight; y += 50) {
    canvas.line(startX, startY + y, startX + graphWidth, startY + y);
  }
  
  // Calculate local min/max for values currently in view
  float localMin = 1023;
  float localMax = 0;
  int visibleCount = 0;
  
  for (int i = 0; i < graphWidth; i++) {
    int dataPos = (dataIndex - graphWidth + i + BUFFER_SIZE) % BUFFER_SIZE;
    if (dataPos < 0) dataPos += BUFFER_SIZE;
    
    float value = data[dataPos];
    
    if (!Float.isNaN(value) && !Float.isInfinite(value)) {
      localMin = min(localMin, value);
      localMax = max(localMax, value);
      visibleCount++;
    }
  }
  
  // Use local range if we have enough values, otherwise use global range
  float displayMin = minValue;
  float displayMax = maxValue;
  
  if (visibleCount > graphWidth / 3) {  // Only use local range if we have enough valid points
    // Add some margin (10% of range) to prevent traces touching the edges
    float margin = (localMax - localMin) * 0.1;
    if (margin < 5) margin = 5;  // Ensure at least 5 units of margin
    
    displayMin = localMin - margin;
    displayMax = localMax + margin;
    
    // Ensure we have at least some range to display
    if (displayMax - displayMin < 10) {
      float mid = (displayMax + displayMin) / 2;
      displayMin = mid - 5;
      displayMax = mid + 5;
    }
  }
  
  // Ensure safe bounds to prevent drawing outside the box
  float safeStartY = startY + 10;  // 10px from top edge
  float safeEndY = startY + graphHeight - 10;  // 10px from bottom edge
  
  // Draw ECG trace
  canvas.stroke(graphColor);
  canvas.strokeWeight(2);
  canvas.noFill();
  
  canvas.beginShape();
  boolean firstValidPoint = true;
  
  for (int i = 0; i < graphWidth; i++) {
    int dataPos = (dataIndex - graphWidth + i + BUFFER_SIZE) % BUFFER_SIZE;
    if (dataPos < 0) dataPos += BUFFER_SIZE;
    
    float value = data[dataPos];
    
    // Skip invalid values
    if (Float.isNaN(value) || Float.isInfinite(value)) {
      if (!firstValidPoint) {
        canvas.endShape();
        firstValidPoint = true;
      }
      continue;
    }
    
    // Map to graph coordinates with safe bounds
    float normalizedValue = map(value, displayMin, displayMax, safeEndY, safeStartY);
    normalizedValue = constrain(normalizedValue, safeStartY, safeEndY);
    
    if (firstValidPoint) {
      canvas.beginShape();
      firstValidPoint = false;
    }
    canvas.vertex(startX + i, normalizedValue);
  }
  if (!firstValidPoint) canvas.endShape();
  
  // Reset stroke weight
  canvas.strokeWeight(1);
  
  // Draw axis labels
  canvas.fill(TEXT_COLOR);
  canvas.text(label, startX, startY - 15);
  
  // Show scale
  canvas.text(nf(displayMax, 0, 0), startX - 35, safeStartY);
  canvas.text(nf(displayMin, 0, 0), startX - 35, safeEndY);
}

// New function to toggle full screen mode
void toggleFullScreen() {
  isFullScreen = !isFullScreen;
  
  if (isFullScreen) {
    // Save window position before going full screen (if needed later)
    surface.setSize(displayWidth, displayHeight);
    surface.setLocation(0, 0);
    println("Entered full screen mode");
  } else {
    // Return to windowed mode with original dimensions
    surface.setSize(DISPLAY_WIDTH, DISPLAY_HEIGHT);
    // Center the window
    surface.setLocation(
      (displayWidth - DISPLAY_WIDTH) / 2,
      (displayHeight - DISPLAY_HEIGHT) / 2
    );
    println("Exited full screen mode");
  }
  
  // Create new canvas with current dimensions for screenshots
  ecgCanvas = createGraphics(width, height);
}

// Override built-in keyPressed for ESC key (to prevent it from exiting the application)
void keyReleased() {
  if (key == ESC && isFullScreen) {
    key = 0;  // Consume the ESC key - prevent exit
    toggleFullScreen();  // Switch back to windowed mode
  }
}
