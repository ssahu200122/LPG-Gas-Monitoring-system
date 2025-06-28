import 'package:flutter/material.dart';
import 'package:lpg_app/screens/lpg_device_list_screen.dart';
import 'package:lpg_app/screens/global_history_screen.dart';
import 'package:lpg_app/screens/settings_screen.dart';

import 'package:salomon_bottom_bar/salomon_bottom_bar.dart'; // Import SalomonBottomBar

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _selectedIndex = 0; // Current index of the selected tab

  // List of screens corresponding to each tab (3 tabs)
  static const List<Widget> _widgetOptions = <Widget>[
    LPGDeviceListScreen(),
    GlobalHistoryScreen(),
    SettingsScreen(),
  ];

  /// Handles tap on a bottom navigation bar item.
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Access theme primary color for consistent styling
    final Color primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      // Ensure there is NO AppBar widget directly inside this Scaffold.
      body: IndexedStack(
        index: _selectedIndex,
        children: _widgetOptions,
      ),
      
      bottomNavigationBar: SalomonBottomBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        
        // SalomonBottomBar specific styling
        selectedItemColor: primaryColor, // Unified selected color (teal)
        unselectedItemColor: Colors.grey.shade600, // Subtle grey for unselected
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), // Margin around the bar
        itemPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0), // Padding within each item
        backgroundColor: Theme.of(context).primaryColorDark, // White background for the bar itself
        // FIXED: Removed 'elevation' parameter as it's not defined for SalomonBottomBar.
        // SalomonBottomBar handles its own shadow/elevation internally.
        // elevation: 10, 
        
        items: [
          /// Devices Tab
          SalomonBottomBarItem(
            icon: const Icon(Icons.propane_tank_outlined), // Using outlined icons for a modern look
            title: const Text('Devices'),
            selectedColor: Colors.yellowAccent, // Redundant here if set on parent, but good for clarity/overrides
            unselectedColor: Colors.white, // Redundant here if set on parent
          ),

          /// History Tab
          SalomonBottomBarItem(
            icon: const Icon(Icons.history_toggle_off_outlined), // Outlined history icon
            title: const Text('History'),
            selectedColor: Colors.yellowAccent,
            unselectedColor: Colors.white,
          ),

          /// Settings Tab
          SalomonBottomBarItem(
            icon: const Icon(Icons.settings_outlined), // Outlined settings icon
            title: const Text('Settings'),
            selectedColor: Colors.yellowAccent,
            unselectedColor: Colors.white,
          ),
        ],
      ),
    );
  }
}