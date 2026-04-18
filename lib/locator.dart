import 'package:get_it/get_it.dart';

import 'services/drive_book_repository.dart';
import 'services/drive_download_manager.dart';
import 'services/drive_library_service.dart';
import 'services/drive_service.dart';
import 'services/enrichment_service.dart';
import 'services/position_service.dart';
import 'services/preferences_service.dart';
import 'services/scanner_service.dart';
import 'services/sleep_timer_controller.dart';

final locator = GetIt.instance;

void setupLocator() {
  locator.registerLazySingleton<PositionService>(() => PositionService());
  locator.registerLazySingleton<PreferencesService>(() => PreferencesService());
  locator.registerLazySingleton<ScannerService>(() => ScannerService());
  locator.registerLazySingleton<EnrichmentService>(() => EnrichmentService());
  locator.registerLazySingleton<SleepTimerController>(
      () => SleepTimerController());
  locator.registerLazySingleton<DriveService>(() => DriveService());
  locator.registerLazySingleton<DriveBookRepository>(
      () => DriveBookRepository(locator<PositionService>()));
  locator.registerLazySingleton<DriveDownloadManager>(
      () => DriveDownloadManager(
            locator<DriveBookRepository>(),
            locator<DriveService>(),
          ));
  locator.registerLazySingleton<DriveLibraryService>(
      () => DriveLibraryService(
            locator<DriveBookRepository>(),
            locator<DriveService>(),
            locator<DriveDownloadManager>(),
            locator<PreferencesService>(),
            locator<ScannerService>(),
          ));
}
