// ignore_for_file: avoid_print

import 'dart:io';
import 'package:args/args.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('name', abbr: 'n', help: 'App Display Name')
    ..addOption('bundle-id',
        abbr: 'i', help: 'Bundle Identifier (com.example.app)')
    ..addOption('asset-dir',
        abbr: 'a', help: 'Directory containing logo.png and splash.png')
    // --- Android Signing ---
    ..addOption('keystore-path',
        help: 'Path to the .jks keystore file for signing the APK')
    ..addOption('key-password', help: 'Password for the keystore and key alias')
    ..addOption('key-alias',
        defaultsTo: 'upload', help: 'Key alias inside the keystore')
    // --- Firebase ---
    ..addOption('google-json',
        help: 'Path to google-services.json for Android Firebase')
    ..addOption('google-plist',
        help: 'Path to GoogleService-Info.plist for iOS Firebase')
    // --- iOS Signing (Apple API Key) ---
    ..addOption('apple-team-id', help: 'Apple Developer Team ID')
    ..addOption('apple-issuer-id', help: 'App Store Connect API Issuer ID')
    ..addOption('apple-key-id', help: 'App Store Connect API Key ID')
    ..addOption('p8-path', help: 'Path to the Apple API .p8 key file');

  final args = parser.parse(arguments);
  final String? appName = args['name'];
  final String? bundleId = args['bundle-id'];
  final String? assetDir = args['asset-dir'];

  if (appName == null || bundleId == null || assetDir == null) {
    print(
        '❌ Usage: dart run rebrand_cli:rebrand -n "My App" -i "com.app" -a "./assets"');
    exit(1);
  }

  final androidDir = Directory('android');
  final iosDir = Directory('ios');

  if (!androidDir.existsSync() || !iosDir.existsSync()) {
    print(
        '❌ Error: This script must be run from the root of your Flutter project.');
    print(
        '   Please run it from the directory containing "android" and "ios" folders.');
    exit(1);
  }

  try {
    print('🚀 Starting Rebrand for $appName ($bundleId)...');

    // ─── 1. Android Rebranding ───────────────────────────────────────────────

    await _replaceInFile('android/app/src/main/AndroidManifest.xml',
        RegExp(r'android:label="[^"]*"'), 'android:label="$appName"');

    final buildGradle = File('android/app/build.gradle');
    final buildGradleKts = File('android/app/build.gradle.kts');
    final gradleFile =
        await buildGradle.exists() ? buildGradle : buildGradleKts;

    if (await gradleFile.exists()) {
      await _replaceInFile(
          gradleFile.path,
          RegExp(r'applicationId\s*=?\s*"[^"]*"'),
          'applicationId = "$bundleId"');
      await _replaceInFile(gradleFile.path, RegExp(r'namespace\s*=?\s*"[^"]*"'),
          'namespace = "$bundleId"');
    }

    await _updateAndroidPackage(bundleId);

    // ─── 2. Android Signing: key.properties ─────────────────────────────────

    final keystorePath = args['keystore-path'] as String?;
    final keyPassword = args['key-password'] as String?;
    final keyAlias = args['key-alias'] as String? ?? 'upload';

    if (keystorePath != null && keyPassword != null) {
      print('🔑 Writing Android key.properties...');
      final keyProps = File('android/key.properties');
      await keyProps.writeAsString('''storePassword=$keyPassword
keyPassword=$keyPassword
keyAlias=$keyAlias
storeFile=${File(keystorePath).absolute.path}
''');

      // Ensure build.gradle.kts references key.properties for release signing
      // await _ensureAndroidSigningConfig(gradleFile.path, keyAlias);
      print('✅ Android signing properties generated.');
    } else {
      print('⚠️  No keystore provided — APK will be unsigned (debug mode).');
    }

    // ─── 3. Firebase Config Files ────────────────────────────────────────────

    final googleJsonPath = args['google-json'] as String?;
    if (googleJsonPath != null && await File(googleJsonPath).exists()) {
      print('🔥 Copying google-services.json...');
      await File(googleJsonPath).copy('android/app/google-services.json');
    }

    final googlePlistPath = args['google-plist'] as String?;
    if (googlePlistPath != null && await File(googlePlistPath).exists()) {
      print('🔥 Copying GoogleService-Info.plist...');
      await File(googlePlistPath).copy('ios/Runner/GoogleService-Info.plist');
    }

    // ─── 4. iOS Rebranding ───────────────────────────────────────────────────

    await _updateIOSDisplayName(appName);
    await _replaceInFile(
        'ios/Runner.xcodeproj/project.pbxproj',
        RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = [^;]+;'),
        'PRODUCT_BUNDLE_IDENTIFIER = $bundleId;');

    // ─── 5. iOS Signing: Apple API Key info ─────────────────────────────────

    final appleTeamId = args['apple-team-id'] as String?;
    final appleIssuerId = args['apple-issuer-id'] as String?;
    final appleKeyId = args['apple-key-id'] as String?;
    final p8Path = args['p8-path'] as String?;

    if (appleTeamId != null && appleIssuerId != null && appleKeyId != null) {
      print('🍎 Writing iOS signing config (apple_signing.env)...');
      final signingEnv = File('ios/apple_signing.env');
      await signingEnv.writeAsString('''APPLE_TEAM_ID=$appleTeamId
APP_STORE_CONNECT_API_ISSUER_ID=$appleIssuerId
APP_STORE_CONNECT_API_KEY_ID=$appleKeyId
''');

      if (p8Path != null && await File(p8Path).exists()) {
        await File(p8Path).copy('ios/auth.p8');
        print('✅ Apple .p8 key copied to ios/auth.p8');
      }

      // Also update DEVELOPMENT_TEAM in Xcode project
      await _replaceInFile(
          'ios/Runner.xcodeproj/project.pbxproj',
          RegExp(r'DEVELOPMENT_TEAM = [^;]*;'),
          'DEVELOPMENT_TEAM = $appleTeamId;');

      print('✅ iOS signing configured.');
    } else {
      print(
          '⚠️  No Apple signing info provided — IPA will not be signed for distribution.');
    }

    // ─── 6. Icon & Splash Generation ────────────────────────────────────────

    await _generateIcons(assetDir);
    await _generateSplash(assetDir);

    // ─── 7. iOS Export Options (for IPA) ────────────────────────────────────
    if (appleTeamId != null) {
      await _generateExportOptions(bundleId, appleTeamId);
    }

    print('');

    print('');
    print('✅ Success: App rebranded to "$appName" ($bundleId)');
  } catch (e) {
    print('❌ Rebrand failed: $e');
    exit(1);
  }
}

