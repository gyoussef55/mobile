import 'package:flutter/material.dart';

const kLichessHost =
    String.fromEnvironment('LICHESS_HOST', defaultValue: 'https://lichess.dev');
const kLichessDevUser =
    String.fromEnvironment('LICHESS_DEV_USER', defaultValue: 'lichess');
const kLichessDevPassword = String.fromEnvironment('LICHESS_DEV_PASSWORD');

const kLichessClientId = 'lichess_mobile';
const kOAuthTokenStorageKey = 'oAuthToken';

// SPACING
const kBodyPadding = EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0);

// TEXT STYLE
const kBold = TextStyle(fontWeight: FontWeight.bold);
const kSectionTitle = TextStyle(fontSize: 16);

// lichess
// https://github.com/lichess-org/lila/blob/4562a83cdb263c3ebf7e148c0f666f0ff92b91c7/modules/rating/src/main/Glicko.scala#L71
const kProvisionalDeviation = 110;
const kClueLessDeviation = 230;

// Misc
const kPlatformCardBorder = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(10.0)));

const kEmptyWidget = SizedBox.shrink();
const kEmptyFen = '8/8/8/8/8/8/8/8 w - - 0 1';

const kSupportedLocales = [
  Locale('af', ''),
  Locale('ar', ''),
  Locale('az', ''),
  Locale('be', ''),
  Locale('bg', ''),
  Locale('bn', ''),
  Locale('br', ''),
  Locale('bs', ''),
  Locale('ca', ''),
  Locale('cs', ''),
  Locale('da', ''),
  Locale('de', ''),
  Locale('de', 'CH'),
  Locale('el', ''),
  Locale('en', ''),
  Locale('en', 'GB'),
  Locale('en', 'US'),
  Locale('eo', ''),
  Locale('es', ''),
  Locale('et', ''),
  Locale('eu', ''),
  Locale('fa', ''),
  Locale('fi', ''),
  Locale('fo', ''),
  Locale('fr', ''),
  Locale('ga', ''),
  Locale('gl', ''),
  Locale('he', ''),
  Locale('hi', ''),
  Locale('hr', ''),
  Locale('hu', ''),
  Locale('hy', ''),
  Locale('id', ''),
  Locale('it', ''),
  Locale('ja', ''),
  Locale('kk', ''),
  Locale('ko', ''),
  Locale('lb', ''),
  Locale('lt', ''),
  Locale('lv', ''),
  Locale('mk', ''),
  Locale('nb', ''),
  Locale('nl', ''),
  Locale('nn', ''),
  Locale('pl', ''),
  Locale('pt', ''),
  Locale('pt', 'BR'),
  Locale('ro', ''),
  Locale('ru', ''),
  Locale('sk', ''),
  Locale('sl', ''),
  Locale('sq', ''),
  Locale('sr', ''),
  Locale('sv', ''),
  Locale('tr', ''),
  Locale('tt', ''),
  Locale('uk', ''),
  Locale('vi', ''),
  Locale('zh', ''),
  Locale('zh', 'CN'),
  Locale('zh', 'TW'),
];
