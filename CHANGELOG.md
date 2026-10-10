# Changelog

## 0.4.0

- Charge immédiate (onglet Pilotage) : charge maintenant jusqu'au niveau
  choisi, même en heures pleines, que l'envoi auto soit actif ou non.
  Confirmation dans l'application en mode sécurisé, bouton Arrêter. À la
  fin, la voiture retrouve sa plage d'heures creuses (envoi auto actif) ou
  ses réglages d'avant ; une charge qui atteint la plage d'heures creuses
  suivante se prolonge jusqu'à sa fin.
- Plage modifiée hors application (MyRenault…) : signalée « Modifié hors
  app » avec un bouton Renvoyer, au lieu d'être affichée comme envoyée.
  Une charge immédiate dont la plage a été modifiée ailleurs est
  abandonnée sans rien écraser.
- « En vigueur » plus précis (onglets Pilotage et État) : charge
  immédiate en cours, heure réelle de l'envoi, plage à renvoyer ou à
  confirmer après un changement d'objectif.
- Onglet État : « en attente de la plage de charge » au lieu de « en
  attente de courant » quand la voiture attend sa plage ; informations de
  la carte Véhicule au choix (bouton de réglage).
- Interface allégée : boutons « Envoi auto » et « Mode sécurisé », et
  explications des cartes affichées à la demande (bouton « ? »).

## 0.3.0

- Seuils de charge (Réglages › Seuils de charge), gérés par l'application :
  la voiture n'applique pas ses propres seuils.
- Charge maximale : chaque plage est raccourcie pour s'arrêter vers ce
  niveau, d'après la batterie au moment de l'envoi ; déjà atteint, la
  voiture ne charge pas. Un objectif plus haut (agenda ou exceptionnel)
  passe outre. Journées entièrement en heures creuses : une plage
  raccourcie est envoyée chaque jour à 10:00.
- Charge minimale : batterie en dessous, voiture branchée et pas en
  charge, l'application propose une charge immédiate jusqu'à ce niveau
  (notification et onglet Pilotage). Si elle atteint la plage d'heures
  creuses suivante, elle se prolonge jusqu'à sa fin ; sinon, la plage
  d'heures creuses est renvoyée automatiquement à la fin de la charge.

## 0.2.3

- Pilotage sans objectif : l'heure « prête à » que la voiture exige pour
  activer la plage de charge n'est plus affichée (onglet Pilotage,
  notifications). Arbitraire et jamais atteinte, elle est désormais fixée
  à 12:00 la veille de l'envoi ; elle reste visible dans les programmes de
  la voiture.
- Sécurité : composants techniques mis à jour (Flutter 3.47.5, stockage
  chiffré de la session et des réglages modernisé). Mise à jour depuis la
  0.2.2 ou antérieure : reconnexion et paramétrage du pilotage à refaire.

## 0.2.2

- Tutoriel au premier lancement, après l'avertissement : onglets de
  l'application, heures creuses, objectifs « prête à », mode sécurisé, et
  autorisations Android (notifications, « Alarmes et rappels ») à donner
  directement. À revoir depuis Réglages › À propos.
- Onglet Pilotage : la plage en vigueur affiche « Envoyé <jour> à
  <heure> » une fois envoyée à la voiture.

## 0.2.1

- Pilotage : à la fin d'une série de journées entièrement en heures
  creuses, la plage envoyée garde ses horaires au lieu de démarrer dès
  l'envoi, qui faisait charger sur les heures pleines entre minuit et le
  début de la plage. Seul un objectif peut encore l'avancer.

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
