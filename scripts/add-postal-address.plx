#!/usr/bin/perl

use strict;
use warnings;

use DBI;
use Encode qw(encode decode);
use Supporters;

binmode STDIN, ":utf8";
binmode STDOUT, ":utf8";

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

print "postal Address (. to end):\n";
my $postal = "";
while (my $line = <STDIN>) {
  last if $line =~ /^\s*\.\s*$/;
  $postal .= $line;
}

print "Postal Address Type: ";
my $postalType = <STDIN>;
chomp $postalType;

print "Preferred (0 or 1): ";
my $preferred = <STDIN>;
chomp $preferred;

my $sp = new Supporters($dbh, [ "none" ]);

$sp->addPostalAddress($supporterId, $postal, $postalType);

print "Preferred postal address was: ", $sp->getPreferredPostalAddress($supporterId), "\n";
if ($preferred) {
  $sp->setPreferredPostalAddress($supporterId, $postal);
    print "Preferred postal address is now: ", $sp->getPreferredPostalAddress($supporterId), "\n";
}
