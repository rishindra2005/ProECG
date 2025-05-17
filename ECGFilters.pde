// ECGFilters.pde - Advanced filtering implementations for ECG signals
// Contains various filters with dynamic parameter adjustment

class ECGFilters {
  // Low-Pass Filter variables
  private float alpha = 0.3;  // Increased smoothing factor to preserve more signal
  private float lastFilteredValue = 0.0;
  
  // Notch Filter variables
  private float notchFreq = 60.0;  // Notch frequency (Hz)
  private float samplingRate = 100.0;  // Sampling rate (Hz)
  private float Q = 15.0;  // Reduced Q factor (wider band) to be less aggressive
  private float[] notchCoeffs = new float[5];
  private float[] notchHistory = new float[4];  // History buffer
  
  // Bandpass Filter variables
  private float lowCutoff = 0.2;  // Lower cutoff frequency (Hz) - allow more low frequencies
  private float highCutoff = 45.0; // Higher cutoff frequency (Hz) - allow more high frequencies
  private float[] bandpassCoeffs = new float[5];
  private float[] bandpassHistory = new float[4];
  
  // Statistical tracking for dynamic adjustment
  private float[] recentValues;
  private int valueIndex = 0;
  private int sampleCount = 0;
  private float runningMean = 0.0;
  private float runningVariance = 0.0;
  private float noiseEstimate = 0.0;
  private float signalQuality = 1.0;  // 0 to 1 scale, 1 being best
  private boolean adaptiveMode = true;
  
  // Signal preservation settings
  private float signalThreshold = 100.0;  // Threshold to identify meaningful signals
  private float preservationFactor = 0.8;  // How much of high-amplitude signals to preserve
  
  // Constructor
  public ECGFilters(int historyLength) {
    // Initialize filters
    setupNotchFilter();
    setupBandpassFilter();
    
    // Initialize history buffer for statistics
    recentValues = new float[historyLength];
    for (int i = 0; i < historyLength; i++) {
      recentValues[i] = 0.0;
    }
  }
  
  // Initialize notch filter coefficients
  public void setupNotchFilter() {
    float w0 = 2.0 * PI * notchFreq / samplingRate;
    float bw = w0 / Q;
    float alpha = sin(bw) / 2.0;
    
    // Calculate filter coefficients
    notchCoeffs[0] = 1.0 / (1.0 + alpha);  // b0
    notchCoeffs[1] = -2.0 * cos(w0) / (1.0 + alpha);  // b1
    notchCoeffs[2] = 1.0 / (1.0 + alpha);  // b2
    notchCoeffs[3] = 2.0 * cos(w0) / (1.0 + alpha);  // a1
    notchCoeffs[4] = (1.0 - alpha) / (1.0 + alpha);  // a2
  }
  
  // Initialize bandpass filter coefficients
  public void setupBandpassFilter() {
    // Calculate normalized frequencies
    float wl = 2.0 * PI * lowCutoff / samplingRate;
    float wh = 2.0 * PI * highCutoff / samplingRate;
    
    // Calculate coefficients for a simple bandpass filter
    float K = tan(PI * (highCutoff - lowCutoff) / samplingRate);
    float norm = 1.0 / (1.0 + K / Q + K * K);
    
    bandpassCoeffs[0] = K / Q * norm;  // b0
    bandpassCoeffs[1] = 0;  // b1
    bandpassCoeffs[2] = -K / Q * norm;  // b2
    bandpassCoeffs[3] = 2.0 * (K * K - 1.0) * norm;  // a1
    bandpassCoeffs[4] = (1.0 - K / Q + K * K) * norm;  // a2
  }
  
  // Apply a low-pass filter to the input value
  public float applyLowPassFilter(float input) {
    // Skip processing if input is invalid
    if (Float.isNaN(input) || Float.isInfinite(input)) {
      return lastFilteredValue;
    }
    
    // Preserve high-amplitude signals that likely represent actual ECG features
    float localAlpha = alpha;
    if (abs(input - lastFilteredValue) > signalThreshold) {
      // Reduce filtering for significant changes (likely R peaks)
      localAlpha = alpha + (1.0 - alpha) * preservationFactor;
    }
    
    // Dynamic alpha adjustment based on signal quality and noise estimate
    if (adaptiveMode && sampleCount > 50) {
      // Adjust alpha based on noise level - more noise = more smoothing
      // But keep a higher minimum to avoid over-filtering
      localAlpha = constrain(0.2 + (1.0 - signalQuality) * 0.2, 0.2, 0.8);
    }
    
    // Apply low-pass filter
    float output = localAlpha * input + (1.0 - localAlpha) * lastFilteredValue;
    
    // Store last value and return filtered value
    lastFilteredValue = output;
    return output;
  }
  
