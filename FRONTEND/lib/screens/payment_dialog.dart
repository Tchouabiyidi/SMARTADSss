import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/formatting.dart';

class PaymentDetails {
  const PaymentDetails({required this.provider, required this.mobileNumber});
  final String provider;
  final String mobileNumber;
}

class PaymentDialog extends StatefulWidget {
  const PaymentDialog(
      {super.key, required this.amount, required this.reviewMessage});
  final double amount;
  final String reviewMessage;

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  final formKey = GlobalKey<FormState>();
  final phone = TextEditingController();
  String provider = 'MTN Mobile Money';

  @override
  void dispose() {
    phone.dispose();
    super.dispose();
  }

  String? validatePhone(String? value) {
    if (!RegExp(r'^[26]\d{8}$').hasMatch(_localNumber(value))) {
      return 'Enter the 9 digits after +237.';
    }
    return null;
  }

  String _localNumber(String? value) {
    var digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('237')) digits = digits.substring(3);
    return digits;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        icon: const Icon(Icons.verified_rounded, color: teal, size: 34),
        title: const Text('Video approved', textAlign: TextAlign.center),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(widget.reviewMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Color(0xFF66777C),
                          height: 1.45,
                          fontSize: 13)),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                        color: const Color(0xFFE7F3F0),
                        borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      const Icon(Icons.receipt_long_outlined, color: teal),
                      const SizedBox(width: 10),
                      const Expanded(
                          child: Text('One-hour booking',
                              style: TextStyle(
                                  color: ink, fontWeight: FontWeight.w600))),
                      Text(money(widget.amount),
                          style: const TextStyle(
                              color: ink, fontWeight: FontWeight.w900)),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  const Text('Choose payment method',
                      style: TextStyle(
                          color: ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 13)),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        avatar: const Icon(Icons.phone_android, size: 18),
                        label: const Text('MTN Mobile Money'),
                        selected: provider == 'MTN Mobile Money',
                        onSelected: (_) =>
                            setState(() => provider = 'MTN Mobile Money'),
                      ),
                      ChoiceChip(
                        avatar: const Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 18),
                        label: const Text('Orange Money'),
                        selected: provider == 'Orange Money',
                        onSelected: (_) =>
                            setState(() => provider = 'Orange Money'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  TextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Mobile money number',
                      prefixText: '+237 ',
                      hintText: '6XX XXX XXX',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    validator: validatePhone,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                      'Demo payment only. No money will be charged. Your number is used for this simulated request and is not saved.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Color(0xFF849194), fontSize: 11, height: 1.4)),
                ],
              ),
            ),
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(
                  context,
                  PaymentDetails(
                      provider: provider,
                      mobileNumber: '+237${_localNumber(phone.text)}'));
            },
            icon: const Icon(Icons.lock_outline, size: 17),
            label: const Text('Simulate payment'),
            style: FilledButton.styleFrom(
                backgroundColor: teal, foregroundColor: Colors.white),
          ),
        ],
      );
}
