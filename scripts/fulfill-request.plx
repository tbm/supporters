#!/usr/bin/perl

use strict;
use warnings;

use DBI;
use Encode qw(encode decode);
use Supporters;

if (@ARGV != 1 and @ARGV !=2) {
  print STDERR "usage: $0 <SUPPORTERS_SQLITE_DB_FILE> <VERBOSITY_LEVEL>\n";
  exit 1;
}

my($SUPPORTERS_SQLITE_DB_FILE, $VERBOSE) = @ARGV;
$VERBOSE = 0 if not defined $VERBOSE;

my $dbh = DBI->connect("dbi:SQLite:dbname=$SUPPORTERS_SQLITE_DB_FILE", "", "",
                               { RaiseError => 1, sqlite_unicode => 1 })
  or die $DBI::errstr;

my $sp = new Supporters($dbh, [ "none" ]);

print "Supporter Id: ";
my $supporterId = <STDIN>;
chomp $supporterId;

my @requestTypes = $sp->getRequestType();
my %requestTypes;
@requestTypes{@requestTypes} = @requestTypes;
my $requestType = "";
while (not defined $requestTypes{$requestType}) {
  print "Request Type (", join(", ", @requestTypes), "): ";
  $requestType = <STDIN>;
  chomp $requestType;
}
print "How Request filled: ";
my $how = <STDIN>;
chomp $how;
print "Who fulfilled: ";
my $who = <STDIN>;
chomp $who;

my $req = $sp->getRequest({ donorId => $supporterId,
                             requestType => $requestType, ignoreFulfilledRequests => 1});

if (defined $req) {
  $sp->fulfillRequest({donorId => $supporterId, requestType => $requestType,
                       who => $who, how => $how});
} else {
  print "Unable to find an open request of that type for $supporterId.  No action taken.\n";
}
