import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../strings.dart';
import '../theme.dart';
import 'family_detail_screen.dart';

class FamiliesScreen extends StatefulWidget {
  const FamiliesScreen({super.key});

  @override
  State<FamiliesScreen> createState() => _FamiliesScreenState();
}

class _FamiliesScreenState extends State<FamiliesScreen> {
  final _searchController = TextEditingController();
  final _tableScrollController = ScrollController();
  Timer? _searchDebounce;

  String _statusFilter = ''; // '', 'active', 'dormant', 'inactive'
  int _page = 1;
  static const int _pageSize = 20;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _families = [];
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _loadFamilies();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _tableScrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _page = 1;
      });
      _loadFamilies();
    });
  }

  Future<void> _loadFamilies() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final queryParams = <String, String>{
        if (_searchController.text.trim().isNotEmpty)
          'search': _searchController.text.trim(),
        if (_statusFilter.isNotEmpty) 'status': _statusFilter,
        'page': '$_page',
        'pageSize': '$_pageSize',
      };
      final uri =
          Uri(path: '/families', queryParameters: queryParams).toString();
      final data = await context.read<AppState>().api.get(uri);

      if (!mounted) return;

      final rawList = (data['families'] as List?) ?? [];
      final list = rawList
          .map((item) => (item as Map).cast<String, dynamic>())
          .toList();
      final total = (data['total'] as num?)?.toInt() ?? list.length;
      final serverPage = (data['page'] as num?)?.toInt() ?? _page;

      setState(() {
        _families = list;
        _total = total;
        _page = serverPage;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = Strings.errGenericFallback;
      });
    }
  }

  void _openDetail(int familyId, String name) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FamilyDetailScreen(
          familyId: familyId,
          initialName: name,
        ),
      ),
    );
    if (mounted) {
      _loadFamilies();
    }
  }

  Widget _statusBadge(String? status) {
    Color fg;
    Color bg;
    String label;

    switch (status) {
      case 'active':
        fg = AppColors.successInk;
        bg = AppColors.successSoft;
        label = Strings.statusActive;
        break;
      case 'dormant':
        fg = AppColors.warningInk;
        bg = AppColors.warningSoft;
        label = Strings.statusDormant;
        break;
      case 'inactive':
      default:
        fg = AppColors.dangerInk;
        bg = AppColors.dangerSoft;
        label = Strings.statusInactive;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = (_total / _pageSize).ceil().clamp(1, 99999);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  Strings.familiesTitle,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: Strings.retry,
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _loadFamilies,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: Strings.searchPlaceholder,
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 20),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: '',
                          label: Text(Strings.filterAll),
                        ),
                        ButtonSegment(
                          value: 'active',
                          label: Text(Strings.statusActive),
                        ),
                        ButtonSegment(
                          value: 'dormant',
                          label: Text(Strings.statusDormant),
                        ),
                        ButtonSegment(
                          value: 'inactive',
                          label: Text(Strings.statusInactive),
                        ),
                      ],
                      selected: {_statusFilter},
                      onSelectionChanged: (selection) {
                        setState(() {
                          _statusFilter = selection.first;
                          _page = 1;
                        });
                        _loadFamilies();
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(48),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_error != null)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Text(
                              _error!,
                              style: const TextStyle(
                                color: AppColors.danger,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _loadFamilies,
                              child: Text(Strings.retry),
                            ),
                          ],
                        ),
                      )
                    else if (_families.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(48),
                        child: Center(
                          child: Text(
                            Strings.noFamiliesFound,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      )
                    else
                      Scrollbar(
                        controller: _tableScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _tableScrollController,
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            showCheckboxColumn: false,
                            columnSpacing: 20,
                            horizontalMargin: 16,
                            columns: [
                              DataColumn(label: Text(Strings.colName)),
                              DataColumn(label: Text(Strings.colId)),
                              DataColumn(label: Text(Strings.colHeartbeat)),
                              DataColumn(label: Text(Strings.colPlan)),
                              DataColumn(label: Text(Strings.colSubscription)),
                              DataColumn(label: Text(Strings.colMembers)),
                              DataColumn(label: Text(Strings.colPending)),
                              DataColumn(label: Text(Strings.colActors)),
                              DataColumn(label: Text(Strings.colCreated)),
                              DataColumn(label: Text(Strings.colLastActive)),
                              DataColumn(label: Text(Strings.colActions)),
                            ],
                            rows: [
                              for (final fam in _families)
                                DataRow(
                                  onSelectChanged: (_) => _openDetail(
                                    fam['id'] as int,
                                    fam['name']?.toString() ?? '',
                                  ),
                                  cells: [
                                    DataCell(
                                      Text(
                                        fam['name']?.toString() ??
                                            Strings.emptyDash,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    DataCell(
                                      Text(Strings.formatId(fam['id'])),
                                    ),
                                    DataCell(
                                        _statusBadge(fam['status']?.toString())),
                                    DataCell(
                                      Text(
                                        fam['planCode']?.toString() ??
                                            Strings.emptyDash,
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        fam['subscriptionStatus']?.toString() ??
                                            Strings.emptyDash,
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        fam['memberCount']?.toString() ??
                                            Strings.emptyDash,
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        fam['pendingMemberCount']?.toString() ??
                                            Strings.emptyDash,
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        fam['actorCount']?.toString() ??
                                            Strings.emptyDash,
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        Strings.formatDate(fam['createdAt']),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        Strings.formatDate(fam['lastActiveAt']),
                                      ),
                                    ),
                                    DataCell(
                                      TextButton(
                                        onPressed: () => _openDetail(
                                          fam['id'] as int,
                                          fam['name']?.toString() ?? '',
                                        ),
                                        child: Text(Strings.viewFamily),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          Strings.pageInfo(_page, totalPages, _total),
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Row(
                          children: [
                            OutlinedButton(
                              onPressed: (_page > 1 && !_loading)
                                  ? () {
                                      setState(() {
                                        _page--;
                                      });
                                      _loadFamilies();
                                    }
                                  : null,
                              child: Text(Strings.prevPage),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: (_page < totalPages && !_loading)
                                  ? () {
                                      setState(() {
                                        _page++;
                                      });
                                      _loadFamilies();
                                    }
                                  : null,
                              child: Text(Strings.nextPage),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
