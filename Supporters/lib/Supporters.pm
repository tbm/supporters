# License: AGPLv3-or-later
#  Copyright info in COPYRIGHT.md, License details in LICENSE.md with this package.
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

use Scalar::Util qw(looks_like_number blessed reftype);
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

   A list reference that contains the main ledger command with any necessary
   arguments, for looking up donation data.  The options should be presented
   such that the output is in the form:
         ProgramTag  Date   Entity   Amount

=item $programTypeSearch

   This hash should have two keys: "monthly" and "annual".  The values of the
   hash should be a regular expression that matches the ProgramTag lines for
   categorization of the donations in annual or monthly buckets.


=back

=cut

sub new ($$;$) {
  my $package = shift;
  my($dbh, $ledgerCmd, $programTypeSearch) = @_;

  die "new: second argument must be a list ref for the ledger command line"
    unless (defined $ledgerCmd and ref $ledgerCmd and (reftype($ledgerCmd) eq 'ARRAY'));

  die "new: keys annual and monthly must be the only keys in this hash"
      if defined $programTypeSearch and (not (defined $programTypeSearch->{monthly} and defined $programTypeSearch->{annual}
      and scalar(keys(%$programTypeSearch) == 2)));

  die "new: first argument must be a database handle"
    unless (defined $dbh and blessed($dbh) =~ /DBI/);

  my $self = bless({ dbh => $dbh, ledgerCmd => $ledgerCmd },
                   $package);

  $self->{programTypeSearch} = $programTypeSearch if defined $programTypeSearch;

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

  if ($sp->{public_ack}) {
    die "display_name required if public_ack requested" unless defined $sp->{display_name};
  }
  $self->_beginWork;
  my $sth = $self->dbh->prepare(
                      "INSERT INTO     donor(ledger_entity_id, display_name, public_ack, is_supporter)" .
                                    " values(?,                ?,            ?, " .
                                    $self->dbh->quote(1, 'SQL_BOOLEAN') . ')');

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

  my $existingEmail = $self->_lookupEmailAddress($emailAddress);

  if (defined $existingEmail) {
    die "addEmailAddress: attempt to add email address that exists, using a different type!"
      if $existingEmail->{type} ne $emailAddressType;

    my $val = $self->dbh()->selectall_hashref("SELECT email_address_id, donor_id " .
                                              "FROM donor_email_address_mapping WHERE " .
                                              "donor_id = " . $self->dbh->quote($id, 'SQL_INTEGER') . " AND " .
                                              "email_address_id = " . $self->dbh->quote($existingEmail->{id}, 'SQL_INTEGER'),
                                              'donor_id');
    return $val->{$id}{email_address_id}
      if (defined $val and defined $val->{$id} and defined $val->{$id}{email_address_id});
  }
  my($sth, $addressId);

  $self->_beginWork();

  if (defined $existingEmail) {
    $addressId = $existingEmail->{id};
  } else {
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
    $sth = $self->dbh->prepare("INSERT INTO email_address(email_address, type_id, date_encountered)" .
                                  "VALUES(                    ?,            ?,       date('now'))");

    $sth->execute($emailAddress, $addressTypeId);
    $addressId = $self->dbh->last_insert_id("","","","");
    $sth->finish();
  }
  $sth = $self->dbh->prepare("INSERT INTO donor_email_address_mapping" .
                             "(donor_id, email_address_id) " .
                             "VALUES(       ?, ?)");
  $sth->execute($id, $addressId);
  $sth->finish();

  $self->_commit();

  return $addressId;
}
######################################################################

=begin setPreferredEmailAddress

Arguments:

=over

=item $donorId

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
  my($self, $donorId, $emailAddress) = @_;

  die "setPreferredEmailAddress: invalid supporter id, $donorId" unless $self->_verifyId($donorId);
  die "setPreferredEmailAddress: email address not defined" unless defined $emailAddress;
  die "setPreferredEmailAddress: invalid email address, $emailAddress"
    unless Mail::RFC822::Address::valid($emailAddress);

  my $ems = $self->dbh()->selectall_hashref("SELECT ea.email_address, ea.id, sem.preferred " .
                                            "FROM email_address ea, donor_email_address_mapping sem " .
                                            "WHERE ea.id = sem.email_address_id AND ".
                                            "sem.donor_id = " . $self->dbh->quote($donorId, 'SQL_INTEGER'),
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
    $self->dbh->do("UPDATE donor_email_address_mapping " .
                     "SET preferred = " . $self->dbh->quote(0, 'SQL_BOOLEAN') . " " .
                     "WHERE donor_id = " . $self->dbh->quote($donorId, 'SQL_INTEGER'));
  }
  $self->dbh->do("UPDATE donor_email_address_mapping " .
                 "SET preferred = " . $self->dbh->quote(1, 'SQL_BOOLEAN') . " " .
                 "WHERE email_address_id = " . $self->dbh->quote($emailAddressId, 'SQL_INTEGER'));
  $self->_commit;
  return $emailAddressId;
}
######################################################################

=begin getPreferredEmailAddress

Arguments:

=over

=item $donorId

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
  my($self, $donorId) = @_;

  die "setPreferredEmailAddress: invalid supporter id, $donorId" unless $self->_verifyId($donorId);

  my $ems = $self->dbh()->selectall_hashref("SELECT email_address FROM email_address em, donor_email_address_mapping sem " .
                                            "WHERE preferred AND sem.email_address_id = em.id AND " .
                                            "sem.donor_id = " . $self->dbh->quote($donorId, 'SQL_INTEGER'),
                                            'email_address');
  my $rowCount = scalar keys %{$ems};
  die "setPreferredEmailAddress: DATABASE INTEGRITY ERROR: more than one email address is preferred for supporter, \"$donorId\""
    if $rowCount > 1;

  if ($rowCount != 1) {
    return undef;
  } else {
    my ($emailAddress) = keys %$ems;
    return $emailAddress;
  }
}
######################################################################
sub _getDonorField($$$) {
  my($self, $field, $donorId) = @_;

  die "get$field: invalid supporter id, $donorId" unless $self->_verifyId($donorId);

  my $results = $self->dbh()->selectall_hashref("SELECT id, $field FROM donor WHERE id = " .
                                                $self->dbh->quote($donorId, 'SQL_INTEGER'),
                                                'id');
  my $rowCount = scalar keys %{$results};
  die "get$field: DATABASE INTEGRITY ERROR: more than one row found when looking up supporter, \"$donorId\""
    if $rowCount > 1;

  if ($rowCount == 1) {
    my ($val) = $results->{$donorId}{$field};
    return $val;
  } else {
    die "get$field: DATABASE INTEGRITY ERROR: $donorId was valid but non-1 row count returned";
  }
}
######################################################################

=begin getLedgerEntityId

Arguments:

=over

=item $donorId

   Valid donor id number currently in the database.  die() will occur if
   the id number is not in the database already as a donor id.

=back

Returns the ledger_entity_id of the donor.  Since the method die()s for an
invalid donor id, undef should never be returned and callers need not test
for it.

=cut

sub getLedgerEntityId ($$) {
  return $_[0]->_getDonorField("ledger_entity_id", $_[1]);
}
######################################################################

=begin getPublicAck

Arguments:

=over

=item $donorId

   Valid donor id number currently in the database.  die() will occur if
   the id number is not in the database already as a donor id.

=back

Returns the a boolean indicating whether or not the donor seeks to be
publicly acknowledged.  undef can be returned if the donor has not specified,
so callers must check for undef.

=cut

sub getPublicAck($$$) {
  return $_[0]->_getDonorField("public_ack", $_[1]);
}
######################################################################

=begin isSupporter

Arguments:

=over

=item $donorId

   Valid donor id number currently in the database.  die() will occur if
   the id number is not in the database already as a donor id.

=back

Returns the a boolean indicating whether or not the donor is a Supporter (as
opposed to an ordinary donor).  undef will not be returned


=cut

sub isSupporter($$$) {
  return $_[0]->_getDonorField("is_supporter", $_[1]);
}
######################################################################

=begin getDisplayName

Arguments:

=over

=item $donorId

   Valid donor id number currently in the database.  die() will occur if
   the id number is not in the database already as a donor id.

=back

Returns the string of the display name for the donor.  undef can be returned
if the donor has not specified, so callers must check for undef.

=cut

sub getDisplayName($$$) {
  return $_[0]->_getDonorField("display_name", $_[1]);
}
######################################################################
sub _setDonorField($$$) {
  my($self, $field, $donorId, $value, $type) = @_;

  die "set$field: invalid supporter id, $donorId" unless $self->_verifyId($donorId);

  $self->_beginWork();
  $self->dbh->do("UPDATE donor " .
                     "SET $field = " . $self->dbh->quote($value, $type) . " " .
                     "WHERE id = " . $self->dbh->quote($donorId, 'SQL_INTEGER'));
  $self->_commit;
  return $value;
}
######################################################################

=begin setPublicAck

Arguments:

=over

=item $donorId

   Valid donor id number currently in the database.  die() will occur if
   the id number is not in the database already as a donor id.

=item $publicAck

   Can be true, false, or undef and will update public acknowledgement bit
   accordingly for donor identified with C<$donorId>.

=back

=cut

sub setPublicAck($$$) {
  return $_[0]->_setDonorField('public_ack', $_[1], $_[2], 'SQL_BOOLEAN');
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

  $sth = $self->dbh->prepare("INSERT INTO donor_postal_address_mapping" .
                                      "(donor_id, postal_address_id) " .
                                "VALUES(       ?, ?)");
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

=item $parmas

A hash reference, the following keys are considered:

=over

=item donorId

   Valid donor_id number currently in the database.  die() will occur if
   the id number is not in the database already as a supporter id.

=item requestTypeId

   Numeric id of a request_type entry.  This must be a valid id in the
   request_type table, otherwise the method  L<die>()s.

   requestType is ignored if this parameter is set.

=item requestType

   If requestTypeId is not given, requestType will be used.  The type is
   added to the request_type table if it is not present, so be careful.

=item ignoreFulfilledRequests

   Optional boolean argument.  If true, a request that is found will not be
   returned if the request has already been fulfilled.  In other words, it
   forces a return of undef for

=back

=back

Returns:

=over

=item undef

      if the C<$requestType> is not found for C<$donorId> (or, as above,
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
  my($self, $params) = @_;
  my($donorId, $requestType, $requestTypeId, $ignoreFulfilledRequests) =
    ($params->{donorId}, $params->{requestType}, $params->{requestTypeId}, $params->{ignoreFulfilledRequests});

  die "getRequest: undefined donorId" unless defined $donorId;
  die "getRequest: donorId, \"$donorId\" not found in supporter database"
    unless $self->_verifyId($donorId);

  my $requestTypeClause = "";
  if (defined $requestTypeId) {
    $requestType = $self->_lookupRequestTypeById($requestTypeId);
    die "getRequest: invalid requestTypeId, \"$requestTypeId\"" unless defined $requestType;
    $requestTypeClause = " AND rt.id = " . $self->dbh->quote($requestTypeId, 'SQL_INTEGER');
  } elsif (defined $requestType) {
    $requestTypeClause = " AND rt.type = " . $self->dbh->quote($requestType);
  } else {
    die "getRequest: undefined requestType" unless defined $requestType;
  }
  my $req = $self->dbh()->selectall_hashref("SELECT r.id, r.request_type_id, r.request_configuration_id, r.date_requested, r.notes, rt.type " .
                                            "FROM request r, request_type rt WHERE r.request_type_id = rt.id AND " .
                                            "r.donor_id = " . $self->dbh->quote($donorId, 'SQL_INTEGER') .
                                            $requestTypeClause,
                                            'type');
  if (defined $requestTypeId) {
    die "getRequest: given requestTypeId, \"$requestTypeId\" was not the one found in the database $req->{$requestType}{'request_type_id'}"
      unless $req->{$requestType}{'request_type_id'} == $requestTypeId;
  } else {
    $requestTypeId = $req->{$requestType}{'request_type_id'};
  }
  return undef unless (defined $req and defined $req->{$requestType} and defined $req->{$requestType}{'id'});

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

=item donorId

   Valid donor_id number currently in the database.  die() will occur if
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
  die "addRequest: undefined donorId" unless defined $params->{donorId};
  my $donorId = $params->{donorId};
  die "addRequest: donorId, \"$donorId\" not found in supporter database"
    unless $self->_verifyId($donorId);

  $self->_beginWork;
  eval {
    $self->_getOrCreateRequestType($params);
    $self->_getOrCreateRequestConfiguration($params) if (defined $params->{requestConfiguration} or
                                                        defined $params->{requestConfigurationId});
  };
  if ($@ or not defined $params->{requestTypeId}) {
    my $err = $@;
    $err = "addRequest: unable to create requestType"  if (not defined $err);
    $self->_rollback();
    die $@ if $@;
  }

  # After those two calls above, I know I have requestTypeId and
  # requestConfigurationId are accurate.  Note that
  # $params->{requestConfigurationId} can be undef, which is permitted in the
  # database schema.

  my $sth = $self->dbh->prepare("INSERT INTO request(donor_id, request_type_id, request_configuration_id, notes, date_requested) " .
                                             "VALUES(?,            ?,               ?,                        ?,      date('now'))");
  $sth->execute($donorId, $params->{requestTypeId}, $params->{requestConfigurationId}, $params->{notes});
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

=item donorId

   Valid donor_id number currently in the database.  die() will occur if
   the id number is not in the database already as a supporter id.

=item requestType

   requestType of the request to be fulfilled.  die() will occur if this is
   undefined.  undef is returned if there is no unfulfilled request of
   requestType in the database for supporter identified by
   C<$params->{donorId}>

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
  die "fulfillRequest: undefined donorId" unless defined $params->{donorId};
  my $donorId = $params->{donorId};
  die "fulfillRequest: donorId, \"$donorId\" not found in supporter database"
    unless $self->_verifyId($donorId);
  die "fulfillRequest: undefined who" unless defined $params->{who};
  die "fulfillRequest: both requestType and requestTypeId undefined"
    unless defined $params->{requestType} or defined $params->{requestTypeId};

  my $req = $self->getRequest($params);
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

=begin findDonor

Arguments:

=over

=item $parmas

A hash reference, the following keys are considered, and are "anded" together
-- in that the donor sought must have all these criteria to be found.

=over

=item emailAddress

   A string containing an email_address from email_address table.

=item ledgerEntityId

   A string containing a ledger_entity_id from the donor table.
   undefined.  undef is returned if there is no unfulfilled request of
   requestType in the database for supporter identified by
   C<$params->{donorId}>

=back

=back

Returns a list of donorIds that meets the criteria, or none if not found.

=cut

sub findDonor($$) {
  my($self, $params) = @_;
  die "findDonor: no search criteria given"
    unless defined $params->{ledgerEntityId} or defined $params->{emailAddress};

  my @donorIds;
  if (not defined $params->{emailAddress}) {
    my $ledgerEntityId = $params->{ledgerEntityId};
    # Simple case: just lookup without a join.
    my $val = $self->dbh()->selectall_hashref("SELECT id, ledger_entity_id from donor where ledger_entity_id = " .
                                              $self->dbh->quote($ledgerEntityId),
                                              "ledger_entity_id");
    # As Connor MacLeod said,  "There can be only one!"
    #  (because of  "ledger_entity_id" varchar(300) NOT NULL UNIQUE,)
    push(@donorIds, $val->{$ledgerEntityId}{id})
      if (defined $val and defined $val->{$ledgerEntityId} and defined $val->{$ledgerEntityId}{id});
  } else {
    my $sql = "SELECT d.id from donor d, email_address ea, donor_email_address_mapping eam " .
              "WHERE eam.email_address_id = ea.id AND d.id = eam.donor_id AND " .
              "ea.email_address = " . $self->dbh->quote($params->{emailAddress});

    $sql .= " AND d.ledger_entity_id = " . $self->dbh->quote($params->{ledgerEntityId})
      if (defined $params->{ledgerEntityId});

    my $val = $self->dbh()->selectall_hashref($sql, 'id');
    push(@donorIds, keys %{$val}) if (defined $val);
  }
  return(@donorIds);
}
######################################################################

=back

=head1 Non-Public Methods

These methods are part of the internal implementation are not recommended for
use outside of this module.

=over

=item DESTROY

=cut

sub DESTROY {
  my $self = shift;
  return unless defined $self;

  # Force rollback if we somehow get destroy'ed while counter is up
  if (defined $self->{__NESTED_TRANSACTION_COUNTER__} and $self->{__NESTED_TRANSACTION_COUNTER__} > 0) {
    my $errorStr = "SUPPORTERS DATABASE ERROR: Mismatched begin_work/commit pair in API implementation";
    if (not defined $self->{dbh}) {
      $errorStr .= "... and unable to rollback or commit work.  Database may very well be inconsistent!";
    } else {
      # Rollback if we didn't call commit enough;  commit if we called commit too often.
      ($self->{__NESTED_TRANSACTION_COUNTER__} > 0) ? $self->_rollback() : $self->_commit();
      $self->{dbh}->disconnect();
    }
    $self->{__NESTED_TRANSACTION_COUNTER__} = 0;
    die $errorStr;
  }
  delete $self->{__NESTED_TRANSACTION_COUNTER__};
  $self->{dbh}->disconnect() if defined $self->{dbh} and blessed($self->{dbh}) =~ /DBI/;
}


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

  confess "_verifyId(): called with a non-numeric id" unless defined $id and looks_like_number($id);

  my $val = $self->dbh()->selectall_hashref("SELECT id FROM donor WHERE id = " .
                                            $self->dbh->quote($id, 'SQL_INTEGER'), 'id');
  return (defined $val and defined $val->{$id});

}

=item _lookupRequestTypeById()

Parameters:

=over

=item $self: current object.

=item $requestTypeId: A scalar numeric argument that is the request type id to  lookup


=back

Returns: scalar, which is the request_type found iff. the C<$requestTypeId> is valid and
already in the supporter database's request_type table.

Die if the C<$requestTypeId> isn't a number.

=cut


sub _lookupRequestTypeById($$) {
  my($self, $requestTypeId) = @_;

  die "_verifyRequestTypeId() called with a non-numeric id" unless defined $requestTypeId and looks_like_number($requestTypeId);

  my $val = $self->dbh()->selectall_hashref("SELECT id, type FROM request_type WHERE id = " .
                                            $self->dbh->quote($requestTypeId, 'SQL_INTEGER'), 'id');
  if (defined $val and defined $val->{$requestTypeId}) {
    return $val->{$requestTypeId}{type};
  } else {
    return undef;
  }
}
######################################################################

=item _lookupEmailAddress()

Parameters:

=over

=item $self: current object.

=item $emailAdress: A scalar string argument that is the email_adress


=back

Returns: undef if the email address is not found, otherwise a hash with the following values:

=over

=item emailAddress: The email address as given

=item id: The email_adress.id

=item type: The email_adress type

=item dateEncountered: The date_encountered of this email address.

=back

=cut


sub _lookupEmailAddress($$) {
  my($self, $emailAddress) = @_;

  die "_lookupEmailAddressId() called with undef" unless defined $emailAddress;

  my $val = $self->dbh()->selectall_hashref("SELECT ea.id, ea.email_address, at.name, ea.date_encountered " .
                                            "FROM email_address ea, address_type at " .
                                            "WHERE ea.type_id = at.id AND " .
                                            "email_address = " . $self->dbh->quote($emailAddress),
                                            'email_address');
  if (defined $val and defined $val->{$emailAddress}) {
    return { id => $val->{$emailAddress}{id}, emailAddress => $val->{$emailAddress}{email_address},
             type => $val->{$emailAddress}{name},  dateEncountered => $val->{$emailAddress}{date_encountered}};
  } else {
    return undef;
  }
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
    die "_getOrCreateRequestType(): invalid requestTypeId, \"$id\""
      unless defined $self->_lookupRequestTypeById($id);
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
