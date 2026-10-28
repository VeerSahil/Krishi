import '../../services/app_language.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('Message sent. An admin reply will appear here.',
              context: context))));
    } on Exception catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr(error.toString(), context: context))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Contact admin', context: context))),
      body: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('How can we help?', context: context),
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              Text(
                  tr('Ask about your visit, readings or recommendation. A member of the admin team will reply here.',
                      context: context),
                  style: TextStyle(color: Colors.grey, height: 1.6)),
              SizedBox(height: 20),
              Form(
                  key: _formKey,
                  child: Column(children: [
                    TextFormField(
                        controller: _subject,
                        maxLength: 120,
                        decoration: InputDecoration(
                            labelText: tr('Subject', context: context),
                            border: OutlineInputBorder()),
                        validator: (value) =>
                            value == null || value.trim().length < 3
                                ? tr('Enter a subject', context: context)
                                : null),
                    SizedBox(height: 12),
                    TextFormField(
                        controller: _message,
                        minLines: 3,
                        maxLines: 6,
                        maxLength: 4000,
                        decoration: InputDecoration(
                            labelText: tr('Your message', context: context),
                            border: OutlineInputBorder()),
                        validator: (value) =>
                            value == null || value.trim().length < 5
                                ? tr('Tell us what you need help with',
                                    context: context)
                                : null),
                    SizedBox(height: 12),
                    SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                            onPressed: _sending ? null : _send,
                            icon: Icon(Icons.send, size: 18),
                            label: Text(tr(
                                _sending ? 'Sending…' : 'Send to admin',
                                context: context)))),
                  ])),
              SizedBox(height: 30),
              Text(tr('Your messages', context: context),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              SizedBox(height: 12),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: ApiService().supportMessagesStream(),
                builder: (context, snapshot) {
                  if (snapshot.hasError)
                    return Text(tr(
                        'Messages could not be loaded. Please check your connection.',
                        context: context));
                  if (!snapshot.hasData)
                    return Center(child: CircularProgressIndicator());
                  if (snapshot.data!.docs.isEmpty)
                    return Text(
                        tr('Your messages and admin replies will appear here.',
                            context: context),
                        style: TextStyle(color: Colors.grey));
                  return Column(
                      children: snapshot.data!.docs.map((doc) {
                    final data = doc.data();
                    final reply = data['adminReply'] as String?;
                    return Card(
                        margin: EdgeInsets.only(bottom: 14),
                        child: Padding(
                          padding: EdgeInsets.all(17),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    tr(data['subject'] ?? 'Message',
                                        context: context),
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600)),
                                SizedBox(height: 8),
                                Text(tr(data['message'] ?? '',
                                    context: context)),
                                Divider(height: 26),
                                Text(
                                    tr(
                                        reply == null
                                            ? 'Waiting for admin reply'
                                            : 'Admin reply',
                                        context: context),
                                    style: TextStyle(
                                        color: reply == null
                                            ? Colors.orange[800]
                                            : Colors.green[800],
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12)),
                                if (reply != null) ...[
                                  SizedBox(height: 7),
                                  Text(tr(reply, context: context))
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
