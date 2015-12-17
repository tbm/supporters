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
use Mail::RFC822::Address;

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
  my($self, $sp) = @_;

  die "ledger_entity_id required" unless defined $sp->{ledger_entity_id};

  $sp->{public_ack} = 0 if not defined $sp->{public_ack};

  if ($sp->{public_ack}) {
    die "display_name required if public_ack requested" unless defined $sp->{display_name};
  }
  $self->_beginWork;
  my $sth = $self->dbh->prepare(
                      "INSERT INTO supporter(ledger_entity_id, display_name, public_ack)" .
                                    " values(?,                ?,            ?)");

  $sth->execute($sp->{ledger_entity_id}, $sp->{display_name}, $sp->{public_ack});
  my $id = $self->dbh->last_insert_id("","","","");
  $sth->finish();

  $self->addEmailAddress($id, $sp->{email_address}, $sp->{email_address_type})
    if defined $sp->{email_address};

  $self->_commit;
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
######################################################################

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

Returns the id value of the email_address entry.

=cut

sub addEmailAddress($$$$) {
  my($self, $id, $emailAddress, $emailAddressType) = @_;

  die "addEmailAddress: invalid id, $id" unless $self->_verifyId($id);

  die "addEmailAddress:: invalid email address, $emailAddressType"
    unless defined $emailAddressType and Mail::RFC822::Address::valid($emailAddress);

  $self->_beginWork();

  my $addressTypeId = $self->addAddressType($emailAddressType);

  my $sth = $self->dbh->prepare("INSERT INTO email_address(email_address, type_id, date_encountered)" .
                                "VALUES(                    ?,            ?,       date('now'))");

  $sth->execute($emailAddress, $addressTypeId);
  my $addressId = $self->dbh->last_insert_id("","","","");
  $sth->finish();

  my $sth = $self->dbh->prepare("INSERT INTO supporter_email_address_mapping" .
                                      "(supporter_id, email_address_id) " .
                                "VALUES(           ?, ?)");
  $sth->execute($id, $addressId);
  $sth->finish();

  $self->_commit();

  return $addressId;
}
######################################################################

=begin getRequestType

Arguments:

=over

=item type

   A string describing the request.

=back

Returns the id value of the request_type entry.  undef is returned if there
is no request of that type.

=cut

sub getRequestType($$) {
  my($self, $type) = @_;

  return undef if not defined $type;
  my $val = $self->dbh()->selectall_hashref("SELECT id, type FROM request_type WHERE type = '$type'", 'type');
  return $val->{$type}{id} if (defined $val and defined $val->{$type} and defined $val->{$type}{id});
  return undef;
}
######################################################################

=begin addRequestType

Arguments:

=over

=item type

   A string describing the request.  die()'s if not defined.

=back

Returns the id value of the request_type entry.  If the type already exists,
it is simply returned.

=cut

sub addRequestType($$) {
  my($self, $requestType) = @_;

  die "addRequestType: undefined request type." unless defined $requestType;

  my $requestId = $self->getRequestType($requestType);
  return $requestId if (defined $requestId);

  $self->_beginWork();

  my $sth = $self->dbh->prepare("INSERT INTO request_type(type) VALUES(?)");

  $sth->execute($requestType);
  $requestId = $self->dbh->last_insert_id("","","","");
  $sth->finish();
  $self->_commit();
  return $requestId;
}
######################################################################

=begin getRequestConfigurations

Arguments:

=over

=item type

   A string describing the request_type.

=back

Returns undef if the request_type is not found in the database.  If the reuqest type is 
is no request of that type.

=cut

sub getRequestConfigurations($$) {
  my($self, $type) = @_;

  return undef if not defined $type;
  my $typeId = $self->getRequestType($type);
  return undef if not defined $typeId;

  my %descriptions;
  my $dbData =
    $self->dbh()->selectall_hashref("SELECT description, id FROM request_configuration " .
                                    "WHERE request_type_id = " . $self->dbh->quote($typeId, 'SQL_INTEGER'),
                                    'description');
  foreach my $description (keys %$dbData) {
    $descriptions{$description} = $dbData->{$description}{id};
  }
  return { $typeId => \%descriptions };
}
######################################################################

=begin addRequestConfigurations

Arguments:

=over

=item type

   A string describing the request type.  This will be created if it does not
   already exist, so be careful.

=item descriptionListRef

   A list reference to the list of configuration descriptions to associate
   with this requestId.  Duplicates aren't permitted in this list, and
   die()'s if duplicates exist.

=back

Returns a hash in the form of:

  $requestTypeId => { description => $requestConfigurationId }

=cut

sub addRequestConfigurations($$$) {
  my($self, $requestType, $descriptionListRef) = @_;

  die "addRequestConfigurations: undefined request type." unless defined $requestType;

  $self->_beginWork();

  my $requestId = $self->addRequestType($requestType);

  die "addRequestConfigurations: unable to create request configurations"
    unless defined $requestType;

  my %descriptions;
  my $sth = $self->dbh->prepare("INSERT INTO request_configuration(request_type_id, description) " .
                                                           "VALUES(?,               ?)");
  foreach my $description (@{$descriptionListRef}) {
    if (defined $descriptions{$description}) {
      $self->dbh->rollback();
      die "addRequestConfigurations: attempt to create duplicate request_configuration \"$description\" for requestType, \"$requestType\"";
    }
    $sth->execute($requestId, $description);
    $descriptions{$description} = $self->dbh->last_insert_id("","","","");
  }
  $sth->finish();
  $self->_commit();
  return { $requestId => \%descriptions };
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


sub _verifyId($$) {
  my($self, $id) = @_;

  die "_verifyId() called with a non-numeric id" unless defined $id and looks_like_number($id);

  my $val = $self->dbh()->selectall_hashref("SELECT id FROM supporter WHERE id = $id", 'id');
  return (defined $val and defined $val->{$id});

}

=item _beginWork()

Parameters:

=over

=item $self: current object.

=back

Returns: None.

This method is a reference counter to keep track of nested begin_work()/commit().


=cut

my $NESTED_TRANSACTION_COUNTER = 0;

sub _beginWork($) {
  my($self) = @_;

  die "_beginWork: Mismatched begin_work/commit pair in API implementation"  if ($NESTED_TRANSACTION_COUNTER < 0);

  $self->dbh->begin_work() if ($NESTED_TRANSACTION_COUNTER++ == 1);
}

=item _commit()

Parameters:

=over

=item $self: current object.

=back

Returns: None.

This method is a reference counter to keep track of nested begin_work()
transactions to verify we don't nest $self->dbh->begin_work()

=cut

sub _commit($) {
  my($self) = @_;

  die "_commit: Mismatched begin_work/commit pair in API implementation"  if ($NESTED_TRANSACTION_COUNTER <= 0);

  $self->dbh->commit() if ($NESTED_TRANSACTION_COUNTER-- == 0);
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
