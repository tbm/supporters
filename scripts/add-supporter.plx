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

print "Ledger Entity Id: ";
my $entityId = <STDIN>;
chomp $entityId;

print "Display Name: ";
my $displayName = <STDIN>;
chomp $displayName;

print "Public Ack (0 or 1): ";
my $publicAck = <STDIN>;
chomp $publicAck;

print "Email Address: ";
my $email = <STDIN>;
chomp $email;

print "Email Address Type: ";
my $emailType = <STDIN>;
chomp $emailType;


print "Want T-Shirt: ";
my $tshirt = <STDIN>;
chomp $tshirt;

my $tshirtSize;

if ($tshirt) {
  print "T-Shirt Size: ";
  $tshirtSize = <STDIN>;
  chomp $tshirtSize;
}

print "Want announcemailing list: ";
my $wantList = <STDIN>;
chomp $wantList;

print "postal Address (. to end):\n";
my $postal;
while (my $line = <STDIN>) {
  last if /^\s*\.\s*$/;
  $postal .= $line;
}

my $sp = new Supporters($dbh, [ "none" ]);

my $donorId = $sp->addSupporter({ ledger_entity_id => $entityId, email_address => $email, email_address_type => $emailType,
                  display_name => $displayName, public_ack => $publicAck} );
if ($tshirt) {
  my $requestParamaters = { donorId => $donorId, requestConfiguration => $tshirtSize, requestType => 't-shirt-0' };
  $sp->addRequest($requestParamaters);
}
if ($wantList) {
  my $requestParamaters = { donorId => $donorId, requestType => 'join-announce-email-list' };
  $sp->addRequest($requestParamaters);
}
if ($postal and $postal !~ /^\s*$/) {
  print "postal type: ";
  my $postalType = <STDIN>;
  chomp $postalType;
  $sp->addPostalAddress($donorId, $postal, $postalType);
}
