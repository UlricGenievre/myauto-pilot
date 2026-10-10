import '../models/battery_status.dart';
import '../models/charge_plan_config.dart';
import '../models/vehicle_schedule.dart';
import 'charge_planner.dart';
import 'pilot_state.dart';

/// Acces au vehicule depuis un reveil (sans interface, donc sans les
/// providers Riverpod) : construit a partir de la session stockee.
abstract interface class PilotVehicleGateway {
  Future<BatteryStatus> fetchBattery(String vin);
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

  /// Batterie sous la charge minimale : propose une charge immediate
  /// (actions Declencher/Ignorer).
  Future<void> showMinimumProposal(String body);
  Future<void> dismissMinimumProposal();
}

enum PilotWake {
  /// Heure d'envoi de la prochaine commande.
  next(1),

  /// Envoi d'une commande confirmee depuis la notification.
  execute(2),

  /// Rappel du soir.
  evening(3),

  /// Fin (ou arret demande) d'une charge immediate : renvoi de la plage
  /// qu'elle a remplacee.
  boostEnd(4);

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

    // Modele sur lequel l'app ne doit pas ecrire, ou pilotage coupe. Une
    // charge immediate demandee depuis l'app ne depend pas du pilotage : elle
    // va a son terme, puis les reglages d'avant sont remis.
    final writable = vin != null && config.vehicleSupport.canWrite;
    if (!config.enabled || !writable) {
      await platform.cancelWake(PilotWake.next);
      await platform.cancelWake(PilotWake.evening);
      if (state.manualChargeTarget == null || !writable) await platform.cancelWake(PilotWake.execute);
      await platform.dismissConfirmation();
      await platform.dismissMinimumProposal();
      state = state.copyWith(
        clearPending: true,
        clearConfirmed: true,
        clearNextWake: true,
        boostProposed: false,
        boostConfirmed: false,
        boostDismissed: false,
        clearManualChargeTarget: !writable,
      );
      final now = _clock();
      if (writable && state.boost != null) {
        if (!state.boost!.activeAt(now)) {
          state = await _finishImmediate(config, state, null, await _safeGateway(), now);
        } else {
          await platform.scheduleWake(PilotWake.boostEnd, state.boost!.end);
        }
      } else {
        await platform.cancelWake(PilotWake.boostEnd);
        state = state.copyWith(clearBoost: true);
      }
      await store.saveState(state);
      return;
    }

    final vehicle = await _safeGateway();
    final battery = vehicle == null ? null : await _safeBattery(vehicle, vin);
    final soc = battery?.batteryLevel;
    final now = _clock();
    final planner = ChargePlanner(config);
    final command = planner.commandInForce(now, socPercent: soc);

    final finished = state.boost;
    if (finished != null && !finished.activeAt(now)) {
      state = await _finishImmediate(config, state, command, vehicle, now);
    }
    final boost = state.boost;

    // Une commande deja envoyee (ou ignoree) est reproposee si le
    // parametrage a change depuis et que son contenu differe (ex. objectif
    // supprime apres l'envoi d'une plage elargie pour lui).
    final fingerprint = config.fingerprint;
    final alreadySent = command != null && (state.sent?.covers(command, fingerprint) ?? false);
    final ignored = command != null && (state.ignored?.covers(command, fingerprint) ?? false);
    if (command != null && !alreadySent && !ignored) {
      if (boost != null && !command.pushAt.isAfter(boost.sentAt)) {
        // Remplacee par la charge immediate en cours : renvoyee a sa fin. Une
        // plage dont l'envoi tombe pendant la charge part normalement.
      } else if (!config.effectiveSafeMode) {
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
    if (state.boost case final active? when !active.merged && active.activeAt(now)) {
      await platform.scheduleWake(PilotWake.boostEnd, active.end);
    }

    state = await _updateMinimumProposal(config, state, battery, now);
    await store.saveState(state);
  }

  // --- Charge immediate ---------------------------------------------------------

  /// Charge immediate terminee (ou arretee) : remettre dans la voiture ce
  /// qu'elle a remplace, sans confirmation (le telephone peut etre en mode
  /// nuit). Pilotage actif : la plage en vigueur si c'est la meme, sinon
  /// celle d'avant telle quelle ; rien si la plage en vigueur n'a pas encore
  /// ete envoyee (elle part juste apres). Pilotage coupe, ou rien a
  /// renvoyer : les reglages de la voiture d'avant la charge.
  Future<PilotState> _finishImmediate(
    ChargePlanConfig config,
    PilotState state,
    ChargeCommand? command,
    PilotVehicleGateway? vehicle,
    DateTime now,
  ) async {
    final finished = state.boost!;
    // Un autre envoi est en cours : reessayer un peu plus tard plutot que
    // perdre ce qu'il faut remettre.
    final since = (await store.loadState()).sendingSince;
    if (since != null && _clock().difference(since) < sendLockTimeout) {
      await platform.scheduleWake(PilotWake.boostEnd, _clock().add(const Duration(minutes: 1)));
      return state;
    }
    state = state.copyWith(clearBoost: true);
    await platform.cancelWake(PilotWake.boostEnd);
    if (finished.merged) return state;
    final displaced = finished.displaced;
    if (config.enabled && displaced != null) {
      final restore =
          command != null && displaced.covers(command, config.fingerprint) ? command : displaced.toCommand(now);
      if (restore != null) {
        return _send(config, state, restore, vehicle, title: 'Plage d\'heures creuses renvoyée');
      }
    }
    if (config.enabled && command != null) return state;
    final previous = finished.previous;
    if (previous == null) return state;
    return _locked(state, () => _restorePrevious(config, state, previous, vehicle));
  }

  /// Charge immediate jusqu'a [targetPercent] a lancer maintenant, ou null :
  /// batterie inconnue ou deja a ce niveau, voiture debranchee, capacite ou
  /// puissance inconnue, pas de programme dedie. Prolongee jusqu'a la plage
  /// d'heures creuses qu'elle atteint seulement si le pilotage est actif.
  ImmediateChargePlan? _immediateOffer(ChargePlanConfig config, BatteryStatus? battery, DateTime now, int targetPercent) {
    final soc = battery?.batteryLevel;
    if (soc == null || battery!.plugState != PlugState.plugged || config.dedicatedProgramIndex == null) return null;
    return ChargePlanner(config)
        .immediateCharge(now, socPercent: soc, targetPercent: targetPercent, mergeWithWindows: config.enabled);
  }

  /// Charge immediate jusqu'au minimum a proposer maintenant, ou null :
  /// pas de minimum, voiture deja en charge ou charge immediate deja en
  /// cours (et cf. [_immediateOffer]).
  ImmediateChargePlan? _minimumOffer(ChargePlanConfig config, PilotState state, BatteryStatus? battery, DateTime now) {
    final min = config.minChargePercent;
    if (min == null || battery?.isCharging == true || (state.boost?.activeAt(now) ?? false)) return null;
    return _immediateOffer(config, battery, now, min);
  }

  Future<PilotState> _updateMinimumProposal(
    ChargePlanConfig config,
    PilotState state,
    BatteryStatus? battery,
    DateTime now,
  ) async {
    if (battery == null) return state;
    final min = config.minChargePercent;
    final soc = battery.batteryLevel;
    // Refus valable jusqu'a ce que la batterie remonte ou que la voiture
    // soit debranchee.
    if (state.boostDismissed &&
        (min == null || (soc != null && soc >= min) || battery.plugState == PlugState.unplugged)) {
      state = state.copyWith(boostDismissed: false);
    }
    final offer = state.boostDismissed || state.boostConfirmed ? null : _minimumOffer(config, state, battery, now);
    if (offer != null) {
      if (!state.boostProposed) {
        await platform.showMinimumProposal(describeMinimum(config, state, offer, soc!));
        state = state.copyWith(boostProposed: true);
      }
    } else if (state.boostProposed) {
      await platform.dismissMinimumProposal();
      state = state.copyWith(boostProposed: false);
    }
    return state;
  }

  /// Bouton "Charger maintenant" de l'app : charge immediate jusqu'a
  /// [targetPercent], pilotage actif ou non, sans confirmation (l'appui en
  /// est une). Comme [confirm], l'envoi est fait par le reveil "execution".
  Future<void> startImmediateCharge(int targetPercent) async {
    final state = await store.loadState();
    await store.saveState(state.copyWith(manualChargeTarget: targetPercent));
    await platform.scheduleWake(PilotWake.execute, _clock().add(const Duration(seconds: 2)));
  }

  /// Bouton "Arreter" : la charge immediate en cours se termine maintenant,
  /// et ce qu'elle a remplace est renvoye par le reveil de fin. Prolongee
  /// jusqu'a la fin d'une plage d'heures creuses, c'est cette plage qui est
  /// renvoyee.
  Future<void> stopImmediateCharge() async {
    final state = await store.loadState();
    final boost = state.boost;
    final now = _clock();
    if (boost == null || !boost.activeAt(now)) return;
    final stopped = boost.merged ? boost.copyWith(end: now, displaced: state.sent, merged: false) : boost.copyWith(end: now);
    await store.saveState(state.copyWith(boost: stopped, clearManualChargeTarget: true));
    await platform.scheduleWake(PilotWake.boostEnd, now.add(const Duration(seconds: 2)));
  }

  /// Action "Declencher" (notification ou app) : comme [confirm], l'envoi
  /// est fait par le reveil "execution".
  Future<void> confirmMinimum() async {
    final state = await store.loadState();
    await store.saveState(state.copyWith(boostConfirmed: true, boostProposed: false));
    await platform.dismissMinimumProposal();
    await platform.scheduleWake(PilotWake.execute, _clock().add(const Duration(seconds: 2)));
  }

  /// Action "Ignorer" de la proposition de charge immediate.
  Future<void> ignoreMinimum() async {
    final state = await store.loadState();
    await store.saveState(state.copyWith(boostDismissed: true, boostProposed: false, boostConfirmed: false));
    await platform.dismissMinimumProposal();
  }

  /// Reveil "execution" : envoie la charge immediate demandee depuis l'app
  /// ou acceptee (minimum), recalculee avec le niveau du moment.
  Future<void> executeImmediate() async {
    final config = await store.load();
    var state = await store.loadState();
    final vin = config.vehicleVin;
    final manualTarget = state.manualChargeTarget;
    if (manualTarget == null && !state.boostConfirmed) return;
    final minimum = manualTarget == null ? config.minChargePercent : null;
    if (vin == null || !config.vehicleSupport.canWrite || (manualTarget == null && (!config.enabled || minimum == null))) {
      await store.saveState(state.copyWith(boostConfirmed: false, clearManualChargeTarget: true));
      return;
    }
    final since = state.sendingSince;
    if (since != null && _clock().difference(since) < sendLockTimeout) {
      await platform.scheduleWake(PilotWake.execute, _clock().add(const Duration(minutes: 1)));
      return;
    }

    state = state.copyWith(boostConfirmed: false, clearManualChargeTarget: true);
    final vehicle = await _safeGateway();
    final battery = vehicle == null ? null : await _safeBattery(vehicle, vin);
    final now = _clock();
    final target = manualTarget ?? minimum!;
    final plan = manualTarget != null
        ? _immediateOffer(config, battery, now, manualTarget)
        : _minimumOffer(config, state, battery, now);
    // Reglages a remettre a la fin : ceux d'avant une charge immediate deja
    // en cours (qu'elle remplace), sinon ceux lus maintenant.
    final active = state.boost != null && state.boost!.activeAt(now) ? state.boost : null;
    CarSettingsSnapshot? previous = active?.previous;
    if (plan != null && previous == null && vehicle != null) {
      try {
        previous = CarSettingsSnapshot.of(await vehicle.fetchSchedule(vin), config.dedicatedProgramIndex!);
      } catch (_) {
        previous = null;
      }
    }
    if (plan == null || (previous == null && !config.enabled)) {
      final reason = plan == null
          ? manualTarget != null
              ? 'voiture débranchée, batterie déjà à $target % ou plus, niveau illisible, capacité ou puissance '
                  'de charge inconnue, ou pas de programme dédié.'
              : 'batterie au-dessus du minimum, voiture débranchée, déjà en charge ou niveau illisible.'
          : 'réglages actuels de la voiture illisibles (ils n\'auraient pas pu être remis ensuite).';
      state = _withResult(state, 'Charge immédiate non lancée : $reason', ok: false);
      await platform.showResult('Charge immédiate non lancée', state.lastResult!);
      await store.saveState(state);
      return;
    }

    final command = plan.command;
    final merged = plan.mergedWith;
    // Plage a renvoyer a la fin (pilotage actif) : celle que la voiture avait
    // avant la charge immediate en cours, s'il y en a une.
    var displaced = active != null && !active.merged ? active.displaced : state.sent;
    if (!config.enabled || (displaced?.id.startsWith(ChargePlanner.immediateIdPrefix) ?? false)) displaced = null;
    final end = _hm(command.windowEnd);
    final body = 'Charge jusqu\'à $end pour atteindre $target %.'
        '${merged != null ? ' Prolongée jusqu\'à la fin de la plage d\'heures creuses.' : displaced != null ? ' La plage d\'heures creuses sera renvoyée à $end.' : !config.enabled ? ' Les réglages de charge d\'avant seront remis à $end.' : ''}';
    state = await _send(config, state, command, vehicle, title: 'Charge immédiate lancée', body: body);
    if (state.lastResultOk == true && state.sent?.id == command.id) {
      state = state.copyWith(
        boost: ImmediateCharge(
          sentAt: now,
          end: command.windowEnd,
          targetPercent: target,
          manual: manualTarget != null,
          displaced: merged == null ? displaced : null,
          merged: merged != null,
          previous: previous,
        ),
        // Plage atteinte par la charge immediate : deja dans la voiture.
        sent: merged != null ? CommandMark.of(merged, config.fingerprint) : null,
      );
      if (merged == null) {
        await platform.scheduleWake(PilotWake.boostEnd, command.windowEnd);
      } else {
        await platform.cancelWake(PilotWake.boostEnd);
      }
    }
    await store.saveState(state);
  }

  /// Texte de la proposition de charge immediate.
  String describeMinimum(ChargePlanConfig config, PilotState state, ImmediateChargePlan plan, int soc) {
    final end = _hm(plan.command.windowEnd);
    return [
      'Batterie à $soc %, voiture branchée. Déclencher la charge pour atteindre le seuil minimal de '
          '${config.minChargePercent} % ?',
      if (plan.mergedWith != null)
        'Charge immédiate, prolongée jusqu\'à la fin de la plage d\'heures creuses ($end).'
      else ...[
        'Charge immédiate jusqu\'à $end environ, en heures pleines.',
        if (state.sent != null) 'La plage d\'heures creuses sera ensuite renvoyée automatiquement.',
      ],
    ].join('\n');
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
    final soc = vehicle == null ? null : (await _safeBattery(vehicle, vin))?.batteryLevel;
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
    PilotVehicleGateway? vehicle, {
    String title = 'Plage envoyée',
    String? body,
  }) =>
      _locked(state, () => _sendUnlocked(config, state, command, vehicle, title: title, body: body));

  /// Execute [write] sous le verrou d'envoi (cf. [_send]).
  Future<PilotState> _locked(PilotState state, Future<PilotState> Function() write) async {
    // Relecture juste avant de verrouiller : l'etat [state] a pu etre lu
    // avant qu'un autre isolate ne pose son verrou.
    final fresh = await store.loadState();
    final since = fresh.sendingSince;
    if (since != null && _clock().difference(since) < sendLockTimeout) {
      // Garder le verrou de l'autre envoi dans ce que l'appelant sauvegardera.
      return state.copyWith(sendingSince: since);
    }
    await store.saveState(fresh.copyWith(sendingSince: _clock()));
    final result = await write();
    return result.copyWith(clearSending: true);
  }

  /// Poste [settings] puis relit jusqu'a voir l'ecriture appliquee ; null
  /// si elle ne l'est pas apres [pollTimeout].
  Future<VehicleSchedule?> _writeAndWait(
    PilotVehicleGateway vehicle,
    String vin,
    VehicleSchedule current,
    Map<String, dynamic> settings,
  ) async {
    await vehicle.updateSchedule(vin, settings);
    final deadline = _clock().add(pollTimeout);
    var reread = await vehicle.fetchSchedule(vin);
    while (reread.lastUpdate == current.lastUpdate && _clock().isBefore(deadline)) {
      await Future<void>.delayed(pollInterval);
      reread = await vehicle.fetchSchedule(vin);
    }
    return reread.lastUpdate != current.lastUpdate ? reread : null;
  }

  /// Remet les reglages de la voiture d'avant une charge immediate.
  Future<PilotState> _restorePrevious(
    ChargePlanConfig config,
    PilotState state,
    CarSettingsSnapshot previous,
    PilotVehicleGateway? vehicle,
  ) async {
    const failTitle = 'Réglages de charge non remis';
    Future<PilotState> fail(String message) async {
      await platform.showResult(failTitle, message);
      return _withResult(state, message, ok: false);
    }

    if (vehicle == null) return fail('Session expirée : ouvrez l\'app pour vous reconnecter.');
    try {
      final vin = config.vehicleVin!;
      final current = await vehicle.fetchSchedule(vin);
      final reread = await _writeAndWait(vehicle, vin, current, previous.applyTo(current));
      if (reread == null ||
          reread.chargeWindowStart != previous.chargeTimeStart ||
          reread.chargeWindowDurationMinutes != previous.durationMinutes) {
        return await fail('Envoyés, mais la voiture n\'a pas confirmé les réglages d\'avant la charge immédiate après '
            '${pollTimeout.inSeconds} s. Vérifiez dans l\'app.');
      }
      final message = 'Charge immédiate terminée : réglages d\'avant remis (plage ${previous.chargeTimeStart}, '
          '${_duration(previous.durationMinutes)}).';
      await platform.showResult('Charge immédiate terminée', message);
      return _withResult(state, message, ok: true);
    } catch (error) {
      return fail('Échec de la remise des réglages d\'avant la charge immédiate : $error');
    }
  }

  static String _duration(int minutes) =>
      minutes % 60 == 0 ? '${minutes ~/ 60} h' : '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';

  Future<PilotState> _sendUnlocked(
    ChargePlanConfig config,
    PilotState state,
    ChargeCommand command,
    PilotVehicleGateway? vehicle, {
    required String title,
    String? body,
  }) async {
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
      final reread = await _writeAndWait(vehicle, vin, current, settings);
      if (reread == null ||
          reread.chargeWindowStart != command.chargeTimeStart.format() ||
          reread.chargeWindowDurationMinutes != command.durationMinutes) {
        return await _fail(state, command, 'Envoyé, mais la voiture n\'a pas confirmé la nouvelle plage après '
            '${pollTimeout.inSeconds} s. Vérifiez dans l\'app.');
      }

      final programs = reread.programs;
      final climateApplied = programIndex >= programs.length ||
          programs[programIndex].kind.includesClimate == command.climate;
      final message = '${body ?? 'Plage appliquée : ${_window(command)}'
              '${command.defaultReadyAt ? '' : ', prête à ${_hm(command.readyAt)}'}'
              '${command.climate && climateApplied ? ', habitacle climatisé${_temperature(command)}' : ''}.'}'
          '${climateApplied ? '' : ' La voiture n\'a pas retenu la climatisation.'}';
      await platform.showResult(title, message);
      var next =
          state.copyWith(sent: CommandMark.of(command, config.fingerprint), clearPending: true, clearConfirmed: true);
      if (command.kind != ChargeCommandKind.immediateCharge && next.boost != null) {
        // La plage envoyee remplace la charge immediate en cours.
        next = next.copyWith(clearBoost: true);
        await platform.cancelWake(PilotWake.boostEnd);
      }
      return _withResult(next, message, ok: true);
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

  Future<BatteryStatus?> _safeBattery(PilotVehicleGateway vehicle, String vin) async {
    try {
      return await vehicle.fetchBattery(vin);
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
