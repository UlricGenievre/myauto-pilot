import '../models/charge_plan_config.dart';
import '../models/vehicle_schedule.dart';
import 'charge_planner.dart';
import 'pilot_state.dart';

/// Acces au vehicule depuis un reveil (sans interface, donc sans les
/// providers Riverpod) : construit a partir de la session stockee.
abstract interface class PilotVehicleGateway {
  Future<int?> fetchSoc(String vin);
  Future<VehicleSchedule> fetchSchedule(String vin);
  Future<void> updateSchedule(String vin, Map<String, dynamic> settings);
}

/// Persistance de la config (lecture seule ici) et de l'etat d'execution.
abstract interface class PilotStore {
  Future<ChargePlanConfig> load();
  Future<PilotState> loadState();
  Future<void> saveState(PilotState state);
}

/// Reveils et notifications (Android). Implementation vide sur le web.
abstract interface class PilotPlatform {
  Future<void> scheduleWake(PilotWake wake, DateTime at);
  Future<void> cancelWake(PilotWake wake);

  /// Mode securise : propose l'envoi de [command] (actions Envoyer/Ignorer).
  Future<void> showConfirmation(ChargeCommand command, String body);
  Future<void> dismissConfirmation();
  Future<void> showResult(String title, String body);
  Future<void> showReminder(String body);
}

enum PilotWake {
  /// Heure d'envoi de la prochaine commande.
  next(1),

  /// Envoi d'une commande confirmee depuis la notification.
  execute(2),

  /// Rappel du soir.
  evening(3);

  const PilotWake(this.alarmId);

  final int alarmId;
}

/// Orchestration du pilotage automatique : quoi faire maintenant, quand se
/// reveiller. Appele a chaque reveil, a l'ouverture de l'app, apres une
/// modification du parametrage et apres une confirmation.
///
/// Pas de tache periodique : chaque passage traite la commande en vigueur
/// si elle n'a pas ete envoyee (rattrapage d'un reveil manque, ex.
/// telephone eteint) et reprogramme le reveil suivant.
class ChargePilot {
  ChargePilot({
    required this.store,
    required this.platform,
    required this.gateway,
    DateTime Function()? clock,
    this.pollInterval = const Duration(seconds: 5),
    this.pollTimeout = const Duration(seconds: 90),
  }) : _clock = clock ?? DateTime.now;

  final PilotStore store;
  final PilotPlatform platform;

  /// Null si aucune session n'est disponible (utilisateur deconnecte).
  final Future<PilotVehicleGateway?> Function() gateway;

  final DateTime Function() _clock;

  /// L'ecriture est asynchrone cote Renault : on relit jusqu'a voir changer
  /// `lastSettingsUpdateTimestamp` (constate : 5 a 20 s).
  final Duration pollInterval;
  final Duration pollTimeout;

  static final eveningTime = ClockTime.hm(20, 0);

  /// Duree maximale du verrou d'envoi : au-dela, un verrou est considere
  /// comme orphelin (app tuee en plein envoi) et ignore.
  static const sendLockTimeout = Duration(minutes: 3);

