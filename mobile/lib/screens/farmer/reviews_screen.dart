import '../../services/app_language.dart';
import 'package:flutter/material.dart';
import '../../auth/auth_service.dart';
import '../../models/review.dart';
import '../../services/api_service.dart';
import '../../widgets/loading_widget.dart';

class ReviewsScreen extends StatefulWidget {
  /// Pass [surveyId] when opening from a completed survey to show the write form.
  /// Leave null to show a read-only list of all reviews (e.g. from admin panel).
  final String? surveyId;

  /// Pass [surveyCompleted] = false to block writing a review for non-completed surveys.
  final bool surveyCompleted;

  const ReviewsScreen({
    super.key,
    this.surveyId,
    this.surveyCompleted = true,
  });

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  final _commentCtrl = TextEditingController();
  int _rating = 5;
  bool _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitReview() async {
    if (_commentCtrl.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      final userData = await AuthService().getUserData();
      await ApiService().submitReview(
        surveyId: widget.surveyId!,
        rating: _rating,
        comment: _commentCtrl.text.trim(),
        farmerName: userData?['name'] ?? 'Farmer',
      );
      if (mounted) {
        _commentCtrl.clear();
        setState(() => _rating = 5);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('Review submitted!', context: context)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(tr('Failed to submit: ${e.toString()}', context: context)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = widget.surveyId != null && widget.surveyCompleted;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Reviews', context: context))),
      body: Column(
        children: [
          // ── Write review form (only for completed surveys) ──
          if (widget.surveyId != null) ...[
            if (canWrite)
              Padding(
                padding: EdgeInsets.all(16),
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Write a Review', context: context),
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        SizedBox(height: 12),
                        // Star rating
                        Row(
                          children: List.generate(5, (i) {
                            return GestureDetector(
                              onTap: () => setState(() => _rating = i + 1),
                              child: Icon(
                                i < _rating ? Icons.star : Icons.star_border,
                                color: Colors.amber,
                                size: 32,
                              ),
                            );
                          }),
                        ),
                        SizedBox(height: 12),
                        TextField(
                          controller: _commentCtrl,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: tr('Share your experience...',
                                context: context),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _submitting ? null : _submitReview,
                            child: _submitting
                                ? SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : Text(tr('Submit Review', context: context)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              // Survey not completed — block review writing
              Padding(
                padding: EdgeInsets.all(16),
                child: Card(
                  color: Colors.orange[50],
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline, color: Colors.orange[700]),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            tr('You can only leave a review after your survey has been completed.',
                                context: context),
                            style:
                                TextStyle(color: Colors.orange, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Divider(height: 0),
          ],

          // ── Reviews list ────────────────────────────
          Expanded(
            child: StreamBuilder<List<Review>>(
              stream: widget.surveyId != null
                  ? ApiService().farmerReviewsStream()
                  : ApiService().reviewsStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(tr(
                          'Unable to load data. Check your connection and try again.',
                          context: context)),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return LoadingWidget();
                }
                final reviews = snapshot.data ?? [];
                if (reviews.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.rate_review_outlined,
                            size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text(tr('No reviews yet', context: context),
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: reviews.length,
                  itemBuilder: (context, i) {
                    final r = reviews[i];
                    return Card(
                      margin: EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(tr(r.farmerName, context: context),
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600)),
                                Spacer(),
                                Row(
                                  children: List.generate(
                                    5,
                                    (j) => Icon(
                                      j < r.rating
                                          ? Icons.star
                                          : Icons.star_border,
                                      color: Colors.amber,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 6),
                            Text(tr(r.comment, context: context),
                                style: TextStyle(color: Colors.black87)),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
