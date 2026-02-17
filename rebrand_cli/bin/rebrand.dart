// ignore_for_file: avoid_print

import 'dart:io';
import 'package:args/args.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('name', abbr: 'n', help: 'App Display Name')
    ..addOption('bundle-id',
        abbr: 'i', help: 'Bundle Identifier (com.example.app)')
    ..addOption('asset-dir', abbr: 'a', help: 'Directory containing logo.png');

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
    print('🚀 Starting Rebrand for $appName...');

    // 1. Android Rebranding
    await _replaceInFile('android/app/src/main/AndroidManifest.xml',
        RegExp(r'android:label="[^"]*"'), 'android:label="$appName"');

    // Update build.gradle (Groovy) or build.gradle.kts (Kotlin)
    final buildGradle = File('android/app/build.gradle');
    final buildGradleKts = File('android/app/build.gradle.kts');
    final gradleFile =
        await buildGradle.exists() ? buildGradle : buildGradleKts;

    if (await gradleFile.exists()) {
      // Update applicationId (supports both 'applicationId "id"' and 'applicationId = "id"')
      await _replaceInFile(
          gradleFile.path,
          RegExp(r'applicationId\s*=?\s*"[^"]*"'),
          'applicationId = "$bundleId"'); // Using = is fail-safe for both in most contexts, or match style

      // Update namespace (common in newer Android projects)
      await _replaceInFile(gradleFile.path, RegExp(r'namespace\s*=?\s*"[^"]*"'),
          'namespace = "$bundleId"');
    }

    // Update Android Package Structure
    await _updateAndroidPackage(bundleId);

    // 2. iOS Rebranding
    await _updateIOSDisplayName(appName);
    await _replaceInFile(
        'ios/Runner.xcodeproj/project.pbxproj',
        RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = [^;]+;'),
        'PRODUCT_BUNDLE_IDENTIFIER = $bundleId;');

    // 3. Icon Generation
    await _generateIcons(assetDir);

    // 4. Splash Generation
    await _generateSplash(assetDir);

    print('✅ Success: App rebranded to $appName ($bundleId)');
  } catch (e) {
    print('❌ Rebrand failed: $e');
    exit(1);
  }
}

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
  final logoPath = '$assetDir/logo.png';
  final configFile = File('rebrand_native_splash.yaml');
  await configFile.writeAsString('''
flutter_native_splash:
  color: "#FFFFFF"
  image: "$logoPath"
  android_12:
    image: "$logoPath"
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

  // Find MainActivity
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

  // Read current package
  final content = await mainActivityFile.readAsString();
  final packageMatch = RegExp(r'package\s+([\w\.]+)').firstMatch(content);
  if (packageMatch == null) return;

  final oldPackage = packageMatch.group(1)!;
  if (oldPackage == newBundleId) return; // Already updated

  // Move file
  final newPackagePath = newBundleId.replaceAll('.', '/');
  final newDir = Directory('${sourceDir.path}/$newPackagePath');
  await newDir.create(recursive: true);

  final newFile =
      File('${newDir.path}/${mainActivityFile.path.split('/').last}');
  await mainActivityFile.rename(newFile.path);

  // Update package declaration
  String newContent = await newFile.readAsString();
  newContent =
      newContent.replaceAll('package $oldPackage', 'package $newBundleId');
  await newFile.writeAsString(newContent);

  print('📦 Moved MainActivity to $newPackagePath');
}
