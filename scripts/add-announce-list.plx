#!/usr/bin/perl

use strict;
use warnings;

use autodie qw(open close);
use DBI;
use Encode qw(encode decode);

use Supporters;

my $LEDGER_CMD = "/usr/local/bin/ledger";

if (@ARGV != 4 and @ARGV != 5) {
  print STDERR "usage: $0 <SUPPORTERS_SQLITE_DB_FILE> <WHO> <HOW> <VERBOSITY_LEVEL>\n";
  exit 1;
}

my($SUPPORTERS_SQLITE_DB_FILE, $WHO, $HOW, $VERBOSE) = @ARGV;
$VERBOSE = 0 if not defined $VERBOSE;

my $dbh = DBI->connect("dbi:SQLite:dbname=$SUPPORTERS_SQLITE_DB_FILE", "", "",
                               { RaiseError => 1, sqlite_unicode => 1 })
  or die $DBI::errstr;

my $sp = new Supporters($dbh, [ "none" ]);

my(@supporterIds) = $sp->findDonor({});
foreach my $id (@supporterIds) {
  my $request;
  $request = $sp->getRequest({ donorId => $id, requestType => 'join-announce-email-list', ignoreFulfilledRequests => 1 });
  if (defined $request and defined $request->{requestType}) {
    my $emailTo = $sp->getPreferredEmailAddress($id);
    if (not defined $emailTo) {
      my(@addr) = $sp->getEmailAddresses($id);
      $emailTo = $addr[0];
    }
    if ($sp->emailOk($id)) {
      print $emailTo, "\n";
      $sp->fulfillRequest({ donorId => $id, requestType => $request->{requestType},
                            who => $WHO, how => $HOW});
    } else {
      $sp->fulfillRequest({ donorId => $id, requestType => $request->{requestType},
                            who => $WHO, how => "canceled this request without adding email address to announce list, since donor later requested no email contact"});
    }
  }
}
###############################################################################
#
# Local variables:
# compile-command: "perl -c add-announce-list.plx"
# End:

