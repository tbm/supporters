package Supporters;

use 5.020002;
use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Supporters ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = '0.02';

######################################################################
sub new ($$) {
  my $package = shift;
  my($dbh, $ledgerCmd) = @_;

  return bless({ dbh => $dbh, ledgerCmd => $ledgerCmd },
                 $package);
}
######################################################################
sub dbh ($) {
  return $_[0]->{dbh};
}
######################################################################
sub ledgerCmd ($) {
  return $_[0]->{ledgerCmd};
}


1;
__END__

=head1 NAME

Supporters - Simple database of supporters of an organation.

=head1 SYNOPSIS

  use Supporters;

=head1 DESCRIPTION

Supporters is an extremely lightweight alternative to larger systems like
CiviCRM to manage a database of Supporters.  The module assumes a setup that
works with Ledger-CLI to find the actual amounts donated.

=head2 EXPORT

None by default.

=head1 AUTHOR

Bradley M. Kuhn, E<lt>bkuhn@ebb.org<gt>

=head1 COPYRIGHT AND LICENSE

See COPYRIGHT.md and LICENSE.md in the main distribution of this software.

License: AGPLv3-or-later

=cut
