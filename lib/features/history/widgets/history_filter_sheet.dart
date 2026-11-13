import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../dashboard/data/dashboard_models.dart';
import '../data/history_models.dart';

/// Advanced filter bottom sheet — type, status, direction, date range and
/// amount bounds. Returns the composed [HistoryFilter] (or an empty one
/// on reset) to the caller, which hands it to `historyProvider`.
class HistoryFilterSheet extends StatefulWidget {
  const HistoryFilterSheet({super.key, required this.initial});

  final HistoryFilter initial;

  static Future<HistoryFilter?> show(
    BuildContext context, {
    required HistoryFilter initial,
  }) {
    return showModalBottomSheet<HistoryFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HistoryFilterSheet(initial: initial),
    );
  }

  @override
  State<HistoryFilterSheet> createState() => _HistoryFilterSheetState();
}

class _HistoryFilterSheetState extends State<HistoryFilterSheet> {
  late Set<TransactionType> _types;
  late Set<TransactionStatus> _statuses;
  late HistoryDirection _direction;
  DateTimeRange? _range;
  late int _datePreset; // 0 any, 1 last7, 2 last30, 3 last90, 4 custom
  final _minAmount = TextEditingController();
  final _maxAmount = TextEditingController();

  static const _typeMeta = <TransactionType, ({String label, IconData icon})>{
    TransactionType.airtime: (
      label: 'Airtime',
      icon: Icons.phone_iphone_rounded,
    ),
    TransactionType.data: (label: 'Data', icon: Icons.wifi_rounded),
    TransactionType.walletTopUp: (
      label: 'MoMo',
      icon: Icons.account_balance_wallet_rounded,
    ),
    TransactionType.shopOrder: (
      label: 'Shop',
      icon: Icons.shopping_bag_rounded,
    ),
    TransactionType.lidaValue: (
      label: 'Lida Value',
      icon: Icons.diamond_rounded,
    ),
    TransactionType.other: (label: 'Other', icon: Icons.receipt_long_rounded),
  };

