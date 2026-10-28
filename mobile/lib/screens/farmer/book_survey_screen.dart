import '../../services/app_language.dart';
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
  bool _fieldsLoading = true;
  String? _fieldsError;
  String? _farmId;
  List<Map<String, dynamic>> _fields = [];
  @override
  void initState() {
    super.initState();
    _loadFields();
  }

  Future<void> _loadFields() async {
    try {
      final fields = await ApiService().registeredFields();
      if (!mounted) return;
      setState(() {
        _fields = fields;
        _fieldsError = null;
      });
      if (fields.length == 1) _selectField(fields.single['id'] as String);
    } catch (_) {
      if (mounted)
        setState(() => _fieldsError =
            'Registered fields could not be loaded. You can still request a visit; admin will link the field.');
    } finally {
      if (mounted) setState(() => _fieldsLoading = false);
    }
  }

  void _selectField(String id) {
    final field = _fields.firstWhere((f) => f['id'] == id);
    setState(() {
      _farmId = id;
      _farmName.text = field['farmName'];
      _address.text = field['farmAddress'];
      _city = field['city'];
      _soilType = field['soilType'];
    });
  }

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
        farmId: _farmId,
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr(
              'Request sent. Admin will approve and assign your farm visit.',
              context: context))));
      Navigator.pop(context);
    } on Exception catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr(error.toString(), context: context))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget choice(String label, String value, List<String> options,
      ValueChanged<String?> changed) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
          labelText: tr(label, context: context), border: OutlineInputBorder()),
      items: options
          .map((item) => DropdownMenuItem(
              value: item, child: Text(tr(item, context: context))))
          .toList(),
      onChanged:
          _loading || (_farmId != null && label != 'Season') ? null : changed,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: Text(tr('Request a farm survey', context: context))),
      body: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                      tr('Where should our field team visit?',
                          context: context),
                      style:
                          TextStyle(fontSize: 21, fontWeight: FontWeight.w600)),
                  SizedBox(height: 10),
                  Text(
                      tr('After admin approves your request, a team member will visit the farm and collect the readings.',
                          context: context),
                      style: TextStyle(color: Colors.grey, height: 1.6)),
                  SizedBox(height: 24),
                  if (_fieldsLoading) const LinearProgressIndicator(),
                  if (_fieldsError != null)
                    Text(tr(_fieldsError!, context: context)),
                  if (_fields.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      value: _farmId,
                      decoration: InputDecoration(
                          labelText:
                              tr('Your registered field', context: context),
                          border: const OutlineInputBorder()),
                      items: _fields
                          .map((field) => DropdownMenuItem<String>(
                              value: field['id'],
                              child: Text(field['farmName'])))
                          .toList(),
                      onChanged:
                          _loading ? null : (value) => _selectField(value!),
                      validator: (value) => value == null
                          ? tr('Choose your field', context: context)
                          : null,
                    ),
                    const SizedBox(height: 18),
                  ],
                  TextFormField(
                      controller: _farmName,
                      enabled: !_loading && _farmId == null,
                      maxLength: 100,
                      decoration: InputDecoration(
                          labelText: tr('Farm name', context: context),
                          border: OutlineInputBorder()),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? tr('Enter a farm name', context: context)
                              : null),
                  SizedBox(height: 12),
                  TextFormField(
                      controller: _address,
                      enabled: !_loading && _farmId == null,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 500,
                      decoration: InputDecoration(
                          labelText: tr('Farm address and landmarks',
                              context: context),
                          border: OutlineInputBorder()),
                      validator: (value) =>
                          value == null || value.trim().length < 8
                              ? tr('Enter an address the team can find',
                                  context: context)
                              : null),
                  SizedBox(height: 12),
                  TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                          labelText: tr('Visit contact phone (optional)',
                              context: context),
                          helperText: tr(
                              'Your account phone is used if left blank.',
                              context: context),
                          border: OutlineInputBorder()),
                      validator: (value) => value == null ||
                              value.trim().isEmpty
                          ? null
                          : RegExp(r'^[+0-9() -]{7,25}$').hasMatch(value.trim())
                              ? null
                              : 'Enter a valid contact number'),
                  SizedBox(height: 22),
                  choice(
                      'Farm city',
                      _city,
                      ['Pune', 'Mumbai', 'Delhi', 'Bangalore', 'Hyderabad'],
                      (value) => setState(() => _city = value!)),
                  SizedBox(height: 18),
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
                  SizedBox(height: 18),
                  choice('Season', _season, ['Summer', 'Monsoon', 'Winter'],
                      (value) => setState(() => _season = value!)),
                  SizedBox(height: 28),
                  CustomButton(
                      label: tr('Send survey request', context: context),
                      icon: Icons.send,
                      loading: _loading,
                      onPressed: _submit),
                ]),
          )),
    );
  }
}