// ─── Helpers ────────────────────────────────────────────────────────────────

/// Ensures the android build.gradle(.kts) has a signingConfigs block that reads
/// from key.properties, and that the release build type uses it.
// function removed as per request

Future<void> _updateIOSDisplayName(String appName) async {
  final file = File('ios/Runner/Info.plist');
  if (!await file.exists()) return;
  String content = await file.readAsString();

  if (content.contains('<key>CFBundleDisplayName</key>')) {
    content = content.replaceAll(
        RegExp(r'<key>CFBundleDisplayName</key>\s*<string>[^<]*</string>'),
        '<key>CFBundleDisplayName</key>\n\t<string>$appName</string>');
  } else {
    content = content.replaceFirst('<dict>',
        '<dict>\n\t<key>CFBundleDisplayName</key>\n\t<string>$appName</string>');
  }
  content = content.replaceAll(
      RegExp(r'<key>CFBundleName</key>\s*<string>[^<]*</string>'),
      '<key>CFBundleName</key>\n\t<string>$appName</string>');
  await file.writeAsString(content);
}

Future<void> _generateIcons(String assetDir) async {
  print('🧹 Removing old icons...');
  await _cleanupOldIcons();

  final logoPath = '$assetDir/logo.png';
  final configFile = File('rebrand_launcher_icons.yaml');
  await configFile.writeAsString('''
flutter_launcher_icons:
  android: "launcher_icon"
  ios: true
  image_path: "$logoPath"
  remove_alpha_ios: true
  min_sdk_android: 21
''');

  print('🎨 Generating App Icons...');
  final result = await Process.run('dart', [
    'run',
    'flutter_launcher_icons:main',
    '-f',
    'rebrand_launcher_icons.yaml'
  ]);
  if (result.exitCode != 0) {
    throw Exception('Icon generation failed: ${result.stderr}');
  }
  await configFile.delete();
}

