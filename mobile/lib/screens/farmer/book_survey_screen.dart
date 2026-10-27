import 'package:flutter/material.dart';
import '../../auth/auth_service.dart';
import '../../services/api_service.dart';
import '../../widgets/custom_button.dart';

class BookSurveyScreen extends StatefulWidget {
  const BookSurveyScreen({super.key});
  @override
  State<BookSurveyScreen> createState() => _BookSurveyScreenState();
}

class _BookSurveyScreenState extends State<BookSurveyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _farmName = TextEditingController(text: 'My farm');
  final _address = TextEditingController();
  final _phone = TextEditingController();
  String _city = 'Pune', _soilType = 'Black', _season = 'Monsoon';
  bool _loading = false;

  @override
  void dispose() {
    _farmName.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final profile = await AuthService().getUserData();
      await ApiService().bookSurvey(
        city: _city,
        soilType: _soilType,
        season: _season,
        year: DateTime.now().year,
        farmerName: profile?['name'] ?? '',
        farmerEmail: profile?['email'] ?? '',
        farmName: _farmName.text.trim(),
        farmAddress: _address.text.trim(),
        contactPhone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Request sent. Admin will approve and assign your farm visit.')));
      Navigator.pop(context);
    } on Exception catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget choice(String label, String value, List<String> options,
      ValueChanged<String?> changed) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration:
          InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: options
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: _loading ? null : changed,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request a farm survey')),
      body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Where should our field team visit?',
                      style:
                          TextStyle(fontSize: 21, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  const Text(
                      'After admin approves your request, a team member will visit the farm and collect the readings.',
                      style: TextStyle(color: Colors.grey, height: 1.6)),
                  const SizedBox(height: 24),
                  TextFormField(
                      controller: _farmName,
                      maxLength: 100,
                      decoration: const InputDecoration(
                          labelText: 'Farm name', border: OutlineInputBorder()),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Enter a farm name'
                              : null),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: _address,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 500,
                      decoration: const InputDecoration(
                          labelText: 'Farm address and landmarks',
                          border: OutlineInputBorder()),
                      validator: (value) =>
                          value == null || value.trim().length < 8
                              ? 'Enter an address the team can find'
                              : null),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                          labelText: 'Visit contact phone (optional)',
                          helperText:
                              'Your account phone is used if left blank.',
                          border: OutlineInputBorder()),
                      validator: (value) => value == null ||
                              value.trim().isEmpty
                          ? null
                          : RegExp(r'^[+0-9() -]{7,25}$').hasMatch(value.trim())
                              ? null
                              : 'Enter a valid contact number'),
                  const SizedBox(height: 22),
                  choice(
                      'Farm city',
                      _city,
                      ['Pune', 'Mumbai', 'Delhi', 'Bangalore', 'Hyderabad'],
                      (value) => setState(() => _city = value!)),
                  const SizedBox(height: 18),
                  choice(
                      'Soil type',
                      _soilType,
                      [
                        'Black',
                        'Red',
                        'Alluvial',
                        'Laterite',
                        'Sandy',
                        'Clay',
                        'Loamy',
                        'Peaty',
                        'Saline',
                        'Chalky'
                      ],
                      (value) => setState(() => _soilType = value!)),
                  const SizedBox(height: 18),
                  choice('Season', _season, ['Summer', 'Monsoon', 'Winter'],
                      (value) => setState(() => _season = value!)),
                  const SizedBox(height: 28),
                  CustomButton(
                      label: 'Send survey request',
                      icon: Icons.send,
                      loading: _loading,
                      onPressed: _submit),
                ]),
          )),
    );
  }
}
