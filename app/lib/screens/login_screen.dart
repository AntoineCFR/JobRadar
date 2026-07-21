import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _register = false; // false = connexion, true = création de compte
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _message(e.code));
    } catch (_) {
      setState(() => _error = 'Une erreur est survenue. Réessayez.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(String code) => switch (code) {
        'invalid-credential' || 'wrong-password' || 'user-not-found' =>
          'Email ou mot de passe incorrect.',
        'email-already-in-use' => 'Cet email a déjà un compte.',
        'weak-password' => 'Mot de passe trop faible (6 caractères min.).',
        'invalid-email' => 'Email invalide.',
        'operation-not-allowed' =>
          'Connexion email/mot de passe non activée dans Firebase.',
        _ => 'Échec de la connexion ($code).',
      };

  void _submitEmail() {
    final auth = context.read<AuthService>();
    final email = _email.text.trim();
    final pwd = _password.text;
    if (email.isEmpty || pwd.isEmpty) {
      setState(() => _error = 'Renseigne un email et un mot de passe.');
      return;
    }
    _run(() => _register
        ? auth.registerWithEmail(email, pwd)
        : auth.signInWithEmail(email, pwd));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Symbols.radar, size: 64),
                  const SizedBox(height: 12),
                  Text('JobRadar', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 24),
                  if (_error != null) ...[
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                        labelText: 'Email', prefixIcon: Icon(Symbols.mail)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Mot de passe', prefixIcon: Icon(Symbols.lock)),
                    onSubmitted: (_) => _submitEmail(),
                  ),
                  const SizedBox(height: 16),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(),
                    )
                  else ...[
                    FilledButton.icon(
                      onPressed: _submitEmail,
                      icon: Icon(_register ? Symbols.person_add : Symbols.login),
                      label: Text(_register ? 'Créer un compte' : 'Se connecter'),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48)),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _register = !_register;
                        _error = null;
                      }),
                      child: Text(_register
                          ? 'J\'ai déjà un compte — me connecter'
                          : 'Pas de compte ? En créer un'),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Expanded(child: Divider()),
                        Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('ou')),
                        Expanded(child: Divider()),
                      ]),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _run(() => auth.signInWithGoogle()),
                      icon: const Icon(Symbols.g_mobiledata, size: 28),
                      label: const Text('Continuer avec Google'),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
