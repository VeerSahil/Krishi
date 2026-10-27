import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class ContactAdminScreen extends StatefulWidget {
  final String? surveyId;
  const ContactAdminScreen({super.key, this.surveyId});
  @override
  State<ContactAdminScreen> createState() => _ContactAdminScreenState();
}

class _ContactAdminScreenState extends State<ContactAdminScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _message = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      await ApiService().contactAdmin(
          subject: _subject.text.trim(),
          message: _message.text.trim(),
          surveyId: widget.surveyId);
      if (!mounted) return;
      _subject.clear();
      _message.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Message sent. An admin reply will appear here.')));
    } on Exception catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contact admin')),
      body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('How can we help?',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text(
                  'Ask about your visit, readings or recommendation. A member of the admin team will reply here.',
                  style: TextStyle(color: Colors.grey, height: 1.6)),
              const SizedBox(height: 20),
              Form(
                  key: _formKey,
                  child: Column(children: [
                    TextFormField(
                        controller: _subject,
                        maxLength: 120,
                        decoration: const InputDecoration(
                            labelText: 'Subject', border: OutlineInputBorder()),
                        validator: (value) =>
                            value == null || value.trim().length < 3
                                ? 'Enter a subject'
                                : null),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: _message,
                        minLines: 3,
                        maxLines: 6,
                        maxLength: 4000,
                        decoration: const InputDecoration(
                            labelText: 'Your message',
                            border: OutlineInputBorder()),
                        validator: (value) =>
                            value == null || value.trim().length < 5
                                ? 'Tell us what you need help with'
                                : null),
                    const SizedBox(height: 12),
                    SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                            onPressed: _sending ? null : _send,
                            icon: const Icon(Icons.send, size: 18),
                            label:
                                Text(_sending ? 'Sending…' : 'Send to admin'))),
                  ])),
              const SizedBox(height: 30),
              const Text('Your messages',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: ApiService().supportMessagesStream(),
                builder: (context, snapshot) {
                  if (snapshot.hasError)
                    return const Text(
                        'Messages could not be loaded. Please check your connection.');
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  if (snapshot.data!.docs.isEmpty)
                    return const Text(
                        'Your messages and admin replies will appear here.',
                        style: TextStyle(color: Colors.grey));
                  return Column(
                      children: snapshot.data!.docs.map((doc) {
                    final data = doc.data();
                    final reply = data['adminReply'] as String?;
                    return Card(
                        margin: const EdgeInsets.only(bottom: 14),
                        child: Padding(
                          padding: const EdgeInsets.all(17),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(data['subject'] ?? 'Message',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                Text(data['message'] ?? ''),
                                const Divider(height: 26),
                                Text(
                                    reply == null
                                        ? 'Waiting for admin reply'
                                        : 'Admin reply',
                                    style: TextStyle(
                                        color: reply == null
                                            ? Colors.orange[800]
                                            : Colors.green[800],
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12)),
                                if (reply != null) ...[
                                  const SizedBox(height: 7),
                                  Text(reply)
                                ],
                              ]),
                        ));
                  }).toList());
                },
              ),
            ],
          )),
    );
  }
}
