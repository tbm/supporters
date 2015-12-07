# Before 'make install' is performed this script should be runnable with
# 'make test'. After 'make install' it should work as 'perl Supporters.t'

#########################

use strict;
use warnings;

use Test::More tests => 3;
BEGIN { use_ok('Supporters') };

=pod

Initial tests to verify creation of objects

=cut

require 't/CreateTestDB.pl';

my $dbh = get_test_dbh();

my $supporters = new Supporters($dbh, "testcmd");

is($dbh, $supporters->dbh());
is("testcmd", $supporters->ledgerCmd());

$dbh->disconnect();

