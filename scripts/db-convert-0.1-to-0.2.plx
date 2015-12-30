#!/usr/bin/perl

use strict;
use warnings;

use DBI;
use Encode qw(encode decode);
use Supporters;

if (@ARGV != 2 and @ARGV !=3) {
  print STDERR "usage: $0 <OLD_SUPPORTERS_SQLITE_DB_FILE> <NEW_SUPPORTERS_SQLITE_DB_FILE> <VERBOSITY_LEVEL>\n";
  exit 1;
}

my($OLD_SUPPORTERS_SQLITE_DB_FILE, $NEW_SUPPORTERS_SQLITE_DB_FILE, $VERBOSE) = @ARGV;
$VERBOSE = 0 if not defined $VERBOSE;

my $dbhOld = DBI->connect("dbi:SQLite:dbname=$OLD_SUPPORTERS_SQLITE_DB_FILE", "", "",
                               { RaiseError => 1, sqlite_unicode => 1 })
    or die $DBI::errstr;

my $dbhNew = DBI->connect("dbi:SQLite:dbname=$NEW_SUPPORTERS_SQLITE_DB_FILE", "", "",
                               { RaiseError => 1, sqlite_unicode => 1 })
  or die $DBI::errstr;

my $sp = new Supporters($dbhNew, "/usr/bin/ledger");

# Insert t-shirt types and sizes

my @sizes = qw/LadiesS LadiesM LadiesL LadiesXL MenS MenM MenL MenXL Men2XL/;
my $tShirt0 = $sp->addRequestConfigurations("t-shirt-0", \@sizes);
my $thShirt1 = $sp->addRequestConfigurations("t-shirt-1", \@sizes);

my $tShirt0RequestTypeId = (keys %{$tShirt0})[0];
my $tShirt1RequestTypeId = (keys %{$tShirt0})[0];

my %tShirt0SizeRequestConfigurationIds = %{$tShirt0->{$tShirt0RequestTypeId}};

# Only one email Adress type so far
my $sthNew = $dbhNew->prepare("INSERT INTO address_type(name) values('paypal_payer')");
$sthNew->execute();
my $paypalPayerTypeId = $dbhNew->last_insert_id("","","","");
$sthNew->finish();

my $sthOld = $dbhOld->prepare('SELECT * from supporters order by id;');
$sthOld->execute();

while (my $row = $sthOld->fetchrow_hashref) {
  $row->{email_address_type} = 'paypal';
  $row->{email_address} = $row->{paypal_payer};
  my $donorId = $sp->addSupporter($row);
  print STDERR "Processing $donorId from $row->{id}, $row->{ledger_entity_id}\n ..." if ($VERBOSE);
  die("Database conversion failed on id matching: $row->{ledger_entity_id} had ID $row->{id} now has $donorId")
      unless ($row->{id} == $donorId);
  if ($row->{want_gift}) {
    die "DB Convert Fail: Unknown shirt size of $row->{shirt_size} when someone wanted a shirt"
      unless defined $tShirt0SizeRequestConfigurationIds{$row->{shirt_size}};
    my $requestParamaters = { donorId => $donorId, requestConfiguration => $row->{shirt_size}, requestType => 't-shirt-0' };
    $sp->addRequest($requestParamaters);
    if ($row->{gift_sent}) {
      $requestParamaters->{who} = 'bkuhn';
      $requestParamaters->{how} = 'legacy import of old database; exact details of this fulfillment are unknown';
      $sp->fulfillRequest($requestParamaters);
    }
  }
  if ($row->{join_list}) {
    my $requestParamaters = { donorId => $donorId,  requestType => "join-announce-email-list" };
    $sp->addRequest($requestParamaters);
    if ($row->{on_announce_mailing_list}) {
      $requestParamaters->{who} = 'bkuhn';
      $requestParamaters->{how} = 'legacy import of old database; exact details of this fulfillment are unknown';
      $sp->fulfillRequest($requestParamaters);
    }
  }
  $sp->addPostalAddress($donorId, $row->{formatted_address}, 'paypal');
}
$sthOld->finish();
foreach my $dbh ($dbhNew, $dbhOld) {
  $dbhNew->disconnect();
}

###############################################################################
#
# Local variables:
# compile-command: "perl -c db-convert-0.1-to-0.2.plx"
# End:
