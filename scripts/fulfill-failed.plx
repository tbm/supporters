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
print "Why fulfillment failed: ";
my $why = <STDIN>;
chomp $why;

my $id = $sp->fulfillFailure({donorId => $supporterId, requestType => $requestType, why => $why});

die "requestType $requestType not found for $supporterId, or the request was not already fulfilled yet anyway." unless defined $id;

print "Fulfill failure recorded.  Hold Id is $id\n";
