TODO
====

* Teach ``load_ledger.py`` to automatically find and import new, and only new, payments in the Ledger.  One possible strategy: find the newest payment in the database, run Ledger with a default ``--begin`` argument some days before that (30?  60?), then use ``Payment.objects.get_or_create()``.
* A few Supporters are "both" annual and monthly; i.e., they're a monthly Supporter who occasionally makes an additional large donation.  Right now their lapse date and status are calculated by whatever payment was made most recently, so that can weirdly fluctuate between the time they make the large donation and the time their next monthly payment comes in.  Should their lapse date be the greater of "one year out from their extra donation" and "one month out from their last monthly donation?"
* Optimize ``status_report.py``.  Right now it loads and calculates all data from scratch for each month.  Keeping some stuff in memory could probably reduce the runtime noticeably.  All the Supporter objects would be a good start; if that's not reasonable, at least all the entity names.
