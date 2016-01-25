#!/usr/bin/perl

use strict;
use warnings;

use autodie qw(open close);
use DBI;
use Encode qw(encode decode);

use Supporters;

if (@ARGV < 2) {
  print STDERR "usage: $0 <SUPPORTERS_SQLITE_DB_FILE> <CRITERION> <SEARCH_PARAMETER> <VERBOSE>\n";
  exit 1;
}

my($SUPPORTERS_SQLITE_DB_FILE, $CRITERION, $SEARCH_PARAMETER, $VERBOSE) = @ARGV;
$VERBOSE = 0 if not defined $VERBOSE;

my $dbh = DBI->connect("dbi:SQLite:dbname=$SUPPORTERS_SQLITE_DB_FILE", "", "",
                               { RaiseError => 1, sqlite_unicode => 1 })
  or die $DBI::errstr;

my $sp = new Supporters($dbh, ['none']);

my $found = 0;
my(@supporterIds) = $sp->findDonor({$CRITERION => $SEARCH_PARAMETER });
foreach my $id (@supporterIds) {
  print "Found:  $id, ", $sp->getLedgerEntityId($id), "\n";
  $found = 1;
}
print "No entries found\n" unless $found;
###############################################################################
#
# Local variables:
# compile-command: "perl -c send-mass-email.plx"
# End:

