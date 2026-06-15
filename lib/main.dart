import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'export_download.dart';
import 'reminder_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final reminderService = ReminderService();
  await reminderService.initialize();
  runApp(MiaoJiZhangApp(reminderService: reminderService));
}

const _bgColor = Color(0xFFFFF7F2);
const _primaryColor = Color(0xFFFF7F96);
const _accentColor = Color(0xFFFFC46B);
const _greenColor = Color(0xFF4CAF7A);
const _textColor = Color(0xFF5B3A32);
const _mutedColor = Color(0xFF9A6A5C);
const _softColor = Color(0xFFFFF0E8);

enum RecordType { expense, income }

enum StatsRange { day, week, month, year }

class MiaoJiZhangApp extends StatefulWidget {
  const MiaoJiZhangApp({super.key, required this.reminderService});

  final ReminderService reminderService;

  @override
  State<MiaoJiZhangApp> createState() => _MiaoJiZhangAppState();
}

class _MiaoJiZhangAppState extends State<MiaoJiZhangApp> {
  late final AppStore store;

  @override
  void initState() {
    super.initState();
    store = AppStore(reminderService: widget.reminderService);
    store.load();
  }

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      store: store,
      child: MaterialApp(
        title: '喵记账',
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        theme: ThemeData(
          scaffoldBackgroundColor: Colors.transparent,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
          ),
          colorScheme: ColorScheme.fromSeed(seedColor: _primaryColor),
          fontFamily: 'Roboto',
          useMaterial3: true,
        ),
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(textScaler: TextScaler.noScaling),
            child: PageBackground(child: child ?? const SizedBox.shrink()),
          );
        },
        home: const LoginPage(),
      ),
    );
  }
}

class PageBackground extends StatelessWidget {
  const PageBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: _bgColor),
        Image.asset(
          'assets/images/page_bg.png',
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
        child,
      ],
    );
  }
}

Route<T> appPageRoute<T>(WidgetBuilder builder) {
  return MaterialPageRoute<T>(
    builder: (context) => PageBackground(child: builder(context)),
  );
}

class AppScope extends InheritedNotifier<AppStore> {
  const AppScope({super.key, required AppStore store, required super.child})
    : super(notifier: store);

  static AppStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found');
    return scope!.notifier!;
  }
}

class AppStore extends ChangeNotifier {
  static const _storageKey = 'miao_jizhang_data_v2';
  static const _legacyStorageKey = 'miao_jizhang_data_v1';

  AppStore({required this.reminderService});

  final ReminderService reminderService;

  bool isLoaded = false;
  bool reminderEnabled = true;
  int reminderHour = 22;
  int reminderMinute = 0;
  String reminderTitle = '喵记账';
  String reminderMessage = '喵~今天你记账了吗？';
  String profileNickname = '猫猫记账员';
  String? profileAvatarDataUri;
  double monthlyBudget = 0;
  String savingGoalName = '储蓄目标';
  double savingGoalTarget = 0;
  double savingGoalSaved = 0;
  final List<AccountRecord> records = [];
  final List<CategoryBudget> categoryBudgets = [];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) {
      await prefs.remove(_legacyStorageKey);
      _resetToEmpty();
      isLoaded = true;
      await _save();
      await _syncReminderSchedule();
      notifyListeners();
      return;
    }

    final data = jsonDecode(raw) as Map<String, dynamic>;
    monthlyBudget = (data['monthlyBudget'] as num?)?.toDouble() ?? 0;
    savingGoalName = data['savingGoalName'] as String? ?? '储蓄目标';
    savingGoalTarget = (data['savingGoalTarget'] as num?)?.toDouble() ?? 0;
    savingGoalSaved = (data['savingGoalSaved'] as num?)?.toDouble() ?? 0;
    reminderEnabled = data['reminderEnabled'] as bool? ?? true;
    reminderHour = ((data['reminderHour'] as num?)?.toInt() ?? 22).clamp(0, 23);
    reminderMinute = ((data['reminderMinute'] as num?)?.toInt() ?? 0).clamp(
      0,
      59,
    );
    reminderTitle =
        (data['reminderTitle'] as String?)?.trim().isNotEmpty == true
        ? (data['reminderTitle'] as String).trim()
        : '喵记账';
    reminderMessage =
        (data['reminderMessage'] as String?)?.trim().isNotEmpty == true
        ? (data['reminderMessage'] as String).trim()
        : '喵~今天你记账了吗？';
    profileNickname =
        (data['profileNickname'] as String?)?.trim().isNotEmpty == true
        ? (data['profileNickname'] as String).trim()
        : '猫猫记账员';
    profileAvatarDataUri =
        (data['profileAvatarDataUri'] as String?)?.trim().isNotEmpty == true
        ? data['profileAvatarDataUri'] as String
        : null;
    categoryBudgets
      ..clear()
      ..addAll(
        (data['categoryBudgets'] as List<dynamic>? ?? []).map(
          (item) => CategoryBudget.fromJson(item as Map<String, dynamic>),
        ),
      );
    records
      ..clear()
      ..addAll(
        (data['records'] as List<dynamic>? ?? [])
            .map((item) => AccountRecord.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
    records.sort((a, b) => b.date.compareTo(a.date));
    isLoaded = true;
    await _syncReminderSchedule();
    notifyListeners();
  }

  Future<void> addRecord(AccountRecord record) async {
    records.insert(0, record);
    records.sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
    await _save();
  }

  Future<void> addRecords(List<AccountRecord> importedRecords) async {
    if (importedRecords.isEmpty) return;
    records.addAll(importedRecords);
    records.sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
    await _save();
  }

  Future<void> updateRecord(AccountRecord updatedRecord) async {
    final index = records.indexWhere((record) => record.id == updatedRecord.id);
    if (index == -1) return;
    records[index] = updatedRecord;
    records.sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
    await _save();
  }

  Future<void> deleteRecord(String id) async {
    records.removeWhere((record) => record.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> updateBudget(double value) async {
    monthlyBudget = math.max(0, value);
    notifyListeners();
    await _save();
  }

  Future<void> upsertCategoryBudget(CategoryBudget budget) async {
    final index = categoryBudgets.indexWhere((item) => item.id == budget.id);
    if (index == -1) {
      categoryBudgets.add(budget);
    } else {
      categoryBudgets[index] = budget;
    }
    notifyListeners();
    await _save();
  }

  Future<void> deleteCategoryBudget(String id) async {
    categoryBudgets.removeWhere((budget) => budget.id == id);
    notifyListeners();
    await _save();
  }

  CategoryBudget? categoryBudgetById(String id) {
    for (final budget in categoryBudgets) {
      if (budget.id == id) return budget;
    }
    return null;
  }

  double categoryMonthExpense(String category) {
    return currentMonthRecords
        .where(
          (record) =>
              record.type == RecordType.expense && record.category == category,
        )
        .fold<double>(0, (sum, record) => sum + record.amount);
  }

  Future<void> updateSavingGoal({
    required String name,
    required double target,
    required double saved,
  }) async {
    savingGoalName = name.trim().isEmpty ? '储蓄目标' : name.trim();
    savingGoalTarget = math.max(0, target);
    savingGoalSaved = math.max(0, saved);
    notifyListeners();
    await _save();
  }

  Future<void> addSaving(double value) async {
    savingGoalSaved = math.max(0, savingGoalSaved + value);
    notifyListeners();
    await _save();
  }

  Future<void> setReminder(bool value) async {
    reminderEnabled = value;
    notifyListeners();
    await _save();
    await _syncReminderSchedule();
  }

  Future<void> updateReminderSettings({
    required bool enabled,
    required int hour,
    required int minute,
    required String title,
    required String message,
  }) async {
    reminderEnabled = enabled;
    reminderHour = hour.clamp(0, 23).toInt();
    reminderMinute = minute.clamp(0, 59).toInt();
    reminderTitle = title.trim().isEmpty ? '喵记账' : title.trim();
    reminderMessage = message.trim().isEmpty ? '喵~今天你记账了吗？' : message.trim();
    notifyListeners();
    await _save();
    await _syncReminderSchedule();
  }

  Future<void> updateProfile({required String nickname, String? avatar}) async {
    profileNickname = nickname.trim().isEmpty ? '猫猫记账员' : nickname.trim();
    profileAvatarDataUri = avatar?.trim().isNotEmpty == true ? avatar : null;
    notifyListeners();
    await _save();
  }

  Future<void> clearAll() async {
    _resetToEmpty();
    notifyListeners();
    await _save();
    await _syncReminderSchedule();
  }

  double get monthExpense => _sumCurrentMonth(RecordType.expense);
  double get monthIncome => _sumCurrentMonth(RecordType.income);
  double get monthBalance => monthIncome - monthExpense;
  double get lastMonthExpense => _sumMonthOffset(RecordType.expense, -1);
  double get lastMonthIncome => _sumMonthOffset(RecordType.income, -1);
  double get lastMonthBalance => lastMonthIncome - lastMonthExpense;
  double get categoryBudgetTotal =>
      categoryBudgets.fold<double>(0, (sum, budget) => sum + budget.limit);
  double get effectiveMonthlyBudget =>
      monthlyBudget > 0 ? monthlyBudget : categoryBudgetTotal;
  double get budgetLeft => effectiveMonthlyBudget - monthExpense;
  double get budgetRatio => effectiveMonthlyBudget <= 0
      ? 0
      : (monthExpense / effectiveMonthlyBudget).clamp(0, 1);
  double get goalRatio => savingGoalTarget <= 0
      ? 0
      : (savingGoalSaved / savingGoalTarget).clamp(0, 1);

  List<AccountRecord> get currentMonthRecords {
    final now = DateTime.now();
    return records
        .where(
          (record) =>
              record.date.year == now.year && record.date.month == now.month,
        )
        .toList();
  }

  List<AccountRecord> get recentRecords => records.take(8).toList();

  AccountRecord? recordById(String id) {
    for (final record in records) {
      if (record.id == id) return record;
    }
    return null;
  }

  List<CategoryStat> get expenseStats {
    return statsFor(RecordType.expense, StatsRange.month);
  }

  List<AccountRecord> recordsForRange(
    StatsRange range, {
    DateTime? anchorDate,
  }) {
    final period = statsPeriodFor(range, anchorDate: anchorDate);

    return records
        .where(
          (record) =>
              !record.date.isBefore(period.start) &&
              record.date.isBefore(period.end),
        )
        .toList();
  }

  double expenseTotalFor(StatsRange range, {DateTime? anchorDate}) {
    return totalFor(RecordType.expense, range, anchorDate: anchorDate);
  }

  List<CategoryStat> expenseStatsFor(StatsRange range, {DateTime? anchorDate}) {
    return statsFor(RecordType.expense, range, anchorDate: anchorDate);
  }

  double totalFor(RecordType type, StatsRange range, {DateTime? anchorDate}) {
    return recordsForRange(range, anchorDate: anchorDate)
        .where((record) => record.type == type)
        .fold<double>(0, (sum, record) => sum + record.amount);
  }

  List<CategoryStat> statsFor(
    RecordType type,
    StatsRange range, {
    DateTime? anchorDate,
  }) {
    final totals = <String, double>{};
    final icons = <String, IconData>{};
    for (final record in recordsForRange(range, anchorDate: anchorDate)) {
      if (record.type != type) continue;
      totals.update(
        record.category,
        (value) => value + record.amount,
        ifAbsent: () => record.amount,
      );
      icons[record.category] = record.icon;
    }
    final total = totals.values.fold<double>(0, (sum, item) => sum + item);
    final stats = totals.entries
        .map(
          (entry) => CategoryStat(
            name: entry.key,
            amount: entry.value,
            ratio: total <= 0 ? 0 : entry.value / total,
            icon: icons[entry.key] ?? Icons.more_horiz_rounded,
          ),
        )
        .toList();
    stats.sort((a, b) => b.amount.compareTo(a.amount));
    return stats;
  }

  int get accountingDays {
    if (records.isEmpty) return 0;
    final uniqueDays =
        records
            .map(
              (record) => DateTime(
                record.date.year,
                record.date.month,
                record.date.day,
              ),
            )
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    var streak = 0;
    var cursor = DateTime.now();
    cursor = DateTime(cursor.year, cursor.month, cursor.day);
    for (final day in uniqueDays) {
      if (day == cursor) {
        streak += 1;
        cursor = cursor.subtract(const Duration(days: 1));
      } else if (day.isBefore(cursor)) {
        break;
      }
    }
    return streak == 0 ? uniqueDays.length : streak;
  }

  int get totalAccountingDays {
    return records
        .map(
          (record) =>
              DateTime(record.date.year, record.date.month, record.date.day),
        )
        .toSet()
        .length;
  }

  double _sumCurrentMonth(RecordType type) {
    return currentMonthRecords
        .where((record) => record.type == type)
        .fold<double>(0, (sum, record) => sum + record.amount);
  }

  double _sumMonthOffset(RecordType type, int monthOffset) {
    final now = DateTime.now();
    final target = DateTime(now.year, now.month + monthOffset);
    return records
        .where(
          (record) =>
              record.type == type &&
              record.date.year == target.year &&
              record.date.month == target.month,
        )
        .fold<double>(0, (sum, record) => sum + record.amount);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'monthlyBudget': monthlyBudget,
      'savingGoalName': savingGoalName,
      'savingGoalTarget': savingGoalTarget,
      'savingGoalSaved': savingGoalSaved,
      'categoryBudgets': categoryBudgets
          .map((budget) => budget.toJson())
          .toList(),
      'reminderEnabled': reminderEnabled,
      'reminderHour': reminderHour,
      'reminderMinute': reminderMinute,
      'reminderTitle': reminderTitle,
      'reminderMessage': reminderMessage,
      'profileNickname': profileNickname,
      'profileAvatarDataUri': profileAvatarDataUri,
      'records': records.map((record) => record.toJson()).toList(),
    };
    await prefs.setString(_storageKey, jsonEncode(data));
  }

  Future<void> _syncReminderSchedule() {
    return reminderService.setDailyReminderEnabled(
      reminderEnabled,
      hour: reminderHour,
      minute: reminderMinute,
      title: reminderTitle,
      body: reminderMessage,
    );
  }

  void _resetToEmpty() {
    monthlyBudget = 0;
    savingGoalName = '储蓄目标';
    savingGoalTarget = 0;
    savingGoalSaved = 0;
    reminderEnabled = true;
    reminderHour = 22;
    reminderMinute = 0;
    reminderTitle = '喵记账';
    reminderMessage = '喵~今天你记账了吗？';
    profileNickname = '猫猫记账员';
    profileAvatarDataUri = null;
    records.clear();
    categoryBudgets.clear();
  }
}

class AccountRecord {
  const AccountRecord({
    required this.id,
    required this.type,
    required this.category,
    required this.icon,
    required this.amount,
    required this.note,
    required this.date,
    this.photoDataUris = const [],
  });

  final String id;
  final RecordType type;
  final String category;
  final IconData icon;
  final double amount;
  final String note;
  final DateTime date;
  final List<String> photoDataUris;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'category': category,
    'amount': amount,
    'note': note,
    'date': date.toIso8601String(),
    'photoDataUris': photoDataUris,
  };

  factory AccountRecord.fromJson(Map<String, dynamic> json) {
    final type = json['type'] == 'income'
        ? RecordType.income
        : RecordType.expense;
    final category = normalizeCategoryName(json['category'] as String? ?? '其他');
    return AccountRecord(
      id: json['id'] as String,
      type: type,
      category: category,
      icon: iconForCategory(type, category),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      note: json['note'] as String? ?? '',
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      photoDataUris:
          (json['photoDataUris'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          const [],
    );
  }
}

class CategoryBudget {
  const CategoryBudget({
    required this.id,
    required this.category,
    required this.limit,
  });

  final String id;
  final String category;
  final double limit;

  IconData get icon => iconForCategory(RecordType.expense, category);

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'limit': limit,
  };

  factory CategoryBudget.fromJson(Map<String, dynamic> json) {
    return CategoryBudget(
      id:
          json['id'] as String? ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      category: normalizeCategoryName(json['category'] as String? ?? '其他'),
      limit: (json['limit'] as num?)?.toDouble() ?? 0,
    );
  }
}

class CategoryOption {
  const CategoryOption(this.name, this.icon, {this.imageAsset});

  final String name;
  final IconData icon;
  final String? imageAsset;
}

class CategoryStat {
  const CategoryStat({
    required this.name,
    required this.amount,
    required this.ratio,
    required this.icon,
  });

  final String name;
  final double amount;
  final double ratio;
  final IconData icon;
}

class StatsPeriod {
  const StatsPeriod({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

class TrendPoint {
  const TrendPoint({
    required this.label,
    required this.detailLabel,
    required this.expense,
    required this.income,
  });

  final String label;
  final String detailLabel;
  final double expense;
  final double income;

  double get balance => income - expense;

  double amountFor(RecordType type) {
    return type == RecordType.expense ? expense : income;
  }
}

class HomeRecordFilter {
  const HomeRecordFilter({
    required this.month,
    this.startDate,
    this.endDate,
    this.type,
    this.category,
    this.expenseCategories,
    this.incomeCategories,
    this.minAmount = 0,
    this.maxAmount = 9999999,
    this.noteKeyword = '',
    this.onlyWithPhotos = false,
  });

  final DateTime month;
  final DateTime? startDate;
  final DateTime? endDate;
  final RecordType? type;
  final String? category;
  final Set<String>? expenseCategories;
  final Set<String>? incomeCategories;
  final double minAmount;
  final double maxAmount;
  final String noteKeyword;
  final bool onlyWithPhotos;

  DateTime get effectiveStartDate => dateOnly(startDate ?? monthStart(month));
  DateTime get effectiveEndDate => dateOnly(endDate ?? monthEnd(month));

  HomeRecordFilter copyWith({
    DateTime? month,
    Object? startDate = _filterNoChange,
    Object? endDate = _filterNoChange,
    Object? type = _filterNoChange,
    Object? category = _filterNoChange,
    Object? expenseCategories = _filterNoChange,
    Object? incomeCategories = _filterNoChange,
    double? minAmount,
    double? maxAmount,
    String? noteKeyword,
    bool? onlyWithPhotos,
  }) {
    return HomeRecordFilter(
      month: month ?? this.month,
      startDate: startDate == _filterNoChange
          ? this.startDate
          : startDate as DateTime?,
      endDate: endDate == _filterNoChange ? this.endDate : endDate as DateTime?,
      type: type == _filterNoChange ? this.type : type as RecordType?,
      category: category == _filterNoChange
          ? this.category
          : category as String?,
      expenseCategories: expenseCategories == _filterNoChange
          ? this.expenseCategories
          : (expenseCategories as Set<String>?)?.toSet(),
      incomeCategories: incomeCategories == _filterNoChange
          ? this.incomeCategories
          : (incomeCategories as Set<String>?)?.toSet(),
      minAmount: minAmount ?? this.minAmount,
      maxAmount: maxAmount ?? this.maxAmount,
      noteKeyword: noteKeyword ?? this.noteKeyword,
      onlyWithPhotos: onlyWithPhotos ?? this.onlyWithPhotos,
    );
  }
}

const Object _filterNoChange = Object();

Set<String>? toggledCategorySet(Set<String>? current, String category) {
  final next = {...?current};
  if (next.contains(category)) {
    next.remove(category);
  } else {
    next.add(category);
  }
  return next.isEmpty ? null : next;
}

Set<String>? categoryNameSet(List<CategoryOption> categories) {
  if (categories.isEmpty) return null;
  return categories.map((category) => category.name).toSet();
}

bool areSameCategorySet(Set<String>? left, Set<String>? right) {
  if (left == null || right == null) return left == right;
  return left.length == right.length && left.containsAll(right);
}

class AmountInputFormatter extends TextInputFormatter {
  final RegExp _pattern = RegExp(r'^\d{0,9}(\.\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty || _pattern.hasMatch(newValue.text)) {
      return newValue;
    }
    return oldValue;
  }
}

const expenseCategories = [
  CategoryOption('餐饮', Icons.restaurant_rounded),
  CategoryOption('交通', Icons.directions_bus_rounded),
  CategoryOption('购物', Icons.shopping_bag_rounded),
  CategoryOption(
    '谷子',
    Icons.auto_awesome_rounded,
    imageAsset: 'assets/images/guzi_avatar.png',
  ),
  CategoryOption('零食', Icons.cookie_rounded),
  CategoryOption('水果', Icons.apple_rounded),
  CategoryOption('饮品', Icons.local_cafe_rounded),
  CategoryOption('娱乐', Icons.sports_esports_rounded),
  CategoryOption('日用', Icons.cleaning_services_rounded),
  CategoryOption('宠物', Icons.pets_rounded),
  CategoryOption('水电', Icons.bolt_rounded),
  CategoryOption('通讯', Icons.phone_iphone_rounded),
  CategoryOption('恋爱', Icons.favorite_border_rounded),
  CategoryOption('追星', Icons.star_rounded),
  CategoryOption('麻将', Icons.casino_rounded),
  CategoryOption('房租', Icons.apartment_rounded),
  CategoryOption('借出', Icons.call_made_rounded),
  CategoryOption('钓鱼', Icons.phishing_rounded),
  CategoryOption('美容', Icons.spa_rounded),
  CategoryOption('烟酒', Icons.liquor_rounded),
  CategoryOption('医疗', Icons.local_hospital_rounded),
  CategoryOption('学习', Icons.menu_book_rounded),
  CategoryOption('运动', Icons.fitness_center_rounded),
  CategoryOption('旅行', Icons.flight_takeoff_rounded),
  CategoryOption('美妆', Icons.face_retouching_natural_rounded),
  CategoryOption('服饰', Icons.checkroom_rounded),
  CategoryOption('家居', Icons.chair_rounded),
  CategoryOption('数码', Icons.devices_rounded),
  CategoryOption('红包', Icons.payments_rounded),
  CategoryOption('还款', Icons.credit_card_rounded),
  CategoryOption('公益', Icons.volunteer_activism_rounded),
  CategoryOption('维修', Icons.build_circle_rounded),
  CategoryOption('礼物', Icons.card_giftcard_rounded),
  CategoryOption('住房', Icons.home_work_rounded),
  CategoryOption('汽车', Icons.directions_car_rounded),
  CategoryOption('其他', Icons.more_horiz_rounded),
];

const incomeCategories = [
  CategoryOption('生活费', Icons.account_balance_wallet_rounded),
  CategoryOption('卖闲置', Icons.sell_rounded),
  CategoryOption('工资', Icons.work_rounded),
  CategoryOption('兼职', Icons.storefront_rounded),
  CategoryOption('年终奖', Icons.emoji_events_rounded),
  CategoryOption('理财', Icons.trending_up_rounded),
  CategoryOption('红包', Icons.payments_rounded),
  CategoryOption('报销', Icons.receipt_long_rounded),
  CategoryOption('退款', Icons.assignment_return_rounded),
  CategoryOption('租金', Icons.apartment_rounded),
  CategoryOption('补贴', Icons.savings_rounded),
  CategoryOption('借入', Icons.call_received_rounded),
  CategoryOption('还款', Icons.credit_score_rounded),
  CategoryOption('彩票', Icons.confirmation_number_rounded),
  CategoryOption('娱乐', Icons.sports_esports_rounded),
  CategoryOption('麻将', Icons.casino_rounded),
  CategoryOption('恋爱', Icons.favorite_border_rounded),
  CategoryOption('奖学金', Icons.school_rounded),
  CategoryOption('赔款', Icons.receipt_rounded),
  CategoryOption('其他', Icons.more_horiz_rounded),
];

IconData iconForCategory(RecordType type, String category) {
  final normalizedCategory = normalizeCategoryName(category);
  final source = type == RecordType.expense
      ? expenseCategories
      : incomeCategories;
  for (final option in source) {
    if (option.name == normalizedCategory) return option.icon;
  }
  return Icons.more_horiz_rounded;
}

String normalizeCategoryName(String category) {
  if (category == '育儿') return '水果';
  if (category == '人情') return '饮品';
  if (category == '保险') return '红包';
  if (category == '奖金') return '年终奖';
  return category;
}

String? categoryImageAsset(String category) {
  return normalizeCategoryName(category) == '谷子'
      ? 'assets/images/guzi_avatar.png'
      : null;
}

Color categoryAccentColor(String category) {
  switch (normalizeCategoryName(category)) {
    case '餐饮':
      return const Color(0xFFFF6B7A);
    case '交通':
      return const Color(0xFF4BA7FF);
    case '购物':
      return const Color(0xFFFF8A59);
    case '谷子':
      return const Color(0xFF7B8CFF);
    case '零食':
      return const Color(0xFFFFB33F);
    case '水果':
      return const Color(0xFFFF5A6E);
    case '饮品':
      return const Color(0xFF5FC9C2);
    case '娱乐':
      return const Color(0xFF8B7CFF);
    case '日用':
      return const Color(0xFF4EC7A2);
    case '宠物':
      return const Color(0xFFFF9A52);
    case '水电':
      return const Color(0xFFFFC247);
    case '通讯':
      return const Color(0xFF55B6FF);
    case '恋爱':
      return const Color(0xFFFF7AA7);
    case '追星':
      return const Color(0xFFFFC247);
    case '麻将':
      return const Color(0xFF47B98A);
    case '房租':
      return const Color(0xFFFF9960);
    case '借出':
      return const Color(0xFF6EA8FF);
    case '钓鱼':
      return const Color(0xFF46B6C8);
    case '美容':
      return const Color(0xFFFF77B7);
    case '烟酒':
      return const Color(0xFF9A88FF);
    case '医疗':
      return const Color(0xFFFF5D78);
    case '学习':
      return const Color(0xFF7E79FF);
    case '运动':
      return const Color(0xFF56C37E);
    case '旅行':
      return const Color(0xFF59A8FF);
    case '美妆':
      return const Color(0xFFFF77A8);
    case '服饰':
      return const Color(0xFFFF8A72);
    case '家居':
      return const Color(0xFF8AC46D);
    case '数码':
      return const Color(0xFF5E8CFF);
    case '还款':
      return const Color(0xFF6D89FF);
    case '公益':
      return const Color(0xFFFF6E93);
    case '维修':
      return const Color(0xFF8E97A6);
    case '礼物':
      return const Color(0xFFFF75A5);
    case '住房':
      return const Color(0xFF9C7BFF);
    case '汽车':
      return const Color(0xFF4BA7FF);
    case '生活费':
      return const Color(0xFFFFA64D);
    case '卖闲置':
      return const Color(0xFF58BE8B);
    case '工资':
      return const Color(0xFF5B8CFF);
    case '兼职':
      return const Color(0xFFFF8C4B);
    case '年终奖':
      return const Color(0xFFFFC23F);
    case '理财':
      return const Color(0xFF49B978);
    case '红包':
      return const Color(0xFFFF5C66);
    case '报销':
      return const Color(0xFF56A9FF);
    case '退款':
      return const Color(0xFF54C7B4);
    case '租金':
      return const Color(0xFFFF9960);
    case '补贴':
      return const Color(0xFFFFB340);
    case '借入':
      return const Color(0xFF6EA8FF);
    case '彩票':
      return const Color(0xFFFF8B55);
    case '奖学金':
      return const Color(0xFF6F8DFF);
    case '赔款':
      return const Color(0xFFFF7D63);
    default:
      return const Color(0xFFFF7F96);
  }
}

class CatPawMark extends StatelessWidget {
  const CatPawMark({super.key, this.size = 22, this.color = _primaryColor});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final toeSize = size * 0.26;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: size * 0.14,
            child: Container(
              width: size * 0.46,
              height: size * 0.38,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          Positioned(
            left: size * 0.08,
            top: size * 0.28,
            child: _PawToe(size: toeSize, color: color),
          ),
          Positioned(
            left: size * 0.3,
            top: size * 0.08,
            child: _PawToe(size: toeSize, color: color),
          ),
          Positioned(
            right: size * 0.3,
            top: size * 0.08,
            child: _PawToe(size: toeSize, color: color),
          ),
          Positioned(
            right: size * 0.08,
            top: size * 0.28,
            child: _PawToe(size: toeSize, color: color),
          ),
        ],
      ),
    );
  }
}

