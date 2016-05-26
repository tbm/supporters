#!/usr/bin/perl

use strict;
use warnings;

use autodie qw(open close chdir);
use DBI;
use Encode qw(encode decode);

use Supporters;

use Date::Manip::DM5;

my $TODAY = UnixDate(ParseDate("today"), '%Y-%m-%d');
my $ONE_YEAR_AGO = UnixDate(DateCalc(ParseDate("today"), "- 1 year"), '%Y-%m-%d');

my $LEDGER_CMD = "/usr/local/bin/ledger";

if (@ARGV < 5 ) {
  print STDERR "usage: $0 <SUPPORTERS_SQLITE_DB_FILE> <MONTHLY_SEARCH_REGEX> <ANNUAL_SEARCH_REGEX>  <VERBOSE> <LEDGER_CMD_LINE>\n";
  exit 1;
}

my($SUPPORTERS_SQLITE_DB_FILE, $MONTHLY_SEARCH_REGEX, $ANNUAL_SEARCH_REGEX, $VERBOSE,
   @LEDGER_CMD_LINE) = @ARGV;

my $dbh = DBI->connect("dbi:SQLite:dbname=$SUPPORTERS_SQLITE_DB_FILE", "", "",
                               { RaiseError => 1, sqlite_unicode => 1 })
  or die $DBI::errstr;

my $sp = new Supporters($dbh, \@LEDGER_CMD_LINE, { monthly => $MONTHLY_SEARCH_REGEX, annual => $ANNUAL_SEARCH_REGEX});
my(@supporterIds) = $sp->findDonor({});

foreach my $id (sort { $sp->donorLastGave($a) cmp $sp->donorLastGave($b) } @supporterIds) {
  my $amount = $sp->donorTotalGaveInPeriod(donorId => $id);
  my $lastGaveDate = $sp->donorLastGave($id);
  my $firstGaveDate = $sp->donorFirstGave($id);
  my $nineMonthsSinceFirstGave = UnixDate(DateCalc(ParseDate($firstGaveDate), "+ 9 months"), '%Y-%m-%d');
  if ($amount > 180.00 and
      $lastGaveDate ne $firstGaveDate and
      $firstGaveDate le $ONE_YEAR_AGO and
      $lastGaveDate ge $nineMonthsSinceFirstGave ) {
    my $ledgerEntityId = $sp->getLedgerEntityId($id);
    my $type = $sp->{ledgerData}{$ledgerEntityId}{__TYPE__};
    my $shirt1 = $sp->getRequest({ donorId => $id, requestType => 't-shirt-1' });
    my $shirt0 = $sp->getRequest({ donorId => $id, requestType => 't-shirt-0' });
    print "$type: ";
    if (not defined $shirt0 and not defined $shirt1) {
      print "NEVER WANTED SHIRT: ";
    } elsif (defined $shirt0 and not defined $shirt1) {
      if (not defined $shirt0->{fulfillDate}) {
        my $rangeStart = UnixDate(DateCalc(ParseDate($lastGaveDate), "- 3 months"), '%Y-%m-%d');
        my $rangeEnd = UnixDate(DateCalc(ParseDate($lastGaveDate), "+ 3 months"), '%Y-%m-%d');
        if ($shirt0->{requestDate} ge $rangeStart and $shirt0->{requestDate} le $rangeEnd) {
          print "ALL OK, only 1 SHIRT EVER REQUESTED: ";
        } else {
          print "NEEDS 2 SHIRTS, 2ND SHIRT REQUEST MISSING: ";
        }
      } else {
        print "NEEDS 1 SHIRT, 2ND SHIRT REQUEST MISSING: ";
      }
    } elsif (defined $shirt1 and not defined $shirt0) {
        print "NEEDS WEIRDNESS ATTENTION, NO SHIRT0 REQUEST BUT THERE IS A SHIRT1 REQUEST: ";
    } elsif (defined $shirt1 and defined $shirt0) {
      print "ALL OK, 2 SHIRTS, WITH REQUESTS: ";
    }
    print " $ledgerEntityId gave total of $amount, firstGave $firstGaveDate, last Gave $lastGaveDate\n";
  }
}
###############################################################################
#
# Local variables:
# compile-command: "perl -c find-already-renewed.plx"
# End:

