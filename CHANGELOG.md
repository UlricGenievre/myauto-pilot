# Changelog

## 0.2.0

- Objectifs climatisés : option « Climatisation », avec sa température
  (16 à 26 °C, 21 °C par défaut), sur les objectifs des agendas et
  l'objectif exceptionnel. L'habitacle est préparé pour l'heure « prête à »
  (programme de la voiture en charge + préclimatisation).
- Onglet État : branchement et état de charge détaillé (en attente de la
  plage, en charge avec puissance et temps restant, charge terminée,
  trappe ouverte…), carburant des hybrides rechargeables (autonomie et
  litres, auparavant jamais affiché), température de l'habitacle avec
  l'ancienneté de la mesure (la voiture ne la rafraîchit qu'éveillée).
- Onglet Actions : état de la climatisation et températures, klaxon et
  phares pour retrouver la voiture.
- Réglages et agendas : le bas des pages n'est plus masqué par la barre de
  navigation d'Android.

## 0.1.1

- Mode démonstration (« Découvrir sans compte ») : véhicule et données
  fictifs, rien n'est envoyé à Renault.
- Réveils à l'heure exacte via l'autorisation Android « Alarmes et rappels »
  (demandée à l'activation du pilotage, alerte si elle manque, réveils
  approximatifs en attendant). Mise à jour depuis la 0.1.0 : Android
  supprime les envois programmés, ouvrez l'application une fois pour les
  reprogrammer.
- Alerte dans « Pilotage automatique » si les notifications (ou leur canal)
  sont désactivées, avec un bouton pour les réactiver : sans elles, le mode
  sécurisé ne peut rien proposer.
- Police Manrope intégrée à l'application : plus aucun appel à Google Fonts.
- Icône de l'application sur Android 7 (icône Flutter par défaut jusqu'ici).
- « À propos » : lien vers la politique de confidentialité, licences des
  composants.
- Fiche de store prête (`fastlane/metadata`), politique de confidentialité
  (`PRIVACY.md`).

## 0.1.0 — première version publique (bêta)

- Plages d'heures creuses par jour, journées entièrement en heures creuses.
- Agendas d'objectifs « prête à X % » et objectif exceptionnel ; élargissement
  automatique d'une plage insuffisante (fin de charge au-delà de 95 % comptée
  à mi-puissance).
- Envoi automatique des plages à l'heure exacte, mode sécurisé par défaut.
- Pilotage limité aux modèles compatibles (lecture seule sinon).
- Clés d'accès Renault récupérées depuis renault-api, mises à jour
  automatiquement ; choix du pays à la connexion.
