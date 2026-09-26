# Changelog

## Non publié

- Réveils à l'heure exacte via l'autorisation Android « Alarmes et rappels »
  (demandée à l'activation du pilotage, alerte si elle manque, réveils
  approximatifs en attendant). Mise à jour depuis la 0.1.0 : Android
  supprime les envois programmés, ouvrez l'application une fois pour les
  reprogrammer.
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
