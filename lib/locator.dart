import 'package:get_it/get_it.dart';

import 'services/enrichment_service.dart';
import 'services/position_service.dart';
import 'services/preferences_service.dart';
import 'services/scanner_service.dart';

final locator = GetIt.instance;

void setupLocator() {
  locator.registerLazySingleton<PositionService>(() => PositionService());
  locator.registerLazySingleton<PreferencesService>(() => PreferencesService());
  locator.registerLazySingleton<ScannerService>(() => ScannerService());
  locator.registerLazySingleton<EnrichmentService>(() => EnrichmentService());
}
