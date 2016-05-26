#!/usr/bin/perl

use strict;
use warnings;

use autodie qw(open close chdir);
use DBI;
use Encode qw(encode decode);

use Supporters;

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

foreach my $id (@supporterIds) {
  my $amount = $sp->donorTotalGaveInPeriod(donorId => $id);
  if ($amount > 120.00) {   # Ok, so they gave more than the minimum
    my $ledgerEntityId = $sp->getLedgerEntityId($id);
    my $lastGaveDate = $sp->donorLastGave($id);
    my $firstGaveDate = $sp->donorFirstGave($id);
    if ($lastGaveDate ne $firstGaveDate) {
      print "$ledgerEntityId gave total of $amount, firstGave $firstGaveDate, last Gave $lastGaveDate\n";
    }
  }
}
###############################################################################
#
# Local variables:
# compile-command: "perl -c find-already-renewed.plx"
# End:

