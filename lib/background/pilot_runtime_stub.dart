/// Version web (apercu de dev) : pas de reveils ni de notifications.
library;

bool get pilotSupported => false;

Future<void> initPilotRuntime() async {}

Future<void> runPilotTick() async {}

Future<void> confirmPilotCommand(String commandId) async {}

Future<void> ignorePilotCommand(String commandId) async {}

Future<bool> requestPilotPermissions() async => false;

void showPilotInfo(String title, String body) {}
