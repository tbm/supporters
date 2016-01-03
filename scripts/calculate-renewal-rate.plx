#!/usr/bin/perl

use strict;
use warnings;

use autodie qw(open close);

use DBI;
use Encode qw(encode decode);
use Date::Manip::DM5;
use Supporters;

my $TODAY = UnixDate(ParseDate("today"), '%Y-%m-%d');

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
foreach my $supporterId (@supporterIds) {
  my $expiresOn = $sp->supporterExpirationDate($supporterId);
  my $isLapsed = ( (not defined $expiresOn) or $expiresOn lt $TODAY);
  next unless $isLapsed;

  print "$supporterId (", $sp->getLedgerEntityId($supporterId), ") lapsed on $expiresOn\n" if $isLapsed;
  $lapsedCount++;
}

my $per = ( ($lapsedCount / scalar(@supporterIds)) * 100.00);
print "\n\nWe have ", scalar(@supporterIds), " supporters and $lapsedCount are lapsed.  That's ",
  sprintf("%.2f", $per), "%.\n";

