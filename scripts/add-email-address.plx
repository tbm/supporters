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

print "Supporter Id: ";
my $supporterId = <STDIN>;
chomp $supporterId;

print "Email Address: ";
my $email = <STDIN>;
chomp $email;

print "Email Address Type: ";
my $emailType = <STDIN>;
chomp $emailType;

print "Preferred (0 or 1): ";
my $preferred = <STDIN>;
chomp $preferred;

my $sp = new Supporters($dbh, [ "none" ]);

$sp->addEmailAddress($supporterId, $email, $emailType);

print "Preferred email address was: ", $sp->getPreferredEmailAddress($supporterId) || "(none)", "\n";
if ($preferred) {
  $sp->setPreferredEmailAddress($supporterId, $email);
    print "Preferred email address is now: ", $sp->getPreferredEmailAddress($supporterId), "\n";
}
