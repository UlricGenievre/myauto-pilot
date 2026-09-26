import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_formatting.dart';
import 'location_providers.dart';

class LocationScreen extends ConsumerWidget {
  const LocationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncLocation = ref.watch(vehicleLocationProvider);

    return asyncLocation.when(
      data: (location) {
        if (location == null) {
          return const Center(child: Text('Aucun véhicule sélectionné.'));
        }
        final position = LatLng(location.latitude, location.longitude);
        return Stack(
          children: [
            FlutterMap(
              options: MapOptions(initialCenter: position, initialZoom: 15),
              children: [
                // Tuiles OSM standard (gratuites, sans cle) passees dans un
                // filtre de couleur pour obtenir un rendu sombre cote client
                // plutot que de depender d'un fournisseur de tuiles
                // pre-stylees (CARTO a ferme son acces anonyme entre-temps :
                // cf. discussion, "API KEY REQUIRED"). _darkMapFilter
                // convertit en niveaux de gris, inverse la luminosite et
                // ajoute une teinte froide coherente avec le theme.
                ColorFiltered(
                  colorFilter: const ColorFilter.matrix(_darkMapFilter),
                  child: TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'fr.genu.myauto_pilot',
                  ),
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: position,
                      width: 44,
                      height: 44,
                      child: const _VehicleMarker(),
                    ),
                  ],
                ),
              ],
            ),
            const Positioned(
              bottom: 4,
              left: 8,
              child: Text(
                '© OpenStreetMap contributors',
                style: TextStyle(fontSize: 9, color: AppColors.textSecondary),
              ),
            ),
            Positioned(
              top: 12,
              right: 16,
              child: _MapButton(
                icon: Icons.refresh_rounded,
                onTap: () => ref.invalidate(vehicleLocationProvider),
              ),
            ),
            if (location.lastUpdated != null)
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Dernière position connue : '
                          '${formatRelativeDateTime(location.lastUpdated!)}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Erreur : $error', style: const TextStyle(color: AppColors.error))),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.92),
      shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

/// Filtre applique aux tuiles OSM (couleurs d'origine) pour simuler un fond
/// de carte sombre : conversion en niveaux de gris (poids de luminance
/// standard), inversion, compression du contraste (evite le noir/blanc pur,
/// plus proche des gris de l'app) et leger virage froid par canal.
///
/// Matrice 4x5 (format ColorFilter.matrix, valeurs sur l'echelle 0-255) :
/// chaque ligne calcule `sortie = a*R + b*G + c*B + d*A + e`.
const List<double> _darkMapFilter = [
  -0.2256, -0.4428, -0.0860, 0, 205.25,
  -0.2329, -0.4572, -0.0888, 0, 211.95,
  -0.2648, -0.5198, -0.1010, 0, 240.95,
  0, 0, 0, 1, 0,
];

/// Pin vehicule sur la carte : halo jaune sur fond sombre, coherent avec
/// l'accent du reste de l'app et bien visible sur le fond de carte assombri.
class _VehicleMarker extends StatelessWidget {
  const _VehicleMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceHigh,
        border: Border.all(color: AppColors.accent, width: 2.5),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: const Icon(Icons.directions_car, color: AppColors.accent, size: 22),
    );
  }
}
