# Before 'make install' is performed this script should be runnable with
# 'make test'. After 'make install' it should work as 'perl Supporters.t'

#########################

use strict;
use warnings;

use Test::More tests => 4;
use Test::Exception;

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

dies_ok(sub { $sp->addSupporter({}) }, "addSupporter: ledger_entity_id required");


$dbh->disconnect();