  @override
  void initState() {
    super.initState();
    _types = {...widget.initial.types};
    _statuses = {...widget.initial.statuses};
    _direction = widget.initial.direction;
    _range = widget.initial.range;
    _datePreset = _range == null ? 0 : 4;
    if (widget.initial.minAmount != null) {
      _minAmount.text = widget.initial.minAmount!.toStringAsFixed(0);
    }
    if (widget.initial.maxAmount != null) {
      _maxAmount.text = widget.initial.maxAmount!.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _minAmount.dispose();
    _maxAmount.dispose();
    super.dispose();
  }

  void _pickPreset(int preset) {
    setState(() {
      _datePreset = preset;
      if (preset == 0) {
        _range = null;
      } else if (preset != 4) {
        final days = switch (preset) {
          1 => 7,
          2 => 30,
          _ => 90,
        };
        final now = DateTime.now();
        _range = DateTimeRange(
          start: DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(Duration(days: days)),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      }
    });
    if (preset == 4) _pickCustomRange();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year, now.month, now.day, 23, 59),
      initialDateRange:
          _range ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 30)),
            end: now,
          ),
    );
    if (picked != null && mounted) {
      setState(() => _range = picked);
    }
  }

  HistoryFilter _compose() {
    return HistoryFilter(
      types: _types,
      statuses: _statuses,
      direction: _direction,
      range: _range,
      minAmount: double.tryParse(_minAmount.text.trim()),
      maxAmount: double.tryParse(_maxAmount.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkSurface : Colors.white;
    final fmt = DateFormat('MMM d');

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(28),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            22,
            14,
            22,
            22 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : const Color(0xFFDDD8E5),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filter activity',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF241E33),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop(const HistoryFilter()),
                    child: const Text('Reset all'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _sectionLabel('Type', isDark),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final meta in _typeMeta.entries)
                    _FilterChip(
                      label: meta.value.label,
                      icon: meta.value.icon,
                      selected: _types.contains(meta.key),
                      onTap: () => setState(
                        () => _types.contains(meta.key)
                            ? _types.remove(meta.key)
                            : _types.add(meta.key),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              _sectionLabel('Status', isDark),
              Wrap(
                spacing: 8,
                children: [
                  _FilterChip(
                    label: 'Delivered',
                    icon: Icons.check_circle_rounded,
                    selected: _statuses.contains(TransactionStatus.success),
                    onTap: () => setState(
                      () => _toggle(_statuses, TransactionStatus.success),
                    ),
                  ),
                  _FilterChip(
                    label: 'Pending',
                    icon: Icons.schedule_rounded,
                    selected: _statuses.contains(TransactionStatus.pending),
                    onTap: () => setState(
                      () => _toggle(_statuses, TransactionStatus.pending),
                    ),
                  ),
                  _FilterChip(
                    label: 'Failed',
                    icon: Icons.cancel_rounded,
                    selected: _statuses.contains(TransactionStatus.failed),
                    onTap: () => setState(
                      () => _toggle(_statuses, TransactionStatus.failed),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _sectionLabel('Direction', isDark),
              Wrap(
                spacing: 8,
                children: [
                  _FilterChip(
                    label: 'All',
                    icon: Icons.swap_vert_rounded,
                    selected: _direction == HistoryDirection.all,
                    onTap: () =>
                        setState(() => _direction = HistoryDirection.all),
                  ),
                  _FilterChip(
                    label: 'Money in',
                    icon: Icons.south_west_rounded,
                    selected: _direction == HistoryDirection.moneyIn,
                    onTap: () =>
                        setState(() => _direction = HistoryDirection.moneyIn),
                  ),
                  _FilterChip(
                    label: 'Money out',
                    icon: Icons.north_east_rounded,
                    selected: _direction == HistoryDirection.moneyOut,
                    onTap: () =>
                        setState(() => _direction = HistoryDirection.moneyOut),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _sectionLabel('Date range', isDark),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FilterChip(
                    label: 'Any time',
                    icon: Icons.all_inclusive_rounded,
                    selected: _datePreset == 0,
                    onTap: () => _pickPreset(0),
                  ),
                  _FilterChip(
                    label: '7 days',
                    icon: Icons.date_range_rounded,
                    selected: _datePreset == 1,
                    onTap: () => _pickPreset(1),
                  ),
                  _FilterChip(
                    label: '30 days',
                    icon: Icons.date_range_rounded,
                    selected: _datePreset == 2,
                    onTap: () => _pickPreset(2),
                  ),
                  _FilterChip(
                    label: '90 days',
                    icon: Icons.date_range_rounded,
                    selected: _datePreset == 3,
                    onTap: () => _pickPreset(3),
                  ),
                  _FilterChip(
                    label: _range != null && _datePreset == 4
                        ? '${fmt.format(_range!.start)} – '
                              '${fmt.format(_range!.end)}'
                        : 'Custom…',
                    icon: Icons.edit_calendar_rounded,
                    selected: _datePreset == 4,
                    onTap: () => _pickPreset(4),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _sectionLabel('Amount (GHS)', isDark),
              Row(
                children: [
                  Expanded(child: _amountField(_minAmount, 'Min', isDark)),
                  const SizedBox(width: 12),
                  Expanded(child: _amountField(_maxAmount, 'Max', isDark)),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_compose()),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Apply filters',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggle(Set<TransactionStatus> set, TransactionStatus value) {
    set.contains(value) ? set.remove(value) : set.add(value);
  }

  Widget _sectionLabel(String label, bool isDark) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
        color: isDark ? Colors.white38 : const Color(0xFF9B95A8),
      ),
    ),
  );

  Widget _amountField(
    TextEditingController controller,
    String hint,
    bool isDark,
  ) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    style: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: isDark ? Colors.white : const Color(0xFF241E33),
    ),
    decoration: InputDecoration(
      hintText: hint,
      prefixText: 'GH₵ ',
      hintStyle: TextStyle(
        color: isDark ? Colors.white30 : const Color(0xFFB7B1C4),
      ),
      filled: true,
      fillColor: isDark ? Colors.white10 : const Color(0xFFF5F3F8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : (isDark ? Colors.white10 : const Color(0xFFF3F0F7)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : (isDark ? Colors.white12 : const Color(0xFFE4E0EC)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected
                  ? Colors.white
                  : (isDark ? Colors.white70 : const Color(0xFF5A526B)),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected
                    ? Colors.white
                    : (isDark ? Colors.white70 : const Color(0xFF5A526B)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
