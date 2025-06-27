import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart'; // Import fl_chart

import 'package:lpg_app/services/firestore_service.dart';

class HistoryScreen extends StatefulWidget {
  final String deviceId;
  final String deviceName;
  final double emptyWeight;
  final double fullWeight;

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
  late final FirestoreService _firestoreService;
  List<Map<String, dynamic>> _historyData = [];
  bool _isLoading = true;
  String? _errorMessage;

  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();

  // Variables for chart axis ranges
  double _minWeightY = 0;
  double _maxWeightY = 0;
  double _minX = 0;
  double _maxX = 0;
  double _intervalX = 1; // Default to 1 unit between major X-axis labels

  double _totalGasConsumed = 0.0;
  double _averageDailyConsumption = 0.0;
  String _daysRemaining = 'N/A'; // New variable for days remaining

  @override
  void initState() {
    super.initState();
    _firestoreService = Provider.of<FirestoreService>(context, listen: false);
    _fetchHistoryData();
  }

  Future<void> _fetchHistoryData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await _firestoreService.getDeviceHistory(
        widget.deviceId,
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

      setState(() {
        _historyData = data;
        _calculateChartRanges(); // Calculate ranges for the chart
        _calculateConsumptionMetrics(); // Calculate total and average consumption
        _calculateDaysRemaining(); // Calculate days remaining
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load history: Invalid data found or calculation error: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
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
    if (_historyData.isEmpty || _averageDailyConsumption <= 0) {
      _daysRemaining = 'N/A';
      return;
    }

    // Get the most recent weight reading
    final latestEntry = _historyData.last;
    final double currentWeightGrams = ((latestEntry['weight_grams'] ?? 0.0) as double).clamp(0.0, double.infinity);

    // Calculate actual gas remaining (total gas in cylinder, not including empty weight)
    final double gasRemainingInCylinder = (currentWeightGrams - widget.emptyWeight).clamp(0.0, double.infinity);

    if (gasRemainingInCylinder <= 0) {
      _daysRemaining = 'Empty';
    } else {
      final double estimatedDays = gasRemainingInCylinder / _averageDailyConsumption;
      // Display as whole days if > 1, otherwise fractions
      if (estimatedDays < 1.0 && estimatedDays > 0) {
        // Convert to hours if less than a day
        final double estimatedHours = estimatedDays * 24;
        _daysRemaining = '${estimatedHours.toStringAsFixed(0)} hrs';
      } else if (estimatedDays >= 1.0) {
        _daysRemaining = '${estimatedDays.toStringAsFixed(0)} days';
      } else {
        _daysRemaining = 'N/A'; // Should not happen with clamping
      }
    }
  }

  /// Calculates the min/max X (time) and Y (weight) values for the chart.
  void _calculateChartRanges() {
    if (_historyData.isEmpty) {
      _minWeightY = (widget.emptyWeight / 1000).clamp(0.0, double.infinity).floorToDouble();
      _maxWeightY = (widget.fullWeight / 1000).clamp(0.0, double.infinity).ceilToDouble();
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
      _minWeightY = (widget.emptyWeight / 1000).clamp(0.0, double.infinity).floorToDouble();
      _maxWeightY = (widget.fullWeight / 1000).clamp(0.0, double.infinity).ceilToDouble();
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
    
    _minWeightY = _minWeightY.clamp(0.0, widget.emptyWeight / 1000);
    _maxWeightY = _maxWeightY.clamp(widget.fullWeight / 1000, double.infinity);

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
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.deviceName} History'),
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
                  const SizedBox(height: 8), // Spacer
                  Row(
                    children: [
                      const Icon(Icons.speed, color: Colors.teal, size: 30), // Icon for average
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
                  const SizedBox(height: 8), // Spacer for the new metric
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, color: Colors.teal, size: 30), // Icon for days remaining
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

          // Conditional rendering for loading, error, no data, or chart/list
          _isLoading
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
                        )
                      : Expanded(
                          child: Column(
                            children: [
                              // === Chart Section ===
                              Padding(
                                padding: const EdgeInsets.only(top: 16.0, left: 16.0, right: 16.0),
                                child: AspectRatio(
                                  aspectRatio: 1.70, // Adjust aspect ratio for chart height
                                  child: Card(
                                    elevation: 5,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                    color: Colors.white, // Chart background
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 18, left: 12, top: 24, bottom: 12),
                                      child: LineChart(
                                        LineChartData(
                                          lineTouchData: LineTouchData( // Tooltip configuration
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
                                                color: Colors.grey.withOpacity(0.3), // Softer grid lines
                                                strokeWidth: 0.8,
                                              );
                                            },
                                            getDrawingVerticalLine: (value) {
                                              return FlLine(
                                                color: Colors.grey.withOpacity(0.3), // Softer grid lines
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
                                                interval: _intervalX, // Use calculated interval
                                                getTitlesWidget: (value, meta) {
                                                  final DateTime date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                                                  // Format based on interval/duration
                                                  String text;
                                                  if (_endDate.difference(_startDate).inDays <= 1) {
                                                    text = DateFormat('HH:mm').format(date); // Hourly for single day
                                                  } else if (_endDate.difference(_startDate).inDays <= 7) {
                                                    text = DateFormat('EEE').format(date); // Day of week for week view
                                                  } else {
                                                    text = DateFormat('MMM dd').format(date); // Month Day for longer views
                                                  }
                                                  return SideTitleWidget(
                                                    angle: 0.0, // Ensure text is horizontal
                                                    space: 8.0,
                                                    meta: meta,
                                                    child: Text(text, style: const TextStyle(fontSize: 10, color: Colors.black)), 
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
                                                    meta: meta,
                                                    child: Text('${value.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 10, color: Colors.black)), 
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                          borderData: FlBorderData(
                                            show: true,
                                            border: Border.all(color: Colors.grey.shade300, width: 1), // Softer border
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
                                                  final DateTime timestamp = ts.toDate();
                                                  final double clampedWeightGrams = weightGrams.clamp(0.0, double.infinity);
                                                  final double weightKg = clampedWeightGrams / 1000;
                                                  return FlSpot(timestamp.millisecondsSinceEpoch.toDouble(), weightKg);
                                                }
                                                return FlSpot(0, 0); // Return a valid FlSpot, possibly at 0,0, to prevent runtime error on null
                                              }).toList(), // No whereType<FlSpot>() filter here, handle FlSpot(0,0) explicitly
                                              isCurved: true,
                                              gradient: LinearGradient( // Gradient for the line
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
                                                gradient: LinearGradient( // Gradient for the area below the line
                                                  colors: [
                                                    Colors.teal.shade200.withOpacity(0.5),
                                                    Colors.teal.shade800.withOpacity(0.1),
                                                  ],
                                                  begin: Alignment.bottomCenter,
                                                  end: Alignment.topCenter,
                                                ),
                                              ),
                                            ),
                                            // Add horizontal lines for empty and full weight
                                            LineChartBarData(
                                              spots: [
                                                FlSpot(_minX, widget.emptyWeight / 1000),
                                                FlSpot(_maxX, widget.emptyWeight / 1000),
                                              ],
                                              color: Colors.redAccent.withOpacity(0.8),
                                              barWidth: 1.5,
                                              dotData: const FlDotData(show: false),
                                              isStrokeCapRound: true,
                                              dashArray: [5, 5],
                                            ),
                                            LineChartBarData(
                                              spots: [
                                                FlSpot(_minX, widget.fullWeight / 1000),
                                                FlSpot(_maxX, widget.fullWeight / 1000),
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
                                    final DateTime? timestamp = (entry['timestamp'] as Timestamp?)?.toDate();
                                    
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
                                                        ? DateFormat('MMM dd, yyyy - HH:mm').format(timestamp.toLocal())
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