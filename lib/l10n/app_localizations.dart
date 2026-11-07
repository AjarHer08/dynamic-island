import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_id.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('id')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Dynamic Island'**
  String get appTitle;

  /// No description provided for @nowPlaying.
  ///
  /// In en, this message translates to:
  /// **'NOW PLAYING'**
  String get nowPlaying;

  /// No description provided for @noTrack.
  ///
  /// In en, this message translates to:
  /// **'No track playing'**
  String get noTrack;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'NOTIFICATIONS'**
  String get notifications;

  /// No description provided for @noNotifications.
  ///
  /// In en, this message translates to:
  /// **'No notifications'**
  String get noNotifications;

  /// No description provided for @weather.
  ///
  /// In en, this message translates to:
  /// **'WEATHER'**
  String get weather;

  /// No description provided for @alarms.
  ///
  /// In en, this message translates to:
  /// **'ALARMS'**
  String get alarms;

  /// No description provided for @noAlarms.
  ///
  /// In en, this message translates to:
  /// **'No alarms set'**
  String get noAlarms;

  /// No description provided for @reminders.
  ///
  /// In en, this message translates to:
  /// **'REMINDERS'**
  String get reminders;

  /// No description provided for @noReminders.
  ///
  /// In en, this message translates to:
  /// **'No reminders yet'**
  String get noReminders;

  /// No description provided for @addReminderHint.
  ///
  /// In en, this message translates to:
  /// **'Add a reminder...'**
  String get addReminderHint;

  /// No description provided for @dnd.
  ///
  /// In en, this message translates to:
  /// **'DO NOT DISTURB'**
  String get dnd;

  /// No description provided for @dndSilenced.
  ///
  /// In en, this message translates to:
  /// **'Notifications silenced'**
  String get dndSilenced;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'SETTINGS'**
  String get settings;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language / Bahasa'**
  String get language;

  /// No description provided for @visualStyle.
  ///
  /// In en, this message translates to:
  /// **'Visual Style'**
  String get visualStyle;

  /// No description provided for @position.
  ///
  /// In en, this message translates to:
  /// **'Island Position'**
  String get position;

  /// No description provided for @visualizerMode.
  ///
  /// In en, this message translates to:
  /// **'Visualizer Mode'**
  String get visualizerMode;

  /// No description provided for @opacity.
  ///
  /// In en, this message translates to:
  /// **'Opacity'**
  String get opacity;

  /// No description provided for @auto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get auto;

  /// No description provided for @perfNote.
  ///
  /// In en, this message translates to:
  /// **'Optimised for Intel HD GPU / 4 GB RAM - Canvas rendering, max 40 particles, blur sigma <= 8'**
  String get perfNote;

  /// No description provided for @playerHint.
  ///
  /// In en, this message translates to:
  /// **'Play something on Spotify, YouTube Music, Apple Music or SoundCloud'**
  String get playerHint;

  /// No description provided for @clearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearAll;

  /// No description provided for @healthReminders.
  ///
  /// In en, this message translates to:
  /// **'BREAK & HYDRATION'**
  String get healthReminders;

  /// No description provided for @restReminder.
  ///
  /// In en, this message translates to:
  /// **'Take a break'**
  String get restReminder;

  /// No description provided for @waterReminder.
  ///
  /// In en, this message translates to:
  /// **'Drink water'**
  String get waterReminder;

  /// No description provided for @nextAt.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get nextAt;

  /// No description provided for @once.
  ///
  /// In en, this message translates to:
  /// **'Once'**
  String get once;

  /// No description provided for @everyDay.
  ///
  /// In en, this message translates to:
  /// **'Every day'**
  String get everyDay;

  /// No description provided for @addAlarm.
  ///
  /// In en, this message translates to:
  /// **'New alarm'**
  String get addAlarm;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @alarmLabel.
  ///
  /// In en, this message translates to:
  /// **'Label (optional)'**
  String get alarmLabel;

  /// No description provided for @clock.
  ///
  /// In en, this message translates to:
  /// **'CLOCK'**
  String get clock;

  /// No description provided for @lyrics.
  ///
  /// In en, this message translates to:
  /// **'LYRICS'**
  String get lyrics;

  /// No description provided for @noLyrics.
  ///
  /// In en, this message translates to:
  /// **'Lyrics not found'**
  String get noLyrics;

  /// No description provided for @loadingLyrics.
  ///
  /// In en, this message translates to:
  /// **'Searching lyrics...'**
  String get loadingLyrics;

  /// No description provided for @instrumental.
  ///
  /// In en, this message translates to:
  /// **'Instrumental'**
  String get instrumental;

  /// No description provided for @lyricsNeedTrack.
  ///
  /// In en, this message translates to:
  /// **'Play a song to see lyrics'**
  String get lyricsNeedTrack;

  /// No description provided for @accentColor.
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get accentColor;

  /// No description provided for @backgroundColor.
  ///
  /// In en, this message translates to:
  /// **'Background color'**
  String get backgroundColor;

  /// No description provided for @customColor.
  ///
  /// In en, this message translates to:
  /// **'Custom color'**
  String get customColor;

  /// No description provided for @colorAuto.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get colorAuto;

  /// No description provided for @feelsLike.
  ///
  /// In en, this message translates to:
  /// **'Feels like'**
  String get feelsLike;

  /// No description provided for @humidity.
  ///
  /// In en, this message translates to:
  /// **'Humidity'**
  String get humidity;

  /// No description provided for @wind.
  ///
  /// In en, this message translates to:
  /// **'Wind'**
  String get wind;

  /// No description provided for @rainChance.
  ///
  /// In en, this message translates to:
  /// **'Rain'**
  String get rainChance;

  /// No description provided for @chooseCity.
  ///
  /// In en, this message translates to:
  /// **'Choose location'**
  String get chooseCity;

  /// No description provided for @searchCity.
  ///
  /// In en, this message translates to:
  /// **'Search city...'**
  String get searchCity;

  /// No description provided for @autoLocation.
  ///
  /// In en, this message translates to:
  /// **'Detect automatically'**
  String get autoLocation;

  /// No description provided for @high.
  ///
  /// In en, this message translates to:
  /// **'H'**
  String get high;

  /// No description provided for @low.
  ///
  /// In en, this message translates to:
  /// **'L'**
  String get low;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'id'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'id':
      return AppLocalizationsId();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
