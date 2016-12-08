#!/usr/bin/perl

use strict;
use warnings;

use autodie qw(open close);

use DBI;
use Encode qw(encode decode);
use Date::Manip::DM5;
use Supporters;

my $SPECIAL_THRESHOLD = 10_001;

my $TODAY = UnixDate(ParseDate("today"), '%Y-%m-%d');
my $ONE_YEAR_AGO = UnixDate(DateCalc(ParseDate("today"), "- 1 years"), '%Y-%m-%d');

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

my $lapsedCount = 0;
my  $yearTot = 0.00;
my %specialContributions;
foreach my $supporterId (@supporterIds) {
  my $expiresOn = $sp->supporterExpirationDate($supporterId);
  my $isLapsed = ( (not defined $expiresOn) or $expiresOn lt $TODAY);
  if (not $isLapsed) {
    my $lastYearGave = $sp->donorTotalGaveInPeriod(donorId => $supporterId,
                                                   startDate => $ONE_YEAR_AGO, endDate => $TODAY);
    ($lastYearGave >= $SPECIAL_THRESHOLD) ? ($specialContributions{$supporterId} = $lastYearGave) :
                                            ($yearTot +=  $lastYearGave);
  } else {
    my $lapsedStr = (defined $expiresOn) ? "lapsed on $expiresOn" : "never gave enough to be a supporter";
    print "$supporterId (", $sp->getLedgerEntityId($supporterId), ") $lapsedStr\n" if $isLapsed;
    $lapsedCount++;
  }
}

my $per = ( ($lapsedCount / scalar(@supporterIds)) * 100.00);
my $activeCount = scalar(@supporterIds) - $lapsedCount;
print "\n\nWe have ", scalar(@supporterIds), " supporters and $lapsedCount are lapsed.  That's ",
  sprintf("%.2f", $per), "%.\nActive supporter count: ", $activeCount, "\n";

print "\n\nTotal (non speical) Given in Year in last year by active supoprters: ", sprintf("%.2f\n", $yearTot);
print "Average annual contribution by non-lapsed donors: ", sprintf("%.2f\n\n", $yearTot / $activeCount);

print "\n\nSpecial Contributions: \n" if (keys(%specialContributions) > 0);
foreach my $key (sort keys %specialContributions) {
  print sprintf("%8d: %.2f\n", $key, $specialContributions{$key});
}
###############################################################################
#
# Local variables:
# compile-command: "perl -c calculate-renewal-rate.plx"
# End:

