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

use Scalar::Util qw(looks_like_number blessed);
use Mail::RFC822::Address;
use Carp qw(confess);

######################################################################

=begin new

Create new Supporters object.

Arguments:

=over

=item $dbh

   Scalar references for the database handle from the L<DBI>, already opened
   and pointing to the right database.  This class will take over and control
   the DBI object after C<new()> completes.

=item $ledgerCmd

   Scalar string that contains the main ledger command (without arguments) to
   run for looking up Supporter donation data.

=back

=cut

sub new ($$) {
  my $package = shift;
  my($dbh, $ledgerCmd) = @_;

  my $self = bless({ dbh => $dbh, ledgerCmd => $ledgerCmd },
                   $package);

  die "new: first argument must be a database handle"
    unless (defined $dbh and blessed($dbh) =~ /DBI/);

  # Turn off AutoCommit, and create our own handler that resets the
  # begin_work/commit reference counter.
  $dbh->{RaiseError} = 0;
  $dbh->{HandleError} = sub {
    $self->{__NESTED_TRANSACTION_COUNTER__} = 0;
    confess $_[0];
  };
  $self->{__NESTED_TRANSACTION_COUNTER__} = 0;
  return $self;
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

  die "addEmailAddress: invalid email address, $emailAddressType"
    unless defined $emailAddressType and Mail::RFC822::Address::valid($emailAddress);

  $self->_beginWork();

  my $addressTypeId;
  eval {
    $addressTypeId = $self->addAddressType($emailAddressType);
  };
  if ($@ or not defined $addressTypeId) {
    my $err = $@;
    $err = "addEmailAddress: unable to addAddressType"  if (not defined $err);
    $self->_rollback();
    die $@ if $@;
  }
  my $sth = $self->dbh->prepare("INSERT INTO email_address(email_address, type_id, date_encountered)" .
                                "VALUES(                    ?,            ?,       date('now'))");

  $sth->execute($emailAddress, $addressTypeId);
  my $addressId = $self->dbh->last_insert_id("","","","");
  $sth->finish();

  $sth = $self->dbh->prepare("INSERT INTO supporter_email_address_mapping" .
                                      "(supporter_id, email_address_id) " .
                                "VALUES(           ?, ?)");
  $sth->execute($id, $addressId);
  $sth->finish();

  $self->_commit();

  return $addressId;
}
######################################################################

=begin setPreferredEmailAddress

Arguments:

=over

=item $supporterId

   Valid supporter id number currently in the database.  die() will occur if
   the id number is not in the database already as a supporter id.


=item $emailAddress

   Scalar string that contains an email address.  undef is returned if the
   email address is not already in the database for this supporter.

=back

Returns the email_address_id of the preferred email address.  undef can be
returned; it means the preferred email address wasn't selected for some reason.

=cut

sub setPreferredEmailAddress($$$) {
  my($self, $supporterId, $emailAddress) = @_;

  die "setPreferredEmailAddress: invalid supporter id, $supporterId" unless $self->_verifyId($supporterId);
  die "setPreferredEmailAddress: email address not defined" unless defined $emailAddress;
  die "setPreferredEmailAddress: invalid email address, $emailAddress"
    unless Mail::RFC822::Address::valid($emailAddress);

  my $ems = $self->dbh()->selectall_hashref("SELECT ea.email_address, ea.id, sem.preferred " .
                                            "FROM email_address ea, supporter_email_address_mapping sem " .
                                            "WHERE ea.id = sem.email_address_id AND ".
                                            "sem.supporter_id = " . $self->dbh->quote($supporterId, 'SQL_INTEGER'),
                                            'email_address');
  # Shortcut: it was already set
  return $ems->{$emailAddress}{id} if (defined $ems->{$emailAddress} and $ems->{$emailAddress}{preferred});

  my $anotherPreferred = 0;
  my $emailAddressId;
  # Iterate over email addresses, finding if any were preferred before, and finding outs too.
  foreach my $em (keys %{$ems}) {
    $anotherPreferred = 1 if $ems->{$em}{preferred};
    $emailAddressId = $ems->{$em}{id} if $em eq $emailAddress;
  }
  return undef if not defined $emailAddressId;

  $self->_beginWork();
  if ($anotherPreferred) {
    $self->dbh->do("UPDATE supporter_email_address_mapping " .
                     "SET preferred = " . $self->dbh->quote(0, 'SQL_BOOLEAN') . " " .
                     "WHERE supporter_id = " . $self->dbh->quote($supporterId, 'SQL_INTEGER'));
  }
  $self->dbh->do("UPDATE supporter_email_address_mapping " .
                 "SET preferred = " . $self->dbh->quote(1, 'SQL_BOOLEAN') . " " .
                 "WHERE email_address_id = " . $self->dbh->quote($emailAddressId, 'SQL_INTEGER'));
  $self->_commit;
  return $emailAddressId;
}
######################################################################

