import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'auth_screen.dart';
import 'create_load_screen.dart';
import 'create_truck_screen.dart';
import 'create_booking_screen.dart';
import 'bookings_screen.dart';
import 'notifications_screen.dart';
import 'payments_screen.dart';
import 'profile_screen.dart';
import 'matching_screen.dart';

const _navy = Color(0xFF142B4A);
const _blue = Color(0xFF2864E8);
const _bg = Color(0xFFF5F7FB);
const _muted = Color(0xFF7A8799);

class HomeScreen extends StatefulWidget {
  final ApiService api;
  const HomeScreen({super.key, required this.api});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  late Future<List<dynamic>> _loads;
  late Future<List<dynamic>> _myLoads;
  late Future<List<dynamic>> _trucks;
  late Future<List<dynamic>> _bookings;
  late Future<Map<String, dynamic>> _user;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _loads = widget.api.listLoads();
    _myLoads = widget.api.listMyLoads();
    _trucks = widget.api.listMyTrucks();
    _bookings = widget.api.listBookings();
    _user = widget.api.getCurrentUser();
  }

  Future<void> _reload() async {
    setState(_refresh);
    try {
      await Future.wait([_loads, _myLoads, _trucks, _bookings, _user]);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _logout() async {
    await widget.api.clearToken();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => AuthScreen(api: widget.api)),
        (_) => false);
  }

  Future<void> _create() async {
    final user = await _user;
    final canCreate = _tab == 2
        ? ['truckOwner', 'agency', 'admin'].contains(user['role'])
        : ['customer', 'agency', 'admin'].contains(user['role']);
    if (!canCreate) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_tab == 2
                ? 'Only truck owners and agencies can register trucks.'
                : 'Only customers and agencies can post loads.'),
          ),
        );
      }
      return;
    }
    final result = await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _tab == 2
            ? CreateTruckScreen(api: widget.api)
            : CreateLoadScreen(api: widget.api)));
    if (result == true) _reload();
  }

  Future<void> _bookLoad(Map<String, dynamic> load) async {
    final user = await _user;
    if (!['truckOwner', 'agency', 'admin'].contains(user['role'])) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only truck owners or agencies can book a load.'),
          ),
        );
      }
      return;
    }
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) => CreateBookingScreen(api: widget.api, load: load)),
    );
    if (result == true) _reload();
  }

  Future<void> _editLoad(Map<String, dynamic> load) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateLoadScreen(api: widget.api, initialLoad: load),
      ),
    );
    if (result == true) await _reload();
  }

  Future<void> _cancelLoad(Map<String, dynamic> load) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this load?'),
        content: const Text('It will no longer appear in load search.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep load'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel load'),
          ),
        ],
      ),
    );
    final id = _recordId(load);
    if (confirmed != true || id == null) return;
    try {
      await widget.api.cancelLoad(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Load cancelled.')),
        );
      }
      await _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  Future<void> _editTruck(Map<String, dynamic> truck) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateTruckScreen(api: widget.api, initialTruck: truck),
      ),
    );
    if (result == true) await _reload();
  }

  Future<void> _deleteTruck(Map<String, dynamic> truck) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this truck?'),
        content: const Text(
          'A truck with an active booking cannot be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep truck'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete truck'),
          ),
        ],
      ),
    );
    final id = _recordId(truck);
    if (confirmed != true || id == null) return;
    try {
      await widget.api.deleteTruck(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Truck deleted.')),
        );
      }
      await _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  String? _recordId(Map<String, dynamic> record) =>
      record['id']?.toString() ?? record['_id']?.toString();

  Future<void> _openScreen(Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = [
      'Dashboard',
      'Find loads',
      'Truck fleet',
      'My bookings',
      'Payments',
    ];
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        elevation: 0,
        titleSpacing: 20,
        title: Row(children: [
          Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: _blue, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.local_shipping_rounded,
                  color: Colors.white, size: 22)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('HaulMate',
                style: TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 19,
                    letterSpacing: -.5)),
            Text(titles[_tab],
                style: const TextStyle(
                    color: _muted, fontSize: 11, fontWeight: FontWeight.w500))
          ]),
        ]),
        actions: [
          FutureBuilder<Map<String, dynamic>>(
            future: _user,
            builder: (context, snapshot) {
              if (!['truckOwner', 'agency'].contains(snapshot.data?['role'])) {
                return const SizedBox.shrink();
              }
              return IconButton(
                onPressed: () => _openScreen(MatchingScreen(api: widget.api)),
                tooltip: 'Nearby matching loads',
                icon: const Icon(Icons.near_me_outlined, color: _navy),
              );
            },
          ),
          IconButton(
            onPressed: () => _openScreen(NotificationsScreen(api: widget.api)),
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_outlined, color: _navy),
          ),
          IconButton(
              onPressed: _reload,
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded, color: _navy)),
          Padding(
              padding: const EdgeInsets.only(right: 16),
              child: PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'profile') {
                    _openScreen(ProfileScreen(api: widget.api));
                  }
                  if (v == 'logout') _logout();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'profile',
                      child: Row(children: [
                        Icon(Icons.person_outline, size: 18),
                        SizedBox(width: 8),
                        Text('Profile')
                      ])),
                  PopupMenuItem(
                      value: 'logout',
                      child: Row(children: [
                        Icon(Icons.logout, size: 18),
                        SizedBox(width: 8),
                        Text('Log out')
                      ]))
                ],
                child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                        color: const Color(0xFFE5ECFA),
                        borderRadius: BorderRadius.circular(50)),
                    child: const Icon(Icons.person_rounded, color: _blue)),
              )),
        ],
      ),
      body: IndexedStack(index: _tab, children: [
        _dashboard(),
        _loadsView(),
        _trucksView(),
        BookingsScreen(api: widget.api),
        PaymentsScreen(api: widget.api),
      ]),
      floatingActionButton: _tab == 1 || _tab == 2
          ? FutureBuilder<Map<String, dynamic>>(
              future: _user,
              builder: (context, snapshot) {
                final allowed = _tab == 2
                    ? ['truckOwner', 'agency', 'admin']
                        .contains(snapshot.data?['role'])
                    : ['customer', 'agency', 'admin']
                        .contains(snapshot.data?['role']);
                if (!allowed) return const SizedBox.shrink();
                return FloatingActionButton.extended(
                    onPressed: _create,
                    backgroundColor: _blue,
                    foregroundColor: Colors.white,
                    elevation: 3,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(_tab == 1 ? 'Post a load' : 'Add a truck'));
              },
            )
          : null,
      bottomNavigationBar: NavigationBar(
        height: 70,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 8,
        selectedIndex: _tab,
        onDestinationSelected: (v) => setState(() => _tab = v),
        indicatorColor: const Color(0xFFE8EFFF),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.grid_view_rounded),
              selectedIcon: Icon(Icons.grid_view_rounded, color: _blue),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2_rounded, color: _blue),
              label: 'Loads'),
          NavigationDestination(
              icon: Icon(Icons.local_shipping_outlined),
              selectedIcon: Icon(Icons.local_shipping_rounded, color: _blue),
              label: 'Trucks'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded, color: _blue),
              label: 'Bookings'),
          NavigationDestination(
              icon: Icon(Icons.payments_outlined),
              selectedIcon: Icon(Icons.payments_rounded, color: _blue),
              label: 'Payments'),
        ],
      ),
    );
  }

  Widget _dashboard() => RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF142B4A), Color(0xFF2864E8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                          color: _blue.withOpacity(.16),
                          blurRadius: 20,
                          offset: const Offset(0, 8))
                    ]),
                child: Stack(children: [
                  Positioned(
                      right: -15,
                      bottom: -24,
                      child: Icon(Icons.local_shipping_rounded,
                          size: 125, color: Colors.white.withOpacity(.09))),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                                color: Colors.white.withOpacity(.14),
                                borderRadius: BorderRadius.circular(30)),
                            child: const Text('SMART LOGISTICS PLATFORM',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.1))),
                        const SizedBox(height: 16),
                        const Text('Move freight.\nMove business.',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 27,
                                height: 1.15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.7)),
                        const SizedBox(height: 9),
                        Text(
                            'Find loads, manage trucks and keep every delivery moving.',
                            style: TextStyle(
                                color: Colors.white.withOpacity(.78),
                                fontSize: 12,
                                height: 1.5)),
                        const SizedBox(height: 18),
                        Row(children: [
                          _heroButton('Explore loads', Icons.search_rounded,
                              () => setState(() => _tab = 1)),
                          const SizedBox(width: 10),
                          _heroButton('Add a truck', Icons.add_road_rounded,
                              () => setState(() => _tab = 2)),
                        ])
                      ])
                ])),
            const SizedBox(height: 24),
            const Row(children: [
              Expanded(
                  child: Text('Your overview',
                      style: TextStyle(
                          color: _navy,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.3))),
              Text('LIVE SUMMARY',
                  style: TextStyle(
                      color: _muted,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .9))
            ]),
            const SizedBox(height: 13),
            FutureBuilder<List<dynamic>>(
                future: _loads,
                builder: (context, l) => FutureBuilder<List<dynamic>>(
                    future: _trucks,
                    builder: (context, t) => FutureBuilder<List<dynamic>>(
                        future: _bookings,
                        builder: (context, b) {
                          final loads = l.data ?? [];
                          final trucks = t.data ?? [];
                          return GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 1.38,
                              children: [
                                _statCard(
                                    'Available loads',
                                    l.connectionState == ConnectionState.waiting
                                        ? '—'
                                        : '${loads.length}',
                                    Icons.inventory_2_rounded,
                                    const Color(0xFFEAF0FF),
                                    _blue,
                                    () => setState(() => _tab = 1)),
                                _statCard(
                                    'Registered trucks',
                                    t.connectionState == ConnectionState.waiting
                                        ? '—'
                                        : '${trucks.length}',
                                    Icons.local_shipping_rounded,
                                    const Color(0xFFE6F7F1),
                                    const Color(0xFF128568),
                                    () => setState(() => _tab = 2)),
                                _statCard(
                                    'Bookings',
                                    b.connectionState == ConnectionState.waiting
                                        ? '—'
                                        : '${b.data?.length ?? 0}',
                                    Icons.receipt_long_rounded,
                                    const Color(0xFFFFF2DF),
                                    const Color(0xFFCA7B10),
                                    () => setState(() => _tab = 3)),
                                _statCard(
                                    'Quick support',
                                    'Get help',
                                    Icons.support_agent_rounded,
                                    const Color(0xFFF1EAFE),
                                    const Color(0xFF8055CE),
                                    () => _showInfo()),
                              ]);
                        }))),
            const SizedBox(height: 25),
            Row(children: [
              const Expanded(
                  child: Text('Quick actions',
                      style: TextStyle(
                          color: _navy,
                          fontSize: 18,
                          fontWeight: FontWeight.w800))),
              TextButton(
                  onPressed: () => setState(() => _tab = 1),
                  child: const Text('View loads'))
            ]),
            const SizedBox(height: 8),
            _actionTile(
                Icons.add_box_rounded,
                'Post a shipment',
                'Share pickup, destination and freight details',
                const Color(0xFFEAF0FF),
                _blue, () async {
              setState(() => _tab = 1);
              await Future.delayed(const Duration(milliseconds: 100));
              if (mounted) _create();
            }),
            const SizedBox(height: 10),
            _actionTile(
                Icons.fire_truck_rounded,
                'Register your truck',
                'Add vehicle details and capacity',
                const Color(0xFFE6F7F1),
                const Color(0xFF128568), () async {
              setState(() => _tab = 2);
              await Future.delayed(const Duration(milliseconds: 100));
              if (mounted) _create();
            }),
            const SizedBox(height: 25),
            const Text('Latest available loads',
                style: TextStyle(
                    color: _navy, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            FutureBuilder<List<dynamic>>(
                future: _loads,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting)
                    return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2)));
                  if (snapshot.hasError)
                    return _error(snapshot.error.toString(), _reload);
                  final items = (snapshot.data ?? []).take(3).toList();
                  if (items.isEmpty)
                    return _empty(
                        'No loads posted yet',
                        'When loads become available, they will appear here.',
                        Icons.inventory_2_outlined);
                  return Column(
                      children: items
                          .map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _loadCard(
                                  Map<String, dynamic>.from(e as Map))))
                          .toList());
                }),
            const SizedBox(height: 10),
            Center(
                child: Text('HAULMATE  •  LOGISTICS MADE SIMPLE',
                    style: TextStyle(
                        color: _muted.withOpacity(.8),
                        fontSize: 9,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700))),
          ]));

  Widget _loadsView() => RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<List<dynamic>>(
          future: _loads,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting)
              return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError)
              return _error(snapshot.error.toString(), _reload);
            final items = snapshot.data ?? [];
            return FutureBuilder<List<dynamic>>(
                future: _myLoads,
                builder: (context, mineSnapshot) {
                  if (mineSnapshot.hasError) {
                    return _error(mineSnapshot.error.toString(), _reload);
                  }
                  if (mineSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final mine = (mineSnapshot.data ?? [])
                      .map((item) => Map<String, dynamic>.from(item as Map))
                      .toList();
                  final mineIds =
                      mine.map(_recordId).whereType<String>().toSet();
                  final available = items
                      .map((item) => Map<String, dynamic>.from(item as Map))
                      .where((load) => !mineIds.contains(_recordId(load)))
                      .toList();
                  return ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      const Text(
                        'My loads',
                        style: TextStyle(
                          color: _navy,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (mine.isEmpty)
                        _empty(
                          'No loads posted by you',
                          'Your shipments will appear here after posting.',
                          Icons.inventory_2_outlined,
                        )
                      else
                        ...mine.map((load) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _loadCard(load, manageable: true),
                            )),
                      const SizedBox(height: 12),
                      const Text(
                        'Available loads',
                        style: TextStyle(
                          color: _navy,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (available.isEmpty)
                        _empty(
                          'No available loads',
                          'Check again later for new shipments.',
                          Icons.inventory_2_outlined,
                        )
                      else
                        ...available.map((load) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _loadCard(load),
                            )),
                    ],
                  );
                });
          }));

  Widget _trucksView() => RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<List<dynamic>>(
          future: _trucks,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting)
              return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError)
              return _error(snapshot.error.toString(), _reload);
            final items = snapshot.data ?? [];
            if (items.isEmpty)
              return ListView(padding: const EdgeInsets.all(24), children: [
                _empty(
                    'No trucks registered',
                    'Add a truck to start managing your fleet.',
                    Icons.local_shipping_outlined)
              ]);
            return ListView.separated(
                padding: const EdgeInsets.all(18),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final t = Map<String, dynamic>.from(items[i] as Map);
                  final available = t['isAvailable'] != false;
                  return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: _cardDecoration(),
                      child: Row(children: [
                        Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                                color: const Color(0xFFEAF0FF),
                                borderRadius: BorderRadius.circular(16)),
                            child: const Icon(Icons.local_shipping_rounded,
                                color: _blue, size: 27)),
                        const SizedBox(width: 14),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text('${t['registrationNumber'] ?? 'Truck'}',
                                  style: const TextStyle(
                                      color: _navy,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15)),
                              const SizedBox(height: 5),
                              Text(
                                  '${t['truckType'] ?? 'General'}  •  ${t['capacityTons'] ?? '-'} tons',
                                  style: const TextStyle(
                                      color: _muted, fontSize: 12)),
                              if ((t['description'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text('${t['description']}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: _muted, fontSize: 11)))
                            ])),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _status(
                                available ? 'Available' : 'Busy', available),
                            PopupMenuButton<String>(
                              tooltip: 'Manage truck',
                              onSelected: (action) {
                                if (action == 'edit') _editTruck(t);
                                if (action == 'delete') _deleteTruck(t);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit truck'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete truck'),
                                ),
                              ],
                            ),
                          ],
                        )
                      ]));
                });
          }));

  Widget _loadCard(Map<String, dynamic> load, {bool manageable = false}) {
    final pickup = _asMap(load['pickup']);
    final delivery = _asMap(load['delivery']);
    final from = _place(pickup, 'Pickup location');
    final to = _place(delivery, 'Delivery location');
    return Container(
        padding: const EdgeInsets.all(17),
        decoration: _cardDecoration(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: const Color(0xFFEAF0FF),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.inventory_2_rounded,
                    color: _blue, size: 20)),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('${load['loadType'] ?? 'Freight shipment'}',
                      style: const TextStyle(
                          color: _navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  const SizedBox(height: 3),
                  Text(
                      '${load['weightTons'] ?? '-'} tons  •  ${load['requiredTruckType'] ?? 'Any truck'}',
                      style: const TextStyle(color: _muted, fontSize: 11))
                ])),
            _status('${load['status'] ?? 'Searching'}', true)
          ]),
          const SizedBox(height: 17),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(children: [
              const Icon(Icons.radio_button_checked_rounded,
                  color: _blue, size: 17),
              Container(width: 1.5, height: 28, color: const Color(0xFFD8E1F2)),
              const Icon(Icons.location_on_rounded,
                  color: Color(0xFF19A17A), size: 17)
            ]),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('PICKUP',
                      style: TextStyle(
                          color: _muted,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .8)),
                  Text(from,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _navy,
                          fontWeight: FontWeight.w600,
                          fontSize: 12)),
                  const SizedBox(height: 10),
                  Text('DELIVERY',
                      style: TextStyle(
                          color: _muted,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .8)),
                  Text(to,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _navy,
                          fontWeight: FontWeight.w600,
                          fontSize: 12))
                ]))
          ]),
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 13),
              child: Divider(height: 1, color: Color(0xFFEDF0F5))),
          Row(children: [
            const Text('Indicative freight',
                style: TextStyle(color: _muted, fontSize: 11)),
            const Spacer(),
            Text('₹${load['price'] ?? '—'}',
                style: const TextStyle(
                    color: _blue, fontWeight: FontWeight.w900, fontSize: 18))
          ]),
          if (load['status'] == 'searching') ...[
            const SizedBox(height: 8),
            if (manageable)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _editLoad(load),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _cancelLoad(load),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancel'),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _bookLoad(load),
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: const Text('Choose truck and book'),
                ),
              ),
          ],
          if (manageable && load['status'] != 'searching')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'This load can no longer be edited.',
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ),
        ]));
  }

  Widget _statCard(String label, String value, IconData icon, Color tint,
          Color color, VoidCallback onTap) =>
      InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
              padding: const EdgeInsets.all(15),
              decoration: _cardDecoration(),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                            color: tint,
                            borderRadius: BorderRadius.circular(11)),
                        child: Icon(icon, color: color, size: 19)),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(value,
                              style: const TextStyle(
                                  color: _navy,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -.6)),
                          const SizedBox(height: 3),
                          Text(label,
                              style: const TextStyle(
                                  color: _muted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600))
                        ])
                  ])));
  Widget _heroButton(String label, IconData icon, VoidCallback onTap) =>
      InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: _blue, size: 16),
                const SizedBox(width: 7),
                Text(label,
                    style: const TextStyle(
                        color: _navy,
                        fontSize: 11,
                        fontWeight: FontWeight.w800))
              ])));
  Widget _actionTile(IconData icon, String title, String subtitle, Color tint,
          Color color, VoidCallback onTap) =>
      InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(17),
          child: Container(
              padding: const EdgeInsets.all(14),
              decoration: _cardDecoration(),
              child: Row(children: [
                Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                        color: tint, borderRadius: BorderRadius.circular(14)),
                    child: Icon(icon, color: color, size: 23)),
                const SizedBox(width: 13),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          style: const TextStyle(
                              color: _navy,
                              fontWeight: FontWeight.w800,
                              fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: const TextStyle(color: _muted, fontSize: 11))
                    ])),
                const Icon(Icons.arrow_forward_ios_rounded,
                    color: _muted, size: 15)
              ])));
  Widget _status(String label, bool positive) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
          color: positive ? const Color(0xFFE6F7F1) : const Color(0xFFFFECEC),
          borderRadius: BorderRadius.circular(30)),
      child: Text(label,
          style: TextStyle(
              color:
                  positive ? const Color(0xFF128568) : const Color(0xFFC54C4C),
              fontSize: 9,
              fontWeight: FontWeight.w800)));
  Widget _empty(String title, String subtitle, IconData icon) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
      decoration: _cardDecoration(),
      child: Column(children: [
        Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
                color: Color(0xFFEAF0FF), shape: BoxShape.circle),
            child: Icon(icon, color: _blue, size: 28)),
        const SizedBox(height: 13),
        Text(title,
            style: const TextStyle(
                color: _navy, fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 6),
        Text(subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.5))
      ]));
  Widget _error(String message, Future<void> Function() retry) =>
      ListView(padding: const EdgeInsets.all(24), children: [
        const Icon(Icons.cloud_off_rounded, size: 44, color: _muted),
        const SizedBox(height: 12),
        const Text('Could not load data',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: _navy, fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 6),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 12),
        Center(
            child: ElevatedButton(
                onPressed: retry, child: const Text('Try again')))
      ]);
  BoxDecoration _cardDecoration() => BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEDF0F5)),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFF1B3150).withOpacity(.035),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ]);
  Map<String, dynamic> _asMap(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  String _place(Map<String, dynamic> p, String fallback) {
    final city = p['city']?.toString() ?? '';
    final state = p['state']?.toString() ?? '';
    if (city.isNotEmpty)
      return [city, state].where((x) => x.isNotEmpty).join(', ');
    final address = p['address']?.toString() ?? '';
    return address.isNotEmpty ? address : fallback;
  }

  void _showInfo() => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
              title: const Text('HaulMate support'),
              content: const Text(
                  'Support contact and help centre can be connected here when your business support details are ready.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'))
              ]));
}
