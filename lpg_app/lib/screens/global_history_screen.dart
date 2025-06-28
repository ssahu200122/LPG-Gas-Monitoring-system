// lib/screens/global_history_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart'; // For accessing current user UID

import 'package:lpg_app/services/firestore_service.dart'; // Corrected import
import 'package:lpg_app/models/lpg_device.dart'; // Corrected import

class GlobalHistoryScreen extends StatefulWidget {
  const GlobalHistoryScreen({super.key}); // This screen does not take parameters

  @override
  State<GlobalHistoryScreen> createState() => _GlobalHistoryScreenState();
}

class _GlobalHistoryScreenState extends State<GlobalHistoryScreen> {
  late final FirestoreService _firestoreService;
  late final User? _currentUser;

  List<LPGDevice> _availableDevices = []; // List of devices for the dropdown
  LPGDevice? _selectedDevice; // Currently selected device
  List<Map<String, dynamic>> _historyData = [];
  bool _isLoading = true;
  String? _errorMessage;

  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();

  double _minWeightY = 0;
  double _maxWeightY = 0;
  double _minX = 0;
  double _maxX = 0;
  double _intervalX = 1;

  double _totalGasConsumed = 0.0;
  double _averageDailyConsumption = 0.0;
  String _daysRemaining = 'N/A';

  @override
  void initState() {
    super.initState();
    _firestoreService = Provider.of<FirestoreService>(context, listen: false);
    _currentUser = FirebaseAuth.instance.currentUser; // Get current user

    if (_currentUser == null) {
      _errorMessage = "User not logged in. Cannot fetch history.";
      _isLoading = false;
      return;
    }

    _fetchAvailableDevices(); // Start by fetching available devices
  }

  /// Fetches all devices linked to the current user and sets the initial selected device.
  Future<void> _fetchAvailableDevices() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userProfile = await _firestoreService.getUserProfile(_currentUser!.uid);
      if (userProfile != null && userProfile.containsKey('devices')) {
        final List<dynamic> deviceIds = userProfile['devices'] as List<dynamic>;
        if (deviceIds.isEmpty) {
          if (mounted) {
            setState(() {
              _availableDevices = [];
              _selectedDevice = null;
              _isLoading = false;
              _errorMessage = 'No devices linked to your account.';
            });
          }
          return;
        }

        // Fetch actual device details for each ID
        // Listen to the stream to keep availableDevices updated
        _firestoreService.streamLPGDevices(deviceIds).listen((devices) {
          if (mounted) {
            setState(() {
              _availableDevices = devices;
              // If no device is selected, or selected device no longer exists, select the first one
              if (_selectedDevice == null || !devices.any((d) => d.id == _selectedDevice!.id)) {
                _selectedDevice = devices.isNotEmpty ? devices.first : null;
              }
              // Only fetch history if a device is selected and we are not already loading
              if (_selectedDevice != null && !_isLoading) {
                 _fetchHistoryData(); // Fetch history for the (auto-)selected device
              }
              _isLoading = false; // Set loading to false once devices are fetched
            });
          }
        }, onError: (e) {
          if (mounted) {
            setState(() {
              _errorMessage = 'Failed to load devices: $e';
              _isLoading = false;
            });
          }
        });
      } else {
        if (mounted) {
          setState(() {
            _availableDevices = [];
            _selectedDevice = null;
            _isLoading = false;
            _errorMessage = 'User profile has no linked devices.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error fetching available devices: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// Fetches historical weight data for the currently selected device within a date range.
  Future<void> _fetchHistoryData() async {
    if (_selectedDevice == null) {
      setState(() {
        _historyData = [];
        _totalGasConsumed = 0.0;
        _averageDailyConsumption = 0.0;
        _daysRemaining = 'N/A';
        _errorMessage = 'No device selected to view history.';
        _isLoading = false; // Ensure loading is off if no device
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _historyData = []; // Clear previous data
    });

    try {
      final data = await _firestoreService.getDeviceHistory(
        _selectedDevice!.id, // Use selected device's ID
        _startDate,
        _endDate,
      );
      // Ensure data is sorted by timestamp ascending for chart plotting
      data.sort((a, b) {
        final Timestamp? tsA = a['timestamp'] as Timestamp?;
        final Timestamp? tsB = b['timestamp'] as Timestamp?;

        final DateTime timeA = tsA?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
        final DateTime timeB = tsB?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
        return timeA.compareTo(timeB);
      });

      if (mounted) {
        setState(() {
          _historyData = data;
          _calculateChartRanges(); // Calculate ranges for the chart
          _calculateConsumptionMetrics(); // Calculate total and average consumption
          _calculateDaysRemaining(); // Calculate days remaining
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load history for ${_selectedDevice?.name}: Invalid data found or calculation error: ${e.toString()}';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Calculates gas usage between a previous weight reading and a current weight reading.
  double _calculateGasUsage(double previousWeight, double currentWeight) {
    if (previousWeight > currentWeight) {
      return (previousWeight - currentWeight);
    }
    return 0.0;
  }

  /// Calculates the total and average daily gas consumed within the fetched history data.
  void _calculateConsumptionMetrics() {
    _totalGasConsumed = 0.0;
    if (_historyData.length < 2) {
      _averageDailyConsumption = 0.0;
      return;
    }

    for (int i = 0; i < _historyData.length - 1; i++) {
      final double currentReading = ((_historyData[i + 1]['weight_grams'] ?? 0.0) as double).clamp(0.0, double.infinity);
      final double previousReadingWeight = ((_historyData[i]['weight_grams'] ?? 0.0) as double).clamp(0.0, double.infinity);
      
      if (currentReading < previousReadingWeight) {
        _totalGasConsumed += (previousReadingWeight - currentReading);
      }
    }

    final int numberOfDays = _endDate.difference(_startDate).inDays + 1;
    if (numberOfDays > 0) {
      _averageDailyConsumption = (_totalGasConsumed / numberOfDays);
    } else {
      _averageDailyConsumption = 0.0;
    }
  }

  /// Calculates the estimated days remaining based on current gas and average daily consumption.
  void _calculateDaysRemaining() {
    if (_selectedDevice == null || _historyData.isEmpty || _averageDailyConsumption <= 0) {
      _daysRemaining = 'N/A';
      return;
    }

    final latestEntry = _historyData.last;
    final double currentWeightGrams = ((latestEntry['weight_grams'] ?? 0.0) as double).clamp(0.0, double.infinity);

    final double gasRemainingInCylinder = (currentWeightGrams - _selectedDevice!.emptyWeight).clamp(0.0, double.infinity);

    if (gasRemainingInCylinder <= 0) {
      _daysRemaining = 'Empty';
    } else {
      final double estimatedDays = gasRemainingInCylinder / _averageDailyConsumption;
      if (estimatedDays < 1.0 && estimatedDays > 0) {
        final double estimatedHours = estimatedDays * 24;
        _daysRemaining = '${estimatedHours.toStringAsFixed(0)} hrs';
      } else if (estimatedDays >= 1.0) {
        _daysRemaining = '${estimatedDays.toStringAsFixed(0)} days';
      } else {
        _daysRemaining = 'N/A';
      }
    }
  }

  /// Calculates the min/max X (time) and Y (weight) values for the chart.
  void _calculateChartRanges() {
    if (_historyData.isEmpty || _selectedDevice == null) {
      _minWeightY = ((_selectedDevice?.emptyWeight ?? 0) / 1000).clamp(0.0, double.infinity).floorToDouble();
      _maxWeightY = ((_selectedDevice?.fullWeight ?? 0) / 1000).clamp(0.0, double.infinity).ceilToDouble();
      if (_minWeightY == _maxWeightY) _maxWeightY += 1.0;
      _minX = 0;
      _maxX = 1;
      _intervalX = 1;
      return;
    }

    double currentMinWeight = double.infinity;
    double currentMaxWeight = double.negativeInfinity;

    final List<FlSpot> validSpots = [];
    for (var entry in _historyData) {
      final Timestamp? ts = entry['timestamp'] as Timestamp?;
      final double? weightGrams = (entry['weight_grams'] as num?)?.toDouble();

      if (ts != null && weightGrams != null) {
        final double clampedWeightGrams = weightGrams.clamp(0.0, double.infinity);
        final DateTime timestamp = ts.toDate();
        final double weightKg = clampedWeightGrams / 1000;
        
        if (weightKg.isFinite) {
          if (weightKg < currentMinWeight) currentMinWeight = weightKg;
          if (weightKg > currentMaxWeight) currentMaxWeight = weightKg;
          validSpots.add(FlSpot(timestamp.millisecondsSinceEpoch.toDouble(), weightKg));
        }
      }
    }

    if (validSpots.isEmpty) {
      _minWeightY = ((_selectedDevice?.emptyWeight ?? 0) / 1000).clamp(0.0, double.infinity).floorToDouble();
      _maxWeightY = ((_selectedDevice?.fullWeight ?? 0) / 1000).clamp(0.0, double.infinity).ceilToDouble();
      if (_minWeightY == _maxWeightY) _maxWeightY += 1.0;
      _minX = 0;
      _maxX = 1;
      _intervalX = 1;
      return;
    }

    validSpots.sort((a, b) => a.x.compareTo(b.x));

    _minX = validSpots.first.x;
    _maxX = validSpots.last.x;

    double yRange = currentMaxWeight - currentMinWeight;
    double yPadding = yRange * 0.1; 
    if (yPadding < 0.5) yPadding = 0.5;

    _minWeightY = (currentMinWeight - yPadding).clamp(0.0, double.infinity);
    _maxWeightY = (currentMaxWeight + yPadding).clamp(0.0, double.infinity);

    if ((_maxWeightY - _minWeightY) < 2.0) {
      double midpoint = (currentMinWeight + currentMaxWeight) / 2;
      _minWeightY = (midpoint - 1.0).clamp(0.0, double.infinity);
      _maxWeightY = (midpoint + 1.0).clamp(0.0, double.infinity);
    }
    
    _minWeightY = _minWeightY.clamp(0.0, (_selectedDevice?.emptyWeight ?? 0) / 1000);
    _maxWeightY = _maxWeightY.clamp((_selectedDevice?.fullWeight ?? 0) / 1000, double.infinity);

    if (_minWeightY == _maxWeightY) {
      _minWeightY = (_minWeightY - 1).clamp(0.0, double.infinity);
      _maxWeightY = _maxWeightY + 1;
    }

    final Duration duration = _endDate.difference(_startDate);
    if (duration.inDays <= 1) {
      _intervalX = const Duration(hours: 3).inMilliseconds.toDouble();
    } else if (duration.inDays <= 7) {
      _intervalX = const Duration(days: 1).inMilliseconds.toDouble();
    } else if (duration.inDays <= 30) {
      _intervalX = const Duration(days: 5).inMilliseconds.toDouble();
    } else {
      _intervalX = const Duration(days: 10).inMilliseconds.toDouble();
    }
  }


  /// Shows a date picker to allow the user to select a start date.
  Future<void> _selectStartDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: _endDate,
    );
    if (picked != null && picked != _startDate) {
      setState(() {
        _startDate = picked;
      });
      _fetchHistoryData();
    }
  }

  /// Shows a date picker to allow the user to select an end date.
  Future<void> _selectEndDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _endDate) {
      setState(() {
        _endDate = picked;
      });
      _fetchHistoryData();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Global History')),
        body: const Center(
          child: Text('Please log in to view device history.', style: TextStyle(color: Colors.red)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Global History'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Device Selector Dropdown
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: _isLoading && _availableDevices.isEmpty // Show circular progress if loading initially and no devices
                ? const Center(child: CircularProgressIndicator())
                : _availableDevices.isEmpty
                    ? Text(
                        _errorMessage ?? 'No devices found to display history.',
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      )
                    : DropdownButtonFormField<LPGDevice>(
                        decoration: InputDecoration(
                          labelText: 'Select Device',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          prefixIcon: const Icon(Icons.devices_other),
                        ),
                        value: _selectedDevice,
                        items: _availableDevices.map((device) {
                          return DropdownMenuItem(
                            value: device,
                            child: Text(device.name),
                          );
                        }).toList(),
                        onChanged: (LPGDevice? newValue) {
                          setState(() {
                            _selectedDevice = newValue;
                          });
                          _fetchHistoryData(); // Fetch new data when device changes
                        },
                        isExpanded: true,
                        hint: const Text('Choose a device'),
                      ),
          ),
          
          // Date Range Selection Row (only show if a device is selected)
          if (_selectedDevice != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _selectStartDate(context),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        backgroundColor: Colors.teal.shade50,
                        foregroundColor: Colors.teal.shade800,
                        elevation: 2,
                      ),
                      child: Column(
                        children: [
                          const Text('Start Date:', style: TextStyle(fontSize: 12)),
                          Text(DateFormat('MMM dd, yyyy').format(_startDate), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _selectEndDate(context),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        backgroundColor: Colors.teal.shade50,
                        foregroundColor: Colors.teal.shade800,
                        elevation: 2,
                      ),
                      child: Column(
                        children: [
                          const Text('End Date:', style: TextStyle(fontSize: 12)),
                          Text(DateFormat('MMM dd, yyyy').format(_endDate), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          // Conditional rendering for loading, error, no data, or chart/list
          _isLoading && _selectedDevice != null // Only show loading spinner if a device is selected and we are fetching
              ? const Expanded(child: Center(child: CircularProgressIndicator()))
              : _errorMessage != null
                  ? Expanded(
                      child: Center(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : _selectedDevice == null
                      ? Expanded(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.touch_app, size: 60, color: Colors.grey.shade400),
                                const SizedBox(height: 16),
                                Text(
                                  'Please select a device from the dropdown above to view its history.',
                                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : _historyData.isEmpty
                          ? Expanded(
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.info_outline, size: 60, color: Colors.grey.shade400),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No history data for ${_selectedDevice!.name} in the selected range.',
                                      style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : Expanded(
                              child: Column(
                                children: [
                                  // Total Gas Consumed & Average Daily Consumption Card
                                  Card(
                                    margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                    elevation: 4,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    color: Colors.teal.shade100,
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.analytics_outlined, color: Colors.teal, size: 30),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  'Total Gas Consumed: ${(_totalGasConsumed / 1000).toStringAsFixed(2)} kg',
                                                  style: TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.teal.shade900,
                                                  ),
                                                  softWrap: true,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              const Icon(Icons.speed, color: Colors.teal, size: 30),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  'Avg. Daily Consumption: ${(_averageDailyConsumption / 1000).toStringAsFixed(2)} kg',
                                                  style: TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.teal.shade900,
                                                  ),
                                                  softWrap: true,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              const Icon(Icons.calendar_today, color: Colors.teal, size: 30),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  'Estimated Days Remaining: $_daysRemaining',
                                                  style: TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.teal.shade900,
                                                  ),
                                                  softWrap: true,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // === Chart Section ===
                                  Padding(
                                    padding: const EdgeInsets.only(top: 16.0, left: 16.0, right: 16.0),
                                    child: AspectRatio(
                                      aspectRatio: 1.70,
                                      child: Card(
                                        elevation: 5,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                        color: Colors.white,
                                        child: Padding(
                                          padding: const EdgeInsets.only(right: 18, left: 12, top: 24, bottom: 12),
                                          child: LineChart(
                                            LineChartData(
                                              lineTouchData: LineTouchData(
                                                touchTooltipData: LineTouchTooltipData(
                                                  getTooltipColor: (LineBarSpot touchedSpot) => Colors.teal.withOpacity(0.8),
                                                  getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                                                    return touchedBarSpots.map((barSpot) {
                                                      final flSpot = barSpot.bar.spots[barSpot.spotIndex];
                                                      final DateTime date = DateTime.fromMillisecondsSinceEpoch(flSpot.x.toInt());
                                                      return LineTooltipItem(
                                                        '${DateFormat('MMM dd, yyyy - HH:mm').format(date.toLocal())}\n'
                                                        '${flSpot.y.toStringAsFixed(2)} kg',
                                                        const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                                      );
                                                    }).toList();
                                                  },
                                                ),
                                                handleBuiltInTouches: true,
                                                getTouchLineStart: (barData, spotIndex) => 0,
                                              ),
                                              gridData: FlGridData(
                                                show: true,
                                                drawVerticalLine: true,
                                                getDrawingHorizontalLine: (value) {
                                                  return FlLine(
                                                    color: Colors.grey.withOpacity(0.3),
                                                    strokeWidth: 0.8,
                                                  );
                                                },
                                                getDrawingVerticalLine: (value) {
                                                  return FlLine(
                                                    color: Colors.grey.withOpacity(0.3),
                                                    strokeWidth: 0.8,
                                                  );
                                                },
                                              ),
                                              titlesData: FlTitlesData(
                                                show: true,
                                                rightTitles: const AxisTitles(
                                                  sideTitles: SideTitles(showTitles: false),
                                                ),
                                                topTitles: const AxisTitles(
                                                  sideTitles: SideTitles(showTitles: false),
                                                ),
                                                bottomTitles: AxisTitles(
                                                  sideTitles: SideTitles(
                                                    showTitles: true,
                                                    reservedSize: 30,
                                                    interval: _intervalX,
                                                    getTitlesWidget: (value, meta) {
                                                      final DateTime date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                                                      String text;
                                                      if (_endDate.difference(_startDate).inDays <= 1) {
                                                        text = DateFormat('HH:mm').format(date);
                                                      } else if (_endDate.difference(_startDate).inDays <= 7) {
                                                        text = DateFormat('EEE').format(date);
                                                      } else {
                                                        text = DateFormat('MMM dd').format(date);
                                                      }
                                                      return SideTitleWidget(
                                                        angle: 0.0,
                                                        space: 8.0,
                                                        child: Text(text, style: const TextStyle(fontSize: 10, color: Colors.black)),
                                                        meta: meta, 
                                                      );
                                                    },
                                                  ),
                                                ),
                                                leftTitles: AxisTitles(
                                                  sideTitles: SideTitles(
                                                    showTitles: true,
                                                    reservedSize: 42,
                                                    getTitlesWidget: (value, meta) {
                                                      return SideTitleWidget(
                                                        space: 8.0,
                                                        child: Text('${value.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 10, color: Colors.black)),
                                                        meta: meta, 
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ),
                                              borderData: FlBorderData(
                                                show: true,
                                                border: Border.all(color: Colors.grey.shade300, width: 1),
                                              ),
                                              minX: _minX,
                                              maxX: _maxX,
                                              minY: _minWeightY,
                                              maxY: _maxWeightY,
                                              lineBarsData: [
                                                LineChartBarData(
                                                  spots: _historyData.map((entry) {
                                                    final Timestamp? ts = entry['timestamp'] as Timestamp?;
                                                    final double? weightGrams = (entry['weight_grams'] as num?)?.toDouble();

                                                    if (ts != null && weightGrams != null) {
                                                      final double clampedWeightGrams = weightGrams.clamp(0.0, double.infinity);
                                                      final DateTime timestamp = ts.toDate();
                                                      final double weightKg = clampedWeightGrams / 1000;
                                                      return FlSpot(timestamp.millisecondsSinceEpoch.toDouble(), weightKg);
                                                    }
                                                    return FlSpot(0, 0);
                                                  }).toList(),
                                                  isCurved: true,
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      Colors.teal.shade300,
                                                      Colors.teal.shade700,
                                                    ],
                                                    begin: Alignment.bottomCenter,
                                                    end: Alignment.topCenter,
                                                  ),
                                                  barWidth: 3,
                                                  isStrokeCapRound: true,
                                                  dotData: const FlDotData(show: false),
                                                  belowBarData: BarAreaData(
                                                    show: true,
                                                    gradient: LinearGradient(
                                                      colors: [
                                                        Colors.teal.shade200.withOpacity(0.5),
                                                        Colors.teal.shade800.withOpacity(0.1),
                                                      ],
                                                      begin: Alignment.bottomCenter,
                                                      end: Alignment.topCenter,
                                                    ),
                                                  ),
                                                ),
                                                LineChartBarData(
                                                  spots: [
                                                    FlSpot(_minX, (_selectedDevice?.emptyWeight ?? 0) / 1000),
                                                    FlSpot(_maxX, (_selectedDevice?.emptyWeight ?? 0) / 1000),
                                                  ],
                                                  color: Colors.redAccent.withOpacity(0.8),
                                                  barWidth: 1.5,
                                                  dotData: const FlDotData(show: false),
                                                  isStrokeCapRound: true,
                                                  dashArray: [5, 5],
                                                ),
                                                LineChartBarData(
                                                  spots: [
                                                    FlSpot(_minX, (_selectedDevice?.fullWeight ?? 0) / 1000),
                                                    FlSpot(_maxX, (_selectedDevice?.fullWeight ?? 0) / 1000),
                                                  ],
                                                  color: Colors.greenAccent.withOpacity(0.8),
                                                  barWidth: 1.5,
                                                  dotData: const FlDotData(show: false),
                                                  isStrokeCapRound: true,
                                                  dashArray: [5, 5],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Expanded(
                                    child: ListView.builder(
                                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                      itemCount: _historyData.length,
                                      itemBuilder: (context, index) {
                                        final entry = _historyData[index];
                                        final double weight = ((entry['weight_grams'] ?? 0.0) as double).clamp(0.0, double.infinity);
                                        final Timestamp? timestamp = entry['timestamp'] as Timestamp?;
                                        
                                        double consumption = 0.0;
                                        if (index > 0) {
                                          final previousEntry = _historyData[index - 1];
                                          final double previousEntryWeight = ((previousEntry['weight_grams'] ?? 0.0) as double).clamp(0.0, double.infinity);
                                          consumption = _calculateGasUsage(previousEntryWeight, weight);
                                        }

                                        return Card(
                                          elevation: 2,
                                          margin: const EdgeInsets.symmetric(vertical: 6.0),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          child: Padding(
                                            padding: const EdgeInsets.all(12.0),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded( 
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        timestamp != null 
                                                            ? DateFormat('MMM dd, yyyy - HH:mm').format(timestamp.toDate().toLocal())
                                                            : 'Date N/A',
                                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text('Weight: ${(weight / 1000).toStringAsFixed(2)} kg'),
                                                    ],
                                                  ),
                                                ),
                                                if (consumption > 0)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.red.shade100,
                                                      borderRadius: BorderRadius.circular(5),
                                                    ),
                                                    child: Text(
                                                      '- ${(consumption / 1000).toStringAsFixed(2)} kg',
                                                      style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
        ],
      ),
    );
  }
}