from flask import Flask, render_template, request, jsonify
import serial
import serial.tools.list_ports
import time
import threading
import json
import numpy as np
from collections import deque

app = Flask(__name__)

# Global variables
serial_connection = None
ecg_data = []
is_monitoring = False
max_data_points = 100  # Limit data points to reduce memory usage
lock = threading.Lock()
# Heart rate calculation variables
heart_rate = 0
last_peaks = deque(maxlen=10)  # Store last 10 peak timestamps
peak_values = deque(maxlen=30)  # Store recent peak values for adaptive thresholding

def get_available_ports():
    """Return a list of available serial ports"""
    ports = serial.tools.list_ports.comports()
    return [port.device for port in ports]

def detect_peaks_and_calculate_hr(new_value, timestamp):
    """
    Detect peaks in noisy ECG data and calculate heart rate
    Using adaptive thresholding for noisy data
    """
    global heart_rate, last_peaks, peak_values, ecg_data
    
    if len(ecg_data) < 10:  # Need some data for initial analysis
        return
    
    # Calculate the dynamic threshold based on recent data
    # For noisy data, we use a more sophisticated threshold calculation
    recent_data = ecg_data[-20:] if len(ecg_data) >= 20 else ecg_data
    mean_val = np.mean(recent_data)
    std_val = np.std(recent_data)
    
    # Adaptive threshold - higher for noisy data (2-3 standard deviations above mean)
    threshold = mean_val + 2.5 * std_val
    
    # Minimum value difference to qualify as a real peak (noise rejection)
    min_peak_height = std_val * 1.5
    
    # Check if the new value might be a peak
    if len(ecg_data) >= 3:
        # Simple peak detection (middle value higher than neighbors)
        if ecg_data[-2] > ecg_data[-3] and ecg_data[-2] > ecg_data[-1] and ecg_data[-2] > threshold:
            # Confirm it's significantly higher than the baseline (noise rejection)
            if ecg_data[-2] - mean_val > min_peak_height:
                # This appears to be a real R peak
                peak_values.append(ecg_data[-2])
                last_peaks.append(timestamp - 0.01)  # Adjust timestamp to when the peak actually occurred
                
                # Calculate heart rate only if we have at least 2 peaks
                if len(last_peaks) >= 2:
                    # Calculate time differences between peaks
                    peak_intervals = []
                    for i in range(1, len(last_peaks)):
                        interval = last_peaks[i] - last_peaks[i-1]
                        # Only use reasonable intervals (between 0.3 and 2.0 seconds)
                        # This corresponds to 30-200 BPM, filtering out noise
                        if 0.3 <= interval <= 2.0:
                            peak_intervals.append(interval)
                    
                    if peak_intervals:
                        # Calculate average interval and convert to BPM
                        avg_interval = np.mean(peak_intervals)
                        current_hr = int(60 / avg_interval)
                        
                        # Sanity check - heart rate should be between 30 and 200 BPM
                        if 30 <= current_hr <= 200:
                            heart_rate = current_hr
    
    return heart_rate

def read_serial_data():
    """Read data from serial port in a separate thread"""
    global ecg_data, is_monitoring, serial_connection, heart_rate
    start_time = time.time()
    
    while is_monitoring and serial_connection:
        try:
            if serial_connection.in_waiting > 0:
                line = serial_connection.readline().decode('utf-8').strip()
                try:
                    value = float(line)
                    current_time = time.time()
                    
                    with lock:
                        ecg_data.append(value)
                        # Keep only the last max_data_points
                        if len(ecg_data) > max_data_points:
                            ecg_data = ecg_data[-max_data_points:]
                        
                        # Calculate heart rate from ECG peaks
                        detect_peaks_and_calculate_hr(value, current_time)
                except ValueError:
                    # Skip lines that can't be converted to float
                    pass
            time.sleep(0.01)  # Short sleep to prevent CPU overuse
        except Exception as e:
            print(f"Error reading serial data: {e}")
            is_monitoring = False
            break

@app.route('/')
def index():
    """Render the main page"""
    ports = get_available_ports()
    baud_rates = [9600, 19200, 38400, 57600, 115200]
    return render_template('index.html', ports=ports, baud_rates=baud_rates)

@app.route('/connect', methods=['POST'])
def connect():
    """Connect to the selected serial port"""
    global serial_connection, is_monitoring, ecg_data
    
    port = request.form.get('port')
    baud_rate = int(request.form.get('baud_rate', 9600))
    
    # Close existing connection if any
    if serial_connection and serial_connection.is_open:
        is_monitoring = False
        time.sleep(0.2)  # Give time for the thread to finish
        serial_connection.close()
    
    try:
        serial_connection = serial.Serial(port, baud_rate, timeout=1)
        ecg_data = []  # Reset data
        is_monitoring = True
        
        # Start reading thread
        thread = threading.Thread(target=read_serial_data)
        thread.daemon = True
        thread.start()
        
        return jsonify({"success": True, "message": f"Connected to {port} at {baud_rate} baud"})
    except Exception as e:
        return jsonify({"success": False, "message": f"Failed to connect: {str(e)}"})

@app.route('/disconnect', methods=['POST'])
def disconnect():
    """Disconnect from the serial port"""
    global serial_connection, is_monitoring
    
    if serial_connection and serial_connection.is_open:
        is_monitoring = False
        time.sleep(0.2)  # Give time for the thread to finish
        serial_connection.close()
        serial_connection = None
        return jsonify({"success": True, "message": "Disconnected"})
    return jsonify({"success": False, "message": "No active connection"})

@app.route('/get_data')
def get_data():
    """Return the current ECG data"""
    with lock:
        data_to_send = list(ecg_data)
    return jsonify(data_to_send)

@app.route('/get_heart_rate')
def get_heart_rate():
    """Return the current heart rate"""
    global heart_rate
    return jsonify({"heart_rate": heart_rate})

@app.route('/refresh_ports')
def refresh_ports():
    """Refresh the list of available serial ports"""
    ports = get_available_ports()
    return jsonify(ports)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001, debug=True, threaded=True)
