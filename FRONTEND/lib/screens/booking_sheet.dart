import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/smartads_api.dart';
import '../theme.dart';
import '../utils/formatting.dart';
import 'payment_dialog.dart';

class BookingSheet extends StatefulWidget {
  const BookingSheet({super.key, required this.api, required this.billboard});
  final SmartAdsApi api;
  final Map<String, dynamic> billboard;
  @override
  State<BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<BookingSheet> {
  DateTime date = DateTime.now();
  List<String> slots = [];
  String? selected;
  bool loadingSlots = true;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  String dateIso(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  Future<void> _loadSlots() async {
    setState(() {
      loadingSlots = true;
      selected = null;
      error = null;
    });
    try {
      final response = await widget.api.get(
          '/api/billboards/${widget.billboard['id']}/availability?date=${dateIso(date)}');
      final booked = (response['bookedSlots'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final free = <String>[];
      for (var hour = 8; hour < 22; hour++) {
        final start = '${hour.toString().padLeft(2, '0')}:00';
        final end = '${(hour + 1).toString().padLeft(2, '0')}:00';
        if (!booked.any((b) =>
            ('${b['start_time']}').compareTo(end) < 0 &&
            ('${b['end_time']}').compareTo(start) > 0)) free.add(start);
      }
      if (mounted)
        setState(() {
          slots = free;
          loadingSlots = false;
        });
    } catch (exception) {
      if (mounted)
        setState(() {
          error = cleanError(exception);
          loadingSlots = false;
        });
    }
  }

  Future<void> _chooseDate() async {
    final chosen = await showDatePicker(
        context: context,
        initialDate: date,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)));
    if (chosen != null) {
      date = chosen;
      await _loadSlots();
    }
  }

  Future<void> _continue() async {
    if (selected == null) {
      setState(() => error = 'Choose an available one-hour slot.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final selection = await FilePicker.platform
          .pickFiles(type: FileType.video, withData: true);
      if (selection == null || selection.files.isEmpty) {
        if (mounted) setState(() => busy = false);
        return;
      }
      final file = selection.files.first;
      final reviewResponse = await widget.api.uploadVideo(file);
      final review = Map<String, dynamic>.from(reviewResponse['review'] as Map);
      if (!mounted) return;
      final amount = (widget.billboard['price_per_hour'] as num).toDouble();
      final payment = await showDialog<PaymentDetails>(
        context: context,
        builder: (_) => PaymentDialog(
          amount: amount,
          reviewMessage: '${review['message']}',
        ),
      );
      if (payment == null || !mounted) {
        setState(() => busy = false);
        return;
      }
      final hour = int.parse(selected!.substring(0, 2));
      final end = '${(hour + 1).toString().padLeft(2, '0')}:00';
      final bookingResponse = await widget.api.post('/api/bookings', body: {
        'billboardId': widget.billboard['id'],
        'reviewId': review['id'],
        'date': dateIso(date),
        'startTime': selected,
        'endTime': end
      });
      final booking =
          Map<String, dynamic>.from(bookingResponse['booking'] as Map);
      await widget.api
          .post('/api/bookings/${booking['id']}/payments/mock', body: {
        'provider': payment.provider,
        'mobileNumber': payment.mobileNumber,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (exception) {
      if (mounted)
        setState(() {
          error = cleanError(exception);
          busy = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 26),
          decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
          child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    Center(
                        child: Container(
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(
                                color: const Color(0xFFDCE4E1),
                                borderRadius: BorderRadius.circular(9)))),
                    const SizedBox(height: 18),
                    Text('${widget.billboard['name']}',
                        style: const TextStyle(
                            color: ink,
                            fontSize: 21,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 5),
                    Text(
                        '${widget.billboard['location']}  ·  ${money(widget.billboard['price_per_hour'])}/hour',
                        style: const TextStyle(
                            color: Color(0xFF718186), fontSize: 13)),
                    const SizedBox(height: 22),
                    const Text('1. Choose a date',
                        style: TextStyle(
                            color: ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                    const SizedBox(height: 9),
                    OutlinedButton.icon(
                        onPressed: busy ? null : _chooseDate,
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: Text(
                            '${date.day.toString().padLeft(2, '0')} ${monthName(date.month)} ${date.year}  ·  Change date'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: ink,
                            minimumSize: const Size.fromHeight(47),
                            alignment: Alignment.centerLeft,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13)))),
                    const SizedBox(height: 19),
                    const Text('2. Available one-hour slots',
                        style: TextStyle(
                            color: ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                    const SizedBox(height: 10),
                    if (loadingSlots)
                      const Center(
                          child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator()))
                    else if (error != null && slots.isEmpty)
                      Text(error!,
                          style: const TextStyle(
                              color: Color(0xFFAA4545), fontSize: 13))
                    else if (slots.isEmpty)
                      const Text(
                          'No slots are available for this date. Try another day.',
                          style:
                              TextStyle(color: Color(0xFF718186), fontSize: 13))
                    else
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final slot in slots)
                          ChoiceChip(
                              label: Text(
                                  '$slot–${(int.parse(slot.substring(0, 2)) + 1).toString().padLeft(2, '0')}:00'),
                              selected: selected == slot,
                              onSelected: busy
                                  ? null
                                  : (value) => setState(() {
                                        selected = value ? slot : null;
                                        error = null;
                                      }),
                              selectedColor: const Color(0xFFDDF1EC),
                              labelStyle: TextStyle(
                                  color: selected == slot ? teal : ink,
                                  fontWeight: FontWeight.w600),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(11)))
                      ]),
                    const SizedBox(height: 20),
                    const Text('3. Upload your advertisement video',
                        style: TextStyle(
                            color: ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                    const SizedBox(height: 5),
                    const Text(
                        'MP4, MOV, M4V or WebM · up to 120 MB · 3 seconds max. Gemini will review your video.',
                        style: TextStyle(
                            color: Color(0xFF7A8A8E),
                            height: 1.4,
                            fontSize: 12)),
                    if (error != null && slots.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(error!,
                              style: const TextStyle(
                                  color: Color(0xFFAA4545), fontSize: 12))),
                    const SizedBox(height: 16),
                    SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                            onPressed: busy || loadingSlots || slots.isEmpty
                                ? null
                                : _continue,
                            icon: busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.upload_file_rounded),
                            label: Text(busy
                                ? 'Uploading & checking video…'
                                : 'Select video & continue'),
                            style: FilledButton.styleFrom(
                                backgroundColor: teal,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(51),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14))))),
                  ]))),
        ));
  }
}