=begin getPreferredEmailAddress

Arguments:

=over

=item $supporterId

   Valid supporter id number currently in the database.  die() will occur if
   the id number is not in the database already as a supporter id.


=item $emailAddress

   Scalar string that contains an email address.  undef is returned if the
   email address is not already in the database for this supporter.

=back

Returns the email_address_id of the preferred email address.  undef can be
returned; it means the preferred email address wasn't selected for some reason.

=cut

sub getPreferredEmailAddress($$) {
  my($self, $supporterId) = @_;

  die "setPreferredEmailAddress: invalid supporter id, $supporterId" unless $self->_verifyId($supporterId);

  my $ems = $self->dbh()->selectall_hashref("SELECT email_address FROM email_address em, supporter_email_address_mapping sem " .
                                            "WHERE preferred AND sem.email_address_id = em.id AND " .
                                            "sem.supporter_id = " . $self->dbh->quote($supporterId, 'SQL_INTEGER'),
                                            'email_address');
  my $rowCount = scalar keys %{$ems};
  die "setPreferredEmailAddress: DATABASE INTEGRITY ERROR: more than one email address is preferred for supporter, \"$supporterId\""
    if $rowCount > 1;

  if ($rowCount != 1) {
    return undef;
  } else {
    my ($emailAddress) = keys %$ems;
    return $emailAddress;
  }
}
######################################################################

=begin addPostalAddress

Arguments:

=over

=item $id

   Valid supporter id number currently in the database.  die() will occur if
   the id number is not in the database already as a supporter id.

=item $formattedPostalAddress

   Scalar string that contains a multi-line, fully formatted, postal address.

=item $addressType

  Scalar string that contains the address type.  This type will be created in
  the database if it does not already exist, so be careful.

=back

Returns the id value of the postal_address table entry.

=cut

