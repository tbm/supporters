#!/usr/bin/perl

use strict;
use warnings;

use DBI;
use Encode qw(encode decode);

my($OLD_SUPPORTERS_SQLITE_DB_FILE, $NEW_SUPPORTERS_SQLITE_DB_FILE) = @ARGV;

my $dbhOld = DBI->connect("dbi:SQLite:dbname=$OLD_SUPPORTERS_SQLITE_DB_FILE", "", "",
                               { RaiseError => 1, sqlite_unicode => 1 })
    or die $DBI::errstr;

my $dbhNew = DBI->connect("dbi:SQLite:dbname=$NEW_SUPPORTERS_SQLITE_DB_FILE", "", "",
                               { RaiseError => 1, sqlite_unicode => 1 })
  or die $DBI::errstr;

# Insert t-shirt types and sizes

my $sthInsertRequestType = $dbhNew->prepare("INSERT INTO request_type(type) values(?)");

$sthInsertRequestType->execute("t-shirt-0");
my $tShirt0RequestTypeId = $dbhNew->last_insert_id("","","","");
$sthInsertRequestType->execute("t-shirt-1");
my $tShirt1RequestTypeId = $dbhNew->last_insert_id("","","","");

my %tShirt0SizeRequestConfigurationIds;

my $sthInsertRequestConfiguration = $dbhNew->prepare("INSERT INTO request_configuration" .
                        "(request_type_id, description) values(?, ?)");
foreach my $requestTypeId (qw/$tShirt1RequestTypeId $tShirt0RequestTypeId/) {
  foreach my $size (qw/LadiesS LadiesM LadiesL LadiesXL MenS MenM MenXL Men2XL/) {
    $sthInsertRequestConfiguration->execute($requestTypeId, $size);
    $tShirt0SizeRequestConfigurationIds{$size} = $dbhNew->last_insert_id("","","","");
  }
}
$sthInsertRequestConfiguration->finish();

$sthInsertRequestType->execute("join-announce-email-list");
my $announceEmailListRequestTypeId = $dbhNew->last_insert_id("","","","");
$sthInsertRequestType->finish();

# Only one email Adress type so far
my $sthNew = $dbhNew->prepare("INSERT INTO address_type(name) values('paypal_payer')");
my $paypalPayerEmailAddresTypeId = $dbhNew->last_insert_id("","","","");
$sthNew->finish();

# Legacy fulfillment confirmation
$sthNew = $dbhNew->prepare("INSERT INTO fulfillment(date, who, how)" .
                           "values(date('now'), 'bkuhn', 'legacy import of old database; exact details of this fulfillment are unknown')");
my $fulfillmentId = $dbhNew->last_insert_id("","","","");
$sthNew->finish();

my $sthNewInsertSupporter = $dbhNew->prepare('INSERT INTO supporter(' .
                              'ledger_entity_id, display_name, public_ack) values (?, ?, ?)');
my $sthInsertEmailAddress = $dbhNew->prepare('INSERT INTO email_address(supporter_id, email_address, email_type_id, date_encountered)' .
                  "values(?, ?, $paypalPayerEmailAddresTypeId, date('now'))");

my $sthLinkSupporterToEmail = $dbhNew->prepare('INSERT INTO supporter_email_address_mapping(supporter_id, email_address_id, preferred)' .
                  "values(?, ?, $paypalPayerEmailAddresTypeId, date('now'), 1)");

my $sthLinkSupporterToPostal = $dbhNew->prepare('INSERT INTO supporter_postal_address_mapping(supporter_id, postal_address_id, preferred)' .
                  "values(?, ?, $paypalPayerEmailAddresTypeId, date('now'), 1)");

my $sthInsertRequest = $dbhNew->prepare('INSERT INTO request' .
     '(supporter_id, request_type_id, request_configuration_id, date_requested, fulfillment_id, notes) ' .
     "values(?, ?, ?, date('now'), ?," .
     '"import of old database; exact date of this request is unknown")');

my $sthPostalAddress = 'INSERT INTO postal_address(formatted_address, date_encountered)' .
                       "VALUES(? , date('now'))";

my $sthOld = $dbhOld->prepare('SELECT * from supporters order by id;');
$sthOld->execute();
while (my $row = $sthOld->fetchrow_hashref) {
  $sthNewInsertSupporter->execute($row->{ledger_entity_id}, $row->{display_name},
                                  $row->{public_ack});
  my $supporterId = $dbhNew->last_insert_id("","","","");
  die("Database conversion failed on id matching: $row->{ledger_entity_id} had ID $row->{id} now has $supporterId")
      unless ($row->{id} == $supporterId);
  if ($row->{want_gift}) {
    die "DB Convert Fail: Unknown shirt size of $row->{shirt_size} when someone wanted a shirt"
      unless defined $tShirt0SizeRequestConfigurationIds{$row->{shirt_size}};
    $sthInsertRequest->execute($supporterId, $tShirt0RequestTypeId,
                               $tShirt0SizeRequestConfigurationIds{$row->{shirt_size}},
                               ($row->{gift_sent} ? $fulfillmentId : undef));
  }
  if ($row->{join_list}) {
    $sthInsertRequest->execute($supporterId, $announceEmailListRequestTypeId, undef,
                               ($row->{on_announce_mailman_list} ? $fulfillmentId : undef));
  }
  $sthInsertEmailAddress->execute($supporterId, $row->{paypal_payer});
  my $emailId = $dbhNew->last_insert_id("","","","");
  $sthLinkSupporterToEmail->execute($supporterId, $emailId);
  $sthPostalAddress->execute($supporterId, $row->{formatted_address});
  my $postalId = $dbhNew->last_insert_id("","","","");
  $sthLinkSupporterToPostal->($supporterId, $postalId);
}
foreach my $sth (qw/$sthOld $sthOld $sthNewInsertSupporter $sthInsertEmailAddress
     $sthLinkSupporterToEmail $sthInsertRequest $sthPostalAddress $sthLinkSupporterToPostal/) {
  $sth->finish();
}
foreach my $dbh (qw/$dbhNew $dbhOld/) {
  $dbhNew->disconnect();
}

###############################################################################
#
# Local variables:
# compile-command: "perl -c db-convert-0.1-to-0.2.plx"
# End:
