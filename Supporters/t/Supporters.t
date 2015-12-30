# Supporters.t                                            -*- Perl -*-
#   Basic unit tests for Supporters.pm
#########################

use strict;
use warnings;

use Test::More tests => 158;
use Test::Exception;

use Scalar::Util qw(looks_like_number reftype);
use POSIX qw(strftime);

# Yes, this may cause tests to fail if you run them near midnight. :)
my $today = strftime "%Y-%m-%d", gmtime;

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

my $sp;

dies_ok { $sp = new Supporters(undef, "test"); }
        "new: dies when dbh is undefined.";
dies_ok { $sp = new Supporters(bless({}, "Not::A::Real::Module"), "test"); }
        "new: dies when dbh is blessed into another module.";

$sp = new Supporters($dbh, "testcmd");

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

my $val = $sp->dbh()->selectall_hashref("SELECT donor_id, email_address_id " .
                                        "FROM donor_email_address_mapping  " .
                                        "WHERE donor_id = " . $sp->dbh->quote($olsonId, 'SQL_INTEGER'),
                                        'donor_id');

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

=item addPostalAddress

=cut

dies_ok { $sp->addPostalAddress(undef, "405 Madison Avenue\nNew York, NY 10000\nUSA", 'office'); }
        "addPostalAddress: dies for undefined id";
dies_ok { $sp->addPostalAddress("String", "405 Madison Avenue\nNew York, NY 10000\nUSA", 'office'); }
        "addPostalAddress: dies for non-numeric id";
dies_ok { $sp->addPostalAddress($drapperId, undef, 'work') }
         "addPostalAddress: postal address undefined fails";

# Verify that the addressType wasn't added when the Email address is invalid
# and the address type did not already exist.

$val = $sp->dbh()->selectall_hashref("SELECT id, name FROM address_type WHERE name = 'office'", 'name');

ok((not defined $val or not defined $val->{'name'}),
   "addPostalAddress: type is not added when other input paramaters are invalid");

my $drapperPostalId;

lives_ok { $drapperPostalId = $sp->addPostalAddress($drapperId,
                                                    "405 Madison Avenue\nNew York, NY 10000\nUSA", 'office'); }
         "addPostalAddress: addPostalAddress of a valid formatted_address works.";
ok((looks_like_number($drapperPostalId) and $drapperPostalId > 0), "addPostalAddress: id returned is sane.");

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

dies_ok { $sp->addRequestConfigurations('t-shirt-1', [ @sizeList, 'Men2XL']) }
  "addRequestConfigurations: dies with duplicate items on configuration list.";

is($sp->{__NESTED_TRANSACTION_COUNTER__}, 0, "addRequestConfigurations: assure proper beginWork/commit matching.");

is_deeply($sp->getRequestConfigurations('t-shirt-1'), undef,
          "addRequestConfigurations/getRequestConfigurations: add fails with undefined configuration list");

lives_ok { $tShirt0Data = $sp->addRequestConfigurations('t-shirt-0', \@sizeList) }
  "addRequestConfigurations: existing requestType with configuration runs.";

is( keys %{$tShirt0Data}, ($tShirt0RequestTypeId),
    "addRequestConfigurations: reuses same requestTypeId on add of configurations");

is($sp->{__NESTED_TRANSACTION_COUNTER__}, 0, "addRequestConfigurations: assure proper beginWork/commit matching.");

my $cnt = 0;
foreach my $size (@sizeList) {
  ok( (defined $tShirt0Data->{$tShirt0RequestTypeId}{$size} and
       looks_like_number($tShirt0Data->{$tShirt0RequestTypeId}{$size}) and
       $tShirt0Data->{$tShirt0RequestTypeId}{$size} > 0),
      sprintf "addRequestConfigurations: item %d added correctly", $cnt++);
}


=item addRequest

=cut

dies_ok { $sp->addRequest({}); }  "addRequest: dies if donorId not specified.";

dies_ok { $sp->addRequest({ donorId => $drapperId }); }
        "addRequest: dies if requestTypeId / requestType not specified.";

dies_ok { $sp->addRequest({ donorId => 0, requestTypeId => $tShirt0RequestTypeId }); }
        "addRequest: dies if donorId invalid.";

dies_ok { $sp->addRequest({ donorId => $drapperId, requestTypeId => 0 }); }
        "addRequest: dies if requestTypeId invalid.";

is($sp->{__NESTED_TRANSACTION_COUNTER__}, 0, "addRequest: assure proper beginWork/commit matching.");

my $emailListRequestId;

lives_ok { $emailListRequestId =
             $sp->addRequest({ donorId => $drapperId, requestType => "join-announce-email-list" }); }
        "addRequest: succeeds with a requestType but no configuration parameter.";

ok( (defined $emailListRequestId and looks_like_number($emailListRequestId) and $emailListRequestId > 0),
    "addRequest: id returned on successful addRequest() is a number");

my $joinEmailListRequestId = $sp->getRequestType("join-announce-email-list");
ok((defined $joinEmailListRequestId and looks_like_number($joinEmailListRequestId) and $joinEmailListRequestId > 0),
   "addRequest: underlying call to addRequestType works properly, per getRequestType");

my $tshirtSmallRequestId;

lives_ok { $tshirtSmallRequestId =
             $sp->addRequest({ donorId => $drapperId, requestType => "t-shirt-small-only",
                               requestConfiguration => 'Small',
                               notes => 'he probably needs a larger size but this shirt has none'}); }
        "addRequest: succeeds with a requestType and requestConfiguration and a note.";

ok( (defined $tshirtSmallRequestId and looks_like_number($tshirtSmallRequestId) and $tshirtSmallRequestId > 0),
    "addRequest: successful call returns an integer id.");

my $tShirt0RequestId;
lives_ok { $tShirt0RequestId =
             $sp->addRequest({ donorId => $drapperId, requestTypeId => $tShirt0RequestTypeId,
                               requestConfigurationId => $tShirt0Data->{$tShirt0RequestTypeId}{'MenL'} }); }
        "addRequest: succeeds with a requestTypeId and requestConfigurationId with no a note.";

ok( (defined $tShirt0RequestId and looks_like_number($tShirt0RequestId) and $tShirt0RequestId > 0),
    "addRequest: another successful call returns an integer id.");


=item fulfillRequest

=cut


my $fulfillRequestId;


dies_ok { $fulfillRequestId = $sp->fulfillRequest( { requestType => "t-shirt-small-only", who => 'joe',
                                                    how => "in-person delivery" }); }
     "fulfillRequest: dies if donorId not specified";

dies_ok { $fulfillRequestId = $sp->fulfillRequest( { donorId => $drapperId + 1000,
                                            requestType => "t-shirt-small-only", who => 'joe',
                                                    how => "in-person delivery" }); }
     "fulfillRequest: dies if donorId not found in database";

dies_ok { $fulfillRequestId = $sp->fulfillRequest( { donorId => $drapperId,  who => 'joe',
                                                    how => "in-person delivery" }); }
     "fulfillRequest: dies if requestType not specified";

dies_ok { $fulfillRequestId = $sp->fulfillRequest( { donorId => $drapperId,
                                                   requestType => "t-shirt-small-only",
                                                    how => "in-person delivery" }); }
     "fulfillRequest: dies if who not specified";

lives_ok { $fulfillRequestId = $sp->fulfillRequest( { donorId => $drapperId,
                                            requestType => "t-shirt-small-only", who => 'joe',
                                                    how => "in-person delivery" }); }
     "fulfillRequest: succeeds for existing request";

ok( (defined $fulfillRequestId and looks_like_number($fulfillRequestId) and $fulfillRequestId > 0),
    "fulfillRequest: id returned on successful fulfillRequest() is a number");

lives_ok { $val = $sp->dbh()->selectall_hashref("SELECT id, date, who, how, request_id FROM fulfillment", 'id'); }
         "fulfillRequest: sql command in  database for entry succeeds.";
is_deeply($val, { $fulfillRequestId => { id => $fulfillRequestId, date => $today,
                                         how => 'in-person delivery', who => 'joe',
                                         request_id => $tshirtSmallRequestId } },
          "fulfillRequest: databse entry from successful return is correct");

my $badFR;
lives_ok { $badFR = $sp->fulfillRequest( { donorId => $drapperId, who => 'john',
                                                   requestType => "does-not-exist",
                                                    how => "in-person delivery" }); }
     "fulfillRequest: attempt to fulfill a request never made does not die...";

ok( (not defined $badFR),
     "fulfillRequest: ... but, rather, returns undef.");

is($sp->getRequestType("does-not-exist"), undef,
     "fulfillRequest: requestType not created when fulfillRequest fails.");


my $lookedUpFulfillmentId;

lives_ok { $lookedUpFulfillmentId = $sp->fulfillRequest( { donorId => $drapperId,
                                            requestType => "t-shirt-small-only", who => 'peggy',
                                                    how => "left in his office." }); }
     "fulfillRequest: attempt to fulfill an already-fulfill request does not die ...";

is($lookedUpFulfillmentId, $fulfillRequestId,
     "fulfillRequest: ... but, rather, returns the same value from the previous fulfillRequest() call.");

=item getRequest

=cut

dies_ok { $sp->getRequest({} ); }  "getRequest: dies if donorId not specified.";

dies_ok { $sp->getRequest({ donorId => 0, requestType => "t-shirt-small-only" }); } "getRequest: dies if donorId invalid.";

dies_ok { $sp->getRequest({ donorId => $drapperId, requestType => undef}); }
        "getRequest: dies if requestType not specified.";

my $tt;
lives_ok { $tt = $sp->getRequest({ donorId => $drapperId, requestType => 'this-one-is-not-there' }); }
        "getRequest: returns normally with non-existent request.";

is($tt, undef, "getRequest: returns undef for valid supporter and on-existent request.");

lives_ok { $tt = $sp->getRequest({donorId => $drapperId, requestType => 't-shirt-small-only' }); }
         "getRequest: succeeds with valid parameters.";

is($tt->{requestType}, 't-shirt-small-only', "getRequest: requestType is correct.");
is($tt->{fulfillDate}, $today, "getRequest: fulfilled request is today.");
is($tt->{requestDate}, $today, "getRequest: request date is today.");
is($tt->{requestConfiguration}, 'Small', "getRequest: configuration is correct.");
is($tt->{notes}, 'he probably needs a larger size but this shirt has none',
   "getRequest: notes are correct.");

lives_ok { $tt = $sp->getRequest({donorId => $drapperId, requestType => 't-shirt-0' } ); }
         "getRequest: succeeds with valid parameters.";

is($tt->{requestType}, 't-shirt-0', "getRequest: requestType is correct.");
is($tt->{requestDate}, $today, "getRequest: request date is today.");
is($tt->{requestConfiguration}, 'MenL', "getRequest: configuration is correct.");
is($tt->{notes}, undef,    "getRequest: notes are undef when null in database.");

lives_ok { $tt = $sp->getRequest({ donorId => $drapperId,  requestType => "join-announce-email-list" }); }
         "getRequest: succeeds with valid parameters.";

is($tt->{requestType}, "join-announce-email-list", "getRequest: requestType is correct.");
is($tt->{requestDate}, $today, "getRequest: request date is today.");
is($tt->{requestConfiguration}, undef, "getRequest: configuration is undefined when there is none.");
is($tt->{notes}, undef,    "getRequest: notes are undef when null in database.");


=item getRequestConfigurations

=cut

my $tShirtSmallOnlyRequestId;
lives_ok { $tShirtSmallOnlyRequestId = $sp->getRequestType('t-shirt-small-only'); }
  "addRequest: added request type";

my $tShirtSmallOnlyData = $sp->getRequestConfigurations('t-shirt-small-only');

is(scalar keys %{$tShirtSmallOnlyData->{$tShirtSmallOnlyRequestId}}, 1,
   "addRequest: just one configuration added correctly");

ok( (defined $tShirtSmallOnlyData->{$tShirtSmallOnlyRequestId}{'Small'} and
       looks_like_number($tShirtSmallOnlyData->{$tShirtSmallOnlyRequestId}{'Small'}) and
       $tShirtSmallOnlyData->{$tShirtSmallOnlyRequestId}{'Small'} > 0),
      "addRequest: configuration added correctly");

is undef, $sp->getRequestConfigurations(undef), "getRequestConfigurations: undef type returns undef";

is undef, $sp->getRequestConfigurations('Hae2Ohlu'), "getRequestConfigurations: non-existent type returns undef";

is_deeply $tShirt0Data,
          $sp->getRequestConfigurations('t-shirt-0'),
          "getRequestConfigurations: lookup of previously added items is same";

=item setPreferredEmailAddress/getPreferredEmailAddress

=cut

dies_ok { $sp->setPreferredEmailAddress(undef, 'drapper@example.org'); }
        "setPreferredEmailAddress: dies for undefined id";
dies_ok { $sp->setPreferredEmailAddress("String", 'drapper@example.org'); }
        "setPreferredEmailAddress: dies for non-numeric id";
dies_ok { $sp->setPreferredEmailAddress($drapperId, undef) }
         "setPreferredEmailAddress: email address undefined fails";
dies_ok { $sp->setPreferredEmailAddress($drapperId, 'drapper@ex@ample.org') }
         "setPreferredEmailAddress: email address with extra @ fails to add.";

dies_ok { $sp->getPreferredEmailAddress(undef); }
        "getPreferredEmailAddress: dies for undefined id";
dies_ok { $sp->getPreferredEmailAddress("String"); }
        "getPreferredEmailAddress: dies for non-numeric id";

my $ret;

lives_ok { $ret = $sp->setPreferredEmailAddress($drapperId, 'drapper@example.com') }
         "setPreferredEmailAddress: email address not found in database does not die....";
is($ret, undef, "setPreferredEmailAddress: ....but returns undef");

lives_ok { $ret = $sp->getPreferredEmailAddress($drapperId) }
         "getPreferredEmailAddress: no preferred does not die....";
is($ret, undef, "getPreferredEmailAddress: ....but returns undef");

lives_ok { $ret = $sp->setPreferredEmailAddress($drapperId, 'drapper@example.org') }
         "setPreferredEmailAddress: setting preferred email address succeeds....";

ok( (defined $ret and looks_like_number($ret) and $ret == $drapperEmailId),
      "setPreferredEmailAddress: ... and returns correct email_address_id on success");

is($sp->{__NESTED_TRANSACTION_COUNTER__}, 0, "setPreferredEmailAddress: assure proper beginWork/commit matching.");

lives_ok { $ret = $sp->getPreferredEmailAddress($drapperId) }
         "getPreferredEmailAddress: lookup of known preferred email address succeeds... ";
is($ret, 'drapper@example.org', "getPreferredEmailAddress: ....and returns the correct value.");

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


$sp = undef;

sub ResetDB($) {
  $_[0]->disconnect() if defined $_[0];
  my $tempDBH = get_test_dbh();
  my $tempSP = new Supporters($tempDBH, "testcmd");
  return ($tempDBH, $tempSP);
}

my($tempDBH, $tempSP) = ResetDB($dbh);

=item _getOrCreateRequestType

=cut

dies_ok { $tempSP->_getOrCreateRequestType({ }); }
   "_getOrCreateRequestType: dies on empty hash";

dies_ok { $tempSP->_getOrCreateRequestType({ requestTypeId => "NoStringsPlease" }); }
   "_getOrCreateRequestType: dies for string request id";

dies_ok { $tempSP->_getOrCreateRequestType({ requestTypeId => 0 }); }
   "_getOrCreateRequestType: dies for non-existant requestTypeId";

my %hh = ( requestType => 'test-request' );
lives_ok { $tempSP->_getOrCreateRequestType(\%hh); }
   "_getOrCreateRequestType: succeeds with just requestType";

my $rr;
lives_ok { $rr = $tempSP->getRequestType("test-request"); }
   "_getOrCreateRequestType: lookup of a request works after _getOrCreateRequestType";

is_deeply(\%hh, { requestTypeId => $rr },
   "_getOrCreateRequestType: lookup of a request works after _getOrCreateRequestType");

%hh = ( requestTypeId => $rr, requestType => 'this-arg-matters-not' );

lives_ok { $tempSP->_getOrCreateRequestType(\%hh); }
   "_getOrCreateRequestType: lookup of existing requestType suceeds.";

is_deeply(\%hh, { requestTypeId => $rr },
   "_getOrCreateRequestType: deletes requestType if both are provided.");

dies_ok { $tempSP->_lookupRequestTypeById(undef); }
        "_lookupRequestTypeById: dies for undefined requestTypeId";

dies_ok { $tempSP->_lookupRequestTypeById("NoStringsPlease"); }
        "_lookupRequestTypeById: dies for a string requestTypeId";

ok( (not $tempSP->_lookupRequestTypeById(0)), "_lookupRequestTypeById: returns false for id lookup for 0");

# Assumption here: that id number one more than the last added would never be in db.
ok( (not $tempSP->_lookupRequestTypeById($rr + 1)),
    "_lookupRequestTypeById: returns false for id one greater than last added");

is($tempSP->_lookupRequestTypeById($rr), "test-request",
    "_lookupRequestTypeById: returns proper result for id known to be in database");


=item _getOrCreateRequestConfiguration

=cut

dies_ok { $tempSP->_getOrCreateRequestConfiguration({ }); }
   "_getOrCreateRequestConfiguration: dies on empty hash";

dies_ok { $tempSP->_getOrCreateRequestConfiguration({ requestConfigurationId => "NoStringsPlease" }); }
   "_getOrCreateRequestConfiguration: dies for string requestConfigurationId";

dies_ok { $tempSP->_getOrCreateRequestConfiguration({ requestConfigurationId => 0 }); }
   "_getOrCreateRequestConfiguration: dies for non-existant requestConfigurationId";

dies_ok { $tempSP->_getOrCreateRequestConfiguration({ requestTypeId => "NoStringsPlease" }); }
   "_getOrCreateRequestConfiguration: dies for string request id";

dies_ok { $tempSP->_getOrCreateRequestConfiguration({ requestTypeId => 0 }); }
   "_getOrCreateRequestConfiguration: dies for non-existant requestTypeId";

dies_ok { $tempSP->_getOrCreateRequestConfiguration({ requestTypeId => $rr,
                                                      requestConfigurationId => "NoStringsPlease" }); }
   "_getOrCreateRequestConfiguration: dies for string requestConfigurationId with valid requestTypeId";

%hh = ( requestConfiguration => 'test-request-config' );
dies_ok { $tempSP->_getOrCreateRequestConfiguration(\%hh); }
   "_getOrCreateRequestConfiguration: fails with just requestConfiguration.";

$val = $tempSP->dbh()->selectall_hashref("SELECT id, description FROM request_configuration", 'description');

ok((defined $val and (keys(%$val) == 0)),
   "_getOrCreateRequestConfiguration: no request_configuration record added for failed attempts");

%hh = ( requestTypeId => $rr, requestConfiguration => 'test-request-config' );
lives_ok { $tempSP->_getOrCreateRequestConfiguration(\%hh); }
   "_getOrCreateRequestConfiguration: succeeds with requestConfiguration and requestType";

my($fullConfig, $rc);
lives_ok { $fullConfig =  $tempSP->getRequestConfigurations('test-request'); }
   "getRequestConfigurations: succeeds after successful _getOrCreateRequestConfiguration()";

$rc = $fullConfig->{$rr}{'test-request-config'};

is_deeply(\%hh, { requestTypeId => $rr, requestConfigurationId => $rc },
   "_getOrCreateRequestConfiguration: modification of paramater argument was correct after successful add");

is_deeply $fullConfig,
  { 1 => { 'test-request-config' => 1 } },
   "_getOrCreateRequestConfiguration: lookup of a request configuration works after _getOrCreateRequestConfiguration";

%hh = (requestTypeId => $rr, requestConfiguration => "test-request-config");
lives_ok { $tempSP->_getOrCreateRequestConfiguration(\%hh); }
   "_getOrCreateRequestConfiguration: looks up one previously added by _getOrCreateRequestConfiguration()";

is_deeply(\%hh, { requestTypeId => $rr, requestConfigurationId => $rc },
   "_getOrCreateRequestConfiguration: lookup of a request works after _getOrCreateRequestConfiguration");

%hh = ( requestTypeId => $rr, requestConfigurationId => $rc, requestConfiguration => 'this-arg-matters-not' );

lives_ok { $tempSP->_getOrCreateRequestConfiguration(\%hh); }
   "_getOrCreateRequestConfiguration: lookup of existing requestConfigurationId succeeds, ignoring requestConfiguration parameter.";

is_deeply(\%hh, { requestTypeId => $rr, requestConfigurationId => $rc },
   "_getOrCreateRequestConfiguration: deletes requestTypeConfiguration if both are provided.");

=back

=item Database weirdness tests

=cut

($tempDBH, $tempSP) = ResetDB($tempDBH);
$tempDBH->do("DROP TABLE email_address;");

dies_ok { $tempSP->addSupporter({ display_name => "Roger Sterling",
                                  public_ack => 0, ledger_entity_id => "Sterling-Roger",
                                  email_address => 'sterlingjr@example.com',
                                  email_address_type => 'home' }) }
        "addSupporter: dies when email_address table does not exist & email adress given";

$tempDBH->disconnect; $tempDBH = reopen_test_dbh();

$val = $tempDBH->selectall_hashref("SELECT id FROM donor;", 'id');

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