  // Apply a notch filter to remove power line interference
  public float applyNotchFilter(float input) {
    // Skip processing if input is invalid
    if (Float.isNaN(input) || Float.isInfinite(input)) {
      return input;
    }
    
    // Apply notch filter (direct form II)
    float w = input - notchCoeffs[3] * notchHistory[0] - notchCoeffs[4] * notchHistory[1];
    float output = notchCoeffs[0] * w + notchCoeffs[1] * notchHistory[2] + notchCoeffs[2] * notchHistory[3];
    
    // Blend with original signal to preserve important features
    float blendFactor = 0.2;  // How much of original signal to keep
    if (abs(input) > signalThreshold) {
      // For high-amplitude signals, preserve more of the original
      blendFactor = 0.5;
    }
    output = output * (1.0 - blendFactor) + input * blendFactor;
    
    // Update filter history
    notchHistory[1] = notchHistory[0];
    notchHistory[0] = w;
    notchHistory[3] = notchHistory[2];
    notchHistory[2] = w;
    
    return output;
  }
  
  // Apply a bandpass filter
  public float applyBandpassFilter(float input) {
    // Skip processing if input is invalid
    if (Float.isNaN(input) || Float.isInfinite(input)) {
      return input;
    }
    
    // Apply bandpass filter (direct form II)
    float w = input - bandpassCoeffs[3] * bandpassHistory[0] - bandpassCoeffs[4] * bandpassHistory[1];
    float output = bandpassCoeffs[0] * w + bandpassCoeffs[1] * bandpassHistory[2] + bandpassCoeffs[2] * bandpassHistory[3];
    
    // Blend with original signal to preserve important features
    float blendFactor = 0.2;  // How much of original signal to keep
    if (abs(input) > signalThreshold) {
      // For high-amplitude signals, preserve more of the original
      blendFactor = 0.5;
    }
    output = output * (1.0 - blendFactor) + input * blendFactor;
    
    // Update filter history
    bandpassHistory[1] = bandpassHistory[0];
    bandpassHistory[0] = w;
    bandpassHistory[3] = bandpassHistory[2];
    bandpassHistory[2] = w;
    
    return output;
  }
  
  // Apply multiple filters in sequence
  public float applyAllFilters(float input) {
    // Skip processing if input is invalid
    if (Float.isNaN(input) || Float.isInfinite(input)) {
      return 0.0;  // Return neutral value instead of NaN
    }
    
    // Update signal statistics
    updateStatistics(input);
    
    // Special case for very high signal values - preserve more of the original
    if (abs(input) > signalThreshold * 2) {
      // For very strong signals (like R peaks), minimal filtering
      float minimallyFiltered = applyNotchFilter(input);
      return minimallyFiltered * 0.8 + input * 0.2;
    }
    
    // Apply filters in sequence with reduced intensity
    float notchedValue = applyNotchFilter(input);
    float bandpassValue = applyBandpassFilter(notchedValue);
    float lowpassValue = applyLowPassFilter(bandpassValue);
    
    // Mix in some of the original signal to preserve waveform features
    return lowpassValue * 0.8 + input * 0.2;
  }
  
  // Update signal statistics for dynamic adjustment
  private void updateStatistics(float input) {
    // Store new value in circular buffer
    recentValues[valueIndex] = input;
    valueIndex = (valueIndex + 1) % recentValues.length;
    sampleCount++;
    
    // After collecting enough samples, update statistics
    if (sampleCount % 50 == 0) {
      // Calculate mean and variance using one-pass algorithm
      float mean = 0.0;
      float M2 = 0.0;
      int n = 0;
      
      // Calculate mean and variance for valid values only
      for (int i = 0; i < recentValues.length; i++) {
        float x = recentValues[i];
        if (!Float.isNaN(x) && !Float.isInfinite(x)) {
          n++;
          float delta = x - mean;
          mean += delta / n;
          float delta2 = x - mean;
          M2 += delta * delta2;
        }
      }
      
      // Calculate variance and standard deviation
      float variance = (n > 1) ? M2 / (n - 1) : 0.0;
      float stdDev = sqrt(variance);
      
      // Update running statistics with smoothing
      runningMean = runningMean * 0.9 + mean * 0.1;
      runningVariance = runningVariance * 0.9 + variance * 0.1;
      
      // Estimate noise level and signal quality
      if (n > 0) {
        // Calculate coefficient of variation as noise estimate
        noiseEstimate = sqrt(runningVariance) / abs(runningMean + 0.1);
        
        // Estimate signal quality (inversely proportional to noise)
        signalQuality = constrain(1.0 / (1.0 + noiseEstimate * 2.0), 0.1, 1.0);
        
        // Update signal threshold based on variance
        signalThreshold = stdDev * 1.5;
        
        // Adjust filter parameters based on signal quality
        adjustFilterParameters();
      }
    }
  }
  
  // Dynamically adjust filter parameters based on signal quality
  private void adjustFilterParameters() {
    if (!adaptiveMode) return;
    
    // Adjust notch filter Q factor based on signal quality
    // Lower quality signal = wider notch to ensure noise removal
    float newQ = 10.0 + signalQuality * 15.0;  // Q range: 10 to 25 (less aggressive)
    if (abs(Q - newQ) > 2.0) {
      Q = newQ;
      setupNotchFilter();
    }
    
    // Adjust bandpass filter cutoffs based on signal quality
    // For noisy signals, narrow the band to focus on core ECG frequencies
    float qualityFactor = map(signalQuality, 0.1, 1.0, 0.7, 1.0);  // Less aggressive range
    float newLowCutoff = 0.2 / qualityFactor;  // Increase low cutoff when noisy, but keep more low freqs
    float newHighCutoff = 45.0 * qualityFactor;  // Decrease high cutoff when noisy, but keep more high freqs
    
    if (abs(lowCutoff - newLowCutoff) > 0.1 || abs(highCutoff - newHighCutoff) > 1.0) {
      lowCutoff = newLowCutoff;
      highCutoff = newHighCutoff;
      setupBandpassFilter();
    }
    
    // Adjust preservation factor based on signal quality
    preservationFactor = constrain(0.5 + signalQuality * 0.3, 0.5, 0.8);
  }
  
  // Get current filter parameters for display
  public String getFilterInfo() {
    return "Filters: LPF(α=" + nf(alpha, 0, 2) + 
           "), Notch(" + int(notchFreq) + "Hz, Q=" + nf(Q, 0, 1) + ")" +
           ", BP(" + nf(lowCutoff, 0, 1) + "-" + nf(highCutoff, 0, 1) + "Hz)" +
           "\nSignal Quality: " + nf(signalQuality * 100, 0, 1) + "%" +
           "\nSignal Threshold: " + nf(signalThreshold, 0, 1);
  }
  
  // Toggle adaptive mode
  public void toggleAdaptiveMode() {
    adaptiveMode = !adaptiveMode;
  }
  
  // Reset all filters
  public void reset() {
    // Reset filter states
    lastFilteredValue = 0.0;
    
    for (int i = 0; i < notchHistory.length; i++) {
      notchHistory[i] = 0.0;
    }
    
    for (int i = 0; i < bandpassHistory.length; i++) {
      bandpassHistory[i] = 0.0;
    }
    
    // Reset statistical values
    valueIndex = 0;
    runningMean = 0.0;
    runningVariance = 0.0;
    noiseEstimate = 0.0;
    signalQuality = 1.0;
    
    // Reset history buffer
    for (int i = 0; i < recentValues.length; i++) {
      recentValues[i] = 0.0;
    }
    
    // Reset filter parameters to defaults (less aggressive values)
    alpha = 0.3;
    Q = 15.0;
    lowCutoff = 0.2;
    highCutoff = 45.0;
    signalThreshold = 100.0;
    preservationFactor = 0.8;
    
    // Recalculate filter coefficients
    setupNotchFilter();
    setupBandpassFilter();
  }
} 