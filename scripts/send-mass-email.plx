#!/usr/bin/perl

use strict;
use warnings;

use autodie qw(open close);
use DBI;
use Encode qw(encode decode);

use Date::Manip::DM5;
use Supporters;

my $TODAY = UnixDate(ParseDate("today"), '%Y-%m-%d');

if (@ARGV < 5) {
  print STDERR "usage: $0 <SUPPORTERS_SQLITE_DB_FILE> <FROM_ADDRESS> <EMAIL_CONTENTS_FILE> <MONTHLY_SEARCH_REGEX> <ANNUAL_SEARCH_REGEX>  <VERBOSE> <LEDGER_CMD_LINE> <LEDGER_COMMAND_LINE>\n";
  exit 1;
}

my($SUPPORTERS_SQLITE_DB_FILE, $FROM_ADDDRESS, $EMAIL_CONTENTS_FILE, $MONTHLY_SEARCH_REGEX, $ANNUAL_SEARCH_REGEX, $VERBOSE,
   @LEDGER_CMD_LINE) = @ARGV;
$VERBOSE = 0 if not defined $VERBOSE;

my $dbh = DBI->connect("dbi:SQLite:dbname=$SUPPORTERS_SQLITE_DB_FILE", "", "",
                               { RaiseError => 1, sqlite_unicode => 1 })
  or die $DBI::errstr;

my $sp = new Supporters($dbh, \@LEDGER_CMD_LINE, { monthly => $MONTHLY_SEARCH_REGEX, annual => $ANNUAL_SEARCH_REGEX});

open(EMAIL, "<", $EMAIL_CONTENTS_FILE);
my(@emailLines) = <EMAIL>;
close EMAIL;

my(@supporterIds) = $sp->findDonor({});
foreach my $id (@supporterIds) {
  my $expiresOn = $sp->supporterExpirationDate($id);
  my $isLapsed = ( (not defined $expiresOn) or $expiresOn lt $TODAY);
  #  next if $isLapsed;

  next unless $sp->emailOk($id);
  my @emails;
  my $preferredEmail = $sp->getPreferredEmailAddress($id);
  if (defined $preferredEmail) {
    push(@emails, $preferredEmail);
  } else {
    (@emails) = $sp->getEmailAddresses($id);
  }
  my $fullEmailLine = "";
  my $emailTo = join(' ', @emails);
  my $displayName = $sp->getDisplayName($supporterId);
  foreach my $email (@emails) {
    $fullEmailLine .= ", " if ($fullEmailLine ne "");
    my $line = "";
    if (defined $displayName) {
      $line .= "\"$displayName\" ";
    }
    $line .= "<$email>";
    $fullEmailLine .= Encode::encode("MIME-Header", $line);
  }
  open(SENDMAIL, "|-", "/usr/lib/sendmail -f \"$FROM_ADDDRESS\" -oi -oem -- \'$emailTo\'");


  print SENDMAIL "To: $fullEmailLine\n";
  print SENDMAIL @emailLines;
  close SENDMAIL;

  print STDERR "Emailed $emailTo with $id who expires on $expiresOn\n" if ($VERBOSE);
}
###############################################################################
#
# Local variables:
# compile-command: "perl -c send-mass-email.plx"
# End:

