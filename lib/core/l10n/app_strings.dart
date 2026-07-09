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
    required this.onbSkip,
    required this.onbNext,
    required this.onbGetStarted,
    required this.onbSlide1Title,
    required this.onbSlide1Body,
    required this.onbSlide2Title,
    required this.onbSlide2Body,
    required this.onbSlide3Title,
    required this.onbSlide3Body,
    required this.authWelcome,
    required this.authSubtitle,
    required this.authGoogle,
    required this.authOffline,
    required this.authFreeNote,
    required this.authDemoNote,
    required this.smsTitle,
    required this.smsBody,
    required this.smsPoint1Title,
    required this.smsPoint1Body,
    required this.smsPoint2Title,
    required this.smsPoint2Body,
    required this.smsPoint3Title,
    required this.smsPoint3Body,
    required this.smsAllow,
    required this.smsDemo,
    required this.smsLater,
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
  });

  final String navHome;
  final String navLedger;
  final String navBudget;
  final String navReports;
  final String navProfile;

  final String onbSkip;
  final String onbNext;
  final String onbGetStarted;
  final String onbSlide1Title;
  final String onbSlide1Body;
  final String onbSlide2Title;
  final String onbSlide2Body;
  final String onbSlide3Title;
  final String onbSlide3Body;

  final String authWelcome;
  final String authSubtitle;
  final String authGoogle;
  final String authOffline;
  final String authFreeNote;
  final String authDemoNote;

  final String smsTitle;
  final String smsBody;
  final String smsPoint1Title;
  final String smsPoint1Body;
  final String smsPoint2Title;
  final String smsPoint2Body;
  final String smsPoint3Title;
  final String smsPoint3Body;
  final String smsAllow;
  final String smsDemo;
  final String smsLater;

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
}

const enStrings = AppStrings(
  navHome: 'Home',
  navLedger: 'Ledger',
  navBudget: 'Budget',
  navReports: 'Reports',
  navProfile: 'Profile',
  onbSkip: 'Skip',
  onbNext: 'Next',
  onbGetStarted: 'Get started',
  onbSlide1Title: 'Your SMS is already\na ledger',
  onbSlide1Body:
      'CBE, Telebirr, Awash, Abyssinia — every birr you move arrives as a '
      'text. Genzeb reads them and builds your money history automatically.',
  onbSlide2Title: 'See where every\nbirr goes',
  onbSlide2Body:
      'Spending by category, monthly trends, budgets that warn you before '
      'you overshoot — not after.',
  onbSlide3Title: 'Private. Smart.\nFree.',
  onbSlide3Body:
      'Everything stays on your phone. Ask Genzeb AI about your money '
      'anytime. No fees, no ads, no card required.',
  authWelcome: 'Welcome to Genzeb',
  authSubtitle: 'One account, and your free plan is ready.\n'
      'Your financial data always stays on your phone.',
  authGoogle: 'Continue with Google',
  authOffline: 'Continue offline',
  authFreeNote: 'Free forever · No card required',
  authDemoNote: 'Preview build — sign-in uses a demo account',
  smsTitle: 'Connect your SMS',
  smsBody: 'Ethiopian banks and Telebirr confirm every transaction by SMS. '
      'Genzeb reads those messages to build your ledger automatically.',
  smsPoint1Title: 'Only money messages matter',
  smsPoint1Body: 'OTPs and personal texts are ignored by the parser.',
  smsPoint2Title: 'Nothing leaves your phone',
  smsPoint2Body: 'Messages are processed and stored on this device only.',
  smsPoint3Title: 'You stay in control',
  smsPoint3Body: 'Uncertain matches wait for your approval in Review.',
  smsAllow: 'Allow SMS access & import',
  smsDemo: 'Explore with demo data',
  smsLater: 'Maybe later',
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
  madeFor: 'Made with ❤️ for Ethiopia',
  net: 'Net',
  ownTransfers: 'Own transfers',
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
);

const amStrings = AppStrings(
  navHome: 'መነሻ',
  navLedger: 'መዝገብ',
  navBudget: 'በጀት',
  navReports: 'ሪፖርት',
  navProfile: 'መገለጫ',
  onbSkip: 'ዝለል',
  onbNext: 'ቀጣይ',
  onbGetStarted: 'ጀምር',
  onbSlide1Title: 'የእርስዎ SMS ራሱ\nመዝገብ ነው',
  onbSlide1Body: 'ሲቢኢ፣ ቴሌብር፣ አዋሽ፣ አቢሲኒያ — እያንዳንዱ ብር በጽሑፍ መልዕክት ይደርሳል። '
      'ገንዘብ መልዕክቶቹን አንብቦ የገንዘብዎን ታሪክ በራስ-ሰር ይገነባል።',
  onbSlide2Title: 'እያንዳንዱ ብር የት\nእንደሚሄድ ይወቁ',
  onbSlide2Body: 'ወጪ በምድብ፣ ወርሃዊ አዝማሚያዎች፣ እና ከመብዛቱ በፊት የሚያስጠነቅቁ በጀቶች።',
  onbSlide3Title: 'የግል። ብልህ።\nነፃ።',
  onbSlide3Body: 'ሁሉም መረጃ በስልክዎ ላይ ይቀራል። ስለ ገንዘብዎ የገንዘብ AIን በማንኛውም ጊዜ '
      'ይጠይቁ። ክፍያ የለም፣ ማስታወቂያ የለም።',
  authWelcome: 'እንኳን ወደ ገንዘብ በደህና መጡ',
  authSubtitle: 'አንድ መለያ ብቻ — ነፃ እቅድዎ ዝግጁ ነው።\nየገንዘብ መረጃዎ ሁልጊዜ በስልክዎ ላይ ይቀራል።',
  authGoogle: 'በGoogle ይቀጥሉ',
  authOffline: 'ያለ መለያ ይቀጥሉ',
  authFreeNote: 'ለዘላለም ነፃ · ካርድ አያስፈልግም',
  authDemoNote: 'የሙከራ ግንባታ — መግቢያው የናሙና መለያ ይጠቀማል',
  smsTitle: 'SMSዎን ያገናኙ',
  smsBody: 'የኢትዮጵያ ባንኮች እና ቴሌብር እያንዳንዱን ግብይት በSMS ያረጋግጣሉ። ገንዘብ እነዚህን '
      'መልዕክቶች አንብቦ መዝገብዎን በራስ-ሰር ይገነባል።',
  smsPoint1Title: 'የገንዘብ መልዕክቶች ብቻ',
  smsPoint1Body: 'የማረጋገጫ ኮዶች እና የግል መልዕክቶች ችላ ይባላሉ።',
  smsPoint2Title: 'ምንም ከስልክዎ አይወጣም',
  smsPoint2Body: 'መልዕክቶች በዚህ መሣሪያ ላይ ብቻ ይታያሉ እና ይቀመጣሉ።',
  smsPoint3Title: 'ቁጥጥሩ የእርስዎ ነው',
  smsPoint3Body: 'እርግጠኛ ያልሆኑ ግጥሚያዎች በግምገማ ውስጥ ፈቃድዎን ይጠብቃሉ።',
  smsAllow: 'የSMS ፈቃድ ስጥ እና አስገባ',
  smsDemo: 'በናሙና ውሂብ ይመልከቱ',
  smsLater: 'ኋላ ላይ',
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
  madeFor: 'በ❤️ ለኢትዮጵያ የተሰራ',
  net: 'ተጣራ',
  ownTransfers: 'የራስ ዝውውሮች',
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
);
