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
  description: 'Plages de charge à envoyer, résultats des envois, rappel du soir.',
  importance: Importance.high,
);

/// Icone monochrome (android/app/src/main/res/drawable/ic_stat_charge.xml).
const _notificationIcon = 'ic_stat_charge';

const _confirmationId = 100;
const _resultId = 101;
const _reminderId = 102;
const _infoId = 103;
const _actionSend = 'send';
const _actionIgnore = 'ignore';

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

/// Autorisation d'afficher des notifications (Android 13+). Les reveils
/// exacts utilisent `USE_EXACT_ALARM`, accordee d'office (cf. manifest).
Future<bool> requestPilotPermissions() async {
  if (!pilotSupported) return false;
  final android = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  return await android?.requestNotificationsPermission() ?? false;
}

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
    await pilot.executeConfirmed();
    await pilot.tick();
  } else if (alarmId == PilotWake.evening.alarmId) {
    await pilot.eveningReminder();
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
  await _notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_channel);
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
    await AndroidAlarmManager.oneShotAt(
      at,
      wake.alarmId,
      pilotAlarmCallback,
      exact: true,
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