sub addPostalAddress($$$$) {
  my($self, $id, $formattedPostalAddress, $addressType) = @_;

  die "addPostalAddress: invalid id, $id" unless $self->_verifyId($id);
  die "addPostalAddress: the formatted postal address must be defined"
    unless defined $formattedPostalAddress;

  $self->_beginWork();

  my $addressTypeId;
  eval {
    $addressTypeId = $self->addAddressType($addressType);
  };
  if ($@ or not defined $addressTypeId) {
    my $err = $@;
    $err = "addPostalAddress: unable to addAddressType"  if (not defined $err);
    $self->_rollback();
    die $@ if $@;
  }
  my $sth = $self->dbh->prepare("INSERT INTO postal_address(formatted_address, type_id, date_encountered)" .
                                "VALUES(                    ?,             ?,       date('now'))");

  $sth->execute($formattedPostalAddress, $addressTypeId);
  my $addressId = $self->dbh->last_insert_id("","","","");
  $sth->finish();

  $sth = $self->dbh->prepare("INSERT INTO supporter_postal_address_mapping" .
                                      "(supporter_id, postal_address_id) " .
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

  if (not defined $requestType) {
    $self->_rollback();
    die "addRequestConfigurations: unable to create request configurations";
  }

  my %descriptions;
  my $sth = $self->dbh->prepare("INSERT INTO request_configuration(request_type_id, description) " .
                                                           "VALUES(?,               ?)");
  foreach my $description (@{$descriptionListRef}) {
    if (defined $descriptions{$description}) {
      $self->_rollback();
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

=begin getRequest

Arguments:

=over

=item $supporterId

   Valid supporter_id number currently in the database.  die() will occur if
   the id number is not in the database already as a supporter id.

=item $requestType

   String for the requestType sought.

=item $ignoreFulfilledRequests

   Optional boolean argument.  If true, a request that is found will not be
   returned if the request has already been fulfilled.  In other words, it
   forces a return of undef for

=back

Returns:

=over

=item undef

      if the C<$requestType> is not found for C<$supporterId> (or, as above,
      the C<$requestType> is found but has been fufilled and
      C<$ignoreFulfilledRequests>.

=item a hash reference

      If found, the has reference will contain at least the following keys:

=over

=item requestType

      Should match the request type in C<$requestType>

=item requestTypeId

      The id from the request_type entry for C<$requestType>

=item requestDate

      The date the request was made, in ISO 8601 format.

=back


Optionally, if these values are not null in the database record, the
following fields may also be included:

=over


=item  notes

       Notes made for the request.

=item  requestConfiguration

       any rquest configuration option given with the request.

=back

If the request has been fufilled, the following keys will also ahve values.

=over

=item fulfillDate

      The date the request was fufilled, in ISO 8601 format.

=back

=back

=cut

sub getRequest($$;$) {
  my($self, $supporterId, $requestType, $ignoreFulfilledRequests) = @_;

  die "getRequest: undefined supporterId" unless defined $supporterId;
  die "getRequest: supporterId, \"$supporterId\" not found in supporter database"
    unless $self->_verifyId($supporterId);

  die "getRequest: undefined requestType" unless defined $requestType;

  my $req = $self->dbh()->selectall_hashref("SELECT r.id, r.request_type_id, r.request_configuration_id, r.date_requested, r.notes, rt.type " .
                                            "FROM request r, request_type rt WHERE r.request_type_id = rt.id AND " .
                                            "r.supporter_id = " . $self->dbh->quote($supporterId, 'SQL_INTEGER') .
                                            " AND rt.type = " . $self->dbh->quote($requestType),
                                            'type');
  return undef unless (defined $req and defined $req->{$requestType} and defined $req->{$requestType}{'id'});
  my $requestTypeId = $req->{$requestType}{'request_type_id'};
  my $requestId = $req->{$requestType}{'id'};

  my $rsp = {  requestType   => $requestType,
               requestTypeId => $requestTypeId,
               requestId     => $req->{$requestType}{'id'},
               requestDate   => $req->{$requestType}{'date_requested'},
               notes         => $req->{$requestType}{'notes'},
            };
  my $configs = $self->getRequestConfigurations($requestType);
  my $configName;
  foreach my $key (keys %{$configs->{$requestTypeId}}) {
    if ($configs->{$requestTypeId}{$key} == $req->{$requestType}{'request_configuration_id'}) { $configName = $key; last; }
  }
  die("getRequest: discovered database integrity error: request_configuration, \"$req->{$requestType}{request_configuration_id} is " .
      "not valid for requestId, \"$requestId\"") unless defined $configName or (keys %{$configs->{$requestId}} == 0);
  $rsp->{requestConfiguration} = $configName;

  my $fulfillReq = $self->dbh()->selectall_hashref("SELECT id, request_id, date FROM fulfillment WHERE request_id = " .
                                                   $self->dbh->quote($requestId, 'SQL_INTEGER'),
                                                   'request_id');
  if (defined $fulfillReq and defined $fulfillReq->{$requestId} and defined $fulfillReq->{$requestId}{id}) {
    return undef if $ignoreFulfilledRequests;
    $rsp->{fulfillDate} = $fulfillReq->{$requestId}{date};
  }
  return $rsp;
}
######################################################################

=begin addRequest

Arguments:

=over

=item $parmas

A hash reference, the following keys are considered:

=over

=item supporterId

   Valid supporter_id number currently in the database.  die() will occur if
   the id number is not in the database already as a supporter id.

=item requestTypeId

   Numeric id of a request_type entry.  This must be a valid id in the
   request_type table, otherwise the method  L<die>()s.

   requestType is ignored if this parameter is set.

=item requestType

   If requestTypeId is not given, requestType will be used.  The type is
   added to the request_type table if it is not present, so be careful.


=item requestConfigurationId

   Numeric id of a request_configuration entry.  This must be a valid id in
   the request_configuration table, otherwise the method L<die>()s.

=item requestConfiguration

   If requestConfigurationId is not given, requestConfiguration will be used.
   This configuration will be added to the request_configuration table if it
   is not present, so be careful.

=back

=back

Returns the id value of the request entry.

=cut

sub addRequest($$) {
  my($self, $params) = @_;
  die "addRequest: undefined supporterId" unless defined $params->{supporterId};
  my $supporterId = $params->{supporterId};
  die "addRequest: supporterId, \"$supporterId\" not found in supporter database"
    unless $self->_verifyId($supporterId);

  $self->_beginWork;
  $self->_getOrCreateRequestType($params);
  $self->_getOrCreateRequestConfiguration($params) if (defined $params->{requestConfiguration} or
                                                       defined $params->{requestConfigurationId});

  # After those two calls above, I know I have requestTypeId and
  # requestConfigurationId are accurate.  Note that
  # $params->{requestConfigurationId} can be undef, which is permitted in the
  # database schema.



  my $sth = $self->dbh->prepare("INSERT INTO request(supporter_id, request_type_id, request_configuration_id, notes, date_requested) " .
                                             "VALUES(?,            ?,               ?,                        ?,      date('now'))");
  $sth->execute($supporterId, $params->{requestTypeId}, $params->{requestConfigurationId}, $params->{notes});
  my $id = $self->dbh->last_insert_id("","","","");
  $self->_commit;
  return $id;
}
######################################################################

=begin fulfillRequest

Arguments:

=over

=item $parmas

A hash reference, the following keys are considered:

=over

=item supporterId

   Valid supporter_id number currently in the database.  die() will occur if
   the id number is not in the database already as a supporter id.

=item requestType

   requestType of the request to be fulfilled.  die() will occur if this is
   undefined.  undef is returned if there is no unfulfilled request of
   requestType in the database for supporter identified by
   C<$params->{supporterId}>

=item who

   A scalar string representing the person that fulfilled the request.  die()
   will occur if C<$params->{who}> is not defined.

=item how

   A scalar string describing how the request was fulfilled.  It can safely be
   undefined.

=back

=back

Returns the id value of the fulfillment entry.

=cut

sub fulfillRequest($$) {
  my($self, $params) = @_;
  die "fulfillRequest: undefined supporterId" unless defined $params->{supporterId};
  my $supporterId = $params->{supporterId};
  die "fulfillRequest: supporterId, \"$supporterId\" not found in supporter database"
    unless $self->_verifyId($supporterId);
  die "fulfillRequest: undefined who" unless defined $params->{who};
  die "fulfillRequest: undefined requestType" unless defined $params->{requestType};

  my $req = $self->getRequest($supporterId, $params->{requestType});
  return undef if not defined $req;
  my $requestId = $req->{requestId};
  return undef if not defined $requestId;

  my $fulfillLookupSql = "SELECT id, request_id FROM fulfillment WHERE request_id = " .
                        $self->dbh->quote($requestId, 'SQL_INTEGER');

  my $fulfillRecord = $self->dbh()->selectall_hashref($fulfillLookupSql, "request_id");
  if (not defined $fulfillRecord or not defined $fulfillRecord->{$requestId}) {
    $self->_beginWork;
    my $sth = $self->dbh->prepare("INSERT INTO fulfillment(request_id, who, how, date) " .
                                                   "VALUES(?         , ?  , ?  , date('now'))");

    $sth->execute($requestId, $params->{who}, $params->{how});
    $sth->finish;
    $self->_commit;
    $fulfillRecord = $self->dbh()->selectall_hashref($fulfillLookupSql, "request_id");
  }
  return $fulfillRecord->{$requestId}{id};
}
######################################################################

=back

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

  my $val = $self->dbh()->selectall_hashref("SELECT id FROM supporter WHERE id = " .
                                            $self->dbh->quote($id, 'SQL_INTEGER'), 'id');
  return (defined $val and defined $val->{$id});

}

=item _verifyRequestTypeId()

Parameters:

=over

=item $self: current object.

=item $requestTypeId: A scalar numeric argument that is the request type id to  lookup


=back

Returns: scalar boolean, which is true iff. the $requestTypeId is valid and
already in the supporter database's request_type table.


=cut


sub _verifyRequestTypeId($$) {
  my($self, $requestTypeId) = @_;

  die "_verifyRequestTypeId() called with a non-numeric id" unless defined $requestTypeId and looks_like_number($requestTypeId);

  my $val = $self->dbh()->selectall_hashref("SELECT id FROM request_type WHERE id = " .
                                            $self->dbh->quote($requestTypeId, 'SQL_INTEGER'), 'id');
  return (defined $val and defined $val->{$requestTypeId});

}

=item _getOrCreateRequestType

Arguments:

=over

=item $params (hash reference)

This hash reference usually contains other paramaters, too, but this method
looks only at the keys C<requestType> and C<requestTypeId>.  If
C<requestTypeId> is set, it simply deletes the C<requestType> parameter and
verifies c<reuqestTypeId> is in the request_type table.

=cut

sub _getOrCreateRequestType($$) {
  my($self, $params) = @_;

  if (not defined $params->{requestTypeId}) {
    $params->{requestTypeId} = $self->addRequestType($params->{requestType});
  } else {
    my $id = $params->{requestTypeId};
    die "_getOrCreateRequestType(): called with a non-numeric requestTypeId"
      unless defined $id and looks_like_number($id);

    my $val = $self->dbh()->selectall_hashref("SELECT id FROM request_type WHERE id = " .
                                              $self->dbh->quote($id, 'SQL_INTEGER'), 'id');

    die "_getOrCreateRequestType(): given requestTypeId, $id, is invalid"
      unless (defined $val and defined $val->{$id});
  }
  delete $params->{requestType};
}

=item _getOrCreateRequestConfiguration

Arguments:

=over

=item $params (hash reference)

This hash reference usually contains other paramaters, too, but this method
looks only at the keys C<requestTypeId>, C<requestConfiguration> and
C<requestConfigurationId>.  If C<requestConfigurationId> is set, it simply
deletes the C<requestConfiguration> parameter and verifies c<reuqestTypeId>
is in the request_type table.

=cut

sub _getOrCreateRequestConfiguration($$) {
  my($self, $params) = @_;

  die "_getOrCreateRequestConfiguration: requestTypeId is required" unless defined $params->{requestTypeId};
  my $requestTypeId = $params->{requestTypeId};
  die "_getOrCreateRequestConfiguration: requestTypeId must be a number" unless looks_like_number($requestTypeId);

  my $val = $self->dbh()->selectall_hashref("SELECT id, type FROM request_type WHERE id = " .
                                            $self->dbh->quote($requestTypeId, 'SQL_INTEGER'), 'id');
  die "_getOrCreateRequestConfiguration: unknown requestTypeId, \"$requestTypeId\""
    unless (defined $val and defined $val->{$requestTypeId} and defined $val->{$requestTypeId}{type});
  my $requestType =  $val->{$requestTypeId}{type};

  my $existingRequestConfig =  $self->getRequestConfigurations($requestType);

  die "_getOrCreateRequestConfiguration: requestTypeId is unknown" unless (keys(%$existingRequestConfig) == 1);

  if (not defined $params->{requestConfigurationId}) {
    die "_getOrCreateRequestConfiguration: requestConfiguration is not defined" unless defined $params->{requestConfiguration};
    if (defined $existingRequestConfig->{$requestTypeId}{$params->{requestConfiguration}}) {
      $params->{requestConfigurationId} = $existingRequestConfig->{$requestTypeId}{$params->{requestConfiguration}};
    } else {
      $existingRequestConfig = $self->addRequestConfigurations($requestType, [ $params->{requestConfiguration} ]);
      $params->{requestConfigurationId} = $existingRequestConfig->{$requestTypeId}{$params->{requestConfiguration}};
    }
  } else {
    my $id = $params->{requestConfigurationId};
    die "_getOrCreateRequestConfiguration(): called with a non-numeric requestConfigurationId, \"$id\""
      unless defined $id and looks_like_number($id);
    my $found = 0;
    foreach my $foundId (values %{$existingRequestConfig->{$requestTypeId}}) { if ($foundId == $id) { $found = 1; last; } }
    die "_getOrCreateRequestType(): given requestConfigurationId, \"$id\", is invalid"
       unless defined $found;
  }
  delete $params->{requestConfiguration};
  return $params->{requestConfigurationId};
}

=item _beginWork()

Parameters:

=over

=item $self: current object.

=back

Returns: None.

This method is a reference counter to keep track of nested begin_work()/commit().


=cut

sub _beginWork($) {
  my($self) = @_;

  if ($self->{__NESTED_TRANSACTION_COUNTER__} < 0) {
    die "_beginWork: Mismatched begin_work/commit pair in API implementation";
    $self->{__NESTED_TRANSACTION_COUNTER__} = 0;
  }
  $self->dbh->begin_work() if ($self->{__NESTED_TRANSACTION_COUNTER__}++ == 0);
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

  if ($self->{__NESTED_TRANSACTION_COUNTER__} < 0) {
    die "_commit: Mismatched begin_work/commit pair in API implementation";
    $self->{__NESTED_TRANSACTION_COUNTER__} = 0;
  }
  $self->dbh->commit() if (--$self->{__NESTED_TRANSACTION_COUNTER__} == 0);
}

=item _rollback()

Parameters:

=over

=item $self: current object.

=back

Returns: None.

This method resets the reference counter entirely and calls $dbh->rollback.

=cut

sub _rollback($) {
  my($self) = @_;

  $self->{__NESTED_TRANSACTION_COUNTER__} = 0;
  $self->dbh->rollback();
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


  sub Supporter_FullLookupUsingId($$) {
  my($dbh, $id) = @_;

  my $sth = $dbh->prepare('SELECT m.supporter_id ' .
                          'FROM email_address e, supporter_email_address_mapping m  ' .
                          'WHERE e.email_address = ? and e.id = m.email_address_id');
  $sth->execute($email);
}
###############################################################################
sub Supporter_LookupByEmail($$) {
  my($dbh, $email) = @_;

  my $sth = $dbh->prepare('SELECT m.supporter_id ' .
                          'FROM email_address e, supporter_email_address_mapping m  ' .
                          'WHERE e.email_address = ? and e.id = m.email_address_id');
  $sth->execute($email);
  my $supporter = $sth->fetchrow_hashref();

  if (defined $supporter) {
    return Supporter_FullLookupUsingId($dbh, $supporter->{'m.supporter_id'});
  } else {
    return undef;
  }

  
