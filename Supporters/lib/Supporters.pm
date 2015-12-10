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

use Scalar::Util qw(looks_like_number);

######################################################################

=begin new

Create new Supporters object.

Arguments:

=over

=item $dbh

   Scalar references for the database handle, already opened and pointing to
   the right database.

=item $ledgerCmd

   Scalar string that contains the main ledger command (without arguments) to
   run for looking up Supporter donation data.

=back

=cut

sub new ($$) {
  my $package = shift;
  my($dbh, $ledgerCmd) = @_;

  return bless({ dbh => $dbh, ledgerCmd => $ledgerCmd },
                 $package);
}
######################################################################

=begin dbh

Accessor method, returns the database handle currently used by this
Supporters object.

=cut

sub dbh ($) {
  return $_[0]->{dbh};
}
######################################################################

=begin ledgerCmd

Accessor method, returns the ledger command currently used by this Supporters
object.

=cut

sub ledgerCmd ($) {
  return $_[0]->{ledgerCmd};
}
######################################################################
sub addSupporter ($$) {
  my($this, $sp) = @_;

  die "ledger_entity_id required" unless defined $sp->{ledger_entity_id};

  $sp->{public_ack} = 0 if not defined $sp->{public_ack};

  if ($sp->{public_ack}) {
    die "display_name required if public_ack requested" unless defined $sp->{display_name};
  }
  my $sth = $this->dbh->prepare(
                      "INSERT INTO supporter(ledger_entity_id, display_name, public_ack)" .
                                    " values(?,                ?,            ?)");

  $sth->execute($sp->{ledger_entity_id}, $sp->{display_name}, $sp->{public_ack});
  my $id = $this->dbh->last_insert_id("","","","");
  $sth->finish();

  $this->addEmailAddress($id, $sp->{email_address}, $sp->{email_address_type})
    if defined $sp->{email_address};

  return $id;
}
######################################################################

=begin addAddressType

Adds an address type, or returns the existing one of that name if it already exists.

Arguments:

=over

=item $addressType

  Scalar string that contains the email address type.  die() is called if not defined.

=back

  Returns id of the address type.

=cut

sub addAddressType($$) {
  my($self, $type) = @_;

  die "addAddressType: type argument must be defined" if not defined $type;

  my $val = $self->dbh()->selectall_hashref("SELECT id, name FROM address_type WHERE name = '$type'", 'name');
  return $val->{$type}{id} if (defined $val and defined $val->{$type} and defined $val->{$type}{id});

  my $sth = $self->dbh->prepare("INSERT INTO address_type(name) VALUES(?)");

  $sth->execute($type);
  my $id = $self->dbh->last_insert_id("","","","");
  $sth->finish();

  return $id;
}

=begin addEmailAddress

Arguments:

=over

=item $id

   Valid supporter id number currently in the database.  die() will occur if
   the id number is not in the database already as a supporter id.

=item $emailAddress

   Scalar string that contains an email address.  die() will occur if the
   email address isn't properly formatted.

=item $emailAddressType

  Scalar string that contains the email address type.  This type will be
  created in the database if it does not already exist, so be careful.

=back

=cut

sub addEmailAddress($$$$) {
  my($self, $id, $emailAddress, $emailAddressType) = @_;

  die "addEmailAddress: invalid id, $id" unless $self->_verifyId($id);

  my $addressTypeId = $self->addAddressType($emailAddressType);

}
######################################################################

=head1 Non-Public Methods

These methods are part of the internal implementation are not recommended for
use outside of this module.

=over

=item _verifyId()

Parameters:

=over

=item $self: current object.

=item $id: A scalar numeric argument that is the to lookup


=back

Returns: scalar boolean, which is true iff. the $id is valid and already in the supporter database.


=cut


sub _verifyId($) {
  my($self, $id) = @_;

  die "_verifyId() called with a non-numeric id" unless defined $id and looks_like_number($id);

  my $val = $self->dbh()->selectall_hashref("SELECT id FROM supporter WHERE id = $id", 'id');
  return (defined $val and defined $val->{$id});

}


=back

=cut

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

###############################################################################
#
# Local variables:
# compile-command: "perl -c Supporters.pm"
# End:
