import 'package:flutter/material.dart';

import '../screens/home_page.dart';
import '../screens/map_page.dart';
import '../screens/activity_page.dart';
import '../screens/account_page.dart';

class BottomNav extends StatefulWidget {
  const BottomNav({super.key});

  @override
  State<BottomNav> createState() => _BottomNavState();
}

class _BottomNavState extends State<BottomNav> {
  static const _activityTabIndex = 2;

  int _currentTabIndex = 0;

  // IndexedStack keeps every tab alive, so Activity is told when it's
  // reopened and can refresh walk history.
  final _activityRefresh = ValueNotifier<int>(0);

  late final List<Widget> _pages = [
    const HomePage(),
    const MapPage(),
    ActivityPage(refreshSignal: _activityRefresh),
    const AccountPage(),
  ];

  @override
  void dispose() {
    _activityRefresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: IndexedStack(index: _currentTabIndex, children: _pages),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentTabIndex,
          onDestinationSelected: (int index) {
            if (index == _activityTabIndex && index != _currentTabIndex) {
              _activityRefresh.value++;
            }
            setState(() {
              _currentTabIndex = index;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Map',
            ),
            NavigationDestination(
              icon: Icon(Icons.photo_outlined),
              selectedIcon: Icon(Icons.photo),
              label: 'Activity',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Account',
            ),
          ],
        ),
      ),
    );
  }
}
