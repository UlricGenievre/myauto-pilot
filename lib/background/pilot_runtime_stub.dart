/// Version web (apercu de dev) : pas de reveils ni de notifications.
library;

bool get pilotSupported => false;

Future<void> initPilotRuntime() async {}

Future<void> runPilotTick() async {}

Future<void> confirmPilotCommand(String commandId) async {}

Future<void> ignorePilotCommand(String commandId) async {}

Future<bool> requestPilotPermissions() async => false;

Future<bool> notificationsAllowed() async => false;

Future<bool> requestNotifications() async => false;

Future<bool> exactAlarmsAllowed() async => false;

Future<bool> requestExactAlarms() async => false;

void showPilotInfo(String title, String body) {}
