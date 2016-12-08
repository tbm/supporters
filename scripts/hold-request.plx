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
print "Why Request held: ";
my $why = <STDIN>;
chomp $why;

print "Who held: ";
my $who = <STDIN>;
chomp $who;

my $heldUntil;
while (not defined $heldUntil) {
  print "Hold when Until What date (ISO 8601 format): ";
  $heldUntil = <STDIN>;
  chomp $heldUntil;
  $heldUntil = undef unless $heldUntil =~ /^\d{4,4}-\d{2,2}-\d{2,2}$/;
}

my $req = $sp->getRequest({ donorId => $supporterId, requestType => $requestType});
if (defined $req) {
  print "Request $req->{requestType}";
  print "($req->{requestConfiguration})" if defined $req->{requestConfiguration};
  print " made on $req->{requestDate}";
}
print "Using request id, $req->{requestId}\n";
if (defined $req->{holdDate}) {
  print "That request is already on hold:\n";
  print "...\n          put on hold on  $req->{holdDate} by $req->{holder}";
  print "...\n              release on: $req->{holdReleaseDate}\n" if defined $req->{holdRelaseDate};
  print "...\n              on hold because: $req->{heldBecause}\n" if defined $req->{heldBecause};
  exit 1;
}

my $id = $sp->holdRequest({donorId => $supporterId, requestType => $req->{requestType},
                           who => $who, heldBecause => $why,
                           holdReleaseDate => $heldUntil});


die "error: unable to hold hold request" unless defined $id;
print "Request held.  Hold Id is $id\n";
