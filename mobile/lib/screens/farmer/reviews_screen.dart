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
          const SnackBar(
            content: Text('Review submitted!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit: ${e.toString()}'),
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
      appBar: AppBar(title: const Text('Reviews')),
      body: Column(
        children: [
          // ── Write review form (only for completed surveys) ──
          if (widget.surveyId != null) ...[
            if (canWrite)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Write a Review',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 12),
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
                        const SizedBox(height: 12),
                        TextField(
                          controller: _commentCtrl,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'Share your experience...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _submitting ? null : _submitReview,
                            child: _submitting
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Submit Review'),
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
                padding: const EdgeInsets.all(16),
                child: Card(
                  color: Colors.orange[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline, color: Colors.orange[700]),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'You can only leave a review after your survey has been completed.',
                            style:
                                TextStyle(color: Colors.orange, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const Divider(height: 0),
          ],

          // ── Reviews list ────────────────────────────
          Expanded(
            child: StreamBuilder<List<Review>>(
              stream: widget.surveyId != null
                  ? ApiService().farmerReviewsStream()
                  : ApiService().reviewsStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                          'Unable to load data. Check your connection and try again.'),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LoadingWidget();
                }
                final reviews = snapshot.data ?? [];
                if (reviews.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.rate_review_outlined,
                            size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('No reviews yet',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: reviews.length,
                  itemBuilder: (context, i) {
                    final r = reviews[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(r.farmerName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                const Spacer(),
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
                            const SizedBox(height: 6),
                            Text(r.comment,
                                style: const TextStyle(color: Colors.black87)),
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
