/// Lightweight bilingual string catalog (English / Amharic).
///
/// Kept as plain const objects instead of ARB codegen so adding a key is a
/// two-line change. Screens read the active catalog via `stringsProvider`.
class AppStrings {
  const AppStrings({
    required this.navHome,
    required this.navLedger,
    required this.navBudget,
    required this.navReports,
    required this.navProfile,
    required this.onbTitle,
    required this.onbBody,
    required this.onbGetStarted,
    required this.authGoogle,
    required this.smsTitle,
    required this.smsBody,
    required this.smsSkipped,
    required this.smsAllow,
    required this.smsDemo,
    required this.smsLater,
    required this.banksTitle,
    required this.banksFoundTitle,
    required this.banksFoundBody,
    required this.banksImport,
    required this.banksContinue,
    required this.banksSettingsBody,
    required this.banksOff,
    required this.banksNoTransactions,
    required this.banksNoneFound,
    required this.banksTurnOff,
    required this.banksTurnOffTitle,
    required this.banksTurnOffBody,
    required this.messageCount,
    required this.transactionCount,
    required this.cancel,
    required this.goodMorning,
    required this.goodAfternoon,
    required this.goodEvening,
    required this.allInstitutions,
    required this.totalBalance,
    required this.income,
    required this.expense,
    required this.add,
    required this.syncSms,
    required this.syncing,
    required this.accounts,
    required this.cashFlow,
    required this.insights,
    required this.recentActivity,
    required this.profileTitle,
    required this.yourPlan,
    required this.appearance,
    required this.theme,
    required this.themeSystem,
    required this.themeLight,
    required this.themeDark,
    required this.language,
    required this.automation,
    required this.dataPrivacy,
    required this.signOut,
    required this.preferences,
    required this.seePlans,
    required this.currentPlan,
    required this.transactions,
    required this.budgets,
    required this.madeFor,
    required this.net,
    required this.ownTransfers,
    required this.toCheck,
    required this.bankFees,
    required this.awaitingReview,
    required this.spendingBreakdown,
    required this.topMerchants,
    required this.biggestTransactions,
    required this.incomeBreakdown,
    required this.balanceOverTime,
    required this.sixMonthTrend,
    required this.dailyAverage,
    required this.projectedTotal,
    required this.vsPrevious,
    required this.other,
    required this.noSpendingPeriod,
    required this.share,
    required this.alertsTitle,
    required this.alertMoneyIn,
    required this.alertMoneyOut,
    required this.alertNeedsReview,
    required this.alertsEmpty,
    required this.alertsMarkRead,
  });

  final String navHome;
  final String navLedger;
  final String navBudget;
  final String navReports;
  final String navProfile;

  final String onbTitle;
  final String onbBody;
  final String onbGetStarted;

  final String authGoogle;

  final String smsTitle;
  final String smsBody;
  final String smsSkipped;
  final String smsAllow;
  final String smsDemo;
  final String smsLater;
  final String banksTitle;
  final String banksFoundTitle;
  final String banksFoundBody;
  final String banksImport;
  final String banksContinue;
  final String banksSettingsBody;
  final String banksOff;
  final String banksNoTransactions;
  final String banksNoneFound;
  final String banksTurnOff;
  final String Function(String name) banksTurnOffTitle;
  final String banksTurnOffBody;
  final String Function(int count) messageCount;
  final String Function(int count) transactionCount;
  final String cancel;

  final String goodMorning;
  final String goodAfternoon;
  final String goodEvening;
  final String allInstitutions;
  final String totalBalance;
  final String income;
  final String expense;
  final String add;
  final String syncSms;
  final String syncing;
  final String accounts;
  final String cashFlow;
  final String insights;
  final String recentActivity;

  final String profileTitle;
  final String yourPlan;
  final String appearance;
  final String theme;
  final String themeSystem;
  final String themeLight;
  final String themeDark;
  final String language;
  final String automation;
  final String dataPrivacy;
  final String signOut;
  final String preferences;
  final String seePlans;
  final String currentPlan;
  final String transactions;
  final String budgets;
  final String madeFor;
  final String net;
  final String ownTransfers;

  /// "3 to check" — possible own transfers waiting for a yes/no.
  final String toCheck;
  final String bankFees;
  final String awaitingReview;
  final String spendingBreakdown;
  final String topMerchants;
  final String biggestTransactions;
  final String incomeBreakdown;
  final String balanceOverTime;
  final String sixMonthTrend;
  final String dailyAverage;
  final String projectedTotal;
  final String vsPrevious;
  final String other;
  final String noSpendingPeriod;
  final String share;
  final String alertsTitle;
  final String alertMoneyIn;
  final String alertMoneyOut;
  final String alertNeedsReview;
  final String alertsEmpty;
  final String alertsMarkRead;
}

String _enTurnOffTitle(String name) => 'Turn off $name?';
String _enMessageCount(int n) => n == 1 ? '1 message' : '$n messages';
String _enTransactionCount(int n) =>
    n == 1 ? '1 transaction' : '$n transactions';

String _amTurnOffTitle(String name) => '$name ይጥፋ?';
String _amMessageCount(int n) => n == 1 ? '1 መልዕክት' : '$n መልዕክቶች';
String _amTransactionCount(int n) => n == 1 ? '1 ግብይት' : '$n ግብይቶች';

const enStrings = AppStrings(
  navHome: 'Home',
  navLedger: 'Ledger',
  navBudget: 'Budget',
  navReports: 'Reports',
  navProfile: 'Profile',
  onbTitle: 'All your banks and wallets in one place',
  onbBody: 'Genzeb tracks your spending from the texts they already send '
      'you.',
  onbGetStarted: 'Get started',
  authGoogle: 'Continue with Google',
  smsTitle: 'Genzeb reads only your bank texts',
  smsBody: 'It records your transactions from them. Personal messages and '
      'codes are skipped, and nothing leaves this phone.',
  smsSkipped: 'Skipped',
  smsAllow: 'Allow SMS access',
  smsDemo: 'Try sample data',
  smsLater: 'Not now',
  banksTitle: 'Banks & wallets',
  banksFoundTitle: 'Found your banks',
  banksFoundBody: 'Tap any you want to leave out. You can change this later '
      'in Profile.',
  banksImport: 'Import',
  banksContinue: 'Continue',
  banksSettingsBody: 'Turn one off to keep it out of your ledger.',
  banksOff: 'Off',
  banksNoTransactions: 'No transactions yet',
  banksNoneFound: 'No bank or wallet messages yet.',
  banksTurnOff: 'Turn off',
  banksTurnOffTitle: _enTurnOffTitle,
  banksTurnOffBody: 'Its transactions leave your ledger until you turn it '
      'back on.',
  messageCount: _enMessageCount,
  transactionCount: _enTransactionCount,
  cancel: 'Cancel',
  goodMorning: 'Good morning',
  goodAfternoon: 'Good afternoon',
  goodEvening: 'Good evening',
  allInstitutions: 'All institutions',
  totalBalance: 'Total balance',
  income: 'Income',
  expense: 'Expense',
  add: 'Add',
  syncSms: 'Sync SMS',
  syncing: 'Syncing…',
  accounts: 'Accounts',
  cashFlow: 'Cash flow',
  insights: 'Insights',
  recentActivity: 'Recent activity',
  profileTitle: 'Profile',
  yourPlan: 'Your plan',
  appearance: 'Appearance',
  theme: 'Theme',
  themeSystem: 'System',
  themeLight: 'Light',
  themeDark: 'Dark',
  language: 'Language',
  automation: 'Automation',
  dataPrivacy: 'Data & privacy',
  signOut: 'Sign out',
  preferences: 'Preferences',
  seePlans: 'See all plans',
  currentPlan: 'Current plan',
  transactions: 'Transactions',
  budgets: 'Budgets',
  madeFor: 'Made for Ethiopia',
  net: 'Net',
  ownTransfers: 'Own transfers',
  toCheck: 'to check',
  bankFees: 'Bank fees',
  awaitingReview: 'awaiting review',
  spendingBreakdown: 'Spending breakdown',
  topMerchants: 'Top merchants',
  biggestTransactions: 'Biggest transactions',
  incomeBreakdown: 'Income breakdown',
  balanceOverTime: 'Balance over time',
  sixMonthTrend: '6-month trend',
  dailyAverage: 'Daily average',
  projectedTotal: 'Projected total',
  vsPrevious: 'vs previous',
  other: 'Other',
  noSpendingPeriod: 'No spending in this period.',
  share: 'Share',
  alertsTitle: 'Notifications',
  alertMoneyIn: 'Money in',
  alertMoneyOut: 'Money out',
  alertNeedsReview: 'Needs your review',
  alertsEmpty: 'Money in and money out alerts will appear here as your bank '
      'and wallet messages arrive.',
  alertsMarkRead: 'Mark all read',
);

const amStrings = AppStrings(
  navHome: 'መነሻ',
  navLedger: 'መዝገብ',
  navBudget: 'በጀት',
  navReports: 'ሪፖርት',
  navProfile: 'መገለጫ',
  onbTitle: 'ሁሉም ባንኮችዎና ዋሌቶችዎ በአንድ ቦታ',
  onbBody: 'ገንዘብ ባንኮችዎ ከሚልኩልዎ መልዕክቶች ወጪዎን ይከታተላል።',
  onbGetStarted: 'ጀምር',
  authGoogle: 'በGoogle ይቀጥሉ',
  smsTitle: 'ገንዘብ የሚያነበው የባንክ መልዕክቶችዎን ብቻ ነው',
  smsBody: 'ግብይቶችዎን ከእነሱ ይመዘግባል። የግል መልዕክቶችና ኮዶች ይዘለላሉ፤ ምንም ከዚህ '
      'ስልክ አይወጣም።',
  smsSkipped: 'ተዘሏል',
  smsAllow: 'የSMS ፈቃድ ስጥ',
  smsDemo: 'በናሙና ውሂብ ሞክር',
  smsLater: 'ኋላ ላይ',
  banksTitle: 'ባንኮችና ዋሌቶች',
  banksFoundTitle: 'ባንኮችዎ ተገኝተዋል',
  banksFoundBody: 'የማይፈልጉትን ይንኩና ያስቀሩ። በኋላ በመገለጫ መቀየር ይችላሉ።',
  banksImport: 'አስገባ',
  banksContinue: 'ቀጥል',
  banksSettingsBody: 'ከመዝገብዎ ለማስቀረት ያጥፉት።',
  banksOff: 'ጠፍቷል',
  banksNoTransactions: 'ገና ግብይት የለም',
  banksNoneFound: 'ገና የባንክ ወይም የዋሌት መልዕክት የለም።',
  banksTurnOff: 'አጥፋ',
  banksTurnOffTitle: _amTurnOffTitle,
  banksTurnOffBody: 'መልሰው እስኪያበሩት ድረስ ግብይቶቹ ከመዝገብዎ ይወጣሉ።',
  messageCount: _amMessageCount,
  transactionCount: _amTransactionCount,
  cancel: 'ይቅር',
  goodMorning: 'እንደምን አደሩ',
  goodAfternoon: 'እንደምን ዋሉ',
  goodEvening: 'እንደምን አመሹ',
  allInstitutions: 'ሁሉም ተቋማት',
  totalBalance: 'ጠቅላላ ቀሪ ሂሳብ',
  income: 'ገቢ',
  expense: 'ወጪ',
  add: 'ጨምር',
  syncSms: 'SMS አመሳስል',
  syncing: 'በማመሳሰል ላይ…',
  accounts: 'ሂሳቦች',
  cashFlow: 'የገንዘብ ፍሰት',
  insights: 'ግንዛቤዎች',
  recentActivity: 'የቅርብ ጊዜ እንቅስቃሴ',
  profileTitle: 'መገለጫ',
  yourPlan: 'እቅድዎ',
  appearance: 'መልክ',
  theme: 'ገጽታ',
  themeSystem: 'ስርዓት',
  themeLight: 'ብርሃን',
  themeDark: 'ጨለማ',
  language: 'ቋንቋ',
  automation: 'ራስ-ሰር ተግባራት',
  dataPrivacy: 'ውሂብ እና ግላዊነት',
  signOut: 'ውጣ',
  preferences: 'ምርጫዎች',
  seePlans: 'ሁሉንም እቅዶች ይመልከቱ',
  currentPlan: 'የአሁን እቅድ',
  transactions: 'ግብይቶች',
  budgets: 'በጀቶች',
  madeFor: 'ለኢትዮጵያ የተሰራ',
  net: 'ተጣራ',
  ownTransfers: 'የራስ ዝውውሮች',
  toCheck: 'ለማረጋገጥ',
  bankFees: 'የባንክ ክፍያዎች',
  awaitingReview: 'ግምገማ በመጠበቅ ላይ',
  spendingBreakdown: 'የወጪ ትንተና',
  topMerchants: 'ዋና ነጋዴዎች',
  biggestTransactions: 'ትልልቅ ግብይቶች',
  incomeBreakdown: 'የገቢ ትንተና',
  balanceOverTime: 'ቀሪ ሂሳብ በጊዜ ሂደት',
  sixMonthTrend: 'የ6 ወር አዝማሚያ',
  dailyAverage: 'ዕለታዊ አማካይ',
  projectedTotal: 'የተገመተ ጠቅላላ',
  vsPrevious: 'ካለፈው ጋር',
  other: 'ሌላ',
  noSpendingPeriod: 'በዚህ ጊዜ ውስጥ ወጪ የለም።',
  share: 'አጋራ',
  alertsTitle: 'ማሳወቂያዎች',
  alertMoneyIn: 'ገቢ ገንዘብ',
  alertMoneyOut: 'ወጪ ገንዘብ',
  alertNeedsReview: 'ግምገማ ያስፈልገዋል',
  alertsEmpty: 'የባንክና የዋሌት መልዕክቶች ሲደርሱ የገቢና የወጪ ማሳወቂያዎች እዚህ ይታያሉ።',
  alertsMarkRead: 'ሁሉንም እንደተነበበ ምልክት አድርግ',
);