  /// Point d'entree general : traite la commande en vigueur et reprogramme
  /// les reveils.
  Future<void> tick() async {
    final config = await store.load();
    var state = await store.loadState();
    final vin = config.vehicleVin;

    // Pilotage coupe, ou modele sur lequel l'app ne doit pas ecrire.
    if (!config.enabled || vin == null || !config.vehicleSupport.canWrite) {
      for (final wake in PilotWake.values) {
        await platform.cancelWake(wake);
      }
      await platform.dismissConfirmation();
      await store.saveState(state.copyWith(clearPending: true, clearConfirmed: true, clearNextWake: true));
      return;
    }

    final vehicle = await _safeGateway();
    final soc = vehicle == null ? null : await _safeSoc(vehicle, vin);
    final now = _clock();
    final planner = ChargePlanner(config);
    final command = planner.commandInForce(now, socPercent: soc);

    // Une commande deja envoyee (ou ignoree) est reproposee si le
    // parametrage a change depuis et que son contenu differe (ex. objectif
    // supprime apres l'envoi d'une plage elargie pour lui).
    final fingerprint = config.fingerprint;
    final alreadySent = command != null && (state.sent?.covers(command, fingerprint) ?? false);
    final ignored = command != null && (state.ignored?.covers(command, fingerprint) ?? false);
    if (command != null && !alreadySent && !ignored) {
      if (!config.effectiveSafeMode) {
        state = await _send(config, state, command, vehicle);
      } else if (state.confirmedId == command.id) {
        // Confirmee : l'envoi est le role exclusif du reveil "execution"
        // programme a la confirmation. L'envoyer ici aussi (ex. "Recalculer"
        // pendant qu'il tourne) ferait une double ecriture simultanee, que
        // Renault refuse.
      } else if (!(state.pending?.covers(command, fingerprint) ?? false)) {
        // Nouvelle proposition, ou mise a jour de celle en attente.
        await platform.showConfirmation(command, describe(command));
        state = state.copyWith(pending: CommandMark.of(command, fingerprint));
      }
    }

    final upcoming = planner.upcomingCommand(now, socPercent: soc);
    if (upcoming != null) {
      await platform.scheduleWake(PilotWake.next, upcoming.pushAt);
      state = state.copyWith(nextWakeAt: upcoming.pushAt);
    } else {
      await platform.cancelWake(PilotWake.next);
      state = state.copyWith(clearNextWake: true);
    }
    await platform.scheduleWake(PilotWake.evening, _nextEvening(now));

    await store.saveState(state);
  }

  /// Action "Envoyer" de la notification. Tourne dans un contexte Android
  /// tres court (recepteur de notification) : on n'y fait qu'enregistrer la
  /// confirmation et programmer un reveil immediat, qui fera l'envoi.
  ///
  /// La confirmation porte sur le contenu exact de la proposition affichee
  /// (horaires, heure "pret a") : c'est lui qui sera envoye, sans recalcul.
  Future<void> confirm(String commandId) async {
    final state = await store.loadState();
    final pending = state.pending;
    final confirmed = pending != null && pending.id == commandId
        ? pending
        : CommandMark(id: commandId, signature: '', configFingerprint: '');
    await store.saveState(state.copyWith(confirmed: confirmed, clearPending: true));
    await platform.scheduleWake(PilotWake.execute, _clock().add(const Duration(seconds: 2)));
  }

  /// Action "Ignorer" de la notification.
  Future<void> ignore(String commandId) async {
    final state = await store.loadState();
    final pending = state.pending;
    await store.saveState(state.copyWith(
      ignored: pending != null && pending.id == commandId
          ? pending
          : CommandMark(id: commandId, signature: '', configFingerprint: (await store.load()).fingerprint),
      clearPending: true,
      clearConfirmed: true,
    ));
    await platform.dismissConfirmation();
  }

  /// Reveil "execution" : envoie **exactement** la proposition confirmee
  /// (jamais un recalcul que l'utilisateur n'aurait pas vu), si elle est
  /// toujours d'actualite :
  /// - plage plus en vigueur -> "expiree", rien n'est envoye ;
  /// - parametrage modifie depuis la confirmation -> rien n'est envoye, une
  ///   nouvelle proposition est faite par le passage qui suit ([tick]).
  Future<void> executeConfirmed() async {
    final config = await store.load();
    var state = await store.loadState();
    final confirmed = state.confirmed;
    final confirmedId = confirmed?.id;
    final vin = config.vehicleVin;
    if (confirmed == null || confirmedId == null || vin == null || !config.vehicleSupport.canWrite) return;

    // Un autre envoi est en cours : reessayer un peu plus tard plutot que
    // perdre la confirmation.
    final since = state.sendingSince;
    if (since != null && _clock().difference(since) < sendLockTimeout) {
      await platform.scheduleWake(PilotWake.execute, _clock().add(const Duration(minutes: 1)));
      return;
    }

    final vehicle = await _safeGateway();
    final soc = vehicle == null ? null : await _safeSoc(vehicle, vin);
    final command = ChargePlanner(config).commandInForce(_clock(), socPercent: soc);

    if (command == null || command.id != confirmedId) {
      state = _withResult(state.copyWith(clearConfirmed: true), 'Plage expirée : elle n\'est plus d\'actualité, rien n\'a été envoyé.',
          ok: false);
      await platform.showResult('Plage expirée', state.lastResult!);
      await store.saveState(state);
      return;
    }
    final toSend = confirmed.toCommand(_clock());
    if (toSend == null || confirmed.configFingerprint != config.fingerprint) {
      // Parametrage modifie (ou proposition inconnue) : ne rien envoyer que
      // l'utilisateur n'ait vu ; [tick] reproposera la plage a jour.
      await store.saveState(state.copyWith(clearConfirmed: true));
      return;
    }
    await store.saveState(await _send(config, state, toSend, vehicle));
  }

