import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/renault_api_settings.dart';
import '../../core/theme/app_theme.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String _locale = defaultRenaultLocale;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    final locales = ref.read(renaultLocalesProvider).valueOrNull;
    if (locales == null || !_formKey.currentState!.validate()) return;
    ref
        .read(authControllerProvider.notifier)
        .login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          settings: locales.firstWhere((s) => s.locale == _locale, orElse: () => locales.first),
        );
  }

  /// Choix du pays du compte : ses cles et serveurs Renault viennent de
  /// `renault-api`, telecharge a l'ouverture de l'ecran.
  Widget _countryField(AsyncValue<List<RenaultApiSettings>> locales) {
    return locales.when(
      loading: () => const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Chargement des clés Renault…', style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
      error: (error, _) => Column(
        children: [
          Text(
            error is ApiException ? error.message : 'Clés Renault indisponibles : $error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w500),
          ),
          TextButton(onPressed: () => ref.invalidate(renaultLocalesProvider), child: const Text('Réessayer')),
        ],
      ),
      data: (list) {
        final value = list.any((s) => s.locale == _locale) ? _locale : list.first.locale;
        return DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          dropdownColor: AppColors.surfaceHigh,
          decoration: const InputDecoration(labelText: 'Pays du compte', prefixIcon: Icon(Icons.public)),
          items: [for (final s in list) DropdownMenuItem(value: s.locale, child: Text(renaultLocaleName(s.locale)))],
          onChanged: (locale) => setState(() => _locale = locale ?? _locale),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final locales = ref.watch(renaultLocalesProvider);
    final isLoading = authState is AuthLoading;
    final canSubmit = !isLoading && locales.hasValue;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.6),
            radius: 1.2,
            colors: [Color(0xFF232427), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              // Groupe de remplissage automatique : expose les champs au
              // systeme Android (gestionnaires de mots de passe). A la
              // connexion reussie, l'ecran est remplace par l'accueil et le
              // groupe, en disparaissant, valide le formulaire : le
              // gestionnaire peut alors proposer d'enregistrer.
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.surfaceHigh,
                            border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
                          ),
                          child: const Icon(Icons.bolt_rounded, size: 36, color: AppColors.accent),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'MyAuto Pilot',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Connecte-toi avec ton compte MyRenault',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 40),
                      _countryField(locales),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email, AutofillHints.username],
                        decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                        validator: (value) => (value == null || value.isEmpty) ? 'Email requis' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        autofillHints: const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: 'Mot de passe',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (value) => (value == null || value.isEmpty) ? 'Mot de passe requis' : null,
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      if (authState is AuthUnauthenticated && authState.error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          authState.error!,
                          style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 28),
                      FilledButton(
                        onPressed: canSubmit ? _submit : null,
                        child: isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAccent),
                              )
                            : const Text('Se connecter'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: isLoading ? null : () => ref.read(authControllerProvider.notifier).startDemo(),
                        child: const Text('Découvrir sans compte (démonstration)'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
