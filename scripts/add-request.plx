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

my $configs = $sp->getRequestConfigurations($requestType);
die "problematic  on configs" if (keys %$configs != 1);
my $requestId = (keys(%$configs)) [0];

print "Using request id, $requestId\n";

my $requestConfig;
if (scalar keys(%{$configs->{$requestId}}) > 0) {
  while (not defined $requestConfig or not defined $configs->{$requestId}{$requestConfig}) {
    print "Request Config (", join(", ", keys(%{$configs->{$requestId}})), "): ";
    $requestConfig = <STDIN>;
    chomp $requestConfig;
  }
}

if ($requestType) {
  my $requestParamaters;
  if (defined $requestConfig) {
    $requestParamaters = { donorId => $supporterId, requestConfiguration => $requestConfig, requestType => $requestType };
  } else {
    $requestParamaters = { donorId => $supporterId, requestType => $requestType };
  }
  $sp->addRequest($requestParamaters);
}
