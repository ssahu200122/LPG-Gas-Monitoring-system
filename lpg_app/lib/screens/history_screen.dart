import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // For accessing FirestoreService
import 'package:intl/intl.dart'; // For date formatting
import 'package:cloud_firestore/cloud_firestore.dart'; // Import for Timestamp type

import 'package:lpg_app/services/firestore_service.dart'; // Import FirestoreService

class HistoryScreen extends StatefulWidget {
  final String deviceId; // The unique ID of the device
  final String deviceName; // The friendly name of the device
  final double emptyWeight; // Empty weight of the cylinder (grams)
  final double fullWeight; // Full weight of the cylinder (grams)

  const HistoryScreen({
    super.key,
    required this.deviceId,
    required this.deviceName,
    required this.emptyWeight,
    required this.fullWeight,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final FirestoreService _firestoreService; // Firestore service instance
  List<Map<String, dynamic>> _historyData = []; // Stores fetched history data
  bool _isLoading = true; // Controls loading indicator visibility
  String? _errorMessage; // Stores and displays error messages

  // Date range for filtering history. Initialize to last 7 days.
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Access FirestoreService from the Provider.
    _firestoreService = Provider.of<FirestoreService>(context, listen: false);
    _fetchHistoryData(); // Fetch initial history data
  }

  /// Fetches historical data from Firestore for the selected device and date range.
  Future<void> _fetchHistoryData() async {
    setState(() {
      _isLoading = true; // Start loading
      _errorMessage = null; // Clear previous errors
    });

    try {
      // Call FirestoreService to get historical data.
      final data = await _firestoreService.getDeviceHistory(
        widget.deviceId,
        _startDate,
        _endDate,
      );
      setState(() {
        _historyData = data; // Update history data list
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load history: ${e.toString()}'; // Set error message
      });
    } finally {
      setState(() {
        _isLoading = false; // Stop loading
      });
    }
  }

  /// Calculates gas usage between a previous weight reading and a current weight reading.
  /// This assumes the previous reading is chronologically *before* the current one.
  ///
  /// [previousWeight]: The weight reading at an earlier point in time.
  /// [currentWeight]: The weight reading at a later point in time.
  /// Returns the amount of gas consumed (positive value) or 0 if consumption is not detected.
  double _calculateGasUsage(double previousWeight, double currentWeight) {
    // If the previous weight is greater than the current weight, gas has been consumed.
    if (previousWeight > currentWeight) {
      return (previousWeight - currentWeight);
    }
    return 0.0; // No consumption detected (e.g., refilled, or sensor fluctuation)
  }

  /// Calculates the total gas consumed within the fetched history data.
  /// This sums up consumption between consecutive readings.
  double _calculateTotalGasConsumed() {
    double totalConsumed = 0.0;
    // Iterate through history data, comparing current reading with the next older one.
    // History data is typically ordered descending by timestamp, so we go from newer to older.
    for (int i = 0; i < _historyData.length - 1; i++) {
      final currentReading = _historyData[i]['weight_grams'] as double;
      // No need to convert timestamp if only weight is used for calculation.
      final nextOlderReadingWeight = _historyData[i + 1]['weight_grams'] as double;
      
      // Ensure current and next older readings are valid before calculating usage.
      // Removed null check for currentReading and nextOlderReadingWeight as they are casted with 'as double' which assumes non-null.
      // If they can be null, the cast should be `as double?` followed by null checks.
      // Based on previous code, they are expected to be non-null after '?? 0.0'
      totalConsumed += _calculateGasUsage(nextOlderReadingWeight, currentReading);
    }
    return totalConsumed;
  }

  /// Shows a date picker to allow the user to select a start date.
  Future<void> _selectStartDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate, // Initial date in the picker
      firstDate: DateTime(2020), // Earliest selectable date
      lastDate: _endDate, // Latest selectable date cannot be after end date
    );
    if (picked != null && picked != _startDate) {
      setState(() {
        _startDate = picked; // Update start date
      });
      _fetchHistoryData(); // Refetch data with new date range
    }
  }

  /// Shows a date picker to allow the user to select an end date.
  Future<void> _selectEndDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _endDate, // Initial date in the picker
      firstDate: _startDate, // Earliest selectable date cannot be before start date
      lastDate: DateTime.now(), // Latest selectable date is today
    );
    if (picked != null && picked != _endDate) {
      setState(() {
        _endDate = picked; // Update end date
      });
      _fetchHistoryData(); // Refetch data with new date range
    }
  }

  @override
  Widget build(BuildContext context) {
    double totalGasConsumed = _calculateTotalGasConsumed(); // Calculate total consumption for display

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.deviceName} History'), // AppBar title with device name
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Date Range Selection Row
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
                      backgroundColor: Colors.teal.shade50, // Lighter background
                      foregroundColor: Colors.teal.shade800, // Teal text
                      elevation: 2,
                    ),
                    child: Column(
                      children: [
                        const Text('Start Date:', style: TextStyle(fontSize: 12)),
                        Text(DateFormat('MMM dd, yyyy').format(_startDate), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), // Changed YYYY to yyyy
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
                      backgroundColor: Colors.teal.shade50, // Lighter background
                      foregroundColor: Colors.teal.shade800, // Teal text
                      elevation: 2,
                    ),
                    child: Column(
                      children: [
                        const Text('End Date:', style: TextStyle(fontSize: 12)),
                        Text(DateFormat('MMM dd, yyyy').format(_endDate), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), // Changed YYYY to yyyy
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Total Gas Consumed Card
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            color: Colors.teal.shade100,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row( // This is the Row that was overflowing
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.analytics_outlined, color: Colors.teal, size: 30),
                  const SizedBox(width: 10),
                  // === FIX: Wrap the Text widget in an Expanded widget ===
                  Expanded( 
                    child: Text(
                      'Total Gas Consumed: ${(totalGasConsumed / 1000).toStringAsFixed(2)} kg',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade900,
                      ),
                      softWrap: true, // Allow text to wrap if it's too long
                      overflow: TextOverflow.ellipsis, // Add ellipsis if it still overflows (unlikely with Expanded)
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Conditional rendering for loading, error, or no data
          _isLoading
              ? const Expanded(child: Center(child: CircularProgressIndicator())) // Show loading spinner
              : _errorMessage != null
                  ? Expanded(
                      child: Center(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ) // Show error message
                  : _historyData.isEmpty
                      ? Expanded(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.info_outline, size: 60, color: Colors.grey.shade400),
                                const SizedBox(height: 16),
                                Text(
                                  'No history data for the selected range.',
                                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        ) // Show no data message
                      : Expanded(
                          // Display history data in a ListView
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            itemCount: _historyData.length,
                            itemBuilder: (context, index) {
                              final entry = _historyData[index];
                              final double weight = (entry['weight_grams'] ?? 0.0) as double;
                              final DateTime timestamp = (entry['timestamp'] as Timestamp).toDate();
                              
                              // Calculate consumption for this specific entry relative to the *next older* entry
                              double consumption = 0.0;
                              if (index < _historyData.length - 1) {
                                final previousEntry = _historyData[index + 1];
                                final double previousEntryWeight = (previousEntry['weight_grams'] ?? 0.0) as double;
                                consumption = _calculateGasUsage(previousEntryWeight, weight);
                              }

                              return Card(
                                elevation: 2,
                                margin: const EdgeInsets.symmetric(vertical: 6.0),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Row( // This is the Row that was originally causing overflow
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      // This Expanded was already correctly applied from previous fix
                                      Expanded( 
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              DateFormat('MMM dd, yyyy - HH:mm').format(timestamp.toLocal()),
                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(height: 4),
                                            Text('Weight: ${(weight / 1000).toStringAsFixed(2)} kg'),
                                          ],
                                        ),
                                      ),
                                      // Display consumption for this interval (if any)
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
    );
  }
}
