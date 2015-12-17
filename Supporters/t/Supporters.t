# Supporters.t                                            -*- Perl -*-
#   Basic unit tests for Supporters.pm
#########################

use strict;
use warnings;

use Test::More tests => 55;
use Test::Exception;

use Scalar::Util qw(looks_like_number reftype);

=pod

Supporters.t is the basic unit tests for Supporters.pm.  It tests the
following things:

=over

=item use command for the module.

=cut

BEGIN { use_ok('Supporters') };


require 't/CreateTestDB.pl';

my $dbh = get_test_dbh();


=item Public-facing methods of the module, as follows:

=over

=item new

=cut

my $sp = new Supporters($dbh, "testcmd");

is($dbh, $sp->dbh(), "new: verify dbh set");
is("testcmd", $sp->ledgerCmd(), "new: verify ledgerCmd set");


=pod

=item addSupporter

=cut

dies_ok { $sp->addSupporter({}) }
        "addSupporter: ledger_entity_id required";

my $id1;
lives_ok { $id1 = $sp->addSupporter({ ledger_entity_id => "Campbell-Peter" }); }
         "addSupporter: add works for minimal acceptable settings";

ok( (looks_like_number($id1) and $id1 > 0),
   "addSupporter: add works for minimal acceptable settings");

dies_ok  { $sp->addSupporter({ public_ack => 1, ledger_entity_id => "Whitman-Dick" }) }
         "addSupporter: display_name required";

my $drapperId;
lives_ok { $drapperId = $sp->addSupporter({ display_name => "Donald Drapper",
                               public_ack => 1, ledger_entity_id => "Whitman-Dick" }); }
         "addSupporter: public_ack set to true with a display_name given";

ok( (looks_like_number($drapperId) and $drapperId > $id1),
   "addSupporter: add works with public_ack set to true and a display_name given");

my $olsonId;

lives_ok { $olsonId = $sp->addSupporter({ display_name => "Peggy Olson",
                                          public_ack => 0, ledger_entity_id => "Olson-Margaret",
                                          email_address => 'olson@example.net',
                                          email_address_type => 'home' }); }
         "addSupporter: succeeds with email address";

ok( (looks_like_number($olsonId) and $olsonId > $drapperId),
   "addSupporter: add succeeded with email address added.");

my $val = $sp->dbh()->selectall_hashref("SELECT supporter_id, email_address_id " .
                                        "FROM supporter_email_address_mapping  " .
                                        "WHERE supporter_id = " . $sp->dbh->quote($olsonId, 'SQL_INTEGER'),
                                        'supporter_id');

ok((defined $val and defined $val->{$olsonId}{email_address_id} and $val->{$olsonId}{email_address_id} > 0),
   "addSuporter: email address mapping is created on addSupporter() w/ email address included");

=item addEmailAddress

=cut

$val = $sp->dbh()->selectall_hashref("SELECT id, name FROM address_type WHERE name = 'home'", 'name');

ok((defined $val and defined $val->{home}{id} and $val->{home}{id} > 0),
   "addSuporter/addEmailAddress: emailAddressType was added when new one given to addSupporter");

my $emailAddressTypeHomeId = $val->{home}{id};

dies_ok { $sp->addEmailAddress(undef, 'drapper@example.org', 'paypal'); }
        "addEmailAddress: dies for undefined id";
dies_ok { $sp->addEmailAddress("String", 'drapper@example.org', 'paypal'); }
        "addEmailAddress: dies for non-numeric id";
dies_ok { $sp->addEmailAddress($drapperId, undef, 'work') }
         "addEmailAddress: email address undefined fails";
dies_ok { $sp->addEmailAddress($drapperId, 'drapper@ex@ample.org', 'work') }
         "addEmailAddress: email address with extra @ fails to add.";

# Verify that the addressType wasn't added when the Email address is invalid
# and the address type did not already exist.

$val = $sp->dbh()->selectall_hashref("SELECT id, name FROM address_type WHERE name = 'work'", 'name');

ok((not defined $val or not defined $val->{'name'}),
   "addEmailAddress: type is not added with email address is bad");

my $drapperEmailId;

lives_ok { $drapperEmailId = $sp->addEmailAddress($drapperId, 'drapper@example.org', 'work') }
         "addEmailAdress: inserting a valid email address works";
ok((looks_like_number($drapperEmailId) and $drapperEmailId > 0), "addEmailAddress: id returned is sane.");

=item addAddressType

=cut

#  This test cheats a bit -- it assumes that the database is assigning serials starting with 1

ok($sp->addAddressType('work') > $emailAddressTypeHomeId,
   "addEmailAddress: verify addEmailAddress added the addressType underneath");

dies_ok { $sp->addAddressType(undef); } "addAddressType: dies for undef";

my $paypalPayerAddressType;

ok($paypalPayerAddressType = $sp->addAddressType("paypal payer"), "addAddressType: basic add works");

my $same;

ok($same = $sp->addAddressType("paypal payer"), "addAddressType: lookup works");

ok($same == $paypalPayerAddressType, "addAddressType: lookup returns same as the basic add");

=item addRequestType/getRequestType

=cut

dies_ok { $sp->addRequestType(undef); }
        "addRequestType: undef argument dies.";

my $tShirt0RequestTypeId;

ok( (not defined $sp->getRequestType('t-shirt-0')), "getRequestType: returns undef when not found");

lives_ok { $tShirt0RequestTypeId = $sp->addRequestType('t-shirt-0'); }
  "addRequestType: succeeds on add";

ok( (defined $tShirt0RequestTypeId and looks_like_number($tShirt0RequestTypeId) and $tShirt0RequestTypeId > 0),
    "addRequestType: id is a number");

my $testSameRequestType;

lives_ok { $testSameRequestType = $sp->addRequestType('t-shirt-0'); }
  "addRequestType: succeeds on add when type already exists";

is $tShirt0RequestTypeId, $testSameRequestType,
    "addRequestType: lookup first of existing request type before adding.";

=item addRequestConfigurations

=cut

dies_ok { $sp->addRequestConfigurations(undef, undef); } "addRequestConfigurations: undef type dies";

is_deeply({ $tShirt0RequestTypeId => {} },
          $sp->addRequestConfigurations('t-shirt-0'),
          "addRequestConfigurations: existing requestType with no configuration yields same");

my @sizeList = qw/LadiesS LadiesM LadiesL LadiesXL MenS MenM MenL MenXL Men2XL/;

my $tShirt0Data;

dies_ok { $sp->addRequestConfigurations('t-shirt-0', [ @sizeList, 'Men2XL']) }
  "addRequestConfigurations: dies with duplicate items on configuration list.";

is_deeply($sp->getRequestConfigurations('t-shirt-0'), undef,
          "addRequestConfigurations/getRequestConfigurations: add fails with duplicate in configuration list");

lives_ok { $tShirt0Data = $sp->addRequestConfigurations('t-shirt-0', \@sizeList) }
  "addRequestConfigurations: existing requestType with configuration runs.";

is( keys %{$tShirt0Data}, ($tShirt0RequestTypeId),
    "addRequestConfigurations: reuses same requestTypeId on add of configurations");

my $cnt = 0;
foreach my $size (@sizeList) {
  ok( (defined $tShirt0Data->{$tShirt0RequestTypeId}{$size} and
       looks_like_number($tShirt0Data->{$tShirt0RequestTypeId}{$size}) and
       $tShirt0Data->{$tShirt0RequestTypeId}{$size} > 0),
      sprintf "addRequestConfigurations: item %d added correctly", $cnt++);
}


=back

=item getRequestConfigurations

=cut

is undef, $sp->getRequestConfigurations(undef), "getRequestConfigurations: undef type returns undef";

is undef, $sp->getRequestConfigurations('Hae2Ohlu'), "getRequestConfigurations: non-existent type returns undef";

is_deeply $tShirt0Data,
          $sp->getRequestConfigurations('t-shirt-0'),
          "getRequestConfigurations: lookup of previously added items is same";


=back

=item Internal methods used only by the module itself.

=over

=item _verifyId

=cut

ok( $sp->_verifyId($drapperId), "_verifyId: id just added exists");

dies_ok { $sp->_verifyId(undef); } "_verifyId: dies for undefined id";
dies_ok { $sp->_verifyId("String") } "_verifyId: dies for non-numeric id";

# This is a hacky way to test this; but should work
ok(not ($sp->_verifyId($drapperId + 10)), "_verifyId: non-existent id is not found");

=back

=item Database weirdness tests

=cut

sub ResetDB($) {
  $_[0]->disconnect() if defined $_[0];
  my $tempDBH = get_test_dbh();
  my $tempSP = new Supporters($tempDBH, "testcmd");
  return ($tempDBH, $tempSP);
}

my($tempDBH, $tempSP) = ResetDB($dbh);
$tempDBH->do("DROP TABLE email_address;");

dies_ok { $tempSP->addSupporter({ display_name => "Roger Sterling",
                                  public_ack => 0, ledger_entity_id => "Sterling-Roger",
                                  email_address => 'sterlingjr@example.com',
                                  email_address_type => 'home' }) }
        "addSupporter: dies when email_address table does not exist & email adress given";

$tempDBH->disconnect; $tempDBH = reopen_test_dbh();

$val = $tempDBH->selectall_hashref("SELECT id FROM supporter;", 'id');

ok( (defined $val and reftype $val eq "HASH" and keys(%{$val}) == 0),
    "addSupporter: fails if email_address given but email cannot be inserted");


=back

=cut

$tempDBH->disconnect;

1;
###############################################################################
#
# Local variables:
# compile-command: "perl -c Supporters.t && cd ..; make clean; perl Makefile.PL && make &&  make test TEST_VERBOSE=1"
# End:

