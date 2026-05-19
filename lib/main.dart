import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MiaoJiZhangApp());
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
  const MiaoJiZhangApp({super.key});

  @override
  State<MiaoJiZhangApp> createState() => _MiaoJiZhangAppState();
}

class _MiaoJiZhangAppState extends State<MiaoJiZhangApp> {
  final AppStore store = AppStore();

  @override
  void initState() {
    super.initState();
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
          return PageBackground(child: child ?? const SizedBox.shrink());
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

  bool isLoaded = false;
  bool reminderEnabled = true;
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
      notifyListeners();
      return;
    }

    final data = jsonDecode(raw) as Map<String, dynamic>;
    monthlyBudget = (data['monthlyBudget'] as num?)?.toDouble() ?? 0;
    savingGoalName = data['savingGoalName'] as String? ?? '储蓄目标';
    savingGoalTarget = (data['savingGoalTarget'] as num?)?.toDouble() ?? 0;
    savingGoalSaved = (data['savingGoalSaved'] as num?)?.toDouble() ?? 0;
    reminderEnabled = data['reminderEnabled'] as bool? ?? true;
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
    notifyListeners();
  }

  Future<void> addRecord(AccountRecord record) async {
    records.insert(0, record);
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
  }

  Future<void> clearAll() async {
    _resetToEmpty();
    notifyListeners();
    await _save();
  }

  double get monthExpense => _sumCurrentMonth(RecordType.expense);
  double get monthIncome => _sumCurrentMonth(RecordType.income);
  double get monthBalance => monthIncome - monthExpense;
  double get lastMonthExpense => _sumMonthOffset(RecordType.expense, -1);
  double get lastMonthIncome => _sumMonthOffset(RecordType.income, -1);
  double get lastMonthBalance => lastMonthIncome - lastMonthExpense;
  double get budgetLeft => monthlyBudget - monthExpense;
  double get budgetRatio =>
      monthlyBudget <= 0 ? 0 : (monthExpense / monthlyBudget).clamp(0, 1);
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
      'records': records.map((record) => record.toJson()).toList(),
    };
    await prefs.setString(_storageKey, jsonEncode(data));
  }

  void _resetToEmpty() {
    monthlyBudget = 0;
    savingGoalName = '储蓄目标';
    savingGoalTarget = 0;
    savingGoalSaved = 0;
    reminderEnabled = true;
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
  });

  final String id;
  final RecordType type;
  final String category;
  final IconData icon;
  final double amount;
  final String note;
  final DateTime date;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'category': category,
    'amount': amount,
    'note': note,
    'date': date.toIso8601String(),
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
  CategoryOption('医疗', Icons.local_hospital_rounded),
  CategoryOption('学习', Icons.menu_book_rounded),
  CategoryOption('运动', Icons.fitness_center_rounded),
  CategoryOption('旅行', Icons.flight_takeoff_rounded),
  CategoryOption('美妆', Icons.face_retouching_natural_rounded),
  CategoryOption('服饰', Icons.checkroom_rounded),
  CategoryOption('家居', Icons.chair_rounded),
  CategoryOption('数码', Icons.devices_rounded),
  CategoryOption('保险', Icons.health_and_safety_rounded),
  CategoryOption('还款', Icons.credit_card_rounded),
  CategoryOption('公益', Icons.favorite_rounded),
  CategoryOption('其他', Icons.more_horiz_rounded),
];

const incomeCategories = [
  CategoryOption('生活费', Icons.account_balance_wallet_rounded),
  CategoryOption('卖闲置', Icons.sell_rounded),
  CategoryOption('工资', Icons.work_rounded),
  CategoryOption('兼职', Icons.storefront_rounded),
  CategoryOption('奖金', Icons.emoji_events_rounded),
  CategoryOption('理财', Icons.trending_up_rounded),
  CategoryOption('红包', Icons.redeem_rounded),
  CategoryOption('报销', Icons.receipt_long_rounded),
  CategoryOption('退款', Icons.assignment_return_rounded),
  CategoryOption('租金', Icons.apartment_rounded),
  CategoryOption('补贴', Icons.savings_rounded),
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
  if (category == '住房') return '谷子';
  if (category == '育儿') return '水果';
  if (category == '人情') return '饮品';
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
    case '保险':
      return const Color(0xFF56B88E);
    case '还款':
      return const Color(0xFF6D89FF);
    case '公益':
      return const Color(0xFFFF6E93);
    case '生活费':
      return const Color(0xFFFFA64D);
    case '卖闲置':
      return const Color(0xFF58BE8B);
    case '工资':
      return const Color(0xFF5B8CFF);
    case '兼职':
      return const Color(0xFFFF8C4B);
    case '奖金':
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
                const SizedBox(height: 20),
                const Text(
                  '喵记账',
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    color: _textColor,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
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
                              MaterialPageRoute(
                                builder: (_) => const MainPage(),
                              ),
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
              centerTitle: false,
              titleSpacing: 16,
              title: Row(
                children: [
                  const CatFaceBadge(size: 34),
                  const SizedBox(width: 8),
                  Text(
                    titles[currentIndex],
                    style: const TextStyle(
                      color: _textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                ],
              ),
            ),
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: KeyedSubtree(
              key: ValueKey(currentIndex),
              child: AppScope.of(context).isLoaded
                  ? pages[currentIndex]
                  : const Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      ),
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
          onTap: (index) => setState(() => currentIndex = index),
          items: const [
            BottomNavigationBarItem(
              icon: CatNavIcon(icon: Icons.home_rounded),
              activeIcon: CatNavIcon(icon: Icons.home_rounded, selected: true),
              label: '首页',
            ),
            BottomNavigationBarItem(
              icon: CatNavIcon(icon: Icons.savings_rounded),
              activeIcon: CatNavIcon(
                icon: Icons.savings_rounded,
                selected: true,
              ),
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
  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final monthRecords = store.recordsForRange(
      StatsRange.month,
      anchorDate: selectedMonth,
    );
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
            Row(
              children: [
                Expanded(
                  child: HomeSummaryMiniCard(
                    title: '本月支出',
                    amount: money(store.monthExpense),
                    compareText: monthCompareText(
                      store.monthExpense,
                      store.lastMonthExpense,
                    ),
                    backgroundColor: const Color(0xFFFFC8CD),
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
                    backgroundColor: const Color(0xFFFFE6B8),
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
                    backgroundColor: const Color(0xFFDDF1D5),
                    accentColor: const Color(0xFF62AF72),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            HomeBudgetProgressCard(store: store),
            const SizedBox(height: 12),
            HomeTodayOverviewCard(
              expense: todayExpense,
              income: todayIncome,
              balance: todayBalance,
              onViewAll: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TodayOverviewDetailPage(),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const SectionTitle(title: '账单记录'),
                const Spacer(),
                HomeMonthFilter(
                  value: selectedMonth,
                  onChanged: (value) => setState(() => selectedMonth = value),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (monthRecords.isEmpty)
              EmptyState(
                icon: Icons.receipt_long_rounded,
                title: '${formatYearMonth(selectedMonth)}还没有记录',
                subtitle: '去「记账」页添加这一月的收支吧',
              )
            else
              ...monthRecords.map((record) => RecordItem(record: record)),
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
    final ratio = store.monthlyBudget <= 0 ? 0.0 : store.budgetRatio;
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
                  value: money(store.monthlyBudget),
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
                ),
              ),
              Expanded(
                child: HomeTodayMetric(
                  title: '收入',
                  value: money(income),
                  valueColor: _textColor,
                ),
              ),
              Expanded(
                child: HomeTodayMetric(
                  title: '结余',
                  value: money(balance),
                  valueColor: balance >= 0 ? _greenColor : _primaryColor,
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
  });

  final String title;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF1FAEF),
        borderRadius: BorderRadius.circular(14),
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

class HomeMonthFilter extends StatelessWidget {
  const HomeMonthFilter({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  Future<void> _pickMonth(BuildContext context) async {
    final selected = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => MonthPickerSheet(value: value),
    );
    if (selected == null) return;
    onChanged(DateTime(selected.year, selected.month));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _pickMonth(context),
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
              const Icon(
                Icons.calendar_month_rounded,
                size: 17,
                color: _primaryColor,
              ),
              const SizedBox(width: 5),
              Text(
                shortYearMonth(value),
                style: const TextStyle(
                  color: _textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
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

class HomeCoverCard extends StatelessWidget {
  const HomeCoverCard({super.key});

  @override
  Widget build(BuildContext context) {
    const aspectRatio = 1920 / 820;
    final width = MediaQuery.sizeOf(context).width;
    final height = width / aspectRatio - 12;

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
            const Positioned(
              left: 18,
              top: 10,
              child: Text(
                '喵记账',
                style: TextStyle(
                  color: _textColor,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const Positioned(left: 112, top: 22, child: CatWhiskerMark()),
            Positioned(
              left: 32,
              bottom: 22,
              child: SpeechBubble(
                child: const Text(
                  '今天也要\n好好记账喵～',
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 14,
                    height: 1.45,
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
      height: 124,
      padding: const EdgeInsets.fromLTRB(12, 13, 10, 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.78)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 8),
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
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  amount,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Color(0xFF3F2C29),
                    fontSize: 18,
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
                  fontSize: 11,
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
  if (previous == 0) return '较上月 新增';
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
          selectedDate: selectedDate,
          onPickDate: _pickDate,
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
        DateTime.now().hour,
        DateTime.now().minute,
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
      ),
    );
    amountController.clear();
    noteController.clear();
    selectedDate = DateTime.now();
    selectedCategoryIndex = 0;
    if (!mounted) return;
    showNewAchievementToast(
      context,
      previousAchievements: previousAchievements,
      store: store,
      fallbackMessage: '已保存这笔记录',
    );
    widget.onSaved();
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
                const SizedBox(height: 28),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [AmountInputFormatter()],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    color: _textColor,
                  ),
                  decoration: const InputDecoration(
                    prefixText: '¥ ',
                    hintText: '00.00',
                    hintStyle: TextStyle(
                      color: Color(0x555B3A32),
                      fontSize: 38,
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
    required this.selectedDate,
    required this.onPickDate,
    required this.onSave,
    required this.buttonText,
  });

  final TextEditingController noteController;
  final DateTime selectedDate;
  final VoidCallback onPickDate;
  final VoidCallback onSave;
  final String buttonText;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InputLikeTile(
              icon: Icons.calendar_month_rounded,
              title: '日期',
              value: formatDate(selectedDate),
              onTap: onPickDate,
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
                ],
              ),
            ),
            const SizedBox(height: 16),
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
  StatsRange range = StatsRange.month;
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
          SectionTitle(
            title: '${statsRangeLabel(range, anchorDate: selectedDate)}统计',
          ),
          const SizedBox(height: 12),
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
    final ranges = StatsRange.values;
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

class ExpenseTrendCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final typeLabel = recordTypeLabel(type);
    final maxPoint = points.isEmpty
        ? null
        : points.reduce(
            (a, b) => a.amountFor(type) >= b.amountFor(type) ? a : b,
          );
    final maxAmount = maxPoint?.amountFor(type) ?? 0;
    final activeDays = points
        .where((point) => point.amountFor(type) > 0)
        .length;
    final average = activeDays == 0 ? 0.0 : total / activeDays;

    return ReportCard(
      title: '$typeLabel趋势',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            maxAmount <= 0
                ? '${statsRangeLabel(range, anchorDate: anchorDate)}暂无$typeLabel'
                : '${statsRangeLabel(range, anchorDate: anchorDate)}最高$typeLabel',
            style: const TextStyle(color: _mutedColor, fontSize: 14),
          ),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              style: const TextStyle(
                color: Color(0xFF2F7F66),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              children: [
                TextSpan(
                  text: maxAmount <= 0
                      ? '记下一笔后，会生成趋势'
                      : '在 ${maxPoint!.detailLabel}，你${type == RecordType.expense ? '支出' : '收入'}了 ',
                ),
                if (maxAmount > 0)
                  TextSpan(
                    text: money(maxAmount),
                    style: const TextStyle(color: _primaryColor),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: MiniMetric(title: '平均$typeLabel', value: money(average)),
              ),
              Expanded(
                child: MiniMetric(
                  title: '$typeLabel笔数',
                  value: '$recordCount笔',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 190,
            child: CustomPaint(
              painter: TrendLinePainter(points),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 10),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ChartLegend(color: _primaryColor, label: '支出'),
              SizedBox(width: 28),
              ChartLegend(color: Color(0xFF9EA4AA), label: '收入'),
              SizedBox(width: 28),
              ChartLegend(color: Color(0xFF7EBE9F), label: '结余'),
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
                  width: 160,
                  height: 160,
                  child: CustomPaint(
                    painter: DonutPainter(stats),
                    child: Center(
                      child: Text(
                        '本期$typeLabel\n${money(total)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: _mutedColor),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ...stats.map((stat) => PercentRow(stat: stat, total: total)),
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
                      trailing: '${(stat.ratio * 100).round()}%',
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
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formatMonthDay(record.date),
                              style: const TextStyle(color: _mutedColor),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${type == RecordType.expense ? '-' : '+'}${money(record.amount)}',
                        style: TextStyle(
                          color: type == RecordType.expense
                              ? _textColor
                              : _greenColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
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
              const Spacer(),
              Container(
                width: 34,
                height: 6,
                decoration: BoxDecoration(
                  color: _primaryColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: _mutedColor)),
        const SizedBox(height: 6),
        Text(
          value,
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
                    Text(trailing, style: const TextStyle(color: _mutedColor)),
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
    _primaryColor,
    _accentColor,
    Color(0xFF8FD8B8),
    Color(0xFFB8A7FF),
    Color(0xFFFFA76B),
    Color(0xFF78C6E7),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.16;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    if (stats.isEmpty) {
      paint.color = _softColor;
      canvas.drawArc(rect.deflate(stroke / 2), 0, math.pi * 2, false, paint);
      return;
    }

    var start = -math.pi / 2;
    for (var i = 0; i < stats.length; i++) {
      final sweep = math.pi * 2 * stats[i].ratio;
      paint.color = colors[i % colors.length];
      canvas.drawArc(rect.deflate(stroke / 2), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant DonutPainter oldDelegate) {
    return oldDelegate.stats != stats;
  }
}

class TrendLinePainter extends CustomPainter {
  TrendLinePainter(this.points);

  final List<TrendPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 28.0;
    const top = 8.0;
    const bottom = 24.0;
    const right = 8.0;
    final chart = Rect.fromLTWH(
      left,
      top,
      size.width - left - right,
      size.height - top - bottom,
    );
    final gridPaint = Paint()
      ..color = const Color(0xFFE9E2DA)
      ..strokeWidth = 1;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final maxValue = math.max(
      1,
      points.fold<double>(
        0,
        (max, point) => math.max(
          max,
          math.max(point.expense, math.max(point.income, point.balance.abs())),
        ),
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

    List<Offset> offsetsFor(double Function(TrendPoint point) selector) {
      return List.generate(points.length, (index) {
        final x = points.length == 1
            ? chart.center.dx
            : chart.left + chart.width * index / (points.length - 1);
        final value = selector(points[index]);
        final y = chart.bottom - chart.height * (value / maxValue);
        return Offset(x, y.clamp(chart.top, chart.bottom));
      });
    }

    void drawSeries(List<Offset> offsets, Color color) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
      for (final offset in offsets.skip(1)) {
        path.lineTo(offset.dx, offset.dy);
      }
      canvas.drawPath(path, paint);
      final dotPaint = Paint()..color = Colors.white;
      final borderPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (final offset in offsets) {
        canvas.drawCircle(offset, 3, dotPaint);
        canvas.drawCircle(offset, 3, borderPaint);
      }
    }

    drawSeries(offsetsFor((point) => point.expense), _primaryColor);
    drawSeries(offsetsFor((point) => point.income), const Color(0xFF9EA4AA));
    drawSeries(
      offsetsFor((point) => math.max(0, point.balance)),
      const Color(0xFF7EBE9F),
    );

    final maxExpense = points.reduce((a, b) => a.expense >= b.expense ? a : b);
    if (maxExpense.expense > 0) {
      final index = points.indexOf(maxExpense);
      final offset = offsetsFor((point) => point.expense)[index];
      final guidePaint = Paint()
        ..color = const Color(0xFFC7BFB7)
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(offset.dx, chart.top),
        Offset(offset.dx, chart.bottom),
        guidePaint,
      );
      final label = '${maxExpense.detailLabel}\n支出${money(maxExpense.expense)}';
      textPainter.text = TextSpan(
        text: label,
        style: const TextStyle(color: Colors.white, fontSize: 10),
      );
      textPainter.layout();
      final labelRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          (offset.dx - textPainter.width / 2 - 6).clamp(0, size.width - 70),
          math.max(chart.top + 4, offset.dy - 44),
          textPainter.width + 12,
          textPainter.height + 8,
        ),
        const Radius.circular(6),
      );
      canvas.drawRRect(
        labelRect,
        Paint()..color = Colors.black.withValues(alpha: 0.45),
      );
      textPainter.paint(canvas, Offset(labelRect.left + 6, labelRect.top + 4));
    }

    final step = math.max(1, (points.length / 6).ceil());
    for (var i = 0; i < points.length; i += step) {
      final x = points.length == 1
          ? chart.center.dx
          : chart.left + chart.width * i / (points.length - 1);
      textPainter.text = TextSpan(
        text: points[i].label,
        style: const TextStyle(color: Color(0xFFB8AEA5), fontSize: 10),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, chart.bottom + 7),
      );
    }
  }

  @override
  bool shouldRepaint(covariant TrendLinePainter oldDelegate) {
    return oldDelegate.points != points;
  }
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
              padding: const EdgeInsets.all(22),
              decoration: whiteCardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '总预算 ${money(store.monthlyBudget)}',
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
      ..sort((a, b) => a.category.compareTo(b.category));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: SectionTitle(title: '分类预算')),
            TextButton.icon(
              onPressed: () => openCategoryBudgetEditor(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加分类'),
              style: TextButton.styleFrom(
                foregroundColor: _textColor,
                backgroundColor: const Color(0xFFFFF0B8),
                shape: const StadiumBorder(),
              ),
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
              onEdit: () => openCategoryBudgetEditor(context, budget: budget),
              onDelete: () =>
                  confirmDeleteCategoryBudget(context, store, budget),
            );
          }),
      ],
    );
  }
}

void openCategoryBudgetEditor(BuildContext context, {CategoryBudget? budget}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => CategoryBudgetEditPage(budgetId: budget?.id),
    ),
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
    required this.onEdit,
    required this.onDelete,
  });

  final CategoryBudget budget;
  final double spent;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ratio = budget.limit <= 0
        ? 0.0
        : (spent / budget.limit).clamp(0, 1).toDouble();
    final left = budget.limit - spent;
    return Container(
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
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                      backgroundColor: _softColor,
                      color: left >= 0 ? _accentColor : _primaryColor,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '猫爪已用 ${money(spent)} / 预算 ${money(budget.limit)}',
                      style: const TextStyle(color: _mutedColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz_rounded, color: _mutedColor),
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
        ],
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
        title: Text(budget == null ? '添加分类预算' : '编辑分类预算'),
        actions: [
          if (budget != null)
            IconButton(
              tooltip: '删除',
              onPressed: () =>
                  confirmDeleteCategoryBudget(context, store, budget),
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
          Container(
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
                    ClipRRect(
                      borderRadius: BorderRadius.circular(26),
                      child: Image.asset(
                        'assets/images/app_icon.png',
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '猫猫记账员',
                            style: TextStyle(
                              fontSize: 20,
                              color: _textColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '已经认真踩爪记账 ${store.accountingDays} 天',
                            style: const TextStyle(color: _mutedColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEFE6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _primaryColor.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                const CatPawMark(size: 20, color: _primaryColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    store.monthBalance >= 0
                        ? '本月小猫攒下了 ${money(store.monthBalance)}'
                        : '本月小猫多花了 ${money(store.monthBalance.abs())}',
                    style: const TextStyle(
                      color: _mutedColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          MineSwitchTile(
            icon: Icons.notifications_rounded,
            title: '记账提醒',
            value: store.reminderEnabled,
            onChanged: store.setReminder,
          ),
          MineTile(
            icon: Icons.emoji_events_rounded,
            title: '成就徽章',
            subtitle:
                '${store.records.length} 笔记录，本月结余 ${money(store.monthBalance)}',
            onTap: () => showAchievementDialog(context, store),
          ),
          MineTile(
            icon: Icons.download_done_rounded,
            title: '数据状态',
            subtitle: '已自动保存在本机',
            onTap: () => showToast(context, '数据会自动保存在本机'),
          ),
          MineTile(
            icon: Icons.delete_sweep_rounded,
            title: '清空数据',
            subtitle: '删除所有记账记录和储蓄进度',
            danger: true,
            onTap: () => confirmClearData(context, store),
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
                          ? '今天还没有支出'
                          : '今天还没有收入',
                      subtitle: '去「记账」页添加后，这里会自动显示',
                    )
                  else
                    ...selectedRecords.map(
                      (record) => RecordItem(record: record),
                    ),
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
                  valueColor: _primaryColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: HomeTodayMetric(
                  title: '收入',
                  value: money(income),
                  valueColor: _greenColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: HomeTodayMetric(
                  title: '结余',
                  value: money(balance),
                  valueColor: balance >= 0 ? _greenColor : _primaryColor,
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
      onDismissed: (_) {
        AppScope.of(context).deleteRecord(record.id);
        showToast(context, '已删除记录');
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RecordDetailPage(recordId: record.id),
            ),
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
                      '${record.note.isEmpty ? '无备注' : record.note} · ${formatRecordDate(record.date)}',
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
                '${isIncome ? '+' : '-'}${money(record.amount)}',
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
        actions: [
          IconButton(
            tooltip: '编辑',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditRecordPage(recordId: record.id),
                ),
              );
            },
            icon: const Icon(Icons.edit_rounded),
          ),
        ],
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
                    '${isIncome ? '+' : '-'}${money(record.amount)}',
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
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: () => confirmDeleteRecord(context, store, record),
                icon: const Icon(Icons.delete_rounded),
                label: const Text('删除这笔记录'),
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
            selectedDate: selectedDate,
            onPickDate: _pickDate,
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
            '${(stat.ratio * 100).round()}%',
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
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: whiteCardDecoration(),
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
          Switch(
            value: value,
            activeThumbColor: _primaryColor,
            onChanged: onChanged,
          ),
        ],
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
  return Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const AchievementPage()),
  );
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
      store.monthlyBudget > 0 &&
      store.monthExpense <= store.monthlyBudget;
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
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: '返回',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: _textColor,
                        ),
                      ),
                      const SizedBox(width: 4),
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
  if (confirm == true) {
    await store.deleteRecord(record.id);
    if (!context.mounted) return;
    showToast(context, '已删除记录');
    Navigator.pop(context);
  }
}

Future<void> confirmDeleteCategoryBudget(
  BuildContext context,
  AppStore store,
  CategoryBudget budget,
) async {
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
    if (context.mounted) showToast(context, '分类预算已删除');
  }
}

void showToast(BuildContext context, String message) {
  final width = math.min(MediaQuery.sizeOf(context).width - 40, 360).toDouble();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: width,
        elevation: 0,
        backgroundColor: Colors.transparent,
        padding: EdgeInsets.zero,
        duration: const Duration(milliseconds: 1800),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBF8),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _primaryColor.withValues(alpha: 0.18)),
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
    );
}

String money(double value) {
  final sign = value < 0 ? '-' : '';
  final absValue = value.abs();
  return '$sign¥${absValue.toStringAsFixed(2)}';
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

String formatMonthDay(DateTime date) {
  return '${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
}

String formatYearMonth(DateTime date) {
  return '${date.year}年${date.month.toString().padLeft(2, '0')}月';
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
