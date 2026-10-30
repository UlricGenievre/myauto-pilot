# Tests

Catalogue des tests de `test/` : contexte, action et résultat attendu. À
mettre à jour à chaque ajout, modification ou suppression de test.

Lancer : `./scripts/flutter.sh test` (la CI lance aussi
`./scripts/flutter.sh analyze --fatal-infos`).

Dates de référence : semaine du lundi 21 au dimanche 27 septembre 2026.
Sauf mention contraire, l'envoi d'une plage se fait 4 h avant son début.

## 1. Calcul des plages : `charge_planner_test.dart`

Logique pure (`ChargePlanner`) : quelle commande envoyer, quand, avec
quelle plage et quelle heure « prête à ».

**Paramétrage de base**
- Plages HC du mardi au vendredi : 01:00-07:00 et 13:00-16:00.
- Samedi, dimanche et lundi entièrement en HC, fusionnés en un seul bloc.
- Batterie de 52 kWh, charge à 7,4 kW (1 % ≈ 4,2 min).
- Un seul agenda, « Habituel ».
- Pas d'objectif, sauf mention contraire.

### Utilitaires

| Test | Résultat attendu |
|---|---|
| `ClockTime` : parse « HH:MM » et « HH:MM:SS » | 07:45 → 465 min, 09:00:00 → 540 min, 25:00 refusé |
| JSON du paramétrage : aller-retour | Objectifs, objectif ponctuel et programme dédié conservés sans perte |

### Occurrences

| Contexte | Action | Résultat attendu |
|---|---|---|
| Du sam 26 00:00 au mar 29 | `occurrences` | Un seul bloc HC, du sam 00:00 au mar 00:00 |
| Vendredi : plage 22:00-00:00 collée au bloc du week-end | `occurrences` | Plage absorbée dans le bloc (`leadInStart` = ven 22:00) |

### Commandes

| Contexte (heure courante) | Action | Résultat attendu |
|---|---|---|
| Mar 22 09:30 | `commandInForce` | Plage 13:00 de 180 min, envoi à 09:00. « Prête à » par défaut : lun 21 12:00, programme actif ce seul jour |
| Mercredi : 01:00-07:00 puis 09:00-11:00 | `commands` | 2ᵉ plage envoyée à 07:00, à la fin de la 1ʳᵉ, pour ne pas remplacer une plage en cours |
| Ven 25 18:00, veille du bloc HC | `upcomingCommand` | `allDayMorning` : envoi à 20:00, plage sam 00:00 de 720 min, « prête à » jeu 12:00 |
| Sam 26 10:05, dans le bloc | `commandInForce` | `allDayFull` : envoi à 10:00, 00:00 + 1440 min, « prête à » ven 12:00. La même commande reste en vigueur dimanche et lundi |
| Lun 28 18:00, sortie du bloc | `upcomingCommand` | Envoi lun 21:00 pour mar 01:00-07:00, plage non avancée |
| Lun 28 18:00, objectif mar 07:00 à 100 %, SOC 10 % | `upcomingCommand` | Envoi lun 21:00, début avancé à 00:15 (+45 min), fin 07:00 |
| Mar 22 20:00, objectif mer 80 % à 07:30, SOC 40 % | `upcomingCommand` | Plage 01:00 non élargie, « prête à » mer 07:30, objectif 80 % |
| Mar 22 20:00, objectif mer 100 % à 07:15, SOC 10 % | `upcomingCommand` | 401 min pour 360 de plage : fin prolongée à 07:15, début avancé à 00:30 (+45 min), pas de note |
| Mar 22 20:00, agenda 60 % à 09:00 et objectif ponctuel mer 100 % à 07:00, SOC 50 % | `upcomingCommand` | Objectif ponctuel prioritaire, « prête à » mer 07:00 |
| Mar 22 20:00, objectif mer 18:00, SOC 70 % | `upcomingCommand` | Objectif tenu par la plage de 13:00 : la plage de nuit garde le « prête à » par défaut (lun 12:00) |
| Capacité inconnue, objectif mer 100 % à 07:15, SOC 10 % | `upcomingCommand` | Pas d'élargissement, note explicative |
| Envoi réglé à 2 h, mar 10:30 | `upcomingCommand` | Plage 13:00, envoi à 11:00 |
| Plage unique jeudi 01:15-06:15, mer 18:00 | `upcomingCommand` | Envoi mer 21:15, « prête à » mar 12:00 (jour 2) |
| Envoi réglé à 90 min, ven 18:00 | `upcomingCommand` | `allDayMorning` envoyé à 22:30 |
| Objectif mer 07:00 : 95 % depuis 15 %, 100 % depuis 15 %, 100 % depuis 97 % | `upcomingCommand` | Seule la tranche au-dessus de 95 % compte double : non élargie, élargie, non élargie |
| Calendrier vide | `upcoming`/`inForce` | Aucune commande |

### Entre deux plages

À mar 22 07:30, la plage de nuit (01:00-07:00) est terminée, mais elle
reste en vigueur jusqu'à l'envoi de la suivante. La plage 13:00-16:00 n'est
pas encore envoyée (envoi à 09:00).

| Paramétrage | Action | Résultat attendu |
|---|---|---|
| Objectif mar 80 % à 14:00, SOC 40 % | `commandInForce` / `upcomingCommand` | Plage de nuit inchangée : même contenu que sans objectif. La plage 13:00 commence à 11:00 (169 min pour 60 min de plage avant 14:00), envoi toujours à 09:00 |
| Objectif mar 80 % à 11:00, avant la plage suivante, SOC 50 % | `commandInForce` | Plage de nuit prolongée **depuis maintenant** : 01:00 → 09:45 (+135 min), « prête à » 11:00, objectif ponctuel |
| Objectif déjà passé (mar 06:00) | `commandInForce` | Ignoré, contenu inchangé |
| Plage en cours (mer 03:00), objectif mer 07:00 à 100 %, SOC 40 % | `commandInForce` | Temps déjà passé non compté : 275 min pour 240 restantes. Début non avancé, fin 07:00 (l'échéance), note « inatteignable » |

### Objectif pendant un bloc HC complet

Bloc du sam 26 00:00 au mar 29 00:00, sans charge maximale. La plage 24 h
est envoyée sam 10:00. La plage de sortie (mar 01:00-07:00) est envoyée lun
21:00.

| Contexte | Action | Résultat attendu |
|---|---|---|
| Dim 15:00, objectif lun 08:00 à 80 % climatisé, SOC 40 % | `commandInForce` | Plage 24 h du dimanche (`allday-full-20260927T0000`) envoyée dim 10:00 : 00:00 + 1440 min, « prête à » lun 08:00, programme actif le lundi, climatisation |
| Sam 15:00, objectif dim 08:00 à 80 % | `commandInForce` | Tenu par la plage 24 h du samedi (« prête à » dim 08:00), qui reste en vigueur jusqu'au lundi |
| Agenda : sam 80 % à 18:00, lun 90 % à 08:00 | `commands` | Une plage 24 h par jour qui porte un objectif : samedi (« prête à » sam 18:00) et dimanche (« prête à » lun 08:00, 1440 min) |
| Lun 22:00, après l'envoi de sortie, objectif mar 07:00 à 100 %, SOC 10 % | `commandInForce` | Plage de sortie recalculée : 00:15-07:00, envoi lun 21:00 (donc tout de suite), « prête à » mar 07:00 |
| Lun 22:00, objectif lun 23:30 (fin du bloc) climatisé | `commandInForce` | Tenu par la plage de sortie. SOC 85 % : plage inchangée (01:00), « prête à » lun 23:30, climatisation. SOC 40 % : 169 min nécessaires, début avancé au plus à 21:00, soit 150 min utiles avant 23:30, note « inatteignable » |

### Charge maximale

Calcul fait le mar 22 à 10:00, sur la plage de mercredi 01:00.

| Paramétrage / SOC | Résultat attendu |
|---|---|
| Maximum 80 %, SOC 60 % | Plage raccourcie : 01:00 + 85 min, `maxPercent` 80, note « 80 % » |
| Maximum 80 %, SOC 85 % | Plage de 5 min terminée à l'envoi (20:55 + 5 min), `maxReached`, jamais considérée comme terminée (`endedAt`) : envoyée quand même |
| Maximum 80 %, objectif mer 90 % à 07:30 (servi par la plage), SOC 60 % | L'objectif passe outre : 130 min, `maxPercent` 90. À 100 % : plage complète (360 min), `maxPercent` nul |
| Maximum 80 %, objectif jeu 90 % à 07:30 (servi plus tard), SOC 60 % | Maximum appliqué : 85 min |
| Maximum 80 %, SOC inconnu | Plage complète, note « Charge maximale non appliquée » |
| Bloc HC, SOC 70 %, ven 10:00 | Sans maximum : un seul `allDayFull` (samedi). Avec maximum 80 % : un envoi par jour à 10:00, celui de dimanche de 45 min à partir de 10:00 |

### Charge minimale et charge immédiate

Batterie de 52 kWh à 7,4 kW.

| Contexte | Résultat attendu |
|---|---|
| Minimum 35 %, mar 20:00, SOC 18 % | Charge immédiate de 19:55 à 21:15, non fusionnée, « prête à » par défaut |
| Minimum 35 %, mar 12:00, SOC 18 % | Atteint la plage de 13:00 : prolongée jusqu'à 16:00 (de 11:55 à 16:00) |
| Idem, maximum 50 % | Prolongée, mais arrêtée à 14:15 |
| SOC déjà au minimum, sans minimum, ou capacité inconnue | Rien |
| Charge immédiate jusqu'à 80 % malgré un maximum de 60 %, mar 20:00, SOC 50 % | De 19:55 à 22:10 |
| Pilotage coupé, 12:00, SOC 18 % → 35 % | Jamais fusionnée avec une plage de l'app : fin 13:15 |
| Cible déjà atteinte | Rien |

## 2. Pilote de bout en bout : `charge_pilot_test.dart`

`ChargePilot`, avec une voiture, un stockage et une plateforme simulés
(réveils, notifications).

**Paramétrage de base**
- Plages HC du mardi au vendredi : 01:15-06:15 et 14:05-17:05.
- Programme dédié n° 0, modèle `XHN1CP`, mode sécurisé sauf mention contraire.
- Voiture simulée branchée, SOC 50 %. Une écriture n'est visible qu'après une relecture.

### Cycle d'envoi

| Contexte | Action | Résultat attendu |
|---|---|---|
| Mar 10:30, mode sécurisé, rien envoyé | 2 × `tick` | Une seule proposition (14:05), aucune écriture. Réveils à 21:15 (prochain envoi) et 20:00 (soir) |
| Idem, écriture prise en compte après 2 relectures | `confirm` puis `executeConfirmed` | Écriture 14:05 / 180 min, « prête à » 12:00 actif le lundi seulement. Résultat « Plage envoyée », sans heure « prête à ». Un nouveau `tick` ne repropose rien |
| Idem | `ignore` puis `tick` | Plus reproposée |
| Texte de confirmation | `describe` | « Prête demain à 07:15 » seulement avec un objectif |
| Confirmée à 10:30, exécutée à 21:30 | `executeConfirmed` | « Plage expirée », rien envoyé |
| Mar 12:00, mode automatique | `tick` | Envoi direct (rattrapage) |
| Écriture refusée (403) | `executeConfirmed` puis `tick` | Résultat en erreur, plage reproposée |
| Écriture jamais appliquée | `tick` | Échec après le délai d'attente |
| Pilotage désactivé | `tick` | Réveils annulés |
| Session absente | `tick` | « Session expirée », rien envoyé |
| Envoi prévu à 21:15, fait à 22:40 | `tick` | `sentAt` = 22:40, conservé en JSON |

### Plage terminée sans avoir été envoyée

Plage de nuit 01:15-06:15 à envoyer lun 21:15, encore en vigueur mar matin
jusqu'à l'envoi de 10:05.

| Contexte | Action | Résultat attendu |
|---|---|---|
| Proposée lun 21:15, sans réponse (mode sécurisé) | `tick` mar 08:00 | Proposition retirée, rien de reproposé ni envoyé. Prochain réveil 10:05 |
| Écriture refusée lun 21:15 (mode automatique) | `tick` mar 08:00 | Pas d'envoi |
| Proposée lun 21:15 | `confirm` et `executeConfirmed` mar 07:00 | « Plage expirée », rien envoyé |

### Paramétrage modifié après un envoi

Objectif exceptionnel mer 07:15 à 100 %, SOC 10 %, mar 22:00 : la plage de
nuit est en vigueur et pas encore commencée.

| Action | Résultat attendu |
|---|---|
| Mode auto : envoi, puis objectif supprimé | 1ᵉʳ envoi élargi (00:30), puis renvoi 01:15 / 300 min |
| Mode sécurisé : envoi confirmé, puis objectif supprimé | Résultat « prête à 07:15 », puis nouvelle proposition et aucune écriture |
| SOC qui passe de 10 à 40 % (mer 02:00) | Pas de renvoi en pleine charge |
| Paramétrage modifié avant la confirmation | Proposition mise à jour, sans doublon |
| Plage ignorée, puis paramétrage modifié | Reproposée |

### Objectif ajouté entre deux plages

Plage de nuit (01:15-06:15) envoyée lun 21:20, terminée mar 06:15. La
plage de 14:05 est à envoyer à 10:05. Objectif exceptionnel ajouté mar 06:30.

| Paramétrage | Action | Résultat attendu |
|---|---|---|
| Mode auto, objectif mar 15:00 à 100 %, SOC 10 % | `tick` à 06:30, puis à 08:05 | 06:30 : rien renvoyé, réveil à 08:05. 08:05 : plage 14:05 avancée, envoyée en 08:05 / 540 min |
| Mode sécurisé, même objectif | `tick` à 06:30 | Aucune nouvelle proposition pour la plage terminée |
| Mode auto, objectif mar 12:00 à 80 % (avant la plage suivante), SOC 50 % | `tick` à 06:30 | Plage terminée renvoyée, prolongée depuis maintenant : 01:15 / 450 min (jusqu'à 08:45), « prête à » 12:00 actif le mardi |

### Objectif ajouté pendant un bloc HC complet

Samedi, dimanche et lundi entièrement en HC, mode auto. La plage 24 h est
envoyée sam 10:05.

| Paramétrage | Action | Résultat attendu |
|---|---|---|
| Objectif lun 08:00 à 80 % climatisé à 20 °C, ajouté dim 15:00 | `tick` à dim 15:00 | Plage 24 h renvoyée : 00:00 / 1440 min, `CHARGE_AND_PRECONDITIONING` au départ 08:00:00, actif le lundi. Commande `allday-full-20260927T0000` comptée comme envoyée |

### Un seul envoi à la fois

| Contexte | Résultat attendu |
|---|---|
| « Recalculer » (`tick`) entre la confirmation et le réveil d'envoi | Pas de double écriture, verrou libéré après l'envoi |
| Verrou d'envoi tenu depuis 1 min, mode auto | Pas d'envoi, verrou conservé |
| Verrou orphelin (plus de 3 min) | Ignoré, envoi fait |
| Réveil d'envoi pendant un autre envoi | Reprogrammé 1 min plus tard, confirmation gardée |

### Ce qui est confirmé est exactement ce qui est envoyé

Objectif mer 07:15 à 100 %, SOC 10 %, mar 22:00.

| Action | Résultat attendu |
|---|---|
| Confirmée, puis SOC à 60 % avant l'envoi | Contenu confirmé envoyé tel quel (00:30) |
| Confirmée, puis paramétrage modifié | Rien envoyé, confirmation annulée, nouvelle proposition |
| Mode sécurisé, passages à 10:30, 21:30, 02:00, 12:00 et modification | Aucune écriture |

### Modèles de véhicule

| Contexte | Résultat attendu |
|---|---|
| `VehicleSupport.of` | `XHN1CP` vérifié, `R5E1VE` compatible, `X102VE` (Zoe phase 2) et inconnu non pris en charge |
| Modèle non pris en charge, mode auto | Aucune écriture ni proposition, réveils annulés |
| Modèle compatible non vérifié, mode auto | Mode sécurisé imposé : proposition, pas d'écriture |

### Climatisation

Objectif exceptionnel mer 07:15 à 80 %, mode auto, mar 22:00.

| Contexte | Résultat attendu |
|---|---|
| Objectif climatisé | Programme `CHARGE_AND_PRECONDITIONING`, départ 07:15:00, résultat « habitacle climatisé » |
| Température 19 °C | `preconditioningTemperature` 19, résultat « à 19 °C » |
| Température passée à 23 °C après l'envoi | Renvoi avec 23 |
| Sans climatisation | Programme `CHARGE`, température de la voiture (21) non touchée |
| Climatisation ajoutée après l'envoi | Renvoi en `CHARGE_AND_PRECONDITIONING` |
| Mode sécurisé, proposition confirmée | Climatisation incluse dans le contenu envoyé |
| JSON d'un objectif sans climatisation | Pas de clés `climate`/`climateTemperature` (empreinte inchangée), relues si présentes |

### Charge minimale

Minimum 35 %, 52 kWh, 7,4 kW, mode auto.

| Contexte | Résultat attendu |
|---|---|
| SOC 18 %, mar 21:20 | Plage de nuit envoyée, minimum proposé une fois. Confirmé à 21:30 : charge 21:25 / 80 min, fin 22:45. Pas de renvoi pendant la charge ; à 22:46, renvoi 01:15 / 300 min |
| Mode sécurisé, plage de nuit déjà envoyée | Renvoi en fin de charge sans confirmation |
| SOC 18 %, mar 13:00 | Atteint la plage de 14:05 : 12:55 / 250 min (jusqu'à 17:05), plage comptée comme envoyée, pas de réveil de fin. Rien renvoyé à 17:10 |
| SOC 10 %, charge lancée à 20:00 (fin 21:50) | L'envoi de 21:15 part quand même et met fin à la charge immédiate |
| Voiture débranchée, puis en charge | Pas de proposition. Refus retenu jusqu'à un débranchement suivi d'un rebranchement |

### Charge immédiate à la demande

52 kWh, 7,4 kW, mode auto.

| Contexte | Résultat attendu |
|---|---|
| Pilotage coupé (mode sécurisé), SOC 50 % → 80 %, 21:30 | Sans confirmation, demande conservée au `tick`. Envoi 21:25 / 135 min, fin 23:40. À 23:41, réglages d'avant remis (00:00 / 1440, départ 09:00:00 actif le dimanche) |
| Pilotage actif, plage de nuit envoyée | À la fin, plage 01:15 / 300 min renvoyée |
| Arrêtée à 22:00 | Fin reprogrammée tout de suite, plage de nuit renvoyée |
| Arrêtée alors que prolongée jusqu'à la plage de 14:05 | Plage 14:05 / 180 min renvoyée |
| Remplace une charge jusqu'au minimum en cours (18 % → 40 %) | Fin 23:15, plage de nuit à renvoyer gardée, réglages d'avant ceux de la 1ʳᵉ charge (01:15) |
| Voiture débranchée | Rien envoyé, « Charge immédiate non lancée » |

### Modifications faites depuis MyRenault

| Contexte | Résultat attendu |
|---|---|
| Plage envoyée, puis modifiée dans MyRenault (23:00 / 420 min) | Rien renvoyé de lui-même. « Renvoyer » : envoi au réveil (pas au `tick`), contenu envoyé à l'identique (01:15 / 300 min) |
| Charge immédiate modifiée dans MyRenault, pilotage actif | Abandonnée sans rien renvoyer, la plage remplacée compte comme envoyée, résultat « modifiée hors app » |
| Idem, pilotage coupé | Réglages d'avant non remis, la modification reste |

## 3. Autres tests

| Fichier | Ce qui est vérifié |
|---|---|
| `vehicle_schedule_test.dart` | Lecture de la réponse `ev/settings` réelle. `toUpdatedJson` : identique sans modification, modifie la plage et le programme sans toucher au reste ni muter `raw`, refuse un index hors limites. Plage en cours ou non. Durée de plus de 24 h ramenée à la plage quotidienne |
| `vehicle_status_models_test.dart` | `battery-status` : branchée en attente, en charge (puissance en kW ou en W), débranchée (états inconnus ignorés). `cockpit` : carburant et autonomie (hybride), rien pour un électrique. `hvac-status`, mesure ancienne signalée |
| `date_formatting_test.dart` | `parseTimeOfDay` : « HH:MM », « HH:MM:SS » (secondes ignorées), null sur un format inattendu |
| `demo_data_test.dart` | Véhicule de démonstration pilotable, paramétrage cohérent. Écriture simulée relue sans modifier le reste. Stockage en mémoire neuf à chaque instance |
| `kamereon_key_rejection_test.dart` | Distinguer un refus de clé d'une autre erreur. Refus : 403 au corps vide, corps qui nomme la clé, Gigya 500/400093. Pas un refus : 403 d'endpoint non supporté, 401 de JWT expiré, Gigya 403005 ou corps illisible |
| `renault_keys_source_test.dart` | `parseRenaultConst` : références par nom, littéral inline, locale au serveur non autorisé écartée, structure introuvable. `validateRenaultSettings` : valeurs actuelles acceptées, serveurs hors liste et clés au format inattendu refusés |
| `auth_keys_recovery_test.dart` | Clé refusée au démarrage : nouvelles clés récupérées, testées et adoptées. `renault-api` pas à jour : erreur et notification, clés inchangées. Nouvelles clés refusées : retour aux anciennes. Au plus une recherche automatique par période (sauf vérification manuelle, sans notification). Déconnexion : clés effacées |
| `widget_test.dart` | Écran de connexion sans session. Premier lancement : avertissement, tutoriel puis connexion. « Passer » mène à la connexion. Démonstration : véhicule fictif sans pilotage, puis retour à la connexion |
