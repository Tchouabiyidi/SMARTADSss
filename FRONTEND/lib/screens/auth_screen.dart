import 'package:flutter/material.dart';

import '../services/smartads_api.dart';
import '../theme.dart';
import '../utils/formatting.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.api, required this.onSignedIn});
  final SmartAdsApi api;
  final ValueChanged<Map<String, dynamic>> onSignedIn;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  bool createAccount = false;
  bool obscure = true;
  bool busy = false;
  String role = 'advertiser';

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final result = await widget.api.post(
        createAccount ? '/api/auth/signup' : '/api/auth/login',
        body: {
          if (createAccount) 'name': name.text.trim(),
          'email': email.text.trim(),
          'password': password.text,
          if (createAccount) 'role': role,
        },
      );
      widget.onSignedIn(result);
    } catch (error) {
      if (mounted) showMessage(context, cleanError(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 700;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: wide
                  ? Row(children: [
                      Expanded(child: _brandPanel()),
                      const SizedBox(width: 52),
                      Expanded(child: _formPanel())
                    ])
                  : Column(children: [
                      const SizedBox(height: 18),
                      _compactBrand(),
                      const SizedBox(height: 28),
                      _formPanel()
                    ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactBrand() => Column(children: [
        Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
                color: teal, borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.play_arrow_rounded,
                color: Colors.white, size: 42)),
        const SizedBox(height: 12),
        const Text('SMARTADS',
            style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 22,
                color: ink,
                letterSpacing: 2)),
      ]);

  Widget _brandPanel() => Container(
        height: 570,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
            color: ink,
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF18394A), Color(0xFF102431)])),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                    color: teal, borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 32)),
            const SizedBox(width: 12),
            const Text('SMARTADS',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5))
          ]),
          const Spacer(),
          const Text('Make every\nlocation count.',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  height: 1.12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1)),
          const SizedBox(height: 18),
          const Text(
              'A simpler way to book digital billboards and put your message in the right place.',
              style: TextStyle(
                  color: Color(0xFFC0D1D6), height: 1.6, fontSize: 16)),
          const SizedBox(height: 30),
          const _FeatureRow(
              icon: Icons.location_on_outlined,
              text: 'Discover billboard locations'),
          const SizedBox(height: 14),
          const _FeatureRow(
              icon: Icons.calendar_month_outlined,
              text: 'Book available time slots'),
          const SizedBox(height: 14),
          const _FeatureRow(
              icon: Icons.verified_outlined,
              text: 'Review and schedule your ad'),
          const Spacer(),
          const Text('YOUR MESSAGE, OUT IN THE WORLD',
              style: TextStyle(
                  color: Color(0xFF95B1B6),
                  fontSize: 10,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _formPanel() => Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                  color: ink.withValues(alpha: .06),
                  blurRadius: 28,
                  offset: const Offset(0, 12))
            ]),
        child: Form(
          key: formKey,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(createAccount ? 'Create your account' : 'Welcome back',
                style: const TextStyle(
                    color: ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 26,
                    letterSpacing: -.5)),
            const SizedBox(height: 8),
            Text(
                createAccount
                    ? 'Get started with SMARTADS in a few steps.'
                    : 'Sign in to continue to your SMARTADS workspace.',
                style: const TextStyle(color: Color(0xFF73828A), height: 1.45)),
            const SizedBox(height: 26),
            if (createAccount) ...[
              TextFormField(
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'Full name',
                      prefixIcon: Icon(Icons.person_outline)),
                  validator: (value) => (value?.trim().length ?? 0) < 2
                      ? 'Enter your name.'
                      : null),
              const SizedBox(height: 14),
            ],
            TextFormField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                    labelText: 'Email address',
                    prefixIcon: Icon(Icons.mail_outline)),
                validator: (value) => value == null || !value.contains('@')
                    ? 'Enter a valid email.'
                    : null),
            const SizedBox(height: 14),
            TextFormField(
                controller: password,
                obscureText: obscure,
                decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                        onPressed: () => setState(() => obscure = !obscure),
                        icon: Icon(obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined))),
                validator: (value) => (value?.length ?? 0) < 8
                    ? 'Use at least 8 characters.'
                    : null),
            if (createAccount) ...[
              const SizedBox(height: 18),
              const Text('I want to join as',
                  style: TextStyle(
                      color: ink, fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 9),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                      value: 'advertiser',
                      label: Text('Advertiser'),
                      icon: Icon(Icons.campaign_outlined)),
                  ButtonSegment(
                      value: 'owner',
                      label: Text('Billboard owner'),
                      icon: Icon(Icons.business_outlined))
                ],
                selected: {role},
                onSelectionChanged: (value) =>
                    setState(() => role = value.first),
              ),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: busy ? null : submit,
              style: FilledButton.styleFrom(
                  backgroundColor: teal,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              child: busy
                  ? const SizedBox(
                      width: 21,
                      height: 21,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(createAccount ? 'Create account' : 'Sign in',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 14),
            TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() => createAccount = !createAccount),
                child: Text(
                    createAccount
                        ? 'Already have an account?  Sign in'
                        : 'New to SMARTADS?  Create an account',
                    style: const TextStyle(
                        color: teal, fontWeight: FontWeight.w700))),
            const SizedBox(height: 4),
            const Text('By continuing, you agree to use SMARTADS responsibly.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF9AA6A8), fontSize: 11)),
          ]),
        ),
      );
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: const Color(0xFF72D5C6), size: 20),
        const SizedBox(width: 12),
        Text(text,
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500))
      ]);
}
