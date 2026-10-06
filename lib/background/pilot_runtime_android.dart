import 'dart:io' show Platform;
import 'dart:ui' show DartPluginRegistrant;

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/charge_plan/charge_pilot.dart';
import '../core/charge_plan/charge_planner.dart';
import '../core/charge_plan/kamereon_pilot_gateway.dart';
import '../core/storage/charge_plan_storage.dart';
import '../core/theme/app_theme.dart';

/// Implementation Android de `pilot_runtime.dart`.
///
/// Les reveils (`android_alarm_manager_plus`) et les actions de
/// notification tournent dans des isolates neufs, sans Riverpod ni etat en
/// memoire : tout passe par [ChargePilot], reconstruit a chaque fois depuis
/// le stockage.

bool get pilotSupported => Platform.isAndroid;

final _notifications = FlutterLocalNotificationsPlugin();

const _channel = AndroidNotificationChannel(
  'charge_pilot',
  'Pilotage de charge',
  description: 'Plages de charge à envoyer, charge immédiate jusqu\'au minimum, résultats des envois, rappel du soir.',
  importance: Importance.high,
);

/// Icone monochrome (android/app/src/main/res/drawable/ic_stat_charge.xml).
const _notificationIcon = 'ic_stat_charge';

const _confirmationId = 100;
const _resultId = 101;
const _reminderId = 102;
const _infoId = 103;
const _minimumId = 104;
const _actionSend = 'send';
const _actionIgnore = 'ignore';
const _actionMinimumStart = 'minimum_start';
const _actionMinimumIgnore = 'minimum_ignore';
const _minimumPayload = 'minimum';

/// A appeler au demarrage de l'app (isolate principal).
Future<void> initPilotRuntime() async {
  if (!pilotSupported) return;
  await AndroidAlarmManager.initialize();
  await _initNotifications();
}

/// Passage du pilote depuis l'app (ouverture, modification du parametrage).
Future<void> runPilotTick() async {
  if (!pilotSupported) return;
  await _createPilot().tick();
}

/// Boutons "Envoyer"/"Ignorer" de l'ecran de pilotage (memes effets que ceux
/// de la notification).
Future<void> confirmPilotCommand(String commandId) async {
  if (!pilotSupported) return;
  await _createPilot().confirm(commandId);
}

Future<void> ignorePilotCommand(String commandId) async {
  if (!pilotSupported) return;
  await _createPilot().ignore(commandId);
}

/// Boutons "Declencher"/"Ignorer" de la charge immediate jusqu'au minimum.
Future<void> confirmMinimumCharge() async {
  if (!pilotSupported) return;
  await _createPilot().confirmMinimum();
}

Future<void> ignoreMinimumCharge() async {
  if (!pilotSupported) return;
  await _createPilot().ignoreMinimum();
}

/// Autorisation d'afficher des notifications (Android 13+).
Future<bool> requestPilotPermissions() async {
  if (!pilotSupported) return false;
  return await _androidNotifications?.requestNotificationsPermission() ?? false;
}

/// Notifications autorisees pour l'app **et** pour son canal (l'utilisateur
/// peut couper l'un ou l'autre dans les reglages Android).
Future<bool> notificationsAllowed() async {
  if (!pilotSupported) return false;
  final android = _androidNotifications;
  if (android == null || await android.areNotificationsEnabled() != true) return false;
  final channels = await android.getNotificationChannels() ?? const [];
  for (final channel in channels) {
    if (channel.id == _channel.id) return channel.importance != Importance.none;
  }
  return true;
}

/// Redemande l'autorisation ; si Android ne l'affiche plus (refus
/// repetes) ou si c'est le canal qui est coupe, ouvre les reglages de
/// notification de l'app. Renvoie l'etat au retour.
Future<bool> requestNotifications() async {
  if (!pilotSupported) return false;
  if (await requestPilotPermissions() && await notificationsAllowed()) return true;
  await _androidNotifications?.openAppNotificationSettings();
  return notificationsAllowed();
}

/// Autorisation "Alarmes et rappels" (`SCHEDULE_EXACT_ALARM`), a accorder
/// par l'utilisateur depuis Android 14. Sans elle, les reveils sont
/// approximatifs (Android peut les retarder).
Future<bool> exactAlarmsAllowed() async {
  if (!pilotSupported) return false;
  return await _androidNotifications?.canScheduleExactNotifications() ?? false;
}

/// Ouvre le reglage Android "Alarmes et rappels" de l'app ; renvoie
/// l'autorisation au retour.
Future<bool> requestExactAlarms() async {
  if (!pilotSupported) return false;
  return await _androidNotifications?.requestExactAlarmsPermission() ?? false;
}

AndroidFlutterLocalNotificationsPlugin? get _androidNotifications =>
    _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

/// Notification d'information (ex. cles Renault mises a jour).
void showPilotInfo(String title, String body) {
  if (!pilotSupported) return;
  _AndroidPilotPlatform()._show(_infoId, title, body).ignore();
}

// --- Points d'entree en arriere-plan ------------------------------------------

/// Reveil programme par [ChargePilot] (`PilotWake.alarmId`).
@pragma('vm:entry-point')
Future<void> pilotAlarmCallback(int alarmId) async {
  await _initBackgroundIsolate();
  final pilot = _createPilot();
  if (alarmId == PilotWake.execute.alarmId) {
    await pilot.executeMinimum();
    await pilot.executeConfirmed();
    await pilot.tick();
  } else if (alarmId == PilotWake.evening.alarmId) {
    await pilot.eveningReminder();
    // Aussi l'occasion de proposer une charge immediate jusqu'au minimum.
    await pilot.tick();
  } else {
    await pilot.tick();
  }
}

/// Action d'une notification alors que l'app n'est pas au premier plan.
@pragma('vm:entry-point')
Future<void> pilotNotificationBackground(NotificationResponse response) async {
  await _initBackgroundIsolate();
  await _handleResponse(response);
}

Future<void> _handleResponse(NotificationResponse response) async {
  final commandId = response.payload;
  if (commandId == null) return;
  if (commandId == _minimumPayload) {
    switch (response.actionId) {
      case _actionMinimumStart:
        await _createPilot().confirmMinimum();
      case _actionMinimumIgnore:
        await _createPilot().ignoreMinimum();
    }
    return;
  }
  switch (response.actionId) {
    case _actionSend:
      await _createPilot().confirm(commandId);
    case _actionIgnore:
      await _createPilot().ignore(commandId);
  }
}

Future<void> _initBackgroundIsolate() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await AndroidAlarmManager.initialize();
  await _initNotifications();
}

Future<void> _initNotifications() async {
  await _notifications.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings(_notificationIcon)),
    onDidReceiveNotificationResponse: _handleResponse,
    onDidReceiveBackgroundNotificationResponse: pilotNotificationBackground,
  );
  await _androidNotifications?.createNotificationChannel(_channel);
}

ChargePilot _createPilot() => ChargePilot(
      store: ChargePlanStorage(),
      platform: _AndroidPilotPlatform(),
      gateway: () => KamereonPilotGateway.open(onKeysEvent: showPilotInfo),
    );

// --- Plateforme ----------------------------------------------------------------

class _AndroidPilotPlatform implements PilotPlatform {
  @override
  Future<void> scheduleWake(PilotWake wake, DateTime at) async {
    // Reveil exact refuse sans l'autorisation (SecurityException) : repli
    // sur un reveil approximatif, signale dans l'ecran de pilotage.
    await AndroidAlarmManager.oneShotAt(
      at,
      wake.alarmId,
      pilotAlarmCallback,
      exact: await exactAlarmsAllowed(),
      wakeup: true,
      allowWhileIdle: true,
      rescheduleOnReboot: true,
    );
  }

  @override
  Future<void> cancelWake(PilotWake wake) async {
    await AndroidAlarmManager.cancel(wake.alarmId);
  }

  @override
  Future<void> showConfirmation(ChargeCommand command, String body) => _show(
        _confirmationId,
        'Plage de charge à envoyer',
        body,
        payload: command.id,
        actions: const [
          AndroidNotificationAction(_actionSend, 'Envoyer'),
          AndroidNotificationAction(_actionIgnore, 'Ignorer'),
        ],
        autoCancel: false,
      );

  @override
  Future<void> dismissConfirmation() => _notifications.cancel(id: _confirmationId);

  @override
  Future<void> showResult(String title, String body) async {
    await dismissConfirmation();
    await _show(_resultId, title, body);
  }

  @override
  Future<void> showReminder(String body) => _show(_reminderId, 'Pilotage de charge', body);

  @override
  Future<void> showMinimumProposal(String body) => _show(
        _minimumId,
        'Batterie sous le minimum',
        body,
        payload: _minimumPayload,
        actions: const [
          AndroidNotificationAction(_actionMinimumStart, 'Déclencher'),
          AndroidNotificationAction(_actionMinimumIgnore, 'Ignorer'),
        ],
        autoCancel: false,
      );

  @override
  Future<void> dismissMinimumProposal() => _notifications.cancel(id: _minimumId);

  Future<void> _show(
    int id,
    String title,
    String body, {
    String? payload,
    List<AndroidNotificationAction>? actions,
    bool autoCancel = true,
  }) =>
      _notifications.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            icon: _notificationIcon,
            color: AppColors.accent,
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(body),
            actions: actions,
            autoCancel: autoCancel,
          ),
        ),
      );
}