class _PawToe extends StatelessWidget {
  const _PawToe({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class CatEarCorner extends StatelessWidget {
  const CatEarCorner({
    super.key,
    this.size = 48,
    this.color = const Color(0xFFFFD6C9),
    this.strokeColor = const Color(0x22FF7F96),
  });

  final double size;
  final Color color;
  final Color strokeColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 0.64,
      child: CustomPaint(painter: CatEarCornerPainter(color, strokeColor)),
    );
  }
}

class CatEarCornerPainter extends CustomPainter {
  const CatEarCornerPainter(this.color, this.strokeColor);

  final Color color;
  final Color strokeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final leftEar = Path()
      ..moveTo(size.width * 0.08, size.height)
      ..lineTo(size.width * 0.28, size.height * 0.08)
      ..lineTo(size.width * 0.48, size.height)
      ..close();
    final rightEar = Path()
      ..moveTo(size.width * 0.48, size.height)
      ..lineTo(size.width * 0.7, size.height * 0.08)
      ..lineTo(size.width * 0.92, size.height)
      ..close();
    canvas.drawPath(leftEar, fill);
    canvas.drawPath(rightEar, fill);
    canvas.drawPath(leftEar, stroke);
    canvas.drawPath(rightEar, stroke);
  }

  @override
  bool shouldRepaint(covariant CatEarCornerPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeColor != strokeColor;
  }
}

class CatFaceBadge extends StatelessWidget {
  const CatFaceBadge({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.08),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.34),
        boxShadow: softShadow(),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28),
        child: Image.asset('assets/images/app_icon.png', fit: BoxFit.cover),
      ),
    );
  }
}

class CatNavIcon extends StatelessWidget {
  const CatNavIcon({super.key, required this.icon, this.selected = false});

  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 30,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (selected)
            Positioned(
              top: 0,
              child: CatPawMark(
                size: 28,
                color: _primaryColor.withValues(alpha: 0.18),
              ),
            ),
          Icon(
            icon,
            size: 24,
            color: selected ? _primaryColor : const Color(0xFFB89A90),
          ),
        ],
      ),
    );
  }
}

class CatEmptyBadge extends StatelessWidget {
  const CatEmptyBadge({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: const Color(0xFFFFEFE6),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFFD6C9), width: 1.4),
          ),
          child: Icon(icon, color: _primaryColor, size: 30),
        ),
        const Positioned(
          left: 10,
          top: -8,
          child: CatEarCorner(size: 38, color: Color(0xFFFFEFE6)),
        ),
      ],
    );
  }
}

class CatBackgroundPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final pawPaint = Paint()
      ..color = _primaryColor.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;
    final earPaint = Paint()
      ..color = _accentColor.withValues(alpha: 0.09)
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = _mutedColor.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final facePaint = Paint()
      ..color = _primaryColor.withValues(alpha: 0.075)
      ..style = PaintingStyle.fill;

    final paws = <({Offset center, double size, double rotation})>[
      (
        center: Offset(size.width * 0.88, size.height * 0.08),
        size: 24,
        rotation: -0.2,
      ),
      (
        center: Offset(size.width * 0.16, size.height * 0.18),
        size: 18,
        rotation: 0.3,
      ),
      (
        center: Offset(size.width * 0.74, size.height * 0.34),
        size: 22,
        rotation: -0.35,
      ),
      (
        center: Offset(size.width * 0.12, size.height * 0.52),
        size: 28,
        rotation: 0.18,
      ),
      (
        center: Offset(size.width * 0.84, size.height * 0.7),
        size: 24,
        rotation: 0.28,
      ),
      (
        center: Offset(size.width * 0.64, size.height * 0.76),
        size: 34,
        rotation: -0.12,
      ),
      (
        center: Offset(size.width * 0.28, size.height * 0.83),
        size: 20,
        rotation: -0.24,
      ),
      (
        center: Offset(size.width * 0.16, size.height * 0.9),
        size: 26,
        rotation: 0.34,
      ),
      (
        center: Offset(size.width * 0.9, size.height * 0.92),
        size: 30,
        rotation: -0.18,
      ),
    ];
    for (final paw in paws) {
      canvas.save();
      canvas.translate(paw.center.dx, paw.center.dy);
      canvas.rotate(paw.rotation);
      _drawPaw(canvas, Offset.zero, paw.size, pawPaint);
      canvas.restore();
    }
    _drawCatHead(
      canvas,
      Offset(size.width * 0.92, size.height * 0.52),
      42,
      facePaint,
      linePaint,
    );
    _drawCatHead(
      canvas,
      Offset(size.width * 0.08, size.height * 0.83),
      36,
      earPaint,
      linePaint,
    );
    _drawCatHead(
      canvas,
      Offset(size.width * 0.5, size.height * 0.64),
      28,
      Paint()
        ..color = _accentColor.withValues(alpha: 0.075)
        ..style = PaintingStyle.fill,
      linePaint,
    );
    _drawCatHead(
      canvas,
      Offset(size.width * 0.5, size.height * 0.82),
      58,
      Paint()
        ..color = _primaryColor.withValues(alpha: 0.06)
        ..style = PaintingStyle.fill,
      linePaint,
    );
    _drawFishBone(canvas, Offset(size.width * 0.18, size.height * 0.68), 42);
    _drawFishBone(canvas, Offset(size.width * 0.36, size.height * 0.74), 46);
    _drawFishBone(canvas, Offset(size.width * 0.78, size.height * 0.22), 34);
    _drawYarn(canvas, Offset(size.width * 0.1, size.height * 0.36), 18);
    _drawYarn(canvas, Offset(size.width * 0.78, size.height * 0.86), 24);
  }

  void _drawPaw(Canvas canvas, Offset center, double size, Paint paint) {
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(0, size * 0.18),
        width: size * 0.56,
        height: size * 0.46,
      ),
      paint,
    );
    final toeRadius = size * 0.13;
    for (final offset in [
      Offset(-size * 0.3, -size * 0.08),
      Offset(-size * 0.1, -size * 0.26),
      Offset(size * 0.1, -size * 0.26),
      Offset(size * 0.3, -size * 0.08),
    ]) {
      canvas.drawCircle(center + offset, toeRadius, paint);
    }
  }

  void _drawCatHead(
    Canvas canvas,
    Offset center,
    double size,
    Paint fillPaint,
    Paint linePaint,
  ) {
    final leftEar = Path()
      ..moveTo(center.dx - size * 0.48, center.dy - size * 0.05)
      ..lineTo(center.dx - size * 0.36, center.dy - size * 0.58)
      ..lineTo(center.dx - size * 0.12, center.dy - size * 0.22)
      ..close();
    final rightEar = Path()
      ..moveTo(center.dx + size * 0.48, center.dy - size * 0.05)
      ..lineTo(center.dx + size * 0.36, center.dy - size * 0.58)
      ..lineTo(center.dx + size * 0.12, center.dy - size * 0.22)
      ..close();
    canvas.drawPath(leftEar, fillPaint);
    canvas.drawPath(rightEar, fillPaint);
    canvas.drawCircle(center, size * 0.48, fillPaint);

    final eyePaint = Paint()
      ..color = _textColor.withValues(alpha: 0.13)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      center.translate(-size * 0.16, -size * 0.05),
      size * 0.035,
      eyePaint,
    );
    canvas.drawCircle(
      center.translate(size * 0.16, -size * 0.05),
      size * 0.035,
      eyePaint,
    );
    canvas.drawCircle(center.translate(0, size * 0.06), size * 0.025, eyePaint);
    canvas.drawLine(
      center.translate(-size * 0.26, size * 0.02),
      center.translate(-size * 0.46, -size * 0.02),
      linePaint,
    );
    canvas.drawLine(
      center.translate(size * 0.26, size * 0.02),
      center.translate(size * 0.46, -size * 0.02),
      linePaint,
    );
    canvas.drawLine(
      center.translate(-size * 0.24, size * 0.1),
      center.translate(-size * 0.44, size * 0.14),
      linePaint,
    );
    canvas.drawLine(
      center.translate(size * 0.24, size * 0.1),
      center.translate(size * 0.44, size * 0.14),
      linePaint,
    );
  }

  void _drawFishBone(Canvas canvas, Offset center, double width) {
    final paint = Paint()
      ..color = _accentColor.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.25);
    canvas.drawLine(Offset(-width * 0.38, 0), Offset(width * 0.38, 0), paint);
    for (final x in [-0.2, 0.0, 0.2]) {
      canvas.drawLine(
        Offset(width * x, 0),
        Offset(width * (x - 0.11), -width * 0.14),
        paint,
      );
      canvas.drawLine(
        Offset(width * x, 0),
        Offset(width * (x - 0.11), width * 0.14),
        paint,
      );
    }
    final tail = Path()
      ..moveTo(-width * 0.38, 0)
      ..lineTo(-width * 0.56, -width * 0.16)
      ..moveTo(-width * 0.38, 0)
      ..lineTo(-width * 0.56, width * 0.16);
    canvas.drawPath(tail, paint);
    canvas.drawCircle(Offset(width * 0.45, 0), width * 0.08, paint);
    canvas.restore();
  }

  void _drawYarn(Canvas canvas, Offset center, double radius) {
    final paint = Paint()
      ..color = _primaryColor.withValues(alpha: 0.055)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, paint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.76),
      -0.8,
      2.2,
      false,
      paint,
    );
    canvas.drawLine(
      center.translate(-radius * 0.72, radius * 0.2),
      center.translate(radius * 0.64, -radius * 0.34),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CatBackgroundPatternPainter oldDelegate) {
    return false;
  }
}

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/login_bg.png', fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: Container(color: Colors.white.withValues(alpha: 0.08)),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 70),
                ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset(
                    'assets/images/app_icon.png',
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 18),
                Image.asset(
                  'assets/images/app_name.png',
                  width: 184,
                  height: 74,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 6),
                const Text(
                  '每一笔，都值得被认真记录',
                  style: TextStyle(
                    fontSize: 16,
                    color: _mutedColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: CatPawPrimaryButton(
                          label: '开始记账',
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              appPageRoute((_) => const MainPage()),
                            );
                          },
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int currentIndex = 0;

  final List<String> titles = const ['首页', '预算', '记账', '统计', '我的'];

  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomePage(),
      const BudgetPage(),
      AddRecordPage(onSaved: () => setState(() => currentIndex = 0)),
      const StatsPage(),
      const MinePage(),
    ];

    return Scaffold(
      appBar: currentIndex == 0
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              centerTitle: true,
              title: Text(
                titles[currentIndex],
                style: const TextStyle(
                  color: _textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
              ),
            ),
      body: AppScope.of(context).isLoaded
          ? IndexedStack(index: currentIndex, children: pages)
          : const Center(child: CircularProgressIndicator()),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.brown.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
          ],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: _primaryColor,
          unselectedItemColor: const Color(0xFFB89A90),
          selectedFontSize: 12,
          unselectedFontSize: 12,
          onTap: (index) {
            if (index == currentIndex) return;
            setState(() => currentIndex = index);
          },
          items: const [
            BottomNavigationBarItem(
              icon: CatNavIcon(icon: Icons.home_rounded),
              activeIcon: CatNavIcon(icon: Icons.home_rounded, selected: true),
              label: '首页',
            ),
            BottomNavigationBarItem(
              icon: CatNavIcon(icon: Icons.pets_rounded),
              activeIcon: CatNavIcon(icon: Icons.pets_rounded, selected: true),
              label: '预算',
            ),
            BottomNavigationBarItem(
              icon: CatNavIcon(icon: Icons.add_circle_rounded),
              activeIcon: CatNavIcon(
                icon: Icons.add_circle_rounded,
                selected: true,
              ),
              label: '记账',
            ),
            BottomNavigationBarItem(
              icon: CatNavIcon(icon: Icons.pie_chart_rounded),
              activeIcon: CatNavIcon(
                icon: Icons.pie_chart_rounded,
                selected: true,
              ),
              label: '统计',
            ),
            BottomNavigationBarItem(
              icon: CatNavIcon(icon: Icons.person_rounded),
              activeIcon: CatNavIcon(
                icon: Icons.person_rounded,
                selected: true,
              ),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late HomeRecordFilter recordFilter = defaultHomeRecordFilter();

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final filteredRecords = store.records.where((record) {
      final recordDay = dateOnly(record.date);
      final dateMatches =
          !recordDay.isBefore(recordFilter.effectiveStartDate) &&
          !recordDay.isAfter(recordFilter.effectiveEndDate);
      final legacyTypeMatches =
          recordFilter.type == null || record.type == recordFilter.type;
      final legacyCategoryMatches =
          recordFilter.category == null ||
          record.category == recordFilter.category;
      final splitCategoryActive =
          recordFilter.expenseCategories != null ||
          recordFilter.incomeCategories != null;
      final splitCategoryMatches =
          !splitCategoryActive ||
          (record.type == RecordType.expense &&
              recordFilter.expenseCategories != null &&
              recordFilter.expenseCategories!.contains(record.category)) ||
          (record.type == RecordType.income &&
              recordFilter.incomeCategories != null &&
              recordFilter.incomeCategories!.contains(record.category));
      final amountMatches =
          record.amount >= recordFilter.minAmount &&
          record.amount <= recordFilter.maxAmount;
      final noteKeyword = recordFilter.noteKeyword.trim();
      final noteMatches =
          noteKeyword.isEmpty || record.note.contains(noteKeyword);
      final photoMatches =
          !recordFilter.onlyWithPhotos || record.photoDataUris.isNotEmpty;
      return dateMatches &&
          legacyTypeMatches &&
          legacyCategoryMatches &&
          splitCategoryMatches &&
          amountMatches &&
          noteMatches &&
          photoMatches;
    }).toList();
    final todayRecords = store.recordsForRange(StatsRange.day);
    final todayExpense = todayRecords
        .where((record) => record.type == RecordType.expense)
        .fold<double>(0, (sum, record) => sum + record.amount);
    final todayIncome = todayRecords
        .where((record) => record.type == RecordType.income)
        .fold<double>(0, (sum, record) => sum + record.amount);
    final todayBalance = todayIncome - todayExpense;

    return SafeArea(
      top: false,
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HomeCoverCard(),
            SizedBox(
              height: 116,
              child: Transform.translate(
                offset: const Offset(0, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: HomeSummaryMiniCard(
                        title: '本月支出',
                        amount: money(store.monthExpense),
                        compareText: monthCompareText(
                          store.monthExpense,
                          store.lastMonthExpense,
                        ),
                        backgroundColor: const Color(0xFFFFBFC9),
                        accentColor: _primaryColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: HomeSummaryMiniCard(
                        title: '本月收入',
                        amount: money(store.monthIncome),
                        compareText: monthCompareText(
                          store.monthIncome,
                          store.lastMonthIncome,
                        ),
                        backgroundColor: const Color(0xFFFFE2AE),
                        accentColor: const Color(0xFFE7A83A),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: HomeSummaryMiniCard(
                        title: '本月结余',
                        amount: money(store.monthBalance),
                        compareText: monthCompareText(
                          store.monthBalance,
                          store.lastMonthBalance,
                        ),
                        backgroundColor: const Color(0xFFD8EFCF),
                        accentColor: const Color(0xFF62AF72),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            HomeBudgetProgressCard(store: store),
            const SizedBox(height: 12),
            HomeTodayOverviewCard(
              expense: todayExpense,
              income: todayIncome,
              balance: todayBalance,
              onViewAll: () {
                Navigator.push(
                  context,
                  appPageRoute((_) => const TodayOverviewDetailPage()),
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const SectionTitle(title: '账单记录'),
                const Spacer(),
                HomeRecordFilterButton(
                  filter: recordFilter,
                  onChanged: (value) => setState(() => recordFilter = value),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (filteredRecords.isEmpty)
              EmptyState(
                icon: Icons.receipt_long_rounded,
                title: '${filterDateRangeLabel(recordFilter)}没有匹配记录',
                subtitle: '调整筛选条件或去「记账」页添加收支吧',
              )
            else
              RecordGroupList(records: filteredRecords),
          ],
        ),
      ),
    );
  }
}

class HomeRecordEmptyCard extends StatelessWidget {
  const HomeRecordEmptyCard({
    super.key,
    required this.height,
    this.title = '还没有记录',
    this.subtitle = '去「记账」页添加第一笔收支吧',
  });

  final double height;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(24),
        boxShadow: softShadow(),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Transform.scale(
              scale: 1.12,
              child: Image.asset(
                'assets/images/home_page.png',
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.02),
                    Colors.white.withValues(alpha: 0.34),
                    Colors.white.withValues(alpha: 0.78),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 42,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF8F8A84),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFB3A6A0),
                    fontSize: 13,
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

class HomeBudgetProgressCard extends StatelessWidget {
  const HomeBudgetProgressCard({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final ratio = store.effectiveMonthlyBudget <= 0 ? 0.0 : store.budgetRatio;
    final percent = '${(ratio * 100).round()}%';
    final leftTitle = store.budgetLeft >= 0 ? '剩余' : '超出';

    return HomeInfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HomeInfoCardTitle(title: '预算进度'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: HomeInfoMetric(
                  title: '总预算',
                  value: money(store.effectiveMonthlyBudget),
                ),
              ),
              HomeInfoMetric(
                title: leftTitle,
                value: money(store.budgetLeft.abs()),
                crossAxisAlignment: CrossAxisAlignment.end,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 14,
                    backgroundColor: const Color(0xFFFFE8D4),
                    color: const Color(0xFFFF9B4A),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                percent,
                style: const TextStyle(
                  color: _textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class HomeTodayOverviewCard extends StatelessWidget {
  const HomeTodayOverviewCard({
    super.key,
    required this.expense,
    required this.income,
    required this.balance,
    required this.onViewAll,
  });

  final double expense;
  final double income;
  final double balance;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return HomeInfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const HomeInfoCardTitle(title: '今日概览'),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onViewAll,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '查看全部',
                        style: TextStyle(
                          color: _mutedColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: _mutedColor,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: HomeTodayMetric(
                  title: '支出',
                  value: money(expense),
                  valueColor: _textColor,
                  backgroundColor: const Color(0xFFFFBFC9),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: HomeTodayMetric(
                  title: '收入',
                  value: money(income),
                  valueColor: _textColor,
                  backgroundColor: const Color(0xFFFFE2AE),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: HomeTodayMetric(
                  title: '结余',
                  value: money(balance),
                  valueColor: balance >= 0 ? _greenColor : _primaryColor,
                  backgroundColor: const Color(0xFFD8EFCF),
                ),
              ),
              const SizedBox(width: 10),
              const CatFaceBadge(size: 56),
            ],
          ),
        ],
      ),
    );
  }
}

class HomeInfoCard extends StatelessWidget {
  const HomeInfoCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF4DACD), width: 1.2),
        boxShadow: softShadow(),
      ),
      child: child,
    );
  }
}

class HomeInfoCardTitle extends StatelessWidget {
  const HomeInfoCardTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _textColor,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 6),
        const CatPawMark(size: 15, color: _accentColor),
      ],
    );
  }
}

class HomeInfoMetric extends StatelessWidget {
  const HomeInfoMetric({
    super.key,
    required this.title,
    required this.value,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final String title;
  final String value;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _mutedColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: _textColor,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class HomeTodayMetric extends StatelessWidget {
  const HomeTodayMetric({
    super.key,
    required this.title,
    required this.value,
    required this.valueColor,
    this.backgroundColor = const Color(0xFFF1FAEF),
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
  });

  final String title;
  final String value;
  final Color valueColor;
  final Color backgroundColor;
  final BorderRadiusGeometry borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: borderRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _mutedColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                color: valueColor,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HomeRecordFilterButton extends StatelessWidget {
  const HomeRecordFilterButton({
    super.key,
    required this.filter,
    required this.onChanged,
  });

  final HomeRecordFilter filter;
  final ValueChanged<HomeRecordFilter> onChanged;

  Future<void> _openFilter(BuildContext context) async {
    final selected = await Navigator.push<HomeRecordFilter>(
      context,
      appPageRoute((_) => HomeRecordFilterPage(initialFilter: filter)),
    );
    if (selected == null) return;
    onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final hasExtraFilter = !isDefaultHomeRecordFilter(filter);
    return PillActionButton(
      icon: Icons.tune_rounded,
      label: hasExtraFilter ? '筛选中' : '筛选',
      iconColor: hasExtraFilter ? _greenColor : _primaryColor,
      textColor: hasExtraFilter ? _greenColor : _textColor,
      onTap: () => _openFilter(context),
    );
  }
}

class PillActionButton extends StatelessWidget {
  const PillActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor = _primaryColor,
    this.textColor = _textColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color iconColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.only(left: 12, right: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFFD4DD)),
            boxShadow: softShadow(),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: iconColor),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: _mutedColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool isDefaultHomeRecordFilter(HomeRecordFilter filter) {
  final defaultFilter = defaultHomeRecordFilter();
  return filter.effectiveStartDate == defaultFilter.effectiveStartDate &&
      filter.effectiveEndDate == defaultFilter.effectiveEndDate &&
      filter.type == null &&
      filter.category == null &&
      filter.expenseCategories == null &&
      filter.incomeCategories == null &&
      filter.minAmount == 0 &&
      filter.maxAmount == 9999999 &&
      filter.noteKeyword.trim().isEmpty &&
      !filter.onlyWithPhotos;
}

HomeRecordFilter defaultHomeRecordFilter() {
  final now = DateTime.now();
  final month = DateTime(now.year, now.month);
  return HomeRecordFilter(
    month: month,
    startDate: monthStart(month),
    endDate: monthEnd(month),
  );
}

class HomeRecordFilterPage extends StatefulWidget {
  const HomeRecordFilterPage({super.key, required this.initialFilter});

  final HomeRecordFilter initialFilter;

  @override
  State<HomeRecordFilterPage> createState() => _HomeRecordFilterPageState();
}

class _HomeRecordFilterPageState extends State<HomeRecordFilterPage> {
  late HomeRecordFilter filter = widget.initialFilter;
  late final TextEditingController minAmountController;
  late final TextEditingController maxAmountController;
  late final TextEditingController noteController;

  @override
  void initState() {
    super.initState();
    minAmountController = TextEditingController(
      text: amountFilterText(widget.initialFilter.minAmount),
    );
    maxAmountController = TextEditingController(
      text: amountFilterText(widget.initialFilter.maxAmount),
    );
    noteController = TextEditingController(
      text: widget.initialFilter.noteKeyword,
    );
  }

  @override
  void dispose() {
    minAmountController.dispose();
    maxAmountController.dispose();
    noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final recordsInRange = store.records.where((record) {
      final recordDay = dateOnly(record.date);
      return !recordDay.isBefore(filter.effectiveStartDate) &&
          !recordDay.isAfter(filter.effectiveEndDate) &&
          record.amount >= filter.minAmount &&
          record.amount <= filter.maxAmount &&
          (filter.noteKeyword.trim().isEmpty ||
              record.note.contains(filter.noteKeyword.trim())) &&
          (!filter.onlyWithPhotos || record.photoDataUris.isNotEmpty);
    }).toList();
    final expenseCategoryNames = recordsInRange
        .where((record) => record.type == RecordType.expense)
        .map((record) => record.category)
        .toSet();
    final incomeCategoryNames = recordsInRange
        .where((record) => record.type == RecordType.income)
        .map((record) => record.category)
        .toSet();
    final expenseFilterCategories = expenseCategories
        .where((category) => expenseCategoryNames.contains(category.name))
        .toList();
    final incomeFilterCategories = incomeCategories
        .where((category) => incomeCategoryNames.contains(category.name))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('筛选'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilterCard(
              child: Column(
                children: [
                  FilterActionRow(
                    icon: Icons.date_range_rounded,
                    title: '时间',
                    value: filterDateRangeLabel(filter),
                    onTap: pickDateRange,
                  ),
                  const Divider(height: 1, color: Color(0xFFFFE6DD)),
                  FilterAmountRangeRow(
                    minController: minAmountController,
                    maxController: maxAmountController,
                    minIsDefault: filter.minAmount == 0,
                    maxIsDefault: filter.maxAmount == 9999999,
                    onChanged: updateAmountFilter,
                  ),
                  const Divider(height: 1, color: Color(0xFFFFE6DD)),
                  FilterNoteRow(
                    controller: noteController,
                    onChanged: updateNoteFilter,
                  ),
                  const Divider(height: 1, color: Color(0xFFFFE6DD)),
                  FilterPhotoOnlyRow(
                    value: filter.onlyWithPhotos,
                    onChanged: (value) {
                      setState(
                        () => filter = filter.copyWith(onlyWithPhotos: value),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  SplitCategorySection(
                    title: '支出分类',
                    emptyText: '${filterDateRangeLabel(filter)}没有支出记录',
                    categories: expenseFilterCategories,
                    selectedCategories: filter.expenseCategories,
                    onSelect: (category) =>
                        setState(() => toggleExpenseCategory(category)),
                    onToggleAll: () => setState(
                      () => toggleAllExpenseCategories(expenseFilterCategories),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SplitCategorySection(
                    title: '收入分类',
                    emptyText: '${filterDateRangeLabel(filter)}没有收入记录',
                    categories: incomeFilterCategories,
                    selectedCategories: filter.incomeCategories,
                    onSelect: (category) =>
                        setState(() => toggleIncomeCategory(category)),
                    onToggleAll: () => setState(
                      () => toggleAllIncomeCategories(incomeFilterCategories),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7F3).withValues(alpha: 0.94),
          boxShadow: [
            BoxShadow(
              color: Colors.brown.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SizedBox(
          height: 112,
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton(
                  onPressed: resetFilter,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryColor,
                    side: const BorderSide(color: _primaryColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: const Text('重置'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton(
                  onPressed: applyFilter,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryColor,
                    side: const BorderSide(color: _primaryColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: const Text('应用筛选'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> pickDateRange() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(
        start: filter.effectiveStartDate,
        end: filter.effectiveEndDate,
      ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: _primaryColor,
              onPrimary: Colors.white,
              surface: const Color(0xFFFFFBF8),
              onSurface: _textColor,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (selected == null) return;
    setState(() {
      filter = filter.copyWith(
        month: DateTime(selected.start.year, selected.start.month),
        startDate: dateOnly(selected.start),
        endDate: dateOnly(selected.end),
        category: null,
      );
    });
  }

  void updateAmountFilter() {
    final minAmount = double.tryParse(minAmountController.text.trim()) ?? 0;
    final maxAmount =
        double.tryParse(maxAmountController.text.trim()) ?? 9999999;
    setState(() {
      filter = filter.copyWith(
        minAmount: math.max(0, minAmount),
        maxAmount: math.max(0, maxAmount),
      );
    });
  }

  void updateNoteFilter() {
    setState(() {
      filter = filter.copyWith(noteKeyword: noteController.text.trim());
    });
  }

  void applyFilter() {
    updateAmountFilter();
    final minAmount = double.tryParse(minAmountController.text.trim()) ?? 0;
    final maxAmount =
        double.tryParse(maxAmountController.text.trim()) ?? 9999999;
    if (maxAmount < minAmount) {
      showToast(context, '最高金额不能小于最低金额');
      return;
    }
    Navigator.pop(
      context,
      filter.copyWith(
        minAmount: math.max(0, minAmount),
        maxAmount: math.max(0, maxAmount),
        noteKeyword: noteController.text.trim(),
      ),
    );
  }

  void resetFilter() {
    setState(() {
      filter = defaultHomeRecordFilter();
      minAmountController.text = '0';
      maxAmountController.text = '9999999';
      noteController.clear();
    });
  }

  void toggleExpenseCategory(String category) {
    filter = filter.copyWith(
      type: null,
      category: null,
      expenseCategories: toggledCategorySet(filter.expenseCategories, category),
    );
  }

  void toggleIncomeCategory(String category) {
    filter = filter.copyWith(
      type: null,
      category: null,
      incomeCategories: toggledCategorySet(filter.incomeCategories, category),
    );
  }

  void toggleAllExpenseCategories(List<CategoryOption> categories) {
    final allCategories = categoryNameSet(categories);
    filter = filter.copyWith(
      type: null,
      category: null,
      expenseCategories:
          areSameCategorySet(filter.expenseCategories, allCategories)
          ? null
          : allCategories,
    );
  }

  void toggleAllIncomeCategories(List<CategoryOption> categories) {
    final allCategories = categoryNameSet(categories);
    filter = filter.copyWith(
      type: null,
      category: null,
      incomeCategories:
          areSameCategorySet(filter.incomeCategories, allCategories)
          ? null
          : allCategories,
    );
  }
}

class FilterAllCategoryTile extends StatelessWidget {
  const FilterAllCategoryTile({
    super.key,
    required this.selected,
    required this.onTap,
  });

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? _primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: softShadow(),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: selected ? Colors.white : const Color(0xFFFFFCF5),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.82)
                      : const Color(0xFFEAD9B8),
                ),
              ),
              child: Icon(
                Icons.apps_rounded,
                color: selected ? _primaryColor : const Color(0xFFFF8F9F),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '全部分类',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF7B5147),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SplitCategorySection extends StatelessWidget {
  const SplitCategorySection({
    super.key,
    required this.title,
    required this.emptyText,
    required this.categories,
    required this.selectedCategories,
    required this.onSelect,
    required this.onToggleAll,
  });

  final String title;
  final String emptyText;
  final List<CategoryOption> categories;
  final Set<String>? selectedCategories;
  final ValueChanged<String> onSelect;
  final VoidCallback onToggleAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: SectionTitle(title: title)),
            TextButton(
              onPressed: onToggleAll,
              child: Text(
                selectedCategories == null ? '全部' : '取消选择',
                style: const TextStyle(
                  color: _textColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (categories.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              emptyText,
              style: const TextStyle(
                color: _mutedColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: categories.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.85,
            ),
            itemBuilder: (context, index) {
              final category = categories[index];
              return CategoryTile(
                option: category,
                selected: selectedCategories?.contains(category.name) ?? false,
                onTap: () => onSelect(category.name),
              );
            },
          ),
      ],
    );
  }
}

class FilterCard extends StatelessWidget {
  const FilterCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: whiteCardDecoration(),
      child: child,
    );
  }
}

class FilterAmountRangeRow extends StatelessWidget {
  const FilterAmountRangeRow({
    super.key,
    required this.minController,
    required this.maxController,
    required this.minIsDefault,
    required this.maxIsDefault,
    required this.onChanged,
  });

  final TextEditingController minController;
  final TextEditingController maxController;
  final bool minIsDefault;
  final bool maxIsDefault;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.payments_rounded, color: _primaryColor),
          const SizedBox(width: 12),
          const Text(
            '金额',
            style: TextStyle(color: _textColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: FilterAmountInput(
              controller: minController,
              isPlaceholderStyle: minIsDefault,
              hintText: '最低',
              onChanged: onChanged,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '-',
              style: TextStyle(
                color: _mutedColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: FilterAmountInput(
              controller: maxController,
              isPlaceholderStyle: maxIsDefault,
              hintText: '最高',
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class FilterAmountInput extends StatelessWidget {
  const FilterAmountInput({
    super.key,
    required this.controller,
    required this.hintText,
    required this.isPlaceholderStyle,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final bool isPlaceholderStyle;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [AmountInputFormatter()],
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(
          hintText: hintText,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 10,
          ),
          filled: true,
          fillColor: const Color(0xFFFFF0E8),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFFFD6C9)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: _primaryColor),
          ),
        ),
        style: TextStyle(
          color: isPlaceholderStyle ? const Color(0x665B3A32) : _textColor,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class FilterNoteRow extends StatelessWidget {
  const FilterNoteRow({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.notes_rounded, color: _primaryColor),
          const SizedBox(width: 12),
          const Text(
            '备注',
            style: TextStyle(color: _textColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: controller,
                onChanged: (_) => onChanged(),
                decoration: InputDecoration(
                  hintText: '请输入备注关键词',
                  hintStyle: const TextStyle(
                    color: Color(0x669A6A5C),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFFF0E8),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: Color(0xFFFFD6C9)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: _primaryColor),
                  ),
                ),
                style: const TextStyle(
                  color: _textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FilterPhotoOnlyRow extends StatelessWidget {
  const FilterPhotoOnlyRow({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.image_rounded, color: _primaryColor),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '仅显示有图片记录',
              style: TextStyle(color: _textColor, fontWeight: FontWeight.bold),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: _primaryColor,
            activeTrackColor: const Color(0xFFFFB8C5),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFFE8E2DE),
          ),
        ],
      ),
    );
  }
}

class FilterActionRow extends StatelessWidget {
  const FilterActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: trailing == null ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: _primaryColor),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                color: _textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            trailing ??
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        color: _textColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFFB48A7C),
                    ),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}

class FilterChipButton extends StatelessWidget {
  const FilterChipButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _primaryColor : const Color(0xFFFFF0E8),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? _primaryColor : const Color(0xFFFFD6C9),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : _mutedColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class HomeCoverCard extends StatelessWidget {
  const HomeCoverCard({super.key});

  @override
  Widget build(BuildContext context) {
    const aspectRatio = 1920 / 820;
    final width = MediaQuery.sizeOf(context).width;
    final safeTop = MediaQuery.paddingOf(context).top;
    final height = width / aspectRatio - 12 + safeTop;

    return SizedBox(
      width: double.infinity,
      height: height,
      child: OverflowBox(
        minWidth: width,
        maxWidth: width,
        minHeight: height,
        maxHeight: height,
        alignment: Alignment.topCenter,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/cover_bg.png',
                fit: BoxFit.cover,
                alignment: Alignment.bottomCenter,
              ),
            ),
            Positioned.fill(
              child: Container(color: Colors.white.withValues(alpha: 0.06)),
            ),
            Positioned(
              left: 18,
              top: safeTop + 6,
              child: Image.asset(
                'assets/images/app_name.png',
                width: 148,
                height: 60,
                fit: BoxFit.contain,
              ),
            ),
            Positioned(
              left: 38,
              bottom: 8,
              child: SpeechBubble(
                child: const Text(
                  '今天也要\n好好记账喵~',
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeSummaryMiniCard extends StatelessWidget {
  const HomeSummaryMiniCard({
    super.key,
    required this.title,
    required this.amount,
    required this.compareText,
    required this.backgroundColor,
    required this.accentColor,
  });

  final String title;
  final String amount;
  final String compareText;
  final Color backgroundColor;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final positive = !compareText.contains('-');
    final compareColor = positive ? const Color(0xFF47A76A) : _primaryColor;
    return Container(
      height: 128,
      padding: const EdgeInsets.fromLTRB(13, 15, 11, 14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.88)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.14),
            blurRadius: 16,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -2,
            top: -8,
            child: CatPawMark(
              size: 24,
              color: Colors.white.withValues(alpha: 0.28),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                style: const TextStyle(
                  color: _textColor,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 15),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  amount,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Color(0xFF3F2C29),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                compareText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: compareColor,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SpeechBubble extends StatelessWidget {
  const SpeechBubble({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: SpeechBubblePainter(),
      child: Container(
        width: 130,
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: child,
      ),
    );
  }
}

class SpeechBubblePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = const Color(0xFFEFD4C5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final bubble = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width - 8, size.height - 10),
      const Radius.circular(22),
    );
    final tail = Path()
      ..moveTo(size.width * 0.68, size.height - 12)
      ..quadraticBezierTo(
        size.width * 0.84,
        size.height - 4,
        size.width - 2,
        size.height - 16,
      )
      ..quadraticBezierTo(
        size.width * 0.82,
        size.height - 10,
        size.width * 0.68,
        size.height - 20,
      )
      ..close();
    canvas.drawRRect(bubble, fill);
    canvas.drawPath(tail, fill);
    canvas.drawRRect(bubble, stroke);
    canvas.drawPath(tail, stroke);
  }

  @override
  bool shouldRepaint(covariant SpeechBubblePainter oldDelegate) {
    return false;
  }
}

class CatPawPrimaryButton extends StatelessWidget {
  const CatPawPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.fontSize = 17,
  });

  final String label;
  final VoidCallback onPressed;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = math.min(constraints.maxWidth * 0.86, 360.0);
            final height = width / 3.23;
            return Center(
              child: SizedBox(
                width: width,
                height: height,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: ExcludeSemantics(
                        child: Image.asset(
                          'assets/images/button_trimmed.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(
                        left: width * 0.15,
                        right: width * 0.28,
                        bottom: height * 0.06,
                      ),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: fontSize,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class OutlineFixedActionButton extends StatelessWidget {
  const OutlineFixedActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _primaryColor, width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: _primaryColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: _primaryColor,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CatWhiskerMark extends StatelessWidget {
  const CatWhiskerMark({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 20,
      child: CustomPaint(painter: CatWhiskerPainter()),
    );
  }
}

class CatWhiskerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _primaryColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.12, size.height * 0.22),
      Offset(size.width * 0.52, size.height * 0.34),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.08, size.height * 0.5),
      Offset(size.width * 0.52, size.height * 0.5),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.12, size.height * 0.78),
      Offset(size.width * 0.52, size.height * 0.64),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CatWhiskerPainter oldDelegate) {
    return false;
  }
}

String monthCompareText(double current, double previous) {
  if (previous == 0) {
    if (current == 0) return '暂无对比';
    return '较上月 新增';
  }
  final diff = (current - previous) / previous.abs() * 100;
  final sign = diff >= 0 ? '+' : '';
  return '较上月 $sign${diff.toStringAsFixed(1)}%';
}

class AddRecordPage extends StatefulWidget {
  const AddRecordPage({super.key, required this.onSaved});

  final VoidCallback onSaved;

  @override
  State<AddRecordPage> createState() => _AddRecordPageState();
}

class _AddRecordPageState extends State<AddRecordPage> {
  final amountController = TextEditingController();
  final noteController = TextEditingController();
  final List<String> photoDataUris = [];
  RecordType type = RecordType.expense;
  int selectedCategoryIndex = 0;
  DateTime selectedDate = DateTime.now();

  @override
  void dispose() {
    amountController.dispose();
    noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = type == RecordType.expense
        ? expenseCategories
        : incomeCategories;
    final selectedCategory = categories[selectedCategoryIndex];

    return Column(
      children: [
        RecordAmountPanel(
          type: type,
          amountController: amountController,
          onTypeChanged: (value) {
            setState(() {
              type = value;
              selectedCategoryIndex = 0;
            });
          },
          helperText: type == RecordType.expense ? '一起喵～记下这笔支出吧' : '收入到账，快乐加一笔',
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
            child: Column(
              children: [
                const SectionTitle(title: '分类选择'),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: categories.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.85,
                  ),
                  itemBuilder: (context, index) {
                    final item = categories[index];
                    final selected = index == selectedCategoryIndex;
                    return CategoryTile(
                      option: item,
                      selected: selected,
                      onTap: () =>
                          setState(() => selectedCategoryIndex = index),
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        RecordBottomPanel(
          noteController: noteController,
          photoDataUris: photoDataUris,
          selectedDate: selectedDate,
          onPickDate: _pickDate,
          onPickTime: _pickTime,
          onAddPhoto: _addPhotos,
          onRemovePhoto: _removePhoto,
          onSave: () => _saveRecord(selectedCategory),
          buttonText: '保存记录',
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('zh', 'CN'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: _primaryColor),
          ),
          child: child!,
        );
      },
    );
    if (date == null) return;
    setState(() {
      selectedDate = DateTime(
        date.year,
        date.month,
        date.day,
        selectedDate.hour,
        selectedDate.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final time = await showWheelTimePicker(
      context,
      initialTime: TimeOfDay.fromDateTime(selectedDate),
      title: '记账时间',
    );
    if (time == null) return;
    setState(() {
      selectedDate = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _saveRecord(CategoryOption selectedCategory) async {
    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || amount <= 0) {
      showToast(context, '请输入有效金额');
      return;
    }

    final store = AppScope.of(context);
    final previousAchievements = unlockedAchievementIds(store);
    await store.addRecord(
      AccountRecord(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        type: type,
        category: selectedCategory.name,
        icon: selectedCategory.icon,
        amount: amount,
        note: noteController.text.trim(),
        date: selectedDate,
        photoDataUris: List.unmodifiable(photoDataUris),
      ),
    );
    amountController.clear();
    noteController.clear();
    photoDataUris.clear();
    selectedDate = DateTime.now();
    selectedCategoryIndex = 0;
    if (!mounted) return;
    showNewAchievementToast(
      context,
      previousAchievements: previousAchievements,
      store: store,
      fallbackMessage: '喵~又有一笔新的记账！',
    );
    widget.onSaved();
  }

  Future<void> _addPhotos() async {
    final pickedPhotos = await pickRecordPhotos(
      context,
      currentCount: photoDataUris.length,
    );
    if (pickedPhotos.isEmpty || !mounted) return;
    setState(() => photoDataUris.addAll(pickedPhotos));
  }

  void _removePhoto(int index) {
    setState(() => photoDataUris.removeAt(index));
  }
}

class RecordAmountPanel extends StatelessWidget {
  const RecordAmountPanel({
    super.key,
    required this.type,
    required this.amountController,
    required this.onTypeChanged,
    required this.helperText,
  });

  final RecordType type;
  final TextEditingController amountController;
  final ValueChanged<RecordType> onTypeChanged;
  final String helperText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      decoration: BoxDecoration(
        color: _bgColor,
        boxShadow: [
          BoxShadow(
            color: Colors.brown.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: whiteCardDecoration(),
        child: Stack(
          children: [
            Positioned(
              right: -6,
              top: -14,
              child: CatEarCorner(
                size: 52,
                color: _softColor,
                strokeColor: _primaryColor.withValues(alpha: 0.12),
              ),
            ),
            Column(
              children: [
                SegmentedRecordType(value: type, onChanged: onTypeChanged),
                const SizedBox(height: 18),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [AmountInputFormatter()],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    color: _textColor,
                  ),
                  decoration: const InputDecoration(
                    prefixText: '¥ ',
                    hintText: '00.00',
                    hintStyle: TextStyle(
                      color: Color(0x555B3A32),
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                    ),
                    border: InputBorder.none,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CatPawMark(size: 14, color: _primaryColor),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        helperText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFB48A7C),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class RecordBottomPanel extends StatelessWidget {
  const RecordBottomPanel({
    super.key,
    required this.noteController,
    required this.photoDataUris,
    required this.selectedDate,
    required this.onPickDate,
    required this.onPickTime,
    required this.onAddPhoto,
    required this.onRemovePhoto,
    required this.onSave,
    required this.buttonText,
  });

  final TextEditingController noteController;
  final List<String> photoDataUris;
  final DateTime selectedDate;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;
  final VoidCallback onAddPhoto;
  final ValueChanged<int> onRemovePhoto;
  final VoidCallback onSave;
  final String buttonText;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
        decoration: BoxDecoration(
          color: _bgColor,
          boxShadow: [
            BoxShadow(
              color: Colors.brown.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: RecordDateTimeButton(
                    icon: Icons.calendar_month_rounded,
                    title: '日期',
                    value: formatDate(selectedDate),
                    onTap: onPickDate,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: RecordDateTimeButton(
                    icon: Icons.access_time_rounded,
                    title: '时间',
                    value: formatTime(selectedDate),
                    onTap: onPickTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: whiteCardDecoration(),
              child: Row(
                children: [
                  const Icon(Icons.edit_note_rounded, color: _primaryColor),
                  const SizedBox(width: 12),
                  const Text(
                    '备注',
                    style: TextStyle(
                      color: _textColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: noteController,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                        hintText: '写点什么吧...',
                        border: InputBorder.none,
                        hintStyle: TextStyle(color: Color(0xFFB48A7C)),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '添加照片',
                    onPressed: onAddPhoto,
                    icon: const Icon(
                      Icons.add_a_photo_rounded,
                      color: _primaryColor,
                    ),
                  ),
                ],
              ),
            ),
            if (photoDataUris.isNotEmpty) ...[
              const SizedBox(height: 10),
              RecordPhotoStrip(
                photoDataUris: photoDataUris,
                onRemove: onRemovePhoto,
              ),
            ],
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: CatPawPrimaryButton(label: buttonText, onPressed: onSave),
            ),
          ],
        ),
      ),
    );
  }
}

class RecordDateTimeButton extends StatelessWidget {
  const RecordDateTimeButton({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: whiteCardDecoration(),
          child: Row(
            children: [
              Icon(icon, color: _primaryColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFB48A7C),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFB48A7C),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<TimeOfDay?> showWheelTimePicker(
  BuildContext context, {
  required TimeOfDay initialTime,
  String title = '选择时间',
}) async {
  var selectedHour = initialTime.hour;
  var selectedMinute = initialTime.minute;
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            top: false,
            child: Container(
              height: 328,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              decoration: const BoxDecoration(
                color: Color(0xFFFFFBF8),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _primaryColor.withValues(alpha: 0.26),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text(
                          '取消',
                          style: TextStyle(color: _mutedColor),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: _textColor,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(
                          sheetContext,
                          TimeOfDay(hour: selectedHour, minute: selectedMinute),
                        ),
                        child: const Text(
                          '确定',
                          style: TextStyle(
                            color: _primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3F5),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: CupertinoPicker.builder(
                              scrollController: FixedExtentScrollController(
                                initialItem: selectedHour,
                              ),
                              itemExtent: 42,
                              selectionOverlay:
                                  const CupertinoPickerDefaultSelectionOverlay(
                                    background: Color(0x55FFFFFF),
                                  ),
                              onSelectedItemChanged: (index) {
                                setSheetState(() => selectedHour = index);
                              },
                              childCount: 24,
                              itemBuilder: (context, index) => Center(
                                child: Text(
                                  twoDigits(index),
                                  style: const TextStyle(
                                    color: _textColor,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const Text(
                            ':',
                            style: TextStyle(
                              color: _mutedColor,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Expanded(
                            child: CupertinoPicker.builder(
                              scrollController: FixedExtentScrollController(
                                initialItem: selectedMinute,
                              ),
                              itemExtent: 42,
                              selectionOverlay:
                                  const CupertinoPickerDefaultSelectionOverlay(
                                    background: Color(0x55FFFFFF),
                                  ),
                              onSelectedItemChanged: (index) {
                                setSheetState(() => selectedMinute = index);
                              },
                              childCount: 60,
                              itemBuilder: (context, index) => Center(
                                child: Text(
                                  twoDigits(index),
                                  style: const TextStyle(
                                    color: _textColor,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class RecordPhotoStrip extends StatelessWidget {
  const RecordPhotoStrip({
    super.key,
    required this.photoDataUris,
    required this.onRemove,
  });

  final List<String> photoDataUris;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photoDataUris.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  imageBytesFromDataUri(photoDataUris[index]),
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 72,
                    height: 72,
                    color: _softColor,
                    child: const Icon(
                      Icons.broken_image_rounded,
                      color: _mutedColor,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -7,
                top: -7,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => onRemove(index),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _primaryColor.withValues(alpha: 0.34),
                      ),
                      boxShadow: softShadow(),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: _primaryColor,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class SegmentedRecordType extends StatelessWidget {
  const SegmentedRecordType({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final RecordType value;
  final ValueChanged<RecordType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: _softColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          _segment('支出', RecordType.expense),
          _segment('收入', RecordType.income),
        ],
      ),
    );
  }

  Widget _segment(String label, RecordType type) {
    final selected = value == type;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => onChanged(type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? _primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : _mutedColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class CategoryTile extends StatelessWidget {
  const CategoryTile({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final CategoryOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? _primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: softShadow(),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CategoryIconView(
              category: option.name,
              icon: option.icon,
              selected: selected,
              size: 30,
            ),
            const SizedBox(height: 8),
            Text(
              option.name,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF7B5147),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CategoryIconView extends StatelessWidget {
  const CategoryIconView({
    super.key,
    required this.category,
    required this.icon,
    this.selected = false,
    this.size = 28,
  });

  final String category;
  final IconData icon;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final imageAsset = categoryImageAsset(category);
    final badgeSize = size + 18;
    final accentColor = categoryAccentColor(category);
    final badgeColor = selected ? Colors.white : const Color(0xFFFFFCF5);
    final badgeBorder = selected
        ? Colors.white.withValues(alpha: 0.82)
        : const Color(0xFFEAD9B8);
    if (imageAsset != null) {
      return Container(
        width: badgeSize,
        height: badgeSize,
        padding: EdgeInsets.all(size * 0.08),
        decoration: BoxDecoration(
          color: badgeColor,
          shape: BoxShape.circle,
          border: Border.all(color: badgeBorder, width: 1.5),
        ),
        child: ClipOval(
          child: Image.asset(
            imageAsset,
            width: badgeSize,
            height: badgeSize,
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return Container(
      width: badgeSize,
      height: badgeSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: badgeColor,
        shape: BoxShape.circle,
        border: Border.all(color: badgeBorder, width: 1.5),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: badgeSize * 0.16,
            top: badgeSize * 0.18,
            child: Container(
              width: badgeSize * 0.22,
              height: badgeSize * 0.22,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Icon(
            icon,
            color: accentColor,
            size: size,
            shadows: [
              Shadow(
                color: accentColor.withValues(alpha: 0.24),
                offset: const Offset(0, 1),
                blurRadius: 0,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  RecordType selectedType = RecordType.expense;
  StatsRange range = StatsRange.week;
  DateTime selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final stats = store.statsFor(selectedType, range, anchorDate: selectedDate);
    final total = store.totalFor(selectedType, range, anchorDate: selectedDate);
    final rangeRecords = store.recordsForRange(range, anchorDate: selectedDate);
    final trendPoints = buildTrendPoints(
      range,
      rangeRecords,
      anchorDate: selectedDate,
    );
    final detailRanks = buildDetailRanks(rangeRecords, selectedType);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedRecordType(
            value: selectedType,
            onChanged: (value) => setState(() => selectedType = value),
          ),
          const SizedBox(height: 12),
          StatsRangeTabs(
            value: range,
            onChanged: (value) => setState(() => range = value),
          ),
          const SizedBox(height: 12),
          StatsDateSelector(
            range: range,
            value: selectedDate,
            onChanged: (value) => setState(() => selectedDate = value),
          ),
          const SizedBox(height: 16),
          ExpenseTrendCard(
            type: selectedType,
            range: range,
            anchorDate: selectedDate,
            points: trendPoints,
            total: total,
            recordCount: detailRanks.length,
          ),
          const SizedBox(height: 18),
          ExpenseOverviewCard(type: selectedType, stats: stats, total: total),
          const SizedBox(height: 18),
          CategoryRankingCard(type: selectedType, stats: stats, total: total),
          const SizedBox(height: 18),
          DetailRankingCard(type: selectedType, records: detailRanks),
        ],
      ),
    );
  }
}

class StatsRangeTabs extends StatelessWidget {
  const StatsRangeTabs({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final StatsRange value;
  final ValueChanged<StatsRange> onChanged;

  @override
  Widget build(BuildContext context) {
    const ranges = [StatsRange.week, StatsRange.month, StatsRange.year];
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _softColor,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: ranges.map((item) {
          final selected = item == value;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => onChanged(item),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? _primaryColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  statsRangeShortLabel(item),
                  style: TextStyle(
                    color: selected ? Colors.white : _mutedColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class StatsDateSelector extends StatelessWidget {
  const StatsDateSelector({
    super.key,
    required this.range,
    required this.value,
    required this.onChanged,
  });

  final StatsRange range;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  Future<void> _pickPeriod(BuildContext context) async {
    final DateTime? selected;
    if (range == StatsRange.day || range == StatsRange.week) {
      selected = await showDatePicker(
        context: context,
        initialDate: value,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
    } else {
      selected = await showModalBottomSheet<DateTime>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => MonthPickerSheet(value: value),
      );
    }
    if (selected == null) return;
    onChanged(selected);
  }

  void _movePeriod(int offset) {
    switch (range) {
      case StatsRange.day:
        onChanged(value.add(Duration(days: offset)));
      case StatsRange.week:
        onChanged(value.add(Duration(days: offset * 7)));
      case StatsRange.month:
        onChanged(DateTime(value.year, value.month + offset, 1));
      case StatsRange.year:
        onChanged(DateTime(value.year + offset, value.month, value.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFFD4DD)),
        boxShadow: softShadow(),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '上一期',
            onPressed: () => _movePeriod(-1),
            icon: const Icon(Icons.chevron_left_rounded),
            color: _primaryColor,
          ),
          Expanded(
            child: TextButton.icon(
              onPressed: () => _pickPeriod(context),
              icon: const Icon(Icons.calendar_month_rounded, size: 20),
              label: Text(statsRangeLabel(range, anchorDate: value)),
              style: TextButton.styleFrom(
                foregroundColor: _textColor,
                textStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          IconButton(
            tooltip: '下一期',
            onPressed: () => _movePeriod(1),
            icon: const Icon(Icons.chevron_right_rounded),
            color: _primaryColor,
          ),
        ],
      ),
    );
  }
}

class MonthPickerSheet extends StatefulWidget {
  const MonthPickerSheet({super.key, required this.value});

  final DateTime value;

  @override
  State<MonthPickerSheet> createState() => _MonthPickerSheetState();
}

class _MonthPickerSheetState extends State<MonthPickerSheet> {
  late int year = widget.value.year;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: softShadow(),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '上一年',
                  onPressed: () => setState(() => year -= 1),
                  icon: const Icon(Icons.chevron_left_rounded),
                  color: _primaryColor,
                ),
                Expanded(
                  child: Text(
                    '$year年',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '下一年',
                  onPressed: () => setState(() => year += 1),
                  icon: const Icon(Icons.chevron_right_rounded),
                  color: _primaryColor,
                ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 12,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 10,
                childAspectRatio: 3,
              ),
              itemBuilder: (context, index) {
                final month = index + 1;
                final selected =
                    widget.value.year == year && widget.value.month == month;
                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.of(context).pop(DateTime(year, month)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? _primaryColor : _softColor,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      '$month月',
                      style: TextStyle(
                        color: selected ? Colors.white : _mutedColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class ExpenseTrendCard extends StatefulWidget {
  const ExpenseTrendCard({
    super.key,
    required this.type,
    required this.range,
    required this.anchorDate,
    required this.points,
    required this.total,
    required this.recordCount,
  });

  final RecordType type;
  final StatsRange range;
  final DateTime anchorDate;
  final List<TrendPoint> points;
  final double total;
  final int recordCount;

  @override
  State<ExpenseTrendCard> createState() => _ExpenseTrendCardState();
}

class _ExpenseTrendCardState extends State<ExpenseTrendCard> {
  int? selectedBarIndex;

  @override
  void didUpdateWidget(covariant ExpenseTrendCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.type != widget.type ||
        oldWidget.range != widget.range ||
        oldWidget.anchorDate != widget.anchorDate ||
        oldWidget.points.length != widget.points.length) {
      selectedBarIndex = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final typeLabel = recordTypeLabel(widget.type);
    final points = widget.points;
    final average = widget.recordCount == 0
        ? 0.0
        : widget.total / widget.recordCount;

    return ReportCard(
      title: '$typeLabel趋势',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: MiniMetric(
                  title: '总$typeLabel',
                  value: money(widget.total),
                ),
              ),
              Expanded(
                child: MiniMetric(title: '平均$typeLabel', value: money(average)),
              ),
              Expanded(
                child: MiniMetric(
                  title: '$typeLabel笔数',
                  value: '${widget.recordCount}笔',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 190,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final chartSize = Size(constraints.maxWidth, 190);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    final index = trendBarIndexAt(
                      details.localPosition,
                      chartSize,
                      points.length,
                    );
                    setState(() => selectedBarIndex = index);
                  },
                  child: CustomPaint(
                    painter: TrendBarPainter(
                      points: points,
                      type: widget.type,
                      selectedIndex: selectedBarIndex,
                    ),
                    child: const SizedBox.expand(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ChartLegend(
                color: widget.type == RecordType.expense
                    ? _primaryColor
                    : _greenColor,
                label: '$typeLabel总额',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ExpenseOverviewCard extends StatelessWidget {
  const ExpenseOverviewCard({
    super.key,
    required this.type,
    required this.stats,
    required this.total,
  });

  final RecordType type;
  final List<CategoryStat> stats;
  final double total;

  @override
  Widget build(BuildContext context) {
    final typeLabel = recordTypeLabel(type);
    final hasDominantStat = stats.any((stat) => stat.ratio >= 0.5);
    return ReportCard(
      title: '$typeLabel占比概况',
      child: stats.isEmpty
          ? EmptyState(
              icon: Icons.pie_chart_rounded,
              title: '暂无$typeLabel统计',
              subtitle: '添加$typeLabel后这里会自动生成分类占比',
            )
          : Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 300,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(painter: DonutPainter(stats)),
                      ),
                      Align(
                        alignment: Alignment(hasDominantStat ? -0.12 : 0, 0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '总$typeLabel',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: _mutedColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                money(total),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: _textColor,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
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

class CategoryRankingCard extends StatelessWidget {
  const CategoryRankingCard({
    super.key,
    required this.type,
    required this.stats,
    required this.total,
  });

  final RecordType type;
  final List<CategoryStat> stats;
  final double total;

  @override
  Widget build(BuildContext context) {
    final typeLabel = recordTypeLabel(type);
    return ReportCard(
      title: '$typeLabel类别排行',
      child: stats.isEmpty
          ? const EmptyRankingText(text: '暂无类别排行')
          : Column(
              children: stats
                  .map(
                    (stat) => RankingBarRow(
                      icon: stat.icon,
                      title: stat.name,
                      subtitle: '$typeLabel ${money(stat.amount)}',
                      trailing: '${(stat.ratio * 100).toStringAsFixed(1)}%',
                      ratio: stat.ratio,
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class DetailRankingCard extends StatelessWidget {
  const DetailRankingCard({
    super.key,
    required this.type,
    required this.records,
  });

  final RecordType type;
  final List<AccountRecord> records;

  @override
  Widget build(BuildContext context) {
    final typeLabel = recordTypeLabel(type);
    return ReportCard(
      title: '$typeLabel明细排行',
      child: records.isEmpty
          ? EmptyRankingText(text: '暂无$typeLabel明细')
          : Column(
              children: records.take(8).map((record) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      RankingIcon(icon: record.icon),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record.category,
                              style: const TextStyle(
                                color: _textColor,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formatMonthDay(record.date),
                              style: const TextStyle(
                                color: _mutedColor,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${type == RecordType.expense ? '-' : '+'} ${money(record.amount)}',
                        style: TextStyle(
                          color: type == RecordType.expense
                              ? _textColor
                              : _greenColor,
                          fontSize: 15,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class ReportCard extends StatelessWidget {
  const ReportCard({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFFD6C9), width: 1.2),
        boxShadow: softShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 7),
              const CatPawMark(size: 15, color: _accentColor),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 1,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _primaryColor.withValues(alpha: 0.22),
                  _accentColor.withValues(alpha: 0.1),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class MiniMetric extends StatelessWidget {
  const MiniMetric({super.key, required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _mutedColor),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _textColor,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 10,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: color, width: 2)),
          ),
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class RankingBarRow extends StatelessWidget {
  const RankingBarRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.ratio,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          RankingIcon(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: _textColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      trailing,
                      style: const TextStyle(
                        color: _textColor,
                        fontSize: 15,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: ratio.clamp(0, 1),
                    minHeight: 7,
                    backgroundColor: _softColor,
                    color: const Color(0xFFFF9878),
                  ),
                ),
                const SizedBox(height: 6),
                Text(subtitle, style: const TextStyle(color: _mutedColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RankingIcon extends StatelessWidget {
  const RankingIcon({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 25,
      backgroundColor: const Color(0xFFFFFBF5),
      child: CircleAvatar(
        radius: 22,
        backgroundColor: Colors.white,
        child: Icon(icon, color: _primaryColor),
      ),
    );
  }
}

class EmptyRankingText extends StatelessWidget {
  const EmptyRankingText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(text, style: const TextStyle(color: _mutedColor)),
      ),
    );
  }
}

class DashedDivider extends StatelessWidget {
  const DashedDivider({super.key, this.thick = false});

  final bool thick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: thick ? 8 : 1,
      width: double.infinity,
      child: CustomPaint(painter: DashedDividerPainter(thick: thick)),
    );
  }
}

class DashedDividerPainter extends CustomPainter {
  DashedDividerPainter({required this.thick});

  final bool thick;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFBEEAD4)
      ..strokeWidth = thick ? 3 : 1
      ..strokeCap = StrokeCap.round;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(math.min(x + 8, size.width), size.height / 2),
        paint,
      );
      x += thick ? 18 : 12;
    }
  }

  @override
  bool shouldRepaint(covariant DashedDividerPainter oldDelegate) {
    return oldDelegate.thick != thick;
  }
}

class DonutPainter extends CustomPainter {
  DonutPainter(this.stats);

  final List<CategoryStat> stats;
  final colors = const [
    Color(0xFFFFA76B),
    Color(0xFF8CB9F2),
    Color(0xFFFFD36E),
    Color(0xFF75E6C8),
    Color(0xFFEA76D1),
    Color(0xFFB8A7FF),
    Color(0xFF78C6E7),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final labeledStats = stats
        .where((stat) => stat.amount > 0)
        .take(3)
        .toList();
    final hasDominantStat = stats.any((stat) => stat.ratio >= 0.5);
    final diameter = hasDominantStat
        ? math.min(size.width * 0.54, size.height * 0.7)
        : math.min(size.width * 0.6, size.height * 0.78);
    final center = Offset(
      hasDominantStat ? size.width * 0.43 : size.width / 2,
      size.height / 2,
    );
    final rect = Rect.fromCenter(
      center: center,
      width: diameter,
      height: diameter,
    );
    final stroke = diameter * 0.18;
    final arcRect = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    paint.color = const Color(0xFFFFF1F4);
    canvas.drawArc(arcRect, 0, math.pi * 2, false, paint);

    if (stats.isEmpty) {
      paint.color = _softColor;
      canvas.drawArc(arcRect, 0, math.pi * 2, false, paint);
      return;
    }

    var start = -math.pi / 2;
    const gap = 0.026;
    final labelPainter = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < stats.length; i++) {
      final sweep = math.pi * 2 * stats[i].ratio;
      if (sweep <= 0) continue;
      paint.color = colors[i % colors.length];
      final visibleSweep = math.max(0.0, sweep - gap);
      canvas.drawArc(arcRect, start + gap / 2, visibleSweep, false, paint);
      final labelIndex = labeledStats.indexOf(stats[i]);
      if (labelIndex >= 0) {
        final labelAngle = labelIndex == 0 && stats[i].ratio >= 0.5
            ? 0.0
            : start + sweep / 2;
        _drawOutsideLabel(
          canvas,
          size,
          arcRect,
          labelAngle,
          stats[i],
          colors[i % colors.length],
          labelPainter,
          labelIndex,
        );
      }
      start += sweep;
    }
  }

  void _drawOutsideLabel(
    Canvas canvas,
    Size size,
    Rect arcRect,
    double angle,
    CategoryStat stat,
    Color color,
    TextPainter textPainter,
    int labelIndex,
  ) {
    final radius = arcRect.width / 2;
    final center = arcRect.center;
    final direction = Offset(math.cos(angle), math.sin(angle));
    final startPoint = center + direction * radius;
    final isRight = labelIndex == 0 ? true : direction.dx >= 0;
    final naturalY = (center + direction * (radius + 18)).dy;
    final preferredY = switch (labelIndex) {
      0 => center.dy - radius * 0.18,
      1 => naturalY + 46,
      _ => naturalY + 8,
    };
    final elbowPoint = Offset(
      isRight ? center.dx + radius + 16 : center.dx - radius - 16,
      preferredY.clamp(30.0, size.height - 44.0),
    );

    final textAlign = isRight ? TextAlign.right : TextAlign.left;
    textPainter
      ..textAlign = textAlign
      ..text = TextSpan(
        children: [
          TextSpan(
            text: '${stat.name}\n',
            style: const TextStyle(
              color: Color(0xFFAFA5A0),
              fontSize: 14,
              height: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(
            text: '${(stat.ratio * 100).toStringAsFixed(1)}%',
            style: const TextStyle(
              color: _textColor,
              fontSize: 15,
              height: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
    textPainter.layout(maxWidth: 62);
    final labelX = isRight ? size.width - 12 - textPainter.width : 12.0;
    final labelY = (elbowPoint.dy - textPainter.height / 2).clamp(
      6.0,
      size.height - textPainter.height - 6.0,
    );
    final lineY = labelY + textPainter.height / 2;
    final endX = isRight ? labelX - 6 : labelX + textPainter.width + 6;
    final endPoint = Offset(endX, lineY);
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(startPoint.dx, startPoint.dy)
      ..lineTo(elbowPoint.dx, lineY)
      ..lineTo(endPoint.dx, lineY);
    canvas.drawPath(path, linePaint);
    textPainter.paint(canvas, Offset(labelX, labelY));
  }

  @override
  bool shouldRepaint(covariant DonutPainter oldDelegate) {
    return oldDelegate.stats != stats;
  }
}

class TrendBarPainter extends CustomPainter {
  TrendBarPainter({
    required this.points,
    required this.type,
    this.selectedIndex,
  });

  final List<TrendPoint> points;
  final RecordType type;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0;
    const top = 8.0;
    const bottom = 28.0;
    const right = 8.0;
    final chart = Rect.fromLTWH(
      left,
      top,
      size.width - left - right,
      size.height - top - bottom,
    );
    final gridPaint = Paint()
      ..color = const Color(0xFFEFE5DE)
      ..strokeWidth = 1;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final maxValue = math.max(
      1,
      points.fold<double>(
        0,
        (max, point) => math.max(max, point.amountFor(type)),
      ),
    );

    for (var i = 0; i <= 4; i++) {
      final y = chart.bottom - chart.height * i / 4;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      textPainter.text = TextSpan(
        text: (maxValue * i / 4).round().toString(),
        style: const TextStyle(color: Color(0xFFC6BDB4), fontSize: 9),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(0, y - 6));
    }

    if (points.isEmpty) return;

    final barColor = type == RecordType.expense ? _primaryColor : _greenColor;
    final groupWidth = chart.width / points.length;
    final barWidth = math.max(5.0, math.min(24.0, groupWidth * 0.52));
    final barPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [barColor, barColor.withValues(alpha: 0.48)],
      ).createShader(chart);

    for (var i = 0; i < points.length; i++) {
      final value = points[i].amountFor(type);
      final x = chart.left + groupWidth * i + groupWidth / 2;
      final barHeight = value <= 0
          ? 2.0
          : math.max(5.0, chart.height * value / maxValue);
      final rect = Rect.fromLTWH(
        x - barWidth / 2,
        chart.bottom - barHeight,
        barWidth,
        barHeight,
      );
      final radius = Radius.circular(math.min(7, barWidth / 2));
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: radius,
          topRight: radius,
          bottomLeft: const Radius.circular(2),
          bottomRight: const Radius.circular(2),
        ),
        value <= 0 ? (Paint()..color = const Color(0xFFF3E7DF)) : barPaint,
      );
    }

    final selected = selectedIndex;
    if (selected != null && selected >= 0 && selected < points.length) {
      final point = points[selected];
      final value = point.amountFor(type);
      final x = chart.left + groupWidth * selected + groupWidth / 2;
      final barHeight = value <= 0
          ? 2.0
          : math.max(5.0, chart.height * value / maxValue);
      final y = chart.bottom - barHeight;
      final selectedPaint = Paint()
        ..color = barColor.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x - barWidth / 2, y, barWidth, barHeight),
          topLeft: Radius.circular(math.min(7, barWidth / 2)),
          topRight: Radius.circular(math.min(7, barWidth / 2)),
          bottomLeft: const Radius.circular(2),
          bottomRight: const Radius.circular(2),
        ),
        selectedPaint,
      );

      final label =
          '${point.detailLabel}\n${recordTypeLabel(type)} ${money(value)}';
      textPainter.text = TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
      );
      textPainter.textAlign = TextAlign.center;
      textPainter.layout();
      final labelWidth = textPainter.width + 18;
      final labelHeight = textPainter.height + 12;
      final left = (x - labelWidth / 2).clamp(0.0, size.width - labelWidth);
      final top = math.max(0.0, y - labelHeight - 8);
      final labelRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, labelWidth, labelHeight),
        const Radius.circular(8),
      );
      canvas.drawRRect(
        labelRect,
        Paint()..color = _textColor.withValues(alpha: 0.72),
      );
      textPainter.paint(canvas, Offset(left + 9, top + 6));
    }

    final step = math.max(1, (points.length / 6).ceil());
    for (var i = 0; i < points.length; i += step) {
      final x = chart.left + groupWidth * i + groupWidth / 2;
      textPainter.text = TextSpan(
        text: points[i].label,
        style: const TextStyle(color: Color(0xFFB8AEA5), fontSize: 10),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, chart.bottom + 8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant TrendBarPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.type != type ||
        oldDelegate.selectedIndex != selectedIndex;
  }
}

int? trendBarIndexAt(Offset offset, Size size, int pointCount) {
  if (pointCount <= 0) return null;
  const left = 34.0;
  const top = 8.0;
  const bottom = 28.0;
  const right = 8.0;
  final chart = Rect.fromLTWH(
    left,
    top,
    size.width - left - right,
    size.height - top - bottom,
  );
  if (!chart.inflate(12).contains(offset)) return null;
  final groupWidth = chart.width / pointCount;
  final index = ((offset.dx - chart.left) / groupWidth).floor();
  return index.clamp(0, pointCount - 1);
}

class BudgetPage extends StatelessWidget {
  const BudgetPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '月度预算'),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => showBudgetDialog(context, store),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 22, 16, 22),
              decoration: whiteCardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '总预算 ${money(store.effectiveMonthlyBudget)}',
                          style: const TextStyle(
                            fontSize: 20,
                            color: _textColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.edit_rounded,
                        color: _mutedColor,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '剩余 ${money(store.budgetLeft)}',
                    style: const TextStyle(fontSize: 15, color: _mutedColor),
                  ),
                  const SizedBox(height: 18),
                  LinearProgressIndicator(
                    value: store.budgetRatio,
                    minHeight: 10,
                    borderRadius: const BorderRadius.all(Radius.circular(10)),
                    backgroundColor: _softColor,
                    color: _primaryColor,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          CategoryBudgetSection(store: store),
        ],
      ),
    );
  }
}

class CategoryBudgetSection extends StatelessWidget {
  const CategoryBudgetSection({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final budgets = [...store.categoryBudgets]
      ..sort((a, b) {
        final limitCompare = b.limit.compareTo(a.limit);
        if (limitCompare != 0) return limitCompare;
        return a.category.compareTo(b.category);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: SectionTitle(title: '分类预算')),
            PillActionButton(
              icon: Icons.add_rounded,
              label: '添加分类',
              onTap: () => openCategoryBudgetEditor(context),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (budgets.isEmpty)
          CategoryBudgetEmptyCard(
            height: math.max(360, MediaQuery.sizeOf(context).height - 390),
          )
        else
          ...budgets.map((budget) {
            final spent = store.categoryMonthExpense(budget.category);
            return CategoryBudgetTile(
              budget: budget,
              spent: spent,
              onTap: () => Navigator.push(
                context,
                appPageRoute(
                  (_) => CategoryBudgetRecordsPage(budgetId: budget.id),
                ),
              ),
            );
          }),
      ],
    );
  }
}

void openCategoryBudgetEditor(BuildContext context, {CategoryBudget? budget}) {
  Navigator.push(
    context,
    appPageRoute((_) => CategoryBudgetEditPage(budgetId: budget?.id)),
  );
}

class CategoryBudgetEmptyCard extends StatelessWidget {
  const CategoryBudgetEmptyCard({super.key, required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(24),
        boxShadow: softShadow(),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/category_budget_empty_cat.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.02),
                    Colors.white.withValues(alpha: 0.34),
                    Colors.white.withValues(alpha: 0.76),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 44,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '猫猫还没收到预算任务～',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF8F8A84),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '给常用分类设个小目标吧',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFB3A6A0), fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CategoryBudgetTile extends StatelessWidget {
  const CategoryBudgetTile({
    super.key,
    required this.budget,
    required this.spent,
    required this.onTap,
  });

  final CategoryBudget budget;
  final double spent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ratio = budget.limit <= 0
        ? 0.0
        : (spent / budget.limit).clamp(0, 1).toDouble();
    final left = budget.limit - spent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: whiteCardDecoration(),
          child: Stack(
            children: [
              Positioned(
                right: 30,
                top: -2,
                child: CatPawMark(
                  size: 18,
                  color: _primaryColor.withValues(alpha: 0.12),
                ),
              ),
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: _softColor,
                    child: CategoryIconView(
                      category: budget.category,
                      icon: budget.icon,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                budget.category,
                                style: const TextStyle(
                                  color: _textColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Text(
                              '剩余 ${money(left)}',
                              style: TextStyle(
                                color: left >= 0 ? _mutedColor : _primaryColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: ratio,
                          minHeight: 8,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(8),
                          ),
                          backgroundColor: _softColor,
                          color: left >= 0 ? _accentColor : _primaryColor,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '猫爪已用 ${money(spent)} / 预算 ${money(budget.limit)}',
                          style: const TextStyle(
                            color: _mutedColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CategoryBudgetRecordsPage extends StatelessWidget {
  const CategoryBudgetRecordsPage({super.key, required this.budgetId});

  final String budgetId;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final budget = store.categoryBudgetById(budgetId);
    if (budget == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: const Text('分类账单'),
        ),
        body: const Center(
          child: Text('这个分类预算已经不存在了', style: TextStyle(color: _mutedColor)),
        ),
      );
    }

    final records = store.currentMonthRecords
        .where(
          (record) =>
              record.type == RecordType.expense &&
              record.category == budget.category,
        )
        .toList();
    final spent = records.fold<double>(0, (sum, record) => sum + record.amount);
    final left = budget.limit - spent;
    final ratio = budget.limit <= 0
        ? 0.0
        : (spent / budget.limit).clamp(0, 1).toDouble();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: Text('${budget.category}预算'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 132),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: whiteCardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: _softColor,
                        child: CategoryIconView(
                          category: budget.category,
                          icon: budget.icon,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              budget.category,
                              style: const TextStyle(
                                color: _textColor,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${formatYearMonth(DateTime.now())}分类预算',
                              style: const TextStyle(
                                color: _mutedColor,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: MiniMetric(title: '已支出', value: money(spent)),
                      ),
                      Expanded(
                        child: MiniMetric(
                          title: '预算',
                          value: money(budget.limit),
                        ),
                      ),
                      Expanded(
                        child: MiniMetric(
                          title: left >= 0 ? '剩余' : '超出',
                          value: money(left.abs()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  LinearProgressIndicator(
                    value: ratio,
                    minHeight: 10,
                    borderRadius: const BorderRadius.all(Radius.circular(10)),
                    backgroundColor: _softColor,
                    color: left >= 0 ? _accentColor : _primaryColor,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SectionTitle(title: '本月${budget.category}账单'),
            const SizedBox(height: 12),
            if (records.isEmpty)
              EmptyState(
                icon: Icons.receipt_long_rounded,
                title:
                    '${formatYearMonth(DateTime.now())}还没有${budget.category}账单',
                subtitle: '去「记账」页添加这一类支出吧',
              )
            else
              RecordGroupList(records: records),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          decoration: BoxDecoration(
            color: _bgColor.withValues(alpha: 0.96),
            boxShadow: [
              BoxShadow(
                color: Colors.brown.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlineFixedActionButton(
                  onPressed: () =>
                      openCategoryBudgetEditor(context, budget: budget),
                  icon: Icons.edit_rounded,
                  label: '编辑',
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlineFixedActionButton(
                  onPressed: () => confirmDeleteCategoryBudget(
                    context,
                    store,
                    budget,
                    popAfterDelete: true,
                  ),
                  icon: Icons.delete_rounded,
                  label: '删除',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CategoryBudgetEditPage extends StatefulWidget {
  const CategoryBudgetEditPage({super.key, this.budgetId});

  final String? budgetId;

  @override
  State<CategoryBudgetEditPage> createState() => _CategoryBudgetEditPageState();
}

class _CategoryBudgetEditPageState extends State<CategoryBudgetEditPage> {
  final amountController = TextEditingController();
  int selectedCategoryIndex = 0;
  bool initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    final budgetId = widget.budgetId;
    if (budgetId != null) {
      final budget = AppScope.of(context).categoryBudgetById(budgetId);
      if (budget != null) {
        selectedCategoryIndex = math.max(
          0,
          expenseCategories.indexWhere(
            (category) => category.name == budget.category,
          ),
        );
        amountController.text = budget.limit.toStringAsFixed(2);
      }
    }
    initialized = true;
  }

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final budget = widget.budgetId == null
        ? null
        : store.categoryBudgetById(widget.budgetId!);
    final selectedCategory = expenseCategories[selectedCategoryIndex];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: Text(budget == null ? '添加分类预算' : '编辑分类预算'),
        actions: [
          if (budget != null)
            IconButton(
              tooltip: '删除',
              onPressed: () => confirmDeleteCategoryBudget(
                context,
                store,
                budget,
                popAfterDelete: true,
              ),
              icon: const Icon(Icons.delete_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          CategoryBudgetTopPanel(
            selectedCategory: selectedCategory,
            amountController: amountController,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle(title: '选择分类'),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: expenseCategories.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.85,
                        ),
                    itemBuilder: (context, index) {
                      final category = expenseCategories[index];
                      return CategoryTile(
                        option: category,
                        selected: index == selectedCategoryIndex,
                        onTap: () =>
                            setState(() => selectedCategoryIndex = index),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              decoration: BoxDecoration(
                color: _bgColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.brown.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                child: CatPawPrimaryButton(
                  label: budget == null ? '保存分类预算' : '保存修改',
                  onPressed: () => _save(store, budget),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save(AppStore store, CategoryBudget? budget) async {
    final value = double.tryParse(amountController.text.trim());
    if (value == null || value <= 0) {
      showToast(context, '请输入有效预算金额');
      return;
    }

    final selectedCategory = expenseCategories[selectedCategoryIndex];
    var id = budget?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    if (budget == null) {
      for (final item in store.categoryBudgets) {
        if (item.category == selectedCategory.name) {
          id = item.id;
          break;
        }
      }
    }

    final previousAchievements = unlockedAchievementIds(store);
    await store.upsertCategoryBudget(
      CategoryBudget(id: id, category: selectedCategory.name, limit: value),
    );
    if (!mounted) return;
    showNewAchievementToast(
      context,
      previousAchievements: previousAchievements,
      store: store,
      fallbackMessage: '分类预算已保存',
    );
    Navigator.pop(context);
  }
}

class CategoryBudgetTopPanel extends StatelessWidget {
  const CategoryBudgetTopPanel({
    super.key,
    required this.selectedCategory,
    required this.amountController,
  });

  final CategoryOption selectedCategory;
  final TextEditingController amountController;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      decoration: BoxDecoration(
        color: _bgColor,
        boxShadow: [
          BoxShadow(
            color: Colors.brown.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFF0E8), Colors.white],
              ),
              borderRadius: BorderRadius.circular(26),
              boxShadow: softShadow(),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: _primaryColor,
                  child: CategoryIconView(
                    category: selectedCategory.name,
                    icon: selectedCategory.icon,
                    selected: true,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '为这个分类设定上限',
                        style: TextStyle(color: _mutedColor, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        selectedCategory.name,
                        style: const TextStyle(
                          color: _textColor,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: whiteCardDecoration(),
            child: TextField(
              controller: amountController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [AmountInputFormatter()],
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w900,
                color: _textColor,
              ),
              decoration: const InputDecoration(
                prefixText: '¥ ',
                hintText: '0.00',
                hintStyle: TextStyle(
                  color: Color(0x555B3A32),
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MinePage extends StatelessWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Navigator.push(context, appPageRoute((_) => const ProfilePage()));
            },
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: whiteCardDecoration(),
              child: Stack(
                children: [
                  Positioned(
                    right: 0,
                    top: 0,
                    child: CatPawMark(
                      size: 28,
                      color: _primaryColor.withValues(alpha: 0.14),
                    ),
                  ),
                  Row(
                    children: [
                      ProfileAvatar(
                        avatarDataUri: store.profileAvatarDataUri,
                        size: 72,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              store.profileNickname,
                              style: TextStyle(
                                fontSize: 20,
                                color: _textColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFFB48A7C),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          MineStatsCard(
            continuousDays: store.accountingDays,
            totalDays: store.totalAccountingDays,
            recordCount: store.records.length,
          ),
          const SizedBox(height: 18),
          MineTile(
            icon: Icons.notifications_rounded,
            title: '记账提醒',
            onTap: () {
              Navigator.push(
                context,
                appPageRoute((_) => const ReminderSettingsPage()),
              );
            },
          ),
          MineTile(
            icon: Icons.emoji_events_rounded,
            title: '成就徽章',
            onTap: () => showAchievementDialog(context, store),
          ),
          MineTile(
            icon: Icons.file_download_rounded,
            title: '导入账单',
            onTap: () {
              Navigator.push(
                context,
                appPageRoute((_) => const ImportBillPage()),
              );
            },
          ),
          MineTile(
            icon: Icons.file_upload_rounded,
            title: '导出账单',
            onTap: () {
              Navigator.push(
                context,
                appPageRoute((_) => const ExportBillPage()),
              );
            },
          ),
          MineTile(
            icon: Icons.info_rounded,
            title: '关于我们',
            onTap: () {
              Navigator.push(context, appPageRoute((_) => const AboutUsPage()));
            },
          ),
          MineTile(
            icon: Icons.delete_sweep_rounded,
            title: '清空数据',
            danger: true,
            onTap: () => confirmClearData(context, store),
          ),
        ],
      ),
    );
  }
}

class MineStatsCard extends StatelessWidget {
  const MineStatsCard({
    super.key,
    required this.continuousDays,
    required this.totalDays,
    required this.recordCount,
  });

  final int continuousDays;
  final int totalDays;
  final int recordCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: whiteCardDecoration(),
      child: Row(
        children: [
          Expanded(
            child: MineStatItem(
              icon: Icons.local_fire_department_rounded,
              label: '连续记账',
              value: '$continuousDays天',
              color: _primaryColor,
            ),
          ),
          Expanded(
            child: MineStatItem(
              icon: Icons.calendar_month_rounded,
              label: '累计记账',
              value: '$totalDays天',
              color: _accentColor,
            ),
          ),
          Expanded(
            child: MineStatItem(
              icon: Icons.receipt_long_rounded,
              label: '账单笔数',
              value: '$recordCount笔',
              color: _greenColor,
            ),
          ),
        ],
      ),
    );
  }
}

class MineStatItem extends StatelessWidget {
  const MineStatItem({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _textColor,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _mutedColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.avatarDataUri,
    required this.size,
  });

  final String? avatarDataUri;
  final double size;

  @override
  Widget build(BuildContext context) {
    Uint8List? avatarBytes;
    if (avatarDataUri != null) {
      try {
        avatarBytes = imageBytesFromDataUri(avatarDataUri!);
      } catch (_) {
        avatarBytes = null;
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.36),
      child: avatarBytes == null
          ? Image.asset(
              'assets/images/app_icon.png',
              width: size,
              height: size,
              fit: BoxFit.cover,
            )
          : Image.memory(
              avatarBytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
    );
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final TextEditingController nicknameController;
  String? avatarDataUri;
  String initialNickname = '';
  String? initialAvatarDataUri;
  bool initialized = false;
  bool allowPop = false;

  @override
  void initState() {
    super.initState();
    nicknameController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    final store = AppScope.of(context);
    nicknameController.text = store.profileNickname;
    avatarDataUri = store.profileAvatarDataUri;
    initialNickname = store.profileNickname;
    initialAvatarDataUri = store.profileAvatarDataUri;
    initialized = true;
  }

  @override
  void dispose() {
    nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        confirmLeaveIfNeeded();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: confirmLeaveIfNeeded,
          ),
          title: const Text('个人信息'),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 26),
                decoration: whiteCardDecoration(),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: pickAvatar,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ProfileAvatar(avatarDataUri: avatarDataUri, size: 96),
                          Positioned(
                            right: -4,
                            bottom: -4,
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: _primaryColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                              ),
                              child: const Icon(
                                Icons.photo_camera_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: pickAvatar,
                      child: const Text(
                        '更换头像',
                        style: TextStyle(
                          color: _primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (avatarDataUri != null)
                      TextButton(
                        onPressed: () => setState(() => avatarDataUri = null),
                        child: const Text(
                          '恢复默认头像',
                          style: TextStyle(
                            color: _mutedColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                decoration: whiteCardDecoration(),
                child: TextField(
                  controller: nicknameController,
                  maxLength: 12,
                  decoration: const InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                    icon: Icon(Icons.badge_rounded, color: _primaryColor),
                    labelText: '昵称',
                    labelStyle: TextStyle(color: _mutedColor),
                    hintText: '请输入昵称',
                  ),
                  style: const TextStyle(
                    color: _textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              CatPawPrimaryButton(label: '保存修改', onPressed: saveProfile),
            ],
          ),
        ),
      ),
    );
  }

  bool get hasUnsavedChanges {
    return nicknameController.text.trim() != initialNickname ||
        avatarDataUri != initialAvatarDataUri;
  }

  Future<void> confirmLeaveIfNeeded() async {
    if (!hasUnsavedChanges) {
      allowPop = true;
      if (mounted) Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('有未保存的修改'),
          content: const Text('昵称或头像还没有保存，确定要离开吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续编辑'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('不保存离开'),
            ),
          ],
        );
      },
    );
    if (discard == true && mounted) {
      allowPop = true;
      Navigator.pop(context);
    }
  }

  Future<void> pickAvatar() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        imageQuality: 80,
      );
      if (file == null) return;
      final dataUri = await recordPhotoDataUri(file);
      if (!mounted) return;
      setState(() => avatarDataUri = dataUri);
    } catch (_) {
      if (!mounted) return;
      showToast(context, '头像读取失败，请再试一次');
    }
  }

  Future<void> saveProfile() async {
    final nickname = nicknameController.text.trim();
    if (nickname.isEmpty) {
      showToast(context, '请输入昵称');
      return;
    }
    await AppScope.of(
      context,
    ).updateProfile(nickname: nickname, avatar: avatarDataUri);
    if (!mounted) return;
    allowPop = true;
    showToast(context, '个人信息已保存');
    Navigator.pop(context);
  }
}

class ReminderSettingsPage extends StatefulWidget {
  const ReminderSettingsPage({super.key});

  @override
  State<ReminderSettingsPage> createState() => _ReminderSettingsPageState();
}

class _ReminderSettingsPageState extends State<ReminderSettingsPage> {
  late bool enabled;
  late TimeOfDay reminderTime;
  late TextEditingController titleController;
  late TextEditingController messageController;
  bool initialized = false;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController();
    messageController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    final store = AppScope.of(context);
    enabled = store.reminderEnabled;
    reminderTime = TimeOfDay(
      hour: store.reminderHour,
      minute: store.reminderMinute,
    );
    titleController.text = store.reminderTitle;
    messageController.text = store.reminderMessage;
    initialized = true;
  }

  @override
  void dispose() {
    titleController.dispose();
    messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeLabel =
        '${twoDigits(reminderTime.hour)}:${twoDigits(reminderTime.minute)}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('记账提醒'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _primaryColor.withValues(alpha: 0.28),
                    width: 1.2,
                  ),
                  boxShadow: softShadow(),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '记账提醒',
                            style: TextStyle(
                              color: _textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Switch(
                          value: enabled,
                          activeThumbColor: Colors.white,
                          activeTrackColor: _primaryColor,
                          inactiveThumbColor: Colors.white,
                          inactiveTrackColor: const Color(0xFFFFC5D0),
                          onChanged: (value) => setState(() => enabled = value),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: DashedDivider(),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: pickReminderTime,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '提醒时间',
                                style: TextStyle(
                                  color: _textColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Text(
                              '每天 $timeLabel',
                              style: const TextStyle(
                                color: _textColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Color(0xFFB48A7C),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEFF3),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _primaryColor.withValues(alpha: 0.16),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.asset(
                                  'assets/images/app_icon.png',
                                  width: 42,
                                  height: 42,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  '喵记账提醒',
                                  style: TextStyle(
                                    color: _textColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const CatPawMark(size: 22),
                            ],
                          ),
                          const SizedBox(height: 12),
                          reminderInputRow(
                            label: '标题',
                            controller: titleController,
                            hintText: '主人，今天记账了吗~',
                            maxLength: 16,
                          ),
                          const SizedBox(height: 10),
                          reminderInputRow(
                            label: '内容',
                            controller: messageController,
                            hintText: '喵~今天你记账了吗？',
                            maxLength: 28,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7F3).withValues(alpha: 0.94),
              boxShadow: [
                BoxShadow(
                  color: Colors.brown.withValues(alpha: 0.06),
                  blurRadius: 14,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: saveSettings,
                style: FilledButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                child: const Text('保存提醒'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget reminderInputRow({
    required String label,
    required TextEditingController controller,
    required String hintText,
    required int maxLength,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: const TextStyle(
              color: _textColor,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFFD6C9)),
            ),
            alignment: Alignment.center,
            child: TextField(
              controller: controller,
              maxLength: maxLength,
              decoration: InputDecoration(
                hintText: hintText,
                counterText: '',
                border: InputBorder.none,
                isDense: true,
              ),
              style: const TextStyle(
                color: _textColor,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> pickReminderTime() async {
    var selectedHour = reminderTime.hour;
    var selectedMinute = reminderTime.minute;
    final picked = await showModalBottomSheet<TimeOfDay>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              height: 328,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              decoration: const BoxDecoration(
                color: Color(0xFFFFFBF8),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _primaryColor.withValues(alpha: 0.26),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text(
                          '取消',
                          style: TextStyle(color: _mutedColor),
                        ),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            '提醒时间',
                            style: TextStyle(
                              color: _textColor,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(
                          sheetContext,
                          TimeOfDay(hour: selectedHour, minute: selectedMinute),
                        ),
                        child: const Text(
                          '确定',
                          style: TextStyle(
                            color: _primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3F5),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: CupertinoPicker.builder(
                              scrollController: FixedExtentScrollController(
                                initialItem: selectedHour,
                              ),
                              itemExtent: 42,
                              selectionOverlay:
                                  const CupertinoPickerDefaultSelectionOverlay(
                                    background: Color(0x55FFFFFF),
                                  ),
                              onSelectedItemChanged: (index) {
                                setSheetState(() => selectedHour = index);
                              },
                              childCount: 24,
                              itemBuilder: (context, index) => Center(
                                child: Text(
                                  twoDigits(index),
                                  style: const TextStyle(
                                    color: _textColor,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const Text(
                            ':',
                            style: TextStyle(
                              color: _mutedColor,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Expanded(
                            child: CupertinoPicker.builder(
                              scrollController: FixedExtentScrollController(
                                initialItem: selectedMinute,
                              ),
                              itemExtent: 42,
                              selectionOverlay:
                                  const CupertinoPickerDefaultSelectionOverlay(
                                    background: Color(0x55FFFFFF),
                                  ),
                              onSelectedItemChanged: (index) {
                                setSheetState(() => selectedMinute = index);
                              },
                              childCount: 60,
                              itemBuilder: (context, index) => Center(
                                child: Text(
                                  twoDigits(index),
                                  style: const TextStyle(
                                    color: _textColor,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (picked == null) return;
    setState(() => reminderTime = picked);
  }

  Future<void> saveSettings() async {
    final store = AppScope.of(context);
    await store.updateReminderSettings(
      enabled: enabled,
      hour: reminderTime.hour,
      minute: reminderTime.minute,
      title: titleController.text,
      message: messageController.text,
    );
    if (!mounted) return;
    showToast(context, '提醒设置已保存');
    Navigator.pop(context);
  }
}

class ReminderSettingRow extends StatelessWidget {
  const ReminderSettingRow({
    super.key,
    required this.icon,
    required this.title,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: _primaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class ImportBillPage extends StatefulWidget {
  const ImportBillPage({super.key});

  @override
  State<ImportBillPage> createState() => _ImportBillPageState();
}

class _ImportBillPageState extends State<ImportBillPage> {
  List<AccountRecord> previewRecords = [];
  String? fileName;
  String? errorText;
  bool importing = false;

  @override
  Widget build(BuildContext context) {
    final expense = previewRecords
        .where((record) => record.type == RecordType.expense)
        .fold<double>(0, (sum, record) => sum + record.amount);
    final income = previewRecords
        .where((record) => record.type == RecordType.income)
        .fold<double>(0, (sum, record) => sum + record.amount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('导入账单'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExportSectionCard(
              icon: Icons.upload_file_rounded,
              title: '选择账单文件',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '支持 JSON / CSV / TXT。CSV 表头可用：类型、分类、金额、备注、时间。',
                    style: TextStyle(
                      color: _mutedColor,
                      fontSize: 13,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: importing ? null : pickImportFile,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primaryColor,
                      side: BorderSide(
                        color: _primaryColor.withValues(alpha: 0.5),
                      ),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.folder_open_rounded),
                    label: Text(fileName == null ? '选择文件' : '重新选择文件'),
                  ),
                  if (fileName != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      fileName!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _textColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorText!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _primaryColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            ExportSectionCard(
              icon: Icons.receipt_long_rounded,
              title: '导入预览',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ExportPreviewMetric(
                          label: '支出',
                          value: money(expense),
                          color: _primaryColor,
                        ),
                      ),
                      Expanded(
                        child: ExportPreviewMetric(
                          label: '收入',
                          value: money(income),
                          color: _greenColor,
                        ),
                      ),
                      Expanded(
                        child: ExportPreviewMetric(
                          label: '笔数',
                          value: '${previewRecords.length}笔',
                          color: _textColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (previewRecords.isEmpty)
                    Container(
                      height: 160,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _softColor.withValues(alpha: 0.58),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Text(
                        '选择文件后，会在这里预览账单',
                        style: TextStyle(
                          color: _mutedColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    ...previewRecords
                        .take(8)
                        .map(
                          (record) => ImportPreviewRecordRow(record: record),
                        ),
                  if (previewRecords.length > 8)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '还有 ${previewRecords.length - 8} 笔将在确认后一起导入',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _mutedColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            CatPawPrimaryButton(
              label: importing ? '导入中...' : '确认导入',
              onPressed: importing || previewRecords.isEmpty
                  ? () {}
                  : confirmImport,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> pickImportFile() async {
    setState(() {
      importing = true;
      errorText = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', 'csv', 'txt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() => importing = false);
        return;
      }
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw FormatException('文件读取失败，请换一个文件再试');
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      final parsed = parseImportedBillRecords(text);
      if (parsed.isEmpty) {
        throw FormatException('没有识别到账单记录');
      }
      setState(() {
        fileName = file.name;
        previewRecords = parsed;
        errorText = null;
        importing = false;
      });
    } on FormatException catch (error) {
      setState(() {
        previewRecords = [];
        errorText = error.message;
        importing = false;
      });
    } catch (_) {
      setState(() {
        previewRecords = [];
        errorText = '导入失败，请确认文件格式是否正确';
        importing = false;
      });
    }
  }

  Future<void> confirmImport() async {
    if (previewRecords.isEmpty || importing) return;
    setState(() => importing = true);
    final store = AppScope.of(context);
    final existingKeys = store.records.map(importDuplicateKey).toSet();
    final recordsToImport = <AccountRecord>[];
    var skippedCount = 0;
    for (final record in previewRecords) {
      final key = importDuplicateKey(record);
      if (existingKeys.contains(key)) {
        skippedCount++;
      } else {
        existingKeys.add(key);
        recordsToImport.add(record);
      }
    }

    await store.addRecords(recordsToImport);
    if (!mounted) return;
    if (recordsToImport.isEmpty) {
      setState(() => importing = false);
      showToast(context, '没有新账单，已跳过 $skippedCount 笔重复记录');
      return;
    }
    showToast(
      context,
      skippedCount > 0
          ? '已导入 ${recordsToImport.length} 笔，跳过 $skippedCount 笔重复记录'
          : '已导入 ${recordsToImport.length} 笔账单',
    );
    Navigator.pop(context);
  }
}

class ImportPreviewRecordRow extends StatelessWidget {
  const ImportPreviewRecordRow({super.key, required this.record});

  final AccountRecord record;

  @override
  Widget build(BuildContext context) {
    final isIncome = record.type == RecordType.income;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _softColor.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CategoryIconView(category: record.category, icon: record.icon),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.category,
                  style: const TextStyle(
                    color: _textColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    formatDate(record.date),
                    formatTime(record.date),
                    if (record.note.trim().isNotEmpty) record.note.trim(),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _mutedColor, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            '${isIncome ? '+' : '-'} ${money(record.amount)}',
            style: TextStyle(
              color: isIncome ? _greenColor : _textColor,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class ExportBillPage extends StatefulWidget {
  const ExportBillPage({super.key});

  @override
  State<ExportBillPage> createState() => _ExportBillPageState();
}

class _ExportBillPageState extends State<ExportBillPage> {
  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  int rangeMonths = 1;
  String exportFormat = 'PNG';
  bool includeName = true;
  bool includeTime = true;
  bool includeAmount = true;
  bool includeNote = true;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final periodStart = rangeMonths == 3
        ? DateTime(selectedMonth.year, selectedMonth.month - 2)
        : selectedMonth;
    final periodEnd = DateTime(selectedMonth.year, selectedMonth.month + 1);
    final records =
        store.records
            .where(
              (record) =>
                  !record.date.isBefore(periodStart) &&
                  record.date.isBefore(periodEnd),
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final expense = records
        .where((record) => record.type == RecordType.expense)
        .fold<double>(0, (sum, record) => sum + record.amount);
    final income = records
        .where((record) => record.type == RecordType.income)
        .fold<double>(0, (sum, record) => sum + record.amount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('导出账单'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExportSectionCard(
              icon: Icons.calendar_month_rounded,
              title: '选择导出月份',
              child: Column(
                children: [
                  Container(
                    height: 58,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: _primaryColor.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => shiftMonth(-1),
                          icon: const Icon(
                            Icons.chevron_left_rounded,
                            color: Color(0xFFB48A7C),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            exportPeriodTitle(periodStart, selectedMonth),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _textColor,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => shiftMonth(1),
                          icon: const Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFFE8A1A4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ExportQuickButton(
                          label: '本月',
                          selected:
                              rangeMonths == 1 &&
                              selectedMonth.year == DateTime.now().year &&
                              selectedMonth.month == DateTime.now().month,
                          onTap: () => setState(() {
                            final now = DateTime.now();
                            selectedMonth = DateTime(now.year, now.month);
                            rangeMonths = 1;
                          }),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ExportQuickButton(
                          label: '上月',
                          selected:
                              rangeMonths == 1 &&
                              selectedMonth.year ==
                                  DateTime(
                                    DateTime.now().year,
                                    DateTime.now().month - 1,
                                  ).year &&
                              selectedMonth.month ==
                                  DateTime(
                                    DateTime.now().year,
                                    DateTime.now().month - 1,
                                  ).month,
                          onTap: () => setState(() {
                            final now = DateTime.now();
                            selectedMonth = DateTime(now.year, now.month - 1);
                            rangeMonths = 1;
                          }),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ExportQuickButton(
                          label: '最近3个月',
                          selected: rangeMonths == 3,
                          onTap: () => setState(() {
                            final now = DateTime.now();
                            selectedMonth = DateTime(now.year, now.month);
                            rangeMonths = 3;
                          }),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ExportSectionCard(
              icon: Icons.assignment_turned_in_rounded,
              title: '导出内容',
              child: Column(
                children: [
                  ExportCheckRow(
                    title: '账单名称',
                    icon: Icons.pets_rounded,
                    value: includeName,
                    onChanged: (value) => setState(() => includeName = value),
                  ),
                  ExportCheckRow(
                    title: '记录时间',
                    icon: Icons.calendar_month_rounded,
                    value: includeTime,
                    onChanged: (value) => setState(() => includeTime = value),
                  ),
                  ExportCheckRow(
                    title: '花费金额',
                    icon: Icons.monetization_on_rounded,
                    value: includeAmount,
                    onChanged: (value) => setState(() => includeAmount = value),
                  ),
                  ExportCheckRow(
                    title: '账单备注',
                    icon: Icons.chat_bubble_outline_rounded,
                    value: includeNote,
                    onChanged: (value) => setState(() => includeNote = value),
                    showDivider: false,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ExportSectionCard(
              icon: Icons.description_rounded,
              title: '导出格式',
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 12.0;
                  final itemWidth = (constraints.maxWidth - gap) / 2;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final item in const ['PNG', 'JSON', 'CSV', 'TXT'])
                        SizedBox(
                          width: itemWidth,
                          child: ExportFormatButton(
                            label: item,
                            selected: exportFormat == item,
                            onTap: () => setState(() => exportFormat = item),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            ExportSectionCard(
              icon: Icons.visibility_rounded,
              title: '导出预览',
              child: ExportPreviewTicket(
                periodLabel: exportPeriodSubtitle(periodStart, selectedMonth),
                expense: expense,
                income: income,
                count: records.length,
                exportFormat: exportFormat,
              ),
            ),
            const SizedBox(height: 20),
            CatPawPrimaryButton(
              label: exportFormat == 'PNG' ? '生成账单图片' : '导出账单文件',
              onPressed: () {
                final periodLabel = exportPeriodSubtitle(
                  periodStart,
                  selectedMonth,
                );
                if (exportFormat == 'PNG') {
                  Navigator.push(
                    context,
                    appPageRoute(
                      (_) => ExportBillPreviewPage(
                        periodLabel: periodLabel,
                        records: records,
                        expense: expense,
                        income: income,
                        exportFormat: exportFormat,
                        includeName: includeName,
                        includeTime: includeTime,
                        includeAmount: includeAmount,
                        includeNote: includeNote,
                      ),
                    ),
                  );
                  return;
                }
                exportBillDataFile(
                  context: context,
                  records: records,
                  periodLabel: periodLabel,
                  format: exportFormat,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void shiftMonth(int value) {
    setState(() {
      selectedMonth = DateTime(selectedMonth.year, selectedMonth.month + value);
    });
  }
}

class ExportSectionCard extends StatelessWidget {
  const ExportSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: whiteCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _primaryColor, size: 24),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  color: _textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class ExportQuickButton extends StatelessWidget {
  const ExportQuickButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? _primaryColor : _textColor,
        side: BorderSide(
          color: selected ? _primaryColor : _mutedColor.withValues(alpha: 0.24),
        ),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(vertical: 13),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}

class ExportCheckRow extends StatelessWidget {
  const ExportCheckRow({
    super.key,
    required this.title,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.showDivider = true,
  });

  final String title;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: value
                        ? _primaryColor
                        : _primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    value ? Icons.check_rounded : Icons.remove_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: _textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(icon, color: _primaryColor.withValues(alpha: 0.72)),
              ],
            ),
          ),
          if (showDivider)
            Divider(
              height: 1,
              color: _primaryColor.withValues(alpha: 0.12),
              indent: 44,
            ),
        ],
      ),
    );
  }
}

class ExportFormatButton extends StatelessWidget {
  const ExportFormatButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.52),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? _primaryColor
                : _mutedColor.withValues(alpha: 0.22),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    label == 'PNG'
                        ? Icons.image_rounded
                        : Icons.description_rounded,
                    color: selected ? _primaryColor : _mutedColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? _primaryColor : _textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Positioned(
                right: -8,
                top: -8,
                child: CircleAvatar(
                  radius: 13,
                  backgroundColor: _primaryColor,
                  child: Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ExportPreviewTicket extends StatelessWidget {
  const ExportPreviewTicket({
    super.key,
    required this.periodLabel,
    required this.expense,
    required this.income,
    required this.count,
    required this.exportFormat,
  });

  final String periodLabel;
  final double expense;
  final double income;
  final int count;
  final String exportFormat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _primaryColor.withValues(alpha: 0.22),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/images/app_icon.png',
                  width: 42,
                  height: 42,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '喵喵记账',
                      style: TextStyle(
                        color: _textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '$periodLabel账单',
                      style: const TextStyle(color: _mutedColor),
                    ),
                  ],
                ),
              ),
              Text(
                exportFormat,
                style: const TextStyle(
                  color: _primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ExportSummaryLine(label: '收支总览', value: '支出 ${money(expense)}'),
          ExportSummaryLine(label: '收入合计', value: money(income)),
          ExportSummaryLine(label: '记录笔数', value: '共 $count 笔'),
          ExportSummaryLine(
            label: '导出时间',
            value:
                '${formatDate(DateTime.now())} ${formatTime(DateTime.now())}',
            showDivider: false,
          ),
        ],
      ),
    );
  }
}

class ExportSummaryLine extends StatelessWidget {
  const ExportSummaryLine({
    super.key,
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (showDivider)
          Divider(color: _primaryColor.withValues(alpha: 0.14), height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Text(label, style: const TextStyle(color: _textColor)),
              const Spacer(),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: _primaryColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ExportBillPreviewPage extends StatefulWidget {
  const ExportBillPreviewPage({
    super.key,
    required this.periodLabel,
    required this.records,
    required this.expense,
    required this.income,
    required this.exportFormat,
    required this.includeName,
    required this.includeTime,
    required this.includeAmount,
    required this.includeNote,
  });

  final String periodLabel;
  final List<AccountRecord> records;
  final double expense;
  final double income;
  final String exportFormat;
  final bool includeName;
  final bool includeTime;
  final bool includeAmount;
  final bool includeNote;

  @override
  State<ExportBillPreviewPage> createState() => _ExportBillPreviewPageState();
}

class _ExportBillPreviewPageState extends State<ExportBillPreviewPage> {
  final GlobalKey previewKey = GlobalKey();
  bool saving = false;

  @override
  Widget build(BuildContext context) {
    final sortedRecords = [...widget.records]
      ..sort((a, b) => b.date.compareTo(a.date));
    final groups = <DateTime, List<AccountRecord>>{};
    for (final record in sortedRecords) {
      final day = DateTime(
        record.date.year,
        record.date.month,
        record.date.day,
      );
      groups.putIfAbsent(day, () => []).add(record);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('账单图片预览'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RepaintBoundary(
              key: previewKey,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBF8),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: _primaryColor.withValues(alpha: 0.18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _primaryColor.withValues(alpha: 0.08),
                      blurRadius: 22,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.asset(
                            'assets/images/app_icon.png',
                            width: 54,
                            height: 54,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (widget.includeName)
                                const Text(
                                  '喵喵记账',
                                  style: TextStyle(
                                    color: _textColor,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              Text(
                                '${widget.periodLabel}账单',
                                style: const TextStyle(
                                  color: _mutedColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: _primaryColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            widget.exportFormat,
                            style: const TextStyle(
                              color: _primaryColor,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _softColor.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: ExportPreviewMetric(
                              label: '支出',
                              value: money(widget.expense),
                              color: _primaryColor,
                            ),
                          ),
                          Expanded(
                            child: ExportPreviewMetric(
                              label: '收入',
                              value: money(widget.income),
                              color: _greenColor,
                            ),
                          ),
                          Expanded(
                            child: ExportPreviewMetric(
                              label: '笔数',
                              value: '${widget.records.length}笔',
                              color: _textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Icon(
                          Icons.pets_rounded,
                          color: _primaryColor,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '本期明细',
                          style: TextStyle(
                            color: _textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Spacer(),
                        if (widget.includeTime)
                          Text(
                            '导出 ${formatDate(DateTime.now())} ${formatTime(DateTime.now())}',
                            style: const TextStyle(
                              color: Color(0xFFB8AAA4),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (widget.records.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 34),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          '这个时间段还没有账单',
                          style: TextStyle(
                            color: _mutedColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else
                      ...groups.entries.map(
                        (entry) => ExportPreviewRecordGroup(
                          day: entry.key,
                          records: entry.value,
                          includeTime: widget.includeTime,
                          includeAmount: widget.includeAmount,
                          includeNote: widget.includeNote,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            CatPawPrimaryButton(
              label: saving ? '保存中...' : '保存到相册',
              onPressed: saving ? () {} : savePreviewToGallery,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> savePreviewToGallery() async {
    if (kIsWeb) {
      showToast(context, '网页预览不能直接保存到手机，请在手机App中使用');
      return;
    }
    setState(() => saving = true);
    try {
      final boundary =
          previewKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('preview boundary missing');
      }
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('image bytes missing');
      }
      final bytes = byteData.buffer.asUint8List();
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        await Gal.requestAccess();
      }
      await Gal.putImageBytes(
        bytes,
        name:
            '喵记账_${widget.periodLabel}_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      if (mounted) showToast(context, '账单图片已保存到相册');
    } catch (_) {
      if (mounted) showToast(context, '保存失败，请检查相册权限后再试');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class ExportPreviewMetric extends StatelessWidget {
  const ExportPreviewMetric({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _mutedColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class ExportPreviewRecordGroup extends StatelessWidget {
  const ExportPreviewRecordGroup({
    super.key,
    required this.day,
    required this.records,
    required this.includeTime,
    required this.includeAmount,
    required this.includeNote,
  });

  final DateTime day;
  final List<AccountRecord> records;
  final bool includeTime;
  final bool includeAmount;
  final bool includeNote;

  @override
  Widget build(BuildContext context) {
    final expenseTotal = records
        .where((record) => record.type == RecordType.expense)
        .fold<double>(0, (sum, record) => sum + record.amount);
    final incomeTotal = records
        .where((record) => record.type == RecordType.income)
        .fold<double>(0, (sum, record) => sum + record.amount);
    final summaries = [
      if (expenseTotal > 0) '支出 ${money(expenseTotal)}',
      if (incomeTotal > 0) '收入 ${money(incomeTotal)}',
    ].join('  ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _primaryColor.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: _primaryColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${formatMonthDay(day)}  星期${weekdayLabel(day.weekday)}',
                style: const TextStyle(
                  color: Color(0xFFAFA5A0),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  summaries,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFAFA5A0),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...records.map(
            (record) => ExportPreviewRecordRow(
              record: record,
              includeTime: includeTime,
              includeAmount: includeAmount,
              includeNote: includeNote,
            ),
          ),
        ],
      ),
    );
  }
}

class ExportPreviewRecordRow extends StatelessWidget {
  const ExportPreviewRecordRow({
    super.key,
    required this.record,
    required this.includeTime,
    required this.includeAmount,
    required this.includeNote,
  });

  final AccountRecord record;
  final bool includeTime;
  final bool includeAmount;
  final bool includeNote;

  @override
  Widget build(BuildContext context) {
    final isIncome = record.type == RecordType.income;
    final note = record.note.trim();
    final details = [
      if (includeTime) formatTime(record.date),
      if (includeNote && note.isNotEmpty) note,
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBF8),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFEBD7A9)),
            ),
            child: Center(
              child: CategoryIconView(
                category: record.category,
                icon: record.icon,
                size: 23,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    details.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFAFA5A0),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (includeAmount) ...[
            const SizedBox(width: 10),
            Text(
              '${isIncome ? '+' : '-'} ${money(record.amount)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: isIncome ? _greenColor : _textColor,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class AboutUsPage extends StatefulWidget {
  const AboutUsPage({super.key});

  @override
  State<AboutUsPage> createState() => _AboutUsPageState();
}

class _AboutUsPageState extends State<AboutUsPage> {
  late final Future<PackageInfo> packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('关于我们'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
              decoration: whiteCardDecoration(),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset(
                      'assets/images/app_icon.png',
                      width: 82,
                      height: 82,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Image.asset(
                    'assets/images/app_name.png',
                    width: 160,
                    height: 64,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '一款可爱的本地记账小工具',
                    style: TextStyle(
                      color: _mutedColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const AboutInfoCard(
              title: '软件简介',
              content: '喵记账用于记录日常支出、收入、预算和储蓄进度，帮助你用更轻松的方式了解每月花销。',
              icon: Icons.auto_awesome_rounded,
            ),
            FutureBuilder<PackageInfo>(
              future: packageInfo,
              builder: (context, snapshot) {
                final version = snapshot.data?.version ?? '读取中';
                return AboutInfoCard(
                  title: '基础信息',
                  content: '版本：$version\n适用场景：个人日常记账、分类预算、消费统计',
                  icon: Icons.apps_rounded,
                );
              },
            ),
            const AboutInfoCard(
              title: '数据说明',
              content: '所有账单、预算和储蓄数据会自动保存在本机，不会上传到云端。',
              icon: Icons.verified_user_rounded,
            ),
            const AboutInfoCard(
              title: '功能能力',
              content: '支持账单记录、月度预算、分类预算、统计图表、账本提醒和成就徽章。',
              icon: Icons.favorite_rounded,
            ),
          ],
        ),
      ),
    );
  }
}

class AboutInfoCard extends StatelessWidget {
  const AboutInfoCard({
    super.key,
    required this.title,
    required this.content,
    required this.icon,
  });

  final String title;
  final String content;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: whiteCardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _softColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: _primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  content,
                  style: const TextStyle(
                    color: _mutedColor,
                    fontSize: 13,
                    height: 1.45,
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

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const CatPawMark(size: 20, color: _primaryColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            color: _textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class TodayOverviewDetailPage extends StatefulWidget {
  const TodayOverviewDetailPage({super.key});

  @override
  State<TodayOverviewDetailPage> createState() =>
      _TodayOverviewDetailPageState();
}

class _TodayOverviewDetailPageState extends State<TodayOverviewDetailPage> {
  RecordType selectedType = RecordType.expense;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final todayRecords = store.recordsForRange(StatsRange.day);
    final expenseRecords = todayRecords
        .where((record) => record.type == RecordType.expense)
        .toList();
    final incomeRecords = todayRecords
        .where((record) => record.type == RecordType.income)
        .toList();
    final selectedRecords = selectedType == RecordType.expense
        ? expenseRecords
        : incomeRecords;
    final todayExpense = expenseRecords.fold<double>(
      0,
      (sum, record) => sum + record.amount,
    );
    final todayIncome = incomeRecords.fold<double>(
      0,
      (sum, record) => sum + record.amount,
    );
    final todayBalance = todayIncome - todayExpense;

    return Scaffold(
      appBar: AppBar(
        title: const Text('今日概览'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TodayDetailSummaryCard(
                    expense: todayExpense,
                    income: todayIncome,
                    balance: todayBalance,
                  ),
                  const SizedBox(height: 16),
                  TodayRecordTabs(
                    value: selectedType,
                    expenseCount: expenseRecords.length,
                    incomeCount: incomeRecords.length,
                    onChanged: (value) => setState(() => selectedType = value),
                  ),
                  const SizedBox(height: 14),
                  SectionTitle(
                    title: selectedType == RecordType.expense ? '今日支出' : '今日收入',
                  ),
                  const SizedBox(height: 12),
                  if (selectedRecords.isEmpty)
                    HomeRecordEmptyCard(
                      height: math.max(
                        360,
                        MediaQuery.sizeOf(context).height - 360,
                      ),
                      title: selectedType == RecordType.expense
                          ? '喵~今天还没有任何支出哟'
                          : '喵~今天还没有任何收入哟',
                      subtitle: '去「记账」页添加账单后，这里会自动同步显示',
                    )
                  else
                    RecordGroupList(records: selectedRecords),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TodayDetailSummaryCard extends StatelessWidget {
  const TodayDetailSummaryCard({
    super.key,
    required this.expense,
    required this.income,
    required this.balance,
  });

  final double expense;
  final double income;
  final double balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: whiteCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HomeInfoCardTitle(title: '今日汇总'),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: HomeTodayMetric(
                  title: '支出',
                  value: money(expense),
                  valueColor: _textColor,
                  backgroundColor: const Color(0xFFFFBFC9),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: HomeTodayMetric(
                  title: '收入',
                  value: money(income),
                  valueColor: _textColor,
                  backgroundColor: const Color(0xFFFFE2AE),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: HomeTodayMetric(
                  title: '结余',
                  value: money(balance),
                  valueColor: balance >= 0 ? _greenColor : _primaryColor,
                  backgroundColor: const Color(0xFFD8EFCF),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class TodayRecordTabs extends StatelessWidget {
  const TodayRecordTabs({
    super.key,
    required this.value,
    required this.expenseCount,
    required this.incomeCount,
    required this.onChanged,
  });

  final RecordType value;
  final int expenseCount;
  final int incomeCount;
  final ValueChanged<RecordType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _softColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          TodayRecordTabButton(
            label: '支出',
            count: expenseCount,
            selected: value == RecordType.expense,
            onTap: () => onChanged(RecordType.expense),
          ),
          TodayRecordTabButton(
            label: '收入',
            count: incomeCount,
            selected: value == RecordType.income,
            onTap: () => onChanged(RecordType.income),
          ),
        ],
      ),
    );
  }
}

class TodayRecordTabButton extends StatelessWidget {
  const TodayRecordTabButton({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? _primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$label $count',
            style: TextStyle(
              color: selected ? Colors.white : _mutedColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class RecordGroupList extends StatelessWidget {
  const RecordGroupList({super.key, required this.records});

  final List<AccountRecord> records;

  @override
  Widget build(BuildContext context) {
    final sortedRecords = [...records]
      ..sort((a, b) => b.date.compareTo(a.date));
    final groups = <DateTime, List<AccountRecord>>{};
    for (final record in sortedRecords) {
      final day = DateTime(
        record.date.year,
        record.date.month,
        record.date.day,
      );
      groups.putIfAbsent(day, () => []).add(record);
    }

    return Column(
      children: groups.entries.map((entry) {
        final dayRecords = entry.value;
        final expenseTotal = dayRecords
            .where((record) => record.type == RecordType.expense)
            .fold<double>(0, (sum, record) => sum + record.amount);
        final incomeTotal = dayRecords
            .where((record) => record.type == RecordType.income)
            .fold<double>(0, (sum, record) => sum + record.amount);
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 2),
          decoration: whiteCardDecoration(),
          child: Column(
            children: [
              RecordDateHeader(
                day: entry.key,
                expenseTotal: expenseTotal,
                incomeTotal: incomeTotal,
              ),
              ...dayRecords.map((record) => CompactRecordItem(record: record)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class RecordDateHeader extends StatelessWidget {
  const RecordDateHeader({
    super.key,
    required this.day,
    required this.expenseTotal,
    required this.incomeTotal,
  });

  final DateTime day;
  final double expenseTotal;
  final double incomeTotal;

  @override
  Widget build(BuildContext context) {
    final summaries = [
      if (expenseTotal > 0) '支出：${money(expenseTotal)}',
      if (incomeTotal > 0) '收入：${money(incomeTotal)}',
    ].join('  ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: _primaryColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            formatMonthDay(day),
            style: const TextStyle(
              color: Color(0xFFAFA5A0),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '星期${weekdayLabel(day.weekday)}',
            style: const TextStyle(
              color: Color(0xFFAFA5A0),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              summaries,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFFAFA5A0),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CompactRecordItem extends StatelessWidget {
  const CompactRecordItem({super.key, required this.record});

  final AccountRecord record;

  @override
  Widget build(BuildContext context) {
    final isIncome = record.type == RecordType.income;
    final note = record.note.trim();
    final subtitle = note.isEmpty
        ? formatTime(record.date)
        : '$note · ${formatTime(record.date)}';
    return Dismissible(
      key: ValueKey('compact-${record.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.only(right: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: _primaryColor,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return confirmDeleteRecordIntent(context, record);
      },
      onDismissed: (_) async {
        await AppScope.of(context).deleteRecord(record.id);
        if (context.mounted) showToast(context, '已删除记录');
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.push(
            context,
            appPageRoute((_) => RecordDetailPage(recordId: record.id)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFEBD7A9)),
                ),
                child: Center(
                  child: CategoryIconView(
                    category: record.category,
                    icon: record.icon,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFAFA5A0),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 128,
                child: Text(
                  '${isIncome ? '+' : '-'} ${money(record.amount)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: isIncome ? _greenColor : _textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RecordItem extends StatelessWidget {
  const RecordItem({super.key, required this.record});

  final AccountRecord record;

  @override
  Widget build(BuildContext context) {
    final isIncome = record.type == RecordType.income;
    return Dismissible(
      key: ValueKey(record.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.only(right: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: _primaryColor,
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return confirmDeleteRecordIntent(context, record);
      },
      onDismissed: (_) async {
        await AppScope.of(context).deleteRecord(record.id);
        if (context.mounted) showToast(context, '已删除记录');
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          Navigator.push(
            context,
            appPageRoute((_) => RecordDetailPage(recordId: record.id)),
          );
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: whiteCardDecoration(),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: _softColor,
                child: CategoryIconView(
                  category: record.category,
                  icon: record.icon,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.category,
                      style: const TextStyle(
                        color: _textColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      recordListSubtitle(record),
                      style: const TextStyle(
                        color: Color(0xFFB48A7C),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(
                '${isIncome ? '+' : '-'} ${money(record.amount)}',
                style: TextStyle(
                  color: isIncome ? _greenColor : _primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RecordDetailPage extends StatelessWidget {
  const RecordDetailPage({super.key, required this.recordId});

  final String recordId;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final record = store.recordById(recordId);

    if (record == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('账单详情'),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
        ),
        body: const Center(child: Text('这笔记录已经不存在了')),
      );
    }

    final isIncome = record.type == RecordType.income;
    return Scaffold(
      appBar: AppBar(
        title: const Text('账单详情'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: whiteCardDecoration(),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: _softColor,
                    child: CategoryIconView(
                      category: record.category,
                      icon: record.icon,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    record.category,
                    style: const TextStyle(
                      color: _textColor,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${isIncome ? '+' : '-'} ${money(record.amount)}',
                    style: TextStyle(
                      color: isIncome ? _greenColor : _primaryColor,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            DetailRow(
              icon: Icons.swap_vert_rounded,
              title: '类型',
              value: isIncome ? '收入' : '支出',
            ),
            DetailRow(
              icon: Icons.calendar_month_rounded,
              title: '日期',
              value: '${formatDate(record.date)} ${formatTime(record.date)}',
            ),
            DetailRow(
              icon: Icons.edit_note_rounded,
              title: '备注',
              value: record.note.isEmpty ? '无备注' : record.note,
            ),
            if (record.photoDataUris.isNotEmpty) ...[
              const SizedBox(height: 10),
              DetailPhotoCard(photoDataUris: record.photoDataUris),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    appPageRoute((_) => EditRecordPage(recordId: record.id)),
                  );
                },
                icon: const Icon(Icons.edit_rounded),
                label: const Text('编辑'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primaryColor,
                  side: const BorderSide(color: _primaryColor),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: () => confirmDeleteRecord(context, store, record),
                icon: const Icon(Icons.delete_rounded),
                label: const Text('删除'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primaryColor,
                  side: const BorderSide(color: _primaryColor),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EditRecordPage extends StatefulWidget {
  const EditRecordPage({super.key, required this.recordId});

  final String recordId;

  @override
  State<EditRecordPage> createState() => _EditRecordPageState();
}

class _EditRecordPageState extends State<EditRecordPage> {
  final amountController = TextEditingController();
  final noteController = TextEditingController();
  final List<String> photoDataUris = [];
  RecordType type = RecordType.expense;
  int selectedCategoryIndex = 0;
  DateTime selectedDate = DateTime.now();
  bool initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    final record = AppScope.of(context).recordById(widget.recordId);
    if (record == null) return;
    type = record.type;
    selectedDate = record.date;
    amountController.text = record.amount.toStringAsFixed(2);
    noteController.text = record.note;
    photoDataUris
      ..clear()
      ..addAll(record.photoDataUris);
    final categories = type == RecordType.expense
        ? expenseCategories
        : incomeCategories;
    selectedCategoryIndex = math.max(
      0,
      categories.indexWhere((category) => category.name == record.category),
    );
    initialized = true;
  }

  @override
  void dispose() {
    amountController.dispose();
    noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existingRecord = AppScope.of(context).recordById(widget.recordId);
    if (existingRecord == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('编辑账单'),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
        ),
        body: const Center(child: Text('这笔记录已经不存在了')),
      );
    }

    final categories = type == RecordType.expense
        ? expenseCategories
        : incomeCategories;
    final selectedCategory = categories[selectedCategoryIndex];

    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑账单'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
      ),
      body: Column(
        children: [
          RecordAmountPanel(
            type: type,
            amountController: amountController,
            onTypeChanged: (value) {
              setState(() {
                type = value;
                selectedCategoryIndex = 0;
              });
            },
            helperText: type == RecordType.expense
                ? '一起喵～记下这笔支出吧'
                : '收入到账，快乐加一笔',
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              child: Column(
                children: [
                  const SectionTitle(title: '分类选择'),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: categories.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.85,
                        ),
                    itemBuilder: (context, index) {
                      final item = categories[index];
                      final selected = index == selectedCategoryIndex;
                      return CategoryTile(
                        option: item,
                        selected: selected,
                        onTap: () =>
                            setState(() => selectedCategoryIndex = index),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          RecordBottomPanel(
            noteController: noteController,
            photoDataUris: photoDataUris,
            selectedDate: selectedDate,
            onPickDate: _pickDate,
            onPickTime: _pickTime,
            onAddPhoto: _addPhotos,
            onRemovePhoto: _removePhoto,
            onSave: () => _saveRecord(existingRecord, selectedCategory),
            buttonText: '保存修改',
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('zh', 'CN'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: _primaryColor),
          ),
          child: child!,
        );
      },
    );
    if (date == null) return;
    setState(() {
      selectedDate = DateTime(
        date.year,
        date.month,
        date.day,
        selectedDate.hour,
        selectedDate.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final time = await showWheelTimePicker(
      context,
      initialTime: TimeOfDay.fromDateTime(selectedDate),
      title: '记账时间',
    );
    if (time == null) return;
    setState(() {
      selectedDate = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _saveRecord(
    AccountRecord existingRecord,
    CategoryOption selectedCategory,
  ) async {
    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || amount <= 0) {
      showToast(context, '请输入有效金额');
      return;
    }

    final store = AppScope.of(context);
    final previousAchievements = unlockedAchievementIds(store);
    await store.updateRecord(
      AccountRecord(
        id: existingRecord.id,
        type: type,
        category: selectedCategory.name,
        icon: selectedCategory.icon,
        amount: amount,
        note: noteController.text.trim(),
        date: selectedDate,
        photoDataUris: List.unmodifiable(photoDataUris),
      ),
    );
    if (!mounted) return;
    showNewAchievementToast(
      context,
      previousAchievements: previousAchievements,
      store: store,
      fallbackMessage: '账单已更新',
    );
    Navigator.pop(context);
  }

  Future<void> _addPhotos() async {
    final pickedPhotos = await pickRecordPhotos(
      context,
      currentCount: photoDataUris.length,
    );
    if (pickedPhotos.isEmpty || !mounted) return;
    setState(() => photoDataUris.addAll(pickedPhotos));
  }

  void _removePhoto(int index) {
    setState(() => photoDataUris.removeAt(index));
  }
}

class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: whiteCardDecoration(),
      child: Row(
        children: [
          Icon(icon, color: _primaryColor),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              color: _textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(color: _mutedColor),
            ),
          ),
        ],
      ),
    );
  }
}

class DetailPhotoCard extends StatelessWidget {
  const DetailPhotoCard({super.key, required this.photoDataUris});

  final List<String> photoDataUris;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: whiteCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.photo_library_rounded, color: _primaryColor),
              SizedBox(width: 12),
              Text(
                '照片',
                style: TextStyle(
                  color: _textColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: photoDataUris.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, index) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  imageBytesFromDataUri(photoDataUris[index]),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: _softColor,
                    child: const Icon(
                      Icons.broken_image_rounded,
                      color: _mutedColor,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class InputLikeTile extends StatelessWidget {
  const InputLikeTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: whiteCardDecoration(),
        child: Row(
          children: [
            Icon(icon, color: _primaryColor),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                color: _textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Text(value, style: const TextStyle(color: Color(0xFFB48A7C))),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFB48A7C)),
          ],
        ),
      ),
    );
  }
}

class PercentRow extends StatelessWidget {
  const PercentRow({super.key, required this.stat, required this.total});

  final CategoryStat stat;
  final double total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(stat.icon, color: _primaryColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              stat.name,
              style: const TextStyle(
                color: _textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Text(
            '${(stat.ratio * 100).toStringAsFixed(1)}%',
            style: const TextStyle(color: _mutedColor),
          ),
          const SizedBox(width: 18),
          Text(
            money(stat.amount),
            style: const TextStyle(
              color: _primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class MineTile extends StatelessWidget {
  const MineTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.danger = false,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = danger ? _primaryColor : _textColor;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: whiteCardDecoration(),
        child: Row(
          children: [
            Icon(icon, color: _primaryColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: const TextStyle(color: _mutedColor, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFB48A7C)),
          ],
        ),
      ),
    );
  }
}

class MineSwitchTile extends StatelessWidget {
  const MineSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        decoration: whiteCardDecoration(),
        child: Row(
          children: [
            Icon(icon, color: _primaryColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _textColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: _mutedColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFB48A7C)),
            Switch(
              value: value,
              activeThumbColor: _primaryColor,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
      decoration: whiteCardDecoration(),
      child: Stack(
        children: [
          Positioned(
            right: 12,
            top: 0,
            child: CatPawMark(
              size: 24,
              color: _primaryColor.withValues(alpha: 0.14),
            ),
          ),
          Center(
            child: Column(
              children: [
                CatEmptyBadge(icon: icon),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: const TextStyle(
                    color: _textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: _mutedColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showBudgetDialog(BuildContext context, AppStore store) async {
  final budgetText = store.monthlyBudget > 0
      ? store.monthlyBudget.toStringAsFixed(2)
      : '';
  final controller = TextEditingController(text: budgetText);
  if (budgetText.isNotEmpty) {
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: budgetText.length,
    );
  }
  final value = await showAmountDialog(
    context: context,
    title: '设置月度预算',
    controller: controller,
  );
  controller.dispose();
  if (value != null) {
    final previousAchievements = unlockedAchievementIds(store);
    await store.updateBudget(value);
    if (context.mounted) {
      showNewAchievementToast(
        context,
        previousAchievements: previousAchievements,
        store: store,
      );
    }
  }
}

Future<void> showAddSavingDialog(BuildContext context, AppStore store) async {
  final controller = TextEditingController();
  final value = await showAmountDialog(
    context: context,
    title: '存入储蓄目标',
    controller: controller,
  );
  controller.dispose();
  if (value != null) {
    final previousAchievements = unlockedAchievementIds(store);
    await store.addSaving(value);
    if (context.mounted) {
      showNewAchievementToast(
        context,
        previousAchievements: previousAchievements,
        store: store,
      );
    }
  }
}

Future<double?> showAmountDialog({
  required BuildContext context,
  required String title,
  required TextEditingController controller,
}) {
  return showDialog<double>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [AmountInputFormatter()],
          decoration: const InputDecoration(prefixText: '¥ ', hintText: '0.00'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              if (value == null || value < 0) return;
              Navigator.pop(context, value);
            },
            child: const Text('保存'),
          ),
        ],
      );
    },
  );
}

Future<void> showGoalDialog(BuildContext context, AppStore store) async {
  final nameController = TextEditingController(text: store.savingGoalName);
  final targetController = TextEditingController(
    text: store.savingGoalTarget.toStringAsFixed(2),
  );
  final savedController = TextEditingController(
    text: store.savingGoalSaved.toStringAsFixed(2),
  );

  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('编辑储蓄目标'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '目标名称'),
            ),
            TextField(
              controller: targetController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [AmountInputFormatter()],
              decoration: const InputDecoration(labelText: '目标金额'),
            ),
            TextField(
              controller: savedController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [AmountInputFormatter()],
              decoration: const InputDecoration(labelText: '已存金额'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final previousAchievements = unlockedAchievementIds(store);
              await store.updateSavingGoal(
                name: nameController.text,
                target: double.tryParse(targetController.text.trim()) ?? 0,
                saved: double.tryParse(savedController.text.trim()) ?? 0,
              );
              if (!context.mounted) return;
              showNewAchievementToast(
                context,
                previousAchievements: previousAchievements,
                store: store,
              );
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      );
    },
  );

  nameController.dispose();
  targetController.dispose();
  savedController.dispose();
}

Future<void> showAchievementDialog(BuildContext context, AppStore store) {
  return Navigator.push(context, appPageRoute((_) => const AchievementPage()));
}

class AchievementBadgeData {
  const AchievementBadgeData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.unlocked,
    required this.icon,
    required this.color,
    required this.imageAsset,
  });

  final String id;
  final String title;
  final String subtitle;
  final bool unlocked;
  final IconData icon;
  final Color color;
  final String imageAsset;
}

List<AchievementBadgeData> achievementBadgesFor(AppStore store) {
  final expenseCategoryCount = store.expenseStats.length;
  final budgetGuardUnlocked =
      isMonthSettlementDay() &&
      store.effectiveMonthlyBudget > 0 &&
      store.monthExpense <= store.effectiveMonthlyBudget;
  return [
    AchievementBadgeData(
      id: 'first_record',
      title: '初次见面',
      subtitle: '记下第一笔账',
      unlocked: store.records.isNotEmpty,
      icon: Icons.edit_note_rounded,
      color: _primaryColor,
      imageAsset: 'assets/images/achievement_1.png',
    ),
    AchievementBadgeData(
      id: 'three_records',
      title: '三笔小账',
      subtitle: '累计记录 3 笔',
      unlocked: store.records.length >= 3,
      icon: Icons.format_list_bulleted_rounded,
      color: const Color(0xFF77A9FF),
      imageAsset: 'assets/images/achievement_2.png',
    ),
    AchievementBadgeData(
      id: 'ten_records',
      title: '十全十美',
      subtitle: '累计记录 10 笔',
      unlocked: store.records.length >= 10,
      icon: Icons.auto_awesome_rounded,
      color: const Color(0xFFFFB35C),
      imageAsset: 'assets/images/achievement_3.png',
    ),
    AchievementBadgeData(
      id: 'income_recorded',
      title: '收入到账',
      subtitle: '记录过收入',
      unlocked:
          store.monthIncome > 0 ||
          store.records.any((record) => record.type == RecordType.income),
      icon: Icons.savings_rounded,
      color: _greenColor,
      imageAsset: 'assets/images/achievement_4.png',
    ),
    AchievementBadgeData(
      id: 'budget_guard',
      title: '预算守护',
      subtitle: '月底结算后，支出未超预算',
      unlocked: budgetGuardUnlocked,
      icon: Icons.shield_rounded,
      color: const Color(0xFF66B889),
      imageAsset: 'assets/images/achievement_5.png',
    ),
    AchievementBadgeData(
      id: 'category_budget',
      title: '分类规划师',
      subtitle: '设置 1 个分类预算',
      unlocked: store.categoryBudgets.isNotEmpty,
      icon: Icons.category_rounded,
      color: const Color(0xFFFF9A76),
      imageAsset: 'assets/images/achievement_6.png',
    ),
    AchievementBadgeData(
      id: 'three_day_streak',
      title: '坚持记录',
      subtitle: '连续记账 3 天',
      unlocked: store.accountingDays >= 3,
      icon: Icons.local_fire_department_rounded,
      color: const Color(0xFFFF7F96),
      imageAsset: 'assets/images/achievement_7.png',
    ),
    AchievementBadgeData(
      id: 'week_streak',
      title: '一周习惯',
      subtitle: '连续记账 7 天',
      unlocked: store.accountingDays >= 7,
      icon: Icons.calendar_month_rounded,
      color: const Color(0xFF8E7CFF),
      imageAsset: 'assets/images/achievement_8.png',
    ),
    AchievementBadgeData(
      id: 'thirty_day_streak',
      title: '月度坚持',
      subtitle: '连续记账 30 天',
      unlocked: store.accountingDays >= 30,
      icon: Icons.event_available_rounded,
      color: const Color(0xFFFFC46B),
      imageAsset: 'assets/images/achievement_9.png',
    ),
    AchievementBadgeData(
      id: 'sixty_day_streak',
      title: '双月坚持',
      subtitle: '连续记账 60 天',
      unlocked: store.accountingDays >= 60,
      icon: Icons.date_range_rounded,
      color: const Color(0xFFD09EFF),
      imageAsset: 'assets/images/achievement_10.png',
    ),
    AchievementBadgeData(
      id: 'positive_balance',
      title: '收支平衡',
      subtitle: '本月结余为正',
      unlocked: store.monthBalance > 0,
      icon: Icons.balance_rounded,
      color: const Color(0xFF4CAF7A),
      imageAsset: 'assets/images/achievement_11.png',
    ),
    AchievementBadgeData(
      id: 'three_expense_categories',
      title: '生活观察家',
      subtitle: '本月支出覆盖 3 个分类',
      unlocked: expenseCategoryCount >= 3,
      icon: Icons.scatter_plot_rounded,
      color: const Color(0xFF6FB7C8),
      imageAsset: 'assets/images/achievement_12.png',
    ),
  ];
}

Set<String> unlockedAchievementIds(AppStore store) {
  return achievementBadgesFor(
    store,
  ).where((badge) => badge.unlocked).map((badge) => badge.id).toSet();
}

void showNewAchievementToast(
  BuildContext context, {
  required Set<String> previousAchievements,
  required AppStore store,
  String? fallbackMessage,
}) {
  final newBadges = achievementBadgesFor(store)
      .where(
        (badge) => badge.unlocked && !previousAchievements.contains(badge.id),
      )
      .toList();
  if (newBadges.isEmpty) {
    if (fallbackMessage != null) showToast(context, fallbackMessage);
    return;
  }

  final names = newBadges.map((badge) => badge.title).join('、');
  showToast(context, '解锁成就：$names');
}

const _maxRecordPhotos = 3;

enum RecordPhotoSource { gallery, camera }

Future<List<String>> pickRecordPhotos(
  BuildContext context, {
  required int currentCount,
}) async {
  final remaining = _maxRecordPhotos - currentCount;
  if (remaining <= 0) {
    showToast(context, '最多添加 $_maxRecordPhotos 张照片');
    return const [];
  }

  final source = await showModalBottomSheet<RecordPhotoSource>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return SafeArea(
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBF8),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _primaryColor.withValues(alpha: 0.16)),
            boxShadow: softShadow(),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 4),
              const Text(
                '添加备注照片',
                style: TextStyle(
                  color: _textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_rounded,
                  color: _primaryColor,
                ),
                title: const Text('从相册选择'),
                onTap: () => Navigator.pop(context, RecordPhotoSource.gallery),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_camera_rounded,
                  color: _primaryColor,
                ),
                title: const Text('拍摄照片'),
                onTap: () => Navigator.pop(context, RecordPhotoSource.camera),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (source == null) return const [];

  try {
    final picker = ImagePicker();
    final pickedFiles = <XFile>[];
    if (source == RecordPhotoSource.gallery) {
      pickedFiles.addAll(
        await picker.pickMultiImage(maxWidth: 1280, imageQuality: 72),
      );
    } else {
      final file = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        imageQuality: 72,
      );
      if (file != null) pickedFiles.add(file);
    }

    if (!context.mounted) return const [];
    if (pickedFiles.length > remaining) {
      showToast(context, '最多还能添加 $remaining 张照片');
    }

    final result = <String>[];
    for (final file in pickedFiles.take(remaining)) {
      result.add(await recordPhotoDataUri(file));
    }
    return result;
  } catch (_) {
    if (!context.mounted) return const [];
    showToast(context, '照片读取失败，请再试一次');
    return const [];
  }
}

Future<String> recordPhotoDataUri(XFile file) async {
  final bytes = await file.readAsBytes();
  final mimeType = file.mimeType ?? recordPhotoMimeType(file.path);
  return 'data:$mimeType;base64,${base64Encode(bytes)}';
}

String recordPhotoMimeType(String path) {
  final lowerPath = path.toLowerCase();
  if (lowerPath.endsWith('.png')) return 'image/png';
  if (lowerPath.endsWith('.webp')) return 'image/webp';
  if (lowerPath.endsWith('.gif')) return 'image/gif';
  return 'image/jpeg';
}

Uint8List imageBytesFromDataUri(String dataUri) {
  final commaIndex = dataUri.indexOf(',');
  final payload = commaIndex == -1
      ? dataUri
      : dataUri.substring(commaIndex + 1);
  return base64Decode(payload);
}

String recordListSubtitle(AccountRecord record) {
  final noteText = record.note.isEmpty ? '无备注' : record.note;
  final photoText = record.photoDataUris.isEmpty
      ? ''
      : ' · ${record.photoDataUris.length} 张照片';
  return '$noteText$photoText · ${formatRecordDate(record.date)}';
}

class AchievementPage extends StatelessWidget {
  const AchievementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final badges = achievementBadgesFor(store);
    final unlockedCount = badges.where((badge) => badge.unlocked).length;
    final progress = badges.isEmpty ? 0.0 : unlockedCount / badges.length;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 18, 8),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          tooltip: '返回',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: _textColor,
                          ),
                        ),
                      ),
                      const Text(
                        '成就徽章',
                        style: TextStyle(
                          color: _textColor,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFEEF3), Color(0xFFFFF5DD)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.84),
                            ),
                            boxShadow: softShadow(),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 70,
                                height: 70,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                child: const Icon(
                                  Icons.emoji_events_rounded,
                                  color: _accentColor,
                                  size: 38,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '已点亮 $unlockedCount / ${badges.length}',
                                      style: const TextStyle(
                                        color: _textColor,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                        value: progress,
                                        minHeight: 8,
                                        backgroundColor: Colors.white
                                            .withValues(alpha: 0.72),
                                        color: _primaryColor,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      '每一笔认真记录，都会变成小小徽章。',
                                      style: TextStyle(
                                        color: _mutedColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        const SectionTitle(title: '徽章墙'),
                        const SizedBox(height: 12),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: badges.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 0.96,
                              ),
                          itemBuilder: (context, index) {
                            return AchievementBadgeCard(badge: badges[index]);
                          },
                        ),
                      ],
                    ),
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

class AchievementBadgeCard extends StatelessWidget {
  const AchievementBadgeCard({super.key, required this.badge});

  final AchievementBadgeData badge;

  @override
  Widget build(BuildContext context) {
    final iconColor = badge.unlocked ? badge.color : const Color(0xFFB9ACA7);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: badge.unlocked
              ? badge.color.withValues(alpha: 0.26)
              : Colors.white.withValues(alpha: 0.76),
        ),
        boxShadow: badge.unlocked ? softShadow() : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              badge.imageAsset,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (context, error, stackTrace) {
                return Image.asset(
                  'assets/images/achievement_11.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                );
              },
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(
                      alpha: badge.unlocked ? 0.04 : 0.44,
                    ),
                    Colors.white.withValues(
                      alpha: badge.unlocked ? 0.12 : 0.56,
                    ),
                    Colors.white.withValues(
                      alpha: badge.unlocked ? 0.54 : 0.72,
                    ),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(
                          alpha: badge.unlocked ? 0.58 : 0.68,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        badge.unlocked ? badge.icon : Icons.lock_rounded,
                        color: iconColor,
                        size: 26,
                      ),
                    ),
                    const Spacer(),
                    if (badge.unlocked)
                      const CatPawMark(size: 18, color: _primaryColor)
                    else
                      Icon(
                        Icons.circle_outlined,
                        color: iconColor.withValues(alpha: 0.5),
                        size: 18,
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  badge.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: badge.unlocked
                        ? _textColor
                        : const Color(0xFF9F9692),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  badge.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: badge.unlocked
                        ? _mutedColor
                        : const Color(0xFFA98478),
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
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

Future<void> confirmClearData(BuildContext context, AppStore store) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('确认清空数据？'),
        content: const Text('清空后所有记录和储蓄进度都会删除，此操作不能撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      );
    },
  );
  if (confirm == true) {
    await store.clearAll();
    if (context.mounted) showToast(context, '数据已清空');
  }
}

Future<void> confirmDeleteRecord(
  BuildContext context,
  AppStore store,
  AccountRecord record,
) async {
  final confirm = await confirmDeleteRecordIntent(context, record);
  if (confirm == true) {
    await store.deleteRecord(record.id);
    if (!context.mounted) return;
    showToast(context, '已删除记录');
    Navigator.pop(context);
  }
}

Future<bool> confirmDeleteRecordIntent(
  BuildContext context,
  AccountRecord record,
) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('删除这笔记录？'),
        content: Text('${record.category} ${money(record.amount)} 删除后不能恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      );
    },
  );
  return confirm ?? false;
}

Future<void> confirmDeleteCategoryBudget(
  BuildContext context,
  AppStore store,
  CategoryBudget budget, {
  bool popAfterDelete = false,
}) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('删除分类预算？'),
        content: Text('${budget.category} 的分类预算删除后不会影响账单记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      );
    },
  );
  if (confirm == true) {
    await store.deleteCategoryBudget(budget.id);
    if (!context.mounted) return;
    showToast(context, '分类预算已删除');
    if (popAfterDelete && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }
}

OverlayEntry? _activeToastEntry;

void showToast(BuildContext context, String message) {
  final overlay = Overlay.of(context);
  final size = MediaQuery.sizeOf(context);
  final safeTop = MediaQuery.paddingOf(context).top;
  final horizontalMargin = math.max(20.0, (size.width - 360) / 2);
  _activeToastEntry?.remove();

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) {
      return Positioned(
        top: safeTop + 16,
        left: horizontalMargin,
        right: horizontalMargin,
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBF8),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _primaryColor.withValues(alpha: 0.18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: _textColor.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: _primaryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(child: CatPawMark(size: 16)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textColor,
                        fontSize: 14,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  _activeToastEntry = entry;
  overlay.insert(entry);
  Future.delayed(const Duration(milliseconds: 1800), () {
    if (_activeToastEntry == entry) {
      entry.remove();
      _activeToastEntry = null;
    }
  });
}

String money(double value) {
  final sign = value < 0 ? '-' : '';
  final absValue = value.abs();
  return '$sign¥${absValue.toStringAsFixed(2)}';
}

String moneyPlain(double value) {
  final absValue = value.abs();
  if (absValue == absValue.roundToDouble()) {
    return absValue.toStringAsFixed(0);
  }
  return absValue.toStringAsFixed(2);
}

List<AccountRecord> parseImportedBillRecords(String rawText) {
  final text = rawText.trim().replaceFirst('\uFEFF', '');
  if (text.isEmpty) {
    throw const FormatException('文件内容为空');
  }
  try {
    final decoded = jsonDecode(text);
    final items = decoded is Map<String, dynamic>
        ? (decoded['records'] is List<dynamic>
              ? decoded['records'] as List<dynamic>
              : <dynamic>[decoded])
        : decoded is List<dynamic>
        ? decoded
        : const <dynamic>[];
    final records = <AccountRecord>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is Map<String, dynamic>) {
        records.add(importRecordFromMap(item, i));
      } else if (item is Map) {
        records.add(importRecordFromMap(Map<String, dynamic>.from(item), i));
      }
    }
    if (records.isNotEmpty) return records;
  } catch (_) {
    // JSON parsing failed; try CSV/TXT below.
  }
  return parseImportedCsvRecords(text);
}

String importDuplicateKey(AccountRecord record) {
  final normalizedDate = record.date.toIso8601String();
  final normalizedAmount = record.amount.toStringAsFixed(2);
  final normalizedCategory = normalizeCategoryName(record.category).trim();
  final normalizedNote = record.note.trim();
  return [
    normalizedAmount,
    normalizedCategory,
    normalizedDate,
    normalizedNote,
  ].join('|');
}

Future<void> exportBillDataFile({
  required BuildContext context,
  required List<AccountRecord> records,
  required String periodLabel,
  required String format,
}) async {
  final normalizedFormat = format.toUpperCase();
  final fileName =
      'miao_jizhang_${safeExportFileName(periodLabel)}.${normalizedFormat.toLowerCase()}';
  final content = buildExportBillContent(
    records,
    periodLabel,
    normalizedFormat,
  );
  final mimeType = switch (normalizedFormat) {
    'JSON' => 'application/json',
    'CSV' => 'text/csv',
    'TXT' => 'text/plain',
    _ => 'text/plain',
  };
  final bytes = Uint8List.fromList(utf8.encode(content));

  try {
    if (kIsWeb) {
      final downloaded = await downloadExportFile(
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
      );
      if (context.mounted) {
        showToast(context, downloaded ? '账单文件已下载' : '导出失败，请稍后再试');
      }
      return;
    }

    final box = context.findRenderObject() as RenderBox?;
    await Share.share(
      '喵记账 $periodLabel 账单',
      subject: '导出账单',
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    );
    if (context.mounted) showToast(context, '账单文件已生成');
  } catch (_) {
    if (context.mounted) showToast(context, '导出失败，请稍后再试');
  }
}

String buildExportBillContent(
  List<AccountRecord> records,
  String periodLabel,
  String format,
) {
  final sortedRecords = [...records]..sort((a, b) => b.date.compareTo(a.date));
  return switch (format) {
    'JSON' => buildExportJson(sortedRecords, periodLabel),
    'CSV' => buildExportCsv(sortedRecords),
    'TXT' => buildExportTxt(sortedRecords),
    _ => buildExportTxt(sortedRecords),
  };
}

String buildExportJson(List<AccountRecord> records, String periodLabel) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert({
    'app': '喵记账',
    'version': 1,
    'periodLabel': periodLabel,
    'exportedAt': DateTime.now().toIso8601String(),
    'records': records.map((record) => record.toJson()).toList(),
  });
}

String buildExportCsv(List<AccountRecord> records) {
  final buffer = StringBuffer('\uFEFF类型,分类,金额,备注,时间\n');
  for (final record in records) {
    buffer.writeln(
      [
        record.type == RecordType.income ? '收入' : '支出',
        record.category,
        record.amount.toStringAsFixed(2),
        record.note,
        '${formatDate(record.date)} ${formatTime(record.date)}',
      ].map(escapeCsvCell).join(','),
    );
  }
  return buffer.toString();
}

String buildExportTxt(List<AccountRecord> records) {
  final buffer = StringBuffer('类型,分类,金额,备注,时间\n');
  for (final record in records) {
    buffer.writeln(
      [
        record.type == RecordType.income ? '收入' : '支出',
        record.category,
        record.amount.toStringAsFixed(2),
        record.note,
        '${formatDate(record.date)} ${formatTime(record.date)}',
      ].map(escapeCsvCell).join(','),
    );
  }
  return buffer.toString();
}

String escapeCsvCell(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

String safeExportFileName(String value) {
  return value
      .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

List<AccountRecord> parseImportedCsvRecords(String text) {
  final rows = const LineSplitter()
      .convert(text)
      .map(parseCsvLine)
      .where((row) => row.any((cell) => cell.trim().isNotEmpty))
      .toList();
  if (rows.isEmpty) {
    throw const FormatException('没有识别到账单记录');
  }

  final firstRow = rows.first.map((cell) => cell.trim()).toList();
  final hasHeader = firstRow.any(isImportHeaderCell);
  final headerIndexes = hasHeader
      ? buildHeaderIndexes(firstRow)
      : <String, int>{};
  final dataRows = hasHeader ? rows.skip(1).toList() : rows;
  final records = <AccountRecord>[];

  for (var i = 0; i < dataRows.length; i++) {
    try {
      records.add(
        hasHeader
            ? importRecordFromCsvHeaderRow(dataRows[i], headerIndexes, i)
            : importRecordFromCsvPlainRow(dataRows[i], i),
      );
    } catch (_) {
      // Skip invalid rows and keep importing rows we can understand.
    }
  }
  if (records.isEmpty) {
    throw const FormatException('没有识别到账单记录');
  }
  return records;
}

AccountRecord importRecordFromCsvHeaderRow(
  List<String> row,
  Map<String, int> headerIndexes,
  int index,
) {
  String? cell(String key) {
    final position = headerIndexes[key];
    if (position == null || position >= row.length) return null;
    return row[position].trim();
  }

  return importRecordFromMap({
    'type': cell('type'),
    'category': cell('category'),
    'amount': cell('amount'),
    'note': cell('note'),
    'date': cell('date') ?? cell('time'),
  }, index);
}

AccountRecord importRecordFromCsvPlainRow(List<String> row, int index) {
  if (row.length < 3) {
    throw const FormatException('CSV 行字段不足');
  }
  return importRecordFromMap({
    'type': row[0],
    'category': row[1],
    'amount': row[2],
    'note': row.length > 3 ? row[3] : '',
    'date': row.length > 4 ? row[4] : null,
  }, index);
}

AccountRecord importRecordFromMap(Map<String, dynamic> data, int index) {
  final amountRaw = readImportField(data, const [
    'amount',
    '金额',
    '花费金额',
    'money',
    'value',
  ]);
  final signedAmount = parseImportAmount(amountRaw);
  final typeRaw = readImportField(data, const ['type', '类型', '收支', '账单类型']);
  final type = parseImportType(typeRaw, signedAmount);
  final categoryRaw = readImportField(data, const [
    'category',
    '分类',
    '账单名称',
    'name',
    '名称',
  ]);
  final categoryText = categoryRaw?.toString().trim();
  final category = normalizeCategoryName(
    categoryText?.isNotEmpty == true ? categoryText! : '其他',
  );
  final note =
      readImportField(data, const [
        'note',
        '备注',
        '账单备注',
        '说明',
      ])?.toString().trim() ??
      '';
  final date =
      parseImportDate(
        readImportField(data, const [
          'date',
          '日期',
          'time',
          '时间',
          'datetime',
          '记录时间',
        ]),
      ) ??
      DateTime.now();

  return AccountRecord(
    id: 'import-${DateTime.now().microsecondsSinceEpoch}-$index',
    type: type,
    category: category,
    icon: iconForCategory(type, category),
    amount: signedAmount.abs(),
    note: note,
    date: date,
  );
}

dynamic readImportField(Map<String, dynamic> data, List<String> aliases) {
  for (final alias in aliases) {
    if (data.containsKey(alias) && data[alias] != null) return data[alias];
  }
  final lowerKeys = {
    for (final key in data.keys) key.toString().toLowerCase(): key,
  };
  for (final alias in aliases) {
    final key = lowerKeys[alias.toLowerCase()];
    if (key != null && data[key] != null) return data[key];
  }
  return null;
}

double parseImportAmount(dynamic value) {
  if (value is num) return value.toDouble();
  final text = value?.toString().trim() ?? '';
  final cleaned = text
      .replaceAll('¥', '')
      .replaceAll('￥', '')
      .replaceAll(',', '')
      .replaceAll('元', '')
      .replaceAll(' ', '');
  final amount = double.tryParse(cleaned);
  if (amount == null) {
    throw const FormatException('金额格式不正确');
  }
  return amount;
}

RecordType parseImportType(dynamic value, double signedAmount) {
  final text = value?.toString().trim().toLowerCase() ?? '';
  if (text.contains('收入') ||
      text.contains('income') ||
      text == 'in' ||
      text == '+') {
    return RecordType.income;
  }
  if (text.contains('支出') ||
      text.contains('expense') ||
      text.contains('out') ||
      text == '-') {
    return RecordType.expense;
  }
  return signedAmount > 0 ? RecordType.income : RecordType.expense;
}

DateTime? parseImportDate(dynamic value) {
  if (value is DateTime) return value;
  if (value is num) {
    final intValue = value.toInt();
    if (intValue > 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(intValue);
    }
  }
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) return null;
  final normalized = raw
      .replaceAll('年', '-')
      .replaceAll('月', '-')
      .replaceAll('日', '')
      .replaceAll('/', '-');
  final parsed = DateTime.tryParse(normalized);
  if (parsed != null) return parsed;
  final match = RegExp(
    r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}):(\d{1,2}))?$',
  ).firstMatch(normalized);
  if (match == null) return null;
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4) ?? '0'),
    int.parse(match.group(5) ?? '0'),
  );
}

List<String> parseCsvLine(String line) {
  final cells = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        buffer.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (char == ',' && !inQuotes) {
      cells.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  cells.add(buffer.toString());
  return cells;
}

bool isImportHeaderCell(String cell) {
  final normalized = cell.trim().toLowerCase();
  return const {
    'type',
    '类型',
    '收支',
    '账单类型',
    'category',
    '分类',
    '账单名称',
    'amount',
    '金额',
    '花费金额',
    'note',
    '备注',
    '账单备注',
    'date',
    '日期',
    'time',
    '时间',
    'datetime',
    '记录时间',
  }.contains(normalized);
}

Map<String, int> buildHeaderIndexes(List<String> headers) {
  final indexes = <String, int>{};
  for (var i = 0; i < headers.length; i++) {
    final header = headers[i].trim().toLowerCase();
    if (const {'type', '类型', '收支', '账单类型'}.contains(header)) {
      indexes['type'] = i;
    } else if (const {
      'category',
      '分类',
      '账单名称',
      'name',
      '名称',
    }.contains(header)) {
      indexes['category'] = i;
    } else if (const {
      'amount',
      '金额',
      '花费金额',
      'money',
      'value',
    }.contains(header)) {
      indexes['amount'] = i;
    } else if (const {'note', '备注', '账单备注', '说明'}.contains(header)) {
      indexes['note'] = i;
    } else if (const {'date', '日期', 'datetime', '记录时间'}.contains(header)) {
      indexes['date'] = i;
    } else if (const {'time', '时间'}.contains(header)) {
      indexes['time'] = i;
    }
  }
  return indexes;
}

String moneyCompact(double value) {
  if (value >= 10000) {
    return '¥${(value / 10000).toStringAsFixed(1)}万';
  }
  return '¥${value.toStringAsFixed(0)}';
}

StatsPeriod statsPeriodFor(StatsRange range, {DateTime? anchorDate}) {
  final now = anchorDate ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  switch (range) {
    case StatsRange.day:
      return StatsPeriod(start: today, end: today.add(const Duration(days: 1)));
    case StatsRange.week:
      final start = today.subtract(Duration(days: today.weekday - 1));
      return StatsPeriod(start: start, end: start.add(const Duration(days: 7)));
    case StatsRange.month:
      return StatsPeriod(
        start: DateTime(now.year, now.month),
        end: DateTime(now.year, now.month + 1),
      );
    case StatsRange.year:
      return StatsPeriod(
        start: DateTime(now.year),
        end: DateTime(now.year + 1),
      );
  }
}

List<TrendPoint> buildTrendPoints(
  StatsRange range,
  List<AccountRecord> records, {
  DateTime? anchorDate,
}) {
  final period = statsPeriodFor(range, anchorDate: anchorDate);
  final points = <TrendPoint>[];
  switch (range) {
    case StatsRange.day:
      for (var hour = 0; hour < 24; hour++) {
        final expense = sumRecords(
          records,
          RecordType.expense,
          (record) => record.date.hour == hour,
        );
        final income = sumRecords(
          records,
          RecordType.income,
          (record) => record.date.hour == hour,
        );
        points.add(
          TrendPoint(
            label: hour % 4 == 0 ? hour.toString().padLeft(2, '0') : '',
            detailLabel: '${hour.toString().padLeft(2, '0')}:00',
            expense: expense,
            income: income,
          ),
        );
      }
    case StatsRange.week:
      for (var i = 0; i < 7; i++) {
        final day = period.start.add(Duration(days: i));
        points.add(buildDayTrendPoint(records, day, weekdayLabel(day.weekday)));
      }
    case StatsRange.month:
      final dayCount = period.end.difference(period.start).inDays;
      for (var i = 0; i < dayCount; i++) {
        final day = period.start.add(Duration(days: i));
        points.add(
          buildDayTrendPoint(records, day, day.day.toString().padLeft(2, '0')),
        );
      }
    case StatsRange.year:
      for (var month = 1; month <= 12; month++) {
        final expense = sumRecords(
          records,
          RecordType.expense,
          (record) => record.date.month == month,
        );
        final income = sumRecords(
          records,
          RecordType.income,
          (record) => record.date.month == month,
        );
        points.add(
          TrendPoint(
            label: '$month月',
            detailLabel: '$month月',
            expense: expense,
            income: income,
          ),
        );
      }
  }
  return points;
}

TrendPoint buildDayTrendPoint(
  List<AccountRecord> records,
  DateTime day,
  String label,
) {
  bool sameDay(AccountRecord record) =>
      record.date.year == day.year &&
      record.date.month == day.month &&
      record.date.day == day.day;
  return TrendPoint(
    label: label,
    detailLabel: formatMonthDay(day),
    expense: sumRecords(records, RecordType.expense, sameDay),
    income: sumRecords(records, RecordType.income, sameDay),
  );
}

List<AccountRecord> buildDetailRanks(
  List<AccountRecord> records,
  RecordType type,
) {
  final items = records.where((record) => record.type == type).toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));
  return items;
}

double sumRecords(
  List<AccountRecord> records,
  RecordType type,
  bool Function(AccountRecord record) test,
) {
  return records
      .where((record) => record.type == type && test(record))
      .fold<double>(0, (sum, record) => sum + record.amount);
}

String formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String formatTime(DateTime date) {
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String twoDigits(int value) => value.toString().padLeft(2, '0');

String amountFilterText(double value) {
  return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
}

DateTime dateOnly(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

DateTime monthStart(DateTime date) {
  return DateTime(date.year, date.month);
}

DateTime monthEnd(DateTime date) {
  return DateTime(date.year, date.month + 1, 0);
}

String formatMonthDay(DateTime date) {
  return '${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
}

String filterDateRangeLabel(HomeRecordFilter filter) {
  final start = filter.effectiveStartDate;
  final end = filter.effectiveEndDate;
  if (start == monthStart(start) && end == monthEnd(start)) {
    return formatYearMonth(start);
  }
  if (start.year == end.year) {
    return '${formatMonthDay(start)}-${formatMonthDay(end)}';
  }
  return '${formatDate(start)}-${formatDate(end)}';
}

String formatYearMonth(DateTime date) {
  return '${date.year}年${date.month.toString().padLeft(2, '0')}月';
}

String exportPeriodTitle(DateTime start, DateTime endMonth) {
  if (start.year == endMonth.year && start.month == endMonth.month) {
    return '${endMonth.year}年${endMonth.month}月';
  }
  if (start.year == endMonth.year) {
    return '${start.month}月-${endMonth.month}月';
  }
  return '${start.year}年${start.month}月-${endMonth.year}年${endMonth.month}月';
}

String exportPeriodSubtitle(DateTime start, DateTime endMonth) {
  if (start.year == endMonth.year && start.month == endMonth.month) {
    return '${endMonth.year}年${endMonth.month}月';
  }
  return '${start.year}年${start.month}月-${endMonth.year}年${endMonth.month}月';
}

String shortYearMonth(DateTime date) {
  return '${date.year}.${date.month.toString().padLeft(2, '0')}';
}

String formatRecordDate(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final time =
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  if (target == today) return '今天 $time';
  if (target == today.subtract(const Duration(days: 1))) return '昨天 $time';
  return '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} $time';
}

String weekdayLabel(int weekday) {
  switch (weekday) {
    case 1:
      return '一';
    case 2:
      return '二';
    case 3:
      return '三';
    case 4:
      return '四';
    case 5:
      return '五';
    case 6:
      return '六';
    case 7:
      return '日';
    default:
      return '';
  }
}

String statsRangeLabel(StatsRange range, {DateTime? anchorDate}) {
  if (anchorDate != null) {
    final period = statsPeriodFor(range, anchorDate: anchorDate);
    switch (range) {
      case StatsRange.day:
        return formatDate(period.start);
      case StatsRange.week:
        final end = period.end.subtract(const Duration(days: 1));
        return '${formatMonthDay(period.start)}-${formatMonthDay(end)}';
      case StatsRange.month:
        return formatYearMonth(anchorDate);
      case StatsRange.year:
        return '${anchorDate.year}年';
    }
  }

  switch (range) {
    case StatsRange.day:
      return '今日';
    case StatsRange.week:
      return '本周';
    case StatsRange.month:
      return '本月';
    case StatsRange.year:
      return '本年';
  }
}

String statsRangeShortLabel(StatsRange range) {
  switch (range) {
    case StatsRange.day:
      return '日';
    case StatsRange.week:
      return '周';
    case StatsRange.month:
      return '月';
    case StatsRange.year:
      return '年';
  }
}

String recordTypeLabel(RecordType type) {
  return type == RecordType.expense ? '支出' : '收入';
}

bool isMonthSettlementDay([DateTime? date]) {
  final now = date ?? DateTime.now();
  final tomorrow = now.add(const Duration(days: 1));
  return tomorrow.month != now.month || tomorrow.year != now.year;
}

BoxDecoration whiteCardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    boxShadow: softShadow(),
  );
}

List<BoxShadow> softShadow() {
  return [
    BoxShadow(
      color: Colors.brown.withValues(alpha: 0.05),
      blurRadius: 14,
      offset: const Offset(0, 6),
    ),
  ];
}