  /// Rappel du soir : prochain objectif et prochaine plage.
  Future<void> eveningReminder() async {
    final config = await store.load();
    if (!config.enabled) return;
    final now = _clock();
    final planner = ChargePlanner(config);
    final targets = planner.targets(now, now.add(const Duration(hours: 36)));
    final upcoming = planner.upcomingCommand(now);
    final lines = <String>[
      if (targets.isNotEmpty)
        'Objectif : ${targets.first.targetPercent} % ${_dayWord(targets.first.readyAt, now)} à ${_hm(targets.first.readyAt)}'
            '${targets.first.climate ? ', climatisée à ${targets.first.climateTemperature} °C' : ''}'
            '${targets.first.isOneOff ? ' (exceptionnel)' : ''}.'
      else
        'Aucun objectif d\'ici demain soir.',
      if (upcoming != null) 'Prochain envoi ${_dayWord(upcoming.pushAt, now)} à ${_hm(upcoming.pushAt)} : ${_window(upcoming)}.',
    ];
    await platform.showReminder(lines.join('\n'));
    await platform.scheduleWake(PilotWake.evening, _nextEvening(now));
  }

  // --- Envoi -------------------------------------------------------------------

  /// Envoi d'une commande, sous verrou : un seul envoi a la fois, que ce
  /// soit depuis l'app ou un reveil en arriere-plan (deux ecritures
  /// simultanees : Renault refuse la seconde). Si un envoi est deja en
  /// cours, ne fait rien.
  Future<PilotState> _send(
    ChargePlanConfig config,
    PilotState state,
    ChargeCommand command,
    PilotVehicleGateway? vehicle,
  ) async {
    // Relecture juste avant de verrouiller : l'etat [state] a pu etre lu
    // avant qu'un autre isolate ne pose son verrou.
    final fresh = await store.loadState();
    final since = fresh.sendingSince;
    if (since != null && _clock().difference(since) < sendLockTimeout) {
      // Garder le verrou de l'autre envoi dans ce que l'appelant sauvegardera.
      return state.copyWith(sendingSince: since);
    }
    await store.saveState(fresh.copyWith(sendingSince: _clock()));
    final result = await _sendUnlocked(config, state, command, vehicle);
    return result.copyWith(clearSending: true);
  }

  Future<PilotState> _sendUnlocked(
    ChargePlanConfig config,
    PilotState state,
    ChargeCommand command,
    PilotVehicleGateway? vehicle,
  ) async {
    final vin = config.vehicleVin!;
    final programIndex = config.dedicatedProgramIndex;
    if (!config.vehicleSupport.canWrite) {
      return _fail(state, command, 'Modèle de véhicule non pris en charge : aucune écriture.');
    }
    if (vehicle == null) {
      return _fail(state, command, 'Session expirée : ouvrez l\'app pour vous reconnecter.');
    }
    if (programIndex == null) {
      return _fail(state, command, 'Aucun programme dédié choisi dans le paramétrage.');
    }

    try {
      final current = await vehicle.fetchSchedule(vin);
      final settings = current.toUpdatedJson(
        chargeTimeStart: command.chargeTimeStart.format(),
        chargeDurationMinutes: command.durationMinutes,
        preconditioningTemperature: command.climate ? command.climateTemperature : null,
        programIndex: programIndex,
        departureTime: _hm(command.readyAt),
        programActive: true,
        // Actif le seul jour de l'heure "pret a" : pas de preparation non
        // desiree les autres jours (la plage est reecrite a chaque envoi).
        programDays: {command.readyDay},
        // Toujours ecrit : le programme dedie appartient a l'app, une clim
        // demandee pour un objectif ne doit pas rester pour le suivant.
        programKind: command.climate ? ProgramKind.chargeAndPreconditioning : ProgramKind.charge,
      );
      await vehicle.updateSchedule(vin, settings);

      final deadline = _clock().add(pollTimeout);
      var reread = await vehicle.fetchSchedule(vin);
      while (reread.lastUpdate == current.lastUpdate && _clock().isBefore(deadline)) {
        await Future<void>.delayed(pollInterval);
        reread = await vehicle.fetchSchedule(vin);
      }

      final applied = reread.lastUpdate != current.lastUpdate &&
          reread.chargeWindowStart == command.chargeTimeStart.format() &&
          reread.chargeWindowDurationMinutes == command.durationMinutes;
      if (!applied) {
        return await _fail(state, command, 'Envoyé, mais la voiture n\'a pas confirmé la nouvelle plage après '
            '${pollTimeout.inSeconds} s. Vérifiez dans l\'app.');
      }

      final programs = reread.programs;
      final climateApplied = programIndex >= programs.length ||
          programs[programIndex].kind.includesClimate == command.climate;
      final body = 'Plage appliquée : ${_window(command)}'
          '${command.defaultReadyAt ? '' : ', prête à ${_hm(command.readyAt)}'}'
          '${command.climate && climateApplied ? ', habitacle climatisé${_temperature(command)}' : ''}.'
          '${climateApplied ? '' : ' La voiture n\'a pas retenu la climatisation.'}';
      await platform.showResult('Plage envoyée', body);
      return _withResult(
        state.copyWith(sent: CommandMark.of(command, config.fingerprint), clearPending: true, clearConfirmed: true),
        body,
        ok: true,
      );
    } catch (error) {
      return _fail(state, command, 'Échec de l\'envoi : $error');
    }
  }

  Future<PilotState> _fail(PilotState state, ChargeCommand command, String message) async {
    await platform.showResult('Plage non envoyée', message);
    // La commande reste "a faire" : un prochain passage (ouverture de l'app,
    // reveil suivant) pourra la reproposer.
    return _withResult(state.copyWith(clearPending: true, clearConfirmed: true), message, ok: false);
  }

  PilotState _withResult(PilotState state, String message, {required bool ok}) =>
      state.copyWith(lastResult: message, lastResultOk: ok, lastResultAt: _clock());

  Future<PilotVehicleGateway?> _safeGateway() async {
    try {
      return await gateway();
    } catch (_) {
      return null;
    }
  }

  Future<int?> _safeSoc(PilotVehicleGateway vehicle, String vin) async {
    try {
      return await vehicle.fetchSoc(vin);
    } catch (_) {
      return null;
    }
  }

  // --- Textes (sans intl : les reveils tournent dans un isolate sans locale
  // initialisee) ------------------------------------------------------------

  /// Texte de la notification de confirmation.
  String describe(ChargeCommand command) {
    final now = _clock();
    final target = command.target;
    return [
      'Plage ${_window(command)}',
      if (!command.defaultReadyAt)
        'Prête ${_dayWord(command.readyAt, now)} à ${_hm(command.readyAt)}'
            '${target != null ? ' (objectif ${target.targetPercent} %)' : ''}'
            '${command.climate ? ', habitacle climatisé${_temperature(command)}' : ''}',
      if (command.extendedMinutes > 0) 'Élargie de ${command.extendedMinutes} min hors heures creuses',
      if (command.note != null) command.note!,
    ].join('\n');
  }

  String _window(ChargeCommand command) => command.durationMinutes >= 1440
      ? '00:00 → 00:00 (24 h)'
      : '${_hm(command.windowStart)} → ${_hm(command.windowEnd)}';

  static String _temperature(ChargeCommand command) =>
      command.climateTemperature != null ? ' à ${command.climateTemperature} °C' : '';

  static String _hm(DateTime d) => ClockTime.hm(d.hour, d.minute).format();

  static String _dayWord(DateTime d, DateTime now) {
    final days = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inHours / 24;
    return switch (days.round()) {
      0 => 'aujourd\'hui',
      1 => 'demain',
      _ => 'le ${d.day}/${d.month}',
    };
  }

  DateTime _nextEvening(DateTime now) {
    final today = eveningTime.onDay(now);
    return today.isAfter(now) ? today : eveningTime.onDay(DateTime(now.year, now.month, now.day + 1));
  }
}