Future<void> _generateSplash(String assetDir) async {
  final splashPath = '$assetDir/splash.png';
  final configFile = File('rebrand_native_splash.yaml');
  await configFile.writeAsString('''
flutter_native_splash:
  color: "#FFFFFF"
  image: "$splashPath"
  android_12:
    image: "$splashPath"
    color: "#FFFFFF"
''');

  print('🌊 Generating Splash Screen...');
  final result = await Process.run('dart', [
    'run',
    'flutter_native_splash:create',
    '--path=rebrand_native_splash.yaml'
  ]);

  if (result.exitCode != 0) {
    throw Exception('Splash generation failed: ${result.stderr}');
  }
  await configFile.delete();
}

Future<void> _replaceInFile(String path, RegExp query, String replace) async {
  final file = File(path);
  if (await file.exists()) {
    final content = await file.readAsString();
    await file.writeAsString(content.replaceAll(query, replace));
  }
}

Future<void> _updateAndroidPackage(String newBundleId) async {
  final androidMainDir = Directory('android/app/src/main');
  final kotlinDir = Directory('${androidMainDir.path}/kotlin');
  final javaDir = Directory('${androidMainDir.path}/java');

  Directory? sourceDir;
  if (await kotlinDir.exists()) {
    sourceDir = kotlinDir;
  } else if (await javaDir.exists()) {
    sourceDir = javaDir;
  }

  if (sourceDir == null) return;

  File? mainActivityFile;
  await for (final entity in sourceDir.list(recursive: true)) {
    if (entity is File &&
        (entity.path.endsWith('MainActivity.kt') ||
            entity.path.endsWith('MainActivity.java'))) {
      mainActivityFile = entity;
      break;
    }
  }

  if (mainActivityFile == null) return;

  final content = await mainActivityFile.readAsString();
  final packageMatch = RegExp(r'package\s+([\w\.]+)').firstMatch(content);
  if (packageMatch == null) return;

  final oldPackage = packageMatch.group(1)!;
  if (oldPackage == newBundleId) return;

  final newPackagePath = newBundleId.replaceAll('.', '/');
  final newDir = Directory('${sourceDir.path}/$newPackagePath');
  await newDir.create(recursive: true);

  final newFile =
      File('${newDir.path}/${mainActivityFile.path.split('/').last}');
  await mainActivityFile.rename(newFile.path);

  String newContent = await newFile.readAsString();
  newContent =
      newContent.replaceAll('package $oldPackage', 'package $newBundleId');
  await newFile.writeAsString(newContent);

  print('📦 Moved MainActivity to $newPackagePath');
}

Future<void> _cleanupOldIcons() async {
  final androidResDir = Directory('android/app/src/main/res');
  if (await androidResDir.exists()) {
    await for (final entity in androidResDir.list()) {
      if (entity is Directory && entity.path.contains('mipmap-')) {
        await for (final file in Directory(entity.path).list()) {
          if (file is File && file.path.contains('launcher_icon')) {
            await file.delete();
          }
        }
      }
    }
  }

  final iosIconDir = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
  if (await iosIconDir.exists()) {
    await for (final file in iosIconDir.list()) {
      if (file is File && file.path.endsWith('.png')) {
        await file.delete();
      }
    }
  }
}

Future<void> _generateExportOptions(String bundleId, String teamId) async {
  final file = File('ios/ExportOptions.plist');
  // Always regenerate to ensure teamID and bundleId are correct
  print('📝 Generating iOS ExportOptions.plist...');

  await file.writeAsString('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store</string>
	<key>teamID</key>
	<string>$teamId</string>
	<key>uploadBitcode</key>
	<false/>
	<key>compileBitcode</key>
	<false/>
	<key>uploadSymbols</key>
	<true/>
	<key>signingStyle</key>
	<string>manual</string>
	<key>signingCertificate</key>
	<string>Apple Distribution</string>
	<key>provisioningProfiles</key>
	<dict>
		<key>$bundleId</key>
		<string>match AppStore $bundleId</string>
	</dict>
</dict>
</plist>
''');
}
