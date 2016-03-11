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
my(@supporterIds);
if ($CRITERION ne 'id') {
  @supporterIds  = $sp->findDonor({$CRITERION => $SEARCH_PARAMETER });
} else {
  push(@supporterIds, $SEARCH_PARAMETER);
}
my @requestTypes = $sp->getRequestType();
foreach my $id (@supporterIds) {
  $found = 1;
  my $preferredEmail = $sp->getPreferredEmailAddress($id);
  my $preferredPostal = undef; # $sp->getPreferredPostalAddress($id);
  print "Found:  $id, ", $sp->getLedgerEntityId($id), "\n";
  my(%addr) = $sp->getEmailAddresses($id);
  print "     Email Addresses: ";
  my $cnt = 0;
  foreach my $email (keys %addr) {
    $cnt++;
    print $email;
    print "(preferred)" if (defined $preferredEmail) and $email eq $preferredEmail;
    print ", " unless $cnt == scalar keys %addr;
  }
  my(%postalAddresses) = $sp->getPostalAddresses($id);
  if (scalar keys %postalAddresses <= 0) {
    print "\n     NO POSTAL ADDRESSES.\n";
  } else {
    print "\n     Postal Addresses:\n";
    foreach my $address (keys %postalAddresses) {
      print "          PREFERRED\n" if (defined $preferredPostal) and $address eq $preferredPostal;
      foreach my $addrLine (split("\n", $address)) {
        print "          $addrLine\n";
      }
    }
  }
  foreach my $requestType (@requestTypes) {
    my $req = $sp->getRequest({ donorId => $id, requestType => $requestType});
    if (defined $req) {
      print "     Request $req->{requestType}";
      print "($req->{requestConfiguration})" if defined $req->{requestConfiguration};
      print " made on $req->{requestDate}";
      if (not defined $req->{fulfillDate}) {
        print "\n";
      } else {
        print "...\n          fulfilled on $req->{fulfillDate}";
        print "...\n          notes: $req->{notes}" if defined $req->{notes};
        print "\n";
      }
    }
  }
}
print "No entries found\n" unless $found;
###############################################################################
#
# Local variables:
# compile-command: "perl -c send-mass-email.plx"
# End:

