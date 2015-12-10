# Supporters.t                                            -*- Perl -*-
#   Basic unit tests for Supporters.pm
#########################

use strict;
use warnings;

use Test::More tests => 15;
use Test::Exception;

use Scalar::Util qw(looks_like_number);

BEGIN { use_ok('Supporters') };

=pod

Initial tests to verify creation of objects

=cut

require 't/CreateTestDB.pl';

my $dbh = get_test_dbh();

my $sp = new Supporters($dbh, "testcmd");

is($dbh, $sp->dbh(), "new: verify dbh set");
is("testcmd", $sp->ledgerCmd(), "new: verify ledgerCmd set");


=pod

Test adding a supporter to the database.

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

my $id2;
lives_ok { $id2 = $sp->addSupporter({ display_name => "Donald Drapper",
                               public_ack => 1, ledger_entity_id => "Whitman-Dick" }); }
         "addSupporter: public_ack set to true with a display_name given";

ok( (looks_like_number($id2) and $id2 > $id1),
   "addSupporter: add works with public_ack set to true and a display_name given");

=pod

Tests for internal methods:

=over


=item _verifyId tests

=cut

ok( $sp->_verifyId($id2), "_verifyId: id just added exists");

dies_ok { $sp->_verifyId(undef); } "_verifyId: dies for undefined id";
dies_ok { $sp->_verifyId("String") } "_verifyId: dies for non-numeric id";

# This is a hacky way to test this; but should work
ok(not ($sp->_verifyId($id2 + 10)), "_verifyId: non-existent id is not found");

dies_ok { $sp->_addEmailAdress(undef, 'drapper@example.org', 'paypal'); }
        "_addEmailAdress: dies for undefined id";
dies_ok { $sp->_addEmailAdress("String", 'drapper@example.org', 'paypal'); }
        "_addEmailAdress: dies for non-numeric id";

=pod

=back

=cut

$dbh->disconnect();
###############################################################################
#
# Local variables:
# compile-command: "perl -c Supporters.t"
# End:

