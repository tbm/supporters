# Supporters.t                                            -*- Perl -*-
#   Basic unit tests for Supporters.pm
#########################

use strict;
use warnings;

use Test::More tests => 25;
use Test::Exception;

use Scalar::Util qw(looks_like_number);

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

=item addEmailAddress

=cut

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

my $val = $sp->dbh()->selectall_hashref("SELECT id FROM address_type WHERE name = 'work'", 'id');

ok((not defined $val or not defined $val->{'id'}),
   "addEmailAddress: type is not added with email address is bad");

my $drapperEmailId;

lives_ok { $drapperEmailId = $sp->addEmailAddress($drapperId, 'drapper@example.org', 'work') }
         "addEmailAdress: inserting a valid email address works";
ok((looks_like_number($drapperEmailId) and $drapperEmailId > 0), "addEmailAddress: id returned is sane.");

=item addAddressType

=cut

#  This test cheats a bit -- it assumes that the database is assigning serials starting with 1

ok($sp->addAddressType('work') == 1,
   "addEmailAddress: verify addEmailAddress added the addressType underneath");

dies_ok { $sp->addAddressType(undef); } "addAddressType: dies for undef";

my $paypalPayerAddressType;

ok($paypalPayerAddressType = $sp->addAddressType("paypal payer"), "addAddressType: basic add works");

my $same;

ok($same = $sp->addAddressType("paypal payer"), "addAddressType: lookup works");

ok($same == $paypalPayerAddressType, "addAddressType: lookup returns same as the basic add");


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

=pod

=back

=back

=cut

$dbh->disconnect();
###############################################################################
#
# Local variables:
# compile-command: "perl -c Supporters.t"
# End:

